extends CharacterBody3D
class_name RTSUnit

## Unidade controlável de RTS (Camponês, Batedor, Espadachim, Lanceiro, Arqueiro, Paladino Real e Aríete).

enum State {
	IDLE,
	MOVING,
	ATTACK_MOVING,
	GATHERING,
	RETURNING_RESOURCE,
	BUILDING,
	CHASING,
	ATTACKING,
}

## Custos em comida/madeira/ouro/pedra. "building_mult" reduz o dano contra prédios,
## "bonus" soma dano contra tipos específicos, "ranged_resist" reduz dano de flechas (aríete).
const STATS: Dictionary = {
	"worker": {
		"name": "Camponês",
		"cost": {"food": 50},
		"hp": 75.0, "armor": 0, "speed": 3.9, "damage": 5.0, "range": 1.9, "cd": 1.3,
		"pop": 1, "train_time": 10.0, "radius": 0.48, "sight": 10.0, "building_mult": 0.4,
		"model": "res://assets/models/unit_worker.glb", "hp_height": 2.35,
		"desc": "Coleta comida, madeira, ouro e pedra. Constrói e repara prédios.",
	},
	"scout": {
		"name": "Batedor",
		"cost": {"food": 70, "gold": 10},
		"hp": 110.0, "armor": 1, "speed": 5.8, "damage": 7.0, "range": 1.9, "cd": 1.15,
		"pop": 1, "train_time": 11.0, "radius": 0.48, "sight": 22.0, "building_mult": 0.3,
		"model": "res://assets/models/unit_scout.glb", "hp_height": 2.35,
		"desc": "Muito rápido e com grande visão. Ideal para explorar a névoa e caçar camponeses.",
	},
	"soldier": {
		"name": "Espadachim",
		"cost": {"food": 60, "gold": 20},
		"hp": 165.0, "armor": 2, "speed": 3.7, "damage": 16.0, "range": 2.3, "cd": 1.1,
		"pop": 1, "train_time": 12.0, "radius": 0.52, "sight": 11.0, "building_mult": 0.5,
		"model": "res://assets/models/unit_soldier.glb", "hp_height": 2.50,
		"desc": "Infantaria resistente e versátil.",
	},
	"spearman": {
		"name": "Lanceiro",
		"cost": {"food": 35, "wood": 25},
		"hp": 120.0, "armor": 1, "speed": 3.9, "damage": 9.0, "range": 2.8, "cd": 1.15,
		"pop": 1, "train_time": 10.0, "radius": 0.5, "sight": 11.0, "building_mult": 0.45,
		"bonus": {"knight": 22.0, "scout": 16.0},
		"model": "res://assets/models/unit_spearman.glb", "hp_height": 2.50,
		"desc": "Barato. Bônus de dano contra Paladinos e Batedores.",
	},
	"archer": {
		"name": "Arqueiro",
		"cost": {"wood": 25, "gold": 45},
		"hp": 95.0, "armor": 0, "speed": 4.0, "damage": 13.0, "range": 14.0, "cd": 1.4,
		"pop": 1, "train_time": 12.0, "radius": 0.48, "sight": 15.0, "building_mult": 0.25,
		"ranged": true, "bonus": {"spearman": 3.0},
		"model": "res://assets/models/unit_archer.glb", "hp_height": 2.45,
		"desc": "Ataque à distância. Fraco contra prédios e cavalaria pesada.",
	},
	"knight": {
		"name": "Paladino Real",
		"cost": {"food": 60, "gold": 85},
		"hp": 300.0, "armor": 4, "speed": 4.4, "damage": 26.0, "range": 2.5, "cd": 1.15,
		"pop": 2, "train_time": 18.0, "radius": 0.62, "sight": 12.0, "building_mult": 0.6,
		"bonus": {"archer": 8.0},
		"model": "res://assets/models/unit_knight.glb", "hp_height": 2.95,
		"desc": "Elite treinada no Castelo. Forte contra arqueiros; vulnerável a lanceiros.",
	},
	"ram": {
		"name": "Aríete",
		"cost": {"wood": 160, "gold": 75},
		"hp": 420.0, "armor": 6, "speed": 2.5, "damage": 70.0, "range": 2.6, "cd": 3.0,
		"pop": 3, "train_time": 22.0, "radius": 1.15, "sight": 8.0, "building_mult": 1.0,
		"siege": true, "ranged_resist": 0.25,
		"model": "res://assets/models/unit_ram.glb", "hp_height": 3.0,
		"desc": "Cerco: só ataca prédios, causando dano enorme. Resiste a flechas.",
	},
	# Só aparece nas ondas tardias dos covis (não é treinável pelo jogador)
	"captain": {
		"name": "Capitão do Corvo",
		"cost": {},
		"hp": 950.0, "armor": 6, "speed": 4.1, "damage": 38.0, "range": 2.7, "cd": 1.2,
		"pop": 2, "train_time": 1.0, "radius": 0.76, "sight": 13.0, "building_mult": 0.8,
		"bonus": {"archer": 10.0}, "scale": 1.22, "enemy_only": true,
		"model": "res://assets/models/unit_knight.glb", "hp_height": 3.6,
		"desc": "Elite das ondas tardias do Barão: muita vida e dano.",
	},
}

const BRIDGES: Array[Vector3] = [
	Vector3(-66.0, 0.0, -66.0),
	Vector3(-22.0, 0.0, -22.0),
	Vector3(22.0, 0.0, 22.0),
	Vector3(66.0, 0.0, 66.0),
]

const RIVER_BANK_DIST: float = 5.75
const BRIDGE_HALF_WIDTH: float = 3.32
const BRIDGE_HALF_LEN: float = 7.65
const CARRY_CAPACITY: int = 10
const UNIT_BOUND: float = 96.0

var unit_type: String = "soldier"
var team: int = 0
var max_hp: float = 100.0
var hp: float = 100.0
var armor: int = 0
var move_speed: float = 3.7
var attack_damage: float = 12.0
var attack_range: float = 2.2
var attack_cooldown: float = 1.0
var pop_cost: int = 1
var body_radius: float = 0.5
var sight_range: float = 10.0
var is_ranged: bool = false
var is_siege: bool = false
var building_mult: float = 1.0
var ranged_resist: float = 1.0
var damage_bonus: Dictionary = {}

var state: int = State.IDLE
var move_target: Vector3 = Vector3.ZERO
var target_enemy: Variant = null
var target_resource: Variant = null
var target_building: Variant = null
var fog_hidden: bool = false

var carrying_type: String = ""
var carrying_amount: int = 0
var _last_resource_pos: Vector3 = Vector3.ZERO
var _last_resource_type: String = "gold"
var _gather_progress: float = 0.0
var _target_depot: Variant = null

var _attack_timer: float = 0.0
var _scan_timer: float = 0.0
var _anim_phase: float = 0.0
var _swing_timer: float = 0.0
var _is_selected: bool = false
var _dead: bool = false
var _stuck_timer: float = 0.0
var _stuck_count: int = 0

var _path: PackedVector3Array = PackedVector3Array()
var _path_idx: int = 0
var _path_goal: Vector3 = Vector3(INF, 0.0, INF)
var _repath_cd: float = 0.0

static var _team_mat_cache: Dictionary = {}

var _game_manager: Node = null
var _visual_root: Node3D
var _anim_player: AnimationPlayer = null
var _current_anim: String = ""
var _attack_anim_timer: float = 0.0
var _death_timer: float = 0.0
var _hammer_sfx_cd: float = 0.0
var _selection_ring: MeshInstance3D
var _selection_mat: StandardMaterial3D
var _team_ring: MeshInstance3D
var _carry_meshes: Dictionary = {}
var _hp_root: Node3D
var _hp_fill: MeshInstance3D
var _vet_label: Label3D = null

var kills: int = 0
var vet_rank: int = 0
var hold_position: bool = false
var _war_cry_timer: float = 0.0
var _smooth_vel: Vector3 = Vector3.ZERO
var _is_walking_anim: bool = false
var _pending_hit_timer: float = -1.0
var _pending_hit_target: Variant = null
var _pending_hit_dmg: float = 0.0
var _hit_flash_timer: float = 0.0
var _dmg_popup_cd: float = 0.0
var _last_ring_mode: int = -1
var _last_attacker: Variant = null
var _last_attacker_team: int = -1

var _base_max_hp: float = 100.0
var _base_armor: int = 0
var _base_speed: float = 3.7
var _base_damage: float = 12.0
var _base_range: float = 2.2
var _base_cd: float = 1.0


func setup(u_type: String, p_team: int, gm: Node) -> void:
	unit_type = u_type
	team = p_team
	_game_manager = gm

	var cfg: Dictionary = STATS.get(unit_type, STATS["soldier"])
	_base_max_hp = float(cfg["hp"])
	_base_armor = int(cfg["armor"])
	_base_speed = float(cfg["speed"])
	_base_damage = float(cfg["damage"])
	_base_range = float(cfg["range"])
	_base_cd = float(cfg["cd"])
	max_hp = _base_max_hp
	hp = max_hp
	armor = _base_armor
	move_speed = _base_speed
	attack_damage = _base_damage
	attack_range = _base_range
	attack_cooldown = _base_cd
	pop_cost = int(cfg["pop"])
	body_radius = float(cfg["radius"])
	sight_range = float(cfg.get("sight", 10.0))
	is_ranged = bool(cfg.get("ranged", false))
	is_siege = bool(cfg.get("siege", false))
	building_mult = float(cfg.get("building_mult", 1.0))
	ranged_resist = float(cfg.get("ranged_resist", 1.0))
	damage_bonus = cfg.get("bonus", {})
	_scan_timer = randf() * 0.35

	add_to_group("rts_units")
	_build_visuals(cfg)
	_build_collision()
	apply_kingdom_modifiers()
	_update_hp_bar()


static func get_cost(u_type: String) -> Dictionary:
	var cfg: Dictionary = STATS.get(u_type, {})
	return cfg.get("cost", {})


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
			_apply_team_materials(inst)
			_setup_animations(inst)
			var model_scale: float = float(cfg.get("scale", 1.0))
			if absf(model_scale - 1.0) > 0.001:
				inst.scale = Vector3.ONE * model_scale
	else:
		var fallback: MeshInstance3D = MeshInstance3D.new()
		var cap: CapsuleMesh = CapsuleMesh.new()
		cap.radius = body_radius
		cap.height = 1.6
		fallback.mesh = cap
		fallback.position.y = 0.8
		_visual_root.add_child(fallback)

	var team_col: Color = team_color(team)

	# Carga transportada pelo camponês (comida, madeira, ouro, pedra)
	if unit_type == "worker":
		_carry_meshes["gold"] = _make_carry_box(Vector3(0.30, 0.24, 0.30), Color(0.98, 0.78, 0.16), 0.88, 0.24)
		_carry_meshes["stone"] = _make_carry_box(Vector3(0.34, 0.26, 0.30), Color(0.62, 0.62, 0.60), 0.0, 0.85)
		_carry_meshes["food"] = _make_carry_box(Vector3(0.34, 0.22, 0.30), Color(0.78, 0.22, 0.18), 0.0, 0.6)
		var wood_mesh: MeshInstance3D = MeshInstance3D.new()
		var wcyl: CylinderMesh = CylinderMesh.new()
		wcyl.top_radius = 0.11
		wcyl.bottom_radius = 0.11
		wcyl.height = 0.55
		wood_mesh.mesh = wcyl
		wood_mesh.rotation.z = PI * 0.5
		wood_mesh.position = Vector3(0.0, 0.92, -0.34)
		var wmat: StandardMaterial3D = StandardMaterial3D.new()
		wmat.albedo_color = Color(0.46, 0.27, 0.12)
		wmat.roughness = 0.78
		wood_mesh.material_override = wmat
		wood_mesh.visible = false
		_visual_root.add_child(wood_mesh)
		_carry_meshes["wood"] = wood_mesh

	# Anel sutil do time no solo
	_team_ring = MeshInstance3D.new()
	var t_torus: TorusMesh = TorusMesh.new()
	t_torus.inner_radius = body_radius * 1.18
	t_torus.outer_radius = body_radius * 1.36
	t_torus.rings = 24
	t_torus.ring_segments = 6
	_team_ring.mesh = t_torus
	_team_ring.position.y = 0.04
	_team_ring.scale = Vector3(1.0, 0.10, 1.0)
	var t_mat: StandardMaterial3D = StandardMaterial3D.new()
	t_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	t_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	t_mat.albedo_color = Color(team_col.r, team_col.g, team_col.b, 0.45)
	_team_ring.material_override = t_mat
	_team_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_team_ring)

	# Anel de seleção brilhante
	_selection_ring = MeshInstance3D.new()
	var s_torus: TorusMesh = TorusMesh.new()
	s_torus.inner_radius = body_radius * 1.48
	s_torus.outer_radius = body_radius * 1.78
	s_torus.rings = 28
	s_torus.ring_segments = 6
	_selection_ring.mesh = s_torus
	_selection_ring.position.y = 0.06
	_selection_ring.scale = Vector3(1.0, 0.12, 1.0)
	_selection_mat = StandardMaterial3D.new()
	_selection_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_selection_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_selection_mat.albedo_color = Color(0.28, 0.98, 0.45, 0.88) if team == 0 else Color(1.0, 0.35, 0.25, 0.88)
	_selection_ring.material_override = _selection_mat
	_selection_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_selection_ring.visible = false
	add_child(_selection_ring)

	# Barra de vida 3D (estrela de veterania é criada sob demanda ao evoluir)
	_hp_root = Node3D.new()
	_hp_root.position = Vector3(0.0, float(cfg["hp_height"]), 0.0)
	add_child(_hp_root)

	var bg: MeshInstance3D = MeshInstance3D.new()
	var bg_q: QuadMesh = QuadMesh.new()
	bg_q.size = Vector2(1.15, 0.18)
	bg.mesh = bg_q
	var bg_mat: StandardMaterial3D = StandardMaterial3D.new()
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.albedo_color = Color(0.06, 0.08, 0.10, 0.9)
	bg.material_override = bg_mat
	bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hp_root.add_child(bg)

	_hp_fill = MeshInstance3D.new()
	var fq: QuadMesh = QuadMesh.new()
	fq.size = Vector2(1.07, 0.11)
	_hp_fill.mesh = fq
	_hp_fill.position = Vector3(0.0, 0.0, 0.012)
	var fmat: StandardMaterial3D = StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.albedo_color = Color(0.24, 0.85, 1.0) if team == 0 else Color(0.95, 0.28, 0.25)
	_hp_fill.material_override = fmat
	_hp_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hp_root.add_child(_hp_fill)


func _make_carry_box(size: Vector3, col: Color, metallic: float, rough: float) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = Vector3(0.0, 0.92, -0.34)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = col
	mat.metallic = metallic
	mat.roughness = rough
	mi.material_override = mat
	mi.visible = false
	_visual_root.add_child(mi)
	return mi


static func team_color(t: int) -> Color:
	return Color(0.18, 0.56, 1.0) if t == 0 else Color(0.95, 0.24, 0.20)


func _apply_team_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh != null:
			var surf_count: int = mi.mesh.get_surface_count()
			for i in range(surf_count):
				var base_mat: Material = mi.get_active_material(i)
				if base_mat == null:
					continue
				var mname: String = base_mat.resource_name
				var prefix: String = ""
				if mname.begins_with("Mat_TeamPrimary"):
					prefix = "Mat_TeamPrimary"
				elif mname.begins_with("Mat_TeamCape"):
					prefix = "Mat_TeamCape"
				elif mname.begins_with("Mat_TeamAccent"):
					prefix = "Mat_TeamAccent"
				if prefix != "":
					var tinted: StandardMaterial3D = _get_or_create_team_material(base_mat, prefix)
					if tinted != null:
						mi.set_surface_override_material(i, tinted)
	for child in node.get_children():
		_apply_team_materials(child)


func _get_or_create_team_material(base_mat: Material, key_prefix: String) -> StandardMaterial3D:
	var cache_key: String = "%d_%s" % [team, key_prefix]
	if _team_mat_cache.has(cache_key):
		var cached: StandardMaterial3D = _team_mat_cache[cache_key] as StandardMaterial3D
		if is_instance_valid(cached):
			return cached
	var std: StandardMaterial3D = base_mat as StandardMaterial3D
	if std == null:
		return null
	var dup: StandardMaterial3D = std.duplicate() as StandardMaterial3D
	if key_prefix == "Mat_TeamPrimary":
		dup.albedo_color = Color(0.14, 0.46, 0.98) if team == 0 else Color(0.90, 0.16, 0.15)
	elif key_prefix == "Mat_TeamCape":
		dup.albedo_color = Color(0.10, 0.32, 0.80) if team == 0 else Color(0.70, 0.11, 0.12)
	elif key_prefix == "Mat_TeamAccent":
		var ac_col: Color = Color(0.26, 0.66, 1.0) if team == 0 else Color(1.0, 0.28, 0.20)
		dup.albedo_color = ac_col
		dup.emission_enabled = true
		dup.emission = Color(0.16, 0.45, 0.95) if team == 0 else Color(0.95, 0.20, 0.15)
		dup.emission_energy_multiplier = 0.22
	dup.resource_name = cache_key
	_team_mat_cache[cache_key] = dup
	return dup


func _setup_animations(inst: Node) -> void:
	_anim_player = _find_animation_player(inst)
	if _anim_player == null:
		return
	for loop_clip in ["Idle", "Walk", "Gather"]:
		if _anim_player.has_animation(loop_clip):
			_anim_player.get_animation(loop_clip).loop_mode = Animation.LOOP_LINEAR
	for once_clip in ["Attack", "Death"]:
		if _anim_player.has_animation(once_clip):
			_anim_player.get_animation(once_clip).loop_mode = Animation.LOOP_NONE
	if _anim_player.has_animation("Idle"):
		_play_anim("Idle", 0.0, 1.0, true)
		var idle_len: float = _anim_player.get_animation("Idle").length
		if idle_len > 0.05:
			_anim_player.seek(randf() * idle_len, true)


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found: AnimationPlayer = _find_animation_player(child)
		if found != null:
			return found
	return null


func _play_anim(anim_name: String, blend: float = 0.16, speed: float = 1.0, force_restart: bool = false) -> void:
	if _anim_player == null or not _anim_player.has_animation(anim_name):
		return
	if not force_restart and _current_anim == anim_name and _anim_player.is_playing():
		_anim_player.speed_scale = speed
		return
	_current_anim = anim_name
	_anim_player.speed_scale = speed
	_anim_player.play(anim_name, blend)


func _build_collision() -> void:
	collision_layer = 1
	collision_mask = 0
	var col: CollisionShape3D = CollisionShape3D.new()
	var cap: CapsuleShape3D = CapsuleShape3D.new()
	cap.radius = body_radius
	cap.height = maxf(1.75, body_radius * 2.2)
	col.shape = cap
	col.position.y = cap.height * 0.5
	add_child(col)


func _process(delta: float) -> void:
	if _dead:
		if _death_timer > 0.0:
			_death_timer -= delta
			if _death_timer < 0.30 and _visual_root != null:
				_visual_root.position.y = lerpf(_visual_root.position.y, -0.25, 8.0 * delta)
			if _death_timer <= 0.0:
				queue_free()
		return

	if fog_hidden:
		return

	if _hp_root != null:
		var show_hp: bool = _is_selected or hp < max_hp
		_hp_root.visible = show_hp
		if _vet_label != null:
			_vet_label.visible = vet_rank > 0 and show_hp
		if show_hp:
			var cam: Camera3D = get_viewport().get_camera_3d()
			if cam != null:
				_hp_root.global_basis = cam.global_basis

	if _selection_mat != null and _selection_ring != null and _selection_ring.visible:
		var mode: int = 2 if _war_cry_timer > 0.0 else (1 if (hold_position and team == 0) else 0)
		if mode == 2:
			_last_ring_mode = 2
			var p_col: float = 0.72 + 0.28 * sin(Time.get_ticks_msec() * 0.018)
			_selection_mat.albedo_color = Color(1.0, 0.84 * p_col, 0.22, 0.95)
		elif mode != _last_ring_mode:
			_last_ring_mode = mode
			if mode == 1:
				_selection_mat.albedo_color = Color(0.32, 0.82, 1.0, 0.92)
			else:
				_selection_mat.albedo_color = Color(0.28, 0.98, 0.45, 0.88) if team == 0 else Color(1.0, 0.35, 0.25, 0.88)

	if _visual_root != null:
		if _hit_flash_timer > 0.0:
			_hit_flash_timer = maxf(0.0, _hit_flash_timer - delta)
			var kt: float = _hit_flash_timer / 0.12
			_visual_root.scale = Vector3(1.0 + 0.09 * kt, 1.0 - 0.08 * kt, 1.0 + 0.09 * kt)
		elif _visual_root.scale != Vector3.ONE:
			_visual_root.scale = _visual_root.scale.lerp(Vector3.ONE, minf(1.0, 18.0 * delta))

	if unit_type == "worker":
		for r_type in _carry_meshes.keys():
			var cm: MeshInstance3D = _carry_meshes[r_type]
			cm.visible = carrying_amount > 0 and carrying_type == String(r_type)

	# Máquina de estados de animação com histerese (sem piscar entre Walk e Idle)
	var spd_now: float = Vector2(velocity.x, velocity.z).length()
	if _is_walking_anim:
		if spd_now < 0.25:
			_is_walking_anim = false
	elif spd_now > 0.60:
		_is_walking_anim = true

	if _anim_player != null:
		if _attack_anim_timer > 0.0:
			_attack_anim_timer = maxf(0.0, _attack_anim_timer - delta)
		elif _is_walking_anim:
			_play_anim("Walk", 0.16, clampf(spd_now / 4.1, 0.72, 1.32))
		elif unit_type == "worker" and (state == State.GATHERING or state == State.BUILDING):
			var gather_clip: String = "Gather" if _anim_player.has_animation("Gather") else "Attack"
			_play_anim(gather_clip, 0.14, 1.15)
		else:
			_play_anim("Idle", 0.20, 1.0)
	elif _visual_root != null:
		if _swing_timer > 0.0:
			_swing_timer = maxf(0.0, _swing_timer - delta)
			var swing_angle: float = sin((_swing_timer / 0.25) * PI) * (0.18 if is_siege else 0.42)
			_visual_root.rotation.x = -swing_angle
		elif _is_walking_anim:
			_anim_phase += delta * (4.5 if is_siege else 8.0)
			_visual_root.position.y = absf(sin(_anim_phase)) * (0.03 if is_siege else 0.08)
			_visual_root.rotation.x = lerpf(_visual_root.rotation.x, -0.03 if is_siege else -0.09, 10.0 * delta)
		elif absf(_visual_root.position.y) > 0.001 or absf(_visual_root.rotation.x) > 0.001:
			_visual_root.position.y = lerpf(_visual_root.position.y, 0.0, 12.0 * delta)
			_visual_root.rotation.x = lerpf(_visual_root.rotation.x, 0.0, 12.0 * delta)


func _physics_process(delta: float) -> void:
	if _dead:
		return

	_attack_timer = maxf(0.0, _attack_timer - delta)
	_scan_timer -= delta
	if _dmg_popup_cd > 0.0:
		_dmg_popup_cd = maxf(0.0, _dmg_popup_cd - delta)
	if _war_cry_timer > 0.0:
		_war_cry_timer = maxf(0.0, _war_cry_timer - delta)
		if _war_cry_timer <= 0.0:
			apply_kingdom_modifiers()
	if _pending_hit_timer > 0.0:
		_pending_hit_timer -= delta
		if _pending_hit_timer <= 0.0:
			_execute_pending_hit()

	match state:
		State.IDLE:
			_smooth_vel = _smooth_vel.move_toward(Vector3.ZERO, 22.0 * delta)
			velocity = Vector3.ZERO
			if _scan_timer <= 0.0:
				_scan_timer = 0.35 + randf() * 0.1
				if _can_auto_acquire():
					var search_r: float = attack_range + 1.2 if hold_position else _aggro_range()
					var enemy: Node3D = _find_nearest_enemy(search_r)
					if enemy != null:
						if hold_position:
							var reach_now: float = attack_range + _get_target_radius(enemy) + 0.35
							if _flat_distance(global_position, enemy.global_position) <= reach_now:
								target_enemy = enemy
								state = State.ATTACKING
						else:
							target_enemy = enemy
							state = State.CHASING

		State.MOVING:
			if _move_toward(move_target, 0.55, delta):
				_smooth_vel = Vector3.ZERO
				velocity = Vector3.ZERO
				state = State.IDLE

		State.ATTACK_MOVING:
			if _scan_timer <= 0.0:
				_scan_timer = 0.3 + randf() * 0.08
				var enemy: Node3D = _find_nearest_enemy(maxf(16.0, _aggro_range()))
				if enemy != null:
					target_enemy = enemy
					state = State.CHASING
					return
			if _stuck_count >= 2:
				var blocker: RTSBuilding = _find_blocking_enemy_building()
				if blocker != null:
					target_enemy = blocker
					_stuck_count = 0
					state = State.CHASING
					return
			if _move_toward(move_target, 0.85, delta):
				_smooth_vel = Vector3.ZERO
				velocity = Vector3.ZERO
				state = State.IDLE

		State.GATHERING:
			_process_gathering(delta)

		State.RETURNING_RESOURCE:
			_process_returning(delta)

		State.BUILDING:
			_process_building(delta)

		State.CHASING:
			_process_chasing(delta)

		State.ATTACKING:
			_process_attacking(delta)


func _can_auto_acquire() -> bool:
	return unit_type != "worker"


func _aggro_range() -> float:
	if is_siege:
		return 11.0
	if is_ranged:
		return maxf(15.0, attack_range + 1.5)
	return 13.5


func _gather_rate_mult() -> float:
	if _game_manager != null and _game_manager.has_method("get_gather_mult"):
		return float(_game_manager.get_gather_mult(team))
	return 1.0


func _process_gathering(delta: float) -> void:
	if unit_type != "worker":
		state = State.IDLE
		return
	if carrying_amount >= CARRY_CAPACITY:
		_begin_return()
		return

	if not _is_valid_resource(target_resource):
		var next_res: RTSResourceNode = _find_nearest_resource(_last_resource_type, _last_resource_pos, 45.0)
		if next_res != null:
			target_resource = next_res
			_last_resource_pos = next_res.global_position
		else:
			if carrying_amount > 0:
				_begin_return()
			else:
				state = State.IDLE
			return

	var res: RTSResourceNode = target_resource as RTSResourceNode
	_last_resource_pos = res.global_position
	_last_resource_type = res.resource_type
	if carrying_amount > 0 and carrying_type != res.resource_type:
		_begin_return()
		return
	var reach: float = res.gather_reach() + body_radius
	var dist: float = _flat_distance(global_position, res.global_position)
	if dist > reach:
		_move_toward(res.global_position, reach * 0.88, delta)
		# Recurso inacessível (ex.: árvore no miolo da floresta): troca pelo mais próximo de si
		if _stuck_count >= 3:
			var alt: RTSResourceNode = _find_nearest_resource_excluding(res.resource_type, global_position, 30.0, res)
			_stuck_count = 0
			if alt != null:
				target_resource = alt
				_clear_path()
		return

	velocity = Vector3.ZERO
	_clear_path()
	_face_point(res.global_position, delta)
	_gather_progress += res.gather_rate * _gather_rate_mult() * delta
	if _swing_timer <= 0.0:
		_swing_timer = 0.24
	if _gather_progress >= 1.0:
		var want: int = mini(int(_gather_progress), CARRY_CAPACITY - carrying_amount)
		_gather_progress -= float(want)
		var taken: int = res.harvest(want)
		if taken > 0:
			carrying_type = res.resource_type
			carrying_amount += taken
			if _game_manager != null and not fog_hidden:
				if _game_manager.sfx != null and (team == 0 or randf() < 0.4):
					_game_manager.sfx.play_harvest_resource(res.resource_type, global_position)
				if _game_manager.vfx != null and (team == 0 or randf() < 0.5):
					_game_manager.vfx.spawn_gather_chips(res.resource_type, res.global_position)
		if carrying_amount >= CARRY_CAPACITY or not _is_valid_resource(target_resource):
			_begin_return()


func _begin_return() -> void:
	_target_depot = null
	_gather_progress = 0.0
	state = State.RETURNING_RESOURCE


func _process_returning(delta: float) -> void:
	if carrying_amount <= 0:
		if _is_valid_resource(target_resource):
			state = State.GATHERING
		else:
			state = State.IDLE
		return

	if not _is_valid_depot(_target_depot):
		_target_depot = _find_nearest_drop_site(carrying_type)
	if _target_depot == null:
		state = State.IDLE
		return

	var depot: RTSBuilding = _target_depot as RTSBuilding
	var reach: float = depot.footprint_radius + 1.45 + body_radius
	var dist: float = _flat_distance(global_position, depot.global_position)
	if dist > reach:
		_move_toward(depot.global_position, reach * 0.92, delta)
		return

	velocity = Vector3.ZERO
	_clear_path()
	if _game_manager != null:
		_game_manager.add_resource(team, carrying_type, carrying_amount)
		if team == 0:
			var label_txt: String = "+%d %s" % [carrying_amount, GameManager.RES_NAMES.get(carrying_type, carrying_type)]
			var col: Color = GameManager.RES_COLORS.get(carrying_type, Color.WHITE)
			_game_manager.spawn_floating_text(global_position + Vector3(0.0, 2.2, 0.0), label_txt, col)
			if _game_manager.sfx != null:
				_game_manager.sfx.play_deposit(carrying_type, global_position)
	carrying_amount = 0
	carrying_type = ""
	_target_depot = null

	if _is_valid_resource(target_resource):
		state = State.GATHERING
	else:
		var next_res: RTSResourceNode = _find_nearest_resource(_last_resource_type, _last_resource_pos, 48.0)
		if next_res != null:
			target_resource = next_res
			_last_resource_pos = next_res.global_position
			state = State.GATHERING
		else:
			state = State.IDLE


func _process_building(delta: float) -> void:
	if unit_type != "worker":
		state = State.IDLE
		return
	if not is_instance_valid(target_building) or target_building.is_queued_for_deletion() or target_building.team != team or target_building._dead:
		target_building = null
		state = State.IDLE
		return

	var b: RTSBuilding = target_building as RTSBuilding
	if b.is_constructed and b.hp >= b.max_hp:
		_after_building_finished(b)
		return

	var reach: float = b.footprint_radius + 1.5 + body_radius
	var dist: float = _flat_distance(global_position, b.global_position)
	if dist > reach:
		_move_toward(b.global_position, reach * 0.9, delta)
		return

	velocity = Vector3.ZERO
	_clear_path()
	_face_point(b.global_position, delta)
	if _swing_timer <= 0.0:
		_swing_timer = 0.25
	_hammer_sfx_cd -= delta
	if _hammer_sfx_cd <= 0.0:
		_hammer_sfx_cd = 0.55 + randf() * 0.25
		if _game_manager != null and _game_manager.sfx != null and not fog_hidden:
			_game_manager.sfx.play_build_hammer(global_position)
	if not b.is_constructed:
		# Pode concluir a obra (e uma fazenda vira campo de cultivo); não usar 'b' depois disso.
		b.advance_construction(delta)
	else:
		b.repair(delta)


func _after_building_finished(b: RTSBuilding) -> void:
	# Comportamento de camponês experiente: procura outra obra; senão coleta ao redor de pontos de entrega.
	var next_b: RTSBuilding = _find_unfinished_building(24.0)
	if next_b != null:
		target_building = next_b
		return
	target_building = null
	var drops: Array = RTSBuilding.get_drop_types(b.building_type)
	if not drops.is_empty() and b.building_type != "town_center":
		var best: RTSResourceNode = null
		for r_type in drops:
			var cand: RTSResourceNode = _find_nearest_resource(String(r_type), b.global_position, 22.0)
			if cand != null and (best == null or _flat_distance(b.global_position, cand.global_position) < _flat_distance(b.global_position, best.global_position)):
				best = cand
		if best != null:
			command_gather(best)
			return
	state = State.IDLE


func _process_chasing(delta: float) -> void:
	if not _is_valid_enemy(target_enemy):
		target_enemy = _find_nearest_enemy(16.0)
		if target_enemy == null:
			state = State.IDLE
			return

	var reach: float = attack_range + _get_target_radius(target_enemy)
	var dist: float = _flat_distance(global_position, target_enemy.global_position)
	if dist <= reach:
		velocity = Vector3.ZERO
		_clear_path()
		state = State.ATTACKING
	else:
		_move_toward(target_enemy.global_position, reach * 0.9, delta)
		_handle_blocked_advance()


## Preso a caminho do alvo: ataca o prédio inimigo que está no caminho; se nada bloquear, desiste.
func _handle_blocked_advance() -> void:
	if _stuck_count < 2:
		return
	var blocker: RTSBuilding = _find_blocking_enemy_building()
	if blocker != null and blocker != target_enemy:
		target_enemy = blocker
		_stuck_count = 0
		_path = PackedVector3Array()
		state = State.CHASING
		return
	if _stuck_count >= 6:
		_clear_path()
		target_enemy = null
		velocity = Vector3.ZERO
		state = State.IDLE


func _find_blocking_enemy_building() -> RTSBuilding:
	if _game_manager == null:
		return null
	var best: RTSBuilding = null
	var best_d: float = body_radius + 3.5
	for b in _game_manager.buildings:
		if not _is_valid_enemy(b) or not _can_see(b):
			continue
		var d: float = _flat_distance(global_position, b.global_position) - b.footprint_radius
		if d < best_d:
			best_d = d
			best = b
	return best


func _process_attacking(delta: float) -> void:
	if not _is_valid_enemy(target_enemy):
		var search_r: float = attack_range + 1.5 if hold_position else 16.0
		target_enemy = _find_nearest_enemy(search_r)
		if target_enemy != null:
			state = State.ATTACKING if hold_position else State.CHASING
		else:
			state = State.IDLE
		return

	var reach: float = attack_range + _get_target_radius(target_enemy) + 0.45
	var dist: float = _flat_distance(global_position, target_enemy.global_position)
	if dist > reach:
		if hold_position:
			target_enemy = null
			state = State.IDLE
		else:
			state = State.CHASING
		return

	_smooth_vel = _smooth_vel.move_toward(Vector3.ZERO, 22.0 * delta)
	velocity = Vector3.ZERO
	_face_point(target_enemy.global_position, delta)

	if _attack_timer <= 0.0:
		_attack_timer = attack_cooldown
		_swing_timer = 0.24
		_play_anim("Attack", 0.08, 1.15, true)
		_attack_anim_timer = minf(attack_cooldown * 0.82, 0.72)
		_pending_hit_target = target_enemy
		_pending_hit_dmg = compute_damage_against(target_enemy)
		_pending_hit_timer = 0.14 if is_ranged else 0.18


func _execute_pending_hit() -> void:
	_pending_hit_timer = -1.0
	if _dead or not _is_valid_enemy(_pending_hit_target):
		_pending_hit_target = null
		return
	var tgt: Variant = _pending_hit_target
	var dmg: float = _pending_hit_dmg
	_pending_hit_target = null

	if is_ranged:
		if _game_manager != null:
			_game_manager.spawn_projectile(global_position + Vector3(0.0, 1.35, 0.0), tgt, dmg, self, team)
			if _game_manager.sfx != null and not fog_hidden:
				_game_manager.sfx.play_arrow_shoot(global_position)
	else:
		if tgt.has_method("take_damage"):
			tgt.take_damage(dmg, self, false)
		if _game_manager != null and not fog_hidden:
			var hit_pos: Vector3 = tgt.global_position if is_instance_valid(tgt) else global_position
			if _game_manager.sfx != null:
				_game_manager.sfx.play_melee_hit(unit_type, hit_pos)
			if _game_manager.vfx != null:
				_game_manager.vfx.spawn_hit_sparks(hit_pos)
			if (unit_type == "ram" or unit_type == "knight" or unit_type == "captain") and _game_manager.get("camera_rig") != null:
				var crig: RTSCamera = _game_manager.get("camera_rig") as RTSCamera
				if crig != null and crig.global_position.distance_to(hit_pos) < 42.0:
					crig.add_trauma(0.11 if unit_type == "ram" else 0.05)


func compute_damage_against(target: Variant) -> float:
	var dmg: float = attack_damage
	if target is RTSUnit:
		dmg += float(damage_bonus.get((target as RTSUnit).unit_type, 0.0))
	elif target is RTSBuilding:
		dmg *= building_mult
		if is_siege and team == 0 and _game_manager != null:
			var mods: Variant = _game_manager.get("player_mods")
			if mods is Dictionary:
				dmg *= float((mods as Dictionary).get("siege_dmg_mult", 1.0))
	return dmg


# ==============================================================================
# RIO, PONTES E NAVEGAÇÃO
# ==============================================================================

static func river_meander_at(x: float, z: float) -> float:
	var s: float = x + z
	return sin(s * 0.038) * 1.35 + cos(s * 0.09) * 0.45


static func river_signed_at(x: float, z: float) -> float:
	return (x - z) + river_meander_at(x, z)


static func river_distance_at(x: float, z: float) -> float:
	return absf(river_signed_at(x, z))


static func is_on_bridge_deck(x: float, z: float, margin_w: float = 0.0) -> bool:
	for b in BRIDGES:
		var along: float = ((x + z) - (b.x + b.z)) * 0.70710678
		var across: float = (x - z) * 0.70710678
		if absf(along) <= (BRIDGE_HALF_WIDTH - margin_w) and absf(across) <= BRIDGE_HALF_LEN:
			return true
	return false


static func is_in_river_water(x: float, z: float, extra_margin: float = 0.0) -> bool:
	return river_distance_at(x, z) < (RIVER_BANK_DIST + extra_margin) and not is_on_bridge_deck(x, z, 0.0)


static func get_bridge_deck_height(x: float, z: float) -> float:
	for b in BRIDGES:
		var along: float = ((x + z) - (b.x + b.z)) * 0.70710678
		var across: float = absf((x - z) * 0.70710678)
		if absf(along) <= (BRIDGE_HALF_WIDTH + 0.25) and across <= BRIDGE_HALF_LEN:
			var t: float = clampf((BRIDGE_HALF_LEN - across) / 2.0, 0.0, 1.0)
			return 0.28 * t * t * (3.0 - 2.0 * t)
	return 0.0


static func _push_point_to_bank(pt: Vector3, preferred_side: float, bank_dist: float) -> Vector3:
	var s_curr: float = river_signed_at(pt.x, pt.z)
	var side: float = (1.0 if s_curr >= 0.0 else -1.0) if absf(s_curr) >= 0.1 else preferred_side
	var target_s: float = side * bank_dist
	var diff: float = target_s - s_curr
	return Vector3(pt.x + diff * 0.5, 0.0, pt.z - diff * 0.5)


func _get_nearby_obstacles(center: Vector3, search_margin: float, skip_active_targets: bool) -> Array:
	if _game_manager == null:
		return []
	var found: Array = _game_manager.query_obstacles(center, search_margin)
	if not skip_active_targets:
		return found
	var out: Array = []
	for obs in found:
		var ref: Variant = obs.get("ref", null)
		if ref != null and (ref == target_building or ref == target_enemy or ref == target_resource or ref == _target_depot):
			continue
		out.append(obs)
	return out


func sanitize_destination(dest: Vector3) -> Vector3:
	var p: Vector3 = Vector3(clampf(dest.x, -UNIT_BOUND, UNIT_BOUND), 0.0, clampf(dest.z, -UNIT_BOUND, UNIT_BOUND))
	var cur_side: float = 1.0 if river_signed_at(global_position.x, global_position.z) >= 0.0 else -1.0

	if is_in_river_water(p.x, p.z, 0.15):
		var snapped_to_bridge: bool = false
		for b in BRIDGES:
			var along: float = ((p.x + p.z) - (b.x + b.z)) * 0.70710678
			if absf(along) <= 6.2:
				var clamped_along: float = clampf(along, -2.6, 2.6)
				var across: float = clampf((p.x - p.z) * 0.70710678, -BRIDGE_HALF_LEN + 0.35, BRIDGE_HALF_LEN - 0.35)
				p.x = b.x + (clamped_along + across) * 0.70710678
				p.z = b.z + (clamped_along - across) * 0.70710678
				snapped_to_bridge = true
				break
		if not snapped_to_bridge:
			p = _push_point_to_bank(p, cur_side, RIVER_BANK_DIST + 0.35)

	for obs in _get_nearby_obstacles(p, body_radius + 0.35, false):
		var op: Vector3 = obs["pos"]
		var min_d: float = float(obs["radius"]) + body_radius + 0.25
		var dvec: Vector2 = Vector2(p.x - op.x, p.z - op.z)
		var d: float = dvec.length()
		if d < min_d:
			var nrm: Vector2 = (dvec / d) if d > 0.001 else Vector2(global_position.x - op.x, global_position.z - op.z).normalized()
			if nrm.length_squared() < 0.01:
				nrm = Vector2(1.0, 0.0)
			p.x = op.x + nrm.x * min_d
			p.z = op.z + nrm.y * min_d

	p.x = clampf(p.x, -UNIT_BOUND, UNIT_BOUND)
	p.z = clampf(p.z, -UNIT_BOUND, UNIT_BOUND)
	if is_in_river_water(p.x, p.z, 0.10):
		p = _push_point_to_bank(p, cur_side, RIVER_BANK_DIST + 0.35)
	return p


func _clear_path() -> void:
	if not _path.is_empty():
		_path = PackedVector3Array()
	_path_idx = 0
	_path_goal = Vector3(INF, 0.0, INF)
	_stuck_count = 0


func _get_nav_target(flat_pos: Vector3, flat_dest: Vector3, delta: float) -> Vector3:
	_repath_cd -= delta
	if _game_manager == null or _game_manager.nav == null:
		return flat_dest
	var nav: NavGrid = _game_manager.nav
	var dist: float = flat_pos.distance_to(flat_dest)
	if dist < 7.0 and nav.segment_clear(flat_pos, flat_dest):
		if not _path.is_empty():
			_path = PackedVector3Array()
		return flat_dest

	var goal_moved: bool = _path_goal.distance_to(flat_dest) > maxf(2.0, dist * 0.18)
	if _path.is_empty() or (goal_moved and _repath_cd <= 0.0):
		_path = nav.find_path(flat_pos, flat_dest)
		_path_idx = 0
		_path_goal = flat_dest
		_repath_cd = 0.55 + randf() * 0.45
		if _path.is_empty():
			return flat_dest

	while _path_idx < _path.size() - 1 and flat_pos.distance_to(_path[_path_idx]) < 1.7:
		_path_idx += 1
	if _path_idx < _path.size() - 1 and nav.segment_clear(flat_pos, _path[_path_idx + 1]):
		_path_idx += 1
	if _path_idx >= _path.size():
		return flat_dest
	var wp: Vector3 = _path[_path_idx]
	if _path_idx == _path.size() - 1 and flat_pos.distance_to(wp) < 1.7:
		return flat_dest
	return wp


func _move_toward(dest: Vector3, stop_dist: float, delta: float) -> bool:
	var flat_pos: Vector3 = Vector3(global_position.x, 0.0, global_position.z)
	var flat_dest: Vector3 = Vector3(dest.x, 0.0, dest.z)
	var dist_goal: float = flat_pos.distance_to(flat_dest)
	if dist_goal <= stop_dist:
		_stuck_timer = 0.0
		_clear_path()
		return true

	# Evita empurra-empurra quando aliados já ocuparam o ponto de chegada
	if (state == State.MOVING or state == State.ATTACK_MOVING) and dist_goal < 1.85 and _game_manager != null:
		for ally in _game_manager.query_units(flat_dest, 1.1):
			if ally != self and is_instance_valid(ally) and not ally._dead and ally.team == team and ally.state == State.IDLE:
				if Vector2(ally.global_position.x - flat_dest.x, ally.global_position.z - flat_dest.z).length() < 0.95:
					_stuck_timer = 0.0
					_smooth_vel = Vector3.ZERO
					velocity = Vector3.ZERO
					_clear_path()
					return true

	var nav_target: Vector3 = _get_nav_target(flat_pos, flat_dest, delta)
	var dir: Vector3 = (nav_target - flat_pos)
	dir.y = 0.0
	if dir.length_squared() > 0.0001:
		dir = dir.normalized()

	var on_path: bool = not _path.is_empty()
	var avoid: Vector3 = _compute_obstacle_avoidance(flat_pos, dir)
	var sep: Vector3 = _compute_separation(flat_pos)
	var final_dir: Vector3 = dir + avoid * (0.6 if on_path else 1.0) + sep * 1.10
	final_dir.y = 0.0
	if final_dir.length_squared() > 0.0001:
		final_dir = final_dir.normalized()

	var arrive_mult: float = 1.0
	if (state == State.MOVING or state == State.ATTACK_MOVING) and _path.size() <= 1 and dist_goal < 1.55:
		arrive_mult = clampf(dist_goal / 1.55, 0.35, 1.0)
	var desired_vel: Vector3 = final_dir * (move_speed * arrive_mult)
	_smooth_vel = _smooth_vel.lerp(desired_vel, minf(1.0, 14.0 * delta))

	var proposed_pos: Vector3 = flat_pos + _smooth_vel * delta
	var next_pos: Vector3 = _resolve_world_collisions(flat_pos, proposed_pos)

	var moved_dist: float = flat_pos.distance_to(next_pos)
	if moved_dist < move_speed * arrive_mult * delta * 0.22:
		_stuck_timer += delta
	else:
		_stuck_timer = maxf(0.0, _stuck_timer - delta * 2.0)

	if _stuck_timer >= 0.35 and dist_goal < 2.4 and (state == State.MOVING or state == State.ATTACK_MOVING):
		_stuck_timer = 0.0
		_smooth_vel = Vector3.ZERO
		velocity = Vector3.ZERO
		return true
	if _stuck_timer >= 1.1:
		_stuck_timer = 0.0
		_stuck_count += 1
		_path = PackedVector3Array()
		_repath_cd = 0.0
		if _stuck_count >= 5 and (state == State.MOVING or state == State.ATTACK_MOVING):
			_smooth_vel = Vector3.ZERO
			velocity = Vector3.ZERO
			_clear_path()
			return true

	var deck_y: float = get_bridge_deck_height(next_pos.x, next_pos.z)
	velocity = (next_pos - flat_pos) / maxf(0.0001, delta)
	global_position = Vector3(next_pos.x, deck_y, next_pos.z)
	var face_vec: Vector3 = next_pos - flat_pos
	if face_vec.length_squared() > 0.0004:
		var steer_face: Vector3 = (dir * 0.60 + face_vec.normalized() * 0.40).normalized()
		_face_point(next_pos + steer_face * 2.0, delta)
	else:
		_face_point(next_pos + dir * 2.0, delta)
	return false


func _compute_obstacle_avoidance(flat_pos: Vector3, desired_dir: Vector3) -> Vector3:
	if _game_manager == null:
		return Vector3.ZERO
	var steer: Vector3 = Vector3.ZERO
	var id_sign: float = 1.0 if (get_instance_id() % 2) == 0 else -1.0

	for obs in _get_nearby_obstacles(flat_pos, body_radius + 1.85, true):
		var op: Vector3 = obs["pos"]
		var min_r: float = float(obs["radius"]) + body_radius
		var feeler_r: float = min_r + 1.65
		var to_obs: Vector3 = Vector3(op.x - flat_pos.x, 0.0, op.z - flat_pos.z)
		var d: float = to_obs.length()
		if d > 0.001 and d < feeler_r:
			var to_dir: Vector3 = to_obs / d
			if to_dir.dot(desired_dir) > -0.15:
				var strength: float = (feeler_r - d) / 1.65
				steer -= to_dir * strength * 1.45
				var tang: Vector3 = Vector3(-to_dir.z, 0.0, to_dir.x)
				var align: float = tang.dot(desired_dir)
				var side_sign: float = (1.0 if align >= 0.0 else -1.0) if absf(align) >= 0.12 else id_sign
				steer += tang * side_sign * strength * 1.85
	return steer


func _resolve_world_collisions(prev_pos: Vector3, pos: Vector3) -> Vector3:
	var p: Vector3 = Vector3(pos.x, 0.0, pos.z)
	var s_prev: float = river_signed_at(prev_pos.x, prev_pos.z)
	var pref_side: float = 1.0 if s_prev >= 0.0 else -1.0
	var neighbors: Array = []
	if _game_manager != null:
		neighbors = _game_manager.query_units(p, body_radius + 1.3)

	for _pass in range(2):
		for obs in _get_nearby_obstacles(p, body_radius + 0.3, false):
			var op: Vector3 = obs["pos"]
			var min_r: float = float(obs["radius"]) + body_radius
			var dx: float = p.x - op.x
			var dz: float = p.z - op.z
			var d_sq: float = dx * dx + dz * dz
			if d_sq < min_r * min_r:
				var d: float = sqrt(d_sq)
				if d > 0.0001:
					p.x = op.x + (dx / d) * min_r
					p.z = op.z + (dz / d) * min_r
				else:
					var fallback_dir: Vector2 = Vector2(prev_pos.x - op.x, prev_pos.z - op.z).normalized()
					if fallback_dir.length_squared() < 0.01:
						fallback_dir = Vector2(1.0, 0.0)
					p.x = op.x + fallback_dir.x * min_r
					p.z = op.z + fallback_dir.y * min_r

		for u in neighbors:
			if u == self or not is_instance_valid(u) or u._dead:
				continue
			var up: Vector3 = u.global_position
			var min_u: float = (body_radius + u.body_radius) * 0.88
			var ux: float = p.x - up.x
			var uz: float = p.z - up.z
			if absf(ux) >= min_u or absf(uz) >= min_u:
				continue
			var d_sq: float = ux * ux + uz * uz
			if d_sq < min_u * min_u:
				var d: float = sqrt(d_sq)
				if d > 0.0001:
					p.x = up.x + (ux / d) * min_u
					p.z = up.z + (uz / d) * min_u
				else:
					p.x += min_u

		# Parapeitos laterais e corredor das pontes sobre o rio
		for b in BRIDGES:
			var across_p: float = (p.x - p.z) * 0.70710678
			var across_prev: float = (prev_pos.x - prev_pos.z) * 0.70710678
			if absf(across_p) <= BRIDGE_HALF_LEN or absf(across_prev) <= BRIDGE_HALF_LEN:
				var along_p: float = ((p.x + p.z) - (b.x + b.z)) * 0.70710678
				var along_prev: float = ((prev_pos.x + prev_pos.z) - (b.x + b.z)) * 0.70710678
				if absf(along_prev) <= BRIDGE_HALF_WIDTH + 0.15:
					if absf(along_p) > BRIDGE_HALF_WIDTH:
						var clamped_al: float = clampf(along_p, -BRIDGE_HALF_WIDTH, BRIDGE_HALF_WIDTH)
						var delta_al: float = (clamped_al - along_p) * 0.70710678
						p.x += delta_al
						p.z += delta_al
				elif absf(across_p) < BRIDGE_HALF_LEN - 0.15 and absf(along_p) < 4.55:
					var wall_side: float = 1.0 if along_prev >= 0.0 else -1.0
					var delta_wall: float = (wall_side * 4.55 - along_p) * 0.70710678
					p.x += delta_wall
					p.z += delta_wall

		# Barreira rígida da água do rio (somente atravessável sobre as pontes)
		if is_in_river_water(p.x, p.z, 0.0):
			var side: float = pref_side if absf(s_prev) >= 0.08 else (1.0 if river_signed_at(p.x, p.z) >= 0.0 else -1.0)
			var s_curr: float = river_signed_at(p.x, p.z)
			var diff: float = (side * RIVER_BANK_DIST) - s_curr
			p.x += diff * 0.5
			p.z -= diff * 0.5

		p.x = clampf(p.x, -UNIT_BOUND - 1.0, UNIT_BOUND + 1.0)
		p.z = clampf(p.z, -UNIT_BOUND - 1.0, UNIT_BOUND + 1.0)

	return p


func _compute_separation(flat_pos: Vector3) -> Vector3:
	if _game_manager == null:
		return Vector3.ZERO
	var push: Vector3 = Vector3.ZERO
	var min_sep: float = body_radius * 2.5
	var min_sep_sq: float = min_sep * min_sep
	for u in _game_manager.query_units(flat_pos, min_sep + 1.2):
		if u == self or not is_instance_valid(u) or u._dead:
			continue
		var up: Vector3 = u.global_position
		var dx: float = flat_pos.x - up.x
		if absf(dx) >= min_sep:
			continue
		var dz: float = flat_pos.z - up.z
		if absf(dz) >= min_sep:
			continue
		var d_sq: float = dx * dx + dz * dz
		if d_sq > 0.0001 and d_sq < min_sep_sq:
			var d: float = sqrt(d_sq)
			push += Vector3(dx / d, 0.0, dz / d) * ((min_sep - d) / min_sep)
	return push


func _face_point(pt: Vector3, delta: float) -> void:
	var flat_dir: Vector3 = Vector3(pt.x - global_position.x, 0.0, pt.z - global_position.z)
	if flat_dir.length_squared() < 0.001:
		return
	var target_yaw: float = atan2(-flat_dir.x, -flat_dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, minf(1.0, 12.0 * delta))


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func _get_target_radius(node: Variant) -> float:
	if node == null or not is_instance_valid(node):
		return 0.6
	if node is RTSBuilding:
		return (node as RTSBuilding).footprint_radius
	if node is RTSUnit:
		return (node as RTSUnit).body_radius
	return 0.6


func _is_valid_enemy(node: Variant) -> bool:
	if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
		return false
	if node is RTSUnit:
		var u: RTSUnit = node as RTSUnit
		if is_siege:
			return false
		return u.team != team and u.hp > 0.0 and not u._dead
	if node is RTSBuilding:
		var b: RTSBuilding = node as RTSBuilding
		return b.team != team and b.hp > 0.0 and not b._dead
	return false


func _is_valid_resource(node: Variant) -> bool:
	if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
		return false
	var r: RTSResourceNode = node as RTSResourceNode
	return r != null and r.amount_left > 0 and r.can_be_gathered_by(team)


func _is_valid_depot(node: Variant) -> bool:
	if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
		return false
	var b: RTSBuilding = node as RTSBuilding
	return b != null and not b._dead and b.team == team and b.is_constructed and b.accepts_resource(carrying_type)


func _can_see(node: Node3D) -> bool:
	# O jogador só reage ao que enxerga; a IA (time 1) conhece o mapa.
	if team != 0:
		return true
	if node is RTSUnit:
		return not (node as RTSUnit).fog_hidden
	if node is RTSBuilding:
		return not (node as RTSBuilding).fog_hidden
	return true


func _find_nearest_enemy(radius: float) -> Node3D:
	if _game_manager == null:
		return null
	var best: Node3D = null
	var best_d: float = radius
	if not is_siege:
		for u in _game_manager.query_units(global_position, radius):
			if not _is_valid_enemy(u) or not _can_see(u):
				continue
			var d: float = _flat_distance(global_position, u.global_position)
			if d < best_d:
				best_d = d
				best = u
		if best != null:
			return best
	for b in _game_manager.buildings:
		if not _is_valid_enemy(b) or not _can_see(b):
			continue
		var d: float = _flat_distance(global_position, b.global_position) - b.footprint_radius
		if d < best_d:
			best_d = d
			best = b
	return best


func _find_nearest_drop_site(r_type: String) -> RTSBuilding:
	if _game_manager == null:
		return null
	var best: RTSBuilding = null
	var best_d: float = 99999.0
	for b in _game_manager.buildings:
		if not is_instance_valid(b) or b.is_queued_for_deletion() or b._dead:
			continue
		if b.team == team and b.is_constructed and b.accepts_resource(r_type):
			var d: float = _flat_distance(global_position, b.global_position)
			if d < best_d:
				best_d = d
				best = b
	return best


func _find_nearest_resource(r_type: String, near_pos: Vector3, max_dist: float) -> RTSResourceNode:
	if _game_manager == null:
		return null
	var best: RTSResourceNode = null
	var best_d: float = max_dist
	for r in _game_manager.resources:
		if not is_instance_valid(r) or r.is_queued_for_deletion() or r.amount_left <= 0:
			continue
		if r.resource_type != r_type or not r.can_be_gathered_by(team):
			continue
		var d: float = _flat_distance(near_pos, r.global_position)
		if d < best_d:
			best_d = d
			best = r
	return best


func _find_nearest_resource_excluding(r_type: String, near_pos: Vector3, max_dist: float, exclude: Variant) -> RTSResourceNode:
	if _game_manager == null:
		return null
	var best: RTSResourceNode = null
	var best_d: float = max_dist
	for r in _game_manager.resources:
		if r == exclude or not is_instance_valid(r) or r.is_queued_for_deletion() or r.amount_left <= 0:
			continue
		if r.resource_type != r_type or not r.can_be_gathered_by(team):
			continue
		var d: float = _flat_distance(near_pos, r.global_position)
		if d < best_d:
			best_d = d
			best = r
	return best


func _find_unfinished_building(max_dist: float) -> RTSBuilding:
	if _game_manager == null:
		return null
	var best: RTSBuilding = null
	var best_d: float = max_dist
	for b in _game_manager.buildings:
		if not is_instance_valid(b) or b.is_queued_for_deletion() or b._dead:
			continue
		if b.team == team and not b.is_constructed:
			var d: float = _flat_distance(global_position, b.global_position)
			if d < best_d:
				best_d = d
				best = b
	return best


# ==============================================================================
# COMANDOS PÚBLICOS DE RTS
# ==============================================================================

func command_move(dest: Vector3) -> void:
	target_enemy = null
	target_resource = null
	target_building = null
	_stuck_timer = 0.0
	_clear_path()
	move_target = sanitize_destination(dest)
	state = State.MOVING


func command_attack_move(dest: Vector3) -> void:
	target_enemy = null
	target_resource = null
	target_building = null
	_stuck_timer = 0.0
	_clear_path()
	move_target = sanitize_destination(dest)
	state = State.ATTACK_MOVING


func command_attack(enemy: Variant) -> void:
	if not _is_valid_enemy(enemy):
		if is_siege and enemy != null and is_instance_valid(enemy) and enemy is Node3D:
			command_move((enemy as Node3D).global_position)
		return
	target_resource = null
	target_building = null
	_stuck_timer = 0.0
	_clear_path()
	target_enemy = enemy
	state = State.CHASING


func command_gather(res: Variant) -> void:
	if unit_type != "worker" or not _is_valid_resource(res):
		return
	target_enemy = null
	target_building = null
	_stuck_timer = 0.0
	_clear_path()
	target_resource = res
	_last_resource_pos = res.global_position
	_last_resource_type = res.resource_type
	_gather_progress = 0.0
	if carrying_amount > 0 and carrying_type != res.resource_type:
		_begin_return()
	else:
		state = State.GATHERING


func command_auto_gather_near(r_type: String = "") -> void:
	if unit_type != "worker" or _game_manager == null:
		return
	var best: RTSResourceNode = null
	var best_d: float = 99999.0
	for r in _game_manager.resources:
		if not is_instance_valid(r) or r.is_queued_for_deletion() or r.amount_left <= 0:
			continue
		if r_type != "" and r.resource_type != r_type:
			continue
		if not r.can_be_gathered_by(team):
			continue
		var d: float = _flat_distance(global_position, r.global_position)
		if d < best_d:
			best_d = d
			best = r
	if best != null:
		command_gather(best)


func command_build(b: Variant) -> void:
	if unit_type != "worker" or b == null or not is_instance_valid(b) or b.is_queued_for_deletion() or b.team != team:
		return
	target_enemy = null
	target_resource = null
	_stuck_timer = 0.0
	_clear_path()
	target_building = b
	state = State.BUILDING


func command_stop() -> void:
	target_enemy = null
	target_resource = null
	target_building = null
	_pending_hit_timer = -1.0
	_pending_hit_target = null
	_stuck_timer = 0.0
	_clear_path()
	_smooth_vel = Vector3.ZERO
	velocity = Vector3.ZERO
	state = State.IDLE


func apply_kingdom_modifiers() -> void:
	var prev_max: float = maxf(1.0, max_hp)
	var hp_mult: float = 1.0
	var dmg_mult: float = 1.0
	var spd_mult: float = 1.0
	var cd_mult: float = 1.0
	var range_add: float = 0.0
	var armor_add: int = 0

	if team == 0 and _game_manager != null and "player_mods" in _game_manager:
		var mods: Dictionary = _game_manager.get("player_mods")
		if unit_type != "worker":
			hp_mult *= float(mods.get("army_hp_mult", 1.0))
			armor_add += int(mods.get("army_armor_bonus", 0))
			if is_siege:
				spd_mult *= float(mods.get("siege_speed_mult", 1.0))
			else:
				spd_mult *= float(mods.get("army_speed_mult", 1.0))
			if is_ranged:
				dmg_mult *= float(mods.get("ranged_dmg_mult", 1.0))
				range_add += float(mods.get("ranged_range_bonus", 0.0))
			elif not is_siege:
				dmg_mult *= float(mods.get("melee_dmg_mult", 1.0))

	if vet_rank > 0:
		hp_mult *= (1.0 + 0.10 * float(vet_rank))
		dmg_mult *= (1.0 + 0.12 * float(vet_rank))
		if vet_rank >= 2:
			armor_add += 1

	if _war_cry_timer > 0.0:
		spd_mult *= 1.28
		cd_mult *= 0.75

	max_hp = roundf(_base_max_hp * hp_mult)
	if max_hp > prev_max:
		hp = minf(max_hp, hp + (max_hp - prev_max))
	else:
		hp = minf(hp, max_hp)
	armor = _base_armor + armor_add
	move_speed = _base_speed * spd_mult
	attack_damage = _base_damage * dmg_mult
	attack_range = _base_range + range_add
	attack_cooldown = maxf(0.45, _base_cd * cd_mult)
	_update_hp_bar()


func register_kill() -> void:
	kills += 1
	var next_rank: int = 0
	if kills >= 10:
		next_rank = 3
	elif kills >= 5:
		next_rank = 2
	elif kills >= 2:
		next_rank = 1

	if next_rank > vet_rank:
		vet_rank = next_rank
		apply_kingdom_modifiers()
		hp = minf(max_hp, hp + max_hp * 0.25)
		_update_hp_bar()
		var stars: String = "★".repeat(vet_rank)
		if _vet_label == null and _hp_root != null and DisplayServer.get_name() != "headless":
			_vet_label = Label3D.new()
			_vet_label.font_size = 34
			_vet_label.outline_size = 7
			_vet_label.modulate = Color(1.0, 0.88, 0.26)
			_vet_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			_vet_label.no_depth_test = true
			_vet_label.position = Vector3(0.0, 0.25, 0.0)
			_hp_root.add_child(_vet_label)
		if _vet_label != null:
			_vet_label.text = stars
		if _game_manager != null and not fog_hidden:
			var titles: Array[String] = ["", "★ Veterano!", "★★ Campeão!", "★★★ Lenda!"]
			_game_manager.spawn_floating_text(global_position + Vector3(0.0, 2.7, 0.0), titles[vet_rank], Color(1.0, 0.88, 0.26))
			if _game_manager.vfx != null:
				_game_manager.vfx.spawn_hit_sparks(global_position + Vector3(0.0, 0.6, 0.0))


func apply_war_cry(duration: float = 6.5) -> void:
	_war_cry_timer = maxf(_war_cry_timer, duration)
	apply_kingdom_modifiers()


func set_hold_position(enabled: bool) -> void:
	hold_position = enabled
	if hold_position and state == State.CHASING:
		target_enemy = null
		state = State.IDLE


func get_rank_title() -> String:
	match vet_rank:
		1:
			return "★ Veterano"
		2:
			return "★★ Campeão"
		3:
			return "★★★ Lenda"
	return ""


func flash_hit() -> void:
	_hit_flash_timer = 0.12


func set_selected(selected: bool) -> void:
	_is_selected = selected
	if _selection_ring != null:
		_selection_ring.visible = selected


func set_fog_hidden(hidden: bool) -> void:
	if hidden == fog_hidden:
		return
	fog_hidden = hidden
	visible = not hidden
	if not _dead:
		collision_layer = 0 if hidden else 1


func get_display_name() -> String:
	var cfg: Dictionary = STATS.get(unit_type, STATS["soldier"])
	return String(cfg["name"])


func get_state_label() -> String:
	var prefix: String = ""
	if _war_cry_timer > 0.0:
		prefix = "Investida! • "
	match state:
		State.IDLE:
			return prefix + ("Mantendo Posição" if hold_position else "Ocioso")
		State.MOVING:
			return prefix + "Marchando"
		State.ATTACK_MOVING:
			return prefix + "Patrulha de Ataque"
		State.GATHERING:
			var r_name: String = GameManager.RES_NAMES.get(_last_resource_type, "")
			return "Coletando %s" % r_name if r_name != "" else "Coletando"
		State.RETURNING_RESOURCE:
			return "Entregando %s" % GameManager.RES_NAMES.get(carrying_type, "recurso")
		State.BUILDING:
			return "Construindo / Reparando"
		State.CHASING:
			return prefix + "Perseguindo Inimigo"
		State.ATTACKING:
			return prefix + "Em Combate"
	return "Ocioso"


func take_damage(amount: float, attacker: Variant = null, ranged: bool = false) -> void:
	if _dead:
		return
	var dmg: float = amount
	var from_ranged: bool = ranged
	if attacker != null and is_instance_valid(attacker):
		_last_attacker = attacker
		if "team" in attacker:
			_last_attacker_team = int(attacker.team)
		if not from_ranged and (attacker is RTSBuilding or (attacker is RTSUnit and (attacker as RTSUnit).is_ranged)):
			from_ranged = true
	if from_ranged:
		dmg *= ranged_resist
	var mitigated: float = maxf(1.0, dmg - float(armor) * 0.5)
	hp = maxf(0.0, hp - mitigated)
	_update_hp_bar()
	flash_hit()

	if _game_manager != null and not fog_hidden and _dmg_popup_cd <= 0.0 and DisplayServer.get_name() != "headless":
		_dmg_popup_cd = 0.35
		var is_big: bool = mitigated >= 24.0
		var pop_col: Color = Color(1.0, 0.86, 0.32) if is_big else Color(1.0, 0.45, 0.40)
		_game_manager.spawn_floating_text(global_position + Vector3(0.0, 1.85, 0.0), "-%d" % int(round(mitigated)), pop_col)

	if state == State.IDLE and _is_valid_enemy(attacker):
		if hold_position:
			var reach_now: float = attack_range + _get_target_radius(attacker) + 0.45
			if _flat_distance(global_position, (attacker as Node3D).global_position) <= reach_now:
				target_enemy = attacker
				state = State.ATTACKING
		else:
			target_enemy = attacker
			state = State.CHASING

	if _game_manager != null and _game_manager.has_method("on_entity_damaged"):
		_game_manager.on_entity_damaged(self, attacker)

	if hp <= 0.0:
		_die()


func _update_hp_bar() -> void:
	if _hp_fill == null:
		return
	var ratio: float = clampf(hp / maxf(1.0, max_hp), 0.0, 1.0)
	var inner_w: float = 1.07
	_hp_fill.scale.x = maxf(0.001, ratio)
	_hp_fill.position.x = -inner_w * 0.5 * (1.0 - ratio)


func _die() -> void:
	if _dead:
		return
	_dead = true
	_pending_hit_timer = -1.0
	_pending_hit_target = null
	_smooth_vel = Vector3.ZERO
	velocity = Vector3.ZERO
	collision_layer = 0
	remove_from_group("rts_units")
	if _selection_ring != null:
		_selection_ring.visible = false
	if _team_ring != null:
		_team_ring.visible = false
	if _hp_root != null:
		_hp_root.visible = false
	for cm in _carry_meshes.values():
		(cm as MeshInstance3D).visible = false

	if _game_manager != null and _game_manager.has_method("on_unit_destroyed"):
		_game_manager.on_unit_destroyed(self)
	if _game_manager != null and _game_manager.sfx != null and not fog_hidden:
		_game_manager.sfx.play_unit_death(global_position)

	if _anim_player != null and _anim_player.has_animation("Death"):
		_play_anim("Death", 0.08, 1.0, true)
		_death_timer = 1.15
	elif is_siege and _visual_root != null:
		_death_timer = 0.9
		var tw: Tween = create_tween()
		tw.tween_property(_visual_root, "rotation:z", 0.5, 0.5)
		tw.parallel().tween_property(_visual_root, "position:y", -0.6, 0.85)
	else:
		queue_free()
