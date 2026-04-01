extends Node3D
class_name CampfireNode

var fuel := 60.0
var warmth_radius := 5.0
var fire_root: Node3D
var glow: OmniLight3D
var material_palette: Dictionary = {}


func _ready() -> void:
	_rebuild_visual()


func apply_material_palette(palette: Dictionary) -> void:
	material_palette = palette
	_rebuild_visual()


func tick(delta: float, is_night: bool) -> void:
	if fuel <= 0.0:
		visible = false
		return
	fuel -= delta * (1.15 if is_night else 0.72)
	visible = fuel > 0.0
	if glow:
		glow.visible = fuel > 0.0
		glow.light_energy = 1.6 + sin(Time.get_ticks_msec() / 1000.0 * 9.0) * 0.25
	if fire_root:
		fire_root.rotation.y += delta * 0.35


func _rebuild_visual() -> void:
	for child in get_children():
		child.queue_free()

	fire_root = Node3D.new()
	add_child(fire_root)

	for data in [
		{"position": Vector3(-0.26, 0.12, 0.0), "rotation": Vector3(0.0, deg_to_rad(20.0), deg_to_rad(90.0))},
		{"position": Vector3(0.26, 0.12, -0.02), "rotation": Vector3(0.0, deg_to_rad(-18.0), deg_to_rad(90.0))},
		{"position": Vector3(0.0, 0.14, 0.24), "rotation": Vector3(0.0, deg_to_rad(96.0), deg_to_rad(90.0))}
	]:
		var log_mesh := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.09
		cylinder.bottom_radius = 0.12
		cylinder.height = 0.86
		log_mesh.mesh = cylinder
		log_mesh.position = data["position"]
		log_mesh.rotation = data["rotation"]
		log_mesh.material_override = material_palette.get("bark")
		fire_root.add_child(log_mesh)

	var coal := MeshInstance3D.new()
	var coal_mesh := SphereMesh.new()
	coal_mesh.radius = 0.18
	coal_mesh.height = 0.24
	coal.mesh = coal_mesh
	coal.position = Vector3(0.0, 0.1, 0.0)
	coal.material_override = material_palette.get("coal")
	fire_root.add_child(coal)

	var flame_a := MeshInstance3D.new()
	var flame_mesh := SphereMesh.new()
	flame_mesh.radius = 0.22
	flame_mesh.height = 0.44
	flame_a.mesh = flame_mesh
	flame_a.position = Vector3(0.0, 0.42, 0.0)
	flame_a.scale = Vector3(0.8, 1.4, 0.8)
	flame_a.material_override = material_palette.get("flame")
	fire_root.add_child(flame_a)

	var flame_b := MeshInstance3D.new()
	var flame_mesh_b := SphereMesh.new()
	flame_mesh_b.radius = 0.16
	flame_mesh_b.height = 0.34
	flame_b.mesh = flame_mesh_b
	flame_b.position = Vector3(0.08, 0.6, -0.02)
	flame_b.scale = Vector3(0.7, 1.2, 0.7)
	flame_b.material_override = material_palette.get("flame_tip")
	fire_root.add_child(flame_b)

	glow = OmniLight3D.new()
	glow.position = Vector3(0.0, 0.7, 0.0)
	glow.light_color = Color(1.0, 0.76, 0.45)
	glow.light_energy = 1.7
	glow.omni_range = 11.0
	glow.shadow_enabled = false
	add_child(glow)
