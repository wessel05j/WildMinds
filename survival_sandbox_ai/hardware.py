from __future__ import annotations

import json
import math
import platform
import subprocess
from dataclasses import dataclass, field
from typing import Any


@dataclass(slots=True)
class GPUInfo:
    name: str
    vram_gb: float
    driver_version: str = ""


@dataclass(slots=True)
class HardwareProfile:
    platform_name: str
    cpu_name: str
    logical_cores: int
    ram_gb: float
    gpus: list[GPUInfo] = field(default_factory=list)

    @property
    def best_gpu(self) -> GPUInfo | None:
        if not self.gpus:
            return None
        return max(self.gpus, key=lambda gpu: gpu.vram_gb)


@dataclass(slots=True)
class ModelChoice:
    model_name: str
    reasoning: str


def _powershell_json(command: str) -> Any:
    completed = subprocess.run(
        ["powershell", "-NoProfile", "-Command", command],
        capture_output=True,
        text=True,
        check=True,
    )
    raw = completed.stdout.strip()
    if not raw:
        return None
    return json.loads(raw)


def detect_hardware() -> HardwareProfile:
    platform_name = platform.platform()
    cpu_name = platform.processor() or "Unknown CPU"
    logical_cores = 1
    ram_gb = 8.0
    gpus: list[GPUInfo] = []

    if platform.system() == "Windows":
        try:
            cpu_data = _powershell_json(
                "Get-CimInstance Win32_Processor | "
                "Select-Object Name,NumberOfLogicalProcessors | ConvertTo-Json -Compress"
            )
            if isinstance(cpu_data, list):
                cpu_data = cpu_data[0]
            cpu_name = cpu_data.get("Name") or cpu_name
            logical_cores = int(cpu_data.get("NumberOfLogicalProcessors") or logical_cores)

            memory_data = _powershell_json(
                "Get-CimInstance Win32_ComputerSystem | "
                "Select-Object TotalPhysicalMemory | ConvertTo-Json -Compress"
            )
            total_bytes = float(memory_data.get("TotalPhysicalMemory") or 0.0)
            if total_bytes:
                ram_gb = total_bytes / (1024**3)

            gpu_data = _powershell_json(
                "Get-CimInstance Win32_VideoController | "
                "Select-Object Name,AdapterRAM,DriverVersion | ConvertTo-Json -Compress"
            )
            if isinstance(gpu_data, dict):
                gpu_data = [gpu_data]
            for entry in gpu_data or []:
                raw_ram = float(entry.get("AdapterRAM") or 0.0)
                gpus.append(
                    GPUInfo(
                        name=entry.get("Name") or "Unknown GPU",
                        vram_gb=raw_ram / (1024**3),
                        driver_version=entry.get("DriverVersion") or "",
                    )
                )
        except Exception:
            pass

    return HardwareProfile(
        platform_name=platform_name,
        cpu_name=cpu_name,
        logical_cores=logical_cores,
        ram_gb=ram_gb,
        gpus=gpus,
    )


def choose_ollama_model(profile: HardwareProfile) -> ModelChoice:
    best_gpu = profile.best_gpu
    vram = best_gpu.vram_gb if best_gpu else 0.0
    ram = profile.ram_gb

    if vram >= 10 and ram >= 24:
        return ModelChoice(
            model_name="llama3.1:8b",
            reasoning="Enough VRAM and system memory for an 8B local model.",
        )

    if vram >= 4 or ram >= 12:
        return ModelChoice(
            model_name="llama3.2:3b",
            reasoning="Mid-range laptop hardware is a good fit for a faster 3B model.",
        )

    return ModelChoice(
        model_name="llama3.2:1b",
        reasoning="Lower-memory hardware is safer with a 1B model to keep the game responsive.",
    )


def hardware_summary(profile: HardwareProfile) -> str:
    gpu_text = ", ".join(f"{gpu.name} ({gpu.vram_gb:.1f} GB)" for gpu in profile.gpus) or "No GPU detected"
    return (
        f"Platform: {profile.platform_name}\n"
        f"CPU: {profile.cpu_name}\n"
        f"Logical cores: {profile.logical_cores}\n"
        f"RAM: {profile.ram_gb:.1f} GB\n"
        f"GPUs: {gpu_text}"
    )


def round_memory_gb(value: float) -> float:
    return math.floor(value * 10 + 0.5) / 10
