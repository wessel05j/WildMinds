from __future__ import annotations

from dataclasses import dataclass

import pygame

from .ai import AsyncCreatureBrain, HeuristicMind, LocalCreatureMind, OllamaRuntime, ScriptedMind, bootstrap_local_model
from .entities import SCREEN_HEIGHT, SCREEN_WIDTH
from .hardware import hardware_summary
from .world import PlayerIntent, SandboxWorld


@dataclass(slots=True)
class LaunchSummary:
    using_local_ai: bool
    model_name: str
    bootstrap_details: str
    hardware_text: str


class SurvivalSandboxGame:
    def __init__(
        self,
        *,
        bootstrap_ai: bool = True,
        seed: int = 7,
        forced_mind: object | None = None,
    ) -> None:
        self.screen = pygame.display.set_mode((SCREEN_WIDTH, SCREEN_HEIGHT))
        pygame.display.set_caption("AI Survival Sandbox")
        self.clock = pygame.time.Clock()
        self.fonts = {
            "small": pygame.font.SysFont("segoeui", 18),
            "medium": pygame.font.SysFont("segoeui", 23, bold=True),
            "large": pygame.font.SysFont("segoeui", 30, bold=True),
        }
        self.world = SandboxWorld(seed=seed)
        self.running = True
        self.using_local_ai = False
        self.model_name = "heuristic-fallback"
        self.bootstrap_details = "Local AI bootstrap skipped."
        self.hardware_text = "Hardware detection skipped."
        self.ai_status_line = "AI: fallback rules"
        self.mind = forced_mind or HeuristicMind()
        self.queued_actions = {
            "gather": False,
            "eat": False,
            "craft_campfire": False,
        }

        if forced_mind is None and bootstrap_ai:
            bootstrap = bootstrap_local_model(OllamaRuntime())
            self.using_local_ai = bootstrap.ready
            self.model_name = bootstrap.model_choice.model_name
            self.bootstrap_details = bootstrap.details
            self.hardware_text = hardware_summary(bootstrap.hardware)
            if bootstrap.ready:
                local_mind = LocalCreatureMind(model_name=bootstrap.model_choice.model_name)
                self.mind = AsyncCreatureBrain(local_mind)
                self.ai_status_line = f"AI: local {bootstrap.model_choice.model_name}"
            else:
                self.mind = HeuristicMind()
                self.ai_status_line = "AI: fallback rules"
        elif forced_mind is None:
            self.ai_status_line = "AI: fallback rules"
        else:
            self.ai_status_line = "AI: test harness"

    def launch_summary(self) -> LaunchSummary:
        return LaunchSummary(
            using_local_ai=self.using_local_ai,
            model_name=self.model_name,
            bootstrap_details=self.bootstrap_details,
            hardware_text=self.hardware_text,
        )

    def run(self) -> None:
        try:
            while self.running:
                dt = self.clock.tick(60) / 1000.0
                self._handle_events()
                pressed = pygame.key.get_pressed()
                self._step(self._intent_from_pressed(pressed), dt)
        finally:
            self.shutdown()

    def run_for_frames(self, frames: int = 60) -> dict[str, float | int | bool]:
        try:
            for _ in range(frames):
                self._handle_events()
                self._step(PlayerIntent(move=pygame.Vector2()), 1 / 60)
            return {
                "frames": frames,
                "player_health": self.world.player.health,
                "creatures_alive": len(self.world.creatures),
                "used_local_ai": self.using_local_ai,
            }
        finally:
            self.shutdown()

    def _handle_events(self) -> None:
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                self.running = False
            elif event.type == pygame.KEYDOWN:
                if event.key == pygame.K_e:
                    self.queued_actions["gather"] = True
                elif event.key in (pygame.K_q, pygame.K_1, pygame.K_RETURN):
                    self.queued_actions["eat"] = True
                elif event.key == pygame.K_f:
                    self.queued_actions["craft_campfire"] = True

    def _step(self, intent: PlayerIntent, dt: float) -> None:
        self.world.update(dt, intent, self.mind)
        self.world.draw(self.screen, self.fonts, self.ai_status_line)
        pygame.display.flip()

    def _intent_from_pressed(self, pressed: pygame.key.ScancodeWrapper) -> PlayerIntent:
        move = pygame.Vector2(
            float(pressed[pygame.K_d]) - float(pressed[pygame.K_a]),
            float(pressed[pygame.K_s]) - float(pressed[pygame.K_w]),
        )
        intent = PlayerIntent(
            move=move,
            gather=pressed[pygame.K_e] or self.queued_actions["gather"],
            attack=pressed[pygame.K_SPACE],
            eat=pressed[pygame.K_q] or pressed[pygame.K_1] or pressed[pygame.K_RETURN] or self.queued_actions["eat"],
            craft_campfire=pressed[pygame.K_f] or self.queued_actions["craft_campfire"],
        )
        for key in self.queued_actions:
            self.queued_actions[key] = False
        return intent

    def shutdown(self) -> None:
        if hasattr(self.mind, "close"):
            self.mind.close()
        pygame.quit()


def build_headless_test_game(seed: int = 7, forced_action: str = "wander") -> SurvivalSandboxGame:
    return SurvivalSandboxGame(
        bootstrap_ai=False,
        seed=seed,
        forced_mind=ScriptedMind(forced_action=forced_action),
    )
