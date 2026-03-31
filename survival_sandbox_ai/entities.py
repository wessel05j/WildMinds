from __future__ import annotations

from collections import deque
from dataclasses import dataclass, field
from typing import Deque

import pygame


SCREEN_WIDTH = 1280
SCREEN_HEIGHT = 720
WORLD_WIDTH = 2400
WORLD_HEIGHT = 1600

RESOURCE_COLORS = {
    "berries": (212, 66, 112),
    "wood": (129, 84, 48),
    "stone": (122, 132, 145),
}

CREATURE_COLORS = {
    "scavenger": (214, 171, 92),
    "wolf": (126, 135, 146),
    "boar": (108, 78, 60),
}


@dataclass(slots=True)
class Inventory:
    berries: int = 0
    wood: int = 0
    stone: int = 0

    def add(self, kind: str, amount: int) -> None:
        current = getattr(self, kind)
        setattr(self, kind, current + amount)

    def consume(self, kind: str, amount: int) -> bool:
        current = getattr(self, kind)
        if current < amount:
            return False
        setattr(self, kind, current - amount)
        return True

    def as_dict(self) -> dict[str, int]:
        return {
            "berries": self.berries,
            "wood": self.wood,
            "stone": self.stone,
        }


@dataclass(slots=True)
class AIAction:
    action: str
    target: str = "none"
    reason: str = ""
    speech: str = ""


@dataclass(slots=True)
class ResourceNode:
    identifier: str
    kind: str
    position: pygame.Vector2
    amount: int
    radius: float = 18.0
    respawn_amount: int = 4
    respawn_timer: float = 0.0
    respawn_delay: float = 14.0

    @property
    def available(self) -> bool:
        return self.amount > 0


@dataclass(slots=True)
class Campfire:
    position: pygame.Vector2
    fuel: float = 60.0
    warmth_radius: float = 130.0

    @property
    def alive(self) -> bool:
        return self.fuel > 0.0


@dataclass(slots=True)
class Actor:
    identifier: str
    position: pygame.Vector2
    velocity: pygame.Vector2
    radius: float
    speed: float
    health: float
    max_health: float

    def distance_to(self, other_position: pygame.Vector2) -> float:
        return self.position.distance_to(other_position)


@dataclass(slots=True)
class Player(Actor):
    inventory: Inventory = field(default_factory=Inventory)
    hunger: float = 10.0
    energy: float = 100.0
    facing: pygame.Vector2 = field(default_factory=lambda: pygame.Vector2(1, 0))
    attack_cooldown: float = 0.0
    gather_cooldown: float = 0.0
    eat_cooldown: float = 0.0
    last_message: str = ""


@dataclass(slots=True)
class Creature(Actor):
    species: str
    name: str
    personality: str
    hunger: float
    energy: float
    fear: float
    aggression: float
    decision: AIAction = field(default_factory=lambda: AIAction(action="wander"))
    think_cooldown: float = 0.0
    attack_cooldown: float = 0.0
    decision_pending: bool = False
    memory: Deque[str] = field(default_factory=lambda: deque(maxlen=6))
    speech_timer: float = 0.0
    ai_enabled: bool = True
    roam_goal: pygame.Vector2 = field(default_factory=pygame.Vector2)

    def remember(self, event: str) -> None:
        if event:
            self.memory.appendleft(event)

    @property
    def alive(self) -> bool:
        return self.health > 0.0
