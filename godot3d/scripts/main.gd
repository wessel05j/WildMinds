extends Node3D

const PlayerController = preload("res://scripts/player_controller.gd")
const CreatureActor = preload("res://scripts/creature_actor.gd")
const ResourceNode3D = preload("res://scripts/resource_node.gd")
const CampfireNode = preload("res://scripts/campfire.gd")
const AIBridge = preload("res://scripts/ai_bridge.gd")

const WORLD_RADIUS := 420.0
const CONTENT_RADIUS := 364.0
const TERRAIN_RESOLUTION := 196
const DAY_CYCLE_SPEED := 0.00155
const RESOURCE_CONFIG := [
	{"kind": "berries", "count": 54, "amount": 4},
	{"kind": "wood", "count": 44, "amount": 3},
	{"kind": "stone", "count": 36, "amount": 4},
	{"kind": "fiber", "count": 42, "amount": 3},
	{"kind": "herb", "count": 34, "amount": 2},
	{"kind": "ore", "count": 26, "amount": 3},
]
const NAME_POOLS := {
	"wolf": ["Ash", "Fen", "Rook", "Thorn", "Morrow", "Slate"],
	"boar": ["Brim", "Tusk", "Cinder", "Bramble", "Ridge"],
	"scavenger": ["Mira", "Vale", "Orin", "Sable", "Kest", "Nera"],
	"deer": ["Lark", "Briar", "Moss", "Thistle", "Fawn", "Sorrel"],
	"fox": ["Rune", "Clover", "Ember", "Tawny", "Vesper", "Ashen"],
}
const RECIPE_ORDER := ["bandage", "trail_ration", "spear", "tower_braces", "signal_core", "beacon_lens"]
const RECIPE_DATA := {
	"bandage": {
		"name": "Bandage",
		"cost": {"herb": 2, "fiber": 1},
		"skill": 1,
		"craft_xp": 1,
		"hint": "Use H to heal.",
	},
	"trail_ration": {
		"name": "Trail Ration",
		"cost": {"berries": 3, "herb": 1},
		"skill": 1,
		"craft_xp": 1,
		"hint": "Use G to eat a better ration.",
	},
	"spear": {
		"name": "Stone Spear",
		"cost": {"wood": 2, "stone": 2, "fiber": 2},
		"skill": 2,
		"craft_xp": 2,
		"hint": "Raises melee damage permanently.",
	},
	"tower_braces": {
		"name": "Tower Braces",
		"cost": {"wood": 5, "fiber": 3, "stone": 2},
		"skill": 1,
		"craft_xp": 2,
		"hint": "Deliver to the signal tower.",
	},
	"signal_core": {
		"name": "Signal Core",
		"cost": {"ore": 3, "stone": 2, "herb": 1},
		"skill": 2,
		"craft_xp": 2,
		"hint": "Needed to power the tower.",
	},
	"beacon_lens": {
		"name": "Beacon Lens",
		"cost": {"ore": 2, "fiber": 2, "hide": 1},
		"skill": 3,
		"craft_xp": 3,
		"hint": "Needed to finish the tower.",
	},
}

var terrain_noise := FastNoiseLite.new()
var detail_noise := FastNoiseLite.new()
var biome_noise := FastNoiseLite.new()
var ridge_noise := FastNoiseLite.new()
var mountain_noise := FastNoiseLite.new()
var continental_noise := FastNoiseLite.new()
var erosion_noise := FastNoiseLite.new()
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
var crosshair_label: Label
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
var inventory_detail_label: Label
var craft_label: Label
var skill_label: Label
var quest_label: Label
var tower_hint_label: Label
var inventory_slots := {}
var item_icon_cache := {}

var status_message := ""
var status_timer := 0.0
var ai_status_text := "AI: checking helper service..."
var time_of_day := 0.36
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
var player_dead := false
var respawn_timer := 0.0
var last_noise_position := Vector3.ZERO
var last_noise_age := 999.0
var last_noise_level := "none"
var last_noise_strength := 0.0
var footstep_noise_timer := 0.0
var damage_overlay: ColorRect
var damage_flash := 0.0
var crosshair_flash := 0.0
var active_effects: Array = []
var selected_recipe_index := 0
var signal_tower_root: Node3D
var signal_tower_glow: OmniLight3D
var signal_tower_position := Vector3.ZERO
var signal_tower_base_energy := 0.15
var signal_tower_parts := {
	"tower_braces": false,
	"signal_core": false,
	"beacon_lens": false,
}
var signal_tower_complete := false


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
	ai_bridge.decision_failed.connect(_on_ai_decision_failed)
	ai_bridge.request_failed.connect(_on_ai_request_failed)
	ai_bridge.request_status()

	_show_message("Explore farther, gather smarter, and rebuild the signal tower.")


func _physics_process(delta: float) -> void:
	time_of_day = wrapf(time_of_day + delta * DAY_CYCLE_SPEED, 0.0, 1.0)
	gather_cooldown = max(0.0, gather_cooldown - delta)
	eat_cooldown = max(0.0, eat_cooldown - delta)
	attack_cooldown = max(0.0, attack_cooldown - delta)
	craft_cooldown = max(0.0, craft_cooldown - delta)
	status_timer = max(0.0, status_timer - delta)
	smoke_elapsed += delta
	last_noise_age += delta
	footstep_noise_timer = max(0.0, footstep_noise_timer - delta)
	damage_flash = max(0.0, damage_flash - delta * 1.65)
	crosshair_flash = max(0.0, crosshair_flash - delta * 2.8)

	_update_environment_lighting()
	_constrain_player_to_world()
	_tick_world_effects(delta)
	if signal_tower_glow != null:
		signal_tower_glow.light_energy = signal_tower_base_energy + sin(Time.get_ticks_msec() / 1000.0 * 2.4) * 0.06
	if not player_dead:
		player.tick_survival(delta, _is_night(), _is_near_campfire(player.global_position))
		_handle_player_actions()
		if player.move_direction.length() > 0.12 and footstep_noise_timer <= 0.0:
			_record_noise(player.global_position, "footsteps", 0.32)
			footstep_noise_timer = 0.75
		if player.health <= 0.0:
			_start_player_death("You died. Respawning soon.")
	else:
		respawn_timer = max(0.0, respawn_timer - delta)
		if respawn_timer <= 0.0:
			_respawn_player()

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
			if not _creature_should_query_ai(creature):
				creature.defer_next_think(randf_range(2.2, 4.4))
				creature.simulate(delta, self)
				continue
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
	_reset_action_bindings("attack")
	_reset_action_bindings("jump")
	_bind_key("move_left", KEY_A)
	_bind_key("move_left", KEY_LEFT)
	_bind_key("move_right", KEY_D)
	_bind_key("move_right", KEY_RIGHT)
	_bind_key("move_forward", KEY_W)
	_bind_key("move_forward", KEY_UP)
	_bind_key("move_back", KEY_S)
	_bind_key("move_back", KEY_DOWN)
	_bind_key("interact", KEY_E)
	_bind_mouse("attack", MOUSE_BUTTON_LEFT)
	_bind_key("jump", KEY_SPACE)
	_bind_key("eat_berry", KEY_Q)
	_bind_key("eat_berry", KEY_1)
	_bind_key("eat_berry", KEY_ENTER)
	_bind_key("use_bandage", KEY_H)
	_bind_key("use_ration", KEY_G)
	_bind_key("craft_item", KEY_C)
	_bind_key("cycle_recipe", KEY_R)
	_bind_key("craft_fire", KEY_F)


func _reset_action_bindings(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
		return
	for existing in InputMap.action_get_events(action):
		InputMap.action_erase_event(action, existing)


func _bind_key(action: String, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for existing in InputMap.action_get_events(action):
		if existing is InputEventKey and existing.physical_keycode == keycode:
			return
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)


func _bind_mouse(action: String, button_index: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for existing in InputMap.action_get_events(action):
		if existing is InputEventMouseButton and existing.button_index == button_index:
			return
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	InputMap.action_add_event(action, event)


func _prepare_noises() -> void:
	terrain_noise.seed = randi()
	terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	terrain_noise.frequency = 0.026
	terrain_noise.fractal_octaves = 4
	terrain_noise.fractal_gain = 0.55
	terrain_noise.fractal_lacunarity = 2.1

	detail_noise.seed = randi()
	detail_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	detail_noise.frequency = 0.082
	detail_noise.fractal_octaves = 3

	biome_noise.seed = randi()
	biome_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	biome_noise.frequency = 0.0062
	biome_noise.fractal_octaves = 3

	ridge_noise.seed = randi()
	ridge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridge_noise.frequency = 0.0094
	ridge_noise.fractal_octaves = 4

	mountain_noise.seed = randi()
	mountain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	mountain_noise.frequency = 0.0048
	mountain_noise.fractal_octaves = 3

	continental_noise.seed = randi()
	continental_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	continental_noise.frequency = 0.0022
	continental_noise.fractal_octaves = 3
	continental_noise.fractal_gain = 0.56

	erosion_noise.seed = randi()
	erosion_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	erosion_noise.frequency = 0.016
	erosion_noise.fractal_octaves = 4


func _build_material_library() -> void:
	var terrain_material := _make_material(Color(0.38, 0.47, 0.31), 0.98, 0.0, Color(0.0, 0.0, 0.0), _make_noise_texture(14, 0.03))
	terrain_material.vertex_color_use_as_albedo = true
	material_palette = {
		"terrain": terrain_material,
		"ground_grass": _make_material(Color(0.28, 0.44, 0.25), 0.98, 0.0, Color(0.0, 0.0, 0.0), _make_noise_texture(14, 0.035)),
		"ground_soil": _make_material(Color(0.39, 0.31, 0.22), 1.0, 0.0, Color(0.0, 0.0, 0.0), _make_noise_texture(42, 0.06)),
		"foliage": _make_material(Color(0.39, 0.55, 0.31), 0.94, 0.0, Color(0.0, 0.0, 0.0), _make_noise_texture(61, 0.085)),
		"foliage_forest": _make_material(Color(0.22, 0.39, 0.21), 0.96, 0.0, Color(0.0, 0.0, 0.0), _make_noise_texture(62, 0.082)),
		"foliage_meadow": _make_material(Color(0.48, 0.62, 0.33), 0.94, 0.0, Color(0.0, 0.0, 0.0), _make_noise_texture(63, 0.082)),
		"foliage_wetland": _make_material(Color(0.36, 0.48, 0.25), 0.96, 0.0, Color(0.0, 0.0, 0.0), _make_noise_texture(64, 0.082)),
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
		"deer_fur": _make_material(Color(0.57, 0.43, 0.27), 0.93, 0.0, Color(0.0, 0.0, 0.0), _make_noise_texture(141, 0.11)),
		"deer_undercoat": _make_material(Color(0.82, 0.74, 0.61), 0.88),
		"antler": _make_material(Color(0.68, 0.59, 0.42), 0.95),
		"fox_fur": _make_material(Color(0.76, 0.42, 0.18), 0.91, 0.0, Color(0.0, 0.0, 0.0), _make_noise_texture(153, 0.14)),
		"fox_white": _make_material(Color(0.94, 0.91, 0.82), 0.83),
		"fox_dark": _make_material(Color(0.19, 0.13, 0.12), 0.95),
		"scavenger_robe": _make_material(Color(0.19, 0.22, 0.2), 0.95, 0.0, Color(0.0, 0.0, 0.0), _make_noise_texture(119, 0.09)),
		"scavenger_trim": _make_material(Color(0.52, 0.36, 0.22), 0.92),
		"grass_tuft": _make_material(Color(0.41, 0.57, 0.29), 0.96, 0.0, Color(0.0, 0.0, 0.0), _make_noise_texture(164, 0.09)),
		"reed": _make_material(Color(0.49, 0.58, 0.34), 0.97),
		"flower_gold": _make_material(Color(0.9, 0.75, 0.31), 0.72, 0.0, Color(0.12, 0.08, 0.0)),
		"flower_blue": _make_material(Color(0.39, 0.58, 0.93), 0.7, 0.0, Color(0.04, 0.06, 0.12)),
		"tower_metal": _make_material(Color(0.45, 0.49, 0.53), 0.42, 0.18, Color(0.0, 0.0, 0.0), _make_noise_texture(171, 0.08)),
		"tower_wood": _make_material(Color(0.42, 0.29, 0.2), 0.92, 0.0, Color(0.0, 0.0, 0.0), _make_noise_texture(172, 0.13)),
		"tower_glow": _make_material(Color(0.96, 0.84, 0.38, 0.88), 0.18, 0.0, Color(0.82, 0.62, 0.18), null, true),
		"ruin_stone": _make_material(Color(0.56, 0.56, 0.5), 0.98, 0.0, Color(0.0, 0.0, 0.0), _make_noise_texture(173, 0.09)),
		"canvas": _make_material(Color(0.74, 0.68, 0.54), 0.95),
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
	environment.ambient_light_energy = 1.28
	environment.fog_enabled = true
	environment.fog_density = 0.00078
	environment.fog_light_color = Color(0.54, 0.63, 0.67)
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.08
	environment.adjustment_contrast = 1.06

	sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.33, 0.49, 0.72)
	sky_material.sky_horizon_color = Color(0.81, 0.82, 0.73)
	sky_material.ground_bottom_color = Color(0.12, 0.18, 0.15)
	sky_material.ground_horizon_color = Color(0.36, 0.39, 0.29)

	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.sky = sky

	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	sun_light = DirectionalLight3D.new()
	sun_light.light_energy = 2.05
	sun_light.shadow_enabled = true
	sun_light.shadow_blur = 0.8
	sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun_light.directional_shadow_blend_splits = true
	sun_light.directional_shadow_max_distance = 360.0
	sun_light.shadow_bias = 0.03
	sun_light.shadow_normal_bias = 1.2
	sun_light.rotation_degrees = Vector3(-48.0, 32.0, 0.0)
	add_child(sun_light)

	moon_light = DirectionalLight3D.new()
	moon_light.light_color = Color(0.47, 0.56, 0.72)
	moon_light.light_energy = 0.14
	moon_light.rotation_degrees = Vector3(40.0, -140.0, 0.0)
	add_child(moon_light)
	_update_environment_lighting()


func _build_world() -> void:
	world_root = Node3D.new()
	add_child(world_root)
	_build_terrain()
	_spawn_backdrop_ridges()
	_spawn_landscape_props()
	_spawn_landmarks()
	_spawn_player()
	_spawn_resources()
	_spawn_creatures()


func _build_terrain() -> void:
	var terrain_mesh := _generate_terrain_mesh()
	terrain_mesh_instance = MeshInstance3D.new()
	terrain_mesh_instance.mesh = terrain_mesh
	terrain_mesh_instance.material_override = material_palette["terrain"]
	world_root.add_child(terrain_mesh_instance)

	terrain_body = StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = terrain_mesh.create_trimesh_shape()
	terrain_body.add_child(collision)
	world_root.add_child(terrain_body)

	water_mesh_instance = MeshInstance3D.new()
	var water := PlaneMesh.new()
	water.size = Vector2(WORLD_RADIUS * 2.8, WORLD_RADIUS * 2.8)
	water_mesh_instance.mesh = water
	water_mesh_instance.material_override = material_palette["water"]
	water_mesh_instance.position = Vector3(0.0, -1.35, 0.0)
	water_mesh_instance.rotation_degrees.x = -90.0
	world_root.add_child(water_mesh_instance)


func _spawn_backdrop_ridges() -> void:
	for index in range(18):
		var ridge := Node3D.new()
		var angle := TAU * float(index) / 18.0 + randf_range(-0.09, 0.09)
		var radius := WORLD_RADIUS + randf_range(85.0, 145.0)
		ridge.position = Vector3(cos(angle) * radius, -6.0, sin(angle) * radius)
		ridge.rotation_degrees.y = rad_to_deg(-angle) + 90.0
		world_root.add_child(ridge)

		var ridge_material: Material = material_palette.get("ruin_stone", material_palette.get("stone"))
		var count := 3 + randi() % 3
		for piece_index in range(count):
			var mesh_instance := MeshInstance3D.new()
			var mesh := SphereMesh.new()
			mesh.radius = 9.0 + piece_index * 1.8
			mesh.height = 18.0 + piece_index * 4.0
			mesh_instance.mesh = mesh
			mesh_instance.position = Vector3((piece_index - count * 0.5) * 18.0, 22.0 + randf_range(-4.0, 7.0), randf_range(-12.0, 12.0))
			mesh_instance.scale = Vector3(2.5 + randf() * 1.4, 1.8 + randf() * 1.1, 1.6 + randf() * 0.8)
			mesh_instance.material_override = ridge_material
			ridge.add_child(mesh_instance)


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
	surface_tool.set_color(_terrain_vertex_color(vertex))
	surface_tool.set_uv(Vector2(vertex.x * 0.12, vertex.z * 0.12))
	surface_tool.add_vertex(vertex)


func _terrain_height(x_value: float, z_value: float) -> float:
	var continental_shape: float = continental_noise.get_noise_2d(x_value, z_value)
	var broad_shape := terrain_noise.get_noise_2d(x_value, z_value) * 5.1
	var detail_shape := detail_noise.get_noise_2d(x_value * 1.45, z_value * 1.45) * 1.2
	var erosion_shape := erosion_noise.get_noise_2d(x_value, z_value) * 2.2
	var ridge_shape: float = abs(ridge_noise.get_noise_2d(x_value, z_value)) * 5.1
	var plateau_mask: float = clampf((continental_shape + 0.08) * 1.15, 0.0, 1.0)
	var mountain_mask: float = clampf((mountain_noise.get_noise_2d(x_value, z_value) + 0.12) * 1.2 + plateau_mask * 0.28, 0.0, 1.0)
	var mountain_shape: float = pow(mountain_mask, 2.9) * 28.0 + ridge_shape * mountain_mask * 1.8
	var basin_shape: float = -pow(max(0.0, -continental_shape - 0.14), 2.0) * 8.5
	var uplift_shape: float = plateau_mask * 5.8
	var edge_ratio: float = clampf(Vector2(x_value, z_value).length() / WORLD_RADIUS, 0.0, 1.0)
	var far_falloff := smoothstep(0.93, 1.0, edge_ratio) * 6.0
	var valley_soften: float = -abs(detail_noise.get_noise_2d(x_value * 0.52, z_value * 0.52)) * 1.2
	return continental_shape * 4.8 + broad_shape + detail_shape + erosion_shape + mountain_shape + uplift_shape + basin_shape + valley_soften - far_falloff


func _terrain_vertex_color(vertex: Vector3) -> Color:
	var biome_name := _biome_name(vertex.x, vertex.z, vertex.y)
	var shore_blend := smoothstep(-1.0, 0.25, vertex.y)
	var highland_blend := smoothstep(3.5, 8.5, vertex.y)
	var peak_blend := smoothstep(12.0, 21.0, vertex.y)
	var base_color := Color(0.4, 0.45, 0.3)

	match biome_name:
		"forest":
			base_color = Color(0.19, 0.31, 0.18)
		"meadow":
			base_color = Color(0.44, 0.54, 0.27)
		"wetland":
			base_color = Color(0.29, 0.38, 0.27)
		"alpine":
			base_color = Color(0.48, 0.47, 0.43)
		_:
			base_color = Color(0.41, 0.35, 0.27)

	base_color = base_color.lerp(Color(0.67, 0.61, 0.43), 1.0 - shore_blend)
	base_color = base_color.lerp(Color(0.48, 0.49, 0.47), highland_blend)
	base_color = base_color.lerp(Color(0.75, 0.77, 0.8), peak_blend)
	return base_color


func _biome_name(x_value: float, z_value: float, height_value: float = INF) -> String:
	var height := height_value if height_value != INF else _terrain_height(x_value, z_value)
	if height < -1.25:
		return "wetland"
	if height > 16.0:
		return "alpine"
	var biome_sample := biome_noise.get_noise_2d(x_value, z_value)
	var continental_shape: float = continental_noise.get_noise_2d(x_value, z_value)
	if height > 6.5 or continental_shape > 0.22:
		return "highland"
	if biome_sample < -0.18:
		return "forest"
	return "meadow"


func _spawn_landscape_props() -> void:
	for _index in range(260):
		var point := random_world_point(-0.2)
		var biome_name := _biome_name(point.x, point.z, point.y)
		if biome_name in ["highland", "alpine"]:
			if randf() < 0.78:
				_spawn_rock_cluster(point, randf_range(0.9, 1.6))
			else:
				_spawn_tree(point, randf_range(0.8, 1.05), biome_name)
		elif biome_name == "forest":
			_spawn_tree(point, randf_range(0.95, 1.45), biome_name)
			if randf() < 0.22:
				_spawn_tree(point + Vector3(randf_range(-2.8, 2.8), 0.0, randf_range(-2.8, 2.8)), randf_range(0.72, 1.0), biome_name)
		elif biome_name == "wetland":
			if randf() < 0.6:
				_spawn_tree(point, randf_range(0.82, 1.1), biome_name)
			else:
				_spawn_rock_cluster(point, randf_range(0.65, 1.0))
		else:
			if randf() < 0.65:
				_spawn_tree(point, randf_range(0.78, 1.12), biome_name)
			else:
				_spawn_rock_cluster(point, randf_range(0.75, 1.2))

	for _index in range(180):
		_spawn_rock_cluster(random_world_point(-0.45), randf_range(0.8, 1.5))

	for _index in range(420):
		_spawn_grass_patch(random_world_point(-0.2), randf_range(0.75, 1.35))

	for _index in range(130):
		var wetland_point := _random_point_in_biomes(["wetland"], -0.7)
		_spawn_reed_clump(wetland_point, randf_range(0.85, 1.3))

	for _index in range(140):
		var flower_point := _random_point_in_biomes(["meadow", "forest"], -0.2)
		_spawn_flower_patch(flower_point, randf_range(0.78, 1.1))

	for _index in range(48):
		var log_point := _random_point_in_biomes(["forest", "meadow"], -0.15)
		_spawn_fallen_log(log_point, randf_range(0.8, 1.35))

	for _index in range(18):
		var outcrop_point := _random_point_in_biomes(["highland", "alpine"], 3.5)
		_spawn_cliff_outcrop(outcrop_point, randf_range(1.25, 2.1))


func _spawn_tree(position_value: Vector3, scale_factor: float, biome_name: String = "forest") -> void:
	var tree := Node3D.new()
	tree.position = position_value
	tree.rotation_degrees.y = randf_range(0.0, 360.0)
	var canopy_material: Material = material_palette["foliage_forest"]
	if biome_name == "meadow":
		canopy_material = material_palette["foliage_meadow"]
	elif biome_name == "wetland":
		canopy_material = material_palette["foliage_wetland"]
	elif biome_name in ["highland", "alpine"]:
		canopy_material = material_palette["foliage_forest"]

	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.18 * scale_factor
	trunk_mesh.bottom_radius = 0.28 * scale_factor
	trunk_mesh.height = 2.8 * scale_factor
	trunk.mesh = trunk_mesh
	trunk.position = Vector3(0.0, 1.3 * scale_factor, 0.0)
	trunk.material_override = material_palette["bark"]
	if biome_name == "wetland":
		trunk.rotation_degrees.z = randf_range(-9.0, 9.0)
	elif biome_name in ["highland", "alpine"]:
		trunk_mesh.height = 3.8 * scale_factor
		trunk.position.y = 1.9 * scale_factor
		trunk_mesh.top_radius = 0.12 * scale_factor
		trunk_mesh.bottom_radius = 0.22 * scale_factor
	tree.add_child(trunk)

	if biome_name in ["highland", "alpine"]:
		for canopy_data in [
			{"position": Vector3(0.0, 3.0, 0.0), "height": 1.7, "radius": 0.9},
			{"position": Vector3(0.0, 4.1, 0.0), "height": 1.4, "radius": 0.68},
			{"position": Vector3(0.0, 5.0, 0.0), "height": 1.05, "radius": 0.46},
		]:
			var cone := MeshInstance3D.new()
			var cone_mesh := CylinderMesh.new()
			cone_mesh.top_radius = 0.01
			cone_mesh.bottom_radius = float(canopy_data["radius"]) * scale_factor
			cone_mesh.height = float(canopy_data["height"]) * scale_factor
			cone.mesh = cone_mesh
			cone.position = canopy_data["position"] * scale_factor
			cone.material_override = canopy_material
			tree.add_child(cone)
	elif biome_name == "wetland":
		for canopy_data in [
			{"position": Vector3(-0.42, 2.55, 0.24), "scale": Vector3(0.95, 0.8, 0.82)},
			{"position": Vector3(0.26, 2.92, -0.18), "scale": Vector3(0.82, 0.72, 0.74)},
			{"position": Vector3(0.0, 3.18, 0.0), "scale": Vector3(1.06, 0.85, 0.94)}
		]:
			var canopy := MeshInstance3D.new()
			var canopy_mesh := SphereMesh.new()
			canopy_mesh.radius = 0.74 * scale_factor
			canopy_mesh.height = 1.28 * scale_factor
			canopy.mesh = canopy_mesh
			canopy.position = canopy_data["position"] * scale_factor
			canopy.scale = canopy_data["scale"]
			canopy.material_override = canopy_material
			tree.add_child(canopy)
	else:
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
			canopy.material_override = canopy_material
			tree.add_child(canopy)

	world_root.add_child(tree)


func _spawn_cliff_outcrop(position_value: Vector3, scale_factor: float) -> void:
	var outcrop := Node3D.new()
	outcrop.position = position_value
	outcrop.rotation_degrees.y = randf_range(0.0, 360.0)
	for piece_data in [
		{"position": Vector3(-1.1, 1.8, -0.4), "size": Vector3(2.6, 3.4, 1.8), "rot": Vector3(0.0, 0.22, 0.08)},
		{"position": Vector3(0.6, 2.5, 0.2), "size": Vector3(2.1, 4.7, 2.0), "rot": Vector3(0.0, -0.18, -0.06)},
		{"position": Vector3(0.0, 4.4, -0.1), "size": Vector3(1.8, 3.2, 1.6), "rot": Vector3(0.0, 0.12, 0.04)},
	]:
		var rock := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = piece_data["size"] * scale_factor
		rock.mesh = mesh
		rock.position = piece_data["position"] * scale_factor
		rock.rotation = piece_data["rot"]
		rock.material_override = material_palette.get("ruin_stone", material_palette.get("stone"))
		outcrop.add_child(rock)
	world_root.add_child(outcrop)


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


func _spawn_grass_patch(position_value: Vector3, scale_factor: float) -> void:
	var biome_name := biome_at(position_value)
	if biome_name == "highland":
		return
	var patch := Node3D.new()
	patch.position = position_value
	patch.rotation_degrees.y = randf_range(0.0, 360.0)
	var blade_material: Material = material_palette.get("grass_tuft", material_palette.get("foliage"))
	if biome_name == "wetland":
		blade_material = material_palette.get("reed", blade_material)

	for index in range(5):
		var blade := MeshInstance3D.new()
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(0.18 * scale_factor, (0.65 + randf() * 0.35) * scale_factor)
		blade.mesh = mesh
		blade.position = Vector3(randf_range(-0.26, 0.26), 0.22 * scale_factor, randf_range(-0.22, 0.22))
		blade.rotation_degrees = Vector3(randf_range(-8.0, 8.0), index * 36.0 + randf_range(-12.0, 12.0), randf_range(-6.0, 6.0))
		blade.material_override = blade_material
		patch.add_child(blade)

	world_root.add_child(patch)


func _spawn_reed_clump(position_value: Vector3, scale_factor: float) -> void:
	var clump := Node3D.new()
	clump.position = position_value
	clump.rotation_degrees.y = randf_range(0.0, 360.0)
	for _index in range(7):
		var stem := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.03 * scale_factor
		mesh.bottom_radius = 0.045 * scale_factor
		mesh.height = randf_range(1.1, 1.9) * scale_factor
		stem.mesh = mesh
		stem.position = Vector3(randf_range(-0.28, 0.28), mesh.height * 0.5, randf_range(-0.24, 0.24))
		stem.rotation_degrees.z = randf_range(-6.0, 7.0)
		stem.material_override = material_palette.get("reed", material_palette.get("grass_tuft"))
		clump.add_child(stem)
	world_root.add_child(clump)


func _spawn_flower_patch(position_value: Vector3, scale_factor: float) -> void:
	var patch := Node3D.new()
	patch.position = position_value
	var bloom_material: Material = material_palette.get("flower_gold")
	if randf() < 0.45:
		bloom_material = material_palette.get("flower_blue", bloom_material)
	for _index in range(4):
		var stem := MeshInstance3D.new()
		var stem_mesh := CylinderMesh.new()
		stem_mesh.top_radius = 0.016
		stem_mesh.bottom_radius = 0.025
		stem_mesh.height = 0.42 * scale_factor
		stem.mesh = stem_mesh
		stem.position = Vector3(randf_range(-0.16, 0.16), 0.21 * scale_factor, randf_range(-0.16, 0.16))
		stem.material_override = material_palette.get("reed", material_palette.get("grass_tuft"))
		patch.add_child(stem)

		var bloom := MeshInstance3D.new()
		var bloom_mesh := SphereMesh.new()
		bloom_mesh.radius = 0.08 * scale_factor
		bloom_mesh.height = 0.16 * scale_factor
		bloom.mesh = bloom_mesh
		bloom.position = stem.position + Vector3(0.0, 0.24 * scale_factor, 0.0)
		bloom.material_override = bloom_material
		patch.add_child(bloom)
	world_root.add_child(patch)


func _spawn_fallen_log(position_value: Vector3, scale_factor: float) -> void:
	var fallen_log := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.16 * scale_factor
	mesh.bottom_radius = 0.22 * scale_factor
	mesh.height = 1.9 * scale_factor
	fallen_log.mesh = mesh
	fallen_log.position = position_value + Vector3(0.0, 0.22 * scale_factor, 0.0)
	fallen_log.rotation = Vector3(deg_to_rad(90.0), randf_range(0.0, TAU), randf_range(-0.14, 0.14))
	fallen_log.material_override = material_palette.get("bark")
	world_root.add_child(fallen_log)


func _spawn_landmarks() -> void:
	_spawn_signal_tower()
	for _index in range(4):
		_spawn_ruin_circle(_random_point_in_biomes(["highland", "meadow"], 0.2), randf_range(0.9, 1.35))
	for _index in range(3):
		_spawn_abandoned_camp(_random_point_in_biomes(["forest", "meadow"], -0.15), randf_range(0.9, 1.25))


func _spawn_signal_tower() -> void:
	signal_tower_root = Node3D.new()
	signal_tower_position = _random_point_in_biomes(["highland", "alpine"], 8.5)
	signal_tower_root.position = signal_tower_position
	world_root.add_child(signal_tower_root)

	for leg_data in [
		{"position": Vector3(-1.1, 3.3, -1.1), "rot": -8.0},
		{"position": Vector3(1.1, 3.3, -1.1), "rot": 8.0},
		{"position": Vector3(-1.1, 3.3, 1.1), "rot": -6.0},
		{"position": Vector3(1.1, 3.3, 1.1), "rot": 6.0},
	]:
		var leg := MeshInstance3D.new()
		var leg_mesh := CylinderMesh.new()
		leg_mesh.top_radius = 0.12
		leg_mesh.bottom_radius = 0.18
		leg_mesh.height = 6.4
		leg.mesh = leg_mesh
		leg.position = leg_data["position"]
		leg.rotation_degrees.z = float(leg_data["rot"])
		leg.material_override = material_palette.get("tower_metal", material_palette.get("stone"))
		signal_tower_root.add_child(leg)

	for beam_pos in [Vector3(0.0, 2.1, -1.12), Vector3(0.0, 2.1, 1.12), Vector3(-1.12, 2.1, 0.0), Vector3(1.12, 2.1, 0.0)]:
		var beam := MeshInstance3D.new()
		var beam_mesh := BoxMesh.new()
		beam_mesh.size = Vector3(2.5, 0.16, 0.16)
		beam.mesh = beam_mesh
		beam.position = beam_pos
		if abs(beam_pos.x) > 0.1:
			beam.rotation_degrees.y = 90.0
		beam.material_override = material_palette.get("tower_wood", material_palette.get("bark"))
		signal_tower_root.add_child(beam)

	var beacon := MeshInstance3D.new()
	var beacon_mesh := SphereMesh.new()
	beacon_mesh.radius = 0.42
	beacon_mesh.height = 0.84
	beacon.mesh = beacon_mesh
	beacon.position = Vector3(0.0, 6.7, 0.0)
	beacon.material_override = material_palette.get("tower_glow", material_palette.get("flame_tip"))
	signal_tower_root.add_child(beacon)

	signal_tower_glow = OmniLight3D.new()
	signal_tower_glow.position = Vector3(0.0, 6.7, 0.0)
	signal_tower_glow.light_color = Color(1.0, 0.84, 0.42)
	signal_tower_glow.light_energy = signal_tower_base_energy
	signal_tower_glow.omni_range = 16.0
	signal_tower_glow.visible = true
	signal_tower_root.add_child(signal_tower_glow)

	var base_ring := MeshInstance3D.new()
	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = 2.2
	ring_mesh.bottom_radius = 2.4
	ring_mesh.height = 0.4
	base_ring.mesh = ring_mesh
	base_ring.position = Vector3(0.0, 0.18, 0.0)
	base_ring.material_override = material_palette.get("ruin_stone", material_palette.get("stone"))
	signal_tower_root.add_child(base_ring)


func _spawn_ruin_circle(position_value: Vector3, scale_factor: float) -> void:
	var ruin_root := Node3D.new()
	ruin_root.position = position_value
	world_root.add_child(ruin_root)

	for index in range(6):
		var angle := TAU * float(index) / 6.0
		var pillar := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.42, 1.8 + randf() * 1.1, 0.42)
		pillar.mesh = mesh
		pillar.position = Vector3(cos(angle) * 1.5 * scale_factor, mesh.size.y * 0.5, sin(angle) * 1.5 * scale_factor)
		pillar.material_override = material_palette.get("ruin_stone", material_palette.get("stone"))
		ruin_root.add_child(pillar)

	var center := MeshInstance3D.new()
	var center_mesh := CylinderMesh.new()
	center_mesh.top_radius = 1.1 * scale_factor
	center_mesh.bottom_radius = 1.25 * scale_factor
	center_mesh.height = 0.22
	center.mesh = center_mesh
	center.position = Vector3(0.0, 0.1, 0.0)
	center.material_override = material_palette.get("ruin_stone", material_palette.get("stone"))
	ruin_root.add_child(center)


func _spawn_abandoned_camp(position_value: Vector3, scale_factor: float) -> void:
	var camp_root := Node3D.new()
	camp_root.position = position_value
	camp_root.rotation_degrees.y = randf_range(0.0, 360.0)
	world_root.add_child(camp_root)

	var tent := MeshInstance3D.new()
	var tent_mesh := PrismMesh.new()
	tent_mesh.size = Vector3(1.6, 1.1, 1.8) * scale_factor
	tent.mesh = tent_mesh
	tent.position = Vector3(0.0, 0.55 * scale_factor, 0.0)
	tent.rotation_degrees.z = 90.0
	tent.material_override = material_palette.get("canvas", material_palette.get("tower_wood"))
	camp_root.add_child(tent)

	var fire_ring := MeshInstance3D.new()
	var fire_mesh := CylinderMesh.new()
	fire_mesh.top_radius = 0.38 * scale_factor
	fire_mesh.bottom_radius = 0.52 * scale_factor
	fire_mesh.height = 0.1
	fire_ring.mesh = fire_mesh
	fire_ring.position = Vector3(1.4 * scale_factor, 0.05, 0.4 * scale_factor)
	fire_ring.material_override = material_palette.get("stone")
	camp_root.add_child(fire_ring)

	var crate := MeshInstance3D.new()
	var crate_mesh := BoxMesh.new()
	crate_mesh.size = Vector3(0.6, 0.46, 0.6) * scale_factor
	crate.mesh = crate_mesh
	crate.position = Vector3(-1.2 * scale_factor, 0.24 * scale_factor, -0.3 * scale_factor)
	crate.material_override = material_palette.get("tower_wood", material_palette.get("bark"))
	camp_root.add_child(crate)


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
			node.position = _random_resource_point(str(config["kind"]))
			node.position.y += 0.02
			world_root.add_child(node)
			node.apply_material_palette(material_palette)
			resources.append(node)
			resource_counter += 1


func _spawn_creatures() -> void:
	var spawn_table := [
		{"species": "wolf", "count": 7},
		{"species": "boar", "count": 6},
		{"species": "deer", "count": 12},
		{"species": "fox", "count": 7},
		{"species": "scavenger", "count": 6},
	]
	var creature_counter := 0
	for row in spawn_table:
		for _index in range(int(row["count"])):
			var creature := CreatureActor.new()
			var spawn_position := _creature_spawn_point(str(row["species"]))
			while spawn_position.distance_to(player.global_position) < 14.0:
				spawn_position = _creature_spawn_point(str(row["species"]))
			creature.position = spawn_position
			var profile := _species_spawn_profile(str(row["species"]))
			creature.configure(
				{
					"id": "creature_%d" % creature_counter,
					"name": _take_name(str(row["species"])),
					"species": str(row["species"]),
					"personality": _random_personality(str(row["species"])),
					"max_health": profile["max_health"],
					"health": profile["max_health"],
					"aggression": profile["aggression"],
					"fear": profile["fear"],
					"hunger": randf_range(18.0, 56.0),
					"thirst": randf_range(14.0, 48.0),
					"energy": randf_range(58.0, 92.0),
					"comfort": randf_range(42.0, 72.0),
					"curiosity": profile["curiosity"],
					"social_drive": profile["social_drive"],
					"sickness": randf_range(0.0, 8.0) if row["species"] == "scavenger" else randf_range(0.0, 4.0),
					"alertness": randf_range(52.0, 78.0),
					"warmth": randf_range(42.0, 66.0),
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
		"deer":
			return ["nervous grazer", "herd-minded drifter", "alert runner", "shy water seeker"][randi() % 4]
		"fox":
			return ["cunning prowler", "opportunistic scavenger", "skittish trickster", "silent hunter"][randi() % 4]
		_:
			return ["opportunistic scavenger", "nervy looter", "cautious rival", "greedy survivor"][randi() % 4]


func _species_spawn_profile(species_name: String) -> Dictionary:
	match species_name:
		"wolf":
			return {"max_health": 90.0, "aggression": 72.0, "fear": 22.0, "curiosity": 44.0, "social_drive": 72.0}
		"boar":
			return {"max_health": 120.0, "aggression": 68.0, "fear": 34.0, "curiosity": 38.0, "social_drive": 26.0}
		"deer":
			return {"max_health": 76.0, "aggression": 18.0, "fear": 58.0, "curiosity": 34.0, "social_drive": 64.0}
		"fox":
			return {"max_health": 62.0, "aggression": 36.0, "fear": 28.0, "curiosity": 66.0, "social_drive": 28.0}
		_:
			return {"max_health": 82.0, "aggression": 44.0, "fear": 18.0, "curiosity": 56.0, "social_drive": 48.0}


func _random_point_in_biomes(allowed_biomes: Array, min_height: float = -0.35) -> Vector3:
	for _attempt in range(80):
		var point := random_world_point(min_height)
		if allowed_biomes.has(biome_at(point)):
			return point
	return random_world_point(min_height)


func _creature_spawn_point(species_name: String) -> Vector3:
	match species_name:
		"wolf":
			return _random_point_in_biomes(["forest", "highland", "alpine", "meadow"], -0.1)
		"boar":
			return _random_point_in_biomes(["forest", "meadow", "wetland"], -0.35)
		"deer":
			return _random_point_in_biomes(["meadow", "forest", "wetland"], -0.3)
		"fox":
			return _random_point_in_biomes(["forest", "meadow"], -0.1)
		_:
			return _random_point_in_biomes(["forest", "meadow", "highland"], -0.1)


func random_world_point(min_height: float = -0.35) -> Vector3:
	for _attempt in range(48):
		var x_value := randf_range(-CONTENT_RADIUS, CONTENT_RADIUS)
		var z_value := randf_range(-CONTENT_RADIUS, CONTENT_RADIUS)
		var y_value := _terrain_height(x_value, z_value)
		if y_value >= min_height:
			return Vector3(x_value, y_value + 0.05, z_value)
	return Vector3(0.0, _terrain_height(0.0, 0.0) + 0.05, 0.0)


func _random_resource_point(kind: String) -> Vector3:
	for _attempt in range(80):
		var point := random_world_point(-0.5)
		var biome_name := _biome_name(point.x, point.z, point.y)
		if kind == "berries" and biome_name in ["forest", "meadow", "wetland"]:
			return point
		if kind == "wood" and biome_name in ["forest", "meadow"]:
			return point
		if kind == "stone" and biome_name in ["highland", "alpine", "meadow"]:
			return point
		if kind == "fiber" and biome_name in ["meadow", "wetland"]:
			return point
		if kind == "herb" and biome_name in ["forest", "meadow", "wetland"]:
			return point
		if kind == "ore" and biome_name in ["highland", "alpine"]:
			return point
	return random_world_point(-0.5)


func biome_at(point: Vector3) -> String:
	return _biome_name(point.x, point.z, point.y)


func find_water_point(origin: Vector3) -> Vector3:
	var best_point := origin
	var best_height := INF
	for radius in [8.0, 16.0, 26.0]:
		for index in range(12):
			var angle := TAU * float(index) / 12.0
			var sample_x: float = origin.x + cos(angle) * radius
			var sample_z: float = origin.z + sin(angle) * radius
			var sample_height := _terrain_height(sample_x, sample_z)
			if sample_height < best_height:
				best_height = sample_height
				best_point = Vector3(sample_x, sample_height + 0.05, sample_z)
	return best_point


func _water_distance_for(origin: Vector3) -> float:
	return origin.distance_to(find_water_point(origin))


func _noise_payload_for(origin: Vector3) -> Dictionary:
	if last_noise_age > 12.0 or last_noise_level == "none":
		return {
			"kind": "none",
			"distance": 999.0,
			"age": 999.0,
			"strength": 0.0,
		}
	return {
		"kind": last_noise_level,
		"distance": snapped(origin.distance_to(last_noise_position), 0.1),
		"age": snapped(last_noise_age, 0.1),
		"strength": last_noise_strength,
	}


func noise_target_for(origin: Vector3):
	if last_noise_age > 9.0 or last_noise_level == "none":
		return null
	if origin.distance_to(last_noise_position) > 38.0:
		return null
	return last_noise_position


func _creature_should_query_ai(creature: CreatureActor) -> bool:
	var player_distance := creature.global_position.distance_to(player.global_position)
	var action := str(creature.decision.get("action", "idle_watch"))
	if player_distance <= 28.0:
		return true
	if action in ["attack", "flee", "stalk", "circle_target", "investigate_sound", "guard"]:
		return true
	if creature.health < creature.max_health * 0.72:
		return true
	if last_noise_age < 2.2 and creature.global_position.distance_to(last_noise_position) < 24.0:
		return true
	return false


func _build_snapshot_for(creature: CreatureActor) -> Dictionary:
	var nearby_creatures: Array = []
	var allies_nearby := 0
	var rivals_nearby := 0
	for other in creatures:
		if other == creature or other.health <= 0.0:
			continue
		var distance := creature.global_position.distance_to(other.global_position)
		if distance <= 24.0:
			var is_ally: bool = other.species == creature.species
			if is_ally:
				allies_nearby += 1
			else:
				rivals_nearby += 1
			nearby_creatures.append(
				{
					"name": other.display_name,
					"species": other.species,
					"distance": snapped(distance, 0.1),
					"ally": is_ally,
					"action": str(other.decision.get("action", "idle_watch")),
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
					"biome": biome_at(resource.global_position),
				}
			)
			if nearby_resources.size() >= 4:
				break

	return {
		"time_label": _time_label(),
		"biome": biome_at(creature.global_position),
		"elevation": snapped(creature.global_position.y, 0.1),
		"near_water": _water_distance_for(creature.global_position) < 10.0,
		"near_campfire": _is_near_campfire(creature.global_position),
		"allies_nearby": allies_nearby,
		"rivals_nearby": rivals_nearby,
		"player": {
			"distance": snapped(creature.global_position.distance_to(player.global_position), 0.1),
			"health": player.health,
			"near_campfire": _is_near_campfire(player.global_position),
			"making_noise": last_noise_age < 1.5,
			"noise_level": last_noise_level,
		},
		"last_noise": _noise_payload_for(creature.global_position),
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
	if player_dead:
		return
	player.receive_damage(amount)
	damage_flash = 1.0
	_spawn_effect_pulse(player.global_position + Vector3(0.0, 1.1, 0.0), Color(0.94, 0.24, 0.18, 0.9), 0.34, 0.38, 1.0)
	_show_message("%s hit you for %d." % [source_name, int(round(amount))])
	if player.health <= 0.0:
		_start_player_death("You were taken down by %s." % source_name)


func _handle_player_actions() -> void:
	if player_dead:
		return
	if Input.is_action_just_pressed("interact") and gather_cooldown <= 0.0:
		gather_cooldown = 0.28
		if not _interact_signal_tower():
			var resource = _focus_resource()
			if resource != null and player.global_position.distance_to(resource.global_position) <= resource.gather_radius + 1.15:
				if resource.harvest(1):
					var amount := _gather_amount_for(resource.resource_type)
					player.add_resource(resource.resource_type, amount)
					player.gain_skill("foraging", 1)
					_record_noise(player.global_position, "gather", 0.42)
					_spawn_effect_pulse(resource.global_position + Vector3(0.0, 0.55, 0.0), Color(0.54, 0.82, 0.41, 0.88), 0.22, 0.44, 0.65)
					_show_message("Gathered %d %s." % [amount, _resource_name(resource.resource_type)])
			else:
				_show_message("Nothing close enough to gather.")

	if Input.is_action_just_pressed("eat_berry") and eat_cooldown <= 0.0:
		eat_cooldown = 0.22
		if player.eat_berry():
			_show_message("You ate a berry.")
		else:
			_show_message("You do not have any berries.")

	if Input.is_action_just_pressed("use_bandage") and eat_cooldown <= 0.0:
		eat_cooldown = 0.22
		if player.use_bandage():
			_spawn_effect_pulse(player.global_position + Vector3(0.0, 1.0, 0.0), Color(0.72, 0.95, 0.72, 0.84), 0.24, 0.42, 0.7)
			_show_message("You wrapped a bandage.")
		else:
			_show_message("You do not have a bandage.")

	if Input.is_action_just_pressed("use_ration") and eat_cooldown <= 0.0:
		eat_cooldown = 0.22
		if player.use_trail_ration():
			_spawn_effect_pulse(player.global_position + Vector3(0.0, 0.9, 0.0), Color(0.92, 0.8, 0.46, 0.84), 0.24, 0.4, 0.6)
			_show_message("You ate a trail ration.")
		else:
			_show_message("You do not have a trail ration.")

	if Input.is_action_just_pressed("cycle_recipe"):
		selected_recipe_index = wrapi(selected_recipe_index + 1, 0, RECIPE_ORDER.size())
		_show_message("Selected recipe: %s." % _selected_recipe()["name"])

	if Input.is_action_just_pressed("craft_item") and craft_cooldown <= 0.0:
		craft_cooldown = 0.32
		_craft_selected_recipe()

	if Input.is_action_just_pressed("attack") and attack_cooldown <= 0.0:
		attack_cooldown = 0.55 * player.attack_cooldown_scale()
		_record_noise(player.global_position, "attack", 0.95)
		_player_attack()

	if Input.is_action_just_pressed("craft_fire") and craft_cooldown <= 0.0:
		craft_cooldown = 0.55
		_record_noise(player.global_position, "craft", 0.62)
		_craft_campfire()


func _player_attack() -> void:
	var target = _focus_creature()
	if target != null and player.global_position.distance_to(target.global_position) > 3.4:
		target = null
	if target == null:
		_show_message("Your attack hit nothing.")
		return

	target.receive_damage(player.attack_damage(), "the player")
	player.gain_skill("combat", 1)
	_spawn_effect_pulse(target.global_position + Vector3(0.0, 0.9, 0.0), Color(1.0, 0.78, 0.34, 0.95), 0.28, 0.35, 0.9)
	crosshair_flash = 1.0
	_show_message("You struck %s the %s." % [target.display_name, target.species])
	if target.health <= 0.0:
		var loot_text := _loot_creature(target)
		player.gain_skill("combat", 2)
		_remove_creature(target)
		if loot_text != "":
			_show_message("%s fell. %s" % [target.display_name, loot_text])


func _gather_amount_for(kind: String) -> int:
	var amount := 1
	if player.skill_level("foraging") >= 2 and randf() < 0.32:
		amount += 1
	if kind == "berries" and player.skill_level("foraging") >= 3 and randf() < 0.25:
		amount += 1
	return amount


func _loot_creature(creature: CreatureActor) -> String:
	match creature.species:
		"deer":
			player.add_resource("hide", 2)
			player.add_resource("fiber", 1)
			return "You collected hide and fiber."
		"boar":
			player.add_resource("hide", 2)
			player.add_resource("herb", 1)
			return "You collected thick hide and herbs."
		"fox":
			player.add_resource("hide", 1)
			player.add_resource("fiber", 1)
			return "You collected a light hide."
		"scavenger":
			player.add_resource("fiber", 1)
			player.add_resource("ore", 1)
			return "You scavenged fiber and ore."
		_:
			player.add_resource("hide", 1)
			return "You collected rough hide."
	return ""


func _selected_recipe() -> Dictionary:
	return RECIPE_DATA[RECIPE_ORDER[selected_recipe_index]]


func _selected_recipe_key() -> String:
	return RECIPE_ORDER[selected_recipe_index]


func _craft_selected_recipe() -> void:
	var recipe_key := _selected_recipe_key()
	var recipe := _selected_recipe()
	if player.skill_level("crafting") < int(recipe["skill"]):
		_show_message("%s needs Crafting %d." % [recipe["name"], int(recipe["skill"])])
		return
	if recipe_key == "spear" and player.has_resource("spear", 1):
		_show_message("You already have a crafted spear.")
		return
	for item_key in recipe["cost"].keys():
		if not player.has_resource(item_key, int(recipe["cost"][item_key])):
			_show_message("Missing materials for %s." % recipe["name"])
			return
	for item_key in recipe["cost"].keys():
		player.consume_resource(item_key, int(recipe["cost"][item_key]))
	player.add_resource(recipe_key, 1)
	player.gain_skill("crafting", int(recipe.get("craft_xp", 1)))
	_record_noise(player.global_position, "craft", 0.54)
	_spawn_effect_pulse(player.global_position + Vector3(0.0, 1.0, 0.0), Color(0.78, 0.86, 1.0, 0.86), 0.28, 0.5, 0.8)
	_show_message("Crafted %s." % recipe["name"])


func _interact_signal_tower() -> bool:
	if signal_tower_root == null:
		return false
	var eye_to_tower: Vector3 = (signal_tower_position + Vector3(0.0, 2.6, 0.0)) - player.eye_position()
	if eye_to_tower.length() > 5.4:
		return false
	var facing := eye_to_tower.normalized().dot(player.view_forward())
	if facing < 0.1:
		return false

	if signal_tower_complete:
		_show_message("The signal tower is already blazing across the valley.")
		return true

	for part_key in ["tower_braces", "signal_core", "beacon_lens"]:
		if not bool(signal_tower_parts.get(part_key, false)) and player.consume_resource(part_key, 1):
			signal_tower_parts[part_key] = true
			player.gain_skill("crafting", 2)
			_spawn_effect_pulse(signal_tower_position + Vector3(0.0, 4.2, 0.0), Color(0.96, 0.82, 0.42, 0.92), 0.34, 0.6, 0.85)
			_show_message("Installed %s into the signal tower." % RECIPE_DATA[part_key]["name"])
			_update_signal_tower_state()
			return true

	if _tower_missing_parts().is_empty():
		_update_signal_tower_state()
		return true

	_show_message("Signal tower still needs: %s." % ", ".join(_tower_missing_parts()))
	return true


func _tower_missing_parts() -> Array[String]:
	var missing: Array[String] = []
	for part_key in ["tower_braces", "signal_core", "beacon_lens"]:
		if not bool(signal_tower_parts.get(part_key, false)):
			missing.append(str(RECIPE_DATA[part_key]["name"]))
	return missing


func _update_signal_tower_state() -> void:
	if signal_tower_glow == null:
		return
	var installed := 0
	for part_key in signal_tower_parts.keys():
		if bool(signal_tower_parts[part_key]):
			installed += 1
	signal_tower_base_energy = 0.15 + float(installed) * 0.4
	signal_tower_glow.light_energy = signal_tower_base_energy
	if installed >= 3:
		signal_tower_complete = true
		signal_tower_base_energy = 2.2
		signal_tower_glow.light_energy = signal_tower_base_energy
		_spawn_effect_pulse(signal_tower_position + Vector3(0.0, 6.8, 0.0), Color(1.0, 0.9, 0.55, 0.98), 0.62, 1.1, 1.25)
		_show_message("The beacon ignites. You rebuilt the signal tower.")


func _recipe_cost_text(recipe_key: String) -> String:
	var recipe: Dictionary = RECIPE_DATA[recipe_key]
	var parts: Array[String] = []
	for item_key in recipe["cost"].keys():
		parts.append("%s x%d" % [item_key.capitalize(), int(recipe["cost"][item_key])])
	return ", ".join(parts)


func _craft_campfire() -> void:
	if not player.has_resource("wood", 2) or not player.has_resource("stone", 1):
		_show_message("Campfire needs 2 wood and 1 stone.")
		return

	player.consume_resource("wood", 2)
	player.consume_resource("stone", 1)

	var fire := CampfireNode.new()
	var forward := player.view_forward_flat()
	if forward == Vector3.ZERO:
		forward = Vector3(0.0, 0.0, 1.0)
	var fire_position := player.global_position + forward * 1.8
	fire_position.y = _terrain_height(fire_position.x, fire_position.z) + 0.05
	fire.position = fire_position
	world_root.add_child(fire)
	fire.apply_material_palette(material_palette)
	campfires.append(fire)
	_spawn_effect_pulse(fire_position + Vector3(0.0, 0.5, 0.0), Color(1.0, 0.62, 0.24, 0.95), 0.3, 0.55, 0.8)
	_show_message("Campfire placed.")


func _is_near_campfire(point: Vector3) -> bool:
	for campfire in campfires:
		if campfire.fuel > 0.0 and point.distance_to(campfire.global_position) <= campfire.warmth_radius:
			return true
	return false


func _focus_resource():
	var origin := player.eye_position()
	var forward := player.view_forward()
	var best = null
	var best_score := -INF
	for resource in resources:
		if not resource.is_available():
			continue
		var target_point: Vector3 = resource.global_position + Vector3(0.0, 0.45, 0.0)
		var to_resource: Vector3 = target_point - origin
		var distance := to_resource.length()
		if distance > resource.gather_radius + 3.0 or distance <= 0.05:
			continue
		var direction := to_resource / distance
		var alignment := direction.dot(forward)
		if alignment < 0.2:
			continue
		var score := alignment * 5.0 - distance * 0.7
		if score > best_score:
			best_score = score
			best = resource
	return best


func _focus_creature():
	var origin := player.eye_position()
	var forward := player.view_forward()
	var best = null
	var best_score := -INF
	for creature in creatures:
		if creature.health <= 0.0:
			continue
		var to_creature: Vector3 = (creature.global_position + Vector3(0.0, 0.8, 0.0)) - origin
		var distance := to_creature.length()
		if distance > 3.8 or distance <= 0.05:
			continue
		var direction := to_creature / distance
		var alignment := direction.dot(forward)
		if alignment < 0.08:
			continue
		var score := alignment * 5.0 - distance
		if score > best_score:
			best_score = score
			best = creature
	return best


func _record_noise(position_value: Vector3, level: String, strength: float) -> void:
	last_noise_position = position_value
	last_noise_age = 0.0
	last_noise_level = level
	last_noise_strength = strength


func broadcast_creature_sound(creature: CreatureActor, sound_name: String) -> void:
	if sound_name == "" or sound_name == "none":
		return

	var noise_strength := 0.36
	if sound_name in ["howl", "bark", "squeal"]:
		noise_strength = 0.78
	elif sound_name in ["growl", "grunt", "snort"]:
		noise_strength = 0.58
	_record_noise(creature.global_position, sound_name, noise_strength)

	for other in creatures:
		if other == creature or other.health <= 0.0:
			continue
		if other.global_position.distance_to(creature.global_position) > 18.0:
			continue
		if other.species == creature.species:
			other.alertness = min(100.0, other.alertness + 8.0)
			other.fear = max(0.0, other.fear - 4.0)
			other.remember("%s made a %s." % [creature.display_name, sound_name])

	if player.global_position.distance_to(creature.global_position) < 16.0:
		_spawn_effect_pulse(creature.global_position + Vector3(0.0, 1.0, 0.0), Color(0.95, 0.83, 0.4, 0.72), 0.18, 0.32, 0.5)
		_show_message("%s the %s made a %s." % [creature.display_name, creature.species, sound_name])


func _constrain_player_to_world() -> void:
	var planar := Vector2(player.global_position.x, player.global_position.z)
	if planar.length() <= WORLD_RADIUS * 0.94:
		return
	var clamped := planar.normalized() * WORLD_RADIUS * 0.94
	player.global_position = Vector3(
		clamped.x,
		_terrain_height(clamped.x, clamped.y) + 0.25,
		clamped.y
	)


func _start_player_death(message: String) -> void:
	if player_dead:
		return
	player_dead = true
	respawn_timer = 2.8
	player.set_controls_enabled(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_show_message(message)


func _respawn_player() -> void:
	var spawn_point := _respawn_point()
	player.reset_state(spawn_point)
	player_dead = false
	player.set_controls_enabled(true)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_show_message("You recovered and returned to the wilds.")


func _respawn_point() -> Vector3:
	var campfire = find_nearest_campfire(player.global_position)
	if campfire != null:
		return campfire.global_position + Vector3(0.0, 0.2, 1.8)
	return Vector3(0.0, _terrain_height(0.0, 0.0) + 0.2, 0.0)


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
	sun_light.light_energy = daylight * 2.55
	moon_light.rotation_degrees = Vector3(35.0 - daylight * 65.0, time_of_day * 360.0 - 155.0, 0.0)
	moon_light.light_energy = clamp(0.72 - daylight, 0.0, 0.72) * 0.58
	sky_material.sky_top_color = Color(0.08, 0.1, 0.18).lerp(Color(0.33, 0.49, 0.72), daylight)
	sky_material.sky_horizon_color = Color(0.18, 0.18, 0.24).lerp(Color(0.81, 0.82, 0.73), daylight)
	sky_material.ground_horizon_color = Color(0.1, 0.13, 0.12).lerp(Color(0.36, 0.39, 0.29), daylight)


func _on_ai_status_ready(payload: Dictionary) -> void:
	if bool(payload.get("using_local_ai", false)):
		ai_status_text = "AI: local %s" % str(payload.get("model_name", "model"))
	else:
		ai_status_text = "AI: unavailable"


func _on_ai_decision_ready(creature_id: String, decision_data: Dictionary) -> void:
	var creature = creature_lookup.get(creature_id)
	if creature == null:
		return
	last_ai_error_message = ""
	ai_status_text = "AI: local %s" % str(ai_bridge.latest_status.get("model_name", "model"))
	creature.apply_decision(decision_data)


func _on_ai_decision_failed(creature_id: String, message: String) -> void:
	var creature = creature_lookup.get(creature_id)
	if creature != null:
		creature.cancel_pending_decision(1.0, "AI call failed")
	if last_ai_error_message == message:
		return
	last_ai_error_message = message
	ai_status_text = "AI: retrying model"
	_show_message(message)


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
	_spawn_effect_pulse(creature.global_position + Vector3(0.0, 0.95, 0.0), Color(0.92, 0.41, 0.25, 0.95), 0.42, 0.55, 1.4)
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
		"fiber":
			return "fiber"
		"herb":
			return "herb"
		"ore":
			return "ore chunk"
		_:
			return "stone"


func _build_ui() -> void:
	ui_root = CanvasLayer.new()
	add_child(ui_root)

	crosshair_label = Label.new()
	crosshair_label.text = "+"
	crosshair_label.position = Vector2(796, 430)
	crosshair_label.size = Vector2(20, 20)
	crosshair_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crosshair_label.add_theme_font_size_override("font_size", 28)
	ui_root.add_child(crosshair_label)

	damage_overlay = ColorRect.new()
	damage_overlay.position = Vector2.ZERO
	damage_overlay.size = Vector2(1600, 900)
	damage_overlay.color = Color(0.72, 0.06, 0.04, 0.0)
	ui_root.add_child(damage_overlay)
	damage_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var message_panel := _make_panel(Vector2(18, 18), Vector2(560, 54))
	ui_root.add_child(message_panel)
	message_label = Label.new()
	message_label.position = Vector2(16, 12)
	message_label.size = Vector2(528, 30)
	message_label.add_theme_font_size_override("font_size", 18)
	message_panel.add_child(message_label)

	var pack_panel := _make_panel(Vector2(18, 498), Vector2(560, 384))
	ui_root.add_child(pack_panel)
	var pack_title := Label.new()
	pack_title.text = "Pack & Status"
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

	inventory_detail_label = Label.new()
	inventory_detail_label.position = Vector2(22, 344)
	inventory_detail_label.size = Vector2(512, 38)
	inventory_detail_label.add_theme_font_size_override("font_size", 16)
	inventory_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pack_panel.add_child(inventory_detail_label)
	skill_label = Label.new()
	skill_label.position = Vector2(22, 314)
	skill_label.size = Vector2(512, 24)
	skill_label.add_theme_font_size_override("font_size", 16)
	skill_label.modulate = Color(0.8, 0.87, 0.89)
	pack_panel.add_child(skill_label)

	inventory_slots.clear()
	var inventory_layout := [
		["berries", "wood", "stone", "fiber", "herb"],
		["ore", "hide", "bandage", "trail_ration", "spear"],
	]
	for row_index in range(inventory_layout.size()):
		for column_index in range(inventory_layout[row_index].size()):
			var item_key := str(inventory_layout[row_index][column_index])
			var slot_position := Vector2(22 + column_index * 102, 212 + row_index * 88)
			inventory_slots[item_key] = _make_inventory_slot(pack_panel, item_key, slot_position, _item_hotkey(item_key))

	var craft_panel := _make_panel(Vector2(18, 372), Vector2(620, 108))
	ui_root.add_child(craft_panel)
	var craft_title := Label.new()
	craft_title.text = "Crafting"
	craft_title.position = Vector2(18, 10)
	craft_title.add_theme_font_size_override("font_size", 24)
	craft_panel.add_child(craft_title)
	craft_label = Label.new()
	craft_label.position = Vector2(18, 40)
	craft_label.size = Vector2(584, 54)
	craft_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	craft_label.add_theme_font_size_override("font_size", 16)
	craft_panel.add_child(craft_label)

	var quest_panel := _make_panel(Vector2(540, 18), Vector2(460, 112))
	ui_root.add_child(quest_panel)
	var quest_title := Label.new()
	quest_title.text = "Goal: Rebuild The Signal Tower"
	quest_title.position = Vector2(18, 10)
	quest_title.add_theme_font_size_override("font_size", 22)
	quest_panel.add_child(quest_title)
	quest_label = Label.new()
	quest_label.position = Vector2(18, 42)
	quest_label.size = Vector2(424, 28)
	quest_label.add_theme_font_size_override("font_size", 17)
	quest_panel.add_child(quest_label)
	tower_hint_label = Label.new()
	tower_hint_label.position = Vector2(18, 68)
	tower_hint_label.size = Vector2(424, 28)
	tower_hint_label.add_theme_font_size_override("font_size", 16)
	tower_hint_label.modulate = Color(0.76, 0.81, 0.83)
	quest_panel.add_child(tower_hint_label)

	var decision_panel := _make_panel(Vector2(1160, 18), Vector2(400, 270))
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
	label.size = Vector2(420, 22)
	label.add_theme_font_size_override("font_size", 20)
	panel.add_child(label)

	var bar := ProgressBar.new()
	bar.position = position_value + Vector2(0, 24)
	bar.size = Vector2(516, 16)
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


func _make_inventory_slot(panel: Panel, item_key: String, position_value: Vector2, hotkey: String = "") -> Dictionary:
	var slot_panel := Panel.new()
	slot_panel.position = position_value
	slot_panel.size = Vector2(94, 80)
	var slot_style := StyleBoxFlat.new()
	slot_style.bg_color = Color(0.06, 0.09, 0.1, 0.94)
	slot_style.border_color = _item_slot_color(item_key)
	slot_style.border_width_left = 2
	slot_style.border_width_top = 2
	slot_style.border_width_right = 2
	slot_style.border_width_bottom = 2
	slot_style.corner_radius_top_left = 12
	slot_style.corner_radius_top_right = 12
	slot_style.corner_radius_bottom_left = 12
	slot_style.corner_radius_bottom_right = 12
	slot_panel.add_theme_stylebox_override("panel", slot_style)
	panel.add_child(slot_panel)

	var icon_bg := ColorRect.new()
	icon_bg.position = Vector2(10, 10)
	icon_bg.size = Vector2(32, 32)
	icon_bg.color = _item_slot_color(item_key).darkened(0.4)
	slot_panel.add_child(icon_bg)

	var icon_rect := TextureRect.new()
	icon_rect.position = Vector2(10, 10)
	icon_rect.size = Vector2(32, 32)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_SCALE
	icon_rect.texture = _item_icon(item_key)
	slot_panel.add_child(icon_rect)

	var name_label := Label.new()
	name_label.text = _item_display_name(item_key)
	name_label.position = Vector2(10, 45)
	name_label.size = Vector2(70, 18)
	name_label.add_theme_font_size_override("font_size", 13)
	slot_panel.add_child(name_label)

	var count_label := Label.new()
	count_label.text = "x0"
	count_label.position = Vector2(48, 12)
	count_label.size = Vector2(36, 18)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.add_theme_font_size_override("font_size", 18)
	slot_panel.add_child(count_label)

	var hotkey_label := Label.new()
	hotkey_label.text = hotkey
	hotkey_label.position = Vector2(48, 32)
	hotkey_label.size = Vector2(36, 16)
	hotkey_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hotkey_label.add_theme_font_size_override("font_size", 12)
	hotkey_label.modulate = Color(0.81, 0.86, 0.9, 0.82)
	slot_panel.add_child(hotkey_label)

	return {"panel": slot_panel, "count": count_label, "hotkey": hotkey_label, "icon": icon_rect}


func _item_display_name(item_key: String) -> String:
	match item_key:
		"trail_ration":
			return "Ration"
		"bandage":
			return "Bandage"
		_:
			return item_key.replace("_", " ").capitalize()


func _item_hotkey(item_key: String) -> String:
	match item_key:
		"berries":
			return "[Q]"
		"bandage":
			return "[H]"
		"trail_ration":
			return "[G]"
		_:
			return ""


func _item_slot_color(item_key: String) -> Color:
	match item_key:
		"berries":
			return Color(0.78, 0.32, 0.44)
		"wood":
			return Color(0.62, 0.4, 0.2)
		"stone":
			return Color(0.57, 0.61, 0.64)
		"fiber":
			return Color(0.53, 0.67, 0.28)
		"herb":
			return Color(0.35, 0.69, 0.48)
		"ore":
			return Color(0.68, 0.68, 0.82)
		"hide":
			return Color(0.74, 0.59, 0.42)
		"bandage":
			return Color(0.89, 0.84, 0.74)
		"trail_ration":
			return Color(0.84, 0.66, 0.28)
		"spear":
			return Color(0.72, 0.72, 0.76)
		_:
			return Color(0.6, 0.65, 0.7)


func _item_icon(item_key: String) -> Texture2D:
	if item_icon_cache.has(item_key):
		return item_icon_cache[item_key]

	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var dark := Color(0.11, 0.12, 0.13, 1.0)
	var accent := _item_slot_color(item_key)

	match item_key:
		"berries":
			_icon_fill_rect(image, 13, 4, 6, 5, Color(0.26, 0.48, 0.18, 1.0))
			_icon_fill_rect(image, 10, 8, 12, 3, Color(0.34, 0.6, 0.22, 1.0))
			_icon_fill_circle(image, 11, 18, 6, accent)
			_icon_fill_circle(image, 20, 18, 6, accent.lightened(0.08))
			_icon_fill_circle(image, 16, 23, 6, accent.darkened(0.1))
		"wood":
			_icon_fill_rect(image, 6, 10, 19, 6, Color(0.58, 0.37, 0.2, 1.0))
			_icon_fill_rect(image, 9, 17, 18, 6, Color(0.49, 0.31, 0.17, 1.0))
			_icon_fill_circle(image, 7, 13, 3, Color(0.72, 0.54, 0.3, 1.0))
			_icon_fill_circle(image, 26, 20, 3, Color(0.72, 0.54, 0.3, 1.0))
		"stone":
			_icon_fill_circle(image, 12, 19, 7, accent)
			_icon_fill_circle(image, 21, 14, 6, accent.darkened(0.08))
			_icon_fill_circle(image, 20, 22, 5, accent.lightened(0.1))
		"fiber":
			for blade in [8, 12, 16, 20, 24]:
				_icon_fill_rect(image, blade, 10 - int(abs(16 - blade) * 0.2), 2, 16 + int(abs(16 - blade) * 0.3), accent)
		"herb":
			_icon_fill_circle(image, 11, 18, 5, accent)
			_icon_fill_circle(image, 21, 18, 5, accent)
			_icon_fill_circle(image, 16, 12, 5, accent.lightened(0.08))
			_icon_fill_circle(image, 16, 20, 3, Color(0.36, 0.61, 0.92, 1.0))
		"ore":
			_icon_fill_circle(image, 14, 18, 8, Color(0.44, 0.48, 0.56, 1.0))
			_icon_fill_circle(image, 22, 20, 5, accent)
			_icon_fill_rect(image, 19, 9, 4, 12, accent.lightened(0.15))
		"hide":
			_icon_fill_rect(image, 9, 10, 14, 12, accent)
			_icon_fill_rect(image, 7, 20, 4, 6, accent.darkened(0.12))
			_icon_fill_rect(image, 21, 20, 4, 6, accent.darkened(0.12))
			_icon_fill_rect(image, 13, 6, 6, 6, accent.lightened(0.08))
		"bandage":
			_icon_fill_rect(image, 8, 8, 16, 16, Color(0.88, 0.84, 0.76, 1.0))
			_icon_fill_rect(image, 14, 10, 4, 12, Color(0.78, 0.26, 0.24, 1.0))
			_icon_fill_rect(image, 10, 14, 12, 4, Color(0.78, 0.26, 0.24, 1.0))
		"trail_ration":
			_icon_fill_rect(image, 10, 8, 12, 16, Color(0.65, 0.45, 0.2, 1.0))
			_icon_fill_rect(image, 12, 6, 8, 4, Color(0.84, 0.66, 0.28, 1.0))
			_icon_fill_rect(image, 13, 14, 6, 6, dark)
		"spear":
			for offset in range(7):
				_icon_fill_rect(image, 7 + offset * 2, 22 - offset * 2, 2, 2, Color(0.66, 0.46, 0.24, 1.0))
			_icon_fill_rect(image, 21, 6, 4, 4, Color(0.76, 0.79, 0.82, 1.0))
			_icon_fill_rect(image, 25, 4, 2, 8, Color(0.76, 0.79, 0.82, 1.0))
		_:
			_icon_fill_circle(image, 16, 16, 8, accent)

	var texture := ImageTexture.create_from_image(image)
	item_icon_cache[item_key] = texture
	return texture


func _icon_fill_rect(image: Image, start_x: int, start_y: int, width: int, height: int, color: Color) -> void:
	for x_index in range(start_x, start_x + width):
		for y_index in range(start_y, start_y + height):
			if x_index >= 0 and y_index >= 0 and x_index < image.get_width() and y_index < image.get_height():
				image.set_pixel(x_index, y_index, color)


func _icon_fill_circle(image: Image, center_x: int, center_y: int, radius: int, color: Color) -> void:
	for x_index in range(center_x - radius, center_x + radius + 1):
		for y_index in range(center_y - radius, center_y + radius + 1):
			if x_index < 0 or y_index < 0 or x_index >= image.get_width() or y_index >= image.get_height():
				continue
			if Vector2(x_index - center_x, y_index - center_y).length() <= float(radius):
				image.set_pixel(x_index, y_index, color)


func _update_ui() -> void:
	if status_timer > 0.0:
		message_label.text = status_message
	else:
		message_label.text = "Survive, craft, and reach the tower."

	health_label.text = "Health %d" % int(round(player.health))
	hunger_label.text = "Food %d" % int(round(max(0.0, 100.0 - player.hunger)))
	energy_label.text = "Energy %d" % int(round(player.energy))
	health_bar.value = player.health
	hunger_bar.value = max(0.0, 100.0 - player.hunger)
	energy_bar.value = player.energy

	for item_key in inventory_slots.keys():
		var slot_data: Dictionary = inventory_slots[item_key]
		var item_count := player.get_count(str(item_key))
		var count_label: Label = slot_data["count"]
		count_label.text = "x%d" % item_count
		count_label.modulate = Color(1.0, 1.0, 1.0) if item_count > 0 else Color(0.54, 0.58, 0.62)
		var slot_panel: Panel = slot_data["panel"]
		var slot_style := slot_panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		slot_style.bg_color = Color(0.08, 0.11, 0.12, 0.97) if item_count > 0 else Color(0.04, 0.06, 0.07, 0.9)
		slot_panel.add_theme_stylebox_override("panel", slot_style)

	inventory_detail_label.text = "Utility: berries [Q], bandage [H], ration [G]. Tower parts: braces x%d, core x%d, lens x%d." % [
		player.get_count("tower_braces"),
		player.get_count("signal_core"),
		player.get_count("beacon_lens"),
	]
	skill_label.text = "Skills  Foraging Lv%d  |  Crafting Lv%d  |  Combat Lv%d" % [
		player.skill_level("foraging"),
		player.skill_level("crafting"),
		player.skill_level("combat"),
	]

	var recipe_key := _selected_recipe_key()
	var recipe := _selected_recipe()
	var can_craft := player.skill_level("crafting") >= int(recipe["skill"])
	craft_label.text = "R cycle  |  C craft  |  %s  |  Cost: %s" % [
		recipe["name"],
		_recipe_cost_text(recipe_key),
	]
	craft_label.text += "\n%s" % str(recipe["hint"])
	if not can_craft:
		craft_label.text += " Needs Crafting %d." % int(recipe["skill"])

	var parts_done := 0
	for part_key in signal_tower_parts.keys():
		if bool(signal_tower_parts[part_key]):
			parts_done += 1
	var missing_text: String = "none" if signal_tower_complete else ", ".join(_tower_missing_parts())
	quest_label.text = "Progress %d / 3  |  Missing: %s" % [parts_done, missing_text]
	var tower_distance: float = player.global_position.distance_to(signal_tower_position)
	if signal_tower_complete:
		tower_hint_label.text = "Beacon restored. Keep exploring."
	else:
		tower_hint_label.text = "Tower %.0fm away. Deliver crafted parts with E." % tower_distance

	ai_status_label.text = ai_status_text
	var low_health := clampf((38.0 - player.health) / 38.0, 0.0, 1.0)
	var pulse := 0.18 + 0.12 * sin(Time.get_ticks_msec() / 1000.0 * 5.0)
	damage_overlay.color.a = clampf(damage_flash * 0.4 + low_health * pulse, 0.0, 0.52)
	crosshair_label.modulate = Color(1.0, 0.86, 0.52).lerp(Color(1.0, 1.0, 1.0), 1.0 - crosshair_flash)
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


func _spawn_effect_pulse(position_value: Vector3, color: Color, scale_factor: float = 0.28, duration: float = 0.45, rise_speed: float = 0.9) -> void:
	if world_root == null:
		return
	var effect_root := Node3D.new()
	effect_root.position = position_value
	world_root.add_child(effect_root)

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.roughness = 0.28
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	for offset in [Vector3.ZERO, Vector3(0.12, 0.08, 0.0), Vector3(-0.1, 0.03, 0.08)]:
		var shard := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.12
		mesh.height = 0.24
		shard.mesh = mesh
		shard.position = offset
		shard.scale = Vector3.ONE * scale_factor
		shard.material_override = material
		effect_root.add_child(shard)

	active_effects.append(
		{
			"node": effect_root,
			"material": material,
			"age": 0.0,
			"duration": duration,
			"rise_speed": rise_speed,
			"base_scale": scale_factor,
			"color": color,
		}
	)


func _tick_world_effects(delta: float) -> void:
	for index in range(active_effects.size() - 1, -1, -1):
		var effect: Dictionary = active_effects[index]
		var node: Node3D = effect["node"]
		var material: StandardMaterial3D = effect["material"]
		var color: Color = effect["color"]
		var age: float = float(effect["age"]) + delta
		var duration: float = float(effect["duration"])
		var progress := clampf(age / max(duration, 0.01), 0.0, 1.0)
		effect["age"] = age
		node.position.y += float(effect["rise_speed"]) * delta
		node.scale = Vector3.ONE * lerpf(1.0, 1.95, progress)
		material.albedo_color = Color(color.r, color.g, color.b, 1.0 - progress)
		material.emission = color * (1.0 - progress * 0.4)
		active_effects[index] = effect
		if age >= duration:
			node.queue_free()
			active_effects.remove_at(index)
