from __future__ import annotations

import pygame

from survival_sandbox_ai.ai import _clamp_action, _extract_json, bootstrap_local_model, LocalCreatureMind
from survival_sandbox_ai.entities import Creature
from survival_sandbox_ai.hardware import GPUInfo, HardwareProfile


class FailingRuntime:
    def chat(self, model_name: str, system_prompt: str, user_prompt: str) -> str:
        raise RuntimeError("offline")


class ReadyRuntime:
    def __init__(self) -> None:
        self.ensured = False

    def ensure_server(self) -> bool:
        return True

    def ensure_model(self, model_name: str) -> None:
        self.ensured = True


def make_creature() -> Creature:
    return Creature(
        identifier="scavenger-1",
        species="scavenger",
        name="Rook",
        personality="careful and greedy",
        position=pygame.Vector2(100, 100),
        velocity=pygame.Vector2(),
        radius=16,
        speed=70,
        health=80,
        max_health=80,
        hunger=70,
        energy=60,
        fear=10,
        aggression=40,
    )


def test_extract_json_handles_code_fences() -> None:
    payload = _extract_json("```json\n{\"action\":\"attack\",\"target\":\"player\"}\n```")
    assert payload["action"] == "attack"
    assert payload["target"] == "player"


def test_clamp_action_defaults_invalid_actions() -> None:
    action = _clamp_action({"action": "dance", "target": "player", "speech": "too long" * 50})
    assert action.action == "wander"
    assert action.target == "player"
    assert len(action.speech) <= 60


def test_local_mind_falls_back_when_runtime_fails() -> None:
    creature = make_creature()
    creature.memory.append("The player is near my stash.")
    snapshot = {
        "time_label": "day",
        "player": {"distance": 120.0, "health": 50.0, "near_campfire": False},
        "nearby_creatures": [],
        "nearby_resources": [{"kind": "berries", "distance": 40.0}],
    }
    mind = LocalCreatureMind(model_name="fake", runtime=FailingRuntime())
    action = mind.decide(creature, snapshot)
    assert action.action in {"forage", "attack", "stalk", "wander"}


def test_bootstrap_local_model_uses_ready_runtime(monkeypatch) -> None:
    fake_profile = HardwareProfile(
        platform_name="Windows",
        cpu_name="CPU",
        logical_cores=8,
        ram_gb=16.0,
        gpus=[GPUInfo(name="RTX", vram_gb=4.0)],
    )
    monkeypatch.setattr("survival_sandbox_ai.ai.detect_hardware", lambda: fake_profile)

    runtime = ReadyRuntime()
    result = bootstrap_local_model(runtime=runtime)
    assert result.ready is True
    assert result.model_choice.model_name == "llama3.2:3b"
    assert runtime.ensured is True
