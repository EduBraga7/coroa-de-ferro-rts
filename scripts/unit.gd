extends CharacterBody3D
class_name RTSUnit

## Unidade controlável de RTS (Camponês, Espadachim, Arqueiro, Paladino Real).

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

const STATS: Dictionary = {
	"worker": {
		"name": "Camponês",
		"gold": 50,
		"wood": 0,
		"hp": 80.0,
		"armor": 0,
		"speed": 6.6,
		"damage": 8.0,
		"range": 2.0,
		"cd": 1.15,
		"pop": 1,
		"train_time": 5.5,
		"radius": 0.48,
		"model": "res://assets/models/unit_worker.glb",
		"hp_height": 2.35,
	},
	"soldier": {
		"name": "Espadachim",
		"gold": 75,
		"wood": 25,
		"hp": 175.0,
		"armor": 2,
		"speed": 6.2,
		"damage": 18.0,
		"range": 2.35,
		"cd": 1.0,
		"pop": 1,
		"train_time": 7.0,
		"radius": 0.52,
		"model": "res://assets/models/unit_soldier.glb",
		"hp_height": 2.50,
	},
	"archer": {
		"name": "Arqueiro",
		"gold": 60,
		"wood": 50,
		"hp": 105.0,
		"armor": 0,
		"speed": 6.8,
		"damage": 15.0,
		"range": 14.5,
		"cd": 1.25,
		"pop": 1,
		"train_time": 7.5,
		"radius": 0.48,
		"model": "res://assets/models/unit_archer.glb",
		"hp_height": 2.45,
	},
	"knight": {
		"name": "Paladino Real",
		"gold": 140,
		"wood": 60,
		"hp": 290.0,
		"armor": 4,
		"speed": 8.2,
		"damage": 32.0,
		"range": 2.65,
		"cd": 1.1,
		"pop": 2,
		"train_time": 11.0,
		"radius": 0.62,
		"model": "res://assets/models/unit_knight.glb",
		"hp_height": 2.95,
	},
}

const BRIDGES: Array[Vector3] = [
	Vector3(-34.0, 0.0, -34.0),
	Vector3(0.0, 0.0, 0.0),
	Vector3(34.0, 0.0, 34.0),
]

const RIVER_BANK_DIST: float = 5.75
const BRIDGE_HALF_WIDTH: float = 3.32
const BRIDGE_HALF_LEN: float = 7.65

var unit_type: String = "soldier"
var team: int = 0
var max_hp: float = 100.0
var hp: float = 100.0
var armor: int = 0
var move_speed: float = 6.0
var attack_damage: float = 12.0
var attack_range: float = 2.2
var attack_cooldown: float = 1.0
var pop_cost: int = 1
var body_radius: float = 0.5

var state: int = State.IDLE
var move_target: Vector3 = Vector3.ZERO
var target_enemy: Variant = null
var target_resource: Variant = null
var target_building: Variant = null

var carrying_type: String = ""
var carrying_amount: int = 0
var _last_resource_pos: Vector3 = Vector3.ZERO
var _last_resource_type: String = "gold"

var _attack_timer: float = 0.0
var _gather_timer: float = 0.0
var _scan_timer: float = 0.0
var _anim_phase: float = 0.0
var _swing_timer: float = 0.0
var _is_selected: bool = false
var _dead: bool = false
var _age_upgraded: bool = false
var _stuck_timer: float = 0.0

static var _team_mat_cache: Dictionary = {}

var _game_manager: Node = null
var _visual_root: Node3D
var _anim_player: AnimationPlayer = null
var _current_anim: String = ""
var _attack_anim_timer: float = 0.0
var _death_timer: float = 0.0
var _selection_ring: MeshInstance3D
var _team_ring: MeshInstance3D
var _carry_gold_mesh: MeshInstance3D
var _carry_wood_mesh: MeshInstance3D
var _hp_root: Node3D
var _hp_fill: MeshInstance3D


func setup(u_type: String, p_team: int, gm: Node, age: int = 1) -> void:
	unit_type = u_type
	team = p_team
	_game_manager = gm

	var cfg: Dictionary = STATS.get(unit_type, STATS["soldier"])
	max_hp = float(cfg["hp"])
	hp = max_hp
	armor = int(cfg["armor"])
	move_speed = float(cfg["speed"])
	attack_damage = float(cfg["damage"])
	attack_range = float(cfg["range"])
	attack_cooldown = float(cfg["cd"])
	pop_cost = int(cfg["pop"])
	body_radius = float(cfg["radius"])

	add_to_group("rts_units")
	_build_visuals(cfg)
	_build_collision()

	if age >= 2:
		apply_age_bonus()
	_update_hp_bar()


func apply_age_bonus() -> void:
	if _age_upgraded:
		return
	_age_upgraded = true
	var ratio: float = hp / maxf(1.0, max_hp)
	max_hp = roundf(max_hp * 1.15)
	hp = max_hp * ratio
	attack_damage = roundf(attack_damage * 1.25)
	armor += 2
	_update_hp_bar()


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
	else:
		var fallback: MeshInstance3D = MeshInstance3D.new()
		var cap: CapsuleMesh = CapsuleMesh.new()
		cap.radius = body_radius
		cap.height = 1.6
		fallback.mesh = cap
		fallback.position.y = 0.8
		_visual_root.add_child(fallback)

	var team_col: Color = Color(0.18, 0.56, 1.0) if team == 0 else Color(0.95, 0.24, 0.20)

	# Pacote carregado pelo camponês (Ouro / Madeira)
	if unit_type == "worker":
		_carry_gold_mesh = MeshInstance3D.new()
		var gbox: BoxMesh = BoxMesh.new()
		gbox.size = Vector3(0.30, 0.24, 0.30)
		_carry_gold_mesh.mesh = gbox
		_carry_gold_mesh.position = Vector3(0.0, 0.92, -0.38)
		var gmat: StandardMaterial3D = StandardMaterial3D.new()
		gmat.albedo_color = Color(0.98, 0.78, 0.16)
		gmat.metallic = 0.88
		gmat.roughness = 0.24
		_carry_gold_mesh.material_override = gmat
		_carry_gold_mesh.visible = false
		_visual_root.add_child(_carry_gold_mesh)

		_carry_wood_mesh = MeshInstance3D.new()
		var wcyl: CylinderMesh = CylinderMesh.new()
		wcyl.top_radius = 0.11
		wcyl.bottom_radius = 0.11
		wcyl.height = 0.55
		_carry_wood_mesh.mesh = wcyl
		_carry_wood_mesh.rotation.z = PI * 0.5
		_carry_wood_mesh.position = Vector3(0.0, 0.92, -0.38)
		var wmat: StandardMaterial3D = StandardMaterial3D.new()
		wmat.albedo_color = Color(0.46, 0.27, 0.12)
		wmat.roughness = 0.78
		_carry_wood_mesh.material_override = wmat
		_carry_wood_mesh.visible = false
		_visual_root.add_child(_carry_wood_mesh)

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
	var s_mat: StandardMaterial3D = StandardMaterial3D.new()
	s_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	s_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	s_mat.albedo_color = Color(0.28, 0.98, 0.45, 0.88) if team == 0 else Color(1.0, 0.35, 0.25, 0.88)
	_selection_ring.material_override = s_mat
	_selection_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_selection_ring.visible = false
	add_child(_selection_ring)

	# Barra de vida 3D
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
		return _team_mat_cache[cache_key] as StandardMaterial3D
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
	cap.height = 1.75
	col.shape = cap
	col.position.y = 0.875
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

	if _hp_root != null:
		var show_hp: bool = _is_selected or hp < max_hp
		_hp_root.visible = show_hp
		if show_hp:
			var cam: Camera3D = get_viewport().get_camera_3d()
			if cam != null:
				_hp_root.global_basis = cam.global_basis

	# Atualiza pacote carregado pelo camponês
	if unit_type == "worker":
		if _carry_gold_mesh != null:
			_carry_gold_mesh.visible = (carrying_amount > 0 and carrying_type == "gold")
		if _carry_wood_mesh != null:
			_carry_wood_mesh.visible = (carrying_amount > 0 and carrying_type == "wood")

	# Máquina de estados de animação (AnimationPlayer esquelético com fallback procedural)
	if _anim_player != null:
		if _attack_anim_timer > 0.0:
			_attack_anim_timer = maxf(0.0, _attack_anim_timer - delta)
		elif velocity.length_squared() > 0.25:
			_play_anim("Walk", 0.14, clampf(velocity.length() / 5.2, 0.85, 1.55))
		elif unit_type == "worker" and (state == State.GATHERING or state == State.BUILDING):
			var gather_clip: String = "Gather" if _anim_player.has_animation("Gather") else "Attack"
			_play_anim(gather_clip, 0.14, 1.15)
		else:
			_play_anim("Idle", 0.20, 1.0)
	elif _visual_root != null:
		if _swing_timer > 0.0:
			_swing_timer = maxf(0.0, _swing_timer - delta)
			var swing_angle: float = sin((_swing_timer / 0.25) * PI) * 0.42
			_visual_root.rotation.x = -swing_angle
		elif velocity.length_squared() > 0.25:
			_anim_phase += delta * 11.0
			_visual_root.position.y = absf(sin(_anim_phase)) * 0.08
			_visual_root.rotation.x = lerpf(_visual_root.rotation.x, -0.09, 10.0 * delta)
		elif absf(_visual_root.position.y) > 0.001 or absf(_visual_root.rotation.x) > 0.001:
			_visual_root.position.y = lerpf(_visual_root.position.y, 0.0, 12.0 * delta)
			_visual_root.rotation.x = lerpf(_visual_root.rotation.x, 0.0, 12.0 * delta)


func _physics_process(delta: float) -> void:
	if _dead:
		return

	_attack_timer = maxf(0.0, _attack_timer - delta)
	_scan_timer -= delta

	match state:
		State.IDLE:
			velocity = Vector3.ZERO
			if _scan_timer <= 0.0:
				_scan_timer = 0.35
				var enemy: Node3D = _find_nearest_enemy(13.5 if unit_type != "archer" else 16.0)
				if enemy != null:
					target_enemy = enemy
					state = State.CHASING

		State.MOVING:
			if _move_toward(move_target, 0.55, delta):
				velocity = Vector3.ZERO
				state = State.IDLE

		State.ATTACK_MOVING:
			if _scan_timer <= 0.0:
				_scan_timer = 0.3
				var enemy: Node3D = _find_nearest_enemy(16.0)
				if enemy != null:
					target_enemy = enemy
					state = State.CHASING
					return
			if _move_toward(move_target, 0.85, delta):
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


func _process_gathering(delta: float) -> void:
	if unit_type != "worker":
		state = State.IDLE
		return
	if carrying_amount >= 10:
		state = State.RETURNING_RESOURCE
		return

	if not is_instance_valid(target_resource) or target_resource.is_queued_for_deletion():
		# Procura outro recurso do mesmo tipo próximo
		var next_res: RTSResourceNode = _find_nearest_resource(_last_resource_type, _last_resource_pos, 45.0)
		if next_res != null:
			target_resource = next_res
			_last_resource_pos = next_res.global_position
		else:
			if carrying_amount > 0:
				state = State.RETURNING_RESOURCE
			else:
				state = State.IDLE
			return

	_last_resource_pos = target_resource.global_position
	_last_resource_type = target_resource.resource_type
	var reach: float = target_resource.collision_radius + 1.55
	var dist: float = _flat_distance(global_position, target_resource.global_position)
	if dist > reach:
		_move_toward(target_resource.global_position, reach * 0.9, delta)
	else:
		velocity = Vector3.ZERO
		_face_point(target_resource.global_position, delta)
		_gather_timer += delta
		if _gather_timer >= 0.65 and _swing_timer <= 0.0:
			_swing_timer = 0.22
		if _gather_timer >= 1.5:
			_gather_timer = 0.0
			var taken: int = target_resource.harvest(10 - carrying_amount)
			if taken > 0:
				carrying_type = _last_resource_type
				carrying_amount += taken
				if _game_manager != null and _game_manager.sfx != null and team == 0:
					_game_manager.sfx.play_harvest()
			if carrying_amount >= 10 or not is_instance_valid(target_resource) or target_resource.is_queued_for_deletion():
				state = State.RETURNING_RESOURCE


func _process_returning(delta: float) -> void:
	if carrying_amount <= 0:
		if is_instance_valid(target_resource) and not target_resource.is_queued_for_deletion():
			state = State.GATHERING
		else:
			state = State.IDLE
		return

	var depot: RTSBuilding = _find_nearest_town_center()
	if depot == null:
		state = State.IDLE
		return

	var reach: float = depot.footprint_radius + 1.55
	var dist: float = _flat_distance(global_position, depot.global_position)
	if dist > reach:
		_move_toward(depot.global_position, reach * 0.92, delta)
	else:
		velocity = Vector3.ZERO
		if _game_manager != null:
			_game_manager.add_resource(team, carrying_type, carrying_amount)
			if team == 0:
				var label_txt: String = "+%d %s" % [carrying_amount, "Ouro" if carrying_type == "gold" else "Madeira"]
				var col: Color = Color(1.0, 0.85, 0.25) if carrying_type == "gold" else Color(0.45, 0.9, 0.42)
				_game_manager.spawn_floating_text(global_position + Vector3(0.0, 2.2, 0.0), label_txt, col)
		carrying_amount = 0
		carrying_type = ""

		if is_instance_valid(target_resource) and not target_resource.is_queued_for_deletion():
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
	if not is_instance_valid(target_building) or target_building.is_queued_for_deletion() or target_building.team != team:
		target_building = null
		state = State.IDLE
		return

	if target_building.is_constructed and target_building.hp >= target_building.max_hp:
		# Procura outra construção inacabada perto ou volta a trabalhar
		var next_b: RTSBuilding = _find_unfinished_building(24.0)
		if next_b != null:
			target_building = next_b
		else:
			target_building = null
			state = State.IDLE
		return

	var reach: float = target_building.footprint_radius + 1.65
	var dist: float = _flat_distance(global_position, target_building.global_position)
	if dist > reach:
		_move_toward(target_building.global_position, reach * 0.9, delta)
	else:
		velocity = Vector3.ZERO
		_face_point(target_building.global_position, delta)
		if _swing_timer <= 0.0:
			_swing_timer = 0.25
		if not target_building.is_constructed:
			target_building.advance_construction(delta)
		else:
			target_building.repair(delta)


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
		state = State.ATTACKING
	else:
		_move_toward(target_enemy.global_position, reach * 0.9, delta)


func _process_attacking(delta: float) -> void:
	if not _is_valid_enemy(target_enemy):
		target_enemy = _find_nearest_enemy(16.0)
		if target_enemy != null:
			state = State.CHASING
		else:
			state = State.IDLE
		return

	var reach: float = attack_range + _get_target_radius(target_enemy) + 0.45
	var dist: float = _flat_distance(global_position, target_enemy.global_position)
	if dist > reach:
		state = State.CHASING
		return

	velocity = Vector3.ZERO
	_face_point(target_enemy.global_position, delta)

	if _attack_timer <= 0.0:
		_attack_timer = attack_cooldown
		_swing_timer = 0.24
		_play_anim("Attack", 0.08, 1.15, true)
		_attack_anim_timer = minf(attack_cooldown * 0.82, 0.72)
		if unit_type == "archer":
			if _game_manager != null:
				_game_manager.spawn_projectile(global_position + Vector3(0.0, 1.35, 0.0), target_enemy, attack_damage, self, team)
				if _game_manager.sfx != null and team == 0:
					_game_manager.sfx.play_shoot_arrow()
		else:
			if target_enemy.has_method("take_damage"):
				target_enemy.take_damage(attack_damage, self)
			if _game_manager != null and _game_manager.sfx != null and team == 0:
				_game_manager.sfx.play_hit_melee()


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


func _get_nearby_obstacles(center: Vector3, search_margin: float, skip_active_targets: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _game_manager == null:
		return out
	for b in _game_manager.buildings:
		if not is_instance_valid(b) or b.is_queued_for_deletion():
			continue
		var is_depot: bool = (state == State.RETURNING_RESOURCE and b.team == team and b.building_type == "town_center")
		if skip_active_targets and (b == target_building or b == target_enemy or is_depot):
			continue
		var bp: Vector3 = b.global_position
		var limit: float = b.footprint_radius + search_margin
		if absf(bp.x - center.x) < limit and absf(bp.z - center.z) < limit:
			out.append({"pos": bp, "radius": b.footprint_radius})
	for r in _game_manager.resources:
		if not is_instance_valid(r) or r.is_queued_for_deletion():
			continue
		if skip_active_targets and r == target_resource:
			continue
		var rp: Vector3 = r.global_position
		var limit: float = r.collision_radius + search_margin
		if absf(rp.x - center.x) < limit and absf(rp.z - center.z) < limit:
			out.append({"pos": rp, "radius": r.collision_radius})
	for obs in _game_manager.static_obstacles:
		var op: Vector3 = obs["pos"]
		var orad: float = float(obs["radius"])
		var limit: float = orad + search_margin
		if absf(op.x - center.x) < limit and absf(op.z - center.z) < limit:
			out.append(obs)
	return out


func sanitize_destination(dest: Vector3) -> Vector3:
	var p: Vector3 = Vector3(clampf(dest.x, -85.0, 85.0), 0.0, clampf(dest.z, -85.0, 85.0))
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

	p.x = clampf(p.x, -85.0, 85.0)
	p.z = clampf(p.z, -85.0, 85.0)
	if is_in_river_water(p.x, p.z, 0.10):
		p = _push_point_to_bank(p, cur_side, RIVER_BANK_DIST + 0.35)
	return p


func _move_toward(dest: Vector3, stop_dist: float, delta: float) -> bool:
	var flat_pos: Vector3 = Vector3(global_position.x, 0.0, global_position.z)
	var flat_dest: Vector3 = Vector3(dest.x, 0.0, dest.z)
	if flat_pos.distance_to(flat_dest) <= stop_dist:
		_stuck_timer = 0.0
		return true

	# Roteamento inteligente de entrada/saída nas pontes sobre o rio diagonal
	var nav_target: Vector3 = _get_bridge_waypoint(flat_pos, flat_dest)
	var dir: Vector3 = (nav_target - flat_pos)
	dir.y = 0.0
	if dir.length_squared() > 0.0001:
		dir = dir.normalized()

	var avoid: Vector3 = _compute_obstacle_avoidance(flat_pos, dir)
	var sep: Vector3 = _compute_separation(flat_pos)
	var final_dir: Vector3 = (dir + avoid + sep * 1.10)
	final_dir.y = 0.0
	if final_dir.length_squared() > 0.0001:
		final_dir = final_dir.normalized()

	var proposed_pos: Vector3 = flat_pos + final_dir * move_speed * delta
	var next_pos: Vector3 = _resolve_world_collisions(flat_pos, proposed_pos)

	var moved_dist: float = flat_pos.distance_to(next_pos)
	if (state == State.MOVING or state == State.ATTACK_MOVING) and flat_pos.distance_to(flat_dest) < 2.4 and moved_dist < move_speed * delta * 0.2:
		_stuck_timer += delta
		if _stuck_timer >= 0.35:
			_stuck_timer = 0.0
			velocity = Vector3.ZERO
			return true
	else:
		_stuck_timer = 0.0

	var deck_y: float = get_bridge_deck_height(next_pos.x, next_pos.z)
	velocity = (next_pos - flat_pos) / maxf(0.0001, delta)
	global_position = Vector3(next_pos.x, deck_y, next_pos.z)
	var face_vec: Vector3 = next_pos - flat_pos
	if face_vec.length_squared() > 0.0004:
		_face_point(next_pos + face_vec.normalized() * 2.0, delta)
	else:
		_face_point(next_pos + dir * 2.0, delta)
	return false


func _get_bridge_waypoint(from_p: Vector3, to_p: Vector3) -> Vector3:
	var s_from: float = river_signed_at(from_p.x, from_p.z)
	var s_to: float = river_signed_at(to_p.x, to_p.z)

	# 1. Se a unidade está sobre uma ponte, garante saída limpa pela boca da ponte antes de virar pela margem
	if is_on_bridge_deck(from_p.x, from_p.z, -0.35):
		for b in BRIDGES:
			var along_f: float = ((from_p.x + from_p.z) - (b.x + b.z)) * 0.70710678
			var across_f: float = (from_p.x - from_p.z) * 0.70710678
			if absf(along_f) <= BRIDGE_HALF_WIDTH + 0.6 and absf(across_f) <= BRIDGE_HALF_LEN + 0.2:
				var along_t: float = ((to_p.x + to_p.z) - (b.x + b.z)) * 0.70710678
				if (s_from * s_to < 0.0 or absf(along_t) > 2.9) and absf(across_f) < BRIDGE_HALF_LEN - 0.5:
					var exit_off: Vector3 = Vector3(-5.6, 0.0, 5.6) if s_to < 0.0 else Vector3(5.6, 0.0, -5.6)
					var exit_mouth: Vector3 = b + exit_off
					if from_p.distance_to(exit_mouth) > 1.2:
						return exit_mouth
				break

	# 2. Se origem e destino estão em margens opostas do rio, roteamento em 2 estágios pela melhor ponte
	if (s_from < 0.0 and s_to > 0.0) or (s_from > 0.0 and s_to < 0.0):
		var best_b: Vector3 = BRIDGES[1]
		var best_score: float = 99999.0
		for b in BRIDGES:
			var sc: float = from_p.distance_to(b) + to_p.distance_to(b)
			if sc < best_score:
				best_score = sc
				best_b = b
		var along_from: float = ((from_p.x + from_p.z) - (best_b.x + best_b.z)) * 0.70710678
		var near_mouth: Vector3 = best_b + (Vector3(-5.6, 0.0, 5.6) if s_from < 0.0 else Vector3(5.6, 0.0, -5.6))
		var far_mouth: Vector3 = best_b + (Vector3(5.6, 0.0, -5.6) if s_from < 0.0 else Vector3(-5.6, 0.0, 5.6))
		if absf(along_from) > 2.65:
			return near_mouth
		return far_mouth

	# 3. Mesmo lado do rio: evita cortar curvas sinuosas do meandro entrando na água
	var side: float = 1.0 if s_from >= 0.0 else -1.0
	var worst_dist: float = 99999.0
	var worst_pt: Vector3 = Vector3.ZERO
	var hits_water: bool = false
	for frac in [0.25, 0.50, 0.75]:
		var probe: Vector3 = from_p.lerp(to_p, frac)
		if is_in_river_water(probe.x, probe.z, 0.45):
			var rd: float = river_distance_at(probe.x, probe.z)
			if rd < worst_dist:
				worst_dist = rd
				worst_pt = probe
				hits_water = true
	if hits_water:
		return _push_point_to_bank(worst_pt, side, RIVER_BANK_DIST + 1.25)

	return to_p


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

		if _game_manager != null:
			for u in _game_manager.units:
				if u == self or not is_instance_valid(u) or u.is_queued_for_deletion() or u._dead:
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

		# Parapeitos laterais e corredor das 3 pontes sobre o rio
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

		p.x = clampf(p.x, -86.0, 86.0)
		p.z = clampf(p.z, -86.0, 86.0)

	return p


func _compute_separation(flat_pos: Vector3) -> Vector3:
	if _game_manager == null:
		return Vector3.ZERO
	var push: Vector3 = Vector3.ZERO
	var min_sep: float = body_radius * 2.5
	var min_sep_sq: float = min_sep * min_sep
	for u in _game_manager.units:
		if u == self or not is_instance_valid(u) or u.is_queued_for_deletion():
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
		return u.team != team and u.hp > 0.0 and not u._dead
	if node is RTSBuilding:
		var b: RTSBuilding = node as RTSBuilding
		return b.team != team and b.hp > 0.0 and not b._dead
	return false


func _find_nearest_enemy(radius: float) -> Node3D:
	if _game_manager == null:
		return null
	var best: Node3D = null
	var best_d: float = radius
	for u in _game_manager.units:
		if not _is_valid_enemy(u):
			continue
		var d: float = _flat_distance(global_position, u.global_position)
		if d < best_d:
			best_d = d
			best = u
	if best != null:
		return best
	for b in _game_manager.buildings:
		if not _is_valid_enemy(b):
			continue
		var d: float = _flat_distance(global_position, b.global_position)
		if d < best_d:
			best_d = d
			best = b
	return best


func _find_nearest_town_center() -> RTSBuilding:
	if _game_manager == null:
		return null
	var best: RTSBuilding = null
	var best_d: float = 99999.0
	for b in _game_manager.buildings:
		if not is_instance_valid(b) or b.is_queued_for_deletion():
			continue
		if b.team == team and b.building_type == "town_center" and b.is_constructed:
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
		if not is_instance_valid(r) or r.is_queued_for_deletion():
			continue
		if r.resource_type != r_type:
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
		if not is_instance_valid(b) or b.is_queued_for_deletion():
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
	move_target = sanitize_destination(dest)
	state = State.MOVING


func command_attack_move(dest: Vector3) -> void:
	target_enemy = null
	target_resource = null
	target_building = null
	_stuck_timer = 0.0
	move_target = sanitize_destination(dest)
	state = State.ATTACK_MOVING


func command_attack(enemy: Variant) -> void:
	if not _is_valid_enemy(enemy):
		return
	target_resource = null
	target_building = null
	_stuck_timer = 0.0
	target_enemy = enemy
	state = State.CHASING


func command_gather(res: Variant) -> void:
	if unit_type != "worker" or res == null or not is_instance_valid(res) or res.is_queued_for_deletion():
		return
	target_enemy = null
	target_building = null
	_stuck_timer = 0.0
	target_resource = res
	_last_resource_pos = res.global_position
	_last_resource_type = res.resource_type
	_gather_timer = 0.0
	if carrying_amount > 0 and carrying_type != res.resource_type:
		state = State.RETURNING_RESOURCE
	else:
		state = State.GATHERING


func command_auto_gather_near(r_type: String = "") -> void:
	if unit_type != "worker" or _game_manager == null:
		return
	var best: RTSResourceNode = null
	var best_d: float = 99999.0
	for r in _game_manager.resources:
		if not is_instance_valid(r) or r.is_queued_for_deletion():
			continue
		if r_type != "" and r.resource_type != r_type:
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
	target_building = b
	state = State.BUILDING


func command_stop() -> void:
	target_enemy = null
	target_resource = null
	target_building = null
	_stuck_timer = 0.0
	velocity = Vector3.ZERO
	state = State.IDLE


func set_selected(selected: bool) -> void:
	_is_selected = selected
	if _selection_ring != null:
		_selection_ring.visible = selected


func get_display_name() -> String:
	var cfg: Dictionary = STATS.get(unit_type, STATS["soldier"])
	return String(cfg["name"])


func get_state_label() -> String:
	match state:
		State.IDLE:
			return "Ocioso"
		State.MOVING:
			return "Marchando"
		State.ATTACK_MOVING:
			return "Patrulha de Ataque"
		State.GATHERING:
			return "Coletando Recurso"
		State.RETURNING_RESOURCE:
			return "Entregando Recurso"
		State.BUILDING:
			return "Construindo / Reparando"
		State.CHASING:
			return "Perseguindo Inimigo"
		State.ATTACKING:
			return "Em Combate"
	return "Ocioso"


func take_damage(amount: float, attacker: Variant = null) -> void:
	if _dead:
		return
	var mitigated: float = maxf(2.0, amount - float(armor) * 0.5)
	hp = maxf(0.0, hp - mitigated)
	_update_hp_bar()

	if state == State.IDLE and _is_valid_enemy(attacker):
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
	velocity = Vector3.ZERO
	collision_layer = 0
	remove_from_group("rts_units")
	if _selection_ring != null:
		_selection_ring.visible = false
	if _team_ring != null:
		_team_ring.visible = false
	if _hp_root != null:
		_hp_root.visible = false
	if _carry_gold_mesh != null:
		_carry_gold_mesh.visible = false
	if _carry_wood_mesh != null:
		_carry_wood_mesh.visible = false

	if _game_manager != null and _game_manager.has_method("on_unit_destroyed"):
		_game_manager.on_unit_destroyed(self)

	if _anim_player != null and _anim_player.has_animation("Death"):
		_play_anim("Death", 0.08, 1.0, true)
		_death_timer = 1.15
	else:
		queue_free()
