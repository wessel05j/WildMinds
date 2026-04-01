extends CharacterBody3D
class_name PlayerController

var health := 100.0
var hunger := 18.0
var energy := 100.0
var inventory := {
	"berries": 0,
	"wood": 0,
	"stone": 0,
}

var move_speed := 8.2
var gravity_strength := 28.0
var input_direction := Vector3.ZERO
var move_direction := Vector3.ZERO
var body_mesh: MeshInstance3D
var head_mesh: MeshInstance3D
var backpack_mesh: MeshInstance3D
var scarf_mesh: MeshInstance3D
var camera_pivot: Node3D
var camera_arm: SpringArm3D
var camera: Camera3D
var material_palette: Dictionary = {}


func _ready() -> void:
	floor_snap_length = 0.45
	_build_visuals()
	_build_camera()


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


func _capture_input() -> void:
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var forward := -camera.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := camera.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	input_direction = right * input_vector.x + forward * input_vector.y
	if input_direction.length() > 1.0:
		input_direction = input_direction.normalized()


func _move_character(delta: float) -> void:
	var acceleration := 22.0 if input_direction.length() > 0.01 else 14.0
	var target_velocity := input_direction * move_speed
	velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)

	if not is_on_floor():
		velocity.y -= gravity_strength * delta
	else:
		velocity.y = min(velocity.y, 0.0)

	move_and_slide()

	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	move_direction = horizontal_velocity.normalized() if horizontal_velocity.length() > 0.1 else Vector3.ZERO
	if move_direction.length() > 0.1:
		var target_yaw := atan2(move_direction.x, move_direction.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, delta * 10.0)


func tick_survival(delta: float, is_night: bool, near_fire: bool) -> void:
	hunger = min(100.0, hunger + delta * 1.35)
	if move_direction.length() > 0.05:
		energy = max(0.0, energy - delta * 3.8)
	else:
		energy = min(100.0, energy + delta * 2.6)

	if is_night:
		energy = max(0.0, energy - delta * 0.9)

	if near_fire:
		energy = min(100.0, energy + delta * 6.0)
		health = min(100.0, health + delta * 1.1)

	if hunger > 84.0:
		health = max(0.0, health - delta * 3.0)
	if energy <= 0.0:
		health = max(0.0, health - delta * 1.8)


func add_resource(kind: String, amount: int = 1) -> void:
	inventory[kind] = int(inventory.get(kind, 0)) + amount


func has_resource(kind: String, amount: int = 1) -> bool:
	return int(inventory.get(kind, 0)) >= amount


func consume_resource(kind: String, amount: int = 1) -> bool:
	if not has_resource(kind, amount):
		return false
	inventory[kind] = int(inventory.get(kind, 0)) - amount
	return true


func eat_berry() -> bool:
	if not consume_resource("berries", 1):
		return false
	hunger = max(0.0, hunger - 34.0)
	energy = min(100.0, energy + 7.0)
	return true


func receive_damage(amount: float) -> void:
	health = max(0.0, health - amount)


func _build_camera() -> void:
	camera_pivot = Node3D.new()
	camera_pivot.position = Vector3(0.0, 1.9, 0.0)
	add_child(camera_pivot)

	camera_arm = SpringArm3D.new()
	camera_arm.spring_length = 8.5
	camera_arm.rotation_degrees = Vector3(-34.0, 0.0, 0.0)
	camera_pivot.add_child(camera_arm)

	camera = Camera3D.new()
	camera.current = true
	camera.fov = 68.0
	camera_arm.add_child(camera)


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
	body_mesh.position = Vector3(0.0, 0.95, 0.0)
	add_child(body_mesh)

	head_mesh = MeshInstance3D.new()
	var head := SphereMesh.new()
	head.radius = 0.28
	head.height = 0.56
	head_mesh.mesh = head
	head_mesh.position = Vector3(0.0, 1.72, 0.08)
	add_child(head_mesh)

	backpack_mesh = MeshInstance3D.new()
	var pack := BoxMesh.new()
	pack.size = Vector3(0.36, 0.42, 0.18)
	backpack_mesh.mesh = pack
	backpack_mesh.position = Vector3(0.0, 1.05, -0.34)
	add_child(backpack_mesh)

	scarf_mesh = MeshInstance3D.new()
	var scarf := BoxMesh.new()
	scarf.size = Vector3(0.48, 0.08, 0.16)
	scarf_mesh.mesh = scarf
	scarf_mesh.position = Vector3(0.0, 1.48, 0.12)
	add_child(scarf_mesh)
