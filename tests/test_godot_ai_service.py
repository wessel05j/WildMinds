from __future__ import annotations

import subprocess

import pytest

from godot_ai_service.brain import (
    AIAction,
    LocalCreatureMind,
    LocalModelRequiredError,
    OllamaRuntime,
    _clean_ollama_output,
    _clamp_action,
    _extract_json,
    bootstrap_local_model,
    creature_from_payload,
    ensure_local_model_ready,
)
from survival_sandbox_ai.hardware import GPUInfo, HardwareProfile


class ReadyRuntime:
    def __init__(self) -> None:
        self.ensured = False

    def ensure_server(self) -> bool:
        return True

    def ensure_model(self, model_name: str) -> bool:
        self.ensured = True
        return False

    def chat(self, model_name: str, system_prompt: str, user_prompt: str) -> str:
        return (
            '{"action":"sleep","target":"none","reason":"Low energy and safe for now.",'
            '"speech":"huff","posture":"sleep","locomotion":"still","sound":"huff",'
            '"duration_seconds":3.4,"memory_note":"Felt safe enough to lie down."}'
        )


class InstallingRuntime(ReadyRuntime):
    def ensure_model(self, model_name: str) -> bool:
        self.ensured = True
        return True

    def chat(self, model_name: str, system_prompt: str, user_prompt: str) -> str:
        return (
            '{"action":"sleep","target":"none","reason":"Low energy and safe for now.",'
            '"speech":"huff","posture":"sleep","locomotion":"still","sound":"huff",'
            '"duration_seconds":3.4,"memory_note":"Felt safe enough to lie down."}'
        )


class MissingRuntime:
    def ensure_server(self) -> bool:
        return False


def make_payload() -> dict[str, object]:
    return {
        "id": "wolf-1",
        "name": "Ash",
        "species": "wolf",
        "personality": "patient hunter",
        "health": 90.0,
        "max_health": 90.0,
        "hunger": 62.0,
        "thirst": 21.0,
        "energy": 74.0,
        "fear": 12.0,
        "aggression": 72.0,
        "comfort": 58.0,
        "curiosity": 40.0,
        "social_drive": 64.0,
        "sickness": 0.0,
        "alertness": 66.0,
        "warmth": 48.0,
        "decision": {"action": "stalk", "target": "player", "reason": "Keep pressure on the player."},
        "memory": ["The player crossed the ridge.", "There is a campfire near the creek."],
    }


def test_extract_json_handles_fenced_payload() -> None:
    payload = _extract_json("```json\n{\"action\":\"attack\",\"target\":\"player\"}\n```")
    assert payload["action"] == "attack"


def test_clean_ollama_output_removes_terminal_noise() -> None:
    noisy = b"\x1b[?25lpulling manifest \xe2\xa0\x8b\r\nError: registry timeout\r\n"
    assert _clean_ollama_output(noisy) == "Error: registry timeout"


def test_clamp_action_limits_invalid_values() -> None:
    action = _clamp_action({"action": "sing", "target": "player", "speech": "x" * 300, "posture": "dance"})
    assert action.action == "idle_watch"
    assert action.target == "player"
    assert action.posture == "stand"
    assert len(action.speech) <= 80


def test_creature_from_payload_preserves_expanded_state() -> None:
    creature = creature_from_payload(make_payload())
    assert creature.name == "Ash"
    assert creature.memory[0] == "The player crossed the ridge."
    assert creature.thirst == 21.0
    assert creature.social_drive == 64.0
    assert creature.decision.action == "stalk"


def test_local_mind_returns_structured_model_action() -> None:
    creature = creature_from_payload(make_payload())
    mind = LocalCreatureMind(model_name="fake", runtime=ReadyRuntime())
    action = mind.decide(
        creature,
        {
            "time_label": "night",
            "biome": "forest",
            "elevation": 1.8,
            "near_water": False,
            "near_campfire": False,
            "player": {"distance": 22.0, "health": 70.0, "near_campfire": False, "making_noise": False, "noise_level": "none"},
            "last_noise": {"kind": "footsteps", "distance": 13.0, "age": 0.6, "strength": 0.4},
            "nearby_creatures": [],
            "nearby_resources": [{"kind": "berries", "distance": 8.0, "biome": "forest"}],
        },
    )
    assert isinstance(action, AIAction)
    assert action.action == "sleep"
    assert action.posture == "sleep"
    assert action.sound == "huff"


def test_bootstrap_local_model_uses_ready_runtime(monkeypatch) -> None:
    fake_profile = HardwareProfile(
        platform_name="Windows",
        cpu_name="CPU",
        logical_cores=8,
        ram_gb=16.0,
        gpus=[GPUInfo(name="RTX", vram_gb=4.0)],
    )
    monkeypatch.setattr("godot_ai_service.brain.detect_hardware", lambda: fake_profile)

    runtime = ReadyRuntime()
    result = bootstrap_local_model(runtime=runtime)
    assert result.ready is True
    assert result.model_choice.model_name == "llama3.2:1b"
    assert runtime.ensured is True
    assert result.details.startswith("Using local model llama3.2:1b.")


def test_bootstrap_local_model_reports_automatic_install(monkeypatch) -> None:
    fake_profile = HardwareProfile(
        platform_name="Windows",
        cpu_name="CPU",
        logical_cores=8,
        ram_gb=16.0,
        gpus=[GPUInfo(name="RTX", vram_gb=4.0)],
    )
    monkeypatch.setattr("godot_ai_service.brain.detect_hardware", lambda: fake_profile)

    runtime = InstallingRuntime()
    result = bootstrap_local_model(runtime=runtime)
    assert result.ready is True
    assert runtime.ensured is True
    assert result.details.startswith("Installed missing local model llama3.2:1b automatically.")


def test_ollama_runtime_retries_pull_until_model_is_installed(monkeypatch) -> None:
    runtime = OllamaRuntime()
    listed_models = [[], ["llama3.2:1b"]]
    pull_attempts: list[str] = []
    pull_results = [
        subprocess.CompletedProcess(["ollama", "pull", "llama3.2:1b"], 1, stdout=b"", stderr=b"registry timeout"),
        subprocess.CompletedProcess(["ollama", "pull", "llama3.2:1b"], 0, stdout=b"pulled", stderr=b""),
    ]

    def fake_list_models() -> list[str]:
        return listed_models.pop(0)

    def fake_pull(model_name: str) -> subprocess.CompletedProcess[bytes]:
        pull_attempts.append(model_name)
        return pull_results.pop(0)

    monkeypatch.setattr(runtime, "list_models", fake_list_models)
    monkeypatch.setattr(runtime, "_pull_model_once", fake_pull)
    monkeypatch.setattr("godot_ai_service.brain.time.sleep", lambda _seconds: None)

    installed_now = runtime.ensure_model("llama3.2:1b")
    assert installed_now is True
    assert pull_attempts == ["llama3.2:1b", "llama3.2:1b"]


def test_ensure_local_model_ready_raises_when_ollama_missing(monkeypatch) -> None:
    fake_profile = HardwareProfile(
        platform_name="Windows",
        cpu_name="CPU",
        logical_cores=8,
        ram_gb=16.0,
        gpus=[GPUInfo(name="RTX", vram_gb=4.0)],
    )
    monkeypatch.setattr("godot_ai_service.brain.detect_hardware", lambda: fake_profile)

    with pytest.raises(LocalModelRequiredError):
        ensure_local_model_ready(runtime=MissingRuntime())
