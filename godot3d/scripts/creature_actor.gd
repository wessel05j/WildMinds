extends CharacterBody3D
class_name CreatureActor

var creature_id := ""
var display_name := "Unknown"
var species := "creature"
var personality := "watchful"

var health := 100.0
var max_health := 100.0
var hunger := 24.0
var energy := 82.0
var fear := 18.0
var aggression := 34.0
var move_speed := 4.8
var gravity_strength := 28.0

var decision := {
	"action": "wander",
	"target": "none",
	"reason": "",
	"speech": "",
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
	energy = float(data.get("energy", energy))
	fear = float(data.get("fear", fear))
	aggression = float(data.get("aggression", aggression))
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
		"energy": energy,
		"fear": fear,
		"aggression": aggression,
		"decision": decision.duplicate(true),
		"memory": memory.duplicate(),
	}


func mark_decision_pending() -> void:
	decision_pending = true


func should_request_decision() -> bool:
	return not decision_pending and think_cooldown <= 0.0 and health > 0.0


func apply_decision(data: Dictionary) -> void:
	decision["action"] = str(data.get("action", "wander"))
	decision["target"] = str(data.get("target", "none"))
	decision["reason"] = str(data.get("reason", ""))
	decision["speech"] = str(data.get("speech", ""))
	decision_pending = false
	think_cooldown = randf_range(1.5, 2.9)
	if decision["reason"] != "":
		remember("%s: %s" % [decision["action"], decision["reason"]])
	if decision["action"] == "wander" or decision["action"] == "guard":
		roam_target = Vector3.ZERO


func receive_damage(amount: float, attacker_label: String = "") -> void:
	health = max(0.0, health - amount)
	fear = min(100.0, fear + amount * 0.9)
	if attacker_label != "":
		remember("Hit by %s" % attacker_label)
	if health <= max_health * 0.45:
		decision["action"] = "flee"
		decision["target"] = "player"
		decision_pending = false
		think_cooldown = randf_range(0.4, 1.1)


func update_metabolism(delta: float, near_campfire: bool) -> void:
	think_cooldown = max(0.0, think_cooldown - delta)
	attack_cooldown = max(0.0, attack_cooldown - delta)
	hunger = min(100.0, hunger + delta * 1.0)
	var active_cost := 3.0 if Vector2(velocity.x, velocity.z).length() > 0.35 else 1.1
	energy = max(0.0, energy - delta * active_cost)
	if decision["action"] == "rest":
		energy = min(100.0, energy + delta * 11.0)
	if near_campfire:
		energy = min(100.0, energy + delta * 5.0)
		fear = max(0.0, fear - delta * 7.0)
	if hunger > 86.0:
		health = max(0.0, health - delta * 2.0)
	if energy <= 0.0:
		health = max(0.0, health - delta * 1.0)


func simulate(delta: float, game: Node) -> void:
	if health <= 0.0:
		velocity = Vector3.ZERO
		return

	var desired_direction := Vector3.ZERO
	var player: CharacterBody3D = game.player
	var player_delta: Vector3 = player.global_position - global_position
	player_delta.y = 0.0
	var player_distance: float = player_delta.length()
	var action := str(decision.get("action", "wander"))

	match action:
		"rest":
			energy = min(100.0, energy + delta * 8.0)
		"flee":
			if player_distance > 0.1:
				desired_direction = (-player_delta).normalized()
			move_speed = _species_speed() * 1.12
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
		"stalk":
			if player_distance > 8.0:
				desired_direction = player_delta.normalized()
			elif player_distance < 4.0:
				desired_direction = (-player_delta).normalized()
			else:
				var strafe := Vector3(player_delta.z, 0.0, -player_delta.x).normalized()
				desired_direction = strafe
			move_speed = _species_speed() * 0.92
		"attack":
			move_speed = _species_speed() * 1.2
			if player_distance > 0.2:
				desired_direction = player_delta.normalized()
			if player_distance <= _attack_range() and attack_cooldown <= 0.0:
				var damage := 7.0 + aggression * 0.06
				game.damage_player("%s the %s" % [display_name, species], damage)
				attack_cooldown = 1.0 if species == "wolf" else 1.35
				remember("Lunged at the player")
		"guard":
			var guard_point: Vector3 = game.guard_target_for(self)
			var to_guard := guard_point - global_position
			to_guard.y = 0.0
			if to_guard.length() > 1.6:
				desired_direction = to_guard.normalized()
			elif player_distance < 7.0 and aggression > 42.0:
				desired_direction = player_delta.normalized()
		_:
			if roam_target == Vector3.ZERO or global_position.distance_to(roam_target) < 1.6:
				roam_target = game.random_world_point()
			var to_target := roam_target - global_position
			to_target.y = 0.0
			if to_target.length() > 0.2:
				desired_direction = to_target.normalized()
			move_speed = _species_speed()

	var target_speed := _species_speed()
	if action == "rest":
		target_speed = 0.0
	elif action == "flee":
		target_speed = _species_speed() * 1.12
	elif action == "stalk":
		target_speed = _species_speed() * 0.92
	elif action == "attack":
		target_speed = _species_speed() * 1.2

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
	_animate_visuals(horizontal, delta, action)


func _animate_visuals(horizontal: Vector3, delta: float, action: String) -> void:
	if body_root == null:
		return

	var stride: float = clampf(horizontal.length() / max(_species_speed(), 0.1), 0.0, 1.0)
	var gait_time := Time.get_ticks_msec() / 1000.0 * (7.5 if species == "scavenger" else 8.8) + stride_phase_offset
	body_root.position.y = lerpf(body_root.position.y, _body_base_height() + sin(gait_time * 2.0) * 0.02 * stride, delta * 10.0)

	var pitch_target := 0.0
	if action == "attack":
		pitch_target = deg_to_rad(8.0)
	elif action == "flee":
		pitch_target = deg_to_rad(4.5)
	elif action == "rest":
		pitch_target = deg_to_rad(-4.0)
	body_root.rotation.x = lerpf(body_root.rotation.x, pitch_target, delta * 8.0)
	body_root.rotation.z = lerpf(body_root.rotation.z, sin(gait_time) * 0.025 * stride, delta * 7.0)

	if head_anchor != null:
		head_anchor.rotation.x = lerpf(head_anchor.rotation.x, -pitch_target * 0.35 + sin(gait_time + 0.4) * 0.05 * stride, delta * 9.0)
	if tail_anchor != null:
		var tail_swing := 0.18 if species == "scavenger" else 0.34
		tail_anchor.rotation.y = lerpf(tail_anchor.rotation.y, sin(gait_time * 1.1) * tail_swing * max(stride, 0.2), delta * 8.0)
		tail_anchor.rotation.x = lerpf(tail_anchor.rotation.x, deg_to_rad(12.0) - pitch_target * 0.3, delta * 8.0)

	for index in range(leg_nodes.size()):
		var leg := leg_nodes[index]
		var phase_shift := PI if index % 2 == 1 else 0.0
		if species == "boar":
			phase_shift += PI * 0.1 if index < 2 else -PI * 0.1
		var leg_angle := sin(gait_time + phase_shift) * 0.62 * stride
		if action == "rest":
			leg_angle = 0.0
		leg.rotation.x = lerpf(leg.rotation.x, leg_angle, delta * 12.0)
		leg.position.y = lerpf(leg.position.y, _leg_mount_height() + abs(sin(gait_time + phase_shift)) * 0.04 * stride, delta * 12.0)


func _species_speed() -> float:
	match species:
		"wolf":
			return 5.9
		"boar":
			return 4.2
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
		_:
			return 1.6


func _body_base_height() -> float:
	match species:
		"wolf":
			return 0.04
		"boar":
			return 0.02
		_:
			return 0.06


func _leg_mount_height() -> float:
	match species:
		"wolf":
			return 0.56
		"boar":
			return 0.48
		_:
			return 0.78


func _build_visuals() -> void:
	for child in get_children():
		child.queue_free()
	leg_nodes.clear()
	torso_anchor = null
	head_anchor = null
	tail_anchor = null

	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.46 if species == "wolf" else (0.52 if species == "boar" else 0.38)
	capsule.height = 1.0 if species == "wolf" else (1.0 if species == "boar" else 1.32)
	collision.shape = capsule
	collision.position = Vector3(0.0, 0.74 if species == "wolf" else (0.66 if species == "boar" else 0.96), 0.0)
	add_child(collision)

	shadow_mesh = MeshInstance3D.new()
	var shadow := CylinderMesh.new()
	shadow.top_radius = 0.72
	shadow.bottom_radius = 0.72
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
	_add_box(torso_anchor, Vector3(0.0, 0.76, -0.16), Vector3(0.36, 0.14, 1.34), accent)

	head_anchor = Node3D.new()
	head_anchor.position = Vector3(0.0, 0.72, 0.72)
	shell_root.add_child(head_anchor)
	_add_sphere(head_anchor, Vector3(0.0, 0.02, 0.0), Vector3(0.95, 0.72, 1.18), fur, 0.26)
	_add_box(head_anchor, Vector3(0.0, -0.04, 0.34), Vector3(0.16, 0.12, 0.46), accent)
	_add_box(head_anchor, Vector3(-0.12, 0.22, -0.05), Vector3(0.08, 0.22, 0.08), accent, Vector3(0.0, 0.0, deg_to_rad(16.0)))
	_add_box(head_anchor, Vector3(0.12, 0.22, -0.05), Vector3(0.08, 0.22, 0.08), accent, Vector3(0.0, 0.0, deg_to_rad(-16.0)))
	_add_sphere(head_anchor, Vector3(-0.1, 0.06, 0.32), Vector3.ONE, eye, 0.04)
	_add_sphere(head_anchor, Vector3(0.1, 0.06, 0.32), Vector3.ONE, eye, 0.04)

	tail_anchor = Node3D.new()
	tail_anchor.position = Vector3(0.0, 0.76, -0.94)
	shell_root.add_child(tail_anchor)
	_add_capsule(tail_anchor, Vector3(0.0, 0.0, -0.12), Vector3(0.28, 0.28, 0.96), accent, 0.08, 0.36, Vector3(deg_to_rad(30.0), 0.0, 0.0))

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
	_add_box(torso_anchor, Vector3(0.0, 0.84, 0.08), Vector3(0.12, 0.12, 0.68), material_palette.get("boar_mane", material_palette.get("coal")))

	head_anchor = Node3D.new()
	head_anchor.position = Vector3(0.0, 0.6, 0.76)
	shell_root.add_child(head_anchor)
	_add_box(head_anchor, Vector3(0.0, 0.0, 0.04), Vector3(0.54, 0.34, 0.82), snout_material)
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

	head_anchor = Node3D.new()
	head_anchor.position = Vector3(0.0, 1.56, 0.08)
	shell_root.add_child(head_anchor)
	_add_sphere(head_anchor, Vector3(0.0, 0.0, 0.0), Vector3(0.7, 0.78, 0.74), skin, 0.24)
	_add_box(head_anchor, Vector3(0.0, 0.08, -0.12), Vector3(0.52, 0.28, 0.46), robe)
	_add_box(head_anchor, Vector3(0.0, -0.34, 0.18), Vector3(0.42, 0.08, 0.12), trim)

	_add_leg(shell_root, Vector3(-0.42, 1.02, 0.02), Vector3(0.12, 0.56, 0.12), robe, true)
	_add_leg(shell_root, Vector3(0.42, 1.02, 0.02), Vector3(0.12, 0.56, 0.12), robe, true)
	_add_leg(shell_root, Vector3(-0.16, 0.78, 0.0), Vector3(0.12, 0.72, 0.12), robe)
	_add_leg(shell_root, Vector3(0.16, 0.78, 0.0), Vector3(0.12, 0.72, 0.12), robe)


func _add_leg(parent: Node3D, mount_position: Vector3, size: Vector3, material: Material, horizontal: bool = false) -> void:
	var pivot := Node3D.new()
	pivot.position = mount_position
	parent.add_child(pivot)
	leg_nodes.append(pivot)

	var limb := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	limb.mesh = mesh
	limb.position = Vector3(0.0, -size.y * 0.5, 0.0) if not horizontal else Vector3(0.0, -size.y * 0.32, 0.0)
	limb.material_override = material
	pivot.add_child(limb)


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
