extends CharacterBody3D
class_name CreatureActor

var creature_id := ""
var display_name := "Unknown"
var species := "creature"
var personality := "watchful"

var health := 100.0
var max_health := 100.0
var hunger := 24.0
var thirst := 18.0
var energy := 82.0
var fear := 18.0
var aggression := 34.0
var comfort := 55.0
var curiosity := 42.0
var social_drive := 40.0
var sickness := 0.0
var alertness := 60.0
var warmth := 50.0
var move_speed := 4.8
var gravity_strength := 28.0

var decision := {
	"action": "idle_watch",
	"target": "none",
	"reason": "",
	"speech": "",
	"posture": "stand",
	"locomotion": "walk",
	"sound": "none",
	"duration_seconds": 2.2,
	"memory_note": "",
}

var decision_pending := false
var think_cooldown := 1.0
var attack_cooldown := 0.0
var memory: Array[String] = []
var roam_target := Vector3.ZERO
var material_palette: Dictionary = {}

var body_root: Node3D
var shell_root: Node3D
var torso_anchor: Node3D
var head_anchor: Node3D
var tail_anchor: Node3D
var leg_nodes: Array[Node3D] = []
var shadow_mesh: MeshInstance3D
var stride_phase_offset := 0.0
var sound_cooldown := 0.0


func _ready() -> void:
	floor_snap_length = 0.45
	stride_phase_offset = randf() * TAU
	_build_visuals()


func configure(data: Dictionary) -> void:
	creature_id = str(data.get("id", creature_id))
	display_name = str(data.get("name", display_name))
	species = str(data.get("species", species))
	personality = str(data.get("personality", personality))
	max_health = float(data.get("max_health", max_health))
	health = float(data.get("health", max_health))
	hunger = float(data.get("hunger", hunger))
	thirst = float(data.get("thirst", thirst))
	energy = float(data.get("energy", energy))
	fear = float(data.get("fear", fear))
	aggression = float(data.get("aggression", aggression))
	comfort = float(data.get("comfort", comfort))
	curiosity = float(data.get("curiosity", curiosity))
	social_drive = float(data.get("social_drive", social_drive))
	sickness = float(data.get("sickness", sickness))
	alertness = float(data.get("alertness", alertness))
	warmth = float(data.get("warmth", warmth))
	move_speed = float(data.get("move_speed", move_speed))
	if is_inside_tree():
		_build_visuals()


func apply_material_palette(palette: Dictionary) -> void:
	material_palette = palette
	if is_inside_tree():
		_build_visuals()


func remember(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	memory.append(text.strip_edges())
	while memory.size() > 6:
		memory.pop_front()


func snapshot_payload() -> Dictionary:
	return {
		"id": creature_id,
		"name": display_name,
		"species": species,
		"personality": personality,
		"health": health,
		"max_health": max_health,
		"hunger": hunger,
		"thirst": thirst,
		"energy": energy,
		"fear": fear,
		"aggression": aggression,
		"comfort": comfort,
		"curiosity": curiosity,
		"social_drive": social_drive,
		"sickness": sickness,
		"alertness": alertness,
		"warmth": warmth,
		"decision": decision.duplicate(true),
		"memory": memory.duplicate(),
	}


func mark_decision_pending() -> void:
	decision_pending = true


func should_request_decision() -> bool:
	return not decision_pending and think_cooldown <= 0.0 and health > 0.0


func apply_decision(data: Dictionary) -> void:
	decision["action"] = str(data.get("action", "idle_watch"))
	decision["target"] = str(data.get("target", "none"))
	decision["reason"] = str(data.get("reason", ""))
	decision["speech"] = str(data.get("speech", ""))
	decision["posture"] = str(data.get("posture", "stand"))
	decision["locomotion"] = str(data.get("locomotion", "walk"))
	decision["sound"] = str(data.get("sound", "none"))
	decision["duration_seconds"] = float(data.get("duration_seconds", 2.2))
	decision["memory_note"] = str(data.get("memory_note", ""))
	decision_pending = false
	think_cooldown = clampf(float(decision["duration_seconds"]) + randf_range(-0.15, 0.35), 1.0, 4.5)
	if decision["reason"] != "":
		remember("%s: %s" % [decision["action"], decision["reason"]])
	if decision["memory_note"] != "":
		remember(str(decision["memory_note"]))
	if decision["action"] == "wander" or decision["action"] == "guard":
		roam_target = Vector3.ZERO


func cancel_pending_decision(retry_delay: float = 1.0, note: String = "") -> void:
	decision_pending = false
	think_cooldown = retry_delay
	if note != "":
		remember(note)


func defer_next_think(delay: float) -> void:
	think_cooldown = max(think_cooldown, delay)


func receive_damage(amount: float, attacker_label: String = "") -> void:
	health = max(0.0, health - amount)
	fear = min(100.0, fear + amount * 0.9)
	alertness = min(100.0, alertness + amount * 0.8)
	comfort = max(0.0, comfort - amount * 0.45)
	if attacker_label != "":
		remember("Hit by %s" % attacker_label)
	if species in ["deer", "fox"]:
		decision["action"] = "flee"
		decision["target"] = "player"
		decision_pending = false
		think_cooldown = randf_range(0.2, 0.6)
	elif health <= max_health * 0.45:
		decision["action"] = "flee"
		decision["target"] = "player"
		decision_pending = false
		think_cooldown = randf_range(0.4, 1.1)


func update_metabolism(delta: float, near_campfire: bool) -> void:
	think_cooldown = max(0.0, think_cooldown - delta)
	attack_cooldown = max(0.0, attack_cooldown - delta)
	sound_cooldown = max(0.0, sound_cooldown - delta)

	var action := str(decision.get("action", "idle_watch"))
	var locomotion := str(decision.get("locomotion", "walk"))
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var is_active := horizontal_speed > 0.3
	var exertion := 1.0
	match locomotion:
		"still":
			exertion = 0.65
		"slow_walk":
			exertion = 0.92
		"run":
			exertion = 1.45
		"circle":
			exertion = 1.18

	hunger = min(100.0, hunger + delta * (0.34 + 0.12 * exertion + (0.08 if is_active else 0.0)))
	thirst = min(100.0, thirst + delta * (0.42 + 0.18 * exertion + (0.1 if is_active else 0.0)))
	alertness = clampf(alertness - delta * (1.8 if action == "sleep" else (0.85 if action in ["rest", "sit", "groom"] else 0.35)), 0.0, 100.0)
	if is_active or action in ["investigate_sound", "attack", "flee"]:
		alertness = min(100.0, alertness + delta * 2.6)

	var energy_drain := delta * (0.78 + 0.62 * exertion)
	if action in ["rest", "sit", "sleep", "groom"]:
		energy_drain *= 0.2
	if near_campfire:
		energy_drain *= 0.82
	energy = max(0.0, energy - energy_drain)

	if action == "rest":
		energy = min(100.0, energy + delta * 5.2)
	elif action == "sit":
		energy = min(100.0, energy + delta * 3.8)
	elif action == "sleep":
		energy = min(100.0, energy + delta * 7.6)
	elif action == "groom":
		energy = min(100.0, energy + delta * 1.8)

	if near_campfire:
		warmth = min(100.0, warmth + delta * 10.0)
		comfort = min(100.0, comfort + delta * 4.0)
		fear = max(0.0, fear - delta * 5.0)
	else:
		warmth = move_toward(warmth, 48.0, delta * 1.35)

	if hunger > 62.0 or thirst > 66.0:
		comfort = max(0.0, comfort - delta * 1.6)
	elif action in ["sleep", "sit", "groom", "drink", "eat"]:
		comfort = min(100.0, comfort + delta * 2.2)

	if hunger > 84.0 or thirst > 88.0:
		sickness = min(100.0, sickness + delta * 1.2)
	elif action in ["sleep", "drink", "groom"] and sickness > 0.0:
		sickness = max(0.0, sickness - delta * 0.6)

	if warmth < 28.0:
		comfort = max(0.0, comfort - delta * 2.0)
		fear = min(100.0, fear + delta * 1.2)

	if hunger > 90.0:
		health = max(0.0, health - delta * 1.3)
	if thirst > 92.0:
		health = max(0.0, health - delta * 1.8)
	if energy <= 0.0:
		health = max(0.0, health - delta * 0.8)
	if sickness > 72.0:
		health = max(0.0, health - delta * 0.7)

	if hunger < 42.0 and thirst < 48.0 and energy > 24.0 and health < max_health:
		health = min(max_health, health + delta * (0.22 + (0.18 if near_campfire else 0.0)))


func simulate(delta: float, game: Node) -> void:
	if health <= 0.0:
		velocity = Vector3.ZERO
		return

	var desired_direction := Vector3.ZERO
	var player: CharacterBody3D = game.player
	var player_delta: Vector3 = player.global_position - global_position
	player_delta.y = 0.0
	var player_distance: float = player_delta.length()
	var action := str(decision.get("action", "idle_watch"))
	var sound_name := str(decision.get("sound", "none"))
	var posture := str(decision.get("posture", "stand"))
	var locomotion := str(decision.get("locomotion", "walk"))
	var threat_close: bool = player_distance < 7.5 and player.health > 0.0
	var noise_target = game.noise_target_for(global_position)

	if sound_cooldown <= 0.0 and sound_name != "none":
		game.broadcast_creature_sound(self, sound_name if sound_name != "none" else _default_sound())
		sound_cooldown = 3.2 if sound_name in ["howl", "bark", "squeal"] else 2.1

	if action in ["sleep", "sit", "rest", "groom"] and (threat_close or noise_target != null):
		think_cooldown = min(think_cooldown, 0.3)

	match action:
		"rest":
			energy = min(100.0, energy + delta * 8.0)
		"sleep":
			energy = min(100.0, energy + delta * 9.5)
			fear = max(0.0, fear - delta * 1.2)
		"sit":
			energy = min(100.0, energy + delta * 4.4)
			comfort = min(100.0, comfort + delta * 1.5)
		"idle_watch":
			if player_distance < 10.0:
				alertness = min(100.0, alertness + delta * 2.0)
		"listen":
			if noise_target != null:
				var to_noise: Vector3 = noise_target - global_position
				to_noise.y = 0.0
				if to_noise.length() > 0.2:
					desired_direction = to_noise.normalized() * 0.2
			alertness = min(100.0, alertness + delta * 2.6)
		"sniff":
			var scent_target = game.find_nearest_resource("berries", global_position)
			if scent_target == null:
				scent_target = game.find_nearest_resource("", global_position)
			if scent_target != null:
				var to_scent: Vector3 = scent_target.global_position - global_position
				to_scent.y = 0.0
				if to_scent.length() > 0.4:
					desired_direction = to_scent.normalized()
			elif noise_target != null:
				var to_noise_follow: Vector3 = noise_target - global_position
				to_noise_follow.y = 0.0
				if to_noise_follow.length() > 0.4:
					desired_direction = to_noise_follow.normalized()
			curiosity = min(100.0, curiosity + delta * 1.2)
		"flee":
			if player_distance > 0.1:
				desired_direction = (-player_delta).normalized()
		"forage":
			var resource = game.find_nearest_resource(str(decision.get("target", "")), global_position)
			if resource == null:
				resource = game.find_nearest_resource("", global_position)
			if resource != null:
				var to_resource: Vector3 = resource.global_position - global_position
				to_resource.y = 0.0
				if to_resource.length() <= resource.gather_radius + 0.8:
					if resource.harvest(1):
						match resource.resource_type:
							"berries":
								hunger = max(0.0, hunger - 28.0)
								thirst = max(0.0, thirst - 6.0)
								energy = min(100.0, energy + 8.0)
							"wood":
								energy = max(0.0, energy - 1.0)
							_:
								energy = max(0.0, energy - 0.5)
						fear = max(0.0, fear - 4.0)
						remember("Foraged %s" % resource.resource_type)
						decision["action"] = "wander"
				else:
					desired_direction = to_resource.normalized()
			else:
				decision["action"] = "wander"
		"eat":
			var food_target = game.find_nearest_resource("berries", global_position)
			if food_target != null:
				var to_food: Vector3 = food_target.global_position - global_position
				to_food.y = 0.0
				if to_food.length() <= food_target.gather_radius + 0.9:
					if food_target.harvest(1):
						hunger = max(0.0, hunger - 24.0)
						thirst = max(0.0, thirst - 5.0)
						energy = min(100.0, energy + 5.0)
						comfort = min(100.0, comfort + 4.0)
						remember("Ate berries")
				else:
					desired_direction = to_food.normalized()
			else:
				decision["action"] = "forage"
		"drink":
			var water_point: Vector3 = game.find_water_point(global_position)
			var to_water := water_point - global_position
			to_water.y = 0.0
			if to_water.length() <= 1.8:
				thirst = max(0.0, thirst - delta * 20.0)
				comfort = min(100.0, comfort + delta * 2.5)
				sickness = max(0.0, sickness - delta * 0.3)
			elif to_water.length() > 0.2:
				desired_direction = to_water.normalized()
		"stalk":
			if player_distance > 8.0:
				desired_direction = player_delta.normalized()
			elif player_distance < 4.0:
				desired_direction = (-player_delta).normalized()
			else:
				var strafe := Vector3(player_delta.z, 0.0, -player_delta.x).normalized()
				desired_direction = strafe
			alertness = min(100.0, alertness + delta * 1.8)
		"circle_target":
			if player_distance > 9.0:
				desired_direction = player_delta.normalized()
			elif player_distance < 3.6:
				desired_direction = (-player_delta).normalized()
			else:
				desired_direction = Vector3(player_delta.z, 0.0, -player_delta.x).normalized()
		"attack":
			if player_distance > 0.2:
				desired_direction = player_delta.normalized()
			if player_distance <= _attack_range() and attack_cooldown <= 0.0:
				var damage := _attack_damage()
				game.damage_player("%s the %s" % [display_name, species], damage)
				attack_cooldown = 0.95 if species == "wolf" else (1.2 if species == "fox" else 1.35)
				alertness = min(100.0, alertness + 6.0)
				remember("Lunged at the player")
		"guard":
			var guard_point: Vector3 = game.guard_target_for(self)
			var to_guard := guard_point - global_position
			to_guard.y = 0.0
			if to_guard.length() > 1.6:
				desired_direction = to_guard.normalized()
			elif player_distance < 7.0 and aggression > 42.0:
				desired_direction = player_delta.normalized()
		"make_sound":
			if sound_name == "none":
				decision["sound"] = _default_sound()
			desired_direction = Vector3.ZERO
			alertness = min(100.0, alertness + delta * 1.2)
		"investigate_sound":
			if noise_target != null:
				var to_investigate: Vector3 = noise_target - global_position
				to_investigate.y = 0.0
				if to_investigate.length() > 0.8:
					desired_direction = to_investigate.normalized()
				else:
					comfort = max(0.0, comfort - delta * 0.2)
					alertness = min(100.0, alertness + delta * 1.5)
			elif player_distance < 14.0:
				desired_direction = player_delta.normalized()
			else:
				decision["action"] = "idle_watch"
		"groom":
			fear = max(0.0, fear - delta * 1.8)
			comfort = min(100.0, comfort + delta * 2.2)
			sickness = max(0.0, sickness - delta * 0.5)
		"retch":
			sickness = max(0.0, sickness - delta * 1.4)
			energy = max(0.0, energy - delta * 0.8)
			comfort = max(0.0, comfort - delta * 0.4)
		_:
			if roam_target == Vector3.ZERO or global_position.distance_to(roam_target) < 1.6:
				roam_target = game.random_world_point()
			var to_target := roam_target - global_position
			to_target.y = 0.0
			if to_target.length() > 0.2:
				desired_direction = to_target.normalized()

	var target_speed := _target_speed_for(action, posture, locomotion)
	if action in ["listen", "make_sound", "groom", "retch", "sleep", "sit", "rest", "idle_watch"]:
		target_speed = min(target_speed, 0.35)

	var target_velocity := desired_direction * target_speed
	velocity.x = move_toward(velocity.x, target_velocity.x, delta * 18.0)
	velocity.z = move_toward(velocity.z, target_velocity.z, delta * 18.0)
	if not is_on_floor():
		velocity.y -= gravity_strength * delta
	else:
		velocity.y = min(velocity.y, 0.0)
	move_and_slide()

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length() > 0.08:
		var target_yaw := atan2(horizontal.x, horizontal.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, delta * 10.0)
	elif action in ["listen", "idle_watch", "sleep", "sit", "make_sound"] and player_distance < 14.0:
		var watch_yaw := atan2(player_delta.x, player_delta.z)
		rotation.y = lerp_angle(rotation.y, watch_yaw, delta * 4.5)
	_animate_visuals(horizontal, delta, action)


func _animate_visuals(horizontal: Vector3, delta: float, action: String) -> void:
	if body_root == null:
		return

	var posture := str(decision.get("posture", "stand"))
	var sound_name := str(decision.get("sound", "none"))
	var stride: float = clampf(horizontal.length() / max(_species_speed(), 0.1), 0.0, 1.0)
	var gait_time := Time.get_ticks_msec() / 1000.0 * (7.5 if species == "scavenger" else 8.8) + stride_phase_offset
	var base_height := _body_base_height()
	var bob_strength := 0.02 * stride
	match posture:
		"low", "crouch":
			base_height -= 0.12 if species != "scavenger" else 0.08
			bob_strength *= 0.6
		"sit":
			base_height -= 0.22 if species != "scavenger" else 0.18
			bob_strength *= 0.18
		"sleep":
			base_height -= 0.34 if species != "scavenger" else 0.26
			bob_strength = 0.004
	body_root.position.y = lerpf(body_root.position.y, base_height + sin(gait_time * 2.0) * bob_strength, delta * 10.0)

	var pitch_target := 0.0
	if action == "attack":
		pitch_target += deg_to_rad(8.0)
	elif action == "flee":
		pitch_target += deg_to_rad(4.5)
	elif action == "rest":
		pitch_target += deg_to_rad(-4.0)
	elif action == "sniff":
		pitch_target += deg_to_rad(5.0)
	elif action == "retch":
		pitch_target += deg_to_rad(12.0)

	match posture:
		"low", "crouch":
			pitch_target += deg_to_rad(7.0)
		"sit":
			pitch_target += deg_to_rad(-7.0)
		"sleep":
			pitch_target += deg_to_rad(-18.0)

	body_root.rotation.x = lerpf(body_root.rotation.x, pitch_target, delta * 8.0)
	body_root.rotation.z = lerpf(body_root.rotation.z, sin(gait_time) * 0.025 * stride, delta * 7.0)

	if head_anchor != null:
		var head_pitch := -pitch_target * 0.35 + sin(gait_time + 0.4) * 0.05 * stride
		if action == "listen":
			head_pitch = deg_to_rad(-10.0) + sin(gait_time * 0.9) * 0.05
		elif action == "sniff":
			head_pitch = deg_to_rad(12.0) + sin(gait_time * 2.8) * 0.12
		elif action == "eat":
			head_pitch = deg_to_rad(18.0)
		elif action == "drink":
			head_pitch = deg_to_rad(26.0)
		elif action == "groom":
			head_pitch = deg_to_rad(18.0)
		elif action == "sleep":
			head_pitch = deg_to_rad(24.0)
		if sound_name in ["howl", "bark", "whine", "squeal"]:
			head_pitch += deg_to_rad(-20.0)
		head_anchor.rotation.x = lerpf(head_anchor.rotation.x, head_pitch, delta * 9.0)
		head_anchor.rotation.y = lerpf(head_anchor.rotation.y, sin(gait_time * 0.6) * 0.08 * max(stride, 0.2 if action == "listen" else 0.0), delta * 7.0)
	if tail_anchor != null:
		var tail_swing := 0.18 if species == "scavenger" else 0.34
		if action in ["flee", "attack"]:
			tail_swing *= 1.2
		elif posture == "sleep":
			tail_swing *= 0.2
		tail_anchor.rotation.y = lerpf(tail_anchor.rotation.y, sin(gait_time * 1.1) * tail_swing * max(stride, 0.2), delta * 8.0)
		tail_anchor.rotation.x = lerpf(tail_anchor.rotation.x, deg_to_rad(12.0) - pitch_target * 0.3, delta * 8.0)

	for index in range(leg_nodes.size()):
		var leg := leg_nodes[index]
		var phase_shift := PI if index % 2 == 1 else 0.0
		if species == "boar":
			phase_shift += PI * 0.1 if index < 2 else -PI * 0.1
		var leg_angle := sin(gait_time + phase_shift) * 0.62 * stride
		var lift_amount: float = abs(sin(gait_time + phase_shift)) * 0.04 * stride
		if action in ["rest", "idle_watch", "listen", "make_sound", "groom"]:
			leg_angle = 0.0
			lift_amount = 0.0
		if posture == "sit":
			leg_angle = deg_to_rad(18.0) if index < 2 else deg_to_rad(-34.0)
			lift_amount = 0.0
		elif posture == "sleep":
			leg_angle = deg_to_rad(48.0) if index < 2 else deg_to_rad(-22.0)
			lift_amount = 0.0
		elif posture in ["low", "crouch"]:
			leg_angle *= 0.45
		leg.rotation.x = lerpf(leg.rotation.x, leg_angle, delta * 12.0)
		leg.position.y = lerpf(leg.position.y, _leg_mount_height() + lift_amount, delta * 12.0)


func _target_speed_for(action: String, posture: String, locomotion: String) -> float:
	var speed := _species_speed() * _locomotion_scale(locomotion)
	match action:
		"rest", "sleep", "sit", "listen", "make_sound", "groom", "retch", "idle_watch":
			speed = 0.0
		"flee":
			speed = _species_speed() * max(_locomotion_scale(locomotion), 1.15)
		"stalk":
			speed = _species_speed() * clampf(_locomotion_scale(locomotion), 0.58, 0.92)
		"attack":
			speed = _species_speed() * max(_locomotion_scale(locomotion), 1.12)
		"circle_target":
			speed = _species_speed() * clampf(_locomotion_scale(locomotion), 0.72, 1.0)
		"sniff", "forage", "drink", "eat", "investigate_sound":
			speed = _species_speed() * clampf(_locomotion_scale(locomotion), 0.55, 0.96)
	if posture == "sleep":
		speed = 0.0
	elif posture == "sit":
		speed *= 0.2
	elif posture in ["low", "crouch"]:
		speed *= 0.8
	return speed


func _locomotion_scale(locomotion: String) -> float:
	match locomotion:
		"still":
			return 0.0
		"slow_walk":
			return 0.58
		"walk":
			return 0.82
		"run":
			return 1.18
		"circle":
			return 0.78
		_:
			return 0.82


func _default_sound() -> String:
	match species:
		"wolf":
			return "growl"
		"boar":
			return "snort"
		"deer":
			return "snort"
		"fox":
			return "bark"
		_:
			return "huff"


func _species_speed() -> float:
	match species:
		"wolf":
			return 5.9
		"boar":
			return 4.2
		"deer":
			return 6.8
		"fox":
			return 6.2
		"scavenger":
			return 4.8
		_:
			return move_speed


func _attack_range() -> float:
	match species:
		"wolf":
			return 2.0
		"boar":
			return 1.8
		"deer":
			return 1.45
		"fox":
			return 1.55
		_:
			return 1.6


func _attack_damage() -> float:
	match species:
		"wolf":
			return 7.0 + aggression * 0.06
		"boar":
			return 8.0 + aggression * 0.052
		"deer":
			return 4.2 + aggression * 0.025
		"fox":
			return 5.6 + aggression * 0.038
		_:
			return 6.0 + aggression * 0.042


func _body_base_height() -> float:
	match species:
		"wolf":
			return 0.04
		"boar":
			return 0.02
		"deer":
			return 0.08
		"fox":
			return 0.04
		_:
			return 0.06


func _leg_mount_height() -> float:
	match species:
		"wolf":
			return 0.56
		"boar":
			return 0.48
		"deer":
			return 0.68
		"fox":
			return 0.5
		_:
			return 0.78


func _collision_radius() -> float:
	match species:
		"wolf":
			return 0.46
		"boar":
			return 0.52
		"deer":
			return 0.42
		"fox":
			return 0.34
		_:
			return 0.38


func _collision_height() -> float:
	match species:
		"wolf":
			return 1.0
		"boar":
			return 1.0
		"deer":
			return 1.38
		"fox":
			return 0.82
		_:
			return 1.32


func _collision_center_y() -> float:
	match species:
		"wolf":
			return 0.74
		"boar":
			return 0.66
		"deer":
			return 1.04
		"fox":
			return 0.58
		_:
			return 0.96


func _build_visuals() -> void:
	for child in get_children():
		child.queue_free()
	leg_nodes.clear()
	torso_anchor = null
	head_anchor = null
	tail_anchor = null

	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = _collision_radius()
	capsule.height = _collision_height()
	collision.shape = capsule
	collision.position = Vector3(0.0, _collision_center_y(), 0.0)
	add_child(collision)

	shadow_mesh = MeshInstance3D.new()
	var shadow := CylinderMesh.new()
	shadow.top_radius = 0.6 if species == "fox" else (0.78 if species == "deer" else 0.72)
	shadow.bottom_radius = shadow.top_radius
	shadow.height = 0.04
	shadow_mesh.mesh = shadow
	shadow_mesh.position = Vector3(0.0, 0.03, 0.0)
	var shadow_material := StandardMaterial3D.new()
	shadow_material.albedo_color = Color(0.0, 0.0, 0.0, 0.35)
	shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_mesh.material_override = shadow_material
	add_child(shadow_mesh)

	body_root = Node3D.new()
	body_root.position = Vector3(0.0, _body_base_height(), 0.0)
	add_child(body_root)

	shell_root = Node3D.new()
	body_root.add_child(shell_root)

	match species:
		"wolf":
			_build_wolf_visual()
		"boar":
			_build_boar_visual()
		"deer":
			_build_deer_visual()
		"fox":
			_build_fox_visual()
		_:
			_build_scavenger_visual()


func _build_wolf_visual() -> void:
	var fur: Material = material_palette.get("wolf_fur", material_palette.get("stone"))
	var accent: Material = material_palette.get("wolf_accent", material_palette.get("coal"))
	var eye: Material = material_palette.get("flame_tip")

	torso_anchor = Node3D.new()
	torso_anchor.position = Vector3(0.0, 0.0, 0.0)
	shell_root.add_child(torso_anchor)
	_add_capsule(torso_anchor, Vector3(0.0, 0.62, -0.08), Vector3(0.95, 0.86, 1.5), fur, 0.34, 0.82)
	_add_sphere(torso_anchor, Vector3(0.0, 0.7, 0.26), Vector3(1.08, 0.86, 1.0), fur, 0.22)
	_add_sphere(torso_anchor, Vector3(0.0, 0.68, -0.62), Vector3(1.18, 0.9, 1.06), fur, 0.24)
	_add_box(torso_anchor, Vector3(0.0, 0.76, -0.16), Vector3(0.36, 0.14, 1.34), accent)
	_add_box(torso_anchor, Vector3(0.0, 0.45, 0.32), Vector3(0.24, 0.16, 0.46), fur)
	_add_capsule(torso_anchor, Vector3(0.0, 0.7, 0.48), Vector3(0.44, 0.44, 0.82), fur, 0.14, 0.44, Vector3(deg_to_rad(26.0), 0.0, 0.0))

	head_anchor = Node3D.new()
	head_anchor.position = Vector3(0.0, 0.72, 0.72)
	shell_root.add_child(head_anchor)
	_add_sphere(head_anchor, Vector3(0.0, 0.02, 0.0), Vector3(0.98, 0.76, 1.22), fur, 0.26)
	_add_box(head_anchor, Vector3(0.0, -0.02, 0.34), Vector3(0.18, 0.13, 0.5), accent)
	_add_box(head_anchor, Vector3(0.0, -0.1, 0.56), Vector3(0.1, 0.08, 0.16), accent)
	_add_sphere(head_anchor, Vector3(-0.16, 0.05, 0.12), Vector3(0.82, 0.74, 0.9), fur, 0.1)
	_add_sphere(head_anchor, Vector3(0.16, 0.05, 0.12), Vector3(0.82, 0.74, 0.9), fur, 0.1)
	_add_box(head_anchor, Vector3(-0.12, 0.24, -0.05), Vector3(0.09, 0.26, 0.09), accent, Vector3(0.0, 0.0, deg_to_rad(16.0)))
	_add_box(head_anchor, Vector3(0.12, 0.24, -0.05), Vector3(0.09, 0.26, 0.09), accent, Vector3(0.0, 0.0, deg_to_rad(-16.0)))
	_add_sphere(head_anchor, Vector3(-0.1, 0.06, 0.32), Vector3.ONE, eye, 0.04)
	_add_sphere(head_anchor, Vector3(0.1, 0.06, 0.32), Vector3.ONE, eye, 0.04)

	tail_anchor = Node3D.new()
	tail_anchor.position = Vector3(0.0, 0.76, -0.94)
	shell_root.add_child(tail_anchor)
	_add_capsule(tail_anchor, Vector3(0.0, 0.0, -0.12), Vector3(0.28, 0.28, 0.96), accent, 0.08, 0.36, Vector3(deg_to_rad(30.0), 0.0, 0.0))
	_add_box(tail_anchor, Vector3(0.0, 0.0, -0.56), Vector3(0.16, 0.14, 0.24), fur)

	_add_leg(shell_root, Vector3(-0.3, _leg_mount_height(), 0.34), Vector3(0.1, 0.72, 0.1), fur)
	_add_leg(shell_root, Vector3(0.3, _leg_mount_height(), 0.32), Vector3(0.1, 0.72, 0.1), fur)
	_add_leg(shell_root, Vector3(-0.26, _leg_mount_height(), -0.6), Vector3(0.11, 0.78, 0.11), fur)
	_add_leg(shell_root, Vector3(0.26, _leg_mount_height(), -0.58), Vector3(0.11, 0.78, 0.11), fur)


func _build_boar_visual() -> void:
	var body_material = material_palette.get("boar_hide", material_palette.get("bark"))
	var snout_material = material_palette.get("boar_snout", material_palette.get("stone"))
	var tusk_material = material_palette.get("tusk", material_palette.get("stone_highlight"))

	torso_anchor = Node3D.new()
	shell_root.add_child(torso_anchor)
	_add_capsule(torso_anchor, Vector3(0.0, 0.55, -0.06), Vector3(1.18, 0.9, 1.72), body_material, 0.38, 0.86)
	_add_sphere(torso_anchor, Vector3(0.0, 0.7, 0.28), Vector3(1.12, 0.9, 0.96), body_material, 0.25)
	_add_sphere(torso_anchor, Vector3(0.0, 0.64, -0.62), Vector3(1.22, 0.92, 1.02), body_material, 0.26)
	_add_box(torso_anchor, Vector3(0.0, 0.84, 0.08), Vector3(0.12, 0.12, 0.68), material_palette.get("boar_mane", material_palette.get("coal")))
	_add_box(torso_anchor, Vector3(0.0, 0.48, 0.28), Vector3(0.28, 0.18, 0.54), snout_material)

	head_anchor = Node3D.new()
	head_anchor.position = Vector3(0.0, 0.6, 0.76)
	shell_root.add_child(head_anchor)
	_add_box(head_anchor, Vector3(0.0, 0.0, 0.04), Vector3(0.54, 0.34, 0.82), snout_material)
	_add_box(head_anchor, Vector3(0.0, -0.02, 0.44), Vector3(0.24, 0.16, 0.24), material_palette.get("coal"))
	_add_box(head_anchor, Vector3(-0.16, 0.16, -0.08), Vector3(0.08, 0.14, 0.08), body_material, Vector3(0.0, 0.0, deg_to_rad(24.0)))
	_add_box(head_anchor, Vector3(0.16, 0.16, -0.08), Vector3(0.08, 0.14, 0.08), body_material, Vector3(0.0, 0.0, deg_to_rad(-24.0)))
	_add_box(head_anchor, Vector3(-0.14, -0.12, 0.42), Vector3(0.06, 0.18, 0.28), tusk_material, Vector3(0.0, 0.0, deg_to_rad(22.0)))
	_add_box(head_anchor, Vector3(0.14, -0.12, 0.42), Vector3(0.06, 0.18, 0.28), tusk_material, Vector3(0.0, 0.0, deg_to_rad(-22.0)))

	tail_anchor = Node3D.new()
	tail_anchor.position = Vector3(0.0, 0.7, -0.98)
	shell_root.add_child(tail_anchor)
	_add_box(tail_anchor, Vector3(0.0, 0.0, -0.12), Vector3(0.06, 0.18, 0.22), material_palette.get("coal"))

	_add_leg(shell_root, Vector3(-0.34, _leg_mount_height(), 0.28), Vector3(0.15, 0.54, 0.15), body_material)
	_add_leg(shell_root, Vector3(0.34, _leg_mount_height(), 0.28), Vector3(0.15, 0.54, 0.15), body_material)
	_add_leg(shell_root, Vector3(-0.32, _leg_mount_height(), -0.56), Vector3(0.16, 0.58, 0.16), body_material)
	_add_leg(shell_root, Vector3(0.32, _leg_mount_height(), -0.56), Vector3(0.16, 0.58, 0.16), body_material)


func _build_deer_visual() -> void:
	var fur: Material = material_palette.get("deer_fur", material_palette.get("bark"))
	var undercoat: Material = material_palette.get("deer_undercoat", material_palette.get("stone_highlight"))
	var antler: Material = material_palette.get("antler", material_palette.get("tusk"))

	torso_anchor = Node3D.new()
	shell_root.add_child(torso_anchor)
	_add_capsule(torso_anchor, Vector3(0.0, 0.82, -0.04), Vector3(0.9, 0.88, 1.52), fur, 0.28, 0.96)
	_add_sphere(torso_anchor, Vector3(0.0, 0.96, 0.26), Vector3(0.96, 0.88, 0.92), fur, 0.2)
	_add_sphere(torso_anchor, Vector3(0.0, 0.88, -0.58), Vector3(1.08, 0.94, 1.02), fur, 0.22)
	_add_box(torso_anchor, Vector3(0.0, 0.68, 0.18), Vector3(0.22, 0.16, 0.52), undercoat)
	_add_capsule(torso_anchor, Vector3(0.0, 1.12, 0.5), Vector3(0.32, 0.32, 0.92), fur, 0.12, 0.66, Vector3(deg_to_rad(18.0), 0.0, 0.0))

	head_anchor = Node3D.new()
	head_anchor.position = Vector3(0.0, 1.12, 0.82)
	shell_root.add_child(head_anchor)
	_add_box(head_anchor, Vector3(0.0, -0.18, -0.34), Vector3(0.16, 0.58, 0.18), fur)
	_add_sphere(head_anchor, Vector3(0.0, 0.06, 0.0), Vector3(0.9, 0.78, 1.08), fur, 0.22)
	_add_box(head_anchor, Vector3(0.0, -0.02, 0.34), Vector3(0.14, 0.11, 0.46), undercoat)
	_add_box(head_anchor, Vector3(-0.14, 0.12, -0.1), Vector3(0.06, 0.2, 0.08), fur, Vector3(0.0, 0.0, deg_to_rad(18.0)))
	_add_box(head_anchor, Vector3(0.14, 0.12, -0.1), Vector3(0.06, 0.2, 0.08), fur, Vector3(0.0, 0.0, deg_to_rad(-18.0)))
	_add_box(head_anchor, Vector3(-0.14, 0.22, -0.02), Vector3(0.06, 0.38, 0.06), antler, Vector3(0.0, 0.0, deg_to_rad(16.0)))
	_add_box(head_anchor, Vector3(0.14, 0.22, -0.02), Vector3(0.06, 0.38, 0.06), antler, Vector3(0.0, 0.0, deg_to_rad(-16.0)))
	_add_box(head_anchor, Vector3(-0.22, 0.42, -0.02), Vector3(0.22, 0.05, 0.05), antler, Vector3(0.0, 0.0, deg_to_rad(24.0)))
	_add_box(head_anchor, Vector3(0.22, 0.42, -0.02), Vector3(0.22, 0.05, 0.05), antler, Vector3(0.0, 0.0, deg_to_rad(-24.0)))
	_add_box(head_anchor, Vector3(-0.3, 0.52, 0.02), Vector3(0.12, 0.04, 0.04), antler, Vector3(0.0, 0.0, deg_to_rad(32.0)))
	_add_box(head_anchor, Vector3(0.3, 0.52, 0.02), Vector3(0.12, 0.04, 0.04), antler, Vector3(0.0, 0.0, deg_to_rad(-32.0)))

	tail_anchor = Node3D.new()
	tail_anchor.position = Vector3(0.0, 0.96, -0.9)
	shell_root.add_child(tail_anchor)
	_add_box(tail_anchor, Vector3(0.0, 0.0, -0.08), Vector3(0.08, 0.18, 0.24), undercoat)

	_add_leg(shell_root, Vector3(-0.24, _leg_mount_height(), 0.38), Vector3(0.08, 1.08, 0.08), fur)
	_add_leg(shell_root, Vector3(0.24, _leg_mount_height(), 0.38), Vector3(0.08, 1.08, 0.08), fur)
	_add_leg(shell_root, Vector3(-0.22, _leg_mount_height(), -0.56), Vector3(0.09, 1.12, 0.09), fur)
	_add_leg(shell_root, Vector3(0.22, _leg_mount_height(), -0.56), Vector3(0.09, 1.12, 0.09), fur)


func _build_fox_visual() -> void:
	var fur: Material = material_palette.get("fox_fur", material_palette.get("wolf_fur"))
	var chest: Material = material_palette.get("fox_white", material_palette.get("deer_undercoat"))
	var accent: Material = material_palette.get("fox_dark", material_palette.get("wolf_accent"))

	torso_anchor = Node3D.new()
	torso_anchor.position = Vector3(0.0, 0.0, 0.0)
	shell_root.add_child(torso_anchor)
	_add_capsule(torso_anchor, Vector3(0.0, 0.52, -0.06), Vector3(0.78, 0.7, 1.28), fur, 0.26, 0.72)
	_add_sphere(torso_anchor, Vector3(0.0, 0.58, 0.2), Vector3(0.94, 0.78, 0.9), fur, 0.18)
	_add_sphere(torso_anchor, Vector3(0.0, 0.54, -0.5), Vector3(1.02, 0.8, 0.98), fur, 0.2)
	_add_box(torso_anchor, Vector3(0.0, 0.45, 0.22), Vector3(0.2, 0.12, 0.42), chest)
	_add_capsule(torso_anchor, Vector3(0.0, 0.64, 0.42), Vector3(0.28, 0.28, 0.72), chest, 0.1, 0.4, Vector3(deg_to_rad(26.0), 0.0, 0.0))

	head_anchor = Node3D.new()
	head_anchor.position = Vector3(0.0, 0.62, 0.66)
	shell_root.add_child(head_anchor)
	_add_sphere(head_anchor, Vector3(0.0, 0.02, 0.0), Vector3(0.88, 0.68, 1.08), fur, 0.2)
	_add_box(head_anchor, Vector3(0.0, -0.02, 0.3), Vector3(0.13, 0.1, 0.38), chest)
	_add_box(head_anchor, Vector3(-0.11, 0.18, -0.04), Vector3(0.07, 0.2, 0.07), accent, Vector3(0.0, 0.0, deg_to_rad(18.0)))
	_add_box(head_anchor, Vector3(0.11, 0.18, -0.04), Vector3(0.07, 0.2, 0.07), accent, Vector3(0.0, 0.0, deg_to_rad(-18.0)))
	_add_box(head_anchor, Vector3(0.0, -0.08, 0.44), Vector3(0.08, 0.06, 0.12), accent)

	tail_anchor = Node3D.new()
	tail_anchor.position = Vector3(0.0, 0.62, -0.82)
	shell_root.add_child(tail_anchor)
	_add_capsule(tail_anchor, Vector3(0.0, 0.0, -0.12), Vector3(0.34, 0.34, 1.18), fur, 0.09, 0.48, Vector3(deg_to_rad(28.0), 0.0, 0.0))
	_add_box(tail_anchor, Vector3(0.0, 0.0, -0.58), Vector3(0.18, 0.16, 0.24), chest)

	_add_leg(shell_root, Vector3(-0.24, _leg_mount_height(), 0.28), Vector3(0.08, 0.6, 0.08), fur)
	_add_leg(shell_root, Vector3(0.24, _leg_mount_height(), 0.26), Vector3(0.08, 0.6, 0.08), fur)
	_add_leg(shell_root, Vector3(-0.22, _leg_mount_height(), -0.46), Vector3(0.08, 0.66, 0.08), fur)
	_add_leg(shell_root, Vector3(0.22, _leg_mount_height(), -0.44), Vector3(0.08, 0.66, 0.08), fur)


func _build_scavenger_visual() -> void:
	var robe: Material = material_palette.get("scavenger_robe", material_palette.get("coal"))
	var trim: Material = material_palette.get("scavenger_trim", material_palette.get("player_scarf"))
	var skin: Material = material_palette.get("player_skin")
	var pack: Material = material_palette.get("player_pack")

	torso_anchor = Node3D.new()
	shell_root.add_child(torso_anchor)
	_add_capsule(torso_anchor, Vector3(0.0, 0.98, 0.0), Vector3(0.88, 1.0, 0.84), robe, 0.32, 0.84)
	_add_box(torso_anchor, Vector3(0.0, 0.54, 0.02), Vector3(0.72, 0.62, 0.48), robe)
	_add_box(torso_anchor, Vector3(0.0, 1.06, -0.34), Vector3(0.34, 0.42, 0.16), pack)
	_add_box(torso_anchor, Vector3(-0.44, 1.0, 0.04), Vector3(0.12, 0.54, 0.12), robe)
	_add_box(torso_anchor, Vector3(0.44, 1.0, 0.04), Vector3(0.12, 0.54, 0.12), robe)

	head_anchor = Node3D.new()
	head_anchor.position = Vector3(0.0, 1.56, 0.08)
	shell_root.add_child(head_anchor)
	_add_sphere(head_anchor, Vector3(0.0, 0.0, 0.0), Vector3(0.7, 0.78, 0.74), skin, 0.24)
	_add_box(head_anchor, Vector3(0.0, 0.08, -0.12), Vector3(0.52, 0.28, 0.46), robe)
	_add_box(head_anchor, Vector3(0.0, -0.34, 0.18), Vector3(0.42, 0.08, 0.12), trim)
	_add_box(head_anchor, Vector3(0.0, 0.18, -0.22), Vector3(0.58, 0.14, 0.54), robe)

	_add_leg(shell_root, Vector3(-0.42, 1.02, 0.02), Vector3(0.12, 0.56, 0.12), robe, true)
	_add_leg(shell_root, Vector3(0.42, 1.02, 0.02), Vector3(0.12, 0.56, 0.12), robe, true)
	_add_leg(shell_root, Vector3(-0.16, 0.78, 0.0), Vector3(0.12, 0.72, 0.12), robe)
	_add_leg(shell_root, Vector3(0.16, 0.78, 0.0), Vector3(0.12, 0.72, 0.12), robe)


func _add_leg(parent: Node3D, mount_position: Vector3, size: Vector3, material: Material, horizontal: bool = false) -> void:
	var pivot := Node3D.new()
	pivot.position = mount_position
	parent.add_child(pivot)
	leg_nodes.append(pivot)

	var upper := MeshInstance3D.new()
	var upper_mesh := BoxMesh.new()
	upper_mesh.size = size
	upper.mesh = upper_mesh
	upper.position = Vector3(0.0, -size.y * 0.32, 0.0) if horizontal else Vector3(0.0, -size.y * 0.42, 0.0)
	upper.material_override = material
	pivot.add_child(upper)

	var lower := MeshInstance3D.new()
	var lower_mesh := BoxMesh.new()
	lower_mesh.size = Vector3(size.x * 0.74, size.y * 0.62, size.z * 0.74)
	lower.mesh = lower_mesh
	lower.position = Vector3(0.0, -size.y * 0.88, 0.0) if not horizontal else Vector3(0.0, -size.y * 0.68, 0.0)
	lower.material_override = material
	pivot.add_child(lower)

	var foot := MeshInstance3D.new()
	var foot_mesh := BoxMesh.new()
	foot_mesh.size = Vector3(size.x * 1.15, max(0.06, size.y * 0.12), size.z * (1.42 if horizontal else 1.24))
	foot.mesh = foot_mesh
	foot.position = Vector3(0.0, -size.y * 1.18, size.z * 0.08) if not horizontal else Vector3(0.0, -size.y * 0.96, size.z * 0.1)
	foot.material_override = material
	pivot.add_child(foot)


func _add_box(parent: Node3D, position: Vector3, size: Vector3, material: Material, rotation_value: Vector3 = Vector3.ZERO) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.rotation = rotation_value
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)


func _add_sphere(parent: Node3D, position: Vector3, scale_value: Vector3, material: Material, radius: float) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.scale = scale_value
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)


func _add_capsule(
	parent: Node3D,
	position: Vector3,
	scale_value: Vector3,
	material: Material,
	radius: float,
	height: float,
	rotation_value: Vector3 = Vector3.ZERO
) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.scale = scale_value
	mesh_instance.rotation = rotation_value
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)
