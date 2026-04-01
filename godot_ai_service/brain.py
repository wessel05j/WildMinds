from __future__ import annotations

import json
import subprocess
import time
from dataclasses import dataclass
from typing import Any

import requests

from survival_sandbox_ai.hardware import HardwareProfile, ModelChoice, choose_ollama_model, detect_hardware


OLLAMA_URL = "http://127.0.0.1:11434"
ALLOWED_ACTIONS = ("wander", "forage", "rest", "flee", "stalk", "attack", "guard")


@dataclass(slots=True)
class AIAction:
    action: str
    target: str = "none"
    reason: str = ""
    speech: str = ""

    def as_dict(self) -> dict[str, str]:
        return {
            "action": self.action,
            "target": self.target,
            "reason": self.reason,
            "speech": self.speech,
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
    energy: float
    fear: float
    aggression: float
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
        energy=float(payload.get("energy", 70.0)),
        fear=float(payload.get("fear", 10.0)),
        aggression=float(payload.get("aggression", 35.0)),
        decision=AIAction(
            action=str(previous.get("action", payload.get("last_action", "wander"))),
            target=str(previous.get("target", "none")),
            reason=str(previous.get("reason", "")),
            speech=str(previous.get("speech", "")),
        ),
        memory=tuple(str(item) for item in payload.get("memory", [])),
    )


class OllamaRuntime:
    def __init__(self, base_url: str = OLLAMA_URL, timeout: float = 15.0) -> None:
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

        subprocess.Popen(
            ["ollama", "serve"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            creationflags=creationflags,
        )

        deadline = time.time() + 20.0
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

    def ensure_model(self, model_name: str) -> None:
        installed = set(self.list_models())
        if model_name in installed:
            return

        completed = subprocess.run(
            ["ollama", "pull", model_name],
            capture_output=True,
            check=False,
        )
        if completed.returncode != 0:
            stderr_text = completed.stderr.decode(errors="replace").strip()
            stdout_text = completed.stdout.decode(errors="replace").strip()
            raise RuntimeError(stderr_text or stdout_text or f"Could not pull {model_name}")

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
                    "temperature": 0.45,
                    "num_predict": 120,
                },
            },
            timeout=self.timeout,
        )
        response.raise_for_status()
        payload = response.json()
        return payload["message"]["content"]


def bootstrap_local_model(force_heuristic: bool = False, runtime: OllamaRuntime | None = None) -> BootstrapResult:
    runtime = runtime or OllamaRuntime()
    hardware = detect_hardware()
    model_choice = choose_ollama_model(hardware)

    if force_heuristic:
        return BootstrapResult(
            hardware=hardware,
            model_choice=model_choice,
            ready=False,
            details="Forced heuristic mode. Local model bootstrap skipped.",
        )

    if not runtime.ensure_server():
        return BootstrapResult(
            hardware=hardware,
            model_choice=model_choice,
            ready=False,
            details="Ollama could not be reached or started. Falling back to heuristic AI.",
        )

    try:
        runtime.ensure_model(model_choice.model_name)
        return BootstrapResult(
            hardware=hardware,
            model_choice=model_choice,
            ready=True,
            details=f"Using local model {model_choice.model_name}. {model_choice.reasoning}",
        )
    except Exception as exc:
        return BootstrapResult(
            hardware=hardware,
            model_choice=model_choice,
            ready=False,
            details=f"Model setup failed: {exc}. Falling back to heuristic AI.",
        )


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


def _clamp_action(data: dict[str, Any]) -> AIAction:
    action = str(data.get("action", "wander")).strip().lower()
    if action not in ALLOWED_ACTIONS:
        action = "wander"
    target = str(data.get("target", "none")).strip().lower() or "none"
    reason = str(data.get("reason", "")).strip()[:120]
    speech = str(data.get("speech", "")).strip()[:60]
    return AIAction(action=action, target=target, reason=reason, speech=speech)


class HeuristicMind:
    def decide(self, creature: CreatureState, snapshot: dict[str, Any]) -> AIAction:
        nearby_resources = snapshot.get("nearby_resources", [])
        player = snapshot.get("player", {})
        player_distance = float(player.get("distance", 999.0))
        player_health = float(player.get("health", 100.0))

        if creature.health < creature.max_health * 0.35 or creature.fear > 65:
            return AIAction("flee", "player", "Too risky to stay in the fight.", "Break away.")

        if creature.species == "wolf":
            if creature.hunger > 55 and player_distance < 18:
                return AIAction("attack", "player", "The player is close enough to run down.", "Close in.")
            if player_distance < 26:
                return AIAction("stalk", "player", "Stay near and pressure the target.", "Shadow them.")

        if creature.species == "scavenger":
            if creature.hunger > 58 and nearby_resources:
                return AIAction("forage", nearby_resources[0]["kind"], "Supplies matter more than fighting.", "Grab it.")
            if player_distance < 16 and player_health < 70:
                return AIAction("attack", "player", "The player looks weak enough to punish.", "Now.")
            if player.get("near_campfire"):
                return AIAction("stalk", "player", "Watch the fire and wait for an opening.", "Wait.")

        if creature.species == "boar":
            if player_distance < 12:
                return AIAction("attack", "player", "Drive the threat away immediately.", "Charge.")
            if nearby_resources:
                return AIAction("forage", nearby_resources[0]["kind"], "Eat while the path is clear.", "Sniff.")

        if creature.energy < 30:
            return AIAction("rest", "none", "Need to recover before committing.", "Rest.")

        if creature.hunger > 50 and nearby_resources:
            return AIAction("forage", nearby_resources[0]["kind"], "Food comes first right now.", "Food.")

        return AIAction("wander", "none", "No urgent pressure. Keep moving.", "")


class LocalCreatureMind:
    def __init__(self, model_name: str, runtime: OllamaRuntime | None = None, fallback: HeuristicMind | None = None) -> None:
        self.model_name = model_name
        self.runtime = runtime or OllamaRuntime()
        self.fallback = fallback or HeuristicMind()

    def decide(self, creature: CreatureState, snapshot: dict[str, Any]) -> AIAction:
        system_prompt = self._build_system_prompt(creature)
        user_prompt = self._build_user_prompt(creature, snapshot)
        try:
            raw = self.runtime.chat(self.model_name, system_prompt, user_prompt)
            return _clamp_action(_extract_json(raw))
        except Exception:
            return self.fallback.decide(creature, snapshot)

    def _build_system_prompt(self, creature: CreatureState) -> str:
        return (
            "You are the decision-making brain for one creature in a realistic 3D survival sandbox. "
            "You are not a narrator. Choose one high-level action only. "
            "Return compact JSON with keys action, target, reason, speech. "
            f"Allowed actions: {', '.join(ALLOWED_ACTIONS)}. "
            f"Creature name: {creature.name}. Species: {creature.species}. Personality: {creature.personality}. "
            "Behave like a believable rival or animal trying to survive."
        )

    def _build_user_prompt(self, creature: CreatureState, snapshot: dict[str, Any]) -> str:
        memory = "; ".join(creature.memory) or "none"
        nearby_creatures = ", ".join(
            f"{item['name']} the {item['species']} at {item['distance']:.1f}m"
            for item in snapshot.get("nearby_creatures", [])
        ) or "none"
        nearby_resources = ", ".join(
            f"{item['kind']} at {item['distance']:.1f}m"
            for item in snapshot.get("nearby_resources", [])
        ) or "none"
        player = snapshot.get("player", {})
        return (
            f"Current time: {snapshot.get('time_label', 'day')}\n"
            f"Self status: health={creature.health:.0f}/{creature.max_health:.0f}, "
            f"hunger={creature.hunger:.0f}, energy={creature.energy:.0f}, fear={creature.fear:.0f}\n"
            f"Player: distance={float(player.get('distance', 999.0)):.1f}, "
            f"health={float(player.get('health', 100.0)):.0f}, "
            f"near campfire={player.get('near_campfire', False)}\n"
            f"Nearby creatures: {nearby_creatures}\n"
            f"Nearby resources: {nearby_resources}\n"
            f"Recent memory: {memory}\n"
            f"Last action: {creature.decision.action}\n"
            "Choose the next action that best helps this creature survive and compete."
        )
