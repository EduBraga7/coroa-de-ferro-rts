extends StaticBody3D
class_name RTSBuilding

## Estrutura construtível no RTS. Todos os prédios ficam disponíveis desde o início:
## o que limita é economia, população e tempo (ver docs/DESIGN.md).

const STATS: Dictionary = {
	"town_center": {
		"name": "Salão Real",
		"cost": {"wood": 275, "stone": 100},
		"hp": 2200.0, "armor": 5, "build_time": 50.0, "radius": 3.5, "pop_bonus": 10, "sight": 18.0,
		"attack_range": 14.0, "attack_damage": 12.0, "attack_cd": 1.6, "arrows": 1,
		"trains": ["worker"], "drop": ["food", "wood", "gold", "stone"], "main": true,
		"model": "res://assets/models/building_town_center.glb", "hp_height": 8.4, "hp_width": 3.4,
		"flag": Vector3(0.0, 7.2, 0.0), "light": 1.55,
		"desc": "Centro do reino: treina camponeses e recebe todos os recursos. Perder todos os Salões e Castelos é a derrota.",
	},
	"house": {
		"name": "Casa",
		"cost": {"wood": 50},
		"hp": 550.0, "armor": 1, "build_time": 10.0, "radius": 2.0, "pop_bonus": 8, "sight": 8.0,
		"model": "res://assets/models/building_house.glb", "hp_height": 4.4, "hp_width": 2.1,
		"desc": "+8 de população máxima.",
	},
	"farm": {
		"name": "Fazenda",
		"cost": {"wood": 60},
		"hp": 260.0, "armor": 0, "build_time": 8.0, "radius": 2.9, "pop_bonus": 0, "sight": 6.0,
		"farm_food": 450,
		"model": "res://assets/models/building_farm.glb", "hp_height": 2.4, "hp_width": 3.0,
		"flag": Vector3(2.75, 1.25, 2.75),
		"desc": "Campo de cultivo: 450 de comida. Construa perto de um Moinho ou Salão Real.",
	},
	"mill": {
		"name": "Moinho",
		"cost": {"wood": 100},
		"hp": 700.0, "armor": 1, "build_time": 14.0, "radius": 2.3, "sight": 9.0,
		"drop": ["food"],
		"model": "res://assets/models/building_mill.glb", "hp_height": 7.4, "hp_width": 2.4,
		"flag": Vector3(1.95, 1.25, 1.95),
		"desc": "Ponto de entrega de comida. Construa perto de frutos silvestres e fazendas.",
	},
	"lumber_camp": {
		"name": "Serraria",
		"cost": {"wood": 100},
		"hp": 700.0, "armor": 1, "build_time": 14.0, "radius": 2.3, "sight": 9.0,
		"drop": ["wood"],
		"model": "res://assets/models/building_lumber_camp.glb", "hp_height": 4.2, "hp_width": 2.4,
		"flag": Vector3(-2.15, 1.25, -1.8),
		"desc": "Ponto de entrega de madeira. Construa na borda de uma floresta.",
	},
	"mining_camp": {
		"name": "Mineração",
		"cost": {"wood": 100},
		"hp": 700.0, "armor": 1, "build_time": 14.0, "radius": 2.3, "sight": 9.0,
		"drop": ["gold", "stone"],
		"model": "res://assets/models/building_mining_camp.glb", "hp_height": 4.4, "hp_width": 2.4,
		"flag": Vector3(2.2, 1.25, 1.9),
		"desc": "Ponto de entrega de ouro e pedra. Construa perto de minas e pedreiras.",
	},
	"barracks": {
		"name": "Quartel",
		"cost": {"wood": 175},
		"hp": 1300.0, "armor": 2, "build_time": 22.0, "radius": 2.8, "sight": 10.0,
		"trains": ["soldier", "spearman", "scout"],
		"model": "res://assets/models/building_barracks.glb", "hp_height": 5.3, "hp_width": 2.8,
		"light": 1.1,
		"desc": "Treina Espadachins, Lanceiros e Batedores.",
	},
	"archery_range": {
		"name": "Campo de Tiro",
		"cost": {"wood": 175},
		"hp": 1200.0, "armor": 2, "build_time": 22.0, "radius": 2.8, "sight": 10.0,
		"trains": ["archer"],
		"model": "res://assets/models/building_archery_range.glb", "hp_height": 4.8, "hp_width": 2.8,
		"flag": Vector3(2.6, 1.25, 0.6),
		"desc": "Treina Arqueiros.",
	},
	"siege_workshop": {
		"name": "Oficina de Cerco",
		"cost": {"wood": 200, "gold": 50},
		"hp": 1400.0, "armor": 2, "build_time": 26.0, "radius": 3.1, "sight": 10.0,
		"trains": ["ram"],
		"model": "res://assets/models/building_siege_workshop.glb", "hp_height": 6.0, "hp_width": 3.0,
		"flag": Vector3(3.0, 1.4, 2.6),
		"desc": "Constrói Aríetes para derrubar muralhas, torres e castelos.",
	},
	"market": {
		"name": "Mercado",
		"cost": {"wood": 175},
		"hp": 1300.0, "armor": 1, "build_time": 26.0, "radius": 3.0, "sight": 10.0,
		"market": true,
		"model": "res://assets/models/building_market.glb", "hp_height": 4.2, "hp_width": 3.0,
		"flag": Vector3(2.9, 1.25, -2.9),
		"desc": "Compra e vende comida, madeira e pedra em troca de ouro.",
	},
	"tower": {
		"name": "Torre de Vigia",
		"cost": {"wood": 50, "stone": 125},
		"hp": 1000.0, "armor": 4, "build_time": 22.0, "radius": 1.8, "sight": 20.0,
		"attack_range": 17.5, "attack_damage": 16.0, "attack_cd": 1.5, "arrows": 1,
		"model": "res://assets/models/building_tower.glb", "hp_height": 8.6, "hp_width": 2.2,
		"flag": Vector3(0.0, 8.2, 0.0),
		"desc": "Defesa com flechas e grande alcance de visão.",
	},
	"lair": {
		"name": "Covil do Corvo Vermelho",
		"cost": {},
		"hp": 6000.0, "armor": 10, "build_time": 1.0, "radius": 4.3, "sight": 16.0,
		"attack_range": 16.0, "attack_damage": 12.0, "attack_cd": 1.6, "arrows": 2,
		"enemy_only": true,
		"model": "res://assets/models/building_lair.glb", "hp_height": 6.2, "hp_width": 4.0,
		"flag": Vector3(-2.6, 1.6, 2.2),
		"desc": "Manda ondas cada vez mais fortes e, se atacado, convoca defensores. Aríetes derrubam a paliçada. Destrua todos para vencer.",
	},
	"castle": {
		"name": "Castelo",
		"cost": {"stone": 650},
		"hp": 4800.0, "armor": 8, "build_time": 68.0, "radius": 4.6, "pop_bonus": 10, "sight": 22.0,
		"attack_range": 20.0, "attack_damage": 15.0, "attack_cd": 1.2, "arrows": 3,
		"trains": ["knight"], "main": true,
		"model": "res://assets/models/building_castle.glb", "hp_height": 11.2, "hp_width": 4.2,
		"flag": Vector3(0.0, 6.4, -4.1), "light": 1.6,
		"desc": "Fortaleza: dispara várias flechas, treina Paladinos Reais e conta como estrutura principal.",
	},
}

var building_type: String = "house"
var team: int = 0
var max_hp: float = 400.0
var hp: float = 400.0
var armor: int = 1
var is_constructed: bool = false
var build_progress: float = 0.0
var build_time: float = 12.0
var footprint_radius: float = 2.0
var pop_bonus: int = 0
var sight_range: float = 8.0
var drop_types: Array = []
var trainable: Array = []
var is_main_structure: bool = false

var production_queue: Array[String] = []
var production_timer: float = 0.0
var current_produce_time: float = 1.0
var rally_point: Vector3 = Vector3.ZERO
var has_custom_rally: bool = false

var attack_range: float = 0.0
var attack_damage: float = 0.0
var attack_cooldown: float = 1.5
var arrows_per_volley: int = 1
var _attack_timer: float = 0.0
var _is_selected: bool = false
var _dead: bool = false

var discovered: bool = false
var fog_hidden: bool = false

var _game_manager: Node = null
var _visual_root: Node3D
var _scaffolding_root: Node3D
var _sails_root: Node3D
var _selection_ring: MeshInstance3D
var _team_ring: MeshInstance3D
var _rally_marker: MeshInstance3D
var _warm_light: OmniLight3D
var _warm_light_base: float = 0.0
var _flicker_seed: float = 0.0
var _detail_vfx: Array[Node3D] = []
var _hp_root: Node3D
var _hp_fill: MeshInstance3D
var _hp_width: float = 2.4
var _base_max_hp: float = 400.0
var _base_attack_damage: float = 0.0
var _base_attack_range: float = 0.0
var _base_arrows: int = 1
var _hit_flash_timer: float = 0.0
var _dmg_popup_cd: float = 0.0


func setup(b_type: String, p_team: int, start_built: bool, gm: Node) -> void:
	building_type = b_type
	team = p_team
	_game_manager = gm

	var cfg: Dictionary = STATS.get(building_type, STATS["house"])
	_base_max_hp = float(cfg["hp"])
	_base_attack_damage = float(cfg.get("attack_damage", 0.0))
	_base_attack_range = float(cfg.get("attack_range", 0.0))
	_base_arrows = int(cfg.get("arrows", 1))
	max_hp = _base_max_hp
	armor = int(cfg["armor"])
	build_time = float(cfg["build_time"])
	footprint_radius = float(cfg["radius"])
	pop_bonus = int(cfg.get("pop_bonus", 0))
	sight_range = float(cfg.get("sight", 8.0))
	attack_range = _base_attack_range
	attack_damage = _base_attack_damage
	attack_cooldown = float(cfg.get("attack_cd", 1.5))
	arrows_per_volley = _base_arrows
	drop_types = cfg.get("drop", [])
	trainable = cfg.get("trains", [])
	is_main_structure = bool(cfg.get("main", false))
	_hp_width = float(cfg["hp_width"])

	is_constructed = start_built
	if is_constructed:
		build_progress = 1.0
		hp = max_hp
	else:
		build_progress = 0.05
		hp = maxf(25.0, max_hp * 0.15)

	add_to_group("rts_buildings")
	_build_visuals(cfg)
	_build_collision()
	apply_kingdom_modifiers()
	_update_construction_visuals()
	_update_hp_bar()


static func get_cost(b_type: String) -> Dictionary:
	var cfg: Dictionary = STATS.get(b_type, {})
	return cfg.get("cost", {})


static func get_drop_types(b_type: String) -> Array:
	var cfg: Dictionary = STATS.get(b_type, {})
	return cfg.get("drop", [])


static func get_trainable(b_type: String) -> Array:
	var cfg: Dictionary = STATS.get(b_type, {})
	return cfg.get("trains", [])


func _ready() -> void:
	if rally_point == Vector3.ZERO:
		var to_center: Vector3 = -global_position
		to_center.y = 0.0
		if to_center.length_squared() < 1.0:
			to_center = Vector3(1.0, 0.0, -1.0)
		rally_point = global_position + to_center.normalized() * (footprint_radius + 3.0)


func _build_visuals(cfg: Dictionary) -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "VisualRoot"
	add_child(_visual_root)

	var model_path: String = String(cfg["model"])
	var packed: PackedScene = load(model_path) as PackedScene
	if packed != null:
		var inst: Node3D = packed.instantiate() as Node3D
		if inst != null:
			_visual_root.add_child(inst)
	else:
		var fallback: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(footprint_radius * 1.4, 3.0, footprint_radius * 1.4)
		fallback.mesh = box
		fallback.position.y = 1.5
		_visual_root.add_child(fallback)

	if building_type == "mill":
		_build_mill_sails()

	# Bandeira / Estandarte colorido do time
	var team_col: Color = RTSUnit.team_color(team)
	var banner_pole: MeshInstance3D = MeshInstance3D.new()
	var pole_mesh: CylinderMesh = CylinderMesh.new()
	pole_mesh.top_radius = 0.045
	pole_mesh.bottom_radius = 0.06
	pole_mesh.height = 2.5
	banner_pole.mesh = pole_mesh
	var pole_mat: StandardMaterial3D = StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.88, 0.70, 0.24)
	pole_mat.metallic = 0.9
	pole_mat.roughness = 0.25
	banner_pole.material_override = pole_mat
	var pole_pos: Vector3 = Vector3(footprint_radius * 0.65, 2.2, footprint_radius * 0.65)
	if cfg.has("flag"):
		pole_pos = cfg["flag"]
	banner_pole.position = pole_pos
	_visual_root.add_child(banner_pole)

	var flag: MeshInstance3D = MeshInstance3D.new()
	var banner_shader: Shader = load("res://scripts/shaders/banner_wave.gdshader") as Shader
	if banner_shader != null:
		var flag_pm: PlaneMesh = PlaneMesh.new()
		flag_pm.orientation = PlaneMesh.FACE_Z
		flag_pm.size = Vector2(1.25, 0.66)
		flag_pm.subdivide_width = 8
		flag.mesh = flag_pm
		flag.position = pole_pos + Vector3(0.0, 0.72, 0.62)
		flag.rotation.y = -PI * 0.5
		var b_mat: ShaderMaterial = ShaderMaterial.new()
		b_mat.shader = banner_shader
		b_mat.set_shader_parameter("team_color", team_col)
		flag.material_override = b_mat
	else:
		var flag_mesh: BoxMesh = BoxMesh.new()
		flag_mesh.size = Vector3(0.06, 0.68, 1.25)
		flag.mesh = flag_mesh
		flag.position = pole_pos + Vector3(0.0, 0.72, 0.62)
		var flag_mat: StandardMaterial3D = StandardMaterial3D.new()
		flag_mat.albedo_color = team_col
		flag_mat.roughness = 0.55
		flag_mat.emission_enabled = true
		flag_mat.emission = team_col * 0.28
		flag.material_override = flag_mat
	flag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual_root.add_child(flag)

	if building_type != "farm":
		add_child(VFXManager.create_contact_ao_disc(footprint_radius * 1.32, 0.38))

	_flicker_seed = fposmod(absf(position.x * 0.73 + position.z * 1.19), TAU)

	# Luz acolhedora quente (apenas prédios maiores, com fade por distância e tremor natural)
	if cfg.has("light"):
		_warm_light = OmniLight3D.new()
		_warm_light.light_color = Color(1.0, 0.72, 0.34)
		_warm_light_base = float(cfg["light"])
		_warm_light.light_energy = _warm_light_base
		_warm_light.omni_range = footprint_radius * 2.6
		_warm_light.omni_attenuation = 1.4
		_warm_light.shadow_enabled = false
		_warm_light.distance_fade_enabled = true
		_warm_light.distance_fade_begin = 48.0
		_warm_light.distance_fade_length = 12.0
		_warm_light.position = Vector3(0.0, 2.3, -footprint_radius * 0.78)
		_warm_light.visible = is_constructed
		add_child(_warm_light)

	if _game_manager != null and _game_manager.get("vfx") != null:
		_attach_building_vfx(_game_manager.vfx as VFXManager)

	# Anel sutil de cor do time e seleção fora do plinto do prédio
	var ring_mult: float = 1.24 if building_type in ["castle", "town_center", "barracks", "market", "siege_workshop"] else 1.06
	_team_ring = MeshInstance3D.new()
	var t_torus: TorusMesh = TorusMesh.new()
	t_torus.inner_radius = footprint_radius * ring_mult
	t_torus.outer_radius = footprint_radius * (ring_mult + 0.06)
	t_torus.rings = 32
	t_torus.ring_segments = 6
	_team_ring.mesh = t_torus
	_team_ring.position.y = 0.05
	_team_ring.scale = Vector3(1.0, 0.10, 1.0)
	var t_mat: StandardMaterial3D = StandardMaterial3D.new()
	t_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	t_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	t_mat.albedo_color = Color(team_col.r, team_col.g, team_col.b, 0.42)
	_team_ring.material_override = t_mat
	_team_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_team_ring)

	# Anel de seleção brilhante
	_selection_ring = MeshInstance3D.new()
	var s_torus: TorusMesh = TorusMesh.new()
	s_torus.inner_radius = footprint_radius * (ring_mult + 0.07)
	s_torus.outer_radius = footprint_radius * (ring_mult + 0.22)
	s_torus.rings = 36
	s_torus.ring_segments = 6
	_selection_ring.mesh = s_torus
	_selection_ring.position.y = 0.07
	_selection_ring.scale = Vector3(1.0, 0.12, 1.0)
	var s_mat: StandardMaterial3D = StandardMaterial3D.new()
	s_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	s_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	s_mat.albedo_color = Color(0.28, 0.96, 0.48, 0.88) if team == 0 else Color(1.0, 0.35, 0.25, 0.88)
	_selection_ring.material_override = s_mat
	_selection_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_selection_ring.visible = false
	add_child(_selection_ring)

	# Andaimes de construção
	_scaffolding_root = Node3D.new()
	_scaffolding_root.name = "Scaffolding"
	add_child(_scaffolding_root)
	var scaf_mat: StandardMaterial3D = StandardMaterial3D.new()
	scaf_mat.albedo_color = Color(0.55, 0.36, 0.18)
	var d: float = footprint_radius * 0.78
	for sx in [-d, d]:
		for sz in [-d, d]:
			var post: MeshInstance3D = MeshInstance3D.new()
			var pbox: BoxMesh = BoxMesh.new()
			pbox.size = Vector3(0.22, 2.8, 0.22)
			post.mesh = pbox
			post.position = Vector3(sx, 1.4, sz)
			post.material_override = scaf_mat
			_scaffolding_root.add_child(post)

	# Marcador de ponto de reunião (visível quando selecionado)
	_rally_marker = MeshInstance3D.new()
	var r_cone: CylinderMesh = CylinderMesh.new()
	r_cone.top_radius = 0.05
	r_cone.bottom_radius = 0.38
	r_cone.height = 1.2
	_rally_marker.mesh = r_cone
	var r_mat: StandardMaterial3D = StandardMaterial3D.new()
	r_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	r_mat.albedo_color = Color(0.95, 0.82, 0.22)
	_rally_marker.material_override = r_mat
	_rally_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rally_marker.visible = false
	_rally_marker.top_level = true
	add_child(_rally_marker)

	# Barra de vida 3D
	_hp_root = Node3D.new()
	_hp_root.position = Vector3(0.0, float(cfg["hp_height"]), 0.0)
	add_child(_hp_root)

	var bg: MeshInstance3D = MeshInstance3D.new()
	var bg_q: QuadMesh = QuadMesh.new()
	bg_q.size = Vector2(_hp_width, 0.28)
	bg.mesh = bg_q
	var bg_mat: StandardMaterial3D = StandardMaterial3D.new()
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.albedo_color = Color(0.08, 0.09, 0.12, 0.9)
	bg.material_override = bg_mat
	bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hp_root.add_child(bg)

	_hp_fill = MeshInstance3D.new()
	var fill_q: QuadMesh = QuadMesh.new()
	fill_q.size = Vector2(_hp_width - 0.1, 0.18)
	_hp_fill.mesh = fill_q
	_hp_fill.position = Vector3(0.0, 0.0, 0.015)
	var fill_mat: StandardMaterial3D = StandardMaterial3D.new()
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.albedo_color = Color(0.22, 0.78, 1.0) if team == 0 else Color(0.95, 0.28, 0.25)
	_hp_fill.material_override = fill_mat
	_hp_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hp_root.add_child(_hp_fill)


func _attach_building_vfx(vfx_mgr: VFXManager) -> void:
	if vfx_mgr == null:
		return
	var flame_spots: Array = []
	var smoke_spots: Array = []
	match building_type:
		"town_center":
			flame_spots = [
				[Vector3(-1.55, 1.52, -3.25), 0.85],
				[Vector3(1.55, 1.52, -3.25), 0.85],
				[Vector3(-1.55, 1.52, 2.95), 0.85],
				[Vector3(1.55, 1.52, 2.95), 0.85],
			]
			smoke_spots = [[Vector3(-1.35, 6.98, 1.25), 1.0]]
		"castle":
			flame_spots = [
				[Vector3(-1.70, 1.55, -5.40), 1.0],
				[Vector3(1.70, 1.55, -5.40), 1.0],
			]
		"barracks":
			flame_spots = [[Vector3(-1.95, 1.15, -1.35), 1.05]]
			smoke_spots = [[Vector3(-1.70, 5.20, 1.60), 0.9]]
		"house":
			smoke_spots = [[Vector3(-1.15, 3.98, 0.90), 0.72]]
		"lair":
			flame_spots = [[Vector3(1.40, 0.42, -1.50), 1.35]]
			smoke_spots = [[Vector3(1.40, 1.12, -1.50), 1.1]]

	for entry in flame_spots:
		var fl: Node3D = vfx_mgr.create_torch_flame(float(entry[1]), 2.4)
		fl.position = entry[0]
		fl.visible = is_constructed
		add_child(fl)
		_detail_vfx.append(fl)
	for entry in smoke_spots:
		var sm: GPUParticles3D = vfx_mgr.create_chimney_smoke(float(entry[1]))
		sm.position = entry[0]
		sm.visible = is_constructed
		add_child(sm)
		_detail_vfx.append(sm)


func _build_mill_sails() -> void:
	# Pás do moinho giratórias (eixo do modelo em Blender (0, 1.38, 4.05) -> Godot (0, 4.05, -1.38))
	_sails_root = Node3D.new()
	_sails_root.name = "MillSails"
	_sails_root.position = Vector3(0.0, 4.05, -1.82)
	_visual_root.add_child(_sails_root)
	var frame_mat: StandardMaterial3D = StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.30, 0.19, 0.10)
	frame_mat.roughness = 0.8
	var cloth_mat: StandardMaterial3D = StandardMaterial3D.new()
	cloth_mat.albedo_color = Color(0.90, 0.85, 0.72)
	cloth_mat.roughness = 0.9
	for i in range(4):
		var arm: Node3D = Node3D.new()
		arm.rotation.z = float(i) * PI * 0.5
		_sails_root.add_child(arm)
		var spar: MeshInstance3D = MeshInstance3D.new()
		var spar_box: BoxMesh = BoxMesh.new()
		spar_box.size = Vector3(0.12, 2.9, 0.08)
		spar.mesh = spar_box
		spar.position = Vector3(0.0, 1.45, 0.0)
		spar.material_override = frame_mat
		arm.add_child(spar)
		var sail: MeshInstance3D = MeshInstance3D.new()
		var sail_box: BoxMesh = BoxMesh.new()
		sail_box.size = Vector3(0.62, 2.2, 0.03)
		sail.mesh = sail_box
		sail.position = Vector3(0.36, 1.75, 0.03)
		sail.material_override = cloth_mat
		sail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		arm.add_child(sail)


func _build_collision() -> void:
	collision_layer = 1
	collision_mask = 0
	var col: CollisionShape3D = CollisionShape3D.new()
	var cyl: CylinderShape3D = CylinderShape3D.new()
	cyl.radius = footprint_radius
	cyl.height = 4.6
	col.shape = cyl
	col.position.y = 2.3
	add_child(col)


func _process(delta: float) -> void:
	if _dead:
		return

	if _dmg_popup_cd > 0.0:
		_dmg_popup_cd = maxf(0.0, _dmg_popup_cd - delta)

	if _hit_flash_timer > 0.0 and _visual_root != null:
		_hit_flash_timer = maxf(0.0, _hit_flash_timer - delta)
		var base_sy: float = 1.0 if is_constructed else lerpf(0.22, 0.98, build_progress)
		var pulse: float = (_hit_flash_timer / 0.10) * 0.025
		_visual_root.scale = Vector3(1.0 + pulse, base_sy * (1.0 - pulse), 1.0 + pulse)
	elif _visual_root != null and is_constructed and _visual_root.scale != Vector3.ONE:
		_visual_root.scale = _visual_root.scale.lerp(Vector3.ONE, minf(1.0, 18.0 * delta))

	if _hp_root != null and not fog_hidden:
		var show_hp: bool = _is_selected or hp < max_hp or not is_constructed
		_hp_root.visible = show_hp
		if show_hp:
			var cam: Camera3D = get_viewport().get_camera_3d()
			if cam != null:
				_hp_root.global_basis = cam.global_basis

	if _rally_marker != null and _rally_marker.visible:
		_rally_marker.global_position = rally_point + Vector3(0.0, 0.65, 0.0)

	if not is_constructed:
		return

	if _sails_root != null:
		_sails_root.rotation.z += delta * 0.85
	if _warm_light != null and _warm_light.visible and _warm_light_base > 0.0:
		var ft: float = Time.get_ticks_msec() * 0.0075 + _flicker_seed
		_warm_light.light_energy = _warm_light_base * (0.91 + 0.09 * sin(ft) + 0.05 * cos(ft * 2.37))

	# Produção de unidades na fila
	if production_queue.size() > 0 and _game_manager != null:
		var u_type: String = production_queue[0]
		if current_produce_time <= 0.0:
			current_produce_time = _game_manager.get_unit_train_time(u_type, team)
		if production_timer < current_produce_time:
			production_timer += delta
		if production_timer >= current_produce_time:
			var pop_cost: int = _game_manager.get_unit_pop_cost(u_type)
			if _game_manager.has_pop_space(team, pop_cost):
				production_queue.pop_front()
				production_timer = 0.0
				if production_queue.size() > 0:
					current_produce_time = _game_manager.get_unit_train_time(production_queue[0], team)
				else:
					current_produce_time = 0.0
				_spawn_trained_unit(u_type)

	# Defesa automática (Torres, Salão Real e Castelo)
	if attack_damage > 0.0 and attack_range > 0.0:
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			var enemy: Node3D = _find_nearest_enemy()
			if enemy != null:
				var cd_use: float = attack_cooldown
				if team == 0 and _game_manager != null and float(_game_manager.get("defense_bell_active")) > 0.0:
					cd_use *= 0.65
				_attack_timer = cd_use
				_fire_volley(enemy)
			else:
				_attack_timer = 0.35


func is_production_blocked() -> bool:
	if production_queue.is_empty() or _game_manager == null:
		return false
	return production_timer >= current_produce_time and not _game_manager.has_pop_space(team, _game_manager.get_unit_pop_cost(production_queue[0]))


func _spawn_trained_unit(u_type: String) -> void:
	if _game_manager == null:
		return
	var dir_to_rally: Vector3 = (rally_point - global_position)
	dir_to_rally.y = 0.0
	if dir_to_rally.length_squared() < 0.01:
		dir_to_rally = Vector3(1.0, 0.0, -1.0)
	dir_to_rally = dir_to_rally.normalized()
	var spawn_pos: Vector3 = global_position + dir_to_rally * (footprint_radius + 1.45)
	var unit: RTSUnit = _game_manager.spawn_unit(u_type, spawn_pos, team)
	if unit == null:
		return
	if _game_manager.has_method("on_unit_trained"):
		_game_manager.on_unit_trained(unit, self)
	# Camponês com ponto de reunião em um recurso vai direto coletar
	if u_type == "worker" and has_custom_rally:
		var res: RTSResourceNode = _game_manager.find_resource_near(rally_point, 3.5, team)
		if res != null:
			unit.command_gather(res)
			return
	unit.command_move(rally_point)


func _find_nearest_enemy() -> Node3D:
	if _game_manager == null:
		return null
	var best: Node3D = null
	var best_dist: float = attack_range
	for u in _game_manager.query_units(global_position, attack_range):
		if not is_instance_valid(u) or u.is_queued_for_deletion() or u._dead:
			continue
		if u.team == team or u.hp <= 0.0:
			continue
		if team == 0 and u.fog_hidden:
			continue
		var d: float = global_position.distance_to(u.global_position)
		if d <= best_dist:
			best_dist = d
			best = u
	return best


func _fire_volley(target: Variant) -> void:
	if _game_manager == null or target == null or not is_instance_valid(target):
		return
	var top_y: float = 6.2 if building_type == "tower" else (7.5 if building_type == "castle" else 5.0)
	if _game_manager.sfx != null and not fog_hidden:
		_game_manager.sfx.play_arrow_shoot(global_position + Vector3(0.0, top_y, 0.0))
	for i in range(arrows_per_volley):
		var off: Vector3 = Vector3.ZERO
		if arrows_per_volley > 1:
			var ang: float = TAU * float(i) / float(arrows_per_volley)
			off = Vector3(cos(ang), 0.0, sin(ang)) * footprint_radius * 0.6
		_game_manager.spawn_projectile(global_position + off + Vector3(0.0, top_y, 0.0), target, attack_damage, self, team)


func accepts_resource(r_type: String) -> bool:
	return is_constructed and r_type in drop_types


func can_train(unit_type: String) -> bool:
	return is_constructed and not _dead and unit_type in trainable


func queue_unit(unit_type: String) -> bool:
	if not can_train(unit_type) or production_queue.size() >= 5 or _game_manager == null:
		return false
	if not _game_manager.spend_cost(team, RTSUnit.get_cost(unit_type)):
		return false
	production_queue.append(unit_type)
	if production_queue.size() == 1:
		production_timer = 0.0
		current_produce_time = _game_manager.get_unit_train_time(unit_type, team)
	if team == 0 and _game_manager.sfx != null:
		_game_manager.sfx.play_train_queue()
	return true


func apply_kingdom_modifiers() -> void:
	if team != 0 or _game_manager == null or not ("player_mods" in _game_manager):
		return
	var mods: Dictionary = _game_manager.get("player_mods")
	var prev_max: float = maxf(1.0, max_hp)
	max_hp = roundf(_base_max_hp * float(mods.get("building_hp_mult", 1.0)))
	if max_hp > prev_max:
		hp = minf(max_hp, hp + (max_hp - prev_max))
	if _base_attack_damage > 0.0:
		attack_damage = _base_attack_damage * float(mods.get("ranged_dmg_mult", 1.0))
		attack_range = _base_attack_range + float(mods.get("ranged_range_bonus", 0.0))
		arrows_per_volley = _base_arrows + int(mods.get("extra_arrows", 0))
	_update_hp_bar()


func cancel_last_production() -> void:
	if production_queue.is_empty() or _game_manager == null:
		return
	var removed: String = production_queue.pop_back()
	_game_manager.refund_cost(team, RTSUnit.get_cost(removed))
	if production_queue.is_empty():
		production_timer = 0.0
		current_produce_time = 0.0
	if team == 0 and _game_manager.sfx != null:
		_game_manager.sfx.play_train_cancel()


func get_production_progress() -> float:
	if production_queue.is_empty() or current_produce_time <= 0.0:
		return 0.0
	return clampf(production_timer / current_produce_time, 0.0, 1.0)


func advance_construction(delta_time: float) -> void:
	if is_constructed or _dead:
		return
	var speed_m: float = 1.0
	if team == 0 and _game_manager != null and "player_mods" in _game_manager:
		speed_m = float((_game_manager.get("player_mods") as Dictionary).get("build_speed_mult", 1.0))
	var step: float = (delta_time * speed_m) / maxf(1.0, build_time)
	build_progress = minf(1.0, build_progress + step)
	hp = minf(max_hp, hp + max_hp * 0.85 * step)
	_update_construction_visuals()
	_update_hp_bar()

	if build_progress >= 1.0:
		is_constructed = true
		hp = max_hp
		_update_construction_visuals()
		_update_hp_bar()
		if _game_manager != null and _game_manager.vfx != null and not fog_hidden:
			_game_manager.vfx.spawn_dust_burst(global_position, footprint_radius)
		if _game_manager != null and _game_manager.has_method("on_building_completed"):
			_game_manager.on_building_completed(self)


func repair(delta_time: float) -> void:
	if not is_constructed or hp >= max_hp or _dead:
		return
	var speed_m: float = 1.0
	if team == 0 and _game_manager != null and "player_mods" in _game_manager:
		speed_m = float((_game_manager.get("player_mods") as Dictionary).get("build_speed_mult", 1.0))
	hp = minf(max_hp, hp + 35.0 * speed_m * delta_time)
	_update_hp_bar()


func _update_construction_visuals() -> void:
	if _visual_root != null:
		var sy: float = 1.0 if is_constructed else lerpf(0.22, 0.98, build_progress)
		_visual_root.scale = Vector3(1.0, sy, 1.0)
	if _scaffolding_root != null:
		_scaffolding_root.visible = not is_constructed
	if _warm_light != null:
		_warm_light.visible = is_constructed
	for dv in _detail_vfx:
		if is_instance_valid(dv):
			dv.visible = is_constructed


func set_rally_point(world_pos: Vector3) -> void:
	rally_point = Vector3(world_pos.x, 0.0, world_pos.z)
	has_custom_rally = true


func set_selected(selected: bool) -> void:
	_is_selected = selected
	if _selection_ring != null:
		_selection_ring.visible = selected
	if _rally_marker != null:
		_rally_marker.visible = selected and team == 0 and not trainable.is_empty()


func set_fog_hidden(hidden: bool) -> void:
	if hidden == fog_hidden:
		return
	fog_hidden = hidden
	visible = not hidden
	if not _dead:
		collision_layer = 0 if hidden else 1


func get_display_name() -> String:
	var cfg: Dictionary = STATS.get(building_type, STATS["house"])
	return String(cfg["name"])


func get_description() -> String:
	var cfg: Dictionary = STATS.get(building_type, STATS["house"])
	return String(cfg.get("desc", ""))


func take_damage(amount: float, attacker: Variant = null, _ranged: bool = false) -> void:
	if _dead:
		return
	var mitigated: float = maxf(1.0, amount - float(armor) * 0.5)
	hp = maxf(0.0, hp - mitigated)
	_update_hp_bar()
	_hit_flash_timer = 0.10

	if _game_manager != null and not fog_hidden and _dmg_popup_cd <= 0.0 and DisplayServer.get_name() != "headless":
		_dmg_popup_cd = 0.45
		var siege_hit: bool = mitigated >= 35.0
		var col: Color = Color(1.0, 0.82, 0.28) if siege_hit else Color(1.0, 0.48, 0.36)
		_game_manager.spawn_floating_text(global_position + Vector3(0.0, 2.8, 0.0), "-%d" % int(round(mitigated)), col)

	if _game_manager != null and _game_manager.has_method("on_entity_damaged"):
		_game_manager.on_entity_damaged(self, attacker)

	if hp <= 0.0:
		_die()


func _update_hp_bar() -> void:
	if _hp_fill == null:
		return
	var ratio: float = clampf(hp / maxf(1.0, max_hp), 0.0, 1.0)
	var inner_w: float = _hp_width - 0.1
	_hp_fill.scale.x = maxf(0.001, ratio)
	_hp_fill.position.x = -inner_w * 0.5 * (1.0 - ratio)


## Remove o prédio sem contá-lo como destruído em combate (ex.: fazenda que virou campo).
func remove_silently() -> void:
	if _dead:
		return
	_dead = true
	collision_layer = 0
	queue_free()


func _die() -> void:
	if _dead:
		return
	_dead = true
	collision_layer = 0
	production_queue.clear()
	if _selection_ring != null:
		_selection_ring.visible = false
	if _rally_marker != null:
		_rally_marker.visible = false
	if _hp_root != null:
		_hp_root.visible = false
	if _game_manager != null and _game_manager.has_method("on_building_destroyed"):
		_game_manager.on_building_destroyed(self)
	if _game_manager != null and _game_manager.sfx != null and not fog_hidden:
		_game_manager.sfx.play_building_collapse(global_position)
	if _game_manager != null and _game_manager.vfx != null and not fog_hidden:
		_game_manager.vfx.spawn_dust_burst(global_position, footprint_radius * 1.25)
	if _visual_root != null and is_inside_tree() and not fog_hidden:
		var tw: Tween = create_tween()
		tw.set_parallel(true)
		tw.tween_property(_visual_root, "position:y", -3.2, 1.3).set_ease(Tween.EASE_IN)
		tw.tween_property(_visual_root, "rotation:z", 0.12, 1.3)
		tw.chain().tween_callback(queue_free)
	else:
		queue_free()
