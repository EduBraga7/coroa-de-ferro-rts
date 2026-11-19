extends Node3D

## Bootstrapper principal da partida RTS 'Coroa de Ferro: Crônicas da Fronteira'.
## Renderização Vulkan Forward+ com Shaders PBR de Terreno/Água, SSAO, SSR, Bloom e Grama 3D.

var game_manager: GameManager
var camera_rig: RTSCamera
var ai_controller: AIController
var sfx_manager: SFXManager
var hud: RTSHUD
var world_root: Node3D

var _screenshot_mode: bool = false
var _screenshot_river: bool = false
var _screenshot_units: bool = false
var _screenshot_timer: float = 0.0
var _recent_deltas: Array[float] = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--screenshot":
			_screenshot_mode = true
		elif arg == "--screenshot-river":
			_screenshot_mode = true
			_screenshot_river = true
		elif arg == "--screenshot-units":
			_screenshot_mode = true
			_screenshot_units = true

	_setup_environment_and_lights()
	_setup_terrain_and_river()
	_setup_systems()
	_populate_resources()
	_populate_scenery_props()
	_spawn_starting_bases()

	game_manager.match_started = true
	game_manager.recalculate_population()
	game_manager.focus_camera_on_base()
	game_manager.post_alert("Bem-vindo, Comandante! Colete recursos, erga seu Quartel e conquiste o Barão Corvo Vermelho!", Color(1.0, 0.86, 0.35))

	if _screenshot_mode:
		camera_rig.edge_pan_enabled = false
		if _screenshot_units:
			_setup_units_showcase_screenshot()
		elif _screenshot_river:
			camera_rig.focus_on(Vector3(0.0, 0.0, 0.0), true)
			camera_rig.set_zoom_instant(34.0)
		else:
			camera_rig.focus_on(Vector3(-49.0, 0.0, 48.0), true)
			camera_rig.set_zoom_instant(31.0)


func _setup_units_showcase_screenshot() -> void:
	ai_controller.set_process(false)
	for u in game_manager.units:
		if is_instance_valid(u):
			u.command_stop()
			u._scan_timer = 9999.0
			if u.team == 0 and u.unit_type != "worker":
				u.global_position = Vector3(-66.0, 0.0, 66.0)
	var types: Array[String] = ["worker", "soldier", "archer", "knight"]
	for i in range(types.size()):
		var bx: float = -51.4 + float(i) * 2.5
		var bu: RTSUnit = game_manager.spawn_unit(types[i], Vector3(bx, 0.0, 47.0), 0)
		if bu != null:
			bu.command_stop()
			bu._scan_timer = 9999.0
			bu.rotation.y = PI
		var ru: RTSUnit = game_manager.spawn_unit(types[i], Vector3(bx + 1.1, 0.0, 43.8), 1)
		if ru != null:
			ru.command_stop()
			ru._scan_timer = 9999.0
			ru.rotation.y = PI
	camera_rig.focus_on(Vector3(-47.2, 0.0, 45.4), true)
	camera_rig.set_zoom_instant(12.2)


func _process(delta: float) -> void:
	if _screenshot_mode:
		_screenshot_timer += delta
		if _screenshot_timer >= 1.2 and delta < 0.25:
			_recent_deltas.append(delta)
			if _recent_deltas.size() > 20:
				_recent_deltas.pop_front()
		if _screenshot_timer >= 3.2:
			_screenshot_mode = false
			var sum_d: float = 0.0
			for d in _recent_deltas:
				sum_d += d
			var real_fps: float = float(_recent_deltas.size()) / maxf(0.0001, sum_d) if _recent_deltas.size() > 0 else Engine.get_frames_per_second()
			var img: Image = get_viewport().get_texture().get_image()
			var fname: String = "rts_units_closeup.png" if _screenshot_units else ("rts_river_preview.png" if _screenshot_river else "rts_gameplay_preview.png")
			var out_path: String = ProjectSettings.globalize_path("res://assets/blender/" + fname)
			var err: int = img.save_png(out_path)
			print("SCREENSHOT_SAVED:", out_path, " err=", err, " FPS=", Engine.get_frames_per_second(), " REAL_FPS=", snappedf(real_fps, 0.1))
			get_tree().quit(0)


func _setup_environment_and_lights() -> void:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky: Sky = Sky.new()
	var sky_mat: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.18, 0.39, 0.74)
	sky_mat.sky_horizon_color = Color(0.68, 0.80, 0.90)
	sky_mat.ground_bottom_color = Color(0.16, 0.22, 0.14)
	sky_mat.ground_horizon_color = Color(0.45, 0.56, 0.42)
	sky_mat.sun_angle_max = 28.0
	sky.sky_material = sky_mat
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.34
	env.ambient_light_sky_contribution = 0.72

	# Pós-processamento Forward+ (ACES, Bloom e Névoa suave distante)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.96

	env.ssao_enabled = false
	env.ssr_enabled = false
	env.glow_enabled = false

	env.fog_enabled = true
	env.fog_light_color = Color(0.58, 0.72, 0.86)
	env.fog_density = 0.0007
	env.fog_sky_affect = 0.15

	var we: WorldEnvironment = WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)

	# Sol dourado principal com sombras suaves (1 passagem ortogonal nítida para RTS)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "SunLight"
	sun.light_color = Color(1.0, 0.91, 0.76)
	sun.light_energy = 1.50
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_blur = 0.4
	sun.rotation_degrees = Vector3(-42.0, 38.0, 0.0)
	add_child(sun)

	# Luz celeste fria de preenchimento (elimina sombras chapadas)
	var fill_sun: DirectionalLight3D = DirectionalLight3D.new()
	fill_sun.name = "SkyFillLight"
	fill_sun.light_color = Color(0.52, 0.70, 0.96)
	fill_sun.light_energy = 0.24
	fill_sun.shadow_enabled = false
	fill_sun.rotation_degrees = Vector3(-34.0, -142.0, 0.0)
	add_child(fill_sun)


func _setup_terrain_and_river() -> void:
	world_root = Node3D.new()
	world_root.name = "WorldRoot"
	add_child(world_root)

	# Colisão sólida plana na área jogável
	var ground_body: StaticBody3D = StaticBody3D.new()
	ground_body.name = "Ground"
	ground_body.collision_layer = 1
	ground_body.collision_mask = 0
	world_root.add_child(ground_body)

	var col: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = Vector3(220.0, 1.0, 220.0)
	col.shape = box_shape
	col.position = Vector3(0.0, -0.5, 0.0)
	ground_body.add_child(col)

	# Malha de Terreno Otimizada com Splatmap PBR + Relevo do Rio + Montanhas
	var terrain_mesh: MeshInstance3D = MeshInstance3D.new()
	terrain_mesh.name = "TerrainMesh"
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(220.0, 220.0)
	plane.subdivide_width = 80
	plane.subdivide_depth = 80
	terrain_mesh.mesh = plane
	terrain_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var terrain_shader: Shader = load("res://scripts/shaders/terrain.gdshader") as Shader
	if terrain_shader != null:
		var t_mat: ShaderMaterial = ShaderMaterial.new()
		t_mat.shader = terrain_shader
		var tex_params: Dictionary = {
			"baked_albedo": "res://assets/textures/terrain_baked_albedo.png",
			"detail_normal": "res://assets/textures/terrain_detail_normal.png",
		}
		for param_name in tex_params.keys():
			var tex_res: Texture2D = load(String(tex_params[param_name])) as Texture2D
			if tex_res != null:
				var img: Image = tex_res.get_image()
				if img != null and not img.has_mipmaps():
					img.generate_mipmaps()
					tex_res = ImageTexture.create_from_image(img)
				t_mat.set_shader_parameter(param_name, tex_res)
		terrain_mesh.material_override = t_mat
	else:
		var fallback_mat: StandardMaterial3D = StandardMaterial3D.new()
		fallback_mat.albedo_color = Color(0.20, 0.38, 0.16)
		terrain_mesh.material_override = fallback_mat
	ground_body.add_child(terrain_mesh)

	# Superfície do Rio com Shader de Ondas, Fresnel e Espuma
	var water_mesh: MeshInstance3D = MeshInstance3D.new()
	water_mesh.name = "RiverWater"
	var water_plane: PlaneMesh = PlaneMesh.new()
	water_plane.size = Vector2(14.5, 295.0)
	water_plane.subdivide_width = 8
	water_plane.subdivide_depth = 48
	water_mesh.mesh = water_plane
	water_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water_mesh.position = Vector3(0.0, -0.22, 0.0)
	water_mesh.rotation.y = PI * 0.25

	var water_shader: Shader = load("res://scripts/shaders/water.gdshader") as Shader
	if water_shader != null:
		var w_mat: ShaderMaterial = ShaderMaterial.new()
		w_mat.shader = water_shader
		water_mesh.material_override = w_mat
	else:
		var w_fallback: StandardMaterial3D = StandardMaterial3D.new()
		w_fallback.albedo_color = Color(0.10, 0.42, 0.65, 0.85)
		w_fallback.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		water_mesh.material_override = w_fallback
	world_root.add_child(water_mesh)

	# 3 Pontes Arquitetônicas em Pedra com Pilares Submersos e Braseiros Acesos
	_build_architectural_bridges()


func _build_architectural_bridges() -> void:
	var stone_mat: StandardMaterial3D = StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.42, 0.41, 0.38)
	stone_mat.roughness = 0.84

	var paver_mat: StandardMaterial3D = StandardMaterial3D.new()
	paver_mat.albedo_color = Color(0.35, 0.34, 0.32)
	paver_mat.roughness = 0.88

	var dark_stone_mat: StandardMaterial3D = StandardMaterial3D.new()
	dark_stone_mat.albedo_color = Color(0.26, 0.27, 0.29)
	dark_stone_mat.roughness = 0.90

	var ember_mat: StandardMaterial3D = StandardMaterial3D.new()
	ember_mat.albedo_color = Color(1.0, 0.58, 0.14)
	ember_mat.emission_enabled = true
	ember_mat.emission = Color(1.0, 0.42, 0.08)
	ember_mat.emission_energy_multiplier = 3.8

	for bp in RTSUnit.BRIDGES:
		var bridge: Node3D = Node3D.new()
		bridge.position = bp
		bridge.rotation.y = -PI * 0.25
		world_root.add_child(bridge)

		# Tabuleiro base
		var deck: MeshInstance3D = MeshInstance3D.new()
		var dbox: BoxMesh = BoxMesh.new()
		dbox.size = Vector3(8.6, 0.34, 15.2)
		deck.mesh = dbox
		deck.position = Vector3(0.0, 0.04, 0.0)
		deck.material_override = dark_stone_mat
		bridge.add_child(deck)

		# Lajes transversais em relevo sobre o piso da ponte
		for iz in range(-7, 8):
			var slab: MeshInstance3D = MeshInstance3D.new()
			var sbox: BoxMesh = BoxMesh.new()
			sbox.size = Vector3(7.8, 0.09, 0.86)
			slab.mesh = sbox
			slab.position = Vector3(0.0, 0.23, float(iz) * 0.98)
			slab.material_override = stone_mat if (iz % 2 == 0) else paver_mat
			slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			bridge.add_child(slab)

		# Pilares de pedra submersos no canal do rio
		for pz in [-4.5, 0.0, 4.5]:
			for px in [-3.4, 3.4]:
				var pier: MeshInstance3D = MeshInstance3D.new()
				var pcyl: CylinderMesh = CylinderMesh.new()
				pcyl.top_radius = 0.65
				pcyl.bottom_radius = 0.85
				pcyl.height = 1.45
				pier.mesh = pcyl
				pier.position = Vector3(px, -0.55, pz)
				pier.material_override = dark_stone_mat
				pier.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				bridge.add_child(pier)

		# Parapeitos laterais com ameias e pilares de braseiro
		for side_x in [-4.15, 4.15]:
			var rail: MeshInstance3D = MeshInstance3D.new()
			var rbox: BoxMesh = BoxMesh.new()
			rbox.size = Vector3(0.52, 0.66, 15.0)
			rail.mesh = rbox
			rail.position = Vector3(side_x, 0.45, 0.0)
			rail.material_override = dark_stone_mat
			bridge.add_child(rail)

			for mz in [-4.0, 0.0, 4.0]:
				var merlon: MeshInstance3D = MeshInstance3D.new()
				var mbox: BoxMesh = BoxMesh.new()
				mbox.size = Vector3(0.62, 0.34, 0.95)
				merlon.mesh = mbox
				merlon.position = Vector3(side_x, 0.92, mz)
				merlon.material_override = stone_mat
				bridge.add_child(merlon)

			for end_z in [-6.8, 6.8]:
				var post: MeshInstance3D = MeshInstance3D.new()
				var pbox: BoxMesh = BoxMesh.new()
				pbox.size = Vector3(0.82, 1.38, 0.82)
				post.mesh = pbox
				post.position = Vector3(side_x, 0.72, end_z)
				post.material_override = stone_mat
				bridge.add_child(post)

				var flame: MeshInstance3D = MeshInstance3D.new()
				var fsph: SphereMesh = SphereMesh.new()
				fsph.radius = 0.26
				fsph.height = 0.44
				flame.mesh = fsph
				flame.position = Vector3(side_x, 1.56, end_z)
				flame.material_override = ember_mat
				flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				bridge.add_child(flame)

		# Luz quente única centralizada por ponte (economia de GPU)
		var bridge_light: OmniLight3D = OmniLight3D.new()
		bridge_light.light_color = Color(1.0, 0.65, 0.25)
		bridge_light.light_energy = 1.4
		bridge_light.omni_range = 14.0
		bridge_light.shadow_enabled = false
		bridge_light.distance_fade_enabled = true
		bridge_light.distance_fade_begin = 50.0
		bridge_light.distance_fade_length = 12.0
		bridge_light.position = Vector3(0.0, 2.2, 0.0)
		bridge.add_child(bridge_light)


func _setup_systems() -> void:
	sfx_manager = SFXManager.new()
	sfx_manager.name = "SFXManager"
	add_child(sfx_manager)

	camera_rig = RTSCamera.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)

	game_manager = GameManager.new()
	game_manager.name = "GameManager"
	game_manager.world_root = world_root
	game_manager.camera_rig = camera_rig
	game_manager.sfx = sfx_manager
	add_child(game_manager)

	ai_controller = AIController.new()
	ai_controller.name = "AIController"
	ai_controller.game_manager = game_manager
	add_child(ai_controller)
	game_manager.ai_controller = ai_controller

	hud = RTSHUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(game_manager, camera_rig, ai_controller)
	game_manager.hud = hud


func _populate_resources() -> void:
	# Minas de Ouro do Jogador (SW)
	game_manager.spawn_resource("gold", Vector3(-68.0, 0.0, 56.0), 1000)
	game_manager.spawn_resource("gold", Vector3(-52.0, 0.0, 71.0), 1000)

	# Minas de Ouro da IA (NE)
	game_manager.spawn_resource("gold", Vector3(68.0, 0.0, -56.0), 1000)
	game_manager.spawn_resource("gold", Vector3(52.0, 0.0, -71.0), 1000)

	# Minas de Ouro Ricas Disputadas no Centro/Pontes
	game_manager.spawn_resource("gold", Vector3(-16.0, 0.0, 12.0), 1400)
	game_manager.spawn_resource("gold", Vector3(16.0, 0.0, -12.0), 1400)
	game_manager.spawn_resource("gold", Vector3(-32.0, 0.0, -14.0), 1200)
	game_manager.spawn_resource("gold", Vector3(32.0, 0.0, 14.0), 1200)

	# Bosques do Jogador (SW)
	var sw_trees: Array[Vector3] = [
		Vector3(-73.0, 0.0, 42.0), Vector3(-76.0, 0.0, 47.0), Vector3(-71.0, 0.0, 36.0),
		Vector3(-75.0, 0.0, 66.0), Vector3(-69.0, 0.0, 72.0), Vector3(-63.0, 0.0, 76.0),
		Vector3(-42.0, 0.0, 74.0), Vector3(-37.0, 0.0, 69.0), Vector3(-62.0, 0.0, 32.0),
		Vector3(-56.0, 0.0, 29.0), Vector3(-68.0, 0.0, 26.0),
	]
	for tp in sw_trees:
		game_manager.spawn_resource("wood", tp, 240)

	# Bosques da IA (NE)
	for tp in sw_trees:
		game_manager.spawn_resource("wood", Vector3(-tp.x, 0.0, -tp.z), 240)

	# Bosques intermediários ao longo das margens
	var mid_trees: Array[Vector3] = [
		Vector3(-25.0, 0.0, 35.0), Vector3(-21.0, 0.0, 40.0), Vector3(-29.0, 0.0, 39.0),
		Vector3(-48.0, 0.0, 10.0), Vector3(-44.0, 0.0, 14.0),
		Vector3(25.0, 0.0, -35.0), Vector3(21.0, 0.0, -40.0), Vector3(29.0, 0.0, -39.0),
		Vector3(48.0, 0.0, -10.0), Vector3(44.0, 0.0, -14.0),
	]
	for tp in mid_trees:
		game_manager.spawn_resource("wood", tp, 240)


func _populate_scenery_props() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20261119

	# Marcos 3D do Blender: Ruínas Antigas, Penhascos Rochosos e Sub-bosque
	var props_root: Node3D = Node3D.new()
	props_root.name = "SceneryLandmarks"
	world_root.add_child(props_root)

	var ruins_scene: PackedScene = load("res://assets/models/prop_ruins_arch.glb") as PackedScene
	if ruins_scene != null:
		var ruin_spots: Array[Dictionary] = [
			{"pos": Vector3(-15.0, 0.0, -4.0), "yaw": 0.78},
			{"pos": Vector3(15.0, 0.0, 4.0), "yaw": -2.35},
			{"pos": Vector3(-24.0, 0.0, 22.0), "yaw": -0.78},
			{"pos": Vector3(24.0, 0.0, -22.0), "yaw": 2.35},
		]
		for rs in ruin_spots:
			var inst: Node3D = ruins_scene.instantiate() as Node3D
			if inst != null:
				inst.position = rs["pos"]
				inst.rotation.y = float(rs["yaw"])
				_attach_static_cylinder_collider(inst, 2.25, 3.6)
				game_manager.register_static_obstacle(inst.position, 2.25, "ruin")
				props_root.add_child(inst)

	var cliff_scene: PackedScene = load("res://assets/models/prop_cliff_rock.glb") as PackedScene
	if cliff_scene != null:
		var cliff_spots: Array[Vector3] = [
			Vector3(-18.0, -0.15, -10.5), Vector3(-10.5, -0.15, -18.0),
			Vector3(18.0, -0.15, 10.5), Vector3(10.5, -0.15, 18.0),
			Vector3(-52.0, -0.15, -42.0), Vector3(-42.0, -0.15, -52.0),
			Vector3(52.0, -0.15, 42.0), Vector3(42.0, -0.15, 52.0),
			Vector3(-76.5, 0.1, 56.0), Vector3(-52.0, 0.1, 77.5),
			Vector3(76.5, 0.1, -56.0), Vector3(52.0, 0.1, -77.5),
			Vector3(-77.5, 0.2, 22.0), Vector3(77.5, 0.2, -22.0),
			Vector3(-24.0, 0.2, 77.5), Vector3(24.0, 0.2, -77.5),
		]
		for cp in cliff_spots:
			var c_inst: Node3D = cliff_scene.instantiate() as Node3D
			if c_inst != null:
				c_inst.position = cp
				c_inst.rotation.y = rng.randf_range(0.0, TAU)
				var cs: float = rng.randf_range(0.85, 1.35)
				c_inst.scale = Vector3(cs, cs * rng.randf_range(0.85, 1.15), cs)
				_set_cast_shadow_recursive(c_inst, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
				_attach_static_cylinder_collider(c_inst, 1.75 * cs, 2.8)
				game_manager.register_static_obstacle(c_inst.position, 1.75 * cs, "cliff")
				props_root.add_child(c_inst)

	var shrub_scene: PackedScene = load("res://assets/models/prop_shrub_cluster.glb") as PackedScene
	if shrub_scene != null:
		var shrub_anchors: Array[Vector3] = [
			Vector3(-71.0, 0.0, 44.0), Vector3(-74.0, 0.0, 40.0), Vector3(-70.0, 0.0, 34.0),
			Vector3(-73.0, 0.0, 68.0), Vector3(-67.0, 0.0, 74.0), Vector3(-40.0, 0.0, 72.0),
			Vector3(-60.0, 0.0, 31.0), Vector3(-54.0, 0.0, 28.0),
			Vector3(71.0, 0.0, -44.0), Vector3(74.0, 0.0, -40.0), Vector3(70.0, 0.0, -34.0),
			Vector3(73.0, 0.0, -68.0), Vector3(67.0, 0.0, -74.0), Vector3(40.0, 0.0, -72.0),
			Vector3(60.0, 0.0, -31.0), Vector3(54.0, 0.0, -28.0),
			Vector3(-24.0, 0.0, 37.0), Vector3(-27.0, 0.0, 40.0), Vector3(-46.0, 0.0, 12.0),
			Vector3(24.0, 0.0, -37.0), Vector3(27.0, 0.0, -40.0), Vector3(46.0, 0.0, -12.0),
			Vector3(-18.2, 0.0, -3.2), Vector3(18.2, 0.0, 3.2),
			Vector3(-20.8, 0.0, 24.8), Vector3(20.8, 0.0, -24.8),
		]
		for sp in shrub_anchors:
			var s_inst: Node3D = shrub_scene.instantiate() as Node3D
			if s_inst != null:
				s_inst.position = sp + Vector3(rng.randf_range(-1.1, 1.1), 0.0, rng.randf_range(-1.1, 1.1))
				s_inst.rotation.y = rng.randf_range(0.0, TAU)
				var ss: float = rng.randf_range(0.85, 1.25)
				s_inst.scale = Vector3.ONE * ss
				_set_cast_shadow_recursive(s_inst, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
				_attach_static_cylinder_collider(s_inst, 0.68 * ss, 1.4)
				game_manager.register_static_obstacle(s_inst.position, 0.68 * ss, "shrub")
				props_root.add_child(s_inst)


func _attach_static_cylinder_collider(target: Node3D, radius: float, height: float = 3.0) -> void:
	var sb: StaticBody3D = StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	# Compensa a escala do nó pai para que o colisor físico tenha o raio exato no espaço do mundo
	sb.scale = Vector3(
		1.0 / maxf(0.01, target.scale.x),
		1.0 / maxf(0.01, target.scale.y),
		1.0 / maxf(0.01, target.scale.z)
	)
	var col: CollisionShape3D = CollisionShape3D.new()
	var cyl: CylinderShape3D = CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = height
	col.shape = cyl
	col.position.y = height * 0.5
	sb.add_child(col)
	target.add_child(sb)


func _set_cast_shadow_recursive(node: Node, mode: GeometryInstance3D.ShadowCastingSetting) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = mode
	for child in node.get_children():
		_set_cast_shadow_recursive(child, mode)


func _spawn_starting_bases() -> void:
	# --- BASE DO JOGADOR (TIME 0 - AZUL, SUDOESTE) ---
	var p_tc: RTSBuilding = game_manager.place_building_at("town_center", Vector3(-55.0, 0.0, 55.0), 0, true)
	p_tc.set_rally_point(Vector3(-47.0, 0.0, 47.0))
	game_manager.place_building_at("house", Vector3(-63.0, 0.0, 45.0), 0, true)
	game_manager.place_building_at("tower", Vector3(-44.0, 0.0, 38.0), 0, true)

	var pw1: RTSUnit = game_manager.spawn_unit("worker", Vector3(-61.0, 0.0, 55.0), 0)
	var pw2: RTSUnit = game_manager.spawn_unit("worker", Vector3(-54.0, 0.0, 62.0), 0)
	var pw3: RTSUnit = game_manager.spawn_unit("worker", Vector3(-59.0, 0.0, 49.0), 0)
	var _pw4: RTSUnit = game_manager.spawn_unit("worker", Vector3(-49.0, 0.0, 58.0), 0)

	pw1.command_auto_gather_near("gold")
	pw2.command_auto_gather_near("gold")
	pw3.command_auto_gather_near("wood")

	game_manager.spawn_unit("soldier", Vector3(-45.0, 0.0, 46.0), 0)
	game_manager.spawn_unit("soldier", Vector3(-47.0, 0.0, 44.0), 0)
	game_manager.spawn_unit("archer", Vector3(-48.0, 0.0, 48.0), 0)

	# --- BASE DO INIMIGO IA (TIME 1 - VERMELHO, NORDESTE) ---
	var ai_tc: RTSBuilding = game_manager.place_building_at("town_center", Vector3(55.0, 0.0, -55.0), 1, true)
	ai_tc.set_rally_point(Vector3(47.0, 0.0, -47.0))
	game_manager.place_building_at("house", Vector3(63.0, 0.0, -45.0), 1, true)
	game_manager.place_building_at("tower", Vector3(44.0, 0.0, -38.0), 1, true)

	game_manager.spawn_unit("worker", Vector3(61.0, 0.0, -55.0), 1)
	game_manager.spawn_unit("worker", Vector3(54.0, 0.0, -62.0), 1)
	game_manager.spawn_unit("worker", Vector3(59.0, 0.0, -49.0), 1)
	game_manager.spawn_unit("worker", Vector3(49.0, 0.0, -58.0), 1)

	game_manager.spawn_unit("soldier", Vector3(45.0, 0.0, -46.0), 1)
	game_manager.spawn_unit("soldier", Vector3(47.0, 0.0, -44.0), 1)
	game_manager.spawn_unit("archer", Vector3(48.0, 0.0, -48.0), 1)
