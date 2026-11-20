extends SceneTree

## Simula uma partida completa no modo de ondas: uma IA (AIController) joga no lugar do jogador
## (economia, defesa e caça aos covis) contra o WaveDirector do Barão. Valida o ritmo
## início/meio/fim: trégua, ondas crescentes, covis destruídos e a condição de vitória/derrota.
##
## Uso (rápido, sem renderização; --fixed-fps faz cada quadro valer exatamente 1/60 s):
##   godot --headless --path . --fixed-fps 60 --script tools/simulate_match.gd -- --minutes=60 --seed=7 --difficulty=normal
##   (--difficulty0=facil|normal|dificil muda só a força da IA que joga pelo time 0)

var _main: Node = null
var _gm: GameManager = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var limit_min: float = 60.0
	var seed_v: int = 7
	var diff: String = "normal"
	var diff0: String = ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--minutes="):
			limit_min = float(a.get_slice("=", 1))
		elif a.begins_with("--seed="):
			seed_v = int(a.get_slice("=", 1))
		elif a.begins_with("--difficulty="):
			diff = a.get_slice("=", 1)
		elif a.begins_with("--difficulty0="):
			diff0 = a.get_slice("=", 1)

	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	_main = scene.instantiate()
	_main.set("auto_start", true)
	_main.set("ai_vs_ai", true)
	_main.set("map_seed", seed_v)
	_main.set("start_difficulty", diff)
	_main.set("team0_difficulty", diff0)
	root.add_child(_main)
	await process_frame
	_gm = _main.get_node("GameManager") as GameManager
	var p_slot: Dictionary = _main.get("player_slot")
	var lair_list: Array = _main.get("lairs")
	var lair_pos: Array[String] = []
	for l in lair_list:
		lair_pos.append(str(snapped((l as Node3D).global_position, Vector3(1, 1, 1))))
	print("SIM_START seed=%d waves=%s player_ai=%s base=%s lairs=%s" % [seed_v, diff, diff0 if diff0 != "" else diff, String(p_slot.get("name", "?")), ", ".join(lair_pos)])

	var t_real0: int = Time.get_ticks_msec()
	var next_report: float = 60.0
	while true:
		await process_frame
		if _gm.is_game_over:
			break
		if _gm.match_time >= limit_min * 60.0:
			break
		if _gm.match_time >= next_report:
			next_report += 60.0
			_report(t_real0)

	_report(t_real0)
	if _gm.is_game_over:
		var why: String = "covis destruídos (vitória do jogador)" if _gm.winner_team == 0 else "base do jogador destruída (derrota)"
		print("SIM_RESULT winner=team%d at %s (%.1f min) — %s" % [_gm.winner_team, _fmt(_gm.match_time), _gm.match_time / 60.0, why])
	else:
		print("SIM_RESULT no_winner after %s" % _fmt(_gm.match_time))
	print("SIM_STATS team0 %s" % str(_gm.team_stats[0]))
	quit(0 if _gm.is_game_over else 2)


func _fmt(secs: float) -> String:
	return "%02d:%02d" % [int(secs) / 60, int(secs) % 60]


func _report(t_real0: int) -> void:
	var real_s: float = float(Time.get_ticks_msec() - t_real0) / 1000.0
	var units_by: Dictionary = {}
	var blds_by: Dictionary = {}
	var enemies: int = 0
	for u in _gm.units:
		if not is_instance_valid(u) or u._dead:
			continue
		if u.team == 0:
			units_by[u.unit_type] = int(units_by.get(u.unit_type, 0)) + 1
		else:
			enemies += 1
	for b in _gm.buildings:
		if is_instance_valid(b) and not b._dead and b.team == 0:
			var key: String = b.building_type + ("" if b.is_constructed else "*")
			blds_by[key] = int(blds_by.get(key, 0)) + 1
	var director: WaveDirector = _gm.ai_controllers.get(1, null) as WaveDirector
	var info: Dictionary = director.get_threat_info() if director != null else {}
	var ai0: AIController = _gm.ai_controllers.get(0, null) as AIController
	print("T=%s real=%.0fs fps_equiv=%.0f | P pop %d/%d res F%d W%d G%d S%d attacks %d units %s blds %s | E lairs %d/%d waves %d marching %d enemies %d" % [
		_fmt(_gm.match_time), real_s, (_gm.match_time / maxf(0.001, real_s)) * 60.0,
		_gm.get_team_pop_used(0), _gm.get_team_pop_cap(0),
		_gm.get_res(0, "food"), _gm.get_res(0, "wood"), _gm.get_res(0, "gold"), _gm.get_res(0, "stone"),
		ai0._wave_count if ai0 != null else -1, str(units_by), str(blds_by),
		int(info.get("lairs_alive", 0)), int(info.get("lairs_total", 0)), int(info.get("waves", 0)),
		int(info.get("marching", 0)), enemies])
