extends Node3D

const PlayerController = preload("res://scripts/player_controller.gd")
const CreatureActor = preload("res://scripts/creature_actor.gd")
const ResourceNode3D = preload("res://scripts/resource_node.gd")
const CampfireNode = preload("res://scripts/campfire.gd")
const AIBridge = preload("res://scripts/ai_bridge.gd")

const WORLD_RADIUS := 54.0
const TERRAIN_RESOLUTION := 88
const RESOURCE_CONFIG := [
	{"kind": "berries", "count": 18, "amount": 4},
	{"kind": "wood", "count": 12, "amount": 3},
	{"kind": "stone", "count": 10, "amount": 4},
]
const NAME_POOLS := {
	"wolf": ["Ash", "Fen", "Rook", "Thorn", "Morrow", "Slate"],
	"boar": ["Brim", "Tusk", "Cinder", "Bramble", "Ridge"],
	"scavenger": ["Mira", "Vale", "Orin", "Sable", "Kest", "Nera"],
}

var terrain_noise := FastNoiseLite.new()
var detail_noise := FastNoiseLite.new()
var world_root: Node3D
var terrain_mesh_instance: MeshInstance3D
var terrain_body: StaticBody3D
var water_mesh_instance: MeshInstance3D
var player: PlayerController
var ai_bridge: AIBridge

var resources: Array = []
var creatures: Array = []
var creature_lookup := {}
var campfires: Array = []
var used_names := {}
var material_palette := {}

var ui_root: CanvasLayer
var message_label: Label
var ai_status_label: Label
var creature_log_label: Label
var health_label: Label
var hunger_label: Label
var energy_label: Label
var health_bar: ProgressBar
var hunger_bar: ProgressBar
var energy_bar: ProgressBar
var berries_label: Label
var wood_label: Label
var stone_label: Label

var status_message := ""
var status_timer := 0.0
var ai_status_text := "AI: checking helper service..."
var time_of_day := 0.28
var smoke_test := false
var smoke_elapsed := 0.0
var gather_cooldown := 0.0
var eat_cooldown := 0.0
var attack_cooldown := 0.0
var craft_cooldown := 0.0
var sun_light: DirectionalLight3D
var moon_light: DirectionalLight3D
var sky_material: ProceduralSkyMaterial
var last_ai_error_message := ""


func _ready() -> void:
	randomize()
	smoke_test = OS.get_cmdline_user_args().has("--smoke-test")
	_configure_input_map()
	_prepare_noises()
	_build_material_library()
	_build_environment()
	_build_world()
	_build_ui()

	ai_bridge = AIBridge.new()
	add_child(ai_bridge)
	ai_bridge.status_ready.connect(_on_ai_status_ready)
	ai_bridge.decision_ready.connect(_on_ai_decision_ready)
	ai_bridge.request_failed.connect(_on_ai_request_failed)
	ai_bridge.request_status()

	_show_message("WASD move | E gather | Q eat berry | Space attack | F campfire")


func _physics_process(delta: float) -> void:
	time_of_day = wrapf(time_of_day + delta * 0.0085, 0.0, 1.0)
	gather_cooldown = max(0.0, gather_cooldown - delta)
	eat_cooldown = max(0.0, eat_cooldown - delta)
	attack_cooldown = max(0.0, attack_cooldown - delta)
	craft_cooldown = max(0.0, craft_cooldown - delta)
	status_timer = max(0.0, status_timer - delta)
	smoke_elapsed += delta

	_update_environment_lighting()
	player.tick_survival(delta, _is_night(), _is_near_campfire(player.global_position))
	_handle_player_actions()

	for resource in resources:
		resource.tick(delta)

	var dead_fires: Array = []
	for campfire in campfires:
		campfire.tick(delta, _is_night())
		if campfire.fuel <= 0.0:
			dead_fires.append(campfire)
	for campfire in dead_fires:
		campfires.erase(campfire)
		campfire.queue_free()

	var dead_creatures: Array = []
	for creature in creatures:
		creature.update_metabolism(delta, _is_near_campfire(creature.global_position))
		if creature.health <= 0.0:
			dead_creatures.append(creature)
			continue
		if creature.should_request_decision():
			var payload := {
				"creature": creature.snapshot_payload(),
				"snapshot": _build_snapshot_for(creature),
			}
			if ai_bridge.enqueue_decision(creature.creature_id, payload):
				creature.mark_decision_pending()
		creature.simulate(delta, self)

	for creature in dead_creatures:
		_remove_creature(creature)

	_update_ui()

	if smoke_test and smoke_elapsed >= 3.0:
		print("SMOKE_TEST_OK")
		get_tree().quit()


func _configure_input_map() -> void:
	_bind_key("move_left", KEY_A)
	_bind_key("move_left", KEY_LEFT)
	_bind_key("move_right", KEY_D)
	_bind_key("move_right", KEY_RIGHT)
	_bind_key("move_forward", KEY_W)
	_bind_key("move_forward", KEY_UP)
	_bind_key("move_back", KEY_S)
	_bind_key("move_back", KEY_DOWN)
	_bind_key("interact", KEY_E)
	_bind_key("attack", KEY_SPACE)
	_bind_key("eat_berry", KEY_Q)
	_bind_key("eat_berry", KEY_1)
	_bind_key("eat_berry", KEY_ENTER)
	_bind_key("craft_fire", KEY_F)


func _bind_key(action: String, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for existing in InputMap.action_get_events(action):
		if existing is InputEventKey and existing.physical_keycode == keycode:
			return
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)


func _prepare_noises() -> void:
	terrain_noise.seed = randi()
	terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	terrain_noise.frequency = 0.045
	terrain_noise.fractal_octaves = 4
	terrain_noise.fractal_gain = 0.55
	terrain_noise.fractal_lacunarity = 2.1

	detail_noise.seed = randi()
	detail_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	detail_noise.frequency = 0.12
	detail_noise.fractal_octaves = 3


func _build_material_library() -> void:
	material_palette = {
		"ground_grass": _make_material(Color(0.28, 0.44, 0.25), 0.98, 0.0, Color(0.0, 0.0, 0.0), _make_noise_texture(14, 0.035)),
		"ground_soil": _make_material(Color(0.39, 0.31, 0.22), 1.0, 0.0, Color(0.0, 0.0, 0.0), _make_noise_texture(42, 0.06)),
		"foliage": _make_material(Color(0.39, 0.55, 0.31), 0.94, 0.0, Color(0.0, 0.0, 0.0), _make_noise_texture(61, 0.085)),
		"bark": _make_material(Color(0.43, 0.31, 0.2), 0.97, 0.0, Color(0.0, 0.0, 0.0), _make_noise_texture(75, 0.14)),
		"stone": _make_material(Color(0.47, 0.49, 0.48), 0.93, 0.0, Color(0.0, 0.0, 0.0), _make_noise_texture(88, 0.12)),
		"stone_highlight": _make_material(Color(0.63, 0.62, 0.58), 0.9),
		"berries": _make_material(Color(0.77, 0.28, 0.4), 0.75),
		"player_body": _make_material(Color(0.18, 0.42, 0.69), 0.7),
		"player_skin": _make_material(Color(0.88, 0.75, 0.63), 0.86),
		"player_pack": _make_material(Color(0.48, 0.33, 0.18), 0.94),
		"player_scarf": _make_material(Color(0.86, 0.73, 0.32), 0.65),
		"coal": _make_material(Color(0.14, 0.12, 0.1), 0.98),
		"flame": _make_material(Color(0.95, 0.49, 0.16), 0.42, 0.0, Color(0.68, 0.22, 0.02)),
		"flame_tip": _make_material(Color(0.98, 0.8, 0.45), 0.3, 0.0, Color(0.84, 0.56, 0.14)),
		"wolf_fur": _make_material(Color(0.48, 0.52, 0.55), 0.92, 0.0, Color(0.0, 0.0, 0.0), _make_noise_texture(91, 0.18)),
		"wolf_accent": _make_material(Color(0.17, 0.18, 0.2), 0.94),
		"boar_hide": _make_material(Color(0.34, 0.23, 0.15), 0.96, 0.0, Color(0.0, 0.0, 0.0), _make_noise_texture(105, 0.16)),
		"boar_snout": _make_material(Color(0.46, 0.34, 0.25), 0.91),
		"boar_mane": _make_material(Color(0.12, 0.08, 0.07), 0.99),
		"tusk": _make_material(Color(0.88, 0.84, 0.74), 0.8),
		"scavenger_robe": _make_material(Color(0.19, 0.22, 0.2), 0.95, 0.0, Color(0.0, 0.0, 0.0), _make_noise_texture(119, 0.09)),
		"scavenger_trim": _make_material(Color(0.52, 0.36, 0.22), 0.92),
		"water": _make_material(Color(0.15, 0.32, 0.37, 0.72), 0.12, 0.02, Color(0.02, 0.05, 0.06), _make_noise_texture(132, 0.04), true),
	}


func _make_material(
	color: Color,
	roughness: float,
	metallic: float = 0.0,
	emission: Color = Color(0, 0, 0),
	texture: Texture2D = null,
	transparent: bool = false
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	material.emission_enabled = emission != Color(0, 0, 0)
	material.emission = emission
	if texture != null:
		material.albedo_texture = texture
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _make_noise_texture(seed_value: int, frequency: float) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = frequency
	noise.fractal_octaves = 4
	var texture := NoiseTexture2D.new()
	texture.width = 512
	texture.height = 512
	texture.seamless = true
	texture.noise = noise
	return texture


func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 1.15
	environment.fog_enabled = true
	environment.fog_density = 0.009
	environment.fog_light_color = Color(0.47, 0.58, 0.52)

	sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.42, 0.58, 0.77)
	sky_material.sky_horizon_color = Color(0.79, 0.77, 0.61)
	sky_material.ground_bottom_color = Color(0.18, 0.22, 0.16)
	sky_material.ground_horizon_color = Color(0.32, 0.34, 0.24)

	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.sky = sky

	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	sun_light = DirectionalLight3D.new()
	sun_light.light_energy = 1.9
	sun_light.shadow_enabled = true
	sun_light.shadow_blur = 0.5
	sun_light.rotation_degrees = Vector3(-48.0, 32.0, 0.0)
	add_child(sun_light)

	moon_light = DirectionalLight3D.new()
	moon_light.light_color = Color(0.47, 0.56, 0.72)
	moon_light.light_energy = 0.18
	moon_light.rotation_degrees = Vector3(40.0, -140.0, 0.0)
	add_child(moon_light)
	_update_environment_lighting()


func _build_world() -> void:
	world_root = Node3D.new()
	add_child(world_root)
	_build_terrain()
	_spawn_landscape_props()
	_spawn_player()
	_spawn_resources()
	_spawn_creatures()


func _build_terrain() -> void:
	var terrain_mesh := _generate_terrain_mesh()
	terrain_mesh_instance = MeshInstance3D.new()
	terrain_mesh_instance.mesh = terrain_mesh
	terrain_mesh_instance.material_override = material_palette["ground_grass"]
	world_root.add_child(terrain_mesh_instance)

	terrain_body = StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = terrain_mesh.create_trimesh_shape()
	terrain_body.add_child(collision)
	world_root.add_child(terrain_body)

	water_mesh_instance = MeshInstance3D.new()
	var water := PlaneMesh.new()
	water.size = Vector2(WORLD_RADIUS * 1.9, WORLD_RADIUS * 1.9)
	water_mesh_instance.mesh = water
	water_mesh_instance.material_override = material_palette["water"]
	water_mesh_instance.position = Vector3(0.0, -1.35, 0.0)
	water_mesh_instance.rotation_degrees.x = -90.0
	world_root.add_child(water_mesh_instance)


func _generate_terrain_mesh() -> ArrayMesh:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	for x in range(TERRAIN_RESOLUTION):
		for z in range(TERRAIN_RESOLUTION):
			var fx0: float = lerpf(-WORLD_RADIUS, WORLD_RADIUS, float(x) / float(TERRAIN_RESOLUTION))
			var fx1: float = lerpf(-WORLD_RADIUS, WORLD_RADIUS, float(x + 1) / float(TERRAIN_RESOLUTION))
			var fz0: float = lerpf(-WORLD_RADIUS, WORLD_RADIUS, float(z) / float(TERRAIN_RESOLUTION))
			var fz1: float = lerpf(-WORLD_RADIUS, WORLD_RADIUS, float(z + 1) / float(TERRAIN_RESOLUTION))

			var a := Vector3(fx0, _terrain_height(fx0, fz0), fz0)
			var b := Vector3(fx1, _terrain_height(fx1, fz0), fz0)
			var c := Vector3(fx1, _terrain_height(fx1, fz1), fz1)
			var d := Vector3(fx0, _terrain_height(fx0, fz1), fz1)

			_add_terrain_vertex(surface_tool, a)
			_add_terrain_vertex(surface_tool, b)
			_add_terrain_vertex(surface_tool, c)
			_add_terrain_vertex(surface_tool, a)
			_add_terrain_vertex(surface_tool, c)
			_add_terrain_vertex(surface_tool, d)

	surface_tool.generate_normals()
	return surface_tool.commit()


func _add_terrain_vertex(surface_tool: SurfaceTool, vertex: Vector3) -> void:
	surface_tool.set_uv(Vector2(vertex.x * 0.12, vertex.z * 0.12))
	surface_tool.add_vertex(vertex)


func _terrain_height(x_value: float, z_value: float) -> float:
	var large_shape := terrain_noise.get_noise_2d(x_value, z_value) * 4.3
	var detail_shape := detail_noise.get_noise_2d(x_value * 1.6, z_value * 1.6) * 0.9
	var edge_ratio: float = clampf(Vector2(x_value, z_value).length() / WORLD_RADIUS, 0.0, 1.0)
	var shoreline_sink := smoothstep(0.78, 1.0, edge_ratio) * 3.6
	return large_shape + detail_shape - shoreline_sink


func _spawn_landscape_props() -> void:
	for _index in range(34):
		_spawn_tree(random_world_point(-0.15), randf_range(0.85, 1.35))
	for _index in range(14):
		_spawn_rock_cluster(random_world_point(-0.4), randf_range(0.8, 1.45))


func _spawn_tree(position_value: Vector3, scale_factor: float) -> void:
	var tree := Node3D.new()
	tree.position = position_value
	tree.rotation_degrees.y = randf_range(0.0, 360.0)

	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.18 * scale_factor
	trunk_mesh.bottom_radius = 0.26 * scale_factor
	trunk_mesh.height = 2.6 * scale_factor
	trunk.mesh = trunk_mesh
	trunk.position = Vector3(0.0, 1.3 * scale_factor, 0.0)
	trunk.material_override = material_palette["bark"]
	tree.add_child(trunk)

	for canopy_data in [
		{"position": Vector3(-0.7, 3.0, 0.2), "scale": Vector3(1.3, 1.1, 1.2)},
		{"position": Vector3(0.7, 3.3, -0.1), "scale": Vector3(1.15, 1.0, 1.1)},
		{"position": Vector3(0.0, 3.55, 0.0), "scale": Vector3(1.55, 1.22, 1.45)}
	]:
		var canopy := MeshInstance3D.new()
		var canopy_mesh := SphereMesh.new()
		canopy_mesh.radius = 0.9 * scale_factor
		canopy_mesh.height = 1.8 * scale_factor
		canopy.mesh = canopy_mesh
		canopy.position = canopy_data["position"] * scale_factor
		canopy.scale = canopy_data["scale"]
		canopy.material_override = material_palette["foliage"]
		tree.add_child(canopy)

	world_root.add_child(tree)


func _spawn_rock_cluster(position_value: Vector3, scale_factor: float) -> void:
	var cluster := Node3D.new()
	cluster.position = position_value
	cluster.rotation_degrees.y = randf_range(0.0, 360.0)

	for rock_data in [
		{"position": Vector3(-0.38, 0.22, -0.12), "scale": Vector3(1.0, 0.7, 1.1)},
		{"position": Vector3(0.2, 0.34, 0.1), "scale": Vector3(0.8, 1.0, 0.9)},
		{"position": Vector3(0.0, 0.15, 0.28), "scale": Vector3(1.15, 0.6, 1.0)}
	]:
		var rock := MeshInstance3D.new()
		var rock_mesh := SphereMesh.new()
		rock_mesh.radius = 0.42 * scale_factor
		rock_mesh.height = 0.8 * scale_factor
		rock.mesh = rock_mesh
		rock.position = rock_data["position"] * scale_factor
		rock.scale = rock_data["scale"]
		rock.material_override = material_palette["stone"]
		cluster.add_child(rock)

	world_root.add_child(cluster)


func _spawn_player() -> void:
	player = PlayerController.new()
	player.position = Vector3(0.0, _terrain_height(0.0, 0.0) + 0.2, 0.0)
	world_root.add_child(player)
	player.apply_material_palette(material_palette)


func _spawn_resources() -> void:
	var resource_counter := 0
	for config in RESOURCE_CONFIG:
		for _index in range(int(config["count"])):
			var node := ResourceNode3D.new()
			node.configure("resource_%d" % resource_counter, str(config["kind"]), int(config["amount"]))
			node.position = random_world_point(-0.5)
			node.position.y += 0.02
			world_root.add_child(node)
			node.apply_material_palette(material_palette)
			resources.append(node)
			resource_counter += 1


func _spawn_creatures() -> void:
	var spawn_table := [
		{"species": "wolf", "count": 3},
		{"species": "boar", "count": 2},
		{"species": "scavenger", "count": 3},
	]
	var creature_counter := 0
	for row in spawn_table:
		for _index in range(int(row["count"])):
			var creature := CreatureActor.new()
			var spawn_position := random_world_point(0.0)
			while spawn_position.distance_to(player.global_position) < 14.0:
				spawn_position = random_world_point(0.0)
			creature.position = spawn_position
			creature.configure(
				{
					"id": "creature_%d" % creature_counter,
					"name": _take_name(str(row["species"])),
					"species": str(row["species"]),
					"personality": _random_personality(str(row["species"])),
					"max_health": 90.0 if row["species"] == "wolf" else (120.0 if row["species"] == "boar" else 82.0),
					"health": 90.0 if row["species"] == "wolf" else (120.0 if row["species"] == "boar" else 82.0),
					"aggression": 72.0 if row["species"] == "wolf" else (68.0 if row["species"] == "boar" else 44.0),
					"fear": 22.0 if row["species"] == "wolf" else (34.0 if row["species"] == "boar" else 18.0),
					"hunger": randf_range(18.0, 56.0),
					"energy": randf_range(58.0, 92.0),
				}
			)
			world_root.add_child(creature)
			creature.apply_material_palette(material_palette)
			creatures.append(creature)
			creature_lookup[creature.creature_id] = creature
			creature_counter += 1


func _take_name(species_name: String) -> String:
	var pool: Array = NAME_POOLS.get(species_name, [species_name.capitalize()])
	var count := int(used_names.get(species_name, 0))
	used_names[species_name] = count + 1
	if count < pool.size():
		return str(pool[count])
	return "%s %d" % [species_name.capitalize(), count + 1]


func _random_personality(species_name: String) -> String:
	match species_name:
		"wolf":
			return ["patient hunter", "territorial", "coldly aggressive", "pack-minded"][randi() % 4]
		"boar":
			return ["defensive bruiser", "food obsessed", "stubborn", "dangerously reactive"][randi() % 4]
		_:
			return ["opportunistic scavenger", "nervy looter", "cautious rival", "greedy survivor"][randi() % 4]


func random_world_point(min_height: float = -0.35) -> Vector3:
	for _attempt in range(48):
		var x_value := randf_range(-WORLD_RADIUS * 0.88, WORLD_RADIUS * 0.88)
		var z_value := randf_range(-WORLD_RADIUS * 0.88, WORLD_RADIUS * 0.88)
		var y_value := _terrain_height(x_value, z_value)
		if y_value >= min_height:
			return Vector3(x_value, y_value + 0.05, z_value)
	return Vector3(0.0, _terrain_height(0.0, 0.0) + 0.05, 0.0)


func _build_snapshot_for(creature: CreatureActor) -> Dictionary:
	var nearby_creatures: Array = []
	for other in creatures:
		if other == creature or other.health <= 0.0:
			continue
		var distance := creature.global_position.distance_to(other.global_position)
		if distance <= 24.0:
			nearby_creatures.append(
				{
					"name": other.display_name,
					"species": other.species,
					"distance": snapped(distance, 0.1),
				}
			)
			if nearby_creatures.size() >= 4:
				break

	var nearby_resources: Array = []
	for resource in resources:
		if not resource.is_available():
			continue
		var resource_distance := creature.global_position.distance_to(resource.global_position)
		if resource_distance <= 18.0:
			nearby_resources.append(
				{
					"kind": resource.resource_type,
					"distance": snapped(resource_distance, 0.1),
				}
			)
			if nearby_resources.size() >= 4:
				break

	return {
		"time_label": _time_label(),
		"player": {
			"distance": snapped(creature.global_position.distance_to(player.global_position), 0.1),
			"health": player.health,
			"near_campfire": _is_near_campfire(player.global_position),
		},
		"nearby_creatures": nearby_creatures,
		"nearby_resources": nearby_resources,
	}


func find_nearest_resource(kind: String, origin: Vector3):
	var best = null
	var best_distance := INF
	for resource in resources:
		if not resource.is_available():
			continue
		if kind != "" and kind != "none" and resource.resource_type != kind:
			continue
		var distance := origin.distance_to(resource.global_position)
		if distance < best_distance:
			best_distance = distance
			best = resource
	return best


func guard_target_for(creature: CreatureActor) -> Vector3:
	var nearest_fire = find_nearest_campfire(creature.global_position)
	if nearest_fire != null:
		return nearest_fire.global_position
	return player.global_position


func find_nearest_campfire(origin: Vector3):
	var best = null
	var best_distance := INF
	for campfire in campfires:
		if campfire.fuel <= 0.0:
			continue
		var distance := origin.distance_to(campfire.global_position)
		if distance < best_distance:
			best_distance = distance
			best = campfire
	return best


func damage_player(source_name: String, amount: float) -> void:
	player.receive_damage(amount)
	_show_message("%s hit you for %d." % [source_name, int(round(amount))])
	if player.health <= 0.0:
		_show_message("You were taken down by %s." % source_name)


func _handle_player_actions() -> void:
	if Input.is_action_just_pressed("interact") and gather_cooldown <= 0.0:
		gather_cooldown = 0.28
		var resource = find_nearest_resource("", player.global_position)
		if resource != null and player.global_position.distance_to(resource.global_position) <= resource.gather_radius + 1.0:
			if resource.harvest(1):
				player.add_resource(resource.resource_type, 1)
				_show_message("Gathered 1 %s." % _resource_name(resource.resource_type))
		else:
			_show_message("Nothing close enough to gather.")

	if Input.is_action_just_pressed("eat_berry") and eat_cooldown <= 0.0:
		eat_cooldown = 0.22
		if player.eat_berry():
			_show_message("You ate a berry.")
		else:
			_show_message("You do not have any berries.")

	if Input.is_action_just_pressed("attack") and attack_cooldown <= 0.0:
		attack_cooldown = 0.55
		_player_attack()

	if Input.is_action_just_pressed("craft_fire") and craft_cooldown <= 0.0:
		craft_cooldown = 0.55
		_craft_campfire()


func _player_attack() -> void:
	var target = null
	var best_distance := INF
	for creature in creatures:
		if creature.health <= 0.0:
			continue
		var distance := player.global_position.distance_to(creature.global_position)
		if distance < best_distance and distance <= 3.1:
			best_distance = distance
			target = creature
	if target == null:
		_show_message("Your attack hit nothing.")
		return

	target.receive_damage(26.0, "the player")
	_show_message("You struck %s the %s." % [target.display_name, target.species])
	if target.health <= 0.0:
		_remove_creature(target)


func _craft_campfire() -> void:
	if not player.has_resource("wood", 2) or not player.has_resource("stone", 1):
		_show_message("Campfire needs 2 wood and 1 stone.")
		return

	player.consume_resource("wood", 2)
	player.consume_resource("stone", 1)

	var fire := CampfireNode.new()
	var forward := -player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	if forward == Vector3.ZERO:
		forward = Vector3(0.0, 0.0, 1.0)
	var fire_position := player.global_position + forward * 1.8
	fire_position.y = _terrain_height(fire_position.x, fire_position.z) + 0.05
	fire.position = fire_position
	world_root.add_child(fire)
	fire.apply_material_palette(material_palette)
	campfires.append(fire)
	_show_message("Campfire placed.")


func _is_near_campfire(point: Vector3) -> bool:
	for campfire in campfires:
		if campfire.fuel > 0.0 and point.distance_to(campfire.global_position) <= campfire.warmth_radius:
			return true
	return false


func _time_label() -> String:
	if time_of_day < 0.18:
		return "night"
	if time_of_day < 0.3:
		return "dawn"
	if time_of_day < 0.68:
		return "day"
	if time_of_day < 0.8:
		return "dusk"
	return "night"


func _is_night() -> bool:
	return time_of_day < 0.2 or time_of_day >= 0.78


func _update_environment_lighting() -> void:
	var sun_phase := sin(time_of_day * TAU - PI * 0.5)
	var daylight: float = clampf(sun_phase * 0.9 + 0.25, 0.0, 1.0)
	sun_light.rotation_degrees = Vector3(-58.0 + daylight * 76.0, time_of_day * 360.0 + 25.0, 0.0)
	sun_light.light_energy = daylight * 2.4
	moon_light.rotation_degrees = Vector3(35.0 - daylight * 65.0, time_of_day * 360.0 - 155.0, 0.0)
	moon_light.light_energy = clamp(0.75 - daylight, 0.0, 0.75) * 0.7
	sky_material.sky_top_color = Color(0.08, 0.1, 0.18).lerp(Color(0.42, 0.58, 0.77), daylight)
	sky_material.sky_horizon_color = Color(0.18, 0.18, 0.24).lerp(Color(0.79, 0.77, 0.61), daylight)
	sky_material.ground_horizon_color = Color(0.12, 0.14, 0.12).lerp(Color(0.32, 0.34, 0.24), daylight)


func _on_ai_status_ready(payload: Dictionary) -> void:
	if bool(payload.get("using_local_ai", false)):
		ai_status_text = "AI: local %s" % str(payload.get("model_name", "model"))
	else:
		ai_status_text = "AI: heuristic brain"


func _on_ai_decision_ready(creature_id: String, decision_data: Dictionary) -> void:
	var creature = creature_lookup.get(creature_id)
	if creature == null:
		return
	creature.apply_decision(decision_data)


func _on_ai_request_failed(message: String) -> void:
	if last_ai_error_message == message:
		return
	last_ai_error_message = message
	ai_status_text = "AI: bridge issue"
	_show_message(message)


func _show_message(text: String) -> void:
	status_message = text
	status_timer = 4.0


func _remove_creature(creature: CreatureActor) -> void:
	if not creatures.has(creature):
		return
	_show_message("%s the %s is down." % [creature.display_name, creature.species])
	creatures.erase(creature)
	creature_lookup.erase(creature.creature_id)
	creature.queue_free()


func _resource_name(kind: String) -> String:
	match kind:
		"berries":
			return "berry"
		"wood":
			return "wood bundle"
		_:
			return "stone"


func _build_ui() -> void:
	ui_root = CanvasLayer.new()
	add_child(ui_root)

	var message_panel := _make_panel(Vector2(18, 18), Vector2(560, 54))
	ui_root.add_child(message_panel)
	message_label = Label.new()
	message_label.position = Vector2(16, 12)
	message_label.size = Vector2(528, 30)
	message_label.add_theme_font_size_override("font_size", 18)
	message_panel.add_child(message_label)

	var pack_panel := _make_panel(Vector2(18, 610), Vector2(390, 246))
	ui_root.add_child(pack_panel)
	var pack_title := Label.new()
	pack_title.text = "Survivor Pack"
	pack_title.position = Vector2(20, 14)
	pack_title.add_theme_font_size_override("font_size", 28)
	pack_panel.add_child(pack_title)

	var health_widgets := _make_bar(pack_panel, "Health", Color(0.77, 0.33, 0.28), Vector2(20, 58))
	health_label = health_widgets["label"]
	health_bar = health_widgets["bar"]
	var hunger_widgets := _make_bar(pack_panel, "Food", Color(0.86, 0.68, 0.21), Vector2(20, 110))
	hunger_label = hunger_widgets["label"]
	hunger_bar = hunger_widgets["bar"]
	var energy_widgets := _make_bar(pack_panel, "Energy", Color(0.35, 0.62, 0.85), Vector2(20, 162))
	energy_label = energy_widgets["label"]
	energy_bar = energy_widgets["bar"]

	berries_label = _make_inventory_chip(pack_panel, "Berries x0 [Q]", Vector2(22, 206))
	wood_label = _make_inventory_chip(pack_panel, "Wood x0", Vector2(156, 206))
	stone_label = _make_inventory_chip(pack_panel, "Stone x0", Vector2(264, 206))

	var decision_panel := _make_panel(Vector2(1160, 18), Vector2(400, 250))
	ui_root.add_child(decision_panel)
	var decision_title := Label.new()
	decision_title.text = "Visible Creature Decisions"
	decision_title.position = Vector2(20, 14)
	decision_title.add_theme_font_size_override("font_size", 22)
	decision_panel.add_child(decision_title)

	ai_status_label = Label.new()
	ai_status_label.position = Vector2(20, 48)
	ai_status_label.size = Vector2(360, 24)
	ai_status_label.modulate = Color(0.72, 0.78, 0.79)
	decision_panel.add_child(ai_status_label)

	creature_log_label = Label.new()
	creature_log_label.position = Vector2(20, 84)
	creature_log_label.size = Vector2(360, 140)
	creature_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	creature_log_label.add_theme_font_size_override("font_size", 19)
	decision_panel.add_child(creature_log_label)


func _make_panel(panel_position: Vector2, panel_size: Vector2) -> Panel:
	var panel := Panel.new()
	panel.position = panel_position
	panel.size = panel_size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.05, 0.06, 0.9)
	style.border_color = Color(0.32, 0.41, 0.43, 0.9)
	style.corner_radius_top_left = 18
	style.corner_radius_top_right = 18
	style.corner_radius_bottom_left = 18
	style.corner_radius_bottom_right = 18
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _make_bar(panel: Panel, title: String, fill_color: Color, position_value: Vector2) -> Dictionary:
	var label := Label.new()
	label.text = title
	label.position = position_value
	label.size = Vector2(300, 22)
	label.add_theme_font_size_override("font_size", 20)
	panel.add_child(label)

	var bar := ProgressBar.new()
	bar.position = position_value + Vector2(0, 24)
	bar.size = Vector2(348, 16)
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.show_percentage = false
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.09, 0.12, 0.13)
	bg_style.corner_radius_top_left = 8
	bg_style.corner_radius_top_right = 8
	bg_style.corner_radius_bottom_left = 8
	bg_style.corner_radius_bottom_right = 8
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = fill_color
	fill_style.corner_radius_top_left = 8
	fill_style.corner_radius_top_right = 8
	fill_style.corner_radius_bottom_left = 8
	fill_style.corner_radius_bottom_right = 8
	bar.add_theme_stylebox_override("background", bg_style)
	bar.add_theme_stylebox_override("fill", fill_style)
	panel.add_child(bar)

	return {"label": label, "bar": bar}


func _make_inventory_chip(panel: Panel, text_value: String, position_value: Vector2) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = position_value
	label.size = Vector2(130, 24)
	label.add_theme_font_size_override("font_size", 18)
	panel.add_child(label)
	return label


func _update_ui() -> void:
	if status_timer > 0.0:
		message_label.text = status_message
	else:
		message_label.text = "Stay fed, stay warm, and watch the creature minds."

	health_label.text = "Health %d" % int(round(player.health))
	hunger_label.text = "Food %d" % int(round(max(0.0, 100.0 - player.hunger)))
	energy_label.text = "Energy %d" % int(round(player.energy))
	health_bar.value = player.health
	hunger_bar.value = max(0.0, 100.0 - player.hunger)
	energy_bar.value = player.energy

	berries_label.text = "Berries x%d [Q]" % int(player.inventory.get("berries", 0))
	wood_label.text = "Wood x%d" % int(player.inventory.get("wood", 0))
	stone_label.text = "Stone x%d" % int(player.inventory.get("stone", 0))

	ai_status_label.text = ai_status_text
	var lines: Array = []
	for creature in _visible_creatures():
		var action := "thinking..." if creature.decision_pending else str(creature.decision.get("action", "wander"))
		lines.append("%s the %s (Action): %s" % [creature.display_name, creature.species.capitalize(), action])
	if lines.is_empty():
		creature_log_label.text = "No creatures in view."
	else:
		creature_log_label.text = "\n".join(lines)


func _visible_creatures() -> Array:
	var visible_list: Array = []
	for creature in creatures:
		if creature.health <= 0.0:
			continue
		if player.global_position.distance_to(creature.global_position) <= 26.0:
			visible_list.append(creature)
			if visible_list.size() >= 6:
				break
	return visible_list
