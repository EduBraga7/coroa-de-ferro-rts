extends Node
class_name AIController

## Inteligência Artificial do inimigo "Barão Corvo Vermelho" (Time 1).

var team: int = 1
var game_manager: GameManager = null
var base_origin: Vector3 = Vector3(55.0, 0.0, -55.0)
var staging_point: Vector3 = Vector3(38.0, 0.0, -38.0)

var _decision_timer: float = 1.0
var _wave_timer: float = 0.0
var _wave_interval: float = 70.0
var _wave_count: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func _process(delta: float) -> void:
	if game_manager == null or not game_manager.match_started or game_manager.is_game_over:
		return

	_wave_timer += delta
	_decision_timer -= delta
	if _decision_timer <= 0.0:
		_decision_timer = 1.5
		_run_ai_tick()


func _run_ai_tick() -> void:
	var my_workers: Array[RTSUnit] = []
	var my_military: Array[RTSUnit] = []
	var my_tcs: Array[RTSBuilding] = []
	var my_barracks: Array[RTSBuilding] = []
	var my_towers: Array[RTSBuilding] = []
	var unfinished_buildings: Array[RTSBuilding] = []

	for u in game_manager.units:
		if not is_instance_valid(u) or u.is_queued_for_deletion() or u.team != team or u.hp <= 0.0:
			continue
		if u.unit_type == "worker":
			my_workers.append(u)
		else:
			my_military.append(u)

	for b in game_manager.buildings:
		if not is_instance_valid(b) or b.is_queued_for_deletion() or b.team != team or b.hp <= 0.0:
			continue
		if not b.is_constructed:
			unfinished_buildings.append(b)
			continue
		match b.building_type:
			"town_center":
				my_tcs.append(b)
			"barracks":
				my_barracks.append(b)
			"tower":
				my_towers.append(b)

	if not my_tcs.is_empty():
		base_origin = my_tcs[0].global_position

	# 1. Alocar camponeses para construções pendentes e coleta
	_manage_workers(my_workers, unfinished_buildings)

	# 2. Treinar camponeses até 7
	if my_workers.size() < 7 and not my_tcs.is_empty():
		var tc: RTSBuilding = my_tcs[0]
		if tc.production_queue.size() < 2 and game_manager.can_afford_unit(team, "worker"):
			tc.queue_unit("worker")

	# 3. Expansão de Base (Casas, Quartéis, Torres)
	_manage_buildings(my_barracks, my_towers, unfinished_buildings)

	# 4. Evolução para Era Real após 180s se tiver recursos
	if game_manager.match_time >= 180.0 and game_manager.get_team_age(team) < 2:
		if game_manager.can_afford(team, GameManager.AGE_UPGRADE_GOLD, GameManager.AGE_UPGRADE_WOOD):
			game_manager.upgrade_age(team)

	# 5. Treinar exército nos Quartéis
	_manage_army_training(my_barracks)

	# 6. Verificar disparo de onda de ataque
	var desired_wave_size: int = 4 + _wave_count * 3
	var ready_troops: Array[RTSUnit] = []
	for m in my_military:
		if m.state == RTSUnit.State.IDLE or (m.state == RTSUnit.State.MOVING and m.global_position.distance_to(staging_point) < 16.0):
			ready_troops.append(m)

	if _wave_timer >= _wave_interval or ready_troops.size() >= desired_wave_size:
		if ready_troops.size() >= 3:
			launch_attack_wave()


func _manage_workers(workers: Array[RTSUnit], unfinished: Array[RTSBuilding]) -> void:
	if workers.is_empty():
		return

	# Garante construtor para prédios inacabados
	for b in unfinished:
		var has_builder: bool = false
		for w in workers:
			if w.state == RTSUnit.State.BUILDING and w.target_building == b:
				has_builder = true
				break
		if not has_builder:
			var chosen: RTSUnit = _pick_available_worker(workers)
			if chosen != null:
				chosen.command_build(b)

	# Conta coletores atuais
	var gold_gatherers: int = 0
	var wood_gatherers: int = 0
	for w in workers:
		if w.state == RTSUnit.State.GATHERING or w.state == RTSUnit.State.RETURNING_RESOURCE:
			if w.carrying_type == "gold" or (is_instance_valid(w.target_resource) and w.target_resource.resource_type == "gold"):
				gold_gatherers += 1
			else:
				wood_gatherers += 1

	# Envia camponeses ociosos (60% ouro / 40% madeira)
	for w in workers:
		if w.state != RTSUnit.State.IDLE:
			continue
		var want_gold: bool = float(gold_gatherers) <= float(wood_gatherers) * 1.4
		var res_type: String = "gold" if want_gold else "wood"
		var node: RTSResourceNode = _find_nearest_resource_to(base_origin, res_type)
		if node == null:
			node = _find_nearest_resource_to(base_origin, "wood" if want_gold else "gold")
		if node != null:
			w.command_gather(node)
			if node.resource_type == "gold":
				gold_gatherers += 1
			else:
				wood_gatherers += 1


func _pick_available_worker(workers: Array[RTSUnit]) -> RTSUnit:
	for w in workers:
		if w.state == RTSUnit.State.IDLE:
			return w
	for w in workers:
		if w.state != RTSUnit.State.BUILDING:
			return w
	return null


func _manage_buildings(my_barracks: Array[RTSBuilding], my_towers: Array[RTSBuilding], unfinished: Array[RTSBuilding]) -> void:
	var has_pending_house: bool = false
	var has_pending_barracks: bool = false
	var has_pending_tower: bool = false
	for b in unfinished:
		match b.building_type:
			"house":
				has_pending_house = true
			"barracks":
				has_pending_barracks = true
			"tower":
				has_pending_tower = true

	var pop_used: int = game_manager.get_team_pop_used(team)
	var pop_cap: int = game_manager.get_team_pop_cap(team)

	# Construir Casa se perto do limite de população
	if pop_used >= pop_cap - 2 and pop_cap < GameManager.MAX_POP_LIMIT and not has_pending_house:
		if game_manager.can_afford_building(team, "house"):
			_try_build("house", base_origin + Vector3(8.0, 0.0, 6.0))
			return

	# Construir Quartel (até 2 quartéis)
	var desired_barracks: int = 1 if game_manager.match_time < 130.0 else 2
	if my_barracks.size() < desired_barracks and not has_pending_barracks:
		if game_manager.can_afford_building(team, "barracks"):
			var offset: Vector3 = Vector3(-11.0, 0.0, 6.0) if my_barracks.is_empty() else Vector3(-6.0, 0.0, 12.0)
			_try_build("barracks", base_origin + offset)
			return

	# Construir Torres de Vigia defensivas (até 2)
	if my_towers.size() < 2 and not has_pending_tower and not my_barracks.is_empty():
		if game_manager.can_afford_building(team, "tower"):
			var t_pos: Vector3 = Vector3(41.0, 0.0, -43.0) if my_towers.size() == 1 else Vector3(36.0, 0.0, -52.0)
			_try_build("tower", t_pos)


func _try_build(b_type: String, preferred_pos: Vector3) -> void:
	var cfg: Dictionary = RTSBuilding.STATS.get(b_type, {})
	if cfg.is_empty():
		return
	var rad: float = float(cfg["radius"])
	var spot: Vector3 = _find_valid_spot_near(preferred_pos, rad)
	if spot == Vector3.INF:
		return
	if game_manager.spend(team, int(cfg["gold"]), int(cfg["wood"])):
		var b: RTSBuilding = game_manager.place_building_at(b_type, spot, team, false)
		if b != null:
			b.set_rally_point(staging_point)


func _find_valid_spot_near(center: Vector3, rad: float) -> Vector3:
	if game_manager.is_valid_building_spot(center, rad):
		return center
	for ring in [5.0, 9.0, 13.0, 17.0]:
		for i in range(10):
			var ang: float = (TAU / 10.0) * float(i) + _rng.randf_range(0.0, 0.4)
			var candidate: Vector3 = center + Vector3(cos(ang) * ring, 0.0, sin(ang) * ring)
			if game_manager.is_valid_building_spot(candidate, rad):
				return candidate
	return Vector3.INF


func _manage_army_training(my_barracks: Array[RTSBuilding]) -> void:
	for b in my_barracks:
		if b.production_queue.size() >= 2:
			continue
		b.set_rally_point(staging_point + Vector3(_rng.randf_range(-4.0, 4.0), 0.0, _rng.randf_range(-4.0, 4.0)))
		var roll: float = _rng.randf()
		var choice: String = "soldier"
		if roll > 0.72 and game_manager.can_afford_unit(team, "knight"):
			choice = "knight"
		elif roll > 0.38 and game_manager.can_afford_unit(team, "archer"):
			choice = "archer"
		elif not game_manager.can_afford_unit(team, "soldier"):
			continue
		b.queue_unit(choice)


func launch_attack_wave() -> void:
	if game_manager == null or game_manager.is_game_over:
		return
	_wave_timer = 0.0
	_wave_count += 1

	var target_pos: Vector3 = Vector3(-55.0, 0.0, 55.0)
	for b in game_manager.buildings:
		if is_instance_valid(b) and not b.is_queued_for_deletion() and b.team == 0:
			target_pos = b.global_position
			if b.building_type == "town_center":
				break

	var attackers: Array[RTSUnit] = []
	for u in game_manager.units:
		if not is_instance_valid(u) or u.is_queued_for_deletion() or u.team != team or u.hp <= 0.0:
			continue
		if u.unit_type == "worker":
			continue
		if u.state == RTSUnit.State.IDLE or u.state == RTSUnit.State.MOVING:
			attackers.append(u)

	if attackers.is_empty():
		return

	var offsets: Array[Vector3] = game_manager.get_formation_offsets(attackers.size())
	for i in range(attackers.size()):
		attackers[i].command_attack_move(target_pos + offsets[i])

	game_manager.post_alert("ALERTA: Onda %d do Barão Corvo Vermelho (%d tropas) está marchando!" % [_wave_count, attackers.size()], Color(1.0, 0.35, 0.28))
	if game_manager.sfx != null:
		game_manager.sfx.play_horn_alert()


func on_ai_entity_damaged(victim: Variant, attacker: Variant) -> void:
	if victim == null or not is_instance_valid(victim) or victim.is_queued_for_deletion():
		return
	if attacker == null or not is_instance_valid(attacker) or attacker.is_queued_for_deletion():
		return
	for u in game_manager.units:
		if not is_instance_valid(u) or u.is_queued_for_deletion() or u.team != team or u.unit_type == "worker":
			continue
		if u.state == RTSUnit.State.IDLE or u.state == RTSUnit.State.ATTACK_MOVING:
			if u.global_position.distance_to(victim.global_position) <= 36.0:
				u.command_attack(attacker)


func _find_nearest_resource_to(origin: Vector3, r_type: String) -> RTSResourceNode:
	var best: RTSResourceNode = null
	var best_d: float = 99999.0
	for r in game_manager.resources:
		if not is_instance_valid(r) or r.is_queued_for_deletion():
			continue
		if r.resource_type != r_type:
			continue
		var d: float = origin.distance_to(r.global_position)
		if d < best_d:
			best_d = d
			best = r
	return best
