from __future__ import annotations

import argparse
import os

import pygame

from survival_sandbox_ai.game import SurvivalSandboxGame


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="AI-driven PyGame survival sandbox")
    parser.add_argument("--headless-smoke", action="store_true", help="Run a short non-interactive smoke test")
    parser.add_argument("--frames", type=int, default=90, help="Frames to run for smoke mode")
    parser.add_argument(
        "--skip-ai-bootstrap",
        action="store_true",
        help="Skip Ollama startup and model download, and use fallback rules instead",
    )
    parser.add_argument("--seed", type=int, default=7, help="World seed")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.headless_smoke:
        os.environ.setdefault("SDL_VIDEODRIVER", "dummy")

    pygame.init()
    game = SurvivalSandboxGame(
        bootstrap_ai=not args.skip_ai_bootstrap,
        seed=args.seed,
    )

    if args.headless_smoke:
        result = game.run_for_frames(frames=args.frames)
        print(result)
        pygame.quit()
        return

    summary = game.launch_summary()
    print(summary.hardware_text)
    print(summary.bootstrap_details)
    game.run()


if __name__ == "__main__":
    main()
