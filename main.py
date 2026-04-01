from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

import requests


ROOT = Path(__file__).resolve().parent
GODOT_PROJECT = ROOT / "godot3d"
SERVICE_URL = "http://127.0.0.1:8765/health"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Launch the WildMinds 3D Godot project")
    parser.add_argument("--headless-smoke", action="store_true", help="Boot the Godot project headlessly and quit")
    parser.add_argument("--legacy-2d", action="store_true", help="Run the old PyGame prototype instead")
    return parser.parse_args()


def find_godot_executable(headless: bool = False) -> str:
    env_override = os.getenv("WILDMINDS_GODOT")
    if env_override and Path(env_override).exists():
        return env_override

    candidates = [
        Path(
            r"C:\Users\ejwes\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6.1-stable_win64_console.exe"
            if headless
            else r"C:\Users\ejwes\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6.1-stable_win64.exe"
        ),
        Path(
            r"C:\Users\ejwes\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6.1-stable_win64_console.exe"
        ),
        Path(
            r"C:\Users\ejwes\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6.1-stable_win64.exe"
        ),
    ]
    for candidate in candidates:
        if candidate.exists():
            return str(candidate)
    raise FileNotFoundError("Could not locate a Godot 4 executable.")


def wait_for_service(timeout: float = 40.0) -> dict[str, object] | None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            response = requests.get(SERVICE_URL, timeout=1.5)
            if response.ok:
                return response.json()
        except requests.RequestException:
            pass
        time.sleep(0.5)
    return None


def launch_service() -> subprocess.Popen[bytes]:
    return subprocess.Popen(
        [sys.executable, "-m", "godot_ai_service.server"],
        cwd=str(ROOT),
        env=os.environ.copy(),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def run_godot(godot_path: str, headless_smoke: bool) -> int:
    command = [godot_path, "--path", str(GODOT_PROJECT)]
    if headless_smoke:
        command = [godot_path, "--headless", "--path", str(GODOT_PROJECT), "--", "--smoke-test"]
    completed = subprocess.run(command, cwd=str(ROOT))
    return completed.returncode


def main() -> None:
    args = parse_args()

    if args.legacy_2d:
        from legacy_2d_main import main as legacy_main

        legacy_main()
        return

    godot_path = find_godot_executable(headless=args.headless_smoke)

    service_started = False
    service_process: subprocess.Popen[bytes] | None = None
    service_status = wait_for_service(timeout=2.0)
    if service_status is None:
        service_process = launch_service()
        service_started = True
        service_status = wait_for_service()
        if service_status is None:
            raise RuntimeError("WildMinds AI helper could not be started with the required local model.")

    if not bool(service_status.get("using_local_ai", False)):
        raise RuntimeError(str(service_status.get("details", "WildMinds requires a local Ollama model to launch.")))

    print(service_status.get("details", "WildMinds AI helper ready."), flush=True)
    try:
        raise SystemExit(run_godot(godot_path, args.headless_smoke))
    finally:
        if service_started and service_process is not None and service_process.poll() is None:
            service_process.terminate()
            try:
                service_process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                service_process.kill()


if __name__ == "__main__":
    main()
