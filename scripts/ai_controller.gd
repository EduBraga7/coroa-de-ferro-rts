extends Node
class_name AIController

## Inteligência Artificial do "Barão Corvo Vermelho" (time 1 por padrão; também roda no time 0 para
## simulações IA x IA). Ritmo lento (ver docs/DESIGN.md): economia primeiro, trégua no início,
## ondas crescentes no meio da partida e cerco com aríetes no fim.

signal wave_launched(wave: int, size: int)

const DIFFICULTY: Dictionary = {
	"facil": {
		"name": "Fácil", "gather": 0.85, "army_start": 330.0, "first_attack": 840.0, "wave_interval": 240.0,
		"wave_base": 5, "wave_growth": 3, "max_workers": 30, "bonus": 0,
	},
	"normal": {
		"name": "Normal", "gather": 1.0, "army_start": 240.0, "first_attack": 600.0, "wave_interval": 185.0,
		"wave_base": 7, "wave_growth": 4, "max_workers": 38, "bonus": 0,
	},
	"dificil": {
		"name": "Difícil", "gather": 1.22, "army_start": 190.0, "first_attack": 480.0, "wave_interval": 145.0,
		"wave_base": 9, "wave_growth": 5, "max_workers": 45, "bonus": 150,
	},
}

const TICK: float = 1.25

var team: int = 1
var enemy_team: int = 0
var game_manager: GameManager = null
var difficulty: String = "normal"
var cfg: Dictionary = DIFFICULTY["normal"]
var base_origin: Vector3 = Vector3(66.0, 0.0, -66.0)
var enemy_base_hint: Vector3 = Vector3(-66.0, 0.0, 66.0)
var staging_point: Vector3 = Vector3(50.0, 0.0, -50.0)
var announce_waves: bool = true
## Quando > 0, adia os ataques (usado pela IA que joga no lugar do jogador nas simulações contra covis).
var attack_start_override: float = -1.0

var _decision_timer: float = 1.0
var _wave_count: int = 0
var _next_wave_time: float = 600.0
var _wave_wait_start: float = -1.0
var _next_raid_time: float = 900.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _wave_units: Array[RTSUnit] = []
var _last_defense_time: float = -100.0


func _ready() -> void:
	_rng.randomize()


func configure(diff: String) -> void:
	difficulty = diff if DIFFICULTY.has(diff) else "normal"
	cfg = DIFFICULTY[difficulty]
	_next_wave_time = float(cfg["first_attack"])
	_next_raid_time = float(cfg["first_attack"]) + 150.0
	if game_manager != null:
		game_manager.gather_mult[team] = float(cfg["gather"])
		var bonus: int = int(cfg["bonus"])
		if bonus > 0:
			game_manager.refund_cost(team, {"food": bonus, "wood": bonus, "gold": bonus, "stone": bonus})


func setup_base(pos: Vector3, enemy_hint: Vector3) -> void:
	base_origin = pos
	enemy_base_hint = enemy_hint
	var dir: Vector3 = (enemy_hint - pos)
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.01 else Vector3(1.0, 0.0, 0.0)
	staging_point = pos + dir * 18.0


func get_threat_info() -> Dictionary:
	var t: float = game_manager.match_time if game_manager != null else 0.0
	return {
		"peace_left": maxf(0.0, float(cfg["first_attack"]) - t),
		"next_wave_in": maxf(0.0, _next_wave_time - t),
		"wave": _wave_count,
		"difficulty": String(cfg["name"]),
	}


func _process(delta: float) -> void:
	if game_manager == null or not game_manager.match_started or game_manager.is_game_over:
		return
	_decision_timer -= delta
	if _decision_timer <= 0.0:
		_decision_timer = TICK
		_run_ai_tick()


# ==============================================================================
# CENSO
# ==============================================================================

func _census() -> Dictionary:
	var c: Dictionary = {
		"workers": [],
		"military": [],
		"unit_count": {},
		"built": {},
		"pending": {},
		"gatherers": {"food": 0, "wood": 0, "gold": 0, "stone": 0},
		"farms": 0,
		"farm_targets": {},
	}
	for u in game_manager.units:
		if not is_instance_valid(u) or u._dead or u.team != team:
			continue
		c["unit_count"][u.unit_type] = int(c["unit_count"].get(u.unit_type, 0)) + 1
		if u.unit_type == "worker":
			(c["workers"] as Array).append(u)
			var r_type: String = _worker_task(u)
			if c["gatherers"].has(r_type):
				c["gatherers"][r_type] = int(c["gatherers"][r_type]) + 1
			if is_instance_valid(u.target_resource) and u.target_resource is RTSResourceNode:
				var res: RTSResourceNode = u.target_resource
				if res.kind == "farm":
					var id: int = res.get_instance_id()
					c["farm_targets"][id] = int(c["farm_targets"].get(id, 0)) + 1
		else:
			(c["military"] as Array).append(u)
	for b in game_manager.buildings:
		if not is_instance_valid(b) or b._dead or b.team != team:
			continue
		var bucket: String = "built" if b.is_constructed else "pending"
		if not c[bucket].has(b.building_type):
			c[bucket][b.building_type] = []
		(c[bucket][b.building_type] as Array).append(b)
	for r in game_manager.resources:
		if is_instance_valid(r) and r.kind == "farm" and r.owner_team == team and r.amount_left > 0:
			c["farms"] = int(c["farms"]) + 1
	return c


func _worker_task(u: RTSUnit) -> String:
	if u.state == RTSUnit.State.GATHERING or u.state == RTSUnit.State.RETURNING_RESOURCE:
		if is_instance_valid(u.target_resource):
			return String(u.target_resource.resource_type)
		if u.carrying_type != "":
			return u.carrying_type
	if u.state == RTSUnit.State.BUILDING:
		return "build"
	if u.state == RTSUnit.State.IDLE:
		return "idle"
	return "other"


func _count(c: Dictionary, b_type: String, include_pending: bool = true) -> int:
	var n: int = (c["built"].get(b_type, []) as Array).size()
	if include_pending:
		n += (c["pending"].get(b_type, []) as Array).size()
	return n


func _first_built(c: Dictionary, b_type: String) -> RTSBuilding:
	var arr: Array = c["built"].get(b_type, [])
	return arr[0] if not arr.is_empty() else null


# ==============================================================================
# CICLO DE DECISÃO
# ==============================================================================

func _run_ai_tick() -> void:
	var c: Dictionary = _census()
	var tc: RTSBuilding = _first_built(c, "town_center")
	if tc != null:
		base_origin = tc.global_position
	elif _first_built(c, "castle") != null:
		base_origin = _first_built(c, "castle").global_position

	_manage_builders(c)
	_manage_gatherers(c)
	_train_workers(c)
	_manage_buildings(c)
	if game_manager.match_time >= float(cfg["army_start"]):
		_train_army(c)
	_manage_market(c)
	_manage_attacks(c)


func _alloc_fractions() -> Dictionary:
	var t: float = game_manager.match_time
	var f: Dictionary
	if t < 180.0:
		f = {"food": 0.62, "wood": 0.38, "gold": 0.0, "stone": 0.0}
	elif t < 420.0:
		f = {"food": 0.5, "wood": 0.34, "gold": 0.16, "stone": 0.0}
	elif t < 720.0:
		f = {"food": 0.42, "wood": 0.3, "gold": 0.18, "stone": 0.10}
	else:
		f = {"food": 0.38, "wood": 0.27, "gold": 0.22, "stone": 0.13}
	# Sem recurso disponível, redistribui a fração
	for r in f.keys():
		if float(f[r]) > 0.0 and _find_resource(String(r), null) == null and not (r == "food" and _team_farm_count() > 0):
			var share: float = float(f[r])
			f[r] = 0.0
			f["wood"] = float(f["wood"]) + share
	return f


func _team_farm_count() -> int:
	var n: int = 0
	for r in game_manager.resources:
		if is_instance_valid(r) and r.kind == "farm" and r.owner_team == team:
			n += 1
	return n


func _manage_builders(c: Dictionary) -> void:
	var workers: Array = c["workers"]
	if workers.is_empty():
		return
	for b_type in c["pending"].keys():
		for b in c["pending"][b_type]:
			var builders: int = 0
			for w in workers:
				if w.state == RTSUnit.State.BUILDING and w.target_building == b:
					builders += 1
			var wanted: int = 2 if b_type in ["town_center", "castle"] else 1
			while builders < wanted:
				var chosen: RTSUnit = _pick_worker_near(workers, (b as RTSBuilding).global_position, true)
				if chosen == null:
					break
				chosen.command_build(b)
				builders += 1


func _pick_worker_near(workers: Array, pos: Vector3, avoid_builders: bool) -> RTSUnit:
	var best: RTSUnit = null
	var best_score: float = 1.0e9
	for w in workers:
		if avoid_builders and w.state == RTSUnit.State.BUILDING:
			continue
		var score: float = w.global_position.distance_to(pos)
		if w.state != RTSUnit.State.IDLE:
			score += 25.0
		if w.carrying_amount > 0:
			score += 10.0
		if score < best_score:
			best_score = score
			best = w
	return best


func _manage_gatherers(c: Dictionary) -> void:
	var workers: Array = c["workers"]
	if workers.is_empty():
		return
	var gatherers: Dictionary = c["gatherers"]
	var total: int = 0
	for w in workers:
		if w.state != RTSUnit.State.BUILDING:
			total += 1
	var frac: Dictionary = _alloc_fractions()
	var desired: Dictionary = {}
	for r in frac.keys():
		desired[r] = int(round(float(frac[r]) * float(total)))

	# 1. Ociosos vão para o recurso mais carente
	for w in workers:
		if w.state != RTSUnit.State.IDLE:
			continue
		var r_type: String = _most_needed(desired, gatherers)
		var node: RTSResourceNode = _find_resource(r_type, c)
		if node == null:
			for alt in ["food", "wood", "gold", "stone"]:
				node = _find_resource(alt, c)
				if node != null:
					r_type = alt
					break
		if node != null:
			w.command_gather(node)
			gatherers[r_type] = int(gatherers.get(r_type, 0)) + 1
			if node.kind == "farm":
				var id: int = node.get_instance_id()
				c["farm_targets"][id] = int(c["farm_targets"].get(id, 0)) + 1

	# 2. Rebalanceia um camponês por ciclo (do recurso com sobra para o mais carente)
	var need: String = _most_needed(desired, gatherers)
	var need_gap: int = int(desired.get(need, 0)) - int(gatherers.get(need, 0))
	if need_gap < 2:
		return
	var surplus_type: String = ""
	var best_surplus: int = 1
	for r in gatherers.keys():
		var s: int = int(gatherers[r]) - int(desired.get(r, 0))
		if s > best_surplus:
			best_surplus = s
			surplus_type = String(r)
	if surplus_type == "":
		return
	var node2: RTSResourceNode = _find_resource(need, c)
	if node2 == null:
		return
	for w in workers:
		if w.state == RTSUnit.State.GATHERING and w.carrying_amount == 0 and is_instance_valid(w.target_resource) and w.target_resource.resource_type == surplus_type:
			w.command_gather(node2)
			return


func _most_needed(desired: Dictionary, gatherers: Dictionary) -> String:
	var best: String = "food"
	var best_gap: float = -1.0e9
	for r in desired.keys():
		var want: int = int(desired[r])
		if want <= 0:
			continue
		var gap: float = float(want - int(gatherers.get(r, 0))) / float(want)
		if gap > best_gap:
			best_gap = gap
			best = String(r)
	return best


func _drop_points(r_type: String) -> Array[Vector3]:
	var pts: Array[Vector3] = [base_origin]
	for b in game_manager.buildings:
		if is_instance_valid(b) and not b._dead and b.team == team and b.is_constructed and b.accepts_resource(r_type):
			pts.append(b.global_position)
	return pts


func _find_resource(r_type: String, c: Variant) -> RTSResourceNode:
	var best: RTSResourceNode = null
	var best_d: float = 1.0e9
	# Prefere recursos perto de um ponto de entrega (viagens curtas)
	var anchors: Array[Vector3] = _drop_points(r_type)
	for r in game_manager.resources:
		if not is_instance_valid(r) or r.amount_left <= 0 or r.resource_type != r_type or not r.can_be_gathered_by(team):
			continue
		var d: float = 1.0e9
		for a in anchors:
			d = minf(d, a.distance_to(r.global_position))
		if r.kind == "farm":
			var on_it: int = 0
			if c != null:
				on_it = int((c as Dictionary)["farm_targets"].get(r.get_instance_id(), 0))
			if on_it >= 2:
				continue
			d -= 30.0
		if r.kind != "farm" and base_origin.distance_to(r.global_position) > 95.0:
			d += 200.0
		if d < best_d:
			best_d = d
			best = r
	return best


func _train_workers(c: Dictionary) -> void:
	var t: float = game_manager.match_time
	var target: int = mini(int(cfg["max_workers"]), 5 + int(t / 24.0))
	var have: int = (c["workers"] as Array).size()
	if have >= target:
		return
	for tc in c["built"].get("town_center", []):
		var b: RTSBuilding = tc
		if b.production_queue.size() < 2 and game_manager.can_afford_unit(team, "worker"):
			b.queue_unit("worker")
			have += 1
			if have >= target:
				return


# ==============================================================================
# CONSTRUÇÕES
# ==============================================================================

func _manage_buildings(c: Dictionary) -> void:
	var t: float = game_manager.match_time
	var pop_used: int = game_manager.get_team_pop_used(team)
	var pop_cap: int = game_manager.get_team_pop_cap(team)
	var workers: Array = c["workers"]
	if workers.is_empty():
		return

	# Reconstrói o Salão Real se perdido (prioridade máxima)
	if _count(c, "town_center") == 0:
		if game_manager.can_afford_building(team, "town_center"):
			_try_build("town_center", base_origin, 0.0, 14.0, workers)
		return

	# Casas antes de travar a população
	var pending_houses: int = (c["pending"].get("house", []) as Array).size()
	var house_slack: int = 3 if t < 600.0 else 6
	if pop_used >= pop_cap - house_slack and pop_cap < GameManager.MAX_POP_LIMIT and pending_houses < (1 if t < 600.0 else 2):
		if _try_build("house", base_origin, 9.0, 26.0, workers):
			return

	# Pontos de entrega perto dos recursos
	if t >= 35.0 and _count(c, "mill") == 0:
		var berry: RTSResourceNode = _nearest_resource_kind("berry_bush", base_origin, 40.0)
		var anchor: Vector3 = berry.global_position if berry != null else base_origin
		if _try_build("mill", anchor, 3.8 if berry != null else 9.0, 9.0 if berry != null else 18.0, workers):
			return
	if t >= 50.0 and _count(c, "lumber_camp") < 7 and _needs_drop_site(c, "lumber_camp", "tree", 13.0):
		var tree: RTSResourceNode = _nearest_resource_kind("tree", base_origin, 110.0)
		if tree != null and _try_build("lumber_camp", tree.global_position, 3.6, 8.0, workers):
			return
	if t >= 160.0 and _count(c, "mining_camp") < 6 and _needs_drop_site(c, "mining_camp", "gold_mine", 9.0):
		var mine: RTSResourceNode = _nearest_resource_kind("gold_mine", base_origin, 95.0)
		if mine != null and _try_build("mining_camp", mine.global_position, 4.6, 8.0, workers):
			return

	# Militar básico
	var barracks_wanted: int = 1 if t >= float(cfg["army_start"]) - 60.0 else 0
	if t >= 720.0:
		barracks_wanted = 2
	if _count(c, "barracks") < barracks_wanted:
		if _try_build("barracks", _toward_front(10.0), 6.0, 20.0, workers):
			return

	# Fazendas quando os frutos acabam ou a partir dos 4 minutos
	var berries_left: bool = _nearest_resource_kind("berry_bush", base_origin, 45.0) != null
	var food_target: int = int(round(_alloc_fractions()["food"] * float(workers.size())))
	var farms_wanted: int = int(ceil(float(food_target) / 2.0))
	if berries_left and t < 300.0:
		farms_wanted = 0
	var farms_have: int = int(c["farms"]) + (c["pending"].get("farm", []) as Array).size()
	if farms_have < farms_wanted:
		var mill: RTSBuilding = _first_built(c, "mill")
		var farm_anchor: Vector3 = mill.global_position if mill != null else base_origin
		if _try_build("farm", farm_anchor, 6.0, 18.0, workers):
			return

	if t >= 330.0 and _needs_drop_site(c, "mining_camp", "stone_quarry", 9.0):
		var quarry: RTSResourceNode = _nearest_resource_kind("stone_quarry", base_origin, 60.0)
		if quarry != null and _try_build("mining_camp", quarry.global_position, 4.4, 8.0, workers):
			return

	if t >= float(cfg["army_start"]) + 60.0 and _count(c, "archery_range") == 0:
		if _try_build("archery_range", _toward_front(8.0), 6.0, 22.0, workers):
			return

	var castle_planned: bool = t >= 660.0 and _count(c, "castle") == 0
	if castle_planned and game_manager.can_afford_building(team, "castle"):
		if _try_build("castle", _toward_front(6.0), 8.0, 26.0, workers):
			return

	var towers_wanted: int = 0
	if t >= 480.0:
		towers_wanted = 1
	if t >= 900.0:
		towers_wanted = 2
	if _count(c, "tower") < towers_wanted and (not castle_planned or game_manager.get_res(team, "stone") >= 800):
		if _try_build("tower", _toward_front(14.0), 0.0, 10.0, workers):
			return

	if t >= 780.0 and _count(c, "market") == 0:
		if _try_build("market", base_origin, 12.0, 26.0, workers):
			return

	if t >= 960.0 and _count(c, "siege_workshop") == 0:
		if _try_build("siege_workshop", _toward_front(4.0), 8.0, 24.0, workers):
			return

	# Pedra excedente no fim do jogo vira torres protegendo a economia
	if t >= 900.0 and _count(c, "tower") < 5 and _count(c, "castle") > 0 and game_manager.get_res(team, "stone") >= 450:
		var camps: Array = (c["built"].get("lumber_camp", []) as Array) + (c["built"].get("mining_camp", []) as Array)
		var anchor_t: Vector3 = _toward_front(16.0)
		if not camps.is_empty():
			anchor_t = (camps[_rng.randi_range(0, camps.size() - 1)] as RTSBuilding).global_position
		if _try_build("tower", anchor_t, 4.0, 12.0, workers):
			return


func _toward_front(dist: float) -> Vector3:
	var dir: Vector3 = staging_point - base_origin
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		return base_origin
	return base_origin + dir.normalized() * dist


func _needs_drop_site(c: Dictionary, camp_type: String, res_kind: String, max_gap: float) -> bool:
	var res: RTSResourceNode = _nearest_resource_kind(res_kind, base_origin, 110.0 if res_kind == "tree" else 95.0)
	if res == null:
		return false
	if not (c["pending"].get(camp_type, []) as Array).is_empty():
		return false
	var best: float = 1.0e9
	for b in game_manager.buildings:
		if is_instance_valid(b) and not b._dead and b.team == team and (b.building_type == camp_type or b.building_type == "town_center"):
			best = minf(best, b.global_position.distance_to(res.global_position))
	return best > max_gap + res.collision_radius


func _nearest_resource_kind(kind: String, origin: Vector3, max_dist: float) -> RTSResourceNode:
	var best: RTSResourceNode = null
	var best_d: float = max_dist
	for r in game_manager.resources:
		if not is_instance_valid(r) or r.amount_left <= 0 or r.kind != kind or not r.can_be_gathered_by(team):
			continue
		var d: float = origin.distance_to(r.global_position)
		if d < best_d:
			best_d = d
			best = r
	return best


func _try_build(b_type: String, anchor: Vector3, min_r: float, max_r: float, workers: Array) -> bool:
	var cost: Dictionary = RTSBuilding.get_cost(b_type)
	if not game_manager.can_afford_cost(team, cost):
		return false
	var rad: float = float(RTSBuilding.STATS[b_type]["radius"])
	var spot: Vector3 = _find_valid_spot(anchor, rad, min_r, max_r)
	if spot.x == INF:
		return false
	if not game_manager.spend_cost(team, cost):
		return false
	var b: RTSBuilding = game_manager.place_building_at(b_type, spot, team, false)
	if b == null:
		return false
	if not b.trainable.is_empty():
		b.set_rally_point(staging_point + Vector3(_rng.randf_range(-4.0, 4.0), 0.0, _rng.randf_range(-4.0, 4.0)))
	var builder: RTSUnit = _pick_worker_near(workers, spot, true)
	if builder != null:
		builder.command_build(b)
	return true


func _find_valid_spot(center: Vector3, rad: float, min_r: float, max_r: float) -> Vector3:
	if min_r <= 0.01 and game_manager.is_valid_building_spot(center, rad, team) and _keeps_clear(center, rad):
		return center
	var ring: float = maxf(min_r, 1.5)
	while ring <= max_r:
		var steps: int = maxi(8, int(ring * 1.2))
		var phase: float = _rng.randf() * TAU
		for i in range(steps):
			var ang: float = phase + TAU * float(i) / float(steps)
			var cand: Vector3 = center + Vector3(cos(ang) * ring, 0.0, sin(ang) * ring)
			if game_manager.is_valid_building_spot(cand, rad, team) and _keeps_clear(cand, rad):
				return cand
		ring += 2.5
	return Vector3(INF, 0.0, INF)


func _keeps_clear(p: Vector3, rad: float) -> bool:
	# Não bloqueia a saída do Salão Real nem a navegação
	if game_manager.nav != null and not game_manager.nav.is_walkable_world(p + Vector3(rad + 2.0, 0.0, 0.0)) and not game_manager.nav.is_walkable_world(p - Vector3(rad + 2.0, 0.0, 0.0)):
		return false
	return true


# ==============================================================================
# EXÉRCITO
# ==============================================================================

func _train_army(c: Dictionary) -> void:
	var t: float = game_manager.match_time
	var enemy_knights: int = 0
	var enemy_archers: int = 0
	for u in game_manager.units:
		if is_instance_valid(u) and not u._dead and u.team == enemy_team:
			if u.unit_type == "knight":
				enemy_knights += 1
			elif u.unit_type == "archer":
				enemy_archers += 1
	# Mantém reserva para casas/fazendas
	var reserve_wood: int = 110 if t > 240.0 else 0
	for b in c["built"].get("barracks", []):
		var bb: RTSBuilding = b
		if bb.production_queue.size() >= 2:
			continue
		var roll: float = _rng.randf()
		var choice: String = "soldier"
		var spear_bias: float = 0.35 + minf(0.3, float(enemy_knights) * 0.05)
		if int(c["unit_count"].get("scout", 0)) < 2 and roll < 0.12:
			choice = "scout"
		elif roll < 0.12 + spear_bias:
			choice = "spearman"
		# Sem ouro: lanceiros (comida + madeira) mantêm o exército crescendo
		if not game_manager.can_afford_unit(team, choice):
			choice = "spearman"
		_queue_if_affordable(bb, choice, reserve_wood)
	for b in c["built"].get("archery_range", []):
		var ab: RTSBuilding = b
		if ab.production_queue.size() < 2:
			_queue_if_affordable(ab, "archer", reserve_wood)
	for b in c["built"].get("castle", []):
		var cb: RTSBuilding = b
		if cb.production_queue.size() < 2 and (enemy_archers > 2 or _rng.randf() < 0.6):
			_queue_if_affordable(cb, "knight", reserve_wood)
	if t >= 960.0:
		for b in c["built"].get("siege_workshop", []):
			var sb: RTSBuilding = b
			if sb.production_queue.size() < 1 and int(c["unit_count"].get("ram", 0)) < 3:
				_queue_if_affordable(sb, "ram", reserve_wood)


func _queue_if_affordable(b: RTSBuilding, u_type: String, reserve_wood: int) -> void:
	var cost: Dictionary = RTSUnit.get_cost(u_type)
	var wood_need: int = int(cost.get("wood", 0)) + reserve_wood
	if game_manager.get_res(team, "wood") < wood_need and cost.has("wood"):
		return
	if not game_manager.has_pop_space(team, game_manager.get_unit_pop_cost(u_type)):
		return
	if game_manager.can_afford_cost(team, cost):
		b.queue_unit(u_type)


func _manage_market(c: Dictionary) -> void:
	if (c["built"].get("market", []) as Array).is_empty():
		return
	var gold: int = game_manager.get_res(team, "gold")
	for r in ["food", "wood", "stone"]:
		var amt: int = game_manager.get_res(team, r)
		var limit: int = 700 if r == "stone" else 1000
		if gold < 150 and r != "stone":
			limit = 550
		if amt > limit:
			game_manager.market_sell(team, r)
			return
	# Falta de comida/madeira trava o exército: compra cedo se houver ouro parado
	if gold > 250:
		for r in ["food", "wood"]:
			if game_manager.get_res(team, r) < 150:
				game_manager.market_buy(team, r)
				return


# ==============================================================================
# ATAQUES, INCURSÕES E DEFESA
# ==============================================================================

func _manage_attacks(c: Dictionary) -> void:
	var t: float = game_manager.match_time
	var military: Array = c["military"]

	# Tropas de ondas anteriores que ficaram ociosas seguem para o próximo alvo
	for i in range(_wave_units.size() - 1, -1, -1):
		var wu: RTSUnit = _wave_units[i]
		if not is_instance_valid(wu) or wu._dead:
			_wave_units.remove_at(i)
			continue
		if wu.state == RTSUnit.State.IDLE:
			var tgt: Node3D = _pick_target_for(wu)
			if tgt != null:
				if wu.is_siege and tgt is RTSBuilding:
					wu.command_attack(tgt)
				else:
					wu.command_attack_move(tgt.global_position)
			else:
				_wave_units.remove_at(i)

	var attack_start: float = attack_start_override if attack_start_override > 0.0 else float(cfg["first_attack"])
	if t < attack_start:
		return

	# Incursões contra a economia do inimigo
	if t >= _next_raid_time:
		_next_raid_time = t + _rng.randf_range(150.0, 210.0)
		_launch_raid(military)

	if t < _next_wave_time:
		return
	var desired: int = int(cfg["wave_base"]) + _wave_count * int(cfg["wave_growth"])
	var ready: Array[RTSUnit] = []
	for m in military:
		var mu: RTSUnit = m
		if mu in _wave_units:
			continue
		if mu.state == RTSUnit.State.IDLE or mu.state == RTSUnit.State.MOVING:
			ready.append(mu)
	if _wave_wait_start < 0.0:
		_wave_wait_start = t
	var waited: float = t - _wave_wait_start
	var enough: bool = ready.size() >= desired or (waited > 75.0 and ready.size() >= maxi(4, int(desired * 0.55)))
	if not enough:
		return
	_wave_wait_start = -1.0
	_next_wave_time = t + float(cfg["wave_interval"]) + _rng.randf_range(-20.0, 20.0)
	# Guarnição: a partir da 3ª onda, alguns arqueiros ficam em casa
	var keep_home: int = 0
	if _wave_count >= 2:
		keep_home = int(ready.size() * 0.2)
	var sent: Array[RTSUnit] = []
	for i in range(ready.size()):
		var u: RTSUnit = ready[i]
		if keep_home > 0 and u.unit_type == "archer":
			keep_home -= 1
			continue
		sent.append(u)
	launch_attack_wave(sent)


func launch_attack_wave(attackers: Array[RTSUnit] = []) -> void:
	if game_manager == null or game_manager.is_game_over:
		return
	if attackers.is_empty():
		for u in game_manager.units:
			if is_instance_valid(u) and not u._dead and u.team == team and u.unit_type != "worker":
				if u.state == RTSUnit.State.IDLE or u.state == RTSUnit.State.MOVING:
					attackers.append(u)
	if attackers.is_empty():
		return
	_wave_count += 1
	var target: Node3D = _pick_wave_target()
	var target_pos: Vector3 = target.global_position if target != null else enemy_base_hint
	var offsets: Array[Vector3] = game_manager.get_formation_offsets(attackers.size())
	for i in range(attackers.size()):
		var u: RTSUnit = attackers[i]
		if u.is_siege and target is RTSBuilding:
			u.command_attack(target)
		else:
			u.command_attack_move(target_pos + offsets[i])
		if not (u in _wave_units):
			_wave_units.append(u)
	wave_launched.emit(_wave_count, attackers.size())
	if announce_waves and team == 1 and game_manager.ai_controllers.size() == 1:
		game_manager.post_alert("ALERTA: a %dª onda do Barão Corvo Vermelho (%d tropas) marcha contra você!" % [_wave_count, attackers.size()], Color(1.0, 0.35, 0.28))
		if game_manager.sfx != null:
			game_manager.sfx.play_horn_alert()


func _launch_raid(military: Array) -> void:
	var raiders: Array[RTSUnit] = []
	for m in military:
		var u: RTSUnit = m
		if u in _wave_units or u.is_siege:
			continue
		if u.state != RTSUnit.State.IDLE:
			continue
		if u.unit_type == "scout" or u.unit_type == "soldier" or u.unit_type == "knight":
			raiders.append(u)
		if raiders.size() >= 4:
			break
	if raiders.size() < 2:
		return
	# Alvo: camponeses inimigos mais próximos da nossa base
	var best: RTSUnit = null
	var best_d: float = 1.0e9
	for u in game_manager.units:
		if is_instance_valid(u) and not u._dead and u.team == enemy_team and u.unit_type == "worker":
			var d: float = u.global_position.distance_to(base_origin)
			if d < best_d:
				best_d = d
				best = u
	if best == null:
		return
	for r in raiders:
		r.command_attack_move(best.global_position)
		_wave_units.append(r)


func _pick_wave_target() -> Node3D:
	# Primeiras ondas atacam prédios periféricos; depois o coração da base inimiga
	var main_only: bool = _wave_count >= 3
	var best: Node3D = null
	var best_d: float = 1.0e9
	for b in game_manager.buildings:
		if not is_instance_valid(b) or b._dead or b.team != enemy_team:
			continue
		if main_only and not b.is_main_structure:
			continue
		var d: float = b.global_position.distance_to(base_origin)
		if d < best_d:
			best_d = d
			best = b
	if best == null and main_only:
		for b in game_manager.buildings:
			if is_instance_valid(b) and not b._dead and b.team == enemy_team:
				var d2: float = b.global_position.distance_to(base_origin)
				if d2 < best_d:
					best_d = d2
					best = b
	return best


func _pick_target_for(u: RTSUnit) -> Node3D:
	var best: Node3D = null
	var best_d: float = 1.0e9
	for b in game_manager.buildings:
		if not is_instance_valid(b) or b._dead or b.team != enemy_team:
			continue
		var d: float = b.global_position.distance_to(u.global_position)
		if b.is_main_structure:
			d -= 15.0
		if d < best_d:
			best_d = d
			best = b
	if best == null and not u.is_siege:
		for e in game_manager.units:
			if is_instance_valid(e) and not e._dead and e.team == enemy_team:
				var d2: float = e.global_position.distance_to(u.global_position)
				if d2 < best_d:
					best_d = d2
					best = e
	return best


func on_ai_entity_damaged(victim: Variant, attacker: Variant) -> void:
	if victim == null or not is_instance_valid(victim) or victim.is_queued_for_deletion():
		return
	if attacker == null or not is_instance_valid(attacker) or attacker.is_queued_for_deletion():
		return
	var vpos: Vector3 = (victim as Node3D).global_position
	var near_home: bool = vpos.distance_to(base_origin) < 42.0
	var t: float = game_manager.match_time
	var radius: float = 55.0 if near_home else 30.0
	for u in game_manager.query_units(vpos, radius):
		if not is_instance_valid(u) or u._dead or u.team != team or u.unit_type == "worker" or u.is_siege:
			continue
		if u in _wave_units and not near_home:
			continue
		if u.state == RTSUnit.State.IDLE or u.state == RTSUnit.State.ATTACK_MOVING or u.state == RTSUnit.State.MOVING:
			if u.global_position.distance_to(vpos) <= radius:
				u.command_attack(attacker)
	if near_home and t - _last_defense_time > 6.0:
		_last_defense_time = t
		# Recolhe a última onda se a base estiver sob ataque pesado
		var threat: int = 0
		for e in game_manager.query_units(vpos, 20.0):
			if is_instance_valid(e) and not e._dead and e.team == enemy_team and e.unit_type != "worker":
				threat += 1
		if threat >= 6:
			for wu in _wave_units:
				if is_instance_valid(wu) and not wu._dead and wu.global_position.distance_to(base_origin) > 50.0:
					wu.command_attack_move(vpos)
