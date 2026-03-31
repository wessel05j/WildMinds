from __future__ import annotations

import json
import random
import subprocess
import threading
import time
from dataclasses import dataclass
from queue import Empty, Full, Queue
from typing import Any

import requests

from .entities import AIAction, Creature
from .hardware import HardwareProfile, ModelChoice, choose_ollama_model, detect_hardware


OLLAMA_URL = "http://127.0.0.1:11434"
ALLOWED_ACTIONS = ("wander", "forage", "rest", "flee", "stalk", "attack", "guard")


@dataclass(slots=True)
class BootstrapResult:
    hardware: HardwareProfile
    model_choice: ModelChoice
    ready: bool
    details: str


@dataclass(slots=True)
class CreatureState:
    identifier: str
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
            raise RuntimeError(
                f"Failed to pull model {model_name}: {stderr_text or stdout_text}"
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
                    "temperature": 0.5,
                    "num_predict": 120,
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
            details="Ollama could not be reached or started. The game will fall back to heuristic AI.",
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
            details=f"Model setup failed: {exc}. The game will fall back to heuristic AI.",
        )


def _extract_json(raw: str) -> dict[str, Any]:
    raw = raw.strip()
    if raw.startswith("```"):
        lines = [line for line in raw.splitlines() if not line.startswith("```")]
        raw = "\n".join(lines).strip()

    start = raw.find("{")
    end = raw.rfind("}")
    if start == -1 or end == -1 or end <= start:
        raise ValueError("No JSON object found in model response")
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
    def decide(self, creature: CreatureState | Creature, snapshot: dict[str, Any]) -> AIAction:
        nearby_resources = snapshot.get("nearby_resources", [])
        player_distance = snapshot.get("player", {}).get("distance", 999.0)
        player_health = snapshot.get("player", {}).get("health", 100.0)

        if creature.health < creature.max_health * 0.35 or creature.fear > 65:
            return AIAction("flee", "player", "Too risky to stay in the fight.", "Back off.")

        if creature.species == "wolf":
            if creature.hunger > 55 and player_distance < 150:
                return AIAction("attack", "player", "The target looks weak enough to hunt.", "Circle in.")
            if player_distance < 220:
                return AIAction("stalk", "player", "Stay close and wait for an opening.", "Keep pressure.")

        if creature.species == "scavenger":
            if creature.hunger > 60 and nearby_resources:
                return AIAction("forage", nearby_resources[0]["kind"], "Grab supplies before someone else does.", "Loot first.")
            if player_distance < 180 and player_health < 60:
                return AIAction("attack", "player", "The player looks exposed.", "Push now.")
            if snapshot.get("player", {}).get("near_campfire"):
                return AIAction("stalk", "player", "Watch the camp before committing.", "Stay hidden.")

        if creature.species == "boar":
            if player_distance < 120:
                return AIAction("attack", "player", "Drive the threat away from my space.", "Charge.")
            if nearby_resources:
                return AIAction("forage", nearby_resources[0]["kind"], "Eat while the area is calm.", "Sniffing.")

        if creature.energy < 30:
            return AIAction("rest", "none", "Need to recover before moving again.", "Resting.")

        if creature.hunger > 50 and nearby_resources:
            return AIAction("forage", nearby_resources[0]["kind"], "Food matters more than fighting right now.", "Food.")

        return AIAction("wander", "none", "No urgent need. Keep moving.", "Roaming.")


class LocalCreatureMind:
    def __init__(
        self,
        model_name: str,
        runtime: OllamaRuntime | None = None,
        fallback: HeuristicMind | None = None,
    ) -> None:
        self.model_name = model_name
        self.runtime = runtime or OllamaRuntime()
        self.fallback = fallback or HeuristicMind()

    def decide(self, creature: CreatureState | Creature, snapshot: dict[str, Any]) -> AIAction:
        system_prompt = self._build_system_prompt(creature)
        user_prompt = self._build_user_prompt(creature, snapshot)

        try:
            raw = self.runtime.chat(self.model_name, system_prompt, user_prompt)
            parsed = _extract_json(raw)
            return _clamp_action(parsed)
        except Exception:
            return self.fallback.decide(creature, snapshot)

    def _build_system_prompt(self, creature: CreatureState | Creature) -> str:
        return (
            "You are the decision-making brain for one creature in a 2D survival sandbox. "
            "You are not a narrator. You must choose one high-level action. "
            "Return only compact JSON with keys action, target, reason, speech. "
            f"Allowed actions: {', '.join(ALLOWED_ACTIONS)}. "
            "Keep the reason short and practical. "
            f"Species: {creature.species}. Personality: {creature.personality}. "
            "Behave like a believable rival or animal trying to survive."
        )

    def _build_user_prompt(self, creature: CreatureState | Creature, snapshot: dict[str, Any]) -> str:
        memory = "; ".join(creature.memory) or "none"
        nearby_creatures = ", ".join(
            f"{item['species']} at {item['distance']:.0f}"
            for item in snapshot.get("nearby_creatures", [])
        ) or "none"
        nearby_resources = ", ".join(
            f"{item['kind']} at {item['distance']:.0f}"
            for item in snapshot.get("nearby_resources", [])
        ) or "none"

        return (
            f"Current time: {snapshot['time_label']}\n"
            f"Self status: health={creature.health:.0f}/{creature.max_health:.0f}, "
            f"hunger={creature.hunger:.0f}, energy={creature.energy:.0f}, fear={creature.fear:.0f}\n"
            f"Player: distance={snapshot['player']['distance']:.0f}, "
            f"health={snapshot['player']['health']:.0f}, "
            f"near campfire={snapshot['player']['near_campfire']}\n"
            f"Nearby creatures: {nearby_creatures}\n"
            f"Nearby resources: {nearby_resources}\n"
            f"Recent memory: {memory}\n"
            f"Last action: {creature.decision.action}\n"
            "Choose the next action that best helps this creature survive and compete."
        )


class ScriptedMind:
    """Deterministic test double used by headless tests."""

    def __init__(self, forced_action: str = "wander") -> None:
        self.forced_action = forced_action

    def decide(self, creature: CreatureState | Creature, snapshot: dict[str, Any]) -> AIAction:
        target = "berries" if self.forced_action == "forage" else "player"
        return AIAction(
            action=self.forced_action,
            target=target,
            reason="Test harness decision.",
            speech="test",
        )


def random_personality(species: str, rng: random.Random) -> str:
    options = {
        "scavenger": ["greedy and careful", "sly and patient", "bold and mean"],
        "wolf": ["pack-minded and relentless", "cautious hunter", "territorial predator"],
        "boar": ["territorial and stubborn", "tired but dangerous", "restless bruiser"],
    }
    return rng.choice(options.get(species, ["survival focused"]))


def snapshot_creature_state(creature: Creature) -> CreatureState:
    return CreatureState(
        identifier=creature.identifier,
        species=creature.species,
        personality=creature.personality,
        health=creature.health,
        max_health=creature.max_health,
        hunger=creature.hunger,
        energy=creature.energy,
        fear=creature.fear,
        aggression=creature.aggression,
        decision=AIAction(
            action=creature.decision.action,
            target=creature.decision.target,
            reason=creature.decision.reason,
            speech=creature.decision.speech,
        ),
        memory=tuple(creature.memory),
    )


class AsyncCreatureBrain:
    """Runs slow creature decisions on a background thread."""

    def __init__(self, decision_mind: object, queue_limit: int = 32) -> None:
        self.decision_mind = decision_mind
        self.task_queue: Queue[tuple[str, CreatureState, dict[str, Any]] | None] = Queue(maxsize=queue_limit)
        self.result_queue: Queue[tuple[str, AIAction]] = Queue()
        self.pending: set[str] = set()
        self.stop_event = threading.Event()
        self.worker = threading.Thread(target=self._worker_loop, daemon=True, name="ai-creature-worker")
        self.worker.start()

    def request_decision(self, creature: Creature, snapshot: dict[str, Any]) -> bool:
        if self.stop_event.is_set() or creature.identifier in self.pending:
            return False
        try:
            self.task_queue.put_nowait((creature.identifier, snapshot_creature_state(creature), snapshot))
        except Full:
            return False
        self.pending.add(creature.identifier)
        creature.decision_pending = True
        return True

    def collect_ready_decisions(self) -> dict[str, AIAction]:
        ready: dict[str, AIAction] = {}
        while True:
            try:
                creature_id, action = self.result_queue.get_nowait()
            except Empty:
                break
            self.pending.discard(creature_id)
            ready[creature_id] = action
        return ready

    def close(self) -> None:
        self.stop_event.set()
        try:
            self.task_queue.put_nowait(None)
        except Full:
            pass
        if self.worker.is_alive():
            self.worker.join(timeout=1.0)

    def _worker_loop(self) -> None:
        while not self.stop_event.is_set():
            try:
                task = self.task_queue.get(timeout=0.2)
            except Empty:
                continue

            if task is None:
                return

            creature_id, creature_state, snapshot = task
            try:
                action = self.decision_mind.decide(creature_state, snapshot)
            except Exception:
                action = AIAction(action="wander", target="none", reason="Worker fallback.", speech="")
            self.result_queue.put((creature_id, action))
