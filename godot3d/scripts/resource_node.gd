extends Node3D
class_name ResourceNode3D

var resource_id := ""
var resource_type := "berries"
var amount := 4
var respawn_amount := 4
var respawn_delay := 18.0
var respawn_timer := 0.0
var gather_radius := 2.8
var shell: Node3D
var bob_offset := 0.0
var material_palette: Dictionary = {}


func _ready() -> void:
	bob_offset = randf() * TAU
	set_process(true)


func configure(id: String, kind: String, initial_amount: int) -> void:
	resource_id = id
	resource_type = kind
	amount = initial_amount
	respawn_amount = initial_amount
	match resource_type:
		"ore":
			respawn_delay = 26.0
			gather_radius = 3.0
		"fiber", "herb":
			respawn_delay = 16.0
			gather_radius = 2.9
		_:
			respawn_delay = 18.0
			gather_radius = 2.8


func apply_material_palette(palette: Dictionary) -> void:
	material_palette = palette
	_rebuild_visual()


func is_available() -> bool:
	return amount > 0


func harvest(units: int = 1) -> bool:
	if amount < units:
		return false
	amount -= units
	if amount <= 0:
		amount = 0
		respawn_timer = respawn_delay
	visible = amount > 0
	return true


func tick(delta: float) -> void:
	if amount > 0:
		return
	respawn_timer -= delta
	if respawn_timer <= 0.0:
		amount = respawn_amount
		visible = true


func _process(_delta: float) -> void:
	if shell:
		shell.position.y = 0.22 + sin(Time.get_ticks_msec() / 1000.0 * 2.2 + bob_offset) * 0.05
	rotation.y += 0.003


func _rebuild_visual() -> void:
	for child in get_children():
		child.queue_free()

	shell = Node3D.new()
	add_child(shell)

	var shadow := MeshInstance3D.new()
	var shadow_mesh := CylinderMesh.new()
	shadow_mesh.top_radius = 0.75
	shadow_mesh.bottom_radius = 0.75
	shadow_mesh.height = 0.04
	shadow.mesh = shadow_mesh
	shadow.position = Vector3(0.0, 0.02, 0.0)
	var shadow_material := StandardMaterial3D.new()
	shadow_material.albedo_color = Color(0.02, 0.03, 0.02, 0.45)
	shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow.material_override = shadow_material
	add_child(shadow)

	match resource_type:
		"berries":
			_build_berry_bush()
		"wood":
			_build_log_pile()
		"fiber":
			_build_fiber_bundle()
		"herb":
			_build_herb_patch()
		"ore":
			_build_ore_vein()
		_:
			_build_stone_stack()


func _build_berry_bush() -> void:
	var leaf_material = material_palette.get("foliage")
	var berry_material = material_palette.get("berries")
	var stem_material = material_palette.get("bark")

	for offset in [Vector3(-0.35, 0.18, -0.15), Vector3(0.0, 0.24, 0.0), Vector3(0.34, 0.2, 0.18), Vector3(0.16, 0.32, -0.28)]:
		var leaf := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.34
		mesh.height = 0.68
		leaf.mesh = mesh
		leaf.position = offset
		leaf.material_override = leaf_material
		shell.add_child(leaf)

	var stem := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.08
	cylinder.bottom_radius = 0.12
	cylinder.height = 0.46
	stem.mesh = cylinder
	stem.position = Vector3(0.0, 0.22, 0.0)
	stem.material_override = stem_material
	shell.add_child(stem)

	for offset in [Vector3(-0.22, 0.18, 0.16), Vector3(0.14, 0.3, -0.14), Vector3(0.28, 0.15, 0.06), Vector3(-0.05, 0.34, 0.18)]:
		var berry := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.1
		sphere.height = 0.2
		berry.mesh = sphere
		berry.position = offset
		berry.material_override = berry_material
		shell.add_child(berry)


func _build_log_pile() -> void:
	var bark_material = material_palette.get("bark")
	for data in [
		{"position": Vector3(-0.18, 0.16, 0.0), "rotation": Vector3(0.0, 0.0, deg_to_rad(90.0))},
		{"position": Vector3(0.18, 0.14, 0.1), "rotation": Vector3(0.0, 0.4, deg_to_rad(90.0))},
		{"position": Vector3(0.0, 0.28, -0.14), "rotation": Vector3(0.0, 1.1, deg_to_rad(90.0))}
	]:
		var log_mesh := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.16
		cylinder.bottom_radius = 0.18
		cylinder.height = 1.12
		log_mesh.mesh = cylinder
		log_mesh.position = data["position"]
		log_mesh.rotation = data["rotation"]
		log_mesh.material_override = bark_material
		shell.add_child(log_mesh)


func _build_stone_stack() -> void:
	var stone_material = material_palette.get("stone")
	for offset in [Vector3(-0.25, 0.16, -0.1), Vector3(0.1, 0.24, 0.12), Vector3(0.28, 0.14, -0.18), Vector3(0.0, 0.38, 0.0)]:
		var rock := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.25
		mesh.height = 0.42
		rock.mesh = mesh
		rock.position = offset
		rock.scale = Vector3(1.0 + randf() * 0.35, 0.75 + randf() * 0.25, 0.9 + randf() * 0.4)
		rock.material_override = stone_material
		shell.add_child(rock)


func _build_fiber_bundle() -> void:
	var reed_material = material_palette.get("reed", material_palette.get("grass_tuft"))
	for index in range(6):
		var blade := MeshInstance3D.new()
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(0.16, 0.72 + randf() * 0.18)
		blade.mesh = mesh
		blade.position = Vector3(randf_range(-0.22, 0.22), 0.34, randf_range(-0.18, 0.18))
		blade.rotation_degrees = Vector3(randf_range(-7.0, 9.0), index * 28.0 + randf_range(-10.0, 10.0), randf_range(-6.0, 6.0))
		blade.material_override = reed_material
		shell.add_child(blade)


func _build_herb_patch() -> void:
	var leaf_material = material_palette.get("foliage_meadow", material_palette.get("foliage"))
	var bloom_material = material_palette.get("flower_blue", material_palette.get("flower_gold"))
	for offset in [Vector3(-0.18, 0.14, -0.1), Vector3(0.0, 0.18, 0.0), Vector3(0.2, 0.16, 0.08)]:
		var leaf := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.2
		mesh.height = 0.26
		leaf.mesh = mesh
		leaf.position = offset
		leaf.scale = Vector3(1.2, 0.65, 1.15)
		leaf.material_override = leaf_material
		shell.add_child(leaf)

		var bloom := MeshInstance3D.new()
		var bloom_mesh := SphereMesh.new()
		bloom_mesh.radius = 0.06
		bloom_mesh.height = 0.12
		bloom.mesh = bloom_mesh
		bloom.position = offset + Vector3(0.0, 0.16, 0.0)
		bloom.material_override = bloom_material
		shell.add_child(bloom)


func _build_ore_vein() -> void:
	var stone_material = material_palette.get("stone")
	var highlight_material = material_palette.get("stone_highlight", stone_material)
	for offset in [Vector3(-0.22, 0.2, -0.06), Vector3(0.12, 0.3, 0.08), Vector3(0.24, 0.18, -0.14)]:
		var rock := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.26
		mesh.height = 0.44
		rock.mesh = mesh
		rock.position = offset
		rock.scale = Vector3(1.15, 0.82, 1.0 + randf() * 0.2)
		rock.material_override = stone_material
		shell.add_child(rock)

		var shard := MeshInstance3D.new()
		var shard_mesh := BoxMesh.new()
		shard_mesh.size = Vector3(0.08, 0.2, 0.08)
		shard.mesh = shard_mesh
		shard.position = offset + Vector3(0.02, 0.12, -0.01)
		shard.rotation_degrees = Vector3(randf_range(-18.0, 18.0), randf_range(0.0, 180.0), randf_range(-14.0, 14.0))
		shard.material_override = highlight_material
		shell.add_child(shard)
