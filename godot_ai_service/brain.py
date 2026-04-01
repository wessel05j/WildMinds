from __future__ import annotations

import json
import re
import subprocess
import time
from dataclasses import dataclass
from typing import Any

import requests

from survival_sandbox_ai.hardware import HardwareProfile, ModelChoice, choose_ollama_model, detect_hardware


OLLAMA_URL = "http://127.0.0.1:11434"
MODEL_PULL_ATTEMPTS = 5
MODEL_PULL_RETRY_DELAY_SECONDS = 4.0
ALLOWED_ACTIONS = (
    "wander",
    "forage",
    "rest",
    "flee",
    "stalk",
    "attack",
    "guard",
    "sleep",
    "sit",
    "idle_watch",
    "sniff",
    "listen",
    "drink",
    "eat",
    "make_sound",
    "circle_target",
    "investigate_sound",
    "groom",
    "retch",
)
ALLOWED_POSTURES = ("stand", "low", "sit", "sleep", "crouch")
ALLOWED_LOCOMOTION = ("still", "slow_walk", "walk", "run", "circle")
ALLOWED_SOUNDS = ("none", "growl", "howl", "grunt", "snort", "whine", "bark", "squeal", "sniff", "huff", "retch")


class LocalModelRequiredError(RuntimeError):
    pass


class LocalDecisionError(RuntimeError):
    pass


_ANSI_ESCAPE_RE = re.compile(r"\x1B\[[0-?]*[ -/]*[@-~]")


@dataclass(slots=True)
class AIAction:
    action: str
    target: str = "none"
    reason: str = ""
    speech: str = ""
    posture: str = "stand"
    locomotion: str = "walk"
    sound: str = "none"
    duration_seconds: float = 2.2
    memory_note: str = ""

    def as_dict(self) -> dict[str, str | float]:
        return {
            "action": self.action,
            "target": self.target,
            "reason": self.reason,
            "speech": self.speech,
            "posture": self.posture,
            "locomotion": self.locomotion,
            "sound": self.sound,
            "duration_seconds": self.duration_seconds,
            "memory_note": self.memory_note,
        }


@dataclass(slots=True)
class BootstrapResult:
    hardware: HardwareProfile
    model_choice: ModelChoice
    ready: bool
    details: str


@dataclass(slots=True)
class CreatureState:
    identifier: str
    name: str
    species: str
    personality: str
    health: float
    max_health: float
    hunger: float
    thirst: float
    energy: float
    fear: float
    aggression: float
    comfort: float
    curiosity: float
    social_drive: float
    sickness: float
    alertness: float
    warmth: float
    decision: AIAction
    memory: tuple[str, ...]


def creature_from_payload(payload: dict[str, Any]) -> CreatureState:
    previous = payload.get("decision", {})
    return CreatureState(
        identifier=str(payload.get("id", "")),
        name=str(payload.get("name", "Unknown")),
        species=str(payload.get("species", "creature")),
        personality=str(payload.get("personality", "survival focused")),
        health=float(payload.get("health", 100.0)),
        max_health=float(payload.get("max_health", 100.0)),
        hunger=float(payload.get("hunger", 25.0)),
        thirst=float(payload.get("thirst", 18.0)),
        energy=float(payload.get("energy", 70.0)),
        fear=float(payload.get("fear", 10.0)),
        aggression=float(payload.get("aggression", 35.0)),
        comfort=float(payload.get("comfort", 55.0)),
        curiosity=float(payload.get("curiosity", 42.0)),
        social_drive=float(payload.get("social_drive", 40.0)),
        sickness=float(payload.get("sickness", 0.0)),
        alertness=float(payload.get("alertness", 60.0)),
        warmth=float(payload.get("warmth", 50.0)),
        decision=AIAction(
            action=str(previous.get("action", payload.get("last_action", "wander"))),
            target=str(previous.get("target", "none")),
            reason=str(previous.get("reason", "")),
            speech=str(previous.get("speech", "")),
            posture=str(previous.get("posture", "stand")),
            locomotion=str(previous.get("locomotion", "walk")),
            sound=str(previous.get("sound", "none")),
            duration_seconds=float(previous.get("duration_seconds", 2.2)),
            memory_note=str(previous.get("memory_note", "")),
        ),
        memory=tuple(str(item) for item in payload.get("memory", [])),
    )


def _clean_ollama_output(raw: bytes) -> str:
    text = raw.decode(errors="replace")
    text = _ANSI_ESCAPE_RE.sub("", text)
    text = text.replace("\r", "\n")
    cleaned_lines = [line.strip() for line in text.splitlines() if line.strip()]
    meaningful_lines = [
        line
        for line in cleaned_lines
        if not line.lower().startswith(
            (
                "pulling manifest",
                "verifying sha256 digest",
                "writing manifest",
                "removing any unused layers",
            )
        )
    ]
    return "\n".join(meaningful_lines or cleaned_lines[-1:])


class OllamaRuntime:
    def __init__(self, base_url: str = OLLAMA_URL, timeout: float = 20.0) -> None:
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout

    def ping(self) -> bool:
        try:
            response = requests.get(f"{self.base_url}/api/tags", timeout=2.0)
            return response.ok
        except requests.RequestException:
            return False

    def ensure_server(self) -> bool:
        if self.ping():
            return True

        creationflags = 0
        if hasattr(subprocess, "DETACHED_PROCESS"):
            creationflags |= subprocess.DETACHED_PROCESS
        if hasattr(subprocess, "CREATE_NEW_PROCESS_GROUP"):
            creationflags |= subprocess.CREATE_NEW_PROCESS_GROUP

        try:
            subprocess.Popen(
                ["ollama", "serve"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                creationflags=creationflags,
            )
        except FileNotFoundError:
            return False

        deadline = time.time() + 25.0
        while time.time() < deadline:
            if self.ping():
                return True
            time.sleep(0.5)
        return False

    def list_models(self) -> list[str]:
        response = requests.get(f"{self.base_url}/api/tags", timeout=self.timeout)
        response.raise_for_status()
        payload = response.json()
        return [entry["name"] for entry in payload.get("models", [])]

    def _pull_model_once(self, model_name: str) -> subprocess.CompletedProcess[bytes]:
        return subprocess.run(
            ["ollama", "pull", model_name],
            capture_output=True,
            check=False,
        )

    def ensure_model(self, model_name: str) -> bool:
        try:
            installed = set(self.list_models())
        except Exception as exc:  # pragma: no cover - defensive network path
            raise RuntimeError(f"Could not query installed Ollama models: {exc}") from exc

        if model_name in installed:
            return False

        last_error = ""
        for attempt in range(1, MODEL_PULL_ATTEMPTS + 1):
            try:
                completed = self._pull_model_once(model_name)
            except FileNotFoundError as exc:
                raise RuntimeError("Ollama is not installed or not on PATH.") from exc

            stderr_text = _clean_ollama_output(completed.stderr)
            stdout_text = _clean_ollama_output(completed.stdout)
            if completed.returncode == 0:
                try:
                    installed = set(self.list_models())
                except Exception as exc:  # pragma: no cover - defensive network path
                    last_error = f"Ollama reported a successful pull, but verification failed: {exc}"
                else:
                    if model_name in installed:
                        return True
                    last_error = (
                        f"Ollama reported a successful pull, but {model_name} was still not listed as installed."
                    )
            else:
                last_error = stderr_text or stdout_text or f"Could not pull {model_name}"

            if attempt < MODEL_PULL_ATTEMPTS:
                time.sleep(MODEL_PULL_RETRY_DELAY_SECONDS * attempt)

        raise RuntimeError(
            f"Could not pull {model_name} after {MODEL_PULL_ATTEMPTS} attempts. "
            f"Last error: {last_error}"
        )

    def chat(self, model_name: str, system_prompt: str, user_prompt: str) -> str:
        response = requests.post(
            f"{self.base_url}/api/chat",
            json={
                "model": model_name,
                "stream": False,
                "messages": [
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt},
                ],
                "options": {
                    "temperature": 0.35,
                    "num_predict": 96,
                },
            },
            timeout=self.timeout,
        )
        response.raise_for_status()
        payload = response.json()
        return payload["message"]["content"]


def bootstrap_local_model(runtime: OllamaRuntime | None = None) -> BootstrapResult:
    runtime = runtime or OllamaRuntime()
    hardware = detect_hardware()
    model_choice = choose_ollama_model(hardware)

    if not runtime.ensure_server():
        return BootstrapResult(
            hardware=hardware,
            model_choice=model_choice,
            ready=False,
            details=(
                "WildMinds requires a local Ollama runtime. "
                "Install Ollama, let it start, and relaunch the game."
            ),
        )

    try:
        installed_now = runtime.ensure_model(model_choice.model_name)
        install_note = (
            f"Installed missing local model {model_choice.model_name} automatically. "
            if installed_now
            else f"Using local model {model_choice.model_name}. "
        )
        return BootstrapResult(
            hardware=hardware,
            model_choice=model_choice,
            ready=True,
            details=f"{install_note}{model_choice.reasoning}",
        )
    except Exception as exc:
        return BootstrapResult(
            hardware=hardware,
            model_choice=model_choice,
            ready=False,
            details=f"WildMinds could not prepare the required Ollama model: {exc}",
        )


def ensure_local_model_ready(runtime: OllamaRuntime | None = None) -> BootstrapResult:
    result = bootstrap_local_model(runtime=runtime)
    if not result.ready:
        raise LocalModelRequiredError(result.details)
    return result


def _extract_json(raw: str) -> dict[str, Any]:
    raw = raw.strip()
    if raw.startswith("```"):
        lines = [line for line in raw.splitlines() if not line.startswith("```")]
        raw = "\n".join(lines).strip()

    start = raw.find("{")
    end = raw.rfind("}")
    if start == -1 or end == -1 or end <= start:
        raise ValueError("No JSON object found")
    return json.loads(raw[start : end + 1])


def _clamp_choice(raw_value: Any, allowed: tuple[str, ...], default: str) -> str:
    candidate = str(raw_value or default).strip().lower()
    return candidate if candidate in allowed else default


def _clamp_action(data: dict[str, Any]) -> AIAction:
    action = _clamp_choice(data.get("action"), ALLOWED_ACTIONS, "idle_watch")
    target = str(data.get("target", "none")).strip().lower() or "none"
    reason = str(data.get("reason", "")).strip()[:160]
    speech = str(data.get("speech", "")).strip()[:80]
    posture = _clamp_choice(data.get("posture"), ALLOWED_POSTURES, "stand")
    locomotion = _clamp_choice(data.get("locomotion"), ALLOWED_LOCOMOTION, "walk")
    sound = _clamp_choice(data.get("sound"), ALLOWED_SOUNDS, "none")
    memory_note = str(data.get("memory_note", "")).strip()[:100]
    try:
        duration_seconds = float(data.get("duration_seconds", 2.2))
    except (TypeError, ValueError):
        duration_seconds = 2.2
    duration_seconds = max(1.0, min(4.5, duration_seconds))
    return AIAction(
        action=action,
        target=target,
        reason=reason,
        speech=speech,
        posture=posture,
        locomotion=locomotion,
        sound=sound,
        duration_seconds=duration_seconds,
        memory_note=memory_note,
    )


class LocalCreatureMind:
    def __init__(self, model_name: str, runtime: OllamaRuntime | None = None) -> None:
        self.model_name = model_name
        self.runtime = runtime or OllamaRuntime()

    def decide(self, creature: CreatureState, snapshot: dict[str, Any]) -> AIAction:
        system_prompt = self._build_system_prompt(creature)
        user_prompt = self._build_user_prompt(creature, snapshot)
        try:
            raw = self.runtime.chat(self.model_name, system_prompt, user_prompt)
            return _clamp_action(_extract_json(raw))
        except Exception as exc:
            raise LocalDecisionError(f"Creature decision failed: {exc}") from exc

    def _build_system_prompt(self, creature: CreatureState) -> str:
        species_guidance = {
            "wolf": "Wolves are social hunters. They circle, test pressure, rest in bursts, vocalize, and react to pack confidence.",
            "boar": "Boars are blunt, territorial, and food-driven. They posture, sniff, charge, retreat, and settle when safe.",
            "deer": "Deer are alert prey animals. They graze, drink, rest lightly, freeze to listen, and flee early when danger feels close.",
            "fox": "Foxes are clever opportunists. They sniff, watch, flank, steal food, vocalize, and disengage if a target looks too risky.",
            "scavenger": "Scavengers are opportunistic rivals. They watch, listen, steal, bluff, rest, and punish weak openings.",
        }.get(creature.species, "Behave like a believable animal or survival-minded rival.")

        return (
            "You are the decision-making brain for one creature in a realistic 3D survival sandbox. "
            "You are not a narrator, not a storyteller, and not a game designer. "
            "Choose exactly one immediate high-level behavior that this creature will follow for the next short span of time. "
            "Return only compact JSON with keys: "
            "action, target, reason, speech, posture, locomotion, sound, duration_seconds, memory_note. "
            f"Allowed actions: {', '.join(ALLOWED_ACTIONS)}. "
            f"Allowed postures: {', '.join(ALLOWED_POSTURES)}. "
            f"Allowed locomotion values: {', '.join(ALLOWED_LOCOMOTION)}. "
            f"Allowed sounds: {', '.join(ALLOWED_SOUNDS)}. "
            f"Creature name: {creature.name}. Species: {creature.species}. Personality: {creature.personality}. "
            f"{species_guidance} "
            "Prefer believable survival behavior over theatrical behavior. "
            "Use short practical reasons. Do not explain the schema. Do not include markdown."
        )

    def _build_user_prompt(self, creature: CreatureState, snapshot: dict[str, Any]) -> str:
        memory = "; ".join(creature.memory[-4:]) or "none"
        nearby_creatures = ", ".join(
            f"{item['name']} the {item['species']} at {item['distance']:.1f}m ally={item.get('ally', False)} action={item.get('action', 'unknown')}"
            for item in snapshot.get("nearby_creatures", [])
        ) or "none"
        nearby_resources = ", ".join(
            f"{item['kind']} at {item['distance']:.1f}m biome={item.get('biome', 'unknown')}"
            for item in snapshot.get("nearby_resources", [])
        ) or "none"
        player = snapshot.get("player", {})
        noise = snapshot.get("last_noise", {})
        return (
            f"Current time: {snapshot.get('time_label', 'day')}\n"
            f"Biome: {snapshot.get('biome', 'meadow')} | elevation={float(snapshot.get('elevation', 0.0)):.1f} | "
            f"near_water={snapshot.get('near_water', False)} | near_campfire={snapshot.get('near_campfire', False)}\n"
            f"Self status: health={creature.health:.0f}/{creature.max_health:.0f}, hunger={creature.hunger:.0f}, "
            f"thirst={creature.thirst:.0f}, energy={creature.energy:.0f}, fear={creature.fear:.0f}, aggression={creature.aggression:.0f}, "
            f"comfort={creature.comfort:.0f}, curiosity={creature.curiosity:.0f}, social_drive={creature.social_drive:.0f}, "
            f"sickness={creature.sickness:.0f}, alertness={creature.alertness:.0f}, warmth={creature.warmth:.0f}\n"
            f"Player: distance={float(player.get('distance', 999.0)):.1f}, health={float(player.get('health', 100.0)):.0f}, "
            f"near campfire={player.get('near_campfire', False)}, making_noise={player.get('making_noise', False)}, "
            f"noise_level={player.get('noise_level', 'none')}\n"
            f"Recent noise: kind={noise.get('kind', 'none')}, distance={float(noise.get('distance', 999.0)):.1f}, "
            f"age={float(noise.get('age', 999.0)):.1f}, strength={float(noise.get('strength', 0.0)):.2f}\n"
            f"Nearby allies={int(snapshot.get('allies_nearby', 0))} rivals={int(snapshot.get('rivals_nearby', 0))}\n"
            f"Nearby creatures: {nearby_creatures}\n"
            f"Nearby resources: {nearby_resources}\n"
            f"Recent memory: {memory}\n"
            f"Last action: {creature.decision.action} with posture={creature.decision.posture} and sound={creature.decision.sound}\n"
            "Choose the next short behavior that best fits this creature's needs, fear, social situation, and nearby stimuli."
        )
