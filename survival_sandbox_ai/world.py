from __future__ import annotations

import math
import random
from dataclasses import dataclass
from typing import Iterable

import pygame

from .entities import (
    CREATURE_COLORS,
    RESOURCE_COLORS,
    SCREEN_HEIGHT,
    SCREEN_WIDTH,
    WORLD_HEIGHT,
    WORLD_WIDTH,
    AIAction,
    Campfire,
    Creature,
    Inventory,
    Player,
    ResourceNode,
)


@dataclass(slots=True)
class PlayerIntent:
    move: pygame.Vector2
    gather: bool = False
    attack: bool = False
    eat: bool = False
    craft_campfire: bool = False


@dataclass(slots=True)
class TickResult:
    status_message: str = ""


class SandboxWorld:
    NAME_POOLS = {
        "wolf": ["Ashfang", "Greyhide", "Needletooth", "Frostbite", "Emberjaw", "Murkfang"],
        "boar": ["Brambleback", "Ironsnout", "Rootmaw", "Mudtusk", "Thornhide", "Rumblehog"],
        "scavenger": ["Rook", "Mira", "Patch", "Sable", "Kest", "Tarn"],
    }

    def __init__(self, seed: int = 7) -> None:
        self.rng = random.Random(seed)
        self.elapsed_time = 0.0
        self.day_length = 140.0
        self.status_message = "Gather berries, wood, and stone. Survive the night."
        self.message_timer = 4.0
        self.controls_hint_timer = 14.0
        self.player = Player(
            identifier="player",
            position=pygame.Vector2(WORLD_WIDTH / 2, WORLD_HEIGHT / 2),
            velocity=pygame.Vector2(),
            radius=18.0,
            speed=210.0,
            health=100.0,
            max_health=100.0,
        )
        self.resources = self._spawn_resources()
        self.campfires: list[Campfire] = []
        self.creatures = self._spawn_creatures()
        self.terrain_surface = self._build_terrain_surface()

    @property
    def time_ratio(self) -> float:
        return (self.elapsed_time % self.day_length) / self.day_length

    @property
    def time_label(self) -> str:
        phase = self.time_ratio
        if phase < 0.25:
            return "morning"
        if phase < 0.55:
            return "day"
        if phase < 0.75:
            return "evening"
        return "night"

    @property
    def is_night(self) -> bool:
        return self.time_label == "night"

    def _spawn_resources(self) -> list[ResourceNode]:
        resources: list[ResourceNode] = []
        index = 0
        for kind, count in (("berries", 14), ("wood", 12), ("stone", 9)):
            for _ in range(count):
                resources.append(
                    ResourceNode(
                        identifier=f"{kind}-{index}",
                        kind=kind,
                        position=pygame.Vector2(
                            self.rng.randint(120, WORLD_WIDTH - 120),
                            self.rng.randint(120, WORLD_HEIGHT - 120),
                        ),
                        amount=self.rng.randint(3, 6),
                    )
                )
                index += 1
        return resources

    def _spawn_creatures(self) -> list[Creature]:
        creatures: list[Creature] = []
        layout = [
            ("scavenger", 3, 72.0, 95.0, 42.0),
            ("wolf", 2, 108.0, 100.0, 35.0),
            ("boar", 2, 94.0, 110.0, 25.0),
        ]
        counter = 0
        used_names: dict[str, list[str]] = {species: [] for species in self.NAME_POOLS}
        for species, count, speed, health, aggression in layout:
            for _ in range(count):
                position = pygame.Vector2(
                    self.rng.randint(150, WORLD_WIDTH - 150),
                    self.rng.randint(150, WORLD_HEIGHT - 150),
                )
                creature = Creature(
                    identifier=f"{species}-{counter}",
                    species=species,
                    name=self._next_name(species, used_names[species]),
                    personality=self._personality_for(species),
                    position=position,
                    velocity=pygame.Vector2(),
                    radius=16.0 if species == "wolf" else 18.0,
                    speed=speed,
                    health=health,
                    max_health=health,
                    hunger=self.rng.uniform(15.0, 40.0),
                    energy=self.rng.uniform(50.0, 95.0),
                    fear=self.rng.uniform(5.0, 35.0),
                    aggression=aggression,
                )
                creature.roam_goal = self._random_point()
                creature.think_cooldown = self.rng.uniform(0.2, 1.4)
                creature.remember("Spawned into a dangerous map.")
                creatures.append(creature)
                counter += 1
        return creatures

    def _next_name(self, species: str, used_names: list[str]) -> str:
        pool = self.NAME_POOLS.get(species, [species.title()])
        available = [name for name in pool if name not in used_names]
        if not available:
            name = f"{species.title()} {len(used_names) + 1}"
        else:
            name = self.rng.choice(available)
        used_names.append(name)
        return name

    def _personality_for(self, species: str) -> str:
        if species == "scavenger":
            return self.rng.choice(["greedy and careful", "opportunistic and tense", "bold and sneaky"])
        if species == "wolf":
            return self.rng.choice(["pack-minded hunter", "patient stalker", "territorial predator"])
        return self.rng.choice(["territorial bruiser", "restless charger", "stubborn forager"])

    def _random_point(self) -> pygame.Vector2:
        return pygame.Vector2(
            self.rng.randint(80, WORLD_WIDTH - 80),
            self.rng.randint(80, WORLD_HEIGHT - 80),
        )

    def _build_terrain_surface(self) -> pygame.Surface:
        surface = pygame.Surface((WORLD_WIDTH, WORLD_HEIGHT))
        surface.fill((62, 104, 66))

        for _ in range(340):
            center = (
                self.rng.randint(0, WORLD_WIDTH),
                self.rng.randint(0, WORLD_HEIGHT),
            )
            radius = self.rng.randint(22, 86)
            color = self.rng.choice(
                [
                    (74, 118, 76),
                    (79, 126, 82),
                    (56, 95, 60),
                    (88, 129, 74),
                ]
            )
            pygame.draw.circle(surface, color, center, radius)

        for _ in range(24):
            start = pygame.Vector2(
                self.rng.randint(0, WORLD_WIDTH),
                self.rng.randint(0, WORLD_HEIGHT),
            )
            end = start + pygame.Vector2(
                self.rng.randint(-260, 260),
                self.rng.randint(-260, 260),
            )
            color = self.rng.choice([(92, 88, 58), (104, 96, 63), (118, 112, 72)])
            pygame.draw.line(surface, color, start, end, self.rng.randint(18, 34))

        for _ in range(14):
            pond = pygame.Surface((220, 160), pygame.SRCALPHA)
            pond.fill((0, 0, 0, 0))
            pygame.draw.ellipse(pond, (42, 86, 98, 180), pond.get_rect())
            pygame.draw.ellipse(pond, (74, 126, 136, 80), pond.get_rect().inflate(-26, -20))
            position = (
                self.rng.randint(50, WORLD_WIDTH - 270),
                self.rng.randint(50, WORLD_HEIGHT - 210),
            )
            surface.blit(pond, position)

        return surface

    def nearby_resource(self, position: pygame.Vector2, radius: float = 50.0) -> ResourceNode | None:
        options = [
            resource
            for resource in self.resources
            if resource.available and resource.position.distance_to(position) <= radius
        ]
        if not options:
            return None
        return min(options, key=lambda item: item.position.distance_to(position))

    def nearby_campfire(self, position: pygame.Vector2, radius: float = 90.0) -> Campfire | None:
        options = [
            campfire
            for campfire in self.campfires
            if campfire.alive and campfire.position.distance_to(position) <= radius
        ]
        if not options:
            return None
        return min(options, key=lambda item: item.position.distance_to(position))

    def nearest_resource_of_kind(self, kind: str, position: pygame.Vector2) -> ResourceNode | None:
        candidates = [resource for resource in self.resources if resource.available and resource.kind == kind]
        if not candidates:
            candidates = [resource for resource in self.resources if resource.available]
        if not candidates:
            return None
        return min(candidates, key=lambda item: item.position.distance_to(position))

    def nearest_creature(
        self, position: pygame.Vector2, creatures: Iterable[Creature], species: str | None = None
    ) -> Creature | None:
        options = [creature for creature in creatures if creature.alive]
        if species is not None:
            options = [creature for creature in options if creature.species == species]
        if not options:
            return None
        return min(options, key=lambda item: item.position.distance_to(position))

    def _announce(self, message: str, *, duration: float = 2.8, player_message: bool = False) -> None:
        self.status_message = message
        self.message_timer = duration
        if player_message:
            self.player.last_message = message

    def _resource_name(self, kind: str, amount: int = 1) -> str:
        if kind == "berries":
            return "berry" if amount == 1 else "berries"
        return kind

    def update(self, dt: float, player_intent: PlayerIntent, brain: object) -> TickResult:
        self.elapsed_time += dt
        self.message_timer = max(0.0, self.message_timer - dt)
        self.controls_hint_timer = max(0.0, self.controls_hint_timer - dt)
        if self.message_timer <= 0:
            self.player.last_message = ""
            self.status_message = ""

        self._update_resources(dt)
        self._update_campfires(dt)
        self._update_player(dt, player_intent)
        self._update_creatures(dt, brain)
        self.creatures = [creature for creature in self.creatures if creature.alive]

        if self.player.health <= 0:
            self._announce("You were overwhelmed. Close the window and relaunch to try again.", duration=10.0)
        elif not self.status_message and not self.player.last_message:
            self.status_message = f"{self.time_label.title()} light. Stay fed and keep moving."

        return TickResult(status_message=self.status_message)

    def _update_resources(self, dt: float) -> None:
        for resource in self.resources:
            if resource.available:
                continue
            resource.respawn_timer -= dt
            if resource.respawn_timer <= 0:
                resource.amount = resource.respawn_amount
                resource.respawn_timer = 0.0

    def _update_campfires(self, dt: float) -> None:
        for campfire in self.campfires:
            if not campfire.alive:
                continue
            campfire.fuel -= dt * (1.2 if self.is_night else 0.65)
            if campfire.position.distance_to(self.player.position) <= campfire.warmth_radius:
                self.player.energy = min(100.0, self.player.energy + dt * 6.0)
                self.player.health = min(self.player.max_health, self.player.health + dt * 1.2)

    def _update_player(self, dt: float, intent: PlayerIntent) -> None:
        player = self.player
        move = intent.move
        if move.length_squared() > 0:
            move = move.normalize()
            player.facing = move
            player.velocity = move * player.speed
            player.energy = max(0.0, player.energy - dt * 5.0)
        else:
            player.velocity *= 0.8
            player.energy = min(100.0, player.energy + dt * 4.0)

        player.position += player.velocity * dt
        player.position.x = max(player.radius, min(WORLD_WIDTH - player.radius, player.position.x))
        player.position.y = max(player.radius, min(WORLD_HEIGHT - player.radius, player.position.y))

        player.hunger = min(100.0, player.hunger + dt * 1.8)
        if self.is_night:
            player.energy = max(0.0, player.energy - dt * 1.3)
        if player.hunger > 85:
            player.health = max(0.0, player.health - dt * 2.8)
        if player.energy <= 0:
            player.health = max(0.0, player.health - dt * 2.0)

        player.attack_cooldown = max(0.0, player.attack_cooldown - dt)
        player.gather_cooldown = max(0.0, player.gather_cooldown - dt)
        player.eat_cooldown = max(0.0, player.eat_cooldown - dt)

        if intent.eat and player.eat_cooldown <= 0:
            if player.inventory.consume("berries", 1):
                player.hunger = max(0.0, player.hunger - 32.0)
                player.energy = min(100.0, player.energy + 6.0)
                player.eat_cooldown = 0.28
                self._announce("You ate a berry.", player_message=True)
            else:
                player.eat_cooldown = 0.2
                self._announce("You have no berries to eat.", duration=1.4)

        if intent.gather and player.gather_cooldown <= 0:
            resource = self.nearby_resource(player.position)
            if resource and resource.available:
                resource.amount -= 1
                player.inventory.add(resource.kind, 1)
                player.gather_cooldown = 0.35
                self._announce(f"Gathered 1 {self._resource_name(resource.kind)}.", player_message=True)
                if resource.amount <= 0:
                    resource.respawn_timer = resource.respawn_delay
            else:
                self._announce("Nothing close enough to gather.", duration=1.6)

        if intent.attack and player.attack_cooldown <= 0:
            self._player_attack()
            player.attack_cooldown = 0.6

        if intent.craft_campfire:
            self._craft_campfire()

    def _player_attack(self) -> None:
        target = None
        best_distance = 48.0
        for creature in self.creatures:
            if not creature.alive:
                continue
            distance = creature.position.distance_to(self.player.position)
            if distance < best_distance:
                best_distance = distance
                target = creature

        if target is None:
            self._announce("Your swing hit nothing.", duration=1.4)
            return

        damage = 18.0
        target.health = max(0.0, target.health - damage)
        target.fear = min(100.0, target.fear + 20.0)
        target.remember("The player hit me at close range.")
        self._announce(f"You hit {target.species} for {damage:.0f}.", player_message=True)
        if target.health <= 0:
            self.player.inventory.berries += 1
            self._announce(f"You dropped {target.species} and scavenged a berry.", duration=3.4, player_message=True)

    def _craft_campfire(self) -> None:
        if self.nearby_campfire(self.player.position, radius=70.0):
            self._announce("Too close to another campfire.", duration=1.8)
            return
        if not self.player.inventory.consume("wood", 2):
            self._announce("Need 2 wood to craft a campfire.", duration=1.8)
            return
        if not self.player.inventory.consume("stone", 1):
            self.player.inventory.wood += 2
            self._announce("Need 1 stone to craft a campfire.", duration=1.8)
            return
        self.campfires.append(Campfire(position=self.player.position.copy()))
        self._announce("Placed a campfire.", player_message=True)

    def _update_creatures(self, dt: float, brain: object) -> None:
        ready_decisions: dict[str, AIAction] = {}
        if hasattr(brain, "collect_ready_decisions"):
            ready_decisions = brain.collect_ready_decisions()

        for creature in self.creatures:
            if not creature.alive:
                continue

            if creature.identifier in ready_decisions:
                decision = ready_decisions[creature.identifier]
                creature.decision = decision
                creature.decision_pending = False
                creature.think_cooldown = self.rng.uniform(1.4, 2.8)
                creature.speech_timer = 0.0
                creature.remember(f"I chose {decision.action} because {decision.reason or 'it felt right'}.")
                if decision.action in {"wander", "guard"}:
                    creature.roam_goal = self._random_point()

            creature.think_cooldown -= dt
            creature.attack_cooldown = max(0.0, creature.attack_cooldown - dt)
            creature.hunger = min(100.0, creature.hunger + dt * 1.35)
            creature.energy = max(0.0, min(100.0, creature.energy - dt * 1.1))
            if creature.hunger > 80:
                creature.health = max(0.0, creature.health - dt * 1.1)
            if self.is_night and self.nearby_campfire(creature.position):
                creature.energy = min(100.0, creature.energy + dt * 5.0)

            snapshot = self.snapshot_for_creature(creature)
            if creature.ai_enabled and creature.think_cooldown <= 0:
                if hasattr(brain, "request_decision"):
                    if not creature.decision_pending:
                        requested = brain.request_decision(creature, snapshot)
                        if requested:
                            creature.decision_pending = True
                else:
                    decision = brain.decide(creature, snapshot)
                    creature.decision = decision
                    creature.think_cooldown = self.rng.uniform(1.4, 2.8)
                    creature.remember(f"I chose {decision.action} because {decision.reason or 'it felt right'}.")
                    if decision.action in {"wander", "guard"}:
                        creature.roam_goal = self._random_point()

            self._apply_creature_decision(creature, dt)

    def snapshot_for_creature(self, creature: Creature) -> dict[str, object]:
        player_distance = creature.position.distance_to(self.player.position)
        nearby_creatures = []
        for other in self.creatures:
            if other.identifier == creature.identifier or not other.alive:
                continue
            distance = creature.position.distance_to(other.position)
            if distance <= 260:
                nearby_creatures.append(
                    {
                        "id": other.identifier,
                        "species": other.species,
                        "distance": distance,
                        "health": other.health,
                    }
                )
        nearby_creatures.sort(key=lambda item: item["distance"])

        nearby_resources = []
        for resource in self.resources:
            if not resource.available:
                continue
            distance = creature.position.distance_to(resource.position)
            if distance <= 280:
                nearby_resources.append(
                    {
                        "id": resource.identifier,
                        "kind": resource.kind,
                        "distance": distance,
                        "amount": resource.amount,
                    }
                )
        nearby_resources.sort(key=lambda item: item["distance"])

        return {
            "time_label": self.time_label,
            "player": {
                "distance": player_distance,
                "health": self.player.health,
                "near_campfire": self.nearby_campfire(self.player.position) is not None,
            },
            "nearby_creatures": nearby_creatures[:4],
            "nearby_resources": nearby_resources[:4],
        }

    def _move_towards(self, actor: Creature, target: pygame.Vector2, dt: float, speed_scale: float = 1.0) -> None:
        direction = target - actor.position
        if direction.length_squared() > 0.01:
            direction = direction.normalize()
            actor.velocity = direction * actor.speed * speed_scale
            actor.position += actor.velocity * dt
        else:
            actor.velocity *= 0.8
        actor.position.x = max(actor.radius, min(WORLD_WIDTH - actor.radius, actor.position.x))
        actor.position.y = max(actor.radius, min(WORLD_HEIGHT - actor.radius, actor.position.y))

    def _move_away_from(self, actor: Creature, threat: pygame.Vector2, dt: float) -> None:
        direction = actor.position - threat
        if direction.length_squared() == 0:
            direction = pygame.Vector2(1, 0)
        actor.velocity = direction.normalize() * actor.speed
        actor.position += actor.velocity * dt
        actor.position.x = max(actor.radius, min(WORLD_WIDTH - actor.radius, actor.position.x))
        actor.position.y = max(actor.radius, min(WORLD_HEIGHT - actor.radius, actor.position.y))

    def _apply_creature_decision(self, creature: Creature, dt: float) -> None:
        action = creature.decision.action

        if action == "rest":
            creature.velocity *= 0.75
            creature.energy = min(100.0, creature.energy + dt * 7.0)
            if self.nearby_campfire(creature.position):
                creature.health = min(creature.max_health, creature.health + dt * 0.8)
            return

        if action == "flee":
            self._move_away_from(creature, self.player.position, dt)
            creature.energy = max(0.0, creature.energy - dt * 2.0)
            return

        if action == "forage":
            target_resource = self.nearest_resource_of_kind(creature.decision.target, creature.position)
            if target_resource is None:
                creature.roam_goal = self._random_point()
                self._move_towards(creature, creature.roam_goal, dt, 0.7)
                return
            self._move_towards(creature, target_resource.position, dt, 0.95)
            if creature.position.distance_to(target_resource.position) <= target_resource.radius + creature.radius + 4:
                target_resource.amount -= 1
                creature.hunger = max(0.0, creature.hunger - 28.0)
                creature.energy = min(100.0, creature.energy + 6.0)
                creature.remember(f"Foraged {target_resource.kind}.")
                if target_resource.amount <= 0:
                    target_resource.respawn_timer = target_resource.respawn_delay
            return

        if action == "stalk":
            to_player = self.player.position - creature.position
            if to_player.length_squared() > 0:
                distance = to_player.length()
                if distance > 120:
                    self._move_towards(creature, self.player.position, dt, 0.8)
                else:
                    side = pygame.Vector2(-to_player.y, to_player.x).normalize()
                    self._move_towards(creature, creature.position + side * 60, dt, 0.6)
            return

        if action == "attack":
            speed_scale = 1.25 if creature.species == "wolf" else 1.1
            reach_bonus = 16 if creature.species == "wolf" else 10
            self._move_towards(creature, self.player.position, dt, speed_scale)
            if creature.position.distance_to(self.player.position) <= creature.radius + self.player.radius + reach_bonus:
                if creature.attack_cooldown <= 0:
                    damage = 12.0 + creature.aggression * 0.06
                    self.player.health = max(0.0, self.player.health - damage)
                    attacker_label = f"{creature.name} the {creature.species}"
                    self._announce(f"{attacker_label.title()} hit you for {damage:.0f}.", duration=1.8, player_message=True)
                    creature.attack_cooldown = 0.85 if creature.species == "wolf" else 1.0
                    creature.think_cooldown = max(creature.think_cooldown, 1.8)
                    creature.remember("I landed a hit on the player.")
            return

        if action == "guard":
            target = self.nearby_campfire(self.player.position) or self.nearest_resource_of_kind("berries", creature.position)
            if isinstance(target, Campfire):
                self._move_towards(creature, target.position, dt, 0.7)
            elif isinstance(target, ResourceNode):
                self._move_towards(creature, target.position, dt, 0.7)
            else:
                self._move_towards(creature, creature.roam_goal, dt, 0.6)
            return

        if creature.roam_goal.distance_to(creature.position) < 32:
            creature.roam_goal = self._random_point()
        wander_target = creature.roam_goal
        if creature.species == "wolf" and self.player.position.distance_to(creature.position) < 260:
            wander_target = self.player.position.lerp(creature.roam_goal, 0.35)
        self._move_towards(creature, wander_target, dt, 0.55)

    def camera_rect(self) -> pygame.Rect:
        left = int(self.player.position.x - SCREEN_WIDTH / 2)
        top = int(self.player.position.y - SCREEN_HEIGHT / 2)
        left = max(0, min(WORLD_WIDTH - SCREEN_WIDTH, left))
        top = max(0, min(WORLD_HEIGHT - SCREEN_HEIGHT, top))
        return pygame.Rect(left, top, SCREEN_WIDTH, SCREEN_HEIGHT)

    def draw(self, screen: pygame.Surface, fonts: dict[str, pygame.font.Font], ai_summary: str = "") -> None:
        camera = self.camera_rect()
        self._draw_background(screen, camera)

        for resource in self.resources:
            if not resource.available:
                continue
            self._draw_resource_node(screen, camera, resource, fonts)

        for campfire in self.campfires:
            if not campfire.alive:
                continue
            self._draw_campfire(screen, camera, campfire)

        for creature in sorted(self.creatures, key=lambda item: item.position.y):
            self._draw_creature(screen, camera, creature)

        self._draw_player(screen, camera)

        self._draw_hud(screen, fonts)
        self._draw_action_log(screen, fonts, camera, ai_summary)

    def _draw_background(self, screen: pygame.Surface, camera: pygame.Rect) -> None:
        screen.blit(self.terrain_surface, (0, 0), camera)

        shade = pygame.Surface((SCREEN_WIDTH, SCREEN_HEIGHT), pygame.SRCALPHA)
        if self.is_night:
            shade.fill((14, 20, 34, 110))
            moon_glow = pygame.Surface((SCREEN_WIDTH, SCREEN_HEIGHT), pygame.SRCALPHA)
            pygame.draw.circle(moon_glow, (88, 123, 164, 54), (-120, -80), 520)
            screen.blit(moon_glow, (0, 0))
        else:
            shade.fill((245, 214, 162, 18))
        screen.blit(shade, (0, 0))

    def _screen_position(self, camera: pygame.Rect, position: pygame.Vector2) -> pygame.Vector2:
        return pygame.Vector2(position.x - camera.left, position.y - camera.top)

    def _draw_shadow(self, screen: pygame.Surface, screen_pos: pygame.Vector2, width: int, height: int) -> None:
        shadow = pygame.Surface((width * 2, height * 2), pygame.SRCALPHA)
        pygame.draw.ellipse(shadow, (8, 12, 8, 70), shadow.get_rect())
        screen.blit(shadow, shadow.get_rect(center=(screen_pos.x, screen_pos.y + 10)))

    def _shift_color(self, color: tuple[int, int, int], amount: int) -> tuple[int, int, int]:
        return tuple(max(0, min(255, channel + amount)) for channel in color)

    def _oriented_points(
        self,
        center: pygame.Vector2,
        heading: pygame.Vector2,
        side: pygame.Vector2,
        points: list[tuple[float, float]],
    ) -> list[tuple[float, float]]:
        return [
            (
                center.x + heading.x * forward + side.x * lateral,
                center.y + heading.y * forward + side.y * lateral,
            )
            for forward, lateral in points
        ]

    def _draw_wolf_sprite(
        self, screen: pygame.Surface, center: pygame.Vector2, heading: pygame.Vector2, side: pygame.Vector2
    ) -> None:
        fur = CREATURE_COLORS["wolf"]
        outline = self._shift_color(fur, -48)
        belly = self._shift_color(fur, 20)
        ears = self._shift_color(fur, -24)

        body = self._oriented_points(
            center,
            heading,
            side,
            [
                (-20, -8),
                (-8, -11),
                (8, -11),
                (20, -7),
                (25, -3),
                (26, 0),
                (25, 3),
                (20, 7),
                (8, 11),
                (-8, 11),
                (-20, 8),
                (-28, 3),
                (-30, 0),
                (-28, -3),
            ],
        )
        muzzle = self._oriented_points(center, heading, side, [(22, -4), (33, -3), (37, 0), (33, 3), (22, 4)])
        back_patch = self._oriented_points(center, heading, side, [(-16, -4), (-4, -7), (12, -7), (8, 0), (-12, 1)])
        tail = self._oriented_points(center, heading, side, [(-28, -2), (-40, -6), (-36, 2)])

        pygame.draw.polygon(screen, fur, body)
        pygame.draw.polygon(screen, outline, body, 2)
        pygame.draw.polygon(screen, belly, back_patch)
        pygame.draw.polygon(screen, fur, muzzle)
        pygame.draw.polygon(screen, outline, muzzle, 2)
        pygame.draw.polygon(screen, fur, tail)
        pygame.draw.polygon(screen, outline, tail, 2)

        ear_left = self._oriented_points(center, heading, side, [(17, -5), (13, -10), (21, -9)])
        ear_right = self._oriented_points(center, heading, side, [(17, 5), (13, 10), (21, 9)])
        pygame.draw.polygon(screen, ears, ear_left)
        pygame.draw.polygon(screen, ears, ear_right)

        for forward in (-12, -2, 9, 18):
            start = self._oriented_points(center, heading, side, [(forward, -6)])[0]
            end = self._oriented_points(center, heading, side, [(forward - 4, -9)])[0]
            pygame.draw.line(screen, outline, start, end, 3)
            start = self._oriented_points(center, heading, side, [(forward, 6)])[0]
            end = self._oriented_points(center, heading, side, [(forward - 4, 9)])[0]
            pygame.draw.line(screen, outline, start, end, 3)

        eye = self._oriented_points(center, heading, side, [(28, 2)])[0]
        nose = self._oriented_points(center, heading, side, [(36, 0)])[0]
        pygame.draw.circle(screen, (22, 22, 24), eye, 2)
        pygame.draw.circle(screen, (30, 25, 25), nose, 2)

    def _draw_boar_sprite(
        self, screen: pygame.Surface, center: pygame.Vector2, heading: pygame.Vector2, side: pygame.Vector2
    ) -> None:
        fur = CREATURE_COLORS["boar"]
        outline = self._shift_color(fur, -46)
        back = self._shift_color(fur, 12)

        body = self._oriented_points(
            center,
            heading,
            side,
            [
                (-22, -11),
                (-10, -15),
                (10, -14),
                (24, -10),
                (31, -4),
                (33, 0),
                (31, 4),
                (24, 10),
                (10, 14),
                (-10, 15),
                (-22, 11),
                (-30, 5),
                (-32, 0),
                (-30, -5),
            ],
        )
        snout = self._oriented_points(center, heading, side, [(29, -6), (40, -5), (45, 0), (40, 5), (29, 6)])
        mane = self._oriented_points(center, heading, side, [(-18, 0), (-6, -3), (8, -4), (18, -2), (18, 2), (8, 4), (-6, 3)])
        tail = self._oriented_points(center, heading, side, [(-31, -1), (-40, -5), (-38, 1)])

        pygame.draw.polygon(screen, fur, body)
        pygame.draw.polygon(screen, outline, body, 2)
        pygame.draw.polygon(screen, self._shift_color(back, -10), mane)
        pygame.draw.polygon(screen, fur, snout)
        pygame.draw.polygon(screen, outline, snout, 2)
        pygame.draw.polygon(screen, fur, tail)

        tusk_left_start = self._oriented_points(center, heading, side, [(38, -4)])[0]
        tusk_left_end = self._oriented_points(center, heading, side, [(45, -8)])[0]
        tusk_right_start = self._oriented_points(center, heading, side, [(38, 4)])[0]
        tusk_right_end = self._oriented_points(center, heading, side, [(45, 8)])[0]
        pygame.draw.line(screen, (236, 232, 222), tusk_left_start, tusk_left_end, 3)
        pygame.draw.line(screen, (236, 232, 222), tusk_right_start, tusk_right_end, 3)

        for forward in (-12, 0, 12, 22):
            start = self._oriented_points(center, heading, side, [(forward, -7)])[0]
            end = self._oriented_points(center, heading, side, [(forward - 2, -12)])[0]
            pygame.draw.line(screen, outline, start, end, 4)
            start = self._oriented_points(center, heading, side, [(forward, 7)])[0]
            end = self._oriented_points(center, heading, side, [(forward - 2, 12)])[0]
            pygame.draw.line(screen, outline, start, end, 4)

        eye = self._oriented_points(center, heading, side, [(31, 3)])[0]
        nostril_a = self._oriented_points(center, heading, side, [(42, -2)])[0]
        nostril_b = self._oriented_points(center, heading, side, [(42, 2)])[0]
        pygame.draw.circle(screen, (24, 18, 16), eye, 2)
        pygame.draw.circle(screen, (24, 18, 16), nostril_a, 2)
        pygame.draw.circle(screen, (24, 18, 16), nostril_b, 2)

    def _draw_scavenger_sprite(
        self, screen: pygame.Surface, center: pygame.Vector2, heading: pygame.Vector2, side: pygame.Vector2
    ) -> None:
        coat = CREATURE_COLORS["scavenger"]
        outline = self._shift_color(coat, -58)
        hood = self._shift_color(coat, -16)
        trim = self._shift_color(coat, 24)

        cloak = self._oriented_points(
            center,
            heading,
            side,
            [
                (-18, -10),
                (-6, -14),
                (7, -12),
                (18, -4),
                (18, 4),
                (7, 12),
                (-6, 14),
                (-18, 10),
                (-24, 0),
            ],
        )
        hood_rect = pygame.Rect(0, 0, 20, 18)
        hood_rect.center = self._oriented_points(center, heading, side, [(10, 0)])[0]
        bag_rect = pygame.Rect(0, 0, 12, 12)
        bag_rect.center = self._oriented_points(center, heading, side, [(-2, 9)])[0]

        pygame.draw.polygon(screen, coat, cloak)
        pygame.draw.polygon(screen, outline, cloak, 2)
        pygame.draw.ellipse(screen, hood, hood_rect)
        pygame.draw.ellipse(screen, outline, hood_rect, 2)
        pygame.draw.rect(screen, (111, 76, 48), bag_rect, border_radius=4)
        pygame.draw.rect(screen, (74, 48, 28), bag_rect, width=2, border_radius=4)

        arm_left_start = self._oriented_points(center, heading, side, [(2, -9)])[0]
        arm_left_end = self._oriented_points(center, heading, side, [(12, -14)])[0]
        arm_right_start = self._oriented_points(center, heading, side, [(2, 9)])[0]
        arm_right_end = self._oriented_points(center, heading, side, [(12, 14)])[0]
        leg_left_start = self._oriented_points(center, heading, side, [(-11, -5)])[0]
        leg_left_end = self._oriented_points(center, heading, side, [(-22, -8)])[0]
        leg_right_start = self._oriented_points(center, heading, side, [(-11, 5)])[0]
        leg_right_end = self._oriented_points(center, heading, side, [(-22, 8)])[0]
        pygame.draw.line(screen, outline, arm_left_start, arm_left_end, 4)
        pygame.draw.line(screen, outline, arm_right_start, arm_right_end, 4)
        pygame.draw.line(screen, outline, leg_left_start, leg_left_end, 4)
        pygame.draw.line(screen, outline, leg_right_start, leg_right_end, 4)

        face = self._oriented_points(center, heading, side, [(13, 0)])[0]
        eye_a = self._oriented_points(center, heading, side, [(15, -3)])[0]
        eye_b = self._oriented_points(center, heading, side, [(15, 3)])[0]
        scarf = self._oriented_points(center, heading, side, [(-2, -4), (8, -5), (9, 5), (-2, 4)])
        pygame.draw.polygon(screen, trim, scarf)
        pygame.draw.circle(screen, (238, 218, 174), face, 5)
        pygame.draw.circle(screen, (30, 24, 20), eye_a, 2)
        pygame.draw.circle(screen, (30, 24, 20), eye_b, 2)

    def _draw_resource_node(
        self, screen: pygame.Surface, camera: pygame.Rect, resource: ResourceNode, fonts: dict[str, pygame.font.Font]
    ) -> None:
        screen_pos = self._screen_position(camera, resource.position)
        self._draw_shadow(screen, screen_pos, 22, 10)

        if resource.kind == "berries":
            leaf = (92, 152, 92)
            for offset in (pygame.Vector2(-8, 2), pygame.Vector2(0, -4), pygame.Vector2(8, 4), pygame.Vector2(3, 10)):
                pygame.draw.circle(screen, RESOURCE_COLORS["berries"], screen_pos + offset, 7)
            pygame.draw.ellipse(screen, leaf, pygame.Rect(screen_pos.x - 3, screen_pos.y - 15, 12, 6))
        elif resource.kind == "wood":
            for y_offset in (-4, 4):
                body = pygame.Rect(screen_pos.x - 16, screen_pos.y - 5 + y_offset, 32, 10)
                pygame.draw.rect(screen, (132, 86, 52), body, border_radius=4)
                pygame.draw.circle(screen, (164, 116, 78), (body.left + 4, body.centery), 4)
                pygame.draw.circle(screen, (164, 116, 78), (body.right - 4, body.centery), 4)
        else:
            pygame.draw.polygon(
                screen,
                (122, 132, 145),
                [
                    (screen_pos.x - 14, screen_pos.y + 8),
                    (screen_pos.x - 8, screen_pos.y - 10),
                    (screen_pos.x + 2, screen_pos.y - 14),
                    (screen_pos.x + 12, screen_pos.y - 6),
                    (screen_pos.x + 14, screen_pos.y + 8),
                    (screen_pos.x + 2, screen_pos.y + 14),
                ],
            )
            pygame.draw.polygon(
                screen,
                (156, 166, 178),
                [
                    (screen_pos.x - 2, screen_pos.y - 10),
                    (screen_pos.x + 8, screen_pos.y - 5),
                    (screen_pos.x + 2, screen_pos.y + 4),
                    (screen_pos.x - 6, screen_pos.y + 2),
                ],
            )

        if resource.position.distance_to(self.player.position) < 100:
            badge = fonts["small"].render(str(resource.amount), True, (23, 24, 28), (245, 232, 196))
            screen.blit(badge, badge.get_rect(center=(screen_pos.x + 18, screen_pos.y - 16)))

    def _draw_campfire(self, screen: pygame.Surface, camera: pygame.Rect, campfire: Campfire) -> None:
        screen_pos = self._screen_position(camera, campfire.position)
        self._draw_shadow(screen, screen_pos, 24, 10)
        glow = pygame.Surface((120, 120), pygame.SRCALPHA)
        pygame.draw.circle(glow, (255, 156, 52, 50), (60, 60), 54)
        screen.blit(glow, glow.get_rect(center=(screen_pos.x, screen_pos.y)))
        pygame.draw.circle(screen, (84, 60, 44), screen_pos, 16)
        pygame.draw.circle(screen, (246, 128, 48), screen_pos, 10)
        pygame.draw.circle(screen, (255, 208, 108), (screen_pos.x, screen_pos.y - 2), 5)

    def _draw_creature(self, screen: pygame.Surface, camera: pygame.Rect, creature: Creature) -> None:
        screen_pos = self._screen_position(camera, creature.position)
        self._draw_shadow(screen, screen_pos, 30, 11)

        heading = creature.velocity.normalize() if creature.velocity.length_squared() > 0.01 else pygame.Vector2(1, 0)
        side = pygame.Vector2(-heading.y, heading.x)
        seed = sum(ord(char) for char in creature.identifier) * 0.17
        move_amount = min(1.0, creature.velocity.length() / max(creature.speed, 1.0))
        bob = math.sin(self.elapsed_time * 8.0 + seed) * 1.6 * move_amount
        body_pos = screen_pos + pygame.Vector2(0, bob)

        if creature.species == "wolf":
            self._draw_wolf_sprite(screen, body_pos, heading, side)
        elif creature.species == "boar":
            self._draw_boar_sprite(screen, body_pos, heading, side)
        else:
            self._draw_scavenger_sprite(screen, body_pos, heading, side)

        action_color = {
            "attack": (213, 78, 73),
            "forage": (114, 182, 92),
            "flee": (94, 154, 210),
            "stalk": (232, 181, 79),
        }.get(creature.decision.action, (202, 216, 184))
        pygame.draw.circle(screen, action_color, body_pos, int(creature.radius) + 5, 2)
        if creature.decision_pending:
            pulse_radius = int(creature.radius + 9 + abs(math.sin(self.elapsed_time * 5 + seed)) * 3)
            pygame.draw.circle(screen, (244, 218, 120), body_pos, pulse_radius, 2)

    def _draw_player(self, screen: pygame.Surface, camera: pygame.Rect) -> None:
        player_pos = self._screen_position(camera, self.player.position)
        self._draw_shadow(screen, player_pos, 26, 12)

        heading = self.player.facing.normalize() if self.player.facing.length_squared() > 0 else pygame.Vector2(1, 0)
        side = pygame.Vector2(-heading.y, heading.x)
        move_amount = min(1.0, self.player.velocity.length() / max(self.player.speed, 1.0))
        bob = math.sin(self.elapsed_time * 9.0) * 2.0 * move_amount
        body_pos = player_pos + pygame.Vector2(0, bob)

        pygame.draw.circle(screen, (68, 168, 248), body_pos, int(self.player.radius))
        pygame.draw.circle(screen, (132, 208, 255), body_pos + pygame.Vector2(-4, -6), 6)
        backpack = pygame.Rect(0, 0, 14, 12)
        backpack.center = (body_pos.x - heading.x * 8, body_pos.y - heading.y * 8 + 2)
        pygame.draw.rect(screen, (64, 86, 108), backpack, border_radius=4)
        scarf_start = body_pos + side * 8
        scarf_end = scarf_start - heading * 12 - side * 5
        pygame.draw.line(screen, (255, 228, 132), scarf_start, scarf_end, 4)
        pygame.draw.line(screen, (219, 242, 255), body_pos, body_pos + heading * 22, 3)

    def _draw_progress_bar(
        self,
        screen: pygame.Surface,
        rect: pygame.Rect,
        label: str,
        value: float,
        color: tuple[int, int, int],
        fonts: dict[str, pygame.font.Font],
    ) -> None:
        pygame.draw.rect(screen, (24, 30, 34), rect, border_radius=8)
        fill_rect = rect.copy()
        fill_rect.width = int(rect.width * max(0.0, min(1.0, value / 100.0)))
        pygame.draw.rect(screen, color, fill_rect, border_radius=8)
        text = fonts["small"].render(f"{label} {value:>4.0f}", True, (240, 239, 232))
        screen.blit(text, text.get_rect(midleft=(rect.left + 10, rect.centery)))

    def _draw_inventory_row(
        self,
        screen: pygame.Surface,
        fonts: dict[str, pygame.font.Font],
        rect: pygame.Rect,
        label: str,
        amount: int,
        color: tuple[int, int, int],
        hint: str = "",
        emphasized: bool = False,
    ) -> None:
        fill = (28, 34, 38) if not emphasized else (52, 36, 43)
        border = (70, 83, 90) if not emphasized else (156, 94, 114)
        pygame.draw.rect(screen, fill, rect, border_radius=12)
        pygame.draw.rect(screen, border, rect, width=2, border_radius=12)
        pygame.draw.circle(screen, color, (rect.left + 18, rect.centery), 8)
        label_text = fonts["small"].render(label, True, (236, 235, 228))
        amount_text = fonts["small"].render(str(amount), True, (249, 248, 241))
        screen.blit(label_text, (rect.left + 34, rect.top + 6))
        screen.blit(amount_text, amount_text.get_rect(topright=(rect.right - 12, rect.top + 6)))
        if hint:
            hint_text = fonts["small"].render(hint, True, (205, 202, 194))
            screen.blit(hint_text, (rect.left + 34, rect.bottom - 22))

    def visible_creatures(self, camera: pygame.Rect) -> list[Creature]:
        padded = camera.inflate(90, 90)
        visible = [
            creature
            for creature in self.creatures
            if creature.alive and padded.collidepoint(creature.position.x, creature.position.y)
        ]
        visible.sort(key=lambda creature: creature.position.distance_to(self.player.position))
        return visible

    def visible_action_logs(self, camera: pygame.Rect) -> list[str]:
        visible = self.visible_creatures(camera)
        lines: list[str] = []
        for creature in visible[:6]:
            action = "thinking..." if creature.decision_pending else creature.decision.action
            lines.append(f"{creature.name} the {creature.species.title()} (Action): {action}")
        return lines

    def _draw_hud(self, screen: pygame.Surface, fonts: dict[str, pygame.font.Font]) -> None:
        panel = pygame.Rect(18, SCREEN_HEIGHT - 206, 370, 180)
        pygame.draw.rect(screen, (15, 20, 23, 210), panel, border_radius=18)
        pygame.draw.rect(screen, (84, 109, 103), panel, width=2, border_radius=18)

        title = fonts["medium"].render("Survivor Pack", True, (240, 239, 232))
        screen.blit(title, (32, SCREEN_HEIGHT - 198))

        self._draw_progress_bar(screen, pygame.Rect(32, SCREEN_HEIGHT - 164, 340, 18), "Health", self.player.health, (188, 82, 74), fonts)
        self._draw_progress_bar(screen, pygame.Rect(32, SCREEN_HEIGHT - 134, 340, 18), "Food", 100.0 - self.player.hunger, (222, 178, 72), fonts)
        self._draw_progress_bar(screen, pygame.Rect(32, SCREEN_HEIGHT - 104, 340, 18), "Energy", self.player.energy, (80, 160, 216), fonts)

        self._draw_inventory_row(
            screen,
            fonts,
            pygame.Rect(32, SCREEN_HEIGHT - 70, 150, 38),
            "Berries",
            self.player.inventory.berries,
            (212, 66, 112),
            hint="Q / 1 Eat",
            emphasized=self.player.inventory.berries > 0,
        )
        self._draw_inventory_row(
            screen,
            fonts,
            pygame.Rect(190, SCREEN_HEIGHT - 70, 86, 38),
            "Wood",
            self.player.inventory.wood,
            (129, 84, 48),
        )
        self._draw_inventory_row(
            screen,
            fonts,
            pygame.Rect(286, SCREEN_HEIGHT - 70, 86, 38),
            "Stone",
            self.player.inventory.stone,
            (122, 132, 145),
        )

        status = self.player.last_message or self.status_message
        if status:
            pill = pygame.Rect(18, SCREEN_HEIGHT - 200, max(240, min(520, 18 + len(status) * 8)), 28)
            pygame.draw.rect(screen, (18, 26, 32), pill, border_radius=14)
            pygame.draw.rect(screen, (116, 142, 152), pill, width=2, border_radius=14)
            status_text = fonts["small"].render(status[:72], True, (245, 231, 176))
            screen.blit(status_text, (pill.left + 12, pill.top + 4))

        if self.controls_hint_timer > 0:
            hint = "WASD Move   E Gather   Space Attack   Q / 1 Eat   F Campfire"
            hint_text = fonts["small"].render(hint, True, (232, 239, 228))
            hint_shadow = fonts["small"].render(hint, True, (16, 18, 20))
            x = (SCREEN_WIDTH - hint_text.get_width()) // 2
            y = SCREEN_HEIGHT - 26
            screen.blit(hint_shadow, (x + 1, y + 1))
            screen.blit(hint_text, (x, y))

    def _draw_action_log(
        self, screen: pygame.Surface, fonts: dict[str, pygame.font.Font], camera: pygame.Rect, ai_summary: str
    ) -> None:
        lines = self.visible_action_logs(camera)
        panel_height = 74 + max(1, len(lines)) * 26
        panel = pygame.Rect(SCREEN_WIDTH - 388, 18, 370, panel_height)
        pygame.draw.rect(screen, (15, 20, 23, 214), panel, border_radius=18)
        pygame.draw.rect(screen, (84, 109, 103), panel, width=2, border_radius=18)

        title = fonts["medium"].render("Visible Creature Decisions", True, (237, 238, 232))
        screen.blit(title, (panel.left + 16, panel.top + 14))

        runtime = fonts["small"].render(ai_summary[:44], True, (172, 197, 190))
        screen.blit(runtime, (panel.left + 16, panel.top + 42))

        if not lines:
            empty = fonts["small"].render("No creatures on screen.", True, (215, 214, 206))
            screen.blit(empty, (panel.left + 16, panel.top + 72))
            return

        y = panel.top + 72
        for line in lines:
            text = fonts["small"].render(line, True, (240, 239, 232))
            screen.blit(text, (panel.left + 16, y))
            y += 24
