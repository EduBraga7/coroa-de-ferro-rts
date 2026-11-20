extends SceneTree

## Benchmark de renderização (precisa de janela e GPU, NÃO rode com --headless).
## Carrega a partida, enquadra a câmera e mede tempo de quadro, GPU e draw calls.
## Com --bench-toggles, também mede o custo de cada camada (sombras, glow, névoa, vegetação...).
##
## Uso:
##   godot --path . --script res://tools/bench_render.gd -- --seed=7 --autostart [opções]
## Opções:
##   --bench-frames=N        quadros medidos por segmento (padrão 150)
##   --bench-zoom=Z          zoom da câmera (padrão 34, o mesmo do início da partida)
##   --bench-focus=X,Z       centro da câmera (padrão: Salão Real do jogador)
##   --bench-toggles         mede também cada camada desligada, uma por vez
##   --bench-scale=S         escala 3D (0.5..1.0) aplicada antes de medir
##   --bench-warmup=S        segundos de aquecimento antes de medir (padrão 3)
##   --bench-timeline=S      imprime a média de cada janela de 2 s durante os primeiros S segundos
##   --bench-ab              custo de cada camada visual por A/B intercalado (liga/desliga 6x, mediana):
##                           robusto contra outro programa disputando a GPU
##   --shots=ALVO;ALVO;...   tira capturas (uma janela só) e sai. ALVO = "base,ZOOM" ou "X,Z,ZOOM"
##                           ("battle,ZOOM" enquadra a batalha de --bench-battle)
##   --shots-out=PASTA       pasta das capturas (padrão user://shots)
##   --bench-battle=N        batalha grande: N unidades mistas (metade por time) lutando diante do
##                           Salão Real; a câmera vai para a luta e o --bench-ab também mede o custo
##                           das unidades e das sombras delas
##   --bench-battle-freeze   a batalha fica parada em poses fixas (capturas comparáveis entre execuções)

var _main: Node = null
var _shots: PackedStringArray = PackedStringArray()
var _shots_out: String = ""
var _shots_nohud: bool = false
var _shots_explored: bool = false
var _shots_hide: PackedStringArray = PackedStringArray()
var _vp_rid: RID
var _frames: int = 150
var _zoom: float = 34.0
var _focus: Variant = null
var _toggles: bool = false
var _ab: bool = false
var _scale: float = 1.0
var _warmup: float = 3.0
var _timeline: float = 0.0
var _battle: int = 0
var _battle_freeze: bool = false
var _battle_center: Vector3 = Vector3.ZERO
var _phys_t0: int = 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bench-frames="):
			_frames = int(arg.get_slice("=", 1))
		elif arg.begins_with("--bench-zoom="):
			_zoom = float(arg.get_slice("=", 1))
		elif arg.begins_with("--bench-focus="):
			var parts: PackedStringArray = arg.get_slice("=", 1).split(",")
			if parts.size() == 2:
				_focus = Vector3(float(parts[0]), 0.0, float(parts[1]))
		elif arg == "--bench-toggles":
			_toggles = true
		elif arg == "--bench-ab":
			_ab = true
		elif arg.begins_with("--bench-scale="):
			_scale = clampf(float(arg.get_slice("=", 1)), 0.25, 2.0)
		elif arg.begins_with("--bench-warmup="):
			_warmup = float(arg.get_slice("=", 1))
		elif arg.begins_with("--bench-timeline="):
			_timeline = float(arg.get_slice("=", 1))
		elif arg.begins_with("--shots="):
			_shots = arg.get_slice("=", 1).split(";", false)
		elif arg.begins_with("--shots-out="):
			_shots_out = arg.get_slice("=", 1)
		elif arg == "--shots-nohud":
			_shots_nohud = true
		elif arg == "--shots-explored":
			_shots_explored = true
		elif arg.begins_with("--shots-hide="):
			_shots_hide = arg.get_slice("=", 1).split(",", false)
		elif arg.begins_with("--bench-battle="):
			_battle = maxi(0, int(arg.get_slice("=", 1)))
		elif arg == "--bench-battle-freeze":
			_battle_freeze = true
	Engine.max_fps = 0
	physics_frame.connect(func() -> void:
		if _phys_t0 == 0:
			_phys_t0 = Time.get_ticks_usec())
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _run() -> void:
	_vp_rid = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp_rid, true)
	# Sem --bench-scale, vale a escala do preset de qualidade (GraphicsSettings / --graphics=)
	if absf(_scale - 1.0) > 0.001:
		root.scaling_3d_scale = _scale
	else:
		_scale = root.scaling_3d_scale
	var cam: Node = _main.get_node_or_null("CameraRig")
	if cam != null:
		cam.set("edge_pan_enabled", false)
		if _focus != null:
			cam.call("focus_on", _focus, true)
		cam.call("set_zoom_instant", _zoom)
	if _battle > 0:
		_spawn_battle()
		if cam != null and _focus == null:
			cam.call("focus_on", _battle_center, true)
	print("BENCH window=%s scale=%.2f zoom=%.0f renderer=%s gpu=%s" % [
		str(root.size), _scale, _zoom,
		str(ProjectSettings.get_setting("rendering/renderer/rendering_method")),
		RenderingServer.get_video_adapter_name()])
	if not _shots.is_empty():
		await _take_shots(cam)
		quit(0)
		return
	if _timeline > 0.0:
		await _run_timeline()
	var t0: int = Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) < _warmup * 1000.0:
		await process_frame
	await _measure("baseline")
	if _ab:
		if _battle > 0:
			await _ab_run("units", func(on: bool) -> void: _set_group_visible("units", on))
			await _ab_run("unit_shadows", func(on: bool) -> void: _set_unit_shadows(on))
		await _ab_run("fog+clouds+vignette", func(on: bool) -> void: _set_prop(_main.get_node_or_null("FogOverlay"), "visible", on))
		await _ab_run("foliage", func(on: bool) -> void: _set_prop(_main.find_child("WorldFoliage", true, false), "visible", on))
		await _ab_run("tree_wind_shader", func(on: bool) -> void: _set_tree_wind(on))
		await _ab_run("grade_lut", func(on: bool) -> void: _set_env("adjustment_color_correction", _saved_lut if on else null))
		await _ab_run("agx_vs_aces", func(on: bool) -> void: _set_env("tonemap_mode", Environment.TONE_MAPPER_AGX if on else Environment.TONE_MAPPER_ACES))
		await _ab_run("glow", func(on: bool) -> void: _set_env("glow_enabled", on))
		await _ab_run("sun_shadows", func(on: bool) -> void: _set_prop(_main.get_node_or_null("SunLight"), "shadow_enabled", on))
		await _ab_run("soft_vs_hard_shadow", func(on: bool) -> void: RenderingServer.directional_soft_shadow_filter_set_quality(
			RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW if on else RenderingServer.SHADOW_QUALITY_HARD))
		await _ab_run("render_scale_77", func(on: bool) -> void: root.scaling_3d_scale = _scale if on else _scale * 0.77)
	if _toggles:
		await _toggle_run("no_shadows", func(on: bool) -> void: _set_prop(_main.get_node_or_null("SunLight"), "shadow_enabled", on))
		await _toggle_run("no_glow", func(on: bool) -> void: _set_env("glow_enabled", on))
		await _toggle_run("no_fog_overlay", func(on: bool) -> void: _set_prop(_main.get_node_or_null("FogOverlay"), "visible", on))
		await _toggle_run("no_foliage", func(on: bool) -> void: _set_prop(_main.find_child("WorldFoliage", true, false), "visible", on))
		await _toggle_run("no_terrain", func(on: bool) -> void: _set_prop(_main.find_child("TerrainMesh", true, false), "visible", on))
		await _toggle_run("no_water", func(on: bool) -> void: _set_prop(_main.find_child("RiverWater", true, false), "visible", on))
		await _toggle_run("no_trees", func(on: bool) -> void: _set_group_visible("tree", on))
		await _toggle_run("no_resources", func(on: bool) -> void: _set_group_visible("resources", on))
		await _toggle_run("no_buildings", func(on: bool) -> void: _set_group_visible("buildings", on))
		await _toggle_run("no_units", func(on: bool) -> void: _set_group_visible("units", on))
		await _toggle_run("no_props", func(on: bool) -> void: _set_prop(_main.find_child("SceneryLandmarks", true, false), "visible", on))
		await _toggle_run("no_omni", func(on: bool) -> void: _set_class_visible("OmniLight3D", on))
		await _toggle_run("no_particles", func(on: bool) -> void: _set_class_visible("GPUParticles3D", on))
		await _toggle_run("no_hud", func(on: bool) -> void: _set_prop(_main.get_node_or_null("HUD"), "visible", on))
		await _toggle_run("half_res", func(on: bool) -> void: root.scaling_3d_scale = _scale if on else _scale * 0.5)
		await _measure("baseline_end")
	quit(0)


## Várias capturas numa só execução (menos janelas abrindo). Cada alvo: "base,ZOOM" ou "X,Z,ZOOM".
func _take_shots(cam: Node) -> void:
	var out_dir: String = _shots_out if _shots_out != "" else ProjectSettings.globalize_path("user://shots")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var base: Vector3 = Vector3.ZERO
	if cam != null:
		base = cam.get("target_pos")
	if _shots_nohud:
		_set_prop(_main.get_node_or_null("HUD"), "visible", false)
	for node_name in _shots_hide:
		_set_prop(_main.find_child(node_name, true, false), "visible", false)
	if _shots_explored:
		# Mapa todo "explorado": mostra o véu de lembrança fora do alcance de visão
		var fog: Node = _main.get_node_or_null("FogOfWar")
		if fog != null:
			fog.call("reveal_all_explored")
			fog.call("update_now")
	for i in range(60):
		await process_frame
	var idx: int = 0
	for spec in _shots:
		var parts: PackedStringArray = spec.split(",")
		var focus: Vector3 = base
		var zoom: float = _zoom
		if parts.size() == 2 and parts[0] == "base":
			zoom = float(parts[1])
		elif parts.size() == 2 and parts[0] == "battle":
			focus = _battle_center
			zoom = float(parts[1])
		elif parts.size() >= 3:
			focus = Vector3(float(parts[0]), 0.0, float(parts[1]))
			zoom = float(parts[2])
		if cam != null:
			cam.set("max_zoom", maxf(float(cam.get("max_zoom")), zoom))
			cam.call("focus_on", focus, true)
			cam.call("set_zoom_instant", zoom)
		for f in range(45):
			await process_frame
		var img: Image = root.get_texture().get_image()
		var path: String = out_dir.path_join("shot_%d_%s.png" % [idx, spec.replace(",", "_").replace("-", "m")])
		img.save_png(path)
		print("SHOT ", path, " fps=", Engine.get_frames_per_second())
		idx += 1


## Linha do tempo desde o carregamento: mostra aquecimento (compilação de pipelines) e picos.
func _run_timeline() -> void:
	var t_start: int = Time.get_ticks_msec()
	var win_start: int = t_start
	var last: int = Time.get_ticks_usec()
	var n: int = 0
	var sum_ms: float = 0.0
	var max_ms: float = 0.0
	var gpu_sum: float = 0.0
	while float(Time.get_ticks_msec() - t_start) < _timeline * 1000.0:
		await process_frame
		var now: int = Time.get_ticks_usec()
		var ms: float = float(now - last) / 1000.0
		last = now
		n += 1
		sum_ms += ms
		max_ms = maxf(max_ms, ms)
		gpu_sum += RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid)
		if Time.get_ticks_msec() - win_start >= 2000:
			print("TIMELINE t=%5.1fs frames=%3d avg=%6.2fms max=%7.2fms gpu=%6.2fms proc=%5.1fms pipelines_compiled=%d" % [
				float(Time.get_ticks_msec() - t_start) / 1000.0, n, sum_ms / float(n), max_ms, gpu_sum / float(n),
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW)) + int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION))])
			win_start = Time.get_ticks_msec()
			n = 0
			sum_ms = 0.0
			max_ms = 0.0
			gpu_sum = 0.0


var _saved_lut: Texture2D = null
var _tree_overrides: Array = []


## A/B intercalado: alterna desligado/ligado 6 vezes (40 quadros cada) e compara as medianas.
## Se outro programa disputa a GPU, a carga dele cai igualmente nos dois lados.
## Atenção: "draws" do Godot cresce ~1 por instância, não por superfície (uma unidade com 12
## superfícies conta como 1); o custo real das draw calls aparece em cpu_render.
func _ab_run(label: String, apply: Callable) -> void:
	if _saved_lut == null:
		var we: WorldEnvironment = _main.get_node_or_null("WorldEnvironment") as WorldEnvironment
		if we != null and we.environment != null:
			_saved_lut = we.environment.adjustment_color_correction
	var on_ms: PackedFloat64Array = PackedFloat64Array()
	var off_ms: PackedFloat64Array = PackedFloat64Array()
	var on_gpu: PackedFloat64Array = PackedFloat64Array()
	var off_gpu: PackedFloat64Array = PackedFloat64Array()
	var on_dr: PackedFloat64Array = PackedFloat64Array()
	var off_dr: PackedFloat64Array = PackedFloat64Array()
	for cycle in range(6):
		for state in [false, true]:
			apply.call(state)
			for i in range(8):
				await process_frame
			var last: int = Time.get_ticks_usec()
			for i in range(40):
				await process_frame
				var now: int = Time.get_ticks_usec()
				var ms: float = float(now - last) / 1000.0
				last = now
				var g: float = RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid)
				var dr: float = float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
				if state:
					on_ms.append(ms)
					on_gpu.append(g)
					on_dr.append(dr)
				else:
					off_ms.append(ms)
					off_gpu.append(g)
					off_dr.append(dr)
	apply.call(true)
	var m_on: float = _median(on_ms)
	var m_off: float = _median(off_ms)
	print("AB %-20s on=%6.2fms off=%6.2fms delta=%+6.2fms | gpu on=%6.2f off=%6.2f delta=%+6.2fms | draws on=%d off=%d" % [
		label, m_on, m_off, m_on - m_off, _median(on_gpu), _median(off_gpu), _median(on_gpu) - _median(off_gpu),
		int(_median(on_dr)), int(_median(off_dr))])


static func _median(a: PackedFloat64Array) -> float:
	if a.is_empty():
		return 0.0
	var b: PackedFloat64Array = a.duplicate()
	b.sort()
	return b[b.size() / 2]


## Troca as árvores entre o material com vento (WorldLook) e o StandardMaterial3D original.
func _set_tree_wind(on: bool) -> void:
	var gm: Node = _main.get_node_or_null("GameManager")
	if gm == null:
		return
	if _tree_overrides.is_empty():
		for r in gm.get("resources"):
			if not is_instance_valid(r) or String(r.get("kind")) != "tree":
				continue
			for mi in (r as Node).find_children("*", "MeshInstance3D", true, false):
				var m: MeshInstance3D = mi as MeshInstance3D
				if m.mesh == null:
					continue
				for s in range(m.mesh.get_surface_count()):
					if m.get_surface_override_material(s) != null:
						_tree_overrides.append([m, s, m.get_surface_override_material(s)])
	for e in _tree_overrides:
		var m: MeshInstance3D = e[0]
		if is_instance_valid(m):
			m.set_surface_override_material(int(e[1]), e[2] if on else null)


func _toggle_run(label: String, apply: Callable) -> void:
	apply.call(false)
	for i in range(20):
		await process_frame
	await _measure(label)
	apply.call(true)
	for i in range(10):
		await process_frame


func _measure(label: String) -> void:
	var frame_ms: PackedFloat64Array = PackedFloat64Array()
	var gpu_sum: float = 0.0
	var cpu_sum: float = 0.0
	var draws: int = 0
	var prims: int = 0
	var objs: int = 0
	var phys_ms: PackedFloat64Array = PackedFloat64Array()
	var last: int = Time.get_ticks_usec()
	_phys_t0 = 0
	for i in range(_frames):
		await process_frame
		var now: int = Time.get_ticks_usec()
		frame_ms.append(float(now - last) / 1000.0)
		last = now
		# Física do quadro (IA das unidades + passos do motor): do 1º physics_frame até este process_frame
		phys_ms.append(float(now - _phys_t0) / 1000.0 if _phys_t0 != 0 else 0.0)
		_phys_t0 = 0
		gpu_sum += RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid)
		cpu_sum += RenderingServer.viewport_get_measured_render_time_cpu(_vp_rid) + RenderingServer.get_frame_setup_time_cpu()
		draws += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		objs += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	var n: float = float(_frames)
	var avg: float = 0.0
	for v in frame_ms:
		avg += v / n
	frame_ms.sort()
	var p95: float = frame_ms[int(frame_ms.size() * 0.95)]
	print("BENCH %-15s frame=%6.2fms (%5.1f fps) p95=%6.2fms gpu=%6.2fms cpu_render=%5.2fms draws=%5d prims=%7d objs=%4d vram=%dMB tex=%dMB" % [
		label, avg, 1000.0 / maxf(0.001, avg), p95, gpu_sum / n, cpu_sum / n,
		int(draws / n), int(prims / n), int(objs / n),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576])
	if _battle > 0:
		var phys_avg: float = 0.0
		for v in phys_ms:
			phys_avg += v / n
		phys_ms.sort()
		print("BENCH %-15s p99=%6.2fms max=%6.2fms phys_avg=%5.2fms phys_p99=%5.2fms phys_max=%5.2fms units_visible=%d" % [
			label, frame_ms[int(frame_ms.size() * 0.99)], frame_ms[frame_ms.size() - 1],
			phys_avg, phys_ms[int(phys_ms.size() * 0.99)], phys_ms[phys_ms.size() - 1], _visible_units()])


func _set_prop(node: Object, prop: String, value: Variant) -> void:
	if node != null:
		node.set(prop, value)


func _set_env(prop: String, value: Variant) -> void:
	var we: WorldEnvironment = _main.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		we.environment.set(prop, value)


func _set_group_visible(what: String, on: bool) -> void:
	var gm: Node = _main.get_node_or_null("GameManager")
	if gm == null:
		return
	var lst: Array = []
	match what:
		"tree", "resources":
			lst = gm.get("resources")
		"buildings":
			lst = gm.get("buildings")
		"units":
			lst = gm.get("units")
	for e in lst:
		if not is_instance_valid(e):
			continue
		if what == "tree" and String(e.get("kind")) != "tree":
			continue
		(e as Node3D).visible = on


func _set_class_visible(cls: String, on: bool) -> void:
	for n in _main.find_children("*", cls, true, false):
		(n as Node3D).visible = on


## --bench-battle=N: dois blocos mistos frente a frente diante do Salão Real, como numa onda tardia.
## A vida é multiplicada para ninguém morrer durante a medição (a contagem fica estável) e começa
## em 85% para as barras de vida aparecerem, como no meio de uma luta.
func _spawn_battle() -> void:
	var gm: Node = _main.get_node_or_null("GameManager")
	if gm == null:
		return
	var slot: Dictionary = _main.get("player_slot")
	var base: Vector3 = slot.get("pos", Vector3.ZERO)
	var to_c: Vector3 = Vector3(-base.x, 0.0, -base.z).normalized()
	var side: Vector3 = Vector3(-to_c.z, 0.0, to_c.x)
	_battle_center = base + to_c * 22.0
	seed(20261120)
	var mixes: Array = [
		["soldier", "spearman", "archer", "knight", "spearman", "soldier", "archer", "scout"],
		["soldier", "spearman", "archer", "knight", "soldier", "captain", "archer", "ram"],
	]
	var cols: int = 8
	var surf_by_type: Dictionary = {}
	var total_surf: int = 0
	var count: int = 0
	for t in range(2):
		var mix: Array = mixes[t]
		var n: int = _battle / 2 + (_battle % 2 if t == 1 else 0)
		var back: Vector3 = to_c * (-1.0 if t == 0 else 1.0)
		for i in range(n):
			var p: Vector3 = _battle_center + back * (3.0 + float(i / cols) * 2.2) \
				+ side * (float(i % cols) - float(cols - 1) * 0.5) * 2.2
			var u: Node3D = gm.call("spawn_unit", String(mix[i % mix.size()]), p, t) as Node3D
			if u == null:
				continue
			count += 1
			u.set("max_hp", float(u.get("max_hp")) * 40.0)
			u.set("hp", float(u.get("max_hp")) * 0.85)
			u.call("_update_hp_bar")
			u.rotation.y = atan2(back.x, back.z)
			# Superfícies do modelo (sem anel de time, barra de vida e cargas escondidas)
			var surf: int = 0
			var vr: Node = u.get_node_or_null("VisualRoot")
			for mi in (vr.find_children("*", "MeshInstance3D", true, false) if vr != null else []):
				var m: MeshInstance3D = mi as MeshInstance3D
				if m.mesh != null and m.visible:
					surf += m.mesh.get_surface_count()
			surf_by_type[String(u.get("unit_type"))] = surf
			total_surf += surf
			if _battle_freeze:
				_freeze_unit(u, i)
			else:
				u.call("command_attack_move", _battle_center - back * 8.0)
	print("BATTLE units=%d model_surfaces=%d per_type=%s" % [count, total_surf, str(surf_by_type)])


## Pose fixa (ataque, marcha ou parado, conforme o índice) e IA desligada.
func _freeze_unit(u: Node3D, i: int) -> void:
	u.call("command_stop")
	u.set("_scan_timer", 1.0e9)
	u.set("_attack_anim_timer", 1.0e9)
	u.set_physics_process(false)
	var ap: AnimationPlayer = u.get("_anim_player") as AnimationPlayer
	if ap == null:
		return
	var clip: String = ["Attack", "Walk", "Idle"][i % 3]
	if ap.has_animation(clip):
		ap.play(clip, 0.0)
		ap.seek(0.2 + 0.1 * float(i % 4), true)
		ap.speed_scale = 0.0


var _unit_shadow_saved: Array = []


## Liga/desliga a sombra de todas as peças das unidades (guarda o ajuste original de cada peça).
func _set_unit_shadows(on: bool) -> void:
	var gm: Node = _main.get_node_or_null("GameManager")
	if gm == null:
		return
	if _unit_shadow_saved.is_empty():
		for u in gm.get("units"):
			if not is_instance_valid(u):
				continue
			var vr: Node = (u as Node).get_node_or_null("VisualRoot")
			if vr == null:
				continue
			for mi in vr.find_children("*", "MeshInstance3D", true, false):
				_unit_shadow_saved.append([mi, (mi as MeshInstance3D).cast_shadow])
	for e in _unit_shadow_saved:
		var m: MeshInstance3D = e[0]
		if is_instance_valid(m):
			m.cast_shadow = e[1] if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _visible_units() -> int:
	var gm: Node = _main.get_node_or_null("GameManager")
	if gm == null:
		return 0
	var c: int = 0
	for u in gm.get("units"):
		if is_instance_valid(u) and (u as Node3D).is_visible_in_tree():
			c += 1
	return c
