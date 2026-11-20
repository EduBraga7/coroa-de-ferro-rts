extends Node
class_name WaveDirector

## Ameaça do Barão Corvo Vermelho (time 1) no modo base-builder com ondas (ver docs/DESIGN.md):
## - Covis espalhados pelo mapa, escondidos na névoa, cada um com uma guarnição que se repõe.
## - Enquanto existirem, os covis enviam ondas; as ondas ficam mais fortes e variadas com o tempo.
## - As tropas se reúnem no covil antes de marchar (dá para vê-las se o covil estiver na sua visão).
## - Vitória do jogador: destruir todos os covis (checado em GameManager).

signal wave_launched(lair: RTSBuilding, size: int, kind: String)
signal lair_discovered(lair: RTSBuilding)
signal lair_destroyed(lair: RTSBuilding, remaining: int)

const DIFFICULTY: Dictionary = {
	"facil": {
		"name": "Fácil", "lairs": 2, "first_wave": 780.0, "lair_interval": 430.0,
		"budget_base": 4.0, "budget_growth": 0.6, "budget_accel": 0.012, "garrison": 3, "hp_mult": 0.9, "dmg_mult": 0.9,
	},
	"normal": {
		"name": "Normal", "lairs": 3, "first_wave": 600.0, "lair_interval": 400.0,
		"budget_base": 5.0, "budget_growth": 0.8, "budget_accel": 0.02, "garrison": 4, "hp_mult": 1.0, "dmg_mult": 1.0,
	},
	"dificil": {
		"name": "Difícil", "lairs": 4, "first_wave": 480.0, "lair_interval": 410.0,
		"budget_base": 6.5, "budget_growth": 0.9, "budget_accel": 0.022, "garrison": 5, "hp_mult": 1.12, "dmg_mult": 1.08,
	},
}
const UNIT_POINTS: Dictionary = {
	"spearman": 0.8, "soldier": 1.0, "scout": 0.7, "archer": 1.1, "knight": 2.2, "ram": 3.0, "captain": 5.0,
}
const MAX_BUDGET: float = 62.0
const GATHER_TIME: float = 30.0
const TICK: float = 1.0
const GUARD_LEASH: float = 24.0
## Trompa do covil: atacado, o covil convoca defensores (fração do orçamento de uma onda) e espera este tempo para convocar de novo.
const ALARM_COOLDOWN: float = 75.0
const ALARM_SHARE: float = 1.0
const MAX_GARRISON: int = 12

var team: int = 1
var enemy_team: int = 0
var game_manager: GameManager = null
var difficulty: String = "normal"
var cfg: Dictionary = DIFFICULTY["normal"]
var lairs: Array[RTSBuilding] = []
var lairs_total: int = 0
var player_base: Vector3 = Vector3.ZERO
var announce: bool = true

var _state: Dictionary = {}
var _wave_units: Array[RTSUnit] = []
var _waves_launched: int = 0
var _lairs_destroyed: int = 0
var _lairs_found: int = 0
var _peace_ended_early: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _tick: float = 0.5
var _configured: bool = false


func _ready() -> void:
	_rng.randomize()


func configure(diff: String) -> void:
	difficulty = diff if DIFFICULTY.has(diff) else "normal"
	cfg = DIFFICULTY[difficulty]
	_configured = true
	_reschedule_all()


func lair_count_for(diff: String) -> int:
	var d: Dictionary = DIFFICULTY.get(diff, DIFFICULTY["normal"])
	return int(d["lairs"])


## Registra os covis já posicionados no mapa (time 1) e a posição da base do jogador.
func register_lairs(list: Array[RTSBuilding], p_player_base: Vector3) -> void:
	player_base = p_player_base
	lairs = list.duplicate()
	lairs_total = lairs.size()
	_state.clear()
	for i in range(lairs.size()):
		var l: RTSBuilding = lairs[i]
		_state[l.get_instance_id()] = {
			"index": i,
			"pos": l.global_position,
			"next_wave": 0.0,
			"next_guard": 0.0,
			"guards": [],
			"gathering": [],
			"launch_at": -1.0,
			"discovered": false,
		}
	if _configured:
		_reschedule_all()


func _reschedule_all() -> void:
	var n: int = maxi(1, lairs.size())
	var interval: float = float(cfg["lair_interval"])
	for l in lairs:
		var st: Dictionary = _state.get(l.get_instance_id(), {})
		if st.is_empty():
			continue
		var k: int = int(st["index"])
		st["next_wave"] = float(cfg["first_wave"]) + float(k) * (interval / float(n))
		st["next_guard"] = 0.0
		# Guarnição inicial
		var guards: Array = st["guards"]
		var missing: int = int(cfg["garrison"]) - _alive_count(guards)
		for _i in range(missing):
			var g: RTSUnit = _spawn_enemy(_pick_guard_type(0.0), l)
			if g != null:
				guards.append(g)


func get_threat_info() -> Dictionary:
	_prune_lairs()
	var t: float = game_manager.match_time if game_manager != null else 0.0
	var next_in: float = 1.0e9
	for l in lairs:
		if not _lair_alive(l):
			continue
		var st: Dictionary = _state[l.get_instance_id()]
		next_in = minf(next_in, float(st["next_wave"]) - t)
	var marching: int = 0
	for u in _wave_units:
		if is_instance_valid(u) and not u._dead:
			marching += 1
	return {
		"peace_left": 0.0 if _peace_ended_early else maxf(0.0, float(cfg["first_wave"]) - t),
		"next_wave_in": maxf(0.0, next_in) if next_in < 1.0e8 else -1.0,
		"waves": _waves_launched,
		"wave": _waves_launched,
		"lairs_total": lairs_total,
		"lairs_alive": _alive_lairs(),
		"lairs_found": _lairs_found,
		"lairs_destroyed": _lairs_destroyed,
		"marching": marching,
		"difficulty": String(cfg["name"]),
	}


func can_call_wave_early() -> bool:
	if game_manager == null or not game_manager.match_started or game_manager.is_game_over:
		return false
	var t: float = game_manager.match_time
	for l in lairs:
		if not _lair_alive(l):
			continue
		var st: Dictionary = _state.get(l.get_instance_id(), {})
		if not st.is_empty() and float(st["launch_at"]) < 0.0 and (float(st["next_wave"]) - t) >= 18.0:
			return true
	return false


func call_next_wave_early() -> Dictionary:
	if game_manager == null or not game_manager.match_started or game_manager.is_game_over:
		return {"ok": false}
	var t: float = game_manager.match_time
	var best_l: RTSBuilding = null
	var best_next: float = 1.0e9
	for l in lairs:
		if not _lair_alive(l):
			continue
		var st: Dictionary = _state.get(l.get_instance_id(), {})
		if st.is_empty() or float(st["launch_at"]) >= 0.0:
			continue
		var nw: float = float(st["next_wave"])
		if nw - t >= 18.0 and nw < best_next:
			best_next = nw
			best_l = l
	if best_l == null:
		return {"ok": false}

	var best_st: Dictionary = _state[best_l.get_instance_id()]
	var saved_sec: float = maxf(0.0, best_next - t)
	var bonus_gold: int = clampi(int(round((saved_sec / 60.0) * 24.0 * float(game_manager.player_mods.get("bounty_mult", 1.0)))), 30, 160)
	_peace_ended_early = true
	_gather_wave(best_l, best_st, t)
	best_st["launch_at"] = t + 14.0
	best_st["next_wave"] = t + 14.0
	game_manager.add_resource(0, "gold", bonus_gold)
	if announce:
		game_manager.post_alert("Onda provocada! Tropas do Barão marcham em 14s — Bônus: +%d Ouro!" % bonus_gold, Color(1.0, 0.80, 0.34))
		if game_manager.sfx != null:
			game_manager.sfx.play_horn_alert()
	return {"ok": true, "bonus_gold": bonus_gold, "lair": best_l}


func _process(delta: float) -> void:
	if game_manager == null or not game_manager.match_started or game_manager.is_game_over:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	_update(game_manager.match_time)


func _update(t: float) -> void:
	_prune_lairs()
	for l in lairs:
		if not _lair_alive(l):
			continue
		var st: Dictionary = _state[l.get_instance_id()]
		_check_discovery(l, st)
		_maintain_garrison(l, st, t)
		if float(st["launch_at"]) < 0.0 and t >= float(st["next_wave"]) - GATHER_TIME:
			_gather_wave(l, st, t)
		elif float(st["launch_at"]) >= 0.0 and t >= float(st["launch_at"]):
			_launch_wave(l, st, t)
	_drive_wave_units()


# ==============================================================================
# COVIS: DESCOBERTA, GUARNIÇÃO E DESTRUIÇÃO
# ==============================================================================

## Sem tipo no parâmetro: um covil já liberado não pode passar por um argumento tipado.
func _lair_alive(l: Variant) -> bool:
	return is_instance_valid(l) and not l._dead and not l.is_queued_for_deletion()


## Tira da lista os covis já liberados (destruídos há mais de um quadro).
func _prune_lairs() -> void:
	for i in range(lairs.size() - 1, -1, -1):
		if not is_instance_valid(lairs[i]):
			lairs.remove_at(i)


func _alive_lairs() -> int:
	var n: int = 0
	for l in lairs:
		if _lair_alive(l):
			n += 1
	return n


func _alive_count(arr: Array) -> int:
	var n: int = 0
	for u in arr:
		if is_instance_valid(u) and not u._dead:
			n += 1
	return n


func _check_discovery(l: RTSBuilding, st: Dictionary) -> void:
	if bool(st["discovered"]) or not l.discovered:
		return
	st["discovered"] = true
	_lairs_found += 1
	lair_discovered.emit(l)
	if announce and game_manager != null:
		game_manager.post_alert("Covil do Barão encontrado (%d de %d)! Ele envia ondas até ser destruído." % [_lairs_found, lairs_total], Color(1.0, 0.5, 0.35))
		game_manager.add_ping(l.global_position, Color(1.0, 0.3, 0.25))


func _maintain_garrison(l: RTSBuilding, st: Dictionary, t: float) -> void:
	var guards: Array = st["guards"]
	for i in range(guards.size() - 1, -1, -1):
		if not is_instance_valid(guards[i]) or guards[i]._dead:
			guards.remove_at(i)
	var war_min: float = maxf(0.0, (t - float(cfg["first_wave"])) / 60.0)
	var target: int = _garrison_target(t)
	if guards.size() < target and t >= float(st["next_guard"]):
		st["next_guard"] = t + 40.0
		var g: RTSUnit = _spawn_enemy(_pick_guard_type(war_min), l)
		if g != null:
			guards.append(g)
	# Guardas que se afastaram demais voltam para o covil
	for g in guards:
		var gu: RTSUnit = g
		if gu.global_position.distance_to(l.global_position) > GUARD_LEASH and (gu.state == RTSUnit.State.IDLE or gu.state == RTSUnit.State.CHASING):
			gu.command_move(_ring_point(l, 6.5, 9.0))


## Guarnição fixa de cada covil: cresce 1 a cada 5 min de guerra.
func _garrison_target(t: float) -> int:
	var war_min: float = maxf(0.0, (t - float(cfg["first_wave"])) / 60.0)
	return mini(MAX_GARRISON, int(cfg["garrison"]) + int(war_min / 5.0))


## Trompa do covil: atacado, convoca defensores do tamanho de uma onda daquele momento (× ALARM_SHARE).
## Os defensores entram na guarnição (voltam ao covil depois) e não se acumulam além de guarnição + uma leva.
func _sound_alarm(l: RTSBuilding, st: Dictionary, attacker: Node3D, t: float) -> int:
	if t < float(st.get("alarm_ready", 0.0)):
		return 0
	st["alarm_ready"] = t + ALARM_COOLDOWN
	var guards: Array = st["guards"]
	var types: Array[String] = _compose_wave(t, true)
	var limit: int = _garrison_target(t) + types.size()
	var have: int = _alive_count(guards)
	var spawned: int = 0
	for u_type in types:
		if have + spawned >= limit:
			break
		var u: RTSUnit = _spawn_enemy(u_type, l)
		if u == null:
			continue
		guards.append(u)
		spawned += 1
		if attacker != null and is_instance_valid(attacker):
			u.command_attack_move(attacker.global_position)
	if spawned > 0 and announce and game_manager != null and bool(st["discovered"]):
		game_manager.post_alert("O covil tocou a trompa: %d defensores saíram para lutar!" % spawned, Color(1.0, 0.5, 0.3))
		if game_manager.sfx != null:
			game_manager.sfx.play_horn_alert()
	return spawned


func _pick_guard_type(war_min: float) -> String:
	var r: float = _rng.randf()
	if war_min > 18.0 and r < 0.2:
		return "knight"
	if r < 0.45:
		return "archer"
	if r < 0.75:
		return "spearman"
	return "soldier"


func on_lair_destroyed(l: RTSBuilding) -> void:
	_lairs_destroyed += 1
	var st: Dictionary = _state.get(l.get_instance_id(), {})
	var remaining: int = _alive_lairs()
	if not st.is_empty():
		# Guarnição e tropas reunidas partem para a vingança
		for arr in [st["guards"], st["gathering"]]:
			for u in arr:
				if is_instance_valid(u) and not u._dead:
					var ru: RTSUnit = u
					_send_unit(ru, _pick_target_for(ru), false)
					if not (ru in _wave_units):
						_wave_units.append(ru)
		(st["guards"] as Array).clear()
		(st["gathering"] as Array).clear()
	lair_destroyed.emit(l, remaining)
	if announce and game_manager != null and remaining > 0:
		game_manager.post_alert("Covil destruído! Restam %d. Menos covis = menos ondas." % remaining, Color(1.0, 0.86, 0.35))


# ==============================================================================
# ONDAS
# ==============================================================================

## Orçamento de uma onda: começa pequeno e acelera (termo quadrático) com os minutos de guerra.
func _budget_at(t: float) -> float:
	var war_min: float = maxf(0.0, (t - float(cfg["first_wave"])) / 60.0)
	var b: float = float(cfg["budget_base"]) + float(cfg["budget_growth"]) * war_min + float(cfg.get("budget_accel", 0.0)) * war_min * war_min
	return minf(MAX_BUDGET, b)


func _is_raid_wave() -> bool:
	return _waves_launched >= 3 and (_waves_launched + 1) % 4 == 0


## for_defense: leva convocada pela trompa do covil (sem incursão nem aríetes, orçamento × ALARM_SHARE).
func _compose_wave(t: float, for_defense: bool = false) -> Array[String]:
	var budget: float = _budget_at(t)
	var war_min: float = maxf(0.0, (t - float(cfg["first_wave"])) / 60.0)
	var out: Array[String] = []
	if for_defense:
		budget *= ALARM_SHARE
	elif _is_raid_wave():
		# Incursão rápida contra a economia
		while budget >= 0.7:
			var pick: String = "scout" if _rng.randf() < 0.6 else "soldier"
			out.append(pick)
			budget -= float(UNIT_POINTS[pick])
		return out
	# Unidades especiais conforme a guerra avança
	if war_min >= 16.0 and not for_defense:
		var rams: int = mini(4, 1 + int((war_min - 16.0) / 10.0))
		for _i in range(rams):
			if budget >= 6.0:
				out.append("ram")
				budget -= float(UNIT_POINTS["ram"])
	if war_min >= 24.0 and budget >= 18.0:
		out.append("captain")
		budget -= float(UNIT_POINTS["captain"])
		if war_min >= 36.0 and budget >= 30.0:
			out.append("captain")
			budget -= float(UNIT_POINTS["captain"])
	var weights: Dictionary
	if war_min < 6.0:
		weights = {"spearman": 0.45, "soldier": 0.45, "scout": 0.10}
	elif war_min < 12.0:
		weights = {"soldier": 0.35, "spearman": 0.25, "archer": 0.30, "scout": 0.10}
	elif war_min < 20.0:
		weights = {"soldier": 0.30, "spearman": 0.20, "archer": 0.30, "knight": 0.15, "scout": 0.05}
	else:
		weights = {"soldier": 0.25, "spearman": 0.17, "archer": 0.30, "knight": 0.28}
	var guard: int = 200
	while budget >= 0.8 and guard > 0:
		guard -= 1
		var pick2: String = _weighted_pick(weights)
		var cost: float = float(UNIT_POINTS[pick2])
		if cost > budget:
			pick2 = "spearman"
			cost = float(UNIT_POINTS[pick2])
		out.append(pick2)
		budget -= cost
	return out


func _weighted_pick(weights: Dictionary) -> String:
	var total: float = 0.0
	for k in weights.keys():
		total += float(weights[k])
	var r: float = _rng.randf() * total
	for k in weights.keys():
		r -= float(weights[k])
		if r <= 0.0:
			return String(k)
	return String(weights.keys()[0])


func _wave_kind(types: Array[String]) -> String:
	var counts: Dictionary = {}
	for t in types:
		counts[t] = int(counts.get(t, 0)) + 1
	if counts.has("captain"):
		return "Elite do Corvo"
	if counts.has("ram"):
		return "Cerco"
	if int(counts.get("scout", 0)) * 2 >= types.size():
		return "Incursão"
	if int(counts.get("knight", 0)) * 4 >= types.size():
		return "Cavalaria pesada"
	if int(counts.get("archer", 0)) * 3 >= types.size():
		return "Arqueiros"
	if _waves_launched < 2:
		return "Milícia"
	return "Infantaria"


func _gather_wave(l: RTSBuilding, st: Dictionary, t: float) -> void:
	var types: Array[String] = _compose_wave(t + GATHER_TIME)
	var gathering: Array = st["gathering"]
	gathering.clear()
	for u_type in types:
		var u: RTSUnit = _spawn_enemy(u_type, l)
		if u != null:
			gathering.append(u)
	st["launch_at"] = t + GATHER_TIME
	st["kind"] = _wave_kind(types)


func _launch_wave(l: RTSBuilding, st: Dictionary, t: float) -> void:
	var gathering: Array = st["gathering"]
	var units: Array[RTSUnit] = []
	for u in gathering:
		if is_instance_valid(u) and not u._dead:
			units.append(u)
	gathering.clear()
	st["launch_at"] = -1.0
	var interval: float = float(cfg["lair_interval"]) * _rng.randf_range(0.9, 1.1)
	st["next_wave"] = t + interval
	if units.is_empty():
		return
	_waves_launched += 1
	var kind: String = String(st.get("kind", "Infantaria"))
	var raid: bool = kind == "Incursão"
	var target: Node3D = _pick_raid_target(l) if raid else _pick_main_target(l)
	var offsets: Array[Vector3] = game_manager.get_formation_offsets(units.size())
	for i in range(units.size()):
		var u: RTSUnit = units[i]
		_send_unit(u, target, true, offsets[i])
		_wave_units.append(u)
	wave_launched.emit(l, units.size(), kind)
	if announce and game_manager != null:
		var origin: String = " de um covil escondido na névoa"
		if bool(st["discovered"]):
			origin = " do covil a %s" % _direction_name(l.global_position)
		game_manager.post_alert("Onda %d (%s, %d tropas) saiu%s!" % [_waves_launched, kind, units.size(), origin], Color(1.0, 0.35, 0.28))
		if bool(st["discovered"]):
			game_manager.add_ping(l.global_position, Color(1.0, 0.35, 0.28), false)
		if game_manager.sfx != null:
			game_manager.sfx.play_horn_alert()


func _direction_name(pos: Vector3) -> String:
	var d: Vector3 = pos - player_base
	var ang: float = atan2(d.x, -d.z)
	var names: Array[String] = ["norte", "nordeste", "leste", "sudeste", "sul", "sudoeste", "oeste", "noroeste"]
	var idx: int = int(round(ang / (PI / 4.0))) % 8
	if idx < 0:
		idx += 8
	return names[idx]


func _send_unit(u: RTSUnit, target: Node3D, use_offset: bool, offset: Vector3 = Vector3.ZERO) -> void:
	if target == null:
		u.command_attack_move(player_base)
		return
	if u.is_siege and target is RTSBuilding:
		u.command_attack(target)
	elif use_offset:
		u.command_attack_move(target.global_position + offset)
	else:
		u.command_attack_move(target.global_position)


func _pick_main_target(from: RTSBuilding) -> Node3D:
	var best: Node3D = null
	var best_d: float = 1.0e9
	for b in game_manager.buildings:
		if not is_instance_valid(b) or b._dead or b.team != enemy_team:
			continue
		var d: float = b.global_position.distance_to(from.global_position)
		if b.is_main_structure:
			d -= 40.0
		if d < best_d:
			best_d = d
			best = b
	return best


func _pick_raid_target(from: RTSBuilding) -> Node3D:
	# Camponeses ou pontos de entrega mais próximos do covil
	var best: Node3D = null
	var best_d: float = 1.0e9
	for u in game_manager.units:
		if is_instance_valid(u) and not u._dead and u.team == enemy_team and u.unit_type == "worker":
			var d: float = u.global_position.distance_to(from.global_position)
			if d < best_d:
				best_d = d
				best = u
	for b in game_manager.buildings:
		if is_instance_valid(b) and not b._dead and b.team == enemy_team and not b.drop_types.is_empty() and b.building_type != "town_center":
			var d2: float = b.global_position.distance_to(from.global_position) + 10.0
			if d2 < best_d:
				best_d = d2
				best = b
	return best if best != null else _pick_main_target(from)


func _pick_target_for(u: RTSUnit) -> Node3D:
	var best: Node3D = null
	var best_d: float = 1.0e9
	for b in game_manager.buildings:
		if not is_instance_valid(b) or b._dead or b.team != enemy_team:
			continue
		var d: float = b.global_position.distance_to(u.global_position)
		if b.is_main_structure:
			d -= 20.0
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


func _drive_wave_units() -> void:
	for i in range(_wave_units.size() - 1, -1, -1):
		var raw: Variant = _wave_units[i]
		if not is_instance_valid(raw) or raw._dead:
			_wave_units.remove_at(i)
			continue
		var u: RTSUnit = raw
		if u.state == RTSUnit.State.IDLE:
			_send_unit(u, _pick_target_for(u), false)


# ==============================================================================
# SPAWN E REAÇÃO A DANO
# ==============================================================================

func _ring_point(l: RTSBuilding, r_min: float, r_max: float) -> Vector3:
	var ang: float = _rng.randf() * TAU
	var r: float = _rng.randf_range(r_min, r_max)
	return l.global_position + Vector3(cos(ang) * r, 0.0, sin(ang) * r)


func _spawn_enemy(u_type: String, l: RTSBuilding) -> RTSUnit:
	if game_manager == null or not _lair_alive(l):
		return null
	var pos: Vector3 = _ring_point(l, l.footprint_radius + 2.0, l.footprint_radius + 6.0)
	var u: RTSUnit = game_manager.spawn_unit(u_type, pos, team)
	if u == null:
		return null
	var hp_m: float = float(cfg["hp_mult"])
	var dmg_m: float = float(cfg["dmg_mult"])
	u.max_hp *= hp_m
	u.hp = u.max_hp
	u.attack_damage *= dmg_m
	u._update_hp_bar()
	return u


func on_ai_entity_damaged(victim: Variant, attacker: Variant) -> void:
	if victim == null or not is_instance_valid(victim) or attacker == null or not is_instance_valid(attacker):
		return
	if (attacker as Node).is_queued_for_deletion():
		return
	var vpos: Vector3 = (victim as Node3D).global_position
	# Guarnição defende o próprio covil
	for l in lairs:
		if not _lair_alive(l) or l.global_position.distance_to(vpos) > GUARD_LEASH + 6.0:
			continue
		var st: Dictionary = _state[l.get_instance_id()]
		if "team" in attacker and int(attacker.team) == enemy_team:
			_sound_alarm(l, st, attacker as Node3D, game_manager.match_time)
		for arr in [st["guards"], st["gathering"]]:
			for g in arr:
				if is_instance_valid(g) and not g._dead and not g.is_siege:
					if g.state == RTSUnit.State.IDLE or g.state == RTSUnit.State.MOVING:
						g.command_attack(attacker)
	# Tropas em marcha próximas ajudam
	for u in game_manager.query_units(vpos, 18.0):
		if is_instance_valid(u) and not u._dead and u.team == team and not u.is_siege:
			if u.state == RTSUnit.State.IDLE or u.state == RTSUnit.State.ATTACK_MOVING:
				u.command_attack(attacker)
