from __future__ import annotations

import pygame

from survival_sandbox_ai.game import build_headless_test_game


def test_keydown_queues_eat_action() -> None:
    game = build_headless_test_game(seed=7, forced_action="wander")
    game.world.player.inventory.berries = 2
    game.world.player.hunger = 80.0

    pygame.event.post(pygame.event.Event(pygame.KEYDOWN, key=pygame.K_q))
    game._handle_events()
    intent = game._intent_from_pressed(pygame.key.get_pressed())
    game.world.update(0.1, intent, game.mind)
    game.shutdown()

    assert game.world.player.inventory.berries == 1
    assert game.world.player.hunger < 80.0
