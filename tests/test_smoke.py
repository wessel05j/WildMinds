from __future__ import annotations

from survival_sandbox_ai.game import build_headless_test_game


def test_headless_game_smoke() -> None:
    game = build_headless_test_game(seed=11, forced_action="wander")
    result = game.run_for_frames(frames=20)
    assert result["frames"] == 20
    assert result["creatures_alive"] > 0
    assert result["player_health"] > 0
