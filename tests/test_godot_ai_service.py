from __future__ import annotations

from godot_ai_service.brain import HeuristicMind, LocalCreatureMind, _clamp_action, _extract_json, bootstrap_local_model, creature_from_payload
from survival_sandbox_ai.hardware import GPUInfo, HardwareProfile


class FailingRuntime:
    def chat(self, model_name: str, system_prompt: str, user_prompt: str) -> str:
        raise RuntimeError("offline")


def make_payload() -> dict[str, object]:
    return {
        "id": "wolf-1",
        "name": "Ash",
        "species": "wolf",
        "personality": "patient hunter",
        "health": 90.0,
        "max_health": 90.0,
        "hunger": 62.0,
        "energy": 74.0,
        "fear": 12.0,
        "aggression": 72.0,
        "decision": {"action": "stalk", "target": "player", "reason": "Keep pressure on the player."},
        "memory": ["The player crossed the ridge.", "There is a campfire near the creek."],
    }


def test_extract_json_handles_fenced_payload() -> None:
    payload = _extract_json("```json\n{\"action\":\"attack\",\"target\":\"player\"}\n```")
    assert payload["action"] == "attack"


def test_clamp_action_limits_invalid_values() -> None:
    action = _clamp_action({"action": "sing", "target": "player", "speech": "x" * 300})
    assert action.action == "wander"
    assert action.target == "player"
    assert len(action.speech) <= 60


def test_creature_from_payload_preserves_name_and_memory() -> None:
    creature = creature_from_payload(make_payload())
    assert creature.name == "Ash"
    assert creature.memory[0] == "The player crossed the ridge."
    assert creature.decision.action == "stalk"


def test_heuristic_mind_attacks_when_hungry_wolf_is_close() -> None:
    creature = creature_from_payload(make_payload())
    action = HeuristicMind().decide(
        creature,
        {
            "time_label": "day",
            "player": {"distance": 11.0, "health": 90.0, "near_campfire": False},
            "nearby_creatures": [],
            "nearby_resources": [],
        },
    )
    assert action.action in {"attack", "stalk"}


def test_local_mind_falls_back_to_heuristics_on_runtime_failure() -> None:
    creature = creature_from_payload(make_payload())
    mind = LocalCreatureMind(model_name="fake", runtime=FailingRuntime())
    action = mind.decide(
        creature,
        {
            "time_label": "night",
            "player": {"distance": 14.0, "health": 70.0, "near_campfire": False},
            "nearby_creatures": [],
            "nearby_resources": [{"kind": "berries", "distance": 8.0}],
        },
    )
    assert action.action in {"attack", "stalk", "forage", "wander"}


def test_bootstrap_local_model_force_heuristic_still_selects_model(monkeypatch) -> None:
    fake_profile = HardwareProfile(
        platform_name="Windows",
        cpu_name="CPU",
        logical_cores=8,
        ram_gb=16.0,
        gpus=[GPUInfo(name="RTX", vram_gb=4.0)],
    )
    monkeypatch.setattr("godot_ai_service.brain.detect_hardware", lambda: fake_profile)

    result = bootstrap_local_model(force_heuristic=True)
    assert result.ready is False
    assert result.model_choice.model_name == "llama3.2:3b"
