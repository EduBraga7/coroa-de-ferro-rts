extends StaticBody3D
class_name RTSBuilding

## Estrutura construtível no RTS (Salão Real, Casa, Quartel, Torre de Vigia).

const STATS: Dictionary = {
	"town_center": {
		"name": "Salão Real",
		"gold": 300,
		"wood": 250,
		"hp": 1400.0,
		"armor": 4,
		"build_time": 26.0,
		"radius": 3.5,
		"pop_bonus": 10,
		"attack_range": 14.0,
		"attack_damage": 16.0,
		"attack_cd": 1.65,
		"model": "res://assets/models/building_town_center.glb",
		"hp_height": 8.4,
		"hp_width": 3.4,
	},
	"house": {
		"name": "Casa",
		"gold": 40,
		"wood": 80,
		"hp": 420.0,
		"armor": 1,
		"build_time": 10.0,
		"radius": 2.0,
		"pop_bonus": 8,
		"attack_range": 0.0,
		"attack_damage": 0.0,
		"attack_cd": 0.0,
		"model": "res://assets/models/building_house.glb",
		"hp_height": 4.4,
		"hp_width": 2.1,
	},
	"barracks": {
		"name": "Quartel",
		"gold": 120,
		"wood": 150,
		"hp": 850.0,
		"armor": 2,
		"build_time": 16.0,
		"radius": 2.8,
		"pop_bonus": 0,
		"attack_range": 0.0,
		"attack_damage": 0.0,
		"attack_cd": 0.0,
		"model": "res://assets/models/building_barracks.glb",
		"hp_height": 5.3,
		"hp_width": 2.8,
	},
	"tower": {
		"name": "Torre de Vigia",
		"gold": 100,
		"wood": 120,
		"hp": 680.0,
		"armor": 3,
		"build_time": 14.0,
		"radius": 1.8,
		"pop_bonus": 0,
		"attack_range": 18.5,
		"attack_damage": 24.0,
		"attack_cd": 1.35,
		"model": "res://assets/models/building_tower.glb",
		"hp_height": 8.6,
		"hp_width": 2.2,
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

var production_queue: Array[String] = []
var production_timer: float = 0.0
var current_produce_time: float = 1.0
var rally_point: Vector3 = Vector3.ZERO
var has_custom_rally: bool = false

var attack_range: float = 0.0
var attack_damage: float = 0.0
var attack_cooldown: float = 1.5
var _attack_timer: float = 0.0
var _tax_timer: float = 0.0
var _is_selected: bool = false
var _dead: bool = false

var _game_manager: Node = null
var _visual_root: Node3D
var _scaffolding_root: Node3D
var _selection_ring: MeshInstance3D
var _team_ring: MeshInstance3D
var _rally_marker: MeshInstance3D
var _warm_light: OmniLight3D
var _hp_root: Node3D
var _hp_fill: MeshInstance3D
var _hp_width: float = 2.4


func setup(b_type: String, p_team: int, start_built: bool, gm: Node) -> void:
	building_type = b_type
	team = p_team
	_game_manager = gm

	var cfg: Dictionary = STATS.get(building_type, STATS["house"])
	max_hp = float(cfg["hp"])
	armor = int(cfg["armor"])
	build_time = float(cfg["build_time"])
	footprint_radius = float(cfg["radius"])
	pop_bonus = int(cfg["pop_bonus"])
	attack_range = float(cfg["attack_range"])
	attack_damage = float(cfg["attack_damage"])
	attack_cooldown = float(cfg["attack_cd"])
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
	_update_construction_visuals()
	_update_hp_bar()


func _ready() -> void:
	if rally_point == Vector3.ZERO:
		rally_point = global_position + Vector3(0.0, 0.0, footprint_radius + 2.6)
		if team == 0:
			rally_point = global_position + Vector3(footprint_radius + 2.2, 0.0, -(footprint_radius + 2.2))
		else:
			rally_point = global_position + Vector3(-(footprint_radius + 2.2), 0.0, footprint_radius + 2.2)


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

	# Bandeira / Estandarte colorido do time no topo ou lateral
	var team_col: Color = Color(0.18, 0.55, 0.98) if team == 0 else Color(0.92, 0.22, 0.18)
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
	if building_type == "town_center":
		pole_pos = Vector3(0.0, 7.2, 0.0)
	elif building_type == "tower":
		pole_pos = Vector3(0.0, 8.2, 0.0)
	banner_pole.position = pole_pos
	_visual_root.add_child(banner_pole)

	var flag: MeshInstance3D = MeshInstance3D.new()
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
	_visual_root.add_child(flag)

	# Luz acolhedora quente da estrutura (apenas Salão Real e Quartel, com fade por distância)
	if building_type == "town_center" or building_type == "barracks":
		_warm_light = OmniLight3D.new()
		_warm_light.light_color = Color(1.0, 0.72, 0.34)
		_warm_light.light_energy = 1.55 if building_type == "town_center" else 1.1
		_warm_light.omni_range = 9.5 if building_type == "town_center" else 7.5
		_warm_light.omni_attenuation = 1.4
		_warm_light.shadow_enabled = false
		_warm_light.distance_fade_enabled = true
		_warm_light.distance_fade_begin = 48.0
		_warm_light.distance_fade_length = 12.0
		_warm_light.position = Vector3(0.0, 2.3, footprint_radius * 0.78)
		_warm_light.visible = is_constructed
		add_child(_warm_light)

	# Anel sutil de cor do time na base
	_team_ring = MeshInstance3D.new()
	var t_torus: TorusMesh = TorusMesh.new()
	t_torus.inner_radius = footprint_radius * 0.99
	t_torus.outer_radius = footprint_radius * 1.05
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
	s_torus.inner_radius = footprint_radius * 1.07
	s_torus.outer_radius = footprint_radius * 1.22
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

	if _hp_root != null:
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

	# Produção de unidades na fila
	if production_queue.size() > 0:
		var u_type: String = production_queue[0]
		if current_produce_time <= 0.0 and _game_manager != null:
			current_produce_time = _game_manager.get_unit_train_time(u_type)
		production_timer += delta
		if production_timer >= current_produce_time:
			var pop_cost: int = _game_manager.get_unit_pop_cost(u_type) if _game_manager != null else 1
			if _game_manager != null and _game_manager.has_pop_space(team, pop_cost):
				production_queue.pop_front()
				production_timer = 0.0
				if production_queue.size() > 0:
					current_produce_time = _game_manager.get_unit_train_time(production_queue[0])
				else:
					current_produce_time = 0.0
				_spawn_trained_unit(u_type)

	# Renda feudal das Casas (+2 ouro a cada 5s)
	if building_type == "house" and _game_manager != null:
		_tax_timer += delta
		if _tax_timer >= 5.0:
			_tax_timer -= 5.0
			_game_manager.add_resource(team, "gold", 2)

	# Defesa automática (Torres e Salão Real)
	if attack_damage > 0.0 and attack_range > 0.0:
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			var enemy: Node3D = _find_nearest_enemy()
			if enemy != null:
				_attack_timer = attack_cooldown
				_fire_arrow(enemy)
			else:
				_attack_timer = 0.35


func _spawn_trained_unit(u_type: String) -> void:
	if _game_manager == null:
		return
	var dir_to_rally: Vector3 = (rally_point - global_position)
	dir_to_rally.y = 0.0
	if dir_to_rally.length_squared() < 0.01:
		dir_to_rally = Vector3(1.0, 0.0, -1.0) if team == 0 else Vector3(-1.0, 0.0, 1.0)
	dir_to_rally = dir_to_rally.normalized()
	var spawn_pos: Vector3 = global_position + dir_to_rally * (footprint_radius + 1.45)
	var unit: Node = _game_manager.spawn_unit(u_type, spawn_pos, team)
	if unit != null:
		if u_type == "worker" and unit.has_method("command_auto_gather_near"):
			# Se ponto de reunião está perto de um recurso, coleta direto; senão vai pro rally
			if not has_custom_rally:
				unit.command_move(rally_point)
			else:
				unit.command_move(rally_point)
		elif unit.has_method("command_move"):
			unit.command_move(rally_point)


func _find_nearest_enemy() -> Node3D:
	if _game_manager == null:
		return null
	var best: Node3D = null
	var best_dist: float = attack_range
	for u in _game_manager.units:
		if not is_instance_valid(u) or u.is_queued_for_deletion():
			continue
		if u.team == team or u.hp <= 0.0:
			continue
		var d: float = global_position.distance_to(u.global_position)
		if d <= best_dist:
			best_dist = d
			best = u
	return best


func _fire_arrow(target: Variant) -> void:
	if _game_manager == null or target == null or not is_instance_valid(target):
		return
	var from_pos: Vector3 = global_position + Vector3(0.0, 6.2 if building_type == "tower" else 5.0, 0.0)
	_game_manager.spawn_projectile(from_pos, target, attack_damage, self, team)


func advance_construction(delta_time: float) -> void:
	if is_constructed or _dead:
		return
	var step: float = delta_time / maxf(1.0, build_time)
	build_progress = minf(1.0, build_progress + step)
	hp = minf(max_hp, hp + max_hp * 0.85 * step)
	_update_construction_visuals()
	_update_hp_bar()

	if build_progress >= 1.0:
		is_constructed = true
		hp = max_hp
		_update_construction_visuals()
		_update_hp_bar()
		if _game_manager != null and _game_manager.has_method("on_building_completed"):
			_game_manager.on_building_completed(self)


func repair(delta_time: float) -> void:
	if not is_constructed or hp >= max_hp or _dead:
		return
	hp = minf(max_hp, hp + 35.0 * delta_time)
	_update_hp_bar()


func _update_construction_visuals() -> void:
	if _visual_root != null:
		var sy: float = 1.0 if is_constructed else lerpf(0.22, 0.98, build_progress)
		_visual_root.scale = Vector3(1.0, sy, 1.0)
	if _scaffolding_root != null:
		_scaffolding_root.visible = not is_constructed
	if _warm_light != null:
		_warm_light.visible = is_constructed


func can_train(unit_type: String) -> bool:
	if not is_constructed:
		return false
	if building_type == "town_center":
		return unit_type == "worker"
	if building_type == "barracks":
		return unit_type in ["soldier", "archer", "knight"]
	return false


func queue_unit(unit_type: String) -> bool:
	if not can_train(unit_type) or production_queue.size() >= 5 or _game_manager == null:
		return false
	if not _game_manager.spend_for_unit(team, unit_type):
		return false
	production_queue.append(unit_type)
	if production_queue.size() == 1:
		production_timer = 0.0
		current_produce_time = _game_manager.get_unit_train_time(unit_type)
	return true


func cancel_last_production() -> void:
	if production_queue.is_empty() or _game_manager == null:
		return
	var removed: String = production_queue.pop_back()
	_game_manager.refund_unit(team, removed)
	if production_queue.is_empty():
		production_timer = 0.0
		current_produce_time = 0.0


func get_production_progress() -> float:
	if production_queue.is_empty() or current_produce_time <= 0.0:
		return 0.0
	return clampf(production_timer / current_produce_time, 0.0, 1.0)


func set_rally_point(world_pos: Vector3) -> void:
	rally_point = Vector3(world_pos.x, 0.0, world_pos.z)
	has_custom_rally = true


func set_selected(selected: bool) -> void:
	_is_selected = selected
	if _selection_ring != null:
		_selection_ring.visible = selected
	if _rally_marker != null:
		_rally_marker.visible = selected and team == 0 and (building_type == "town_center" or building_type == "barracks")


func get_display_name() -> String:
	var cfg: Dictionary = STATS.get(building_type, STATS["house"])
	return String(cfg["name"])


func take_damage(amount: float, attacker: Variant = null) -> void:
	if _dead:
		return
	var mitigated: float = maxf(2.0, amount - float(armor) * 0.5)
	hp = maxf(0.0, hp - mitigated)
	_update_hp_bar()

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


func _die() -> void:
	if _dead:
		return
	_dead = true
	if _game_manager != null and _game_manager.has_method("on_building_destroyed"):
		_game_manager.on_building_destroyed(self)
	queue_free()
