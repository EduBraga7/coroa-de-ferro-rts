extends Node3D

## Bootstrapper da partida 'Coroa de Ferro: Crônicas da Fronteira' (base-builder com ondas, ver docs/DESIGN.md).
## Fluxo: menu inicial (dificuldade/névoa) -> trégua -> ondas saindo de covis sorteados e escondidos
## na névoa -> vitória ao destruir todos os covis, derrota ao perder todos os Salões Reais/Castelos.
##
## Argumentos (após "--" na linha de comando):
##   --autostart                 pula o menu inicial (Normal, névoa ligada)
##   --seed=N                    semente do sorteio das bases e do mapa
##   --difficulty=facil|normal|dificil
##   --no-fog                    desliga a névoa de guerra
##   --aivai                     IA também controla o time 0 (simulação)
##   --screenshot, --screenshot-river, --screenshot-units   capturas de preview (legado)
##   --shot-out=CAMINHO --shot-at=SEG --shot-focus=X,Z --shot-zoom=Z --shot-menu   capturas de verificação

const TERRAIN_HALF: float = GameManager.TERRAIN_HALF
const TIPS: Array = [
	[9.0, "Dica: explore a névoa com o Batedor para achar Caravanas e Baús perdidos! Use [N] quando ganhar um Decreto Real ou [K] para provocar a próxima onda e lucrar Ouro."],
	[28.0, "Dica: [F9] alterna a qualidade gráfica (Alta, Equilibrada, Leve) se o jogo ficar pesado."],
	[45.0, "Dica: Casas dão +8 de população. Com um camponês selecionado, a aba Economia [B] mostra as construções."],
	[100.0, "Dica: Moinho perto dos frutos, Serraria na floresta e Mineração junto ao ouro/pedra encurtam as viagens."],
	[160.0, "Dica: os covis do Barão estão escondidos do outro lado do rio. Abates dão Ouro em saque e promovem suas tropas a Veteranos!"],
	[250.0, "Dica: Fazendas (60 madeira) dão comida contínua quando os frutos acabarem. Construa perto do Moinho."],
	[370.0, "Dica: use [Q] Investida nas tropas, [E] Manter Posição para segurar a linha e [R] Sino de Defesa no Salão Real!"],
	[480.0, "Dica: os melhores recursos (minas ricas) ficam perto dos covis, longe da sua base."],
]

var game_manager: GameManager
var camera_rig: RTSCamera
var wave_director: WaveDirector
var ai_team0: AIController = null
var sfx_manager: SFXManager
var vfx_manager: VFXManager
var hud: RTSHUD
var fog: FogOfWar
var map_gen: MapGenerator
var graphics: GraphicsSettings
var world_root: Node3D
var _bridge_lights: Array[OmniLight3D] = []

var auto_start: bool = false
var ai_vs_ai: bool = false
var start_difficulty: String = "normal"
var team0_difficulty: String = ""
var start_fog: bool = true
var map_seed: int = -1
var player_slot: Dictionary = {}
var lairs: Array[RTSBuilding] = []
var _lair_candidates: Array[Vector3] = []

var _screenshot_mode: bool = false
var _screenshot_river: bool = false
var _screenshot_units: bool = false
var _shot_out: String = ""
var _shot_at: float = 3.2
var _shot_focus: Variant = null
var _shot_zoom: float = -1.0
var _shot_menu: bool = false
var _shot_select: String = ""
var _shot_end: String = ""
var _shot_wave: bool = false
var _screenshot_timer: float = 0.0
var _recent_deltas: Array[float] = []
var _tip_idx: int = 0
var _peace_warned: bool = false


func _ready() -> void:
	_parse_args()

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	if map_seed >= 0:
		rng.seed = map_seed
	else:
		rng.randomize()

	map_gen = MapGenerator.new()
	map_gen.load_layout()

	vfx_manager = VFXManager.new()
	vfx_manager.name = "VFXManager"
	add_child(vfx_manager)

	_setup_environment_and_lights()
	_setup_terrain_and_river()
	_setup_systems()

	var props_root: Node3D = Node3D.new()
	props_root.name = "SceneryLandmarks"
	world_root.add_child(props_root)
	map_gen.populate(game_manager, props_root, rng)
	_setup_graphics_settings()

	var picks: Dictionary = map_gen.choose_start_slots(rng)
	player_slot = map_gen.get_slot(int(picks["player"]))
	_spawn_starting_base(0, player_slot)
	game_manager.team_base_pos = {0: player_slot["pos"]}
	# Os covis só são erguidos ao iniciar (a quantidade depende da dificuldade escolhida no menu)
	_lair_candidates = map_gen.lair_candidates(int(player_slot["side"]), rng)
	if ai_vs_ai:
		# Simulação: uma IA joga no lugar do jogador (economia, defesa e caça aos covis)
		ai_team0 = AIController.new()
		ai_team0.name = "AIControllerTeam0"
		ai_team0.team = 0
		ai_team0.enemy_team = 1
		ai_team0.game_manager = game_manager
		ai_team0.attack_start_override = 900.0
		add_child(ai_team0)
		ai_team0.setup_base(player_slot["pos"], Vector3.ZERO)
		game_manager.ai_controllers[0] = ai_team0

	game_manager.recalculate_population()
	fog.update_now()
	game_manager.focus_camera_on_base()
	camera_rig.global_position = camera_rig.target_pos

	if _screenshot_mode:
		auto_start = true
	if auto_start:
		start_match(start_difficulty, start_fog)
	else:
		get_tree().paused = true
		hud.show_start_menu(start_difficulty, start_fog)

	if _screenshot_mode:
		_apply_screenshot_framing()


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--screenshot":
			_screenshot_mode = true
		elif arg == "--screenshot-river":
			_screenshot_mode = true
			_screenshot_river = true
		elif arg == "--screenshot-units":
			_screenshot_mode = true
			_screenshot_units = true
		elif arg == "--autostart":
			auto_start = true
		elif arg == "--no-fog" or arg == "--reveal":
			start_fog = false
		elif arg == "--aivai":
			ai_vs_ai = true
			auto_start = true
		elif arg.begins_with("--seed="):
			map_seed = int(arg.get_slice("=", 1))
		elif arg.begins_with("--difficulty="):
			start_difficulty = arg.get_slice("=", 1)
		elif arg.begins_with("--shot-out="):
			_screenshot_mode = true
			_shot_out = arg.get_slice("=", 1)
		elif arg.begins_with("--shot-at="):
			_shot_at = float(arg.get_slice("=", 1))
		elif arg.begins_with("--shot-focus="):
			var parts: PackedStringArray = arg.get_slice("=", 1).split(",")
			if parts.size() == 2:
				_shot_focus = Vector3(float(parts[0]), 0.0, float(parts[1]))
		elif arg.begins_with("--shot-zoom="):
			_shot_zoom = float(arg.get_slice("=", 1))
		elif arg == "--shot-menu":
			_shot_menu = true
		elif arg.begins_with("--shot-select="):
			_shot_select = arg.get_slice("=", 1)
		elif arg.begins_with("--shot-end="):
			_shot_end = arg.get_slice("=", 1)
		elif arg == "--shot-wave":
			_screenshot_mode = true
			_shot_wave = true


func start_match(difficulty: String, fog_on: bool) -> void:
	start_difficulty = difficulty if WaveDirector.DIFFICULTY.has(difficulty) else "normal"
	game_manager.difficulty = start_difficulty
	if lairs.is_empty():
		_spawn_lairs(wave_director.lair_count_for(start_difficulty))
	if game_manager.caches.is_empty():
		_spawn_frontier_encounters()
	wave_director.configure(start_difficulty)
	if ai_team0 != null:
		ai_team0.configure(team0_difficulty if AIController.DIFFICULTY.has(team0_difficulty) else start_difficulty)
		if not lairs.is_empty():
			ai_team0.setup_base(player_slot["pos"], _nearest_lair_pos(player_slot["pos"]))
	fog.set_enabled(fog_on)
	game_manager.match_started = true
	get_tree().paused = false
	hud.on_match_started()
	game_manager.recalculate_population()
	game_manager.focus_camera_on_base()
	var peace_min: int = int(float(WaveDirector.DIFFICULTY[start_difficulty]["first_wave"]) / 60.0)
	game_manager.post_alert("Bem-vindo, Comandante! Você começa em %s. %d covis do Barão estão escondidos na névoa — a primeira onda chega em ~%d min." % [String(player_slot.get("name", "?")), lairs.size(), peace_min], Color(1.0, 0.86, 0.35))


## Ergue os covis do Barão em pontos sorteados do outro lado do rio (longe da base e entre si)
## e enriquece as minas ao redor: os melhores recursos ficam longe de casa (docs/DESIGN.md).
func _spawn_lairs(count: int) -> void:
	var base: Vector3 = player_slot["pos"]
	var rad: float = float(RTSBuilding.STATS["lair"]["radius"])
	for cand in _lair_candidates:
		if lairs.size() >= count:
			break
		if cand.distance_to(base) < 75.0:
			continue
		var too_close: bool = false
		for l in lairs:
			if l.global_position.distance_to(cand) < 40.0:
				too_close = true
				break
		if too_close:
			continue
		var spot: Vector3 = _find_lair_spot(cand, rad)
		if spot.x == INF:
			continue
		var lair: RTSBuilding = game_manager.place_building_at("lair", spot, 1, true)
		if lair == null:
			continue
		lairs.append(lair)
		_enrich_resources_near(spot)
	game_manager.lairs_total = lairs.size()
	wave_director.register_lairs(lairs, base)
	fog.update_now()


## Popula pontos de interesse vivos (caravanas, baús, arsenais, estandartes) e pequenas patrulhas além-rio
## para recompensar exploração desde os primeiros segundos da partida.
func _spawn_frontier_encounters() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	if map_seed >= 0:
		rng.seed = map_seed + 9173
	else:
		rng.randomize()

	var base: Vector3 = player_slot.get("pos", Vector3(-66.0, 0.0, 66.0))
	var p_side: float = 1.0 if RTSUnit.river_signed_at(base.x, base.z) >= 0.0 else -1.0
	var to_center: Vector3 = Vector3(-base.x, 0.0, -base.z)
	to_center.y = 0.0
	if to_center.length_squared() < 1.0:
		to_center = Vector3(1.0, 0.0, -1.0)
	to_center = to_center.normalized()

	var specs: Array = [
		{"kind": "supplies", "same_side": true, "min_d": 26.0, "max_d": 48.0, "guarded": false, "bias_center": true},
		{"kind": "treasury", "same_side": true, "min_d": 34.0, "max_d": 76.0, "guarded": false, "bias_center": false},
		{"kind": "armory", "same_side": true, "min_d": 40.0, "max_d": 88.0, "guarded": false, "bias_center": false},
		{"kind": "treasury", "same_side": false, "min_d": 50.0, "max_d": 175.0, "guarded": true, "bias_center": false},
		{"kind": "banner", "same_side": false, "min_d": 55.0, "max_d": 180.0, "guarded": true, "bias_center": false},
		{"kind": "armory", "same_side": false, "min_d": 48.0, "max_d": 170.0, "guarded": false, "bias_center": false},
		{"kind": "supplies", "same_side": false, "min_d": 48.0, "max_d": 170.0, "guarded": false, "bias_center": false},
	]

	var placed_pts: Array[Vector3] = []
	for sp in specs:
		var want_same: bool = bool(sp["same_side"])
		var min_d: float = float(sp["min_d"])
		var max_d: float = float(sp["max_d"])
		var spot: Vector3 = Vector3(INF, 0.0, INF)

		for attempt in range(160):
			var cand: Vector3
			if attempt < 30 and bool(sp["bias_center"]):
				var d: float = rng.randf_range(min_d, minf(max_d, 42.0))
				var spread: Vector3 = Vector3(-to_center.z, 0.0, to_center.x) * rng.randf_range(-14.0, 14.0)
				cand = base + to_center * d + spread
			else:
				cand = Vector3(rng.randf_range(-88.0, 88.0), 0.0, rng.randf_range(-88.0, 88.0))

			var s_cand: float = RTSUnit.river_signed_at(cand.x, cand.z)
			if want_same and (s_cand * p_side <= 0.0):
				continue
			if not want_same and (s_cand * p_side >= 0.0):
				continue
			var db: float = Vector2(cand.x - base.x, cand.z - base.z).length()
			if db < min_d or db > max_d:
				continue
			var too_close: bool = false
			for pp in placed_pts:
				if Vector2(cand.x - pp.x, cand.z - pp.z).length() < 18.0:
					too_close = true
					break
			for l in lairs:
				if is_instance_valid(l) and cand.distance_to(l.global_position) < 14.0:
					too_close = true
					break
			if too_close:
				continue
			if not game_manager.is_valid_building_spot(cand, 1.4, 1):
				continue
			spot = cand
			break

		if spot.x == INF:
			continue
		var fc: FrontierCache = game_manager.spawn_cache(String(sp["kind"]), spot)
		if fc == null:
			continue
		placed_pts.append(spot)

		if bool(sp["guarded"]) and spot.distance_to(base) >= 48.0:
			var guard_types: Array = ["scout", "spearman"] if rng.randf() < 0.5 else ["soldier", "archer"]
			for gi in range(guard_types.size()):
				var g_ang: float = rng.randf() * TAU + float(gi) * PI
				var g_pos: Vector3 = spot + Vector3(cos(g_ang), 0.0, sin(g_ang)) * 3.0
				if game_manager.nav != null and not game_manager.nav.is_walkable_world(g_pos):
					g_pos = spot
				game_manager.spawn_unit(String(guard_types[gi]), g_pos, 1)
	if fog != null:
		fog.update_now()


func _find_lair_spot(center: Vector3, rad: float) -> Vector3:
	var ring: float = 0.0
	while ring <= 16.0:
		var steps: int = maxi(1, int(ring * 1.2))
		for i in range(steps):
			var ang: float = TAU * float(i) / float(steps)
			var p: Vector3 = center + Vector3(cos(ang), 0.0, sin(ang)) * ring
			if game_manager.is_valid_building_spot(p, rad + 1.5, 1):
				return p
		ring += 2.0
	return Vector3(INF, 0.0, INF)


func _enrich_resources_near(pos: Vector3) -> void:
	var has_gold: bool = false
	for r in game_manager.resources:
		if not is_instance_valid(r) or r.global_position.distance_to(pos) > 30.0:
			continue
		if r.kind == "gold_mine":
			r.max_amount = maxi(int(r.max_amount * 1.6), 2400)
			r.amount_left = r.max_amount
			has_gold = true
		elif r.kind == "stone_quarry":
			r.max_amount = maxi(int(r.max_amount * 1.6), 1800)
			r.amount_left = r.max_amount
	if has_gold:
		return
	for ring in [10.0, 13.0, 16.0, 19.0]:
		for i in range(10):
			var ang: float = TAU * float(i) / 10.0
			var p: Vector3 = pos + Vector3(cos(ang), 0.0, sin(ang)) * ring
			if game_manager.is_valid_building_spot(p, 2.6, 1):
				game_manager.spawn_resource("gold_mine", p, 2400)
				return


func _nearest_lair_pos(from: Vector3) -> Vector3:
	var best: Vector3 = Vector3.ZERO
	var best_d: float = 1.0e9
	for l in lairs:
		if is_instance_valid(l) and l.global_position.distance_to(from) < best_d:
			best_d = l.global_position.distance_to(from)
			best = l.global_position
	return best


func _apply_screenshot_framing() -> void:
	camera_rig.edge_pan_enabled = false
	if _shot_menu:
		get_tree().paused = true
		hud.show_start_menu(start_difficulty, start_fog)
		_screenshot_mode = false
		get_tree().create_timer(2.0, true).timeout.connect(func() -> void:
			_capture_screenshot(0.0)
		)
	if _screenshot_units:
		_setup_units_showcase_screenshot()
	elif _screenshot_river:
		camera_rig.focus_on(Vector3(-22.0, 0.0, -22.0), true)
		camera_rig.set_zoom_instant(34.0)
	if _shot_zoom > 0.0:
		camera_rig.max_zoom = maxf(camera_rig.max_zoom, _shot_zoom)
		camera_rig.map_limit = 140.0
		camera_rig.set_zoom_instant(_shot_zoom)
	if _shot_focus != null:
		camera_rig.focus_on(_shot_focus as Vector3, true)
	if _shot_select != "":
		_select_for_screenshot.call_deferred(_shot_select)
	if _shot_wave and not lairs.is_empty():
		# Captura: o primeiro covil reúne uma onda do meio da partida (~15 min de guerra) e a segura ali
		var st: Dictionary = wave_director._state.get(lairs[0].get_instance_id(), {})
		if not st.is_empty():
			var mid_war: float = float(WaveDirector.DIFFICULTY[start_difficulty]["first_wave"]) + 15.0 * 60.0
			wave_director._gather_wave(lairs[0], st, mid_war)
		if _shot_focus == null:
			camera_rig.focus_on(lairs[0].global_position, true)


func _select_for_screenshot(what: String) -> void:
	game_manager.clear_selection()
	var page: String = ""
	if what.ends_with(":mil"):
		page = "mil"
		what = what.trim_suffix(":mil")
	if what == "lair" and not lairs.is_empty():
		# Covil do Barão: marca como descoberto, seleciona e centraliza a câmera nele
		var lair: RTSBuilding = lairs[0]
		lair.discovered = true
		game_manager.selected_building = lair
		lair.set_selected(true)
		if _shot_focus == null:
			camera_rig.focus_on(lair.global_position, true)
	elif RTSBuilding.STATS.has(what) and what != "town_center":
		# Ergue o prédio pronto perto do Salão Real só para a captura
		var base: Vector3 = player_slot["pos"]
		var to_c: Vector3 = Vector3(-base.x, 0.0, -base.z).normalized()
		var rad: float = float(RTSBuilding.STATS[what]["radius"])
		for ring in range(4, 30, 2):
			var found: bool = false
			for i in range(16):
				var a: float = TAU * float(i) / 16.0
				var p: Vector3 = base + to_c * 8.0 + Vector3(cos(a), 0.0, sin(a)) * float(ring)
				if game_manager.is_valid_building_spot(p, rad, 0):
					var nb: RTSBuilding = game_manager.place_building_at(what, p, 0, true)
					game_manager.selected_building = nb
					nb.set_selected(true)
					camera_rig.focus_on(p, true)
					found = true
					break
			if found:
				break
	elif what == "tc":
		for b in game_manager.buildings:
			if b.team == 0 and b.building_type == "town_center":
				game_manager.selected_building = b
				b.set_selected(true)
				break
	else:
		for u in game_manager.units:
			if u.team == 0 and u.unit_type == what:
				u.set_selected(true)
				game_manager.selected_units.append(u)
				break
	if page != "":
		hud._cmd_page = page
	game_manager.selection_changed.emit()


func _setup_units_showcase_screenshot() -> void:
	wave_director.set_process(false)
	var base: Vector3 = player_slot["pos"]
	var to_c: Vector3 = (-base).normalized()
	var side: Vector3 = Vector3(-to_c.z, 0.0, to_c.x)
	var origin: Vector3 = base + to_c * 12.0
	var types: Array[String] = ["worker", "scout", "soldier", "spearman", "archer", "knight", "ram"]
	for i in range(types.size()):
		var p0: Vector3 = origin + side * (float(i) - 3.0) * 2.6
		var bu: RTSUnit = game_manager.spawn_unit(types[i], p0, 0)
		if bu != null:
			bu.command_stop()
			bu._scan_timer = 9999.0
		var ru: RTSUnit = game_manager.spawn_unit(types[i], p0 + to_c * 3.2, 1)
		if ru != null:
			ru.command_stop()
			ru._scan_timer = 9999.0
	camera_rig.focus_on(origin + to_c * 1.6, true)
	camera_rig.set_zoom_instant(16.0)


func _process(delta: float) -> void:
	if not _bridge_lights.is_empty():
		var ft: float = Time.get_ticks_msec() * 0.0085
		for i in range(_bridge_lights.size()):
			var bl: OmniLight3D = _bridge_lights[i]
			if is_instance_valid(bl):
				bl.light_energy = 1.55 * (0.92 + 0.08 * sin(ft + float(i) * 2.1) + 0.04 * cos(ft * 2.3 + float(i)))
	if game_manager != null and game_manager.match_started and not game_manager.is_game_over and ai_team0 == null:
		_update_tips()
	if _screenshot_mode:
		_screenshot_timer += delta
		if _screenshot_timer >= 1.2 and delta < 0.25:
			_recent_deltas.append(delta)
			if _recent_deltas.size() > 20:
				_recent_deltas.pop_front()
		if _shot_end != "":
			if _screenshot_timer >= 1.5 and not game_manager.is_game_over:
				game_manager.match_time = 37.0 * 60.0 + 12.0
				game_manager.end_match(0 if _shot_end == "win" else 1)
			if _screenshot_timer >= 3.0:
				_screenshot_mode = false
				_capture_screenshot(game_manager.match_time)
			return
		var sim_t: float = game_manager.match_time if (game_manager != null and game_manager.match_started) else _screenshot_timer
		if sim_t >= _shot_at and _screenshot_timer >= 1.5:
			_screenshot_mode = false
			_capture_screenshot(sim_t)


func _capture_screenshot(sim_t: float) -> void:
	var sum_d: float = 0.0
	for d in _recent_deltas:
		sum_d += d
	var real_fps: float = float(_recent_deltas.size()) / maxf(0.0001, sum_d) if _recent_deltas.size() > 0 else Engine.get_frames_per_second()
	var img: Image = get_viewport().get_texture().get_image()
	var out_path: String = _shot_out
	if out_path == "":
		var fname: String = "rts_units_closeup.png" if _screenshot_units else ("rts_river_preview.png" if _screenshot_river else "rts_gameplay_preview.png")
		out_path = ProjectSettings.globalize_path("res://assets/blender/" + fname)
	var err: int = img.save_png(out_path)
	print("SCREENSHOT_SAVED:", out_path, " err=", err, " FPS=", Engine.get_frames_per_second(), " REAL_FPS=", snappedf(real_fps, 0.1), " T=", snappedf(sim_t, 0.1))
	if game_manager != null:
		print("STATE: units=", game_manager.units.size(), " buildings=", game_manager.buildings.size(), " res0=", game_manager.team_data[0], " res1=", game_manager.team_data[1])
	get_tree().quit(0)


func _update_tips() -> void:
	var t: float = game_manager.match_time
	if _tip_idx < TIPS.size() and t >= float(TIPS[_tip_idx][0]):
		game_manager.post_alert(String(TIPS[_tip_idx][1]), Color(0.78, 0.92, 1.0))
		_tip_idx += 1
	var info: Dictionary = wave_director.get_threat_info()
	if not _peace_warned and float(info["peace_left"]) <= 60.0 and float(info["peace_left"]) > 0.0:
		_peace_warned = true
		game_manager.post_alert("A trégua termina em 1 minuto! As tropas dos covis vão marchar: torres, lanceiros contra paladinos e arqueiros atrás da linha.", Color(1.0, 0.7, 0.35))
		if sfx_manager != null:
			sfx_manager.play_horn_alert()


## Primeiro prédio inimigo avistado (um covil). O WaveDirector já anuncia cada covil encontrado.
func _on_enemy_base_discovered(_b: RTSBuilding) -> void:
	if sfx_manager != null:
		sfx_manager.play_horn_alert()
	if hud != null:
		hud.on_enemy_discovered()


# ==============================================================================
# AMBIENTE, TERRENO E RIO
# ==============================================================================

## Direção de arte: tarde dourada de verão, medieval realista e acolhedora (ver WorldLook).
## Tudo aqui é custo fixo de pós-processo ou de luz; nada escala com o número de objetos.
func _setup_environment_and_lights() -> void:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky: Sky = Sky.new()
	var sky_mat: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.43, 0.74)
	sky_mat.sky_horizon_color = Color(0.80, 0.79, 0.74)
	sky_mat.ground_bottom_color = Color(0.20, 0.23, 0.16)
	sky_mat.ground_horizon_color = Color(0.56, 0.58, 0.49)
	sky_mat.sun_angle_max = 18.0
	sky_mat.sun_curve = 0.08
	sky.sky_material = sky_mat
	# O céu é fixo: um mapa de radiância pequeno basta para a luz ambiente
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.sky = sky

	# Céu frio levanta as sombras (nada de preto-azulado) e contrasta com o sol quente.
	# Substitui a antiga 2ª luz direcional de preenchimento: visual quase igual e ~0,9 ms a menos na RX 550.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.67
	env.ambient_light_sky_contribution = 1.0

	# AgX: cores naturais e altas luzes suaves (o ACES deixava a grama neon e estourava janelas/tochas)
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.18
	env.tonemap_agx_contrast = 1.22
	env.ssao_enabled = false
	env.ssr_enabled = false
	env.glow_enabled = true
	env.glow_normalized = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_intensity = 0.32
	env.glow_strength = 0.80
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.15
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.04
	env.adjustment_saturation = 1.14
	env.adjustment_color_correction = _make_grade_lut()
	# Perspectiva aérea: ao afastar o zoom, o fundo ganha uma bruma quente de fim de tarde
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 70.0
	env.fog_depth_end = 250.0
	env.fog_depth_curve = 1.5
	env.fog_light_color = Color(0.80, 0.80, 0.78)
	env.fog_sun_scatter = 0.12
	env.fog_sky_affect = 0.25

	var we: WorldEnvironment = WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)

	# Sol de lado e um pouco mais alto: modela bem os prédios e as sombras não escondem as unidades
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "SunLight"
	sun.light_color = Color(1.0, 0.88, 0.70)
	sun.light_energy = 2.0
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 115.0
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.4
	sun.shadow_blur = 1.2
	sun.rotation_degrees = Vector3(-44.0, 40.0, 0.0)
	add_child(sun)


## Qualidade gráfica ([F9]): precisa do sol, do ambiente e da vegetação já criados.
func _setup_graphics_settings() -> void:
	graphics = GraphicsSettings.new()
	graphics.name = "GraphicsSettings"
	add_child(graphics)
	var we: WorldEnvironment = get_node_or_null("WorldEnvironment") as WorldEnvironment
	graphics.setup(get_node_or_null("SunLight") as DirectionalLight3D, we.environment if we != null else null,
		world_root.find_child("WorldFoliage", true, false), game_manager)


## LUT 1D de gradação (aplicada por canal no passe de tonemap, custo ~zero):
## sombras levemente frias, altas luzes quentes e pretos suavizados, como fim de tarde.
static func _make_grade_lut() -> GradientTexture1D:
	var g: Gradient = Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	g.colors = PackedColorArray([
		Color(0.030, 0.032, 0.055),
		Color(0.236, 0.246, 0.272),
		Color(0.505, 0.500, 0.490),
		Color(0.770, 0.756, 0.722),
		Color(1.000, 0.985, 0.940),
	])
	var tex: GradientTexture1D = GradientTexture1D.new()
	tex.gradient = g
	tex.width = 256
	return tex


func _setup_terrain_and_river() -> void:
	world_root = Node3D.new()
	world_root.name = "WorldRoot"
	add_child(world_root)

	var ground_body: StaticBody3D = StaticBody3D.new()
	ground_body.name = "Ground"
	ground_body.collision_layer = 1
	ground_body.collision_mask = 0
	world_root.add_child(ground_body)

	var col: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = Vector3(TERRAIN_HALF * 2.0, 1.0, TERRAIN_HALF * 2.0)
	col.shape = box_shape
	col.position = Vector3(0.0, -0.5, 0.0)
	ground_body.add_child(col)

	var terrain_mesh: MeshInstance3D = MeshInstance3D.new()
	terrain_mesh.name = "TerrainMesh"
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(TERRAIN_HALF * 2.0, TERRAIN_HALF * 2.0)
	plane.subdivide_width = 200
	plane.subdivide_depth = 200
	terrain_mesh.mesh = plane
	terrain_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var terrain_shader: Shader = load("res://scripts/shaders/terrain.gdshader") as Shader
	if terrain_shader != null:
		var t_mat: ShaderMaterial = ShaderMaterial.new()
		t_mat.shader = terrain_shader
		t_mat.set_shader_parameter("terrain_half", TERRAIN_HALF)
		t_mat.set_shader_parameter("hills_start", GameManager.MAP_HALF - 2.0)
		var tex_params: Dictionary = {
			"baked_albedo": "res://assets/textures/terrain_baked_albedo.png",
			"detail_normal": "res://assets/textures/terrain_detail_normal.png",
			"splat_mask": "res://assets/textures/terrain_splat_mask.png",
			"cobble_albedo": "res://assets/textures/terrain_cobble_albedo.png",
			"cobble_normal": "res://assets/textures/terrain_cobble_normal.png",
			"micro_detail": "res://assets/textures/terrain_micro_detail.png",
		}
		for param_name in tex_params.keys():
			# Mesma instância que a grama 3D usa (WorldLook): sem VRAM duplicada
			var tex_res: Texture2D = WorldLook.load_mipmapped(String(tex_params[param_name]))
			if tex_res != null:
				t_mat.set_shader_parameter(param_name, tex_res)
		t_mat.set_shader_parameter("world_noise", WorldLook.noise_texture())
		t_mat.set_shader_parameter("splat_ready", 1.0)
		terrain_mesh.material_override = t_mat
	else:
		var fallback_mat: StandardMaterial3D = StandardMaterial3D.new()
		fallback_mat.albedo_color = Color(0.20, 0.38, 0.16)
		terrain_mesh.material_override = fallback_mat
	ground_body.add_child(terrain_mesh)

	var water_mesh: MeshInstance3D = MeshInstance3D.new()
	water_mesh.name = "RiverWater"
	var water_plane: PlaneMesh = PlaneMesh.new()
	water_plane.size = Vector2(18.0, TERRAIN_HALF * 2.0 * 1.4142 + 12.0)
	water_plane.subdivide_width = 16
	water_plane.subdivide_depth = 128
	water_mesh.mesh = water_plane
	water_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water_mesh.position = Vector3(0.0, -0.26, 0.0)
	water_mesh.rotation.y = PI * 0.25

	var water_shader: Shader = load("res://scripts/shaders/water.gdshader") as Shader
	if water_shader != null:
		var w_mat: ShaderMaterial = ShaderMaterial.new()
		w_mat.shader = water_shader
		var bridge_xz: PackedVector2Array = PackedVector2Array()
		for bp in RTSUnit.BRIDGES:
			if bridge_xz.size() < 4:  # o shader tem espaço para 4 pontes
				bridge_xz.append(Vector2(bp.x, bp.z))
		while bridge_xz.size() < 4:
			bridge_xz.append(Vector2(9999.0, 9999.0))
		w_mat.set_shader_parameter("bridge_pos", bridge_xz)
		water_mesh.material_override = w_mat
	else:
		var w_fallback: StandardMaterial3D = StandardMaterial3D.new()
		w_fallback.albedo_color = Color(0.10, 0.42, 0.65, 0.85)
		w_fallback.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		water_mesh.material_override = w_fallback
	world_root.add_child(water_mesh)

	_build_architectural_bridges()


func _build_architectural_bridges() -> void:
	var bridge_scene: PackedScene = load("res://assets/models/prop_stone_bridge.glb") as PackedScene
	var dark_stone_mat: StandardMaterial3D = StandardMaterial3D.new()
	dark_stone_mat.albedo_color = Color(0.28, 0.28, 0.30)
	dark_stone_mat.roughness = 0.88

	_bridge_lights.clear()
	for bp in RTSUnit.BRIDGES:
		var bridge: Node3D = Node3D.new()
		bridge.position = bp
		bridge.rotation.y = -PI * 0.25
		world_root.add_child(bridge)

		if bridge_scene != null:
			var model_inst: Node3D = bridge_scene.instantiate() as Node3D
			if model_inst != null:
				bridge.add_child(model_inst)
		else:
			var deck: MeshInstance3D = MeshInstance3D.new()
			var dbox: BoxMesh = BoxMesh.new()
			dbox.size = Vector3(8.6, 0.34, 15.2)
			deck.mesh = dbox
			deck.position = Vector3(0.0, 0.04, 0.0)
			deck.material_override = dark_stone_mat
			bridge.add_child(deck)

		if vfx_manager != null:
			for sx in [-4.18, 4.18]:
				for ez in [-6.75, 6.75]:
					var fl: Node3D = vfx_manager.create_torch_flame(0.92, 2.5)
					fl.position = Vector3(sx, 1.54, ez)
					bridge.add_child(fl)

		var bridge_light: OmniLight3D = OmniLight3D.new()
		bridge_light.light_color = Color(1.0, 0.65, 0.25)
		bridge_light.light_energy = 1.55
		bridge_light.omni_range = 15.0
		bridge_light.shadow_enabled = false
		bridge_light.distance_fade_enabled = true
		bridge_light.distance_fade_begin = 52.0
		bridge_light.distance_fade_length = 12.0
		bridge_light.position = Vector3(0.0, 2.2, 0.0)
		bridge.add_child(bridge_light)
		_bridge_lights.append(bridge_light)


func _setup_systems() -> void:
	sfx_manager = SFXManager.new()
	sfx_manager.name = "SFXManager"
	add_child(sfx_manager)

	camera_rig = RTSCamera.new()
	camera_rig.name = "CameraRig"
	camera_rig.map_limit = GameManager.MAP_HALF - 6.0
	add_child(camera_rig)
	if vfx_manager != null:
		vfx_manager.attach_ambient_motes(camera_rig)

	game_manager = GameManager.new()
	game_manager.name = "GameManager"
	game_manager.world_root = world_root
	game_manager.camera_rig = camera_rig
	game_manager.sfx = sfx_manager
	game_manager.vfx = vfx_manager
	add_child(game_manager)

	var nav: NavGrid = NavGrid.new()
	nav.setup(GameManager.MAP_HALF, GameManager.UNIT_BOUND)
	game_manager.nav = nav

	fog = FogOfWar.new()
	fog.name = "FogOfWar"
	add_child(fog)
	fog.setup(game_manager, GameManager.MAP_HALF)
	game_manager.fog = fog
	fog.enemy_base_discovered.connect(_on_enemy_base_discovered)
	_create_fog_overlay()

	wave_director = WaveDirector.new()
	wave_director.name = "WaveDirector"
	wave_director.game_manager = game_manager
	add_child(wave_director)
	game_manager.ai_controller = wave_director
	game_manager.ai_controllers[1] = wave_director

	hud = RTSHUD.new()
	hud.name = "HUD"
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hud)
	hud.setup(game_manager, camera_rig, wave_director)
	hud.start_requested.connect(start_match)
	game_manager.hud = hud


func _create_fog_overlay() -> void:
	var shader: Shader = load("res://scripts/shaders/fog_overlay.gdshader") as Shader
	if shader == null:
		return
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	mat.render_priority = 120
	# O mesmo passe também desenha as sombras de nuvens e a vinheta (ver fog_overlay.gdshader)
	mat.set_shader_parameter("noise_tex", WorldLook.noise_texture())
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "FogOverlay"
	mi.mesh = quad
	mi.material_override = mat
	mi.extra_cull_margin = 16384.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)
	fog.register_material(mat)


func _spawn_starting_base(team: int, slot: Dictionary) -> void:
	var pos: Vector3 = slot["pos"]
	var to_c: Vector3 = Vector3(-pos.x, 0.0, -pos.z).normalized()
	var side: Vector3 = Vector3(-to_c.z, 0.0, to_c.x)
	var tc: RTSBuilding = game_manager.place_building_at("town_center", pos, team, true)
	if tc != null:
		tc.rally_point = pos + to_c * 7.5
	var workers: Array[RTSUnit] = []
	for off in [to_c * 5.8 + side * 2.2, to_c * 5.8 - side * 2.2, to_c * 7.2]:
		var w: RTSUnit = game_manager.spawn_unit("worker", pos + off, team)
		if w != null:
			workers.append(w)
	game_manager.spawn_unit("scout", pos + to_c * 8.5 + side * 3.5, team)
	if team == 0 and not ai_vs_ai and workers.size() >= 3:
		workers[0].command_auto_gather_near("food")
		workers[1].command_auto_gather_near("food")
		workers[2].command_auto_gather_near("wood")
