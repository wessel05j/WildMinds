from __future__ import annotations

import pygame

from survival_sandbox_ai.ai import ScriptedMind
from survival_sandbox_ai.world import PlayerIntent, SandboxWorld


def test_gathering_adds_resource_to_inventory() -> None:
    world = SandboxWorld(seed=5)
    resource = world.resources[0]
    resource.kind = "berries"
    resource.amount = 3
    world.player.position = resource.position.copy()

    world.update(0.1, PlayerIntent(move=pygame.Vector2(), gather=True), ScriptedMind("wander"))
    assert world.player.inventory.berries == 1
    assert resource.amount == 2


def test_crafting_campfire_consumes_materials() -> None:
    world = SandboxWorld(seed=5)
    world.player.inventory.wood = 2
    world.player.inventory.stone = 1

    world.update(0.1, PlayerIntent(move=pygame.Vector2(), craft_campfire=True), ScriptedMind("wander"))
    assert len(world.campfires) == 1
    assert world.player.inventory.wood == 0
    assert world.player.inventory.stone == 0


def test_player_attack_damages_nearby_creature() -> None:
    world = SandboxWorld(seed=5)
    creature = world.creatures[0]
    creature.position = world.player.position + pygame.Vector2(20, 0)
    starting_health = creature.health

    world.update(0.1, PlayerIntent(move=pygame.Vector2(), attack=True), ScriptedMind("wander"))
    assert creature.health < starting_health


def test_player_can_eat_berries() -> None:
    world = SandboxWorld(seed=5)
    world.player.inventory.berries = 2
    world.player.hunger = 75.0

    world.update(0.1, PlayerIntent(move=pygame.Vector2(), eat=True), ScriptedMind("wander"))
    assert world.player.inventory.berries == 1
    assert world.player.hunger < 75.0


def test_eating_without_berries_does_not_change_hunger() -> None:
    world = SandboxWorld(seed=5)
    world.player.hunger = 70.0

    world.update(0.1, PlayerIntent(move=pygame.Vector2(), eat=True), ScriptedMind("wander"))
    assert world.player.inventory.berries == 0
    assert world.player.hunger >= 70.0


def test_forage_action_reduces_creature_hunger() -> None:
    world = SandboxWorld(seed=5)
    creature = world.creatures[0]
    berry_patch = next(resource for resource in world.resources if resource.kind == "berries")
    creature.position = berry_patch.position + pygame.Vector2(5, 0)
    creature.hunger = 80.0
    creature.think_cooldown = 0.0

    world.update(0.2, PlayerIntent(move=pygame.Vector2()), ScriptedMind("forage"))
    assert creature.hunger < 80.0


def test_snapshot_lists_close_threats_and_resources() -> None:
    world = SandboxWorld(seed=5)
    creature = world.creatures[0]
    resource = world.resources[0]
    creature.position = world.player.position + pygame.Vector2(40, 0)
    resource.position = creature.position + pygame.Vector2(30, 0)

    snapshot = world.snapshot_for_creature(creature)
    assert snapshot["player"]["distance"] < 50
    assert snapshot["nearby_resources"]


def test_player_move_updates_position() -> None:
    world = SandboxWorld(seed=5)
    start = world.player.position.copy()
    world.update(0.3, PlayerIntent(move=pygame.Vector2(1, 0)), ScriptedMind("wander"))
    assert world.player.position.x > start.x


def test_visible_action_logs_show_on_screen_creatures() -> None:
    world = SandboxWorld(seed=5)
    creature = world.creatures[0]
    creature.position = world.player.position + pygame.Vector2(30, 0)
    creature.decision.action = "attack"
    camera = world.camera_rect()
    logs = world.visible_action_logs(camera)
    assert any(creature.name in line and "attack" in line for line in logs)


def test_wolf_attack_can_damage_player_over_time() -> None:
    world = SandboxWorld(seed=5)
    wolf = next(creature for creature in world.creatures if creature.species == "wolf")
    wolf.position = world.player.position + pygame.Vector2(140, 0)
    wolf.decision.action = "attack"
    wolf.think_cooldown = 999.0
    start_health = world.player.health

    for _ in range(180):
        world.update(1 / 60, PlayerIntent(move=pygame.Vector2()), ScriptedMind("attack"))

    assert world.player.health < start_health
