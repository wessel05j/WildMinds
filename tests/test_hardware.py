from __future__ import annotations

from survival_sandbox_ai.hardware import GPUInfo, HardwareProfile, choose_ollama_model


def test_choose_small_model_for_low_memory_machine() -> None:
    profile = HardwareProfile(
        platform_name="Windows",
        cpu_name="Budget CPU",
        logical_cores=4,
        ram_gb=8.0,
        gpus=[],
    )
    assert choose_ollama_model(profile).model_name == "llama3.2:1b"


def test_choose_mid_model_for_laptop_gpu() -> None:
    profile = HardwareProfile(
        platform_name="Windows",
        cpu_name="Ryzen",
        logical_cores=12,
        ram_gb=16.0,
        gpus=[GPUInfo(name="RTX 3050", vram_gb=4.0)],
    )
    assert choose_ollama_model(profile).model_name == "llama3.2:3b"


def test_choose_large_model_for_high_end_machine() -> None:
    profile = HardwareProfile(
        platform_name="Windows",
        cpu_name="Workstation",
        logical_cores=24,
        ram_gb=32.0,
        gpus=[GPUInfo(name="RTX 4080", vram_gb=16.0)],
    )
    assert choose_ollama_model(profile).model_name == "llama3.1:8b"
