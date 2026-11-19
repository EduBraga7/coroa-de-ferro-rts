extends Node
class_name GameManager

## Controlador central da partida RTS: economia, seleção, formações, ghost de construção e vitória/derrota.

signal resources_changed()
signal selection_changed()
signal alert_posted(message: String, color: Color)
signal game_over(player_won: bool, stats: Dictionary)

const AGE_UPGRADE_GOLD: int = 250
const AGE_UPGRADE_WOOD: int = 200
const MAX_POP_LIMIT: int = 80

var units: Array[RTSUnit] = []
var buildings: Array[RTSBuilding] = []
var resources: Array[RTSResourceNode] = []
var static_obstacles: Array[Dictionary] = []

var selected_units: Array[RTSUnit] = []
var selected_building: Variant = null
var selected_resource: Variant = null

var team_data: Dictionary = {
	0: {"gold": 450, "wood": 350, "pop_used": 0, "pop_cap": 0, "age": 1},
	1: {"gold": 450, "wood": 350, "pop_used": 0, "pop_cap": 0, "age": 1},
}

var stats: Dictionary = {
	"units_trained": 0,
	"enemies_slain": 0,
	"buildings_built": 0,
	"gold_gathered": 0,
	"wood_gathered": 0,
}

var match_time: float = 0.0
var match_started: bool = false
var is_game_over: bool = false
var attack_move_mode: bool = false
var pending_building_type: String = ""

var world_root: Node3D = null
var camera_rig: RTSCamera = null
var sfx: SFXManager = null
var ai_controller: Node = null
var hud: Node = null

var _ghost_node: Node3D = null
var _ghost_mat: StandardMaterial3D = null
var _is_dragging_box: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _drag_current: Vector2 = Vector2.ZERO
var _last_click_time: float = 0.0
var _last_clicked_unit: Variant = null
var _idle_worker_cycle_idx: int = 0
var _control_groups: Dictionary = {}
var _last_group_tap_time: float = 0.0
var _last_group_tap_id: int = -1


func _ready() -> void:
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.albedo_color = Color(0.25, 0.95, 0.45, 0.52)
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func _process(delta: float) -> void:
	if match_started and not is_game_over:
		match_time += delta
	if pending_building_type != "" and _ghost_node != null:
		_update_ghost_position()
	if camera_rig != null:
		camera_rig.block_edge_pan = is_drawing_selection_box()


# ==============================================================================
# ECONOMIA E POPULAÇÃO
# ==============================================================================

func get_team_gold(team: int) -> int:
	var d: Dictionary = team_data[team]
	return int(d["gold"])


func get_team_wood(team: int) -> int:
	var d: Dictionary = team_data[team]
	return int(d["wood"])


func get_team_pop_used(team: int) -> int:
	var d: Dictionary = team_data[team]
	return int(d["pop_used"])


func get_team_pop_cap(team: int) -> int:
	var d: Dictionary = team_data[team]
	return mini(MAX_POP_LIMIT, int(d["pop_cap"]))


func get_team_age(team: int) -> int:
	var d: Dictionary = team_data[team]
	return int(d["age"])


func add_resource(team: int, r_type: String, amount: int) -> void:
	if amount <= 0:
		return
	var d: Dictionary = team_data[team]
	d[r_type] = int(d[r_type]) + amount
	if team == 0:
		if r_type == "gold":
			stats["gold_gathered"] = int(stats["gold_gathered"]) + amount
		else:
			stats["wood_gathered"] = int(stats["wood_gathered"]) + amount
		resources_changed.emit()


func can_afford(team: int, gold_cost: int, wood_cost: int) -> bool:
	var d: Dictionary = team_data[team]
	return int(d["gold"]) >= gold_cost and int(d["wood"]) >= wood_cost


func spend(team: int, gold_cost: int, wood_cost: int) -> bool:
	if not can_afford(team, gold_cost, wood_cost):
		return false
	var d: Dictionary = team_data[team]
	d["gold"] = int(d["gold"]) - gold_cost
	d["wood"] = int(d["wood"]) - wood_cost
	if team == 0:
		resources_changed.emit()
	return true


func can_afford_building(team: int, b_type: String) -> bool:
	var cfg: Dictionary = RTSBuilding.STATS.get(b_type, {})
	if cfg.is_empty():
		return false
	return can_afford(team, int(cfg["gold"]), int(cfg["wood"]))


func can_afford_unit(team: int, u_type: String) -> bool:
	var cfg: Dictionary = RTSUnit.STATS.get(u_type, {})
	if cfg.is_empty():
		return false
	return can_afford(team, int(cfg["gold"]), int(cfg["wood"]))


func spend_for_unit(team: int, u_type: String) -> bool:
	var cfg: Dictionary = RTSUnit.STATS.get(u_type, {})
	if cfg.is_empty():
		return false
	return spend(team, int(cfg["gold"]), int(cfg["wood"]))


func refund_unit(team: int, u_type: String) -> void:
	var cfg: Dictionary = RTSUnit.STATS.get(u_type, {})
	if cfg.is_empty():
		return
	var d: Dictionary = team_data[team]
	d["gold"] = int(d["gold"]) + int(cfg["gold"])
	d["wood"] = int(d["wood"]) + int(cfg["wood"])
	if team == 0:
		resources_changed.emit()


func get_unit_train_time(u_type: String) -> float:
	var cfg: Dictionary = RTSUnit.STATS.get(u_type, {})
	return float(cfg.get("train_time", 6.0))


func get_unit_pop_cost(u_type: String) -> int:
	var cfg: Dictionary = RTSUnit.STATS.get(u_type, {})
	return int(cfg.get("pop", 1))


func has_pop_space(team: int, needed: int) -> bool:
	return get_team_pop_used(team) + needed <= get_team_pop_cap(team)


func recalculate_population() -> void:
	for t in [0, 1]:
		var d: Dictionary = team_data[t]
		d["pop_used"] = 0
		d["pop_cap"] = 0
	for u in units:
		if is_instance_valid(u) and not u.is_queued_for_deletion() and u.hp > 0.0:
			var d: Dictionary = team_data[u.team]
			d["pop_used"] = int(d["pop_used"]) + u.pop_cost
	for b in buildings:
		if is_instance_valid(b) and not b.is_queued_for_deletion() and b.is_constructed and b.hp > 0.0:
			var d: Dictionary = team_data[b.team]
			d["pop_cap"] = int(d["pop_cap"]) + b.pop_bonus
	resources_changed.emit()


func upgrade_age(team: int) -> bool:
	if get_team_age(team) >= 2:
		return false
	if not spend(team, AGE_UPGRADE_GOLD, AGE_UPGRADE_WOOD):
		if team == 0:
			post_alert("Recursos insuficientes para Era Real (250 Ouro, 200 Madeira).", Color(1.0, 0.45, 0.35))
		return false
	var d: Dictionary = team_data[team]
	d["age"] = 2
	for u in units:
		if is_instance_valid(u) and not u.is_queued_for_deletion() and u.team == team:
			u.apply_age_bonus()
	if team == 0:
		post_alert("Avanço Concluído: ERA REAL! Todas as tropas receberam +25% Dano, +15% HP e +2 Armadura!", Color(1.0, 0.85, 0.3))
		if sfx != null:
			sfx.play_build_complete()
	else:
		post_alert("O Barão Corvo Vermelho avançou para a ERA REAL!", Color(1.0, 0.4, 0.3))
	resources_changed.emit()
	return true


# ==============================================================================
# SPAWN DE ENTIDADES
# ==============================================================================

func spawn_unit(u_type: String, pos: Vector3, team: int) -> RTSUnit:
	if world_root == null:
		return null
	var u: RTSUnit = RTSUnit.new()
	u.position = Vector3(clampf(pos.x, -85.0, 85.0), 0.0, clampf(pos.z, -85.0, 85.0))
	world_root.add_child(u)
	u.setup(u_type, team, self, get_team_age(team))
	units.append(u)
	if team == 0 and match_started:
		stats["units_trained"] = int(stats["units_trained"]) + 1
	recalculate_population()
	return u


func place_building_at(b_type: String, pos: Vector3, team: int, start_built: bool = false) -> RTSBuilding:
	if world_root == null:
		return null
	var b: RTSBuilding = RTSBuilding.new()
	b.position = Vector3(clampf(pos.x, -82.0, 82.0), 0.0, clampf(pos.z, -82.0, 82.0))
	world_root.add_child(b)
	b.setup(b_type, team, start_built, self)
	buildings.append(b)
	if team == 0 and match_started and not start_built:
		stats["buildings_built"] = int(stats["buildings_built"]) + 1
	recalculate_population()
	return b


func spawn_resource(r_type: String, pos: Vector3, amount: int = -1) -> RTSResourceNode:
	if world_root == null:
		return null
	var r: RTSResourceNode = RTSResourceNode.new()
	r.position = Vector3(pos.x, 0.0, pos.z)
	world_root.add_child(r)
	r.setup(r_type, amount, self)
	resources.append(r)
	return r


func register_static_obstacle(pos: Vector3, radius: float, kind: String = "prop") -> void:
	static_obstacles.append({"pos": Vector3(pos.x, 0.0, pos.z), "radius": radius, "kind": kind})


func spawn_projectile(from_pos: Vector3, target: Variant, damage: float, attacker: Variant, team: int) -> void:
	if world_root == null:
		return
	var p: RTSProjectile = RTSProjectile.new()
	world_root.add_child(p)
	p.launch(from_pos, target, damage, attacker, team)


func spawn_floating_text(pos: Vector3, text: String, color: Color) -> void:
	if world_root == null or DisplayServer.get_name() == "headless":
		return
	var lbl: Label3D = Label3D.new()
	lbl.text = text
	lbl.font_size = 38
	lbl.outline_size = 8
	lbl.modulate = color
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position = pos
	world_root.add_child(lbl)

	var tw: Tween = lbl.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", pos.y + 1.8, 1.1)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.1)
	tw.chain().tween_callback(lbl.queue_free)


func _spawn_order_ring(pos: Vector3, color: Color) -> void:
	if world_root == null or DisplayServer.get_name() == "headless":
		return
	var ring: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.78
	torus.rings = 20
	torus.ring_segments = 6
	ring.mesh = torus
	ring.position = Vector3(pos.x, 0.08, pos.z)
	ring.scale = Vector3(0.4, 0.15, 0.4)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	ring.material_override = mat
	world_root.add_child(ring)

	var tw: Tween = ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(1.5, 0.15, 1.5), 0.38)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.38)
	tw.chain().tween_callback(ring.queue_free)


# ==============================================================================
# EVENTOS DE ENTIDADES E VITÓRIA / DERROTA
# ==============================================================================

func on_building_completed(b: RTSBuilding) -> void:
	recalculate_population()
	if b.team == 0:
		post_alert("Construção concluída: %s" % b.get_display_name(), Color(0.45, 0.92, 0.55))
		if sfx != null:
			sfx.play_build_complete()
	selection_changed.emit()


func on_building_destroyed(b: RTSBuilding) -> void:
	buildings.erase(b)
	for unit in units:
		if is_instance_valid(unit):
			if unit.target_enemy == b:
				unit.target_enemy = null
			if unit.target_building == b:
				unit.target_building = null
	if selected_building == b:
		selected_building = null
		selection_changed.emit()
	recalculate_population()
	if match_started:
		_check_victory_defeat()


func on_unit_destroyed(u: RTSUnit) -> void:
	units.erase(u)
	for unit in units:
		if is_instance_valid(unit) and unit.target_enemy == u:
			unit.target_enemy = null
	if _last_clicked_unit == u:
		_last_clicked_unit = null
	if u in selected_units:
		selected_units.erase(u)
		selection_changed.emit()
	if u.team == 1 and match_started:
		stats["enemies_slain"] = int(stats["enemies_slain"]) + 1
	recalculate_population()


func on_resource_depleted(r: RTSResourceNode) -> void:
	resources.erase(r)
	for unit in units:
		if is_instance_valid(unit) and unit.target_resource == r:
			unit.target_resource = null
	if selected_resource == r:
		selected_resource = null
		selection_changed.emit()


func on_entity_damaged(victim: Variant, attacker: Variant) -> void:
	if victim == null or not is_instance_valid(victim):
		return
	if ai_controller != null and ai_controller.has_method("on_ai_entity_damaged"):
		if (victim is RTSUnit and (victim as RTSUnit).team == 1) or (victim is RTSBuilding and (victim as RTSBuilding).team == 1):
			ai_controller.on_ai_entity_damaged(victim, attacker)


func _check_victory_defeat() -> void:
	if is_game_over or not match_started:
		return
	var p_buildings: int = 0
	var ai_buildings: int = 0
	for b in buildings:
		if not is_instance_valid(b) or b.is_queued_for_deletion() or b.hp <= 0.0:
			continue
		if b.team == 0:
			p_buildings += 1
		elif b.team == 1:
			ai_buildings += 1

	if ai_buildings == 0:
		is_game_over = true
		game_over.emit(true, stats)
	elif p_buildings == 0:
		is_game_over = true
		game_over.emit(false, stats)


# ==============================================================================
# MODO DE CONSTRUÇÃO (GHOST 3D)
# ==============================================================================

func start_building_placement(b_type: String) -> void:
	cancel_building_placement()
	if not can_afford_building(0, b_type):
		var cfg: Dictionary = RTSBuilding.STATS.get(b_type, {})
		post_alert("Recursos insuficientes! Necessário: %d Ouro e %d Madeira." % [int(cfg.get("gold", 0)), int(cfg.get("wood", 0))], Color(1.0, 0.45, 0.35))
		return

	pending_building_type = b_type
	attack_move_mode = false
	_ghost_node = Node3D.new()
	var cfg_b: Dictionary = RTSBuilding.STATS.get(b_type, RTSBuilding.STATS["house"])
	var packed: PackedScene = load(String(cfg_b["model"])) as PackedScene
	if packed != null:
		var inst: Node3D = packed.instantiate() as Node3D
		if inst != null:
			_apply_material_recursive(inst, _ghost_mat)
			_ghost_node.add_child(inst)
	world_root.add_child(_ghost_node)
	_update_ghost_position()
	post_alert("Clique com o botão esquerdo no mapa para posicionar %s (Botão direito/ESC cancela)." % String(cfg_b["name"]), Color(0.95, 0.85, 0.4))


func cancel_building_placement() -> void:
	pending_building_type = ""
	if is_instance_valid(_ghost_node):
		_ghost_node.queue_free()
	_ghost_node = null


func _apply_material_recursive(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for ch in node.get_children():
		_apply_material_recursive(ch, mat)


func _update_ghost_position() -> void:
	if _ghost_node == null:
		return
	var ground_pos: Variant = _raycast_ground(get_viewport().get_mouse_position())
	if ground_pos == null:
		return
	var p: Vector3 = ground_pos as Vector3
	_ghost_node.global_position = Vector3(p.x, 0.0, p.z)
	var cfg: Dictionary = RTSBuilding.STATS.get(pending_building_type, RTSBuilding.STATS["house"])
	var rad: float = float(cfg["radius"])
	var ok: bool = is_valid_building_spot(_ghost_node.global_position, rad)
	_ghost_mat.albedo_color = Color(0.25, 0.95, 0.45, 0.52) if ok else Color(0.95, 0.25, 0.22, 0.55)


func is_valid_building_spot(pos: Vector3, radius: float) -> bool:
	if absf(pos.x) > 80.0 or absf(pos.z) > 80.0:
		return false
	# Não construir dentro do rio ou pontes (faixa x == z com meandro)
	if RTSUnit.river_distance_at(pos.x, pos.z) < 7.5 + radius:
		return false
	for b in buildings:
		if not is_instance_valid(b) or b.is_queued_for_deletion():
			continue
		if Vector2(pos.x, pos.z).distance_to(Vector2(b.global_position.x, b.global_position.z)) < (radius + b.footprint_radius + 1.1):
			return false
	for r in resources:
		if not is_instance_valid(r) or r.is_queued_for_deletion():
			continue
		if Vector2(pos.x, pos.z).distance_to(Vector2(r.global_position.x, r.global_position.z)) < (radius + r.collision_radius + 0.8):
			return false
	for obs in static_obstacles:
		var op: Vector3 = obs["pos"]
		var orad: float = float(obs["radius"])
		if Vector2(pos.x, pos.z).distance_to(Vector2(op.x, op.z)) < (radius + orad + 0.6):
			return false
	return true


func _confirm_building_placement() -> void:
	if pending_building_type == "" or _ghost_node == null:
		return
	var pos: Vector3 = _ghost_node.global_position
	var cfg: Dictionary = RTSBuilding.STATS.get(pending_building_type, RTSBuilding.STATS["house"])
	var rad: float = float(cfg["radius"])
	if not is_valid_building_spot(pos, rad):
		post_alert("Local inválido! Escolha um terreno livre fora do rio e longe de outras estruturas.", Color(1.0, 0.4, 0.3))
		return

	var gold_c: int = int(cfg["gold"])
	var wood_c: int = int(cfg["wood"])
	if not spend(0, gold_c, wood_c):
		post_alert("Recursos insuficientes!", Color(1.0, 0.4, 0.3))
		cancel_building_placement()
		return

	var b_type: String = pending_building_type
	cancel_building_placement()
	var new_b: RTSBuilding = place_building_at(b_type, pos, 0, false)
	if new_b != null:
		post_alert("Construção iniciada: %s" % new_b.get_display_name(), Color(0.55, 0.85, 1.0))
		_assign_worker_to_build(new_b)
		if sfx != null:
			sfx.play_command()


func _assign_worker_to_build(b: RTSBuilding) -> void:
	var assigned: int = 0
	for u in selected_units:
		if is_instance_valid(u) and u.team == 0 and u.unit_type == "worker":
			u.command_build(b)
			assigned += 1
	if assigned > 0:
		return
	# Busca camponês ocioso mais próximo, ou qualquer camponês do jogador mais próximo
	var best_worker: RTSUnit = null
	var best_score: float = 999999.0
	for u in units:
		if not is_instance_valid(u) or u.is_queued_for_deletion() or u.team != 0 or u.unit_type != "worker":
			continue
		var d: float = u.global_position.distance_to(b.global_position)
		if u.state != RTSUnit.State.IDLE:
			d += 120.0
		if d < best_score:
			best_score = d
			best_worker = u
	if best_worker != null:
		best_worker.command_build(b)


# ==============================================================================
# INPUT DE SELEÇÃO, CAIXA 2D, ORDENS E GRUPOS
# ==============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if is_game_over:
		return

	if event is InputEventKey:
		var ek: InputEventKey = event as InputEventKey
		if ek.pressed and not ek.echo:
			_handle_hotkey(ek)

	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if pending_building_type != "":
					_confirm_building_placement()
					return
				if attack_move_mode and selected_units.size() > 0:
					_issue_attack_move_click(mb.position)
					attack_move_mode = false
					return
				_is_dragging_box = true
				_drag_start = mb.position
				_drag_current = mb.position
			else:
				if _is_dragging_box:
					_is_dragging_box = false
					var dist: float = _drag_start.distance_to(mb.position)
					if dist > 12.0:
						_select_units_in_rect(_make_rect(_drag_start, mb.position))
					else:
						_handle_single_left_click(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if pending_building_type != "":
				cancel_building_placement()
				return
			if attack_move_mode:
				attack_move_mode = false
			_handle_right_click(mb.position)

	elif event is InputEventMouseMotion and _is_dragging_box:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		_drag_current = mm.position


func _handle_hotkey(ek: InputEventKey) -> void:
	if ek.keycode == KEY_ESCAPE:
		if pending_building_type != "":
			cancel_building_placement()
		elif attack_move_mode:
			attack_move_mode = false
		else:
			clear_selection()
		return

	if ek.keycode == KEY_SPACE or ek.keycode == KEY_HOME:
		focus_camera_on_base()
		return

	if ek.keycode == KEY_TAB:
		select_next_idle_worker()
		return

	if ek.keycode == KEY_F and camera_rig != null:
		if camera_rig.is_following():
			camera_rig.stop_following()
			post_alert("Câmera liberada.", Color(0.75, 0.9, 1.0))
		elif selected_units.size() > 0 and is_instance_valid(selected_units[0]):
			camera_rig.start_following(selected_units[0])
			post_alert("Seguindo unidade (mova a câmera ou pressione [F] para soltar).", Color(0.6, 0.92, 1.0))
		return

	# Grupos de controle (Ctrl + 1..5 / 1..5)
	var group_keys: Array[int] = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5]
	var g_idx: int = group_keys.find(ek.keycode)
	if g_idx != -1:
		var grp_id: int = g_idx + 1
		if ek.ctrl_pressed:
			_save_control_group(grp_id)
		else:
			_recall_control_group(grp_id)
		return


func _save_control_group(grp_id: int) -> void:
	var valid: Array[RTSUnit] = []
	for u in selected_units:
		if is_instance_valid(u) and not u.is_queued_for_deletion() and u.team == 0:
			valid.append(u)
	_control_groups[grp_id] = valid
	if valid.size() > 0:
		post_alert("Grupo %d salvo (%d unidades)." % [grp_id, valid.size()], Color(0.7, 0.88, 1.0))


func _recall_control_group(grp_id: int) -> void:
	if not _control_groups.has(grp_id):
		return
	var raw: Array = _control_groups[grp_id]
	var alive: Array[RTSUnit] = []
	for u in raw:
		if is_instance_valid(u) and not u.is_queued_for_deletion() and u.hp > 0.0:
			alive.append(u)
	_control_groups[grp_id] = alive
	if alive.is_empty():
		return
	clear_selection()
	for u in alive:
		u.set_selected(true)
		selected_units.append(u)
	selection_changed.emit()
	if sfx != null:
		sfx.play_select()

	var now: float = Time.get_ticks_msec() * 0.001
	if _last_group_tap_id == grp_id and (now - _last_group_tap_time) < 0.45 and camera_rig != null:
		camera_rig.focus_on(alive[0].global_position)
	_last_group_tap_id = grp_id
	_last_group_tap_time = now


func is_drawing_selection_box() -> bool:
	return _is_dragging_box and _drag_start.distance_to(_drag_current) > 12.0


func get_selection_box_rect() -> Rect2:
	return _make_rect(_drag_start, _drag_current)


func _make_rect(a: Vector2, b: Vector2) -> Rect2:
	var tl: Vector2 = Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var sz: Vector2 = Vector2(absf(b.x - a.x), absf(b.y - a.y))
	return Rect2(tl, sz)


func clear_selection() -> void:
	for u in selected_units:
		if is_instance_valid(u):
			u.set_selected(false)
	selected_units.clear()
	if is_instance_valid(selected_building):
		selected_building.set_selected(false)
	selected_building = null
	if is_instance_valid(selected_resource):
		selected_resource.set_selected(false)
	selected_resource = null
	selection_changed.emit()


func _select_units_in_rect(rect: Rect2) -> void:
	if camera_rig == null or camera_rig.camera == null:
		return
	var cam: Camera3D = camera_rig.camera
	var add_mode: bool = Input.is_key_pressed(KEY_SHIFT)
	if not add_mode:
		clear_selection()
	else:
		if is_instance_valid(selected_building):
			selected_building.set_selected(false)
			selected_building = null
		if is_instance_valid(selected_resource):
			selected_resource.set_selected(false)
			selected_resource = null

	for u in units:
		if not is_instance_valid(u) or u.is_queued_for_deletion() or u.team != 0 or u.hp <= 0.0:
			continue
		if cam.is_position_behind(u.global_position):
			continue
		var screen_pt: Vector2 = cam.unproject_position(u.global_position + Vector3(0.0, 0.7, 0.0))
		if rect.has_point(screen_pt):
			if not (u in selected_units):
				u.set_selected(true)
				selected_units.append(u)

	if selected_units.size() > 0 and sfx != null:
		sfx.play_select()
	selection_changed.emit()


func _handle_single_left_click(screen_pos: Vector2) -> void:
	var hit: Dictionary = _raycast_world(screen_pos)
	var add_mode: bool = Input.is_key_pressed(KEY_SHIFT)
	if hit.is_empty():
		if not add_mode:
			clear_selection()
		return

	var col: Object = hit.get("collider", null)
	if col is RTSUnit:
		var u: RTSUnit = col as RTSUnit
		var now: float = Time.get_ticks_msec() * 0.001
		if u.team == 0 and u == _last_clicked_unit and (now - _last_click_time) < 0.38:
			# Clique duplo: seleciona todas as unidades do mesmo tipo na tela
			_select_all_visible_of_type(u.unit_type)
			_last_clicked_unit = null
			return
		_last_clicked_unit = u
		_last_click_time = now

		if not add_mode or u.team != 0:
			clear_selection()
		if u.team == 0:
			if not (u in selected_units):
				u.set_selected(true)
				selected_units.append(u)
		else:
			u.set_selected(true)
			selected_units.append(u)
		if sfx != null:
			sfx.play_select()
		selection_changed.emit()
		return

	if col is RTSBuilding:
		var b: RTSBuilding = col as RTSBuilding
		clear_selection()
		selected_building = b
		b.set_selected(true)
		if sfx != null:
			sfx.play_select()
		selection_changed.emit()
		return

	if col is RTSResourceNode:
		var r: RTSResourceNode = col as RTSResourceNode
		clear_selection()
		selected_resource = r
		r.set_selected(true)
		if sfx != null:
			sfx.play_select()
		selection_changed.emit()
		return

	if not add_mode:
		clear_selection()


func _select_all_visible_of_type(u_type: String) -> void:
	if camera_rig == null or camera_rig.camera == null:
		return
	var cam: Camera3D = camera_rig.camera
	var vp_rect: Rect2 = get_viewport().get_visible_rect()
	clear_selection()
	for u in units:
		if not is_instance_valid(u) or u.team != 0 or u.unit_type != u_type or u.hp <= 0.0:
			continue
		if cam.is_position_behind(u.global_position):
			continue
		var pt: Vector2 = cam.unproject_position(u.global_position)
		if vp_rect.has_point(pt):
			u.set_selected(true)
			selected_units.append(u)
	if sfx != null:
		sfx.play_select()
	selection_changed.emit()


func _issue_attack_move_click(screen_pos: Vector2) -> void:
	var hit: Dictionary = _raycast_world(screen_pos)
	if hit.is_empty():
		return
	var col: Object = hit.get("collider", null)
	if (col is RTSUnit and (col as RTSUnit).team != 0) or (col is RTSBuilding and (col as RTSBuilding).team != 0):
		for u in selected_units:
			if is_instance_valid(u) and u.team == 0:
				u.command_attack(col as Node3D)
		_spawn_order_ring((col as Node3D).global_position, Color(1.0, 0.25, 0.22, 0.9))
	else:
		var pos: Vector3 = hit["position"]
		var offsets: Array[Vector3] = get_formation_offsets(selected_units.size())
		for i in range(selected_units.size()):
			var u: RTSUnit = selected_units[i]
			if is_instance_valid(u) and u.team == 0:
				u.command_attack_move(pos + offsets[i])
		_spawn_order_ring(pos, Color(1.0, 0.35, 0.25, 0.9))
	if sfx != null:
		sfx.play_command()


func _handle_right_click(screen_pos: Vector2) -> void:
	var hit: Dictionary = _raycast_world(screen_pos)
	if hit.is_empty():
		return

	var col: Object = hit.get("collider", null)
	var pos: Vector3 = hit["position"]

	# Definir ponto de reunião de prédio selecionado
	if is_instance_valid(selected_building) and selected_building.team == 0 and selected_units.is_empty():
		if selected_building.building_type == "town_center" or selected_building.building_type == "barracks":
			selected_building.set_rally_point(pos)
			_spawn_order_ring(pos, Color(1.0, 0.85, 0.25, 0.9))
			if sfx != null:
				sfx.play_command()
		return

	if selected_units.is_empty():
		return

	# Filtra apenas unidades do jogador
	var my_units: Array[RTSUnit] = []
	for u in selected_units:
		if is_instance_valid(u) and not u.is_queued_for_deletion() and u.team == 0:
			my_units.append(u)
	if my_units.is_empty():
		return

	# Clique direito em inimigo
	if (col is RTSUnit and (col as RTSUnit).team != 0) or (col is RTSBuilding and (col as RTSBuilding).team != 0):
		for u in my_units:
			u.command_attack(col as Node3D)
		_spawn_order_ring((col as Node3D).global_position, Color(1.0, 0.25, 0.25, 0.92))
		if sfx != null:
			sfx.play_command()
		return

	# Clique direito em recurso
	if col is RTSResourceNode:
		var res: RTSResourceNode = col as RTSResourceNode
		var workers_sent: int = 0
		for u in my_units:
			if u.unit_type == "worker":
				u.command_gather(res)
				workers_sent += 1
			else:
				u.command_move(res.global_position + Vector3(2.5, 0.0, 2.5))
		var ring_col: Color = Color(1.0, 0.85, 0.2, 0.9) if workers_sent > 0 else Color(0.3, 0.85, 1.0, 0.9)
		_spawn_order_ring(res.global_position, ring_col)
		if sfx != null:
			sfx.play_command()
		return

	# Clique direito em prédio aliado (construir ou reparar)
	if col is RTSBuilding and (col as RTSBuilding).team == 0:
		var ally_b: RTSBuilding = col as RTSBuilding
		if not ally_b.is_constructed or ally_b.hp < ally_b.max_hp:
			for u in my_units:
				if u.unit_type == "worker":
					u.command_build(ally_b)
			_spawn_order_ring(ally_b.global_position, Color(0.4, 0.95, 0.55, 0.9))
			if sfx != null:
				sfx.play_command()
			return

	# Movimento em formação no terreno
	var offsets: Array[Vector3] = get_formation_offsets(my_units.size())
	for i in range(my_units.size()):
		my_units[i].command_move(pos + offsets[i])
	_spawn_order_ring(pos, Color(0.32, 0.92, 0.48, 0.9))
	if sfx != null:
		sfx.play_command()


func issue_minimap_move(world_pos: Vector3) -> void:
	var my_units: Array[RTSUnit] = []
	for u in selected_units:
		if is_instance_valid(u) and not u.is_queued_for_deletion() and u.team == 0:
			my_units.append(u)
	if my_units.is_empty():
		if is_instance_valid(selected_building) and selected_building.team == 0:
			selected_building.set_rally_point(world_pos)
			_spawn_order_ring(world_pos, Color(1.0, 0.85, 0.25, 0.9))
		return
	var offsets: Array[Vector3] = get_formation_offsets(my_units.size())
	for i in range(my_units.size()):
		if attack_move_mode:
			my_units[i].command_attack_move(world_pos + offsets[i])
		else:
			my_units[i].command_move(world_pos + offsets[i])
	attack_move_mode = false
	_spawn_order_ring(world_pos, Color(0.32, 0.92, 0.48, 0.9))
	if sfx != null:
		sfx.play_command()


func get_formation_offsets(count: int) -> Array[Vector3]:
	var res: Array[Vector3] = []
	if count <= 1:
		res.append(Vector3.ZERO)
		return res
	var cols: int = ceili(sqrt(float(count)))
	var spacing: float = 1.65
	for i in range(count):
		var row: int = i / cols
		var col_idx: int = i % cols
		var ox: float = (float(col_idx) - float(cols - 1) * 0.5) * spacing
		var oz: float = (float(row) - float(cols - 1) * 0.5) * spacing
		res.append(Vector3(ox, 0.0, oz))
	return res


func get_idle_workers(team: int = 0) -> Array[RTSUnit]:
	var list: Array[RTSUnit] = []
	for u in units:
		if is_instance_valid(u) and not u.is_queued_for_deletion() and u.team == team and u.unit_type == "worker" and u.state == RTSUnit.State.IDLE:
			list.append(u)
	return list


func select_next_idle_worker() -> void:
	var idle_list: Array[RTSUnit] = get_idle_workers(0)
	if idle_list.is_empty():
		post_alert("Todos os camponeses já estão trabalhando!", Color(0.75, 0.9, 1.0))
		return
	_idle_worker_cycle_idx = _idle_worker_cycle_idx % idle_list.size()
	var w: RTSUnit = idle_list[_idle_worker_cycle_idx]
	_idle_worker_cycle_idx += 1
	clear_selection()
	w.set_selected(true)
	selected_units.append(w)
	if camera_rig != null:
		camera_rig.focus_on(w.global_position)
	selection_changed.emit()
	if sfx != null:
		sfx.play_select()


func focus_camera_on_base() -> void:
	if camera_rig == null:
		return
	for b in buildings:
		if is_instance_valid(b) and b.team == 0 and b.building_type == "town_center":
			camera_rig.focus_on(b.global_position)
			return
	camera_rig.focus_on(Vector3(-55.0, 0.0, 55.0))


func command_selected_stop() -> void:
	for u in selected_units:
		if is_instance_valid(u) and u.team == 0:
			u.command_stop()
	attack_move_mode = false


func command_selected_auto_gather() -> void:
	for u in selected_units:
		if is_instance_valid(u) and u.team == 0 and u.unit_type == "worker":
			u.command_auto_gather_near()
	if sfx != null:
		sfx.play_command()


func post_alert(msg: String, color: Color = Color(1.0, 0.88, 0.45)) -> void:
	alert_posted.emit(msg, color)


# ==============================================================================
# RAYCAST 3D
# ==============================================================================

func _raycast_world(screen_pos: Vector2) -> Dictionary:
	if camera_rig == null or camera_rig.camera == null or world_root == null:
		return {}
	var cam: Camera3D = camera_rig.camera
	var from: Vector3 = cam.project_ray_origin(screen_pos)
	var dir: Vector3 = cam.project_ray_normal(screen_pos)
	var space_state: PhysicsDirectSpaceState3D = world_root.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, from + dir * 280.0)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return space_state.intersect_ray(query)


func _raycast_ground(screen_pos: Vector2) -> Variant:
	if camera_rig == null or camera_rig.camera == null:
		return null
	var cam: Camera3D = camera_rig.camera
	var from: Vector3 = cam.project_ray_origin(screen_pos)
	var dir: Vector3 = cam.project_ray_normal(screen_pos)
	var plane: Plane = Plane(Vector3.UP, 0.0)
	return plane.intersects_ray(from, dir)
