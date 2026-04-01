extends CharacterBody3D
class_name PlayerController

var health := 100.0
var hunger := 18.0
var energy := 100.0
var inventory := {
	"berries": 0,
	"wood": 0,
	"stone": 0,
	"fiber": 0,
	"herb": 0,
	"ore": 0,
	"hide": 0,
	"bandage": 0,
	"trail_ration": 0,
	"spear": 0,
	"tower_braces": 0,
	"signal_core": 0,
	"beacon_lens": 0,
}
var skill_xp := {
	"foraging": 0,
	"crafting": 0,
	"combat": 0,
}

var move_speed := 8.2
var gravity_strength := 28.0
var jump_velocity := 8.6
var mouse_sensitivity := 0.0024
var look_pitch := 0.0
var input_direction := Vector3.ZERO
var move_direction := Vector3.ZERO
var body_mesh: MeshInstance3D
var head_mesh: MeshInstance3D
var backpack_mesh: MeshInstance3D
var scarf_mesh: MeshInstance3D
var camera_pivot: Node3D
var camera: Camera3D
var material_palette: Dictionary = {}
var camera_base_position := Vector3.ZERO
var headbob_time := 0.0
var landing_bounce := 0.0
var last_floor_state := false


func _ready() -> void:
	floor_snap_length = 0.45
	_build_visuals()
	_build_camera()
	camera_base_position = camera_pivot.position
	last_floor_state = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func apply_material_palette(palette: Dictionary) -> void:
	material_palette = palette
	if body_mesh:
		body_mesh.material_override = palette.get("player_body")
	if head_mesh:
		head_mesh.material_override = palette.get("player_skin")
	if backpack_mesh:
		backpack_mesh.material_override = palette.get("player_pack")
	if scarf_mesh:
		scarf_mesh.material_override = palette.get("player_scarf")


func _physics_process(delta: float) -> void:
	_capture_input()
	_move_character(delta)
	_update_camera_motion(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * mouse_sensitivity
		look_pitch = clampf(look_pitch - event.relative.y * mouse_sensitivity, deg_to_rad(-82.0), deg_to_rad(82.0))
		camera_pivot.rotation.x = look_pitch

	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif event is InputEventMouseButton and event.pressed and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _capture_input() -> void:
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	input_direction = right * input_vector.x - forward * input_vector.y
	if input_direction.length() > 1.0:
		input_direction = input_direction.normalized()


func _move_character(delta: float) -> void:
	var was_grounded := is_on_floor()
	var fall_speed := velocity.y
	var acceleration := 22.0 if input_direction.length() > 0.01 else 14.0
	var target_velocity := input_direction * move_speed
	velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)

	if not is_on_floor():
		velocity.y -= gravity_strength * delta
	else:
		velocity.y = min(velocity.y, 0.0)
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity

	move_and_slide()
	if not was_grounded and is_on_floor() and fall_speed < -3.0:
		landing_bounce = min(0.18, abs(fall_speed) * 0.015)
	last_floor_state = is_on_floor()

	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	move_direction = horizontal_velocity.normalized() if horizontal_velocity.length() > 0.1 else Vector3.ZERO


func tick_survival(delta: float, is_night: bool, near_fire: bool) -> void:
	if health <= 0.0:
		return

	var food_drain := delta * 0.15
	var energy_regen := 0.0

	if move_direction.length() > 0.05:
		energy = max(0.0, energy - delta * 2.25)
		food_drain += delta * 0.08
	else:
		energy_regen += delta * 0.9

	if is_night:
		energy = max(0.0, energy - delta * 0.28)
		food_drain += delta * 0.02

	if near_fire:
		energy_regen += delta * 1.8

	if energy_regen > 0.0:
		var energy_before := energy
		energy = min(100.0, energy + energy_regen)
		food_drain += (energy - energy_before) * 0.18

	if hunger < 36.0 and energy > 20.0 and health < 100.0:
		var heal_rate := 0.28 + (0.22 if near_fire else 0.0)
		var health_before := health
		health = min(100.0, health + delta * heal_rate)
		food_drain += (health - health_before) * 0.45

	hunger = min(100.0, hunger + food_drain)

	if hunger > 92.0:
		health = max(0.0, health - delta * 1.6)
	if energy <= 0.0:
		health = max(0.0, health - delta * 0.8)


func add_resource(kind: String, amount: int = 1) -> void:
	inventory[kind] = int(inventory.get(kind, 0)) + amount


func get_count(kind: String) -> int:
	return int(inventory.get(kind, 0))


func has_resource(kind: String, amount: int = 1) -> bool:
	return get_count(kind) >= amount


func consume_resource(kind: String, amount: int = 1) -> bool:
	if not has_resource(kind, amount):
		return false
	inventory[kind] = get_count(kind) - amount
	return true


func gain_skill(skill_name: String, amount: int = 1) -> void:
	skill_xp[skill_name] = int(skill_xp.get(skill_name, 0)) + amount


func skill_level(skill_name: String) -> int:
	return 1 + int(int(skill_xp.get(skill_name, 0)) / 4)


func attack_damage() -> float:
	var damage := 26.0 + float(skill_level("combat") - 1) * 2.5
	if has_resource("spear", 1):
		damage += 8.0
	return damage


func attack_cooldown_scale() -> float:
	return max(0.62, 1.0 - float(skill_level("combat") - 1) * 0.06)


func eat_berry() -> bool:
	if not consume_resource("berries", 1):
		return false
	hunger = max(0.0, hunger - 34.0)
	energy = min(100.0, energy + 7.0)
	gain_skill("foraging", 1)
	return true


func use_bandage() -> bool:
	if not consume_resource("bandage", 1):
		return false
	health = min(100.0, health + 24.0)
	energy = max(0.0, energy - 3.0)
	return true


func use_trail_ration() -> bool:
	if not consume_resource("trail_ration", 1):
		return false
	hunger = max(0.0, hunger - 42.0)
	energy = min(100.0, energy + 12.0)
	return true


func receive_damage(amount: float) -> void:
	health = max(0.0, health - amount)
	landing_bounce = min(0.2, landing_bounce + amount * 0.0026)


func set_controls_enabled(enabled: bool) -> void:
	set_physics_process(enabled)
	set_process_unhandled_input(enabled)
	if not enabled:
		input_direction = Vector3.ZERO
		move_direction = Vector3.ZERO
		velocity = Vector3.ZERO


func reset_state(spawn_position: Vector3) -> void:
	global_position = spawn_position
	velocity = Vector3.ZERO
	input_direction = Vector3.ZERO
	move_direction = Vector3.ZERO
	health = 100.0
	hunger = 22.0
	energy = 74.0
	look_pitch = 0.0
	headbob_time = 0.0
	landing_bounce = 0.0
	camera_pivot.rotation.x = 0.0
	camera_pivot.position = camera_base_position
	camera.rotation.z = 0.0


func view_forward() -> Vector3:
	return -camera.global_transform.basis.z.normalized()


func view_forward_flat() -> Vector3:
	var forward := view_forward()
	forward.y = 0.0
	return forward.normalized()


func eye_position() -> Vector3:
	return camera.global_position


func _build_camera() -> void:
	camera_pivot = Node3D.new()
	camera_pivot.position = Vector3(0.0, 1.58, 0.0)
	add_child(camera_pivot)

	camera = Camera3D.new()
	camera.current = true
	camera.fov = 78.0
	camera.near = 0.05
	camera.far = 2200.0
	camera_pivot.add_child(camera)


func _update_camera_motion(delta: float) -> void:
	if camera_pivot == null or camera == null:
		return

	landing_bounce = move_toward(landing_bounce, 0.0, delta * 2.6)
	var speed_factor := clampf(Vector2(velocity.x, velocity.z).length() / max(move_speed, 0.1), 0.0, 1.0)
	if is_on_floor() and speed_factor > 0.05:
		headbob_time += delta * lerpf(6.0, 9.4, speed_factor)
	else:
		headbob_time = lerpf(headbob_time, 0.0, delta * 1.3)

	var sway_x: float = sin(headbob_time) * 0.03 * speed_factor
	var sway_y: float = abs(cos(headbob_time * 2.0)) * 0.04 * speed_factor
	var target_position := camera_base_position + Vector3(sway_x, sway_y - landing_bounce, 0.0)
	if not is_on_floor():
		target_position.y -= 0.02
	camera_pivot.position = camera_pivot.position.lerp(target_position, delta * 8.0)

	var target_roll: float = -input_direction.x * 0.045 + sin(headbob_time) * 0.01 * speed_factor
	camera.rotation.z = lerpf(camera.rotation.z, target_roll, delta * 9.0)


func _build_visuals() -> void:
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.46
	capsule.height = 1.1
	collision.shape = capsule
	add_child(collision)

	body_mesh = MeshInstance3D.new()
	var body := CapsuleMesh.new()
	body.radius = 0.46
	body.height = 0.92
	body_mesh.mesh = body
	body_mesh.position = Vector3(0.0, -20.0, 0.0)
	add_child(body_mesh)

	head_mesh = MeshInstance3D.new()
	var head := SphereMesh.new()
	head.radius = 0.28
	head.height = 0.56
	head_mesh.mesh = head
	head_mesh.position = Vector3(0.0, -20.0, 0.08)
	add_child(head_mesh)

	backpack_mesh = MeshInstance3D.new()
	var pack := BoxMesh.new()
	pack.size = Vector3(0.36, 0.42, 0.18)
	backpack_mesh.mesh = pack
	backpack_mesh.position = Vector3(0.0, -20.0, -0.34)
	add_child(backpack_mesh)

	scarf_mesh = MeshInstance3D.new()
	var scarf := BoxMesh.new()
	scarf.size = Vector3(0.48, 0.08, 0.16)
	scarf_mesh.mesh = scarf
	scarf_mesh.position = Vector3(0.0, -20.0, 0.12)
	add_child(scarf_mesh)
