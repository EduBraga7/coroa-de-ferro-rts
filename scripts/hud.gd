extends CanvasLayer
class_name RTSHUD

## Interface Completa de RTS em Português: Barra Superior, Minimapa Tático,
## Painel de Seleção, Command Card 3x3, Caixa de Seleção 2D, Alertas e Vitória/Derrota.

var game_manager: GameManager = null
var camera_rig: RTSCamera = null
var ai_controller: AIController = null

var _root: Control
var _gold_lbl: Label
var _wood_lbl: Label
var _pop_lbl: Label
var _age_lbl: Label
var _time_lbl: Label
var _fps_lbl: Label
var _idle_btn: Button
var _edge_btn: Button
var _alert_panel: PanelContainer
var _alert_lbl: Label
var _alert_timer: float = 0.0

var _selection_box_overlay: Control
var _minimap_canvas: Control
var _sel_title_lbl: Label
var _sel_sub_lbl: Label
var _sel_hp_bar: ProgressBar
var _sel_hp_lbl: Label
var _sel_queue_box: VBoxContainer
var _sel_queue_lbl: Label
var _sel_queue_bar: ProgressBar
var _sel_filter_row: HFlowContainer

var _cmd_grid: GridContainer
var _cmd_actions: Array[Dictionary] = []

var _help_modal: PanelContainer
var _end_modal: PanelContainer
var _end_title_lbl: Label
var _end_stats_lbl: Label

var _minimap_dragging: bool = false
var _was_drawing_box: bool = false
var _refresh_accum: float = 0.0


class SelectionOverlay extends Control:
	var gm: GameManager = null
	func _draw() -> void:
		if gm == null or not gm.is_drawing_selection_box():
			return
		var rect: Rect2 = gm.get_selection_box_rect()
		draw_rect(rect, Color(0.22, 0.85, 0.45, 0.16), true)
		draw_rect(rect, Color(0.92, 0.82, 0.35, 0.92), false, 2.0)


class MinimapDrawer extends Control:
	var gm: GameManager = null
	var cam_rig: RTSCamera = null
	const MAP_HALF: float = 90.0

	func _world_to_mini(pos: Vector3) -> Vector2:
		var u: float = clampf((pos.x + MAP_HALF) / (MAP_HALF * 2.0), 0.0, 1.0)
		var v: float = clampf((pos.z + MAP_HALF) / (MAP_HALF * 2.0), 0.0, 1.0)
		return Vector2(u * size.x, v * size.y)

	func mini_to_world(local_pt: Vector2) -> Vector3:
		var u: float = clampf(local_pt.x / maxf(1.0, size.x), 0.0, 1.0)
		var v: float = clampf(local_pt.y / maxf(1.0, size.y), 0.0, 1.0)
		return Vector3(u * MAP_HALF * 2.0 - MAP_HALF, 0.0, v * MAP_HALF * 2.0 - MAP_HALF)

	func _draw() -> void:
		# Grama base do vale
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.14, 0.26, 0.12), true)

		# Manchas de solo florestal musgoso
		var forest_zones: Array[Vector3] = [
			Vector3(-72.0, 42.0, 12.0), Vector3(-68.0, 72.0, 13.0), Vector3(-40.0, 72.0, 10.0),
			Vector3(72.0, -42.0, 12.0), Vector3(68.0, -72.0, 13.0), Vector3(40.0, -72.0, 10.0),
			Vector3(-25.0, 38.0, 9.0), Vector3(25.0, -38.0, 9.0),
		]
		for fz in forest_zones:
			var fp: Vector2 = _world_to_mini(Vector3(fz.x, 0.0, fz.y))
			draw_circle(fp, fz.z * (size.x / 180.0), Color(0.10, 0.20, 0.08))

		# Estradas Imperiais (principal + rotas secundárias até pontes)
		var road_col: Color = Color(0.36, 0.29, 0.20)
		var p_sw: Vector2 = _world_to_mini(Vector3(-55.0, 0.0, 55.0))
		var p_ne: Vector2 = _world_to_mini(Vector3(55.0, 0.0, -55.0))
		var p_nw_b: Vector2 = _world_to_mini(Vector3(-34.0, 0.0, -34.0))
		var p_se_b: Vector2 = _world_to_mini(Vector3(34.0, 0.0, 34.0))
		var p_m1: Vector2 = _world_to_mini(Vector3(-48.0, 0.0, 10.0))
		var p_m2: Vector2 = _world_to_mini(Vector3(-10.0, 0.0, 46.0))
		var p_m3: Vector2 = _world_to_mini(Vector3(10.0, 0.0, -46.0))
		var p_m4: Vector2 = _world_to_mini(Vector3(48.0, 0.0, -10.0))
		draw_line(p_sw, p_ne, road_col, 4.2)
		draw_line(p_sw, p_m1, road_col, 2.8)
		draw_line(p_m1, p_nw_b, road_col, 2.8)
		draw_line(p_nw_b, p_m3, road_col, 2.8)
		draw_line(p_m3, p_ne, road_col, 2.8)
		draw_line(p_sw, p_m2, road_col, 2.8)
		draw_line(p_m2, p_se_b, road_col, 2.8)
		draw_line(p_se_b, p_m4, road_col, 2.8)
		draw_line(p_m4, p_ne, road_col, 2.8)

		# Calçamento Real das bases e marcos das ruínas
		draw_circle(p_sw, 13.0, Color(0.34, 0.35, 0.37))
		draw_circle(p_ne, 13.0, Color(0.34, 0.35, 0.37))
		for rp in [Vector3(-15.0, 0.0, -4.0), Vector3(15.0, 0.0, 4.0), Vector3(-24.0, 0.0, 22.0), Vector3(24.0, 0.0, -22.0)]:
			var mr: Vector2 = _world_to_mini(rp)
			draw_rect(Rect2(mr - Vector2(2.5, 2.5), Vector2(5.0, 5.0)), Color(0.75, 0.72, 0.64), true)

		# Margens arenosas e rio diagonal
		draw_line(Vector2(0.0, 0.0), size, Color(0.42, 0.37, 0.26), 14.5)
		draw_line(Vector2(0.0, 0.0), size, Color(0.13, 0.43, 0.70), 9.5)
		# Pontes
		for bp in RTSUnit.BRIDGES:
			var p: Vector2 = _world_to_mini(bp)
			draw_rect(Rect2(p - Vector2(7.0, 7.0), Vector2(14.0, 14.0)), Color(0.56, 0.51, 0.44), true)

		if gm == null:
			return

		# Recursos
		for r in gm.resources:
			if not is_instance_valid(r) or r.is_queued_for_deletion():
				continue
			var mp: Vector2 = _world_to_mini(r.global_position)
			if r.resource_type == "gold":
				draw_circle(mp, 3.3, Color(0.98, 0.82, 0.18))
			else:
				draw_circle(mp, 2.0, Color(0.14, 0.54, 0.18))

		# Prédios
		for b in gm.buildings:
			if not is_instance_valid(b) or b.is_queued_for_deletion() or b.hp <= 0.0:
				continue
			var mp: Vector2 = _world_to_mini(b.global_position)
			var col: Color = Color(0.24, 0.65, 1.0) if b.team == 0 else Color(0.95, 0.25, 0.22)
			var sz: float = 8.0 if b.building_type == "town_center" else 5.5
			draw_rect(Rect2(mp - Vector2(sz * 0.5, sz * 0.5), Vector2(sz, sz)), col, true)

		# Unidades
		for u in gm.units:
			if not is_instance_valid(u) or u.is_queued_for_deletion() or u.hp <= 0.0:
				continue
			var mp: Vector2 = _world_to_mini(u.global_position)
			var col: Color = Color(0.50, 0.88, 1.0) if u.team == 0 else Color(1.0, 0.45, 0.40)
			draw_circle(mp, 2.3, col)

		# Trapézio real de visão 3D da câmera
		if cam_rig != null:
			var poly_world: PackedVector2Array = cam_rig.get_view_polygon_world()
			if poly_world.size() >= 4:
				var pts: PackedVector2Array = PackedVector2Array()
				for wp in poly_world:
					pts.append(_world_to_mini(Vector3(wp.x, 0.0, wp.y)))
				pts.append(pts[0])
				draw_polyline(pts, Color(1.0, 1.0, 1.0, 0.90), 1.6, true)
			else:
				var vr: Rect2 = cam_rig.get_view_rect_world()
				var p0: Vector2 = _world_to_mini(Vector3(vr.position.x, 0.0, vr.position.y))
				var p1: Vector2 = _world_to_mini(Vector3(vr.end.x, 0.0, vr.end.y))
				draw_rect(Rect2(p0, p1 - p0), Color(1.0, 1.0, 1.0, 0.88), false, 1.5)

		# Moldura interna dourada do minimapa
		draw_rect(Rect2(Vector2(1.0, 1.0), size - Vector2(2.0, 2.0)), Color(0.76, 0.60, 0.27, 0.85), false, 1.5)


func setup(gm: GameManager, cam: RTSCamera, ai: AIController) -> void:
	game_manager = gm
	camera_rig = cam
	ai_controller = ai
	_build_ui()
	_connect_signals()
	_refresh_resources()
	_refresh_selection_and_commands()


func _make_panel_style(bg: Color = Color(0.09, 0.11, 0.15, 0.92), border: Color = Color(0.76, 0.60, 0.27, 0.92), radius: int = 8) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _make_button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	return sb


func _style_button(btn: Button, bg: Color = Color(0.16, 0.19, 0.26, 0.96), border: Color = Color(0.74, 0.58, 0.26, 0.85)) -> void:
	btn.add_theme_stylebox_override("normal", _make_button_style(bg, border))
	btn.add_theme_stylebox_override("hover", _make_button_style(bg.lightened(0.14), Color(0.95, 0.80, 0.42)))
	btn.add_theme_stylebox_override("pressed", _make_button_style(bg.darkened(0.15), Color(1.0, 0.88, 0.5)))
	btn.add_theme_color_override("font_color", Color(0.95, 0.93, 0.86))


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Overlay de seleção por caixa 2D
	var ov: SelectionOverlay = SelectionOverlay.new()
	ov.gm = game_manager
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(ov)
	_selection_box_overlay = ov

	# -------------------------------------------------------------------------
	# BARRA SUPERIOR
	# -------------------------------------------------------------------------
	var top_bar: PanelContainer = PanelContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_left = 10
	top_bar.offset_right = -10
	top_bar.offset_top = 8
	top_bar.offset_bottom = 56
	top_bar.add_theme_stylebox_override("panel", _make_panel_style())
	top_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(top_bar)

	var top_hb: HBoxContainer = HBoxContainer.new()
	top_hb.add_theme_constant_override("separation", 10)
	top_bar.add_child(top_hb)

	var title_lbl: Label = Label.new()
	title_lbl.text = "COROA DE FERRO"
	title_lbl.add_theme_color_override("font_color", Color(0.95, 0.80, 0.38))
	title_lbl.add_theme_font_size_override("font_size", 15)
	top_hb.add_child(title_lbl)

	_gold_lbl = Label.new()
	_gold_lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.25))
	_gold_lbl.add_theme_font_size_override("font_size", 14)
	top_hb.add_child(_gold_lbl)

	_wood_lbl = Label.new()
	_wood_lbl.add_theme_color_override("font_color", Color(0.55, 0.92, 0.45))
	_wood_lbl.add_theme_font_size_override("font_size", 14)
	top_hb.add_child(_wood_lbl)

	_pop_lbl = Label.new()
	_pop_lbl.add_theme_color_override("font_color", Color(0.60, 0.86, 1.0))
	_pop_lbl.add_theme_font_size_override("font_size", 14)
	top_hb.add_child(_pop_lbl)

	_age_lbl = Label.new()
	_age_lbl.add_theme_color_override("font_color", Color(0.92, 0.85, 0.72))
	_age_lbl.add_theme_font_size_override("font_size", 13)
	top_hb.add_child(_age_lbl)

	_time_lbl = Label.new()
	_time_lbl.add_theme_color_override("font_color", Color(0.80, 0.84, 0.90))
	_time_lbl.add_theme_font_size_override("font_size", 13)
	top_hb.add_child(_time_lbl)

	_fps_lbl = Label.new()
	_fps_lbl.add_theme_color_override("font_color", Color(0.55, 0.92, 0.65))
	_fps_lbl.add_theme_font_size_override("font_size", 13)
	top_hb.add_child(_fps_lbl)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hb.add_child(spacer)

	_idle_btn = Button.new()
	_idle_btn.text = "Ociosos: 0 [Tab]"
	_idle_btn.add_theme_font_size_override("font_size", 13)
	_style_button(_idle_btn)
	_idle_btn.pressed.connect(func() -> void:
		if game_manager != null:
			game_manager.select_next_idle_worker()
	)
	top_hb.add_child(_idle_btn)

	var base_btn: Button = Button.new()
	base_btn.text = "Base [Espaço]"
	base_btn.add_theme_font_size_override("font_size", 13)
	_style_button(base_btn)
	base_btn.pressed.connect(func() -> void:
		if game_manager != null:
			game_manager.focus_camera_on_base()
	)
	top_hb.add_child(base_btn)

	var north_btn: Button = Button.new()
	north_btn.text = "Norte [Bksp]"
	north_btn.add_theme_font_size_override("font_size", 13)
	_style_button(north_btn)
	north_btn.pressed.connect(func() -> void:
		if camera_rig != null:
			camera_rig.reset_orientation()
	)
	top_hb.add_child(north_btn)

	_edge_btn = Button.new()
	_edge_btn.text = "Borda: ON [P]"
	_edge_btn.add_theme_font_size_override("font_size", 13)
	_style_button(_edge_btn)
	_edge_btn.pressed.connect(_on_toggle_edge_pan)
	top_hb.add_child(_edge_btn)

	var wave_btn: Button = Button.new()
	wave_btn.text = "Onda IA"
	wave_btn.add_theme_font_size_override("font_size", 13)
	_style_button(wave_btn, Color(0.38, 0.14, 0.14, 0.95), Color(0.88, 0.35, 0.28))
	wave_btn.pressed.connect(func() -> void:
		if ai_controller != null:
			ai_controller.launch_attack_wave()
	)
	top_hb.add_child(wave_btn)

	var help_btn: Button = Button.new()
	help_btn.text = "Ajuda [F1]"
	help_btn.add_theme_font_size_override("font_size", 13)
	_style_button(help_btn)
	help_btn.pressed.connect(_toggle_help_modal)
	top_hb.add_child(help_btn)

	# -------------------------------------------------------------------------
	# BANNER DE ALERTAS
	# -------------------------------------------------------------------------
	_alert_panel = PanelContainer.new()
	_alert_panel.anchor_left = 0.5
	_alert_panel.anchor_right = 0.5
	_alert_panel.anchor_top = 0.0
	_alert_panel.offset_left = -320
	_alert_panel.offset_right = 320
	_alert_panel.offset_top = 64
	_alert_panel.offset_bottom = 102
	_alert_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.08, 0.09, 0.12, 0.88), Color(0.85, 0.68, 0.30, 0.85), 6))
	_alert_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_alert_panel.visible = false
	_root.add_child(_alert_panel)

	_alert_lbl = Label.new()
	_alert_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_alert_lbl.add_theme_font_size_override("font_size", 14)
	_alert_panel.add_child(_alert_lbl)

	# -------------------------------------------------------------------------
	# MINIMAPA TÁTICO (CANTO INFERIOR ESQUERDO)
	# -------------------------------------------------------------------------
	var mini_panel: PanelContainer = PanelContainer.new()
	mini_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	mini_panel.offset_left = 12
	mini_panel.offset_top = -236
	mini_panel.offset_right = 236
	mini_panel.offset_bottom = -12
	mini_panel.add_theme_stylebox_override("panel", _make_panel_style())
	mini_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(mini_panel)

	var md: MinimapDrawer = MinimapDrawer.new()
	md.gm = game_manager
	md.cam_rig = camera_rig
	md.custom_minimum_size = Vector2(204, 204)
	md.gui_input.connect(_on_minimap_gui_input.bind(md))
	mini_panel.add_child(md)
	_minimap_canvas = md

	# -------------------------------------------------------------------------
	# PAINEL CENTRAL DE SELEÇÃO E PRODUÇÃO
	# -------------------------------------------------------------------------
	var sel_panel: PanelContainer = PanelContainer.new()
	sel_panel.anchor_left = 0.5
	sel_panel.anchor_right = 0.5
	sel_panel.anchor_top = 1.0
	sel_panel.anchor_bottom = 1.0
	sel_panel.offset_left = -290
	sel_panel.offset_right = 210
	sel_panel.offset_top = -164
	sel_panel.offset_bottom = -12
	sel_panel.add_theme_stylebox_override("panel", _make_panel_style())
	sel_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(sel_panel)

	var sel_vb: VBoxContainer = VBoxContainer.new()
	sel_vb.add_theme_constant_override("separation", 6)
	sel_panel.add_child(sel_vb)

	_sel_title_lbl = Label.new()
	_sel_title_lbl.add_theme_color_override("font_color", Color(0.98, 0.85, 0.42))
	_sel_title_lbl.add_theme_font_size_override("font_size", 16)
	sel_vb.add_child(_sel_title_lbl)

	_sel_sub_lbl = Label.new()
	_sel_sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sel_sub_lbl.add_theme_color_override("font_color", Color(0.84, 0.88, 0.93))
	_sel_sub_lbl.add_theme_font_size_override("font_size", 13)
	sel_vb.add_child(_sel_sub_lbl)

	var hp_row: HBoxContainer = HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 8)
	sel_vb.add_child(hp_row)

	_sel_hp_bar = ProgressBar.new()
	_sel_hp_bar.custom_minimum_size = Vector2(240, 18)
	_sel_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sel_hp_bar.show_percentage = false
	hp_row.add_child(_sel_hp_bar)

	_sel_hp_lbl = Label.new()
	_sel_hp_lbl.add_theme_font_size_override("font_size", 13)
	hp_row.add_child(_sel_hp_lbl)

	_sel_filter_row = HFlowContainer.new()
	_sel_filter_row.add_theme_constant_override("h_separation", 6)
	_sel_filter_row.add_theme_constant_override("v_separation", 4)
	sel_vb.add_child(_sel_filter_row)

	_sel_queue_box = VBoxContainer.new()
	_sel_queue_box.add_theme_constant_override("separation", 4)
	sel_vb.add_child(_sel_queue_box)

	_sel_queue_lbl = Label.new()
	_sel_queue_lbl.add_theme_color_override("font_color", Color(0.65, 0.90, 1.0))
	_sel_queue_lbl.add_theme_font_size_override("font_size", 13)
	_sel_queue_box.add_child(_sel_queue_lbl)

	_sel_queue_bar = ProgressBar.new()
	_sel_queue_bar.custom_minimum_size = Vector2(260, 16)
	_sel_queue_box.add_child(_sel_queue_bar)

	# -------------------------------------------------------------------------
	# COMMAND CARD 3x3 (CANTO INFERIOR DIREITO)
	# -------------------------------------------------------------------------
	var cmd_panel: PanelContainer = PanelContainer.new()
	cmd_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	cmd_panel.offset_left = -395
	cmd_panel.offset_top = -224
	cmd_panel.offset_right = -12
	cmd_panel.offset_bottom = -12
	cmd_panel.add_theme_stylebox_override("panel", _make_panel_style())
	cmd_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(cmd_panel)

	var cmd_vb: VBoxContainer = VBoxContainer.new()
	cmd_vb.add_theme_constant_override("separation", 6)
	cmd_panel.add_child(cmd_vb)

	var cmd_hdr: Label = Label.new()
	cmd_hdr.text = "ORDENS E CONSTRUÇÕES"
	cmd_hdr.add_theme_color_override("font_color", Color(0.95, 0.80, 0.38))
	cmd_hdr.add_theme_font_size_override("font_size", 13)
	cmd_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cmd_vb.add_child(cmd_hdr)

	_cmd_grid = GridContainer.new()
	_cmd_grid.columns = 3
	_cmd_grid.add_theme_constant_override("h_separation", 6)
	_cmd_grid.add_theme_constant_override("v_separation", 6)
	cmd_vb.add_child(_cmd_grid)

	# -------------------------------------------------------------------------
	# MODAL DE AJUDA [F1]
	# -------------------------------------------------------------------------
	_help_modal = PanelContainer.new()
	_help_modal.anchor_left = 0.5
	_help_modal.anchor_right = 0.5
	_help_modal.anchor_top = 0.5
	_help_modal.anchor_bottom = 0.5
	_help_modal.offset_left = -280
	_help_modal.offset_right = 280
	_help_modal.offset_top = -210
	_help_modal.offset_bottom = 210
	_help_modal.add_theme_stylebox_override("panel", _make_panel_style(Color(0.07, 0.09, 0.13, 0.97)))
	_help_modal.visible = false
	_root.add_child(_help_modal)

	var hvb: VBoxContainer = VBoxContainer.new()
	hvb.add_theme_constant_override("separation", 10)
	_help_modal.add_child(hvb)

	var htitle: Label = Label.new()
	htitle.text = "MANUAL DO COMANDANTE — COROA DE FERRO"
	htitle.add_theme_color_override("font_color", Color(0.98, 0.82, 0.36))
	htitle.add_theme_font_size_override("font_size", 17)
	htitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hvb.add_child(htitle)

	var htext: Label = Label.new()
	htext.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	htext.add_theme_font_size_override("font_size", 14)
	htext.text = (
		"• Câmera: WASD/Setas (+Shift turbo) • Borda da Tela ([P]) • Arraste 1:1 com Botão do Meio • Zoom ao Cursor (Roda)\n"
		+ "• Órbita 3D: Alt+Botão do Meio ou Z/C • Norte: [Backspace] • Seguir Unidade: [F] • Favoritos: Ctrl+F2..F4 / F2..F4\n"
		+ "• Seleção: Clique Esquerdo (Duplo Clique seleciona tropas iguais) ou Arraste Caixa 2D • Shift adiciona\n"
		+ "• Ordens (Botão Direito): Terreno move em formação • Inimigo ataca • Ouro/Árvore coleta • Prédio constrói/repara\n"
		+ "• Grupos de Controle: Ctrl + 1..5 salva esquadrão • 1..5 seleciona (duplo toque desliza câmera)\n"
		+ "• Objetivo: Destrua todas as estruturas do Barão Corvo Vermelho (Nordeste) antes que destruam as suas!"
	)
	hvb.add_child(htext)

	var hclose: Button = Button.new()
	hclose.text = "Fechar [F1]"
	_style_button(hclose)
	hclose.pressed.connect(_toggle_help_modal)
	hvb.add_child(hclose)

	# -------------------------------------------------------------------------
	# MODAL DE VITÓRIA / DERROTA
	# -------------------------------------------------------------------------
	_end_modal = PanelContainer.new()
	_end_modal.anchor_left = 0.5
	_end_modal.anchor_right = 0.5
	_end_modal.anchor_top = 0.5
	_end_modal.anchor_bottom = 0.5
	_end_modal.offset_left = -260
	_end_modal.offset_right = 260
	_end_modal.offset_top = -170
	_end_modal.offset_bottom = 170
	_end_modal.add_theme_stylebox_override("panel", _make_panel_style(Color(0.07, 0.08, 0.12, 0.98)))
	_end_modal.visible = false
	_root.add_child(_end_modal)

	var evb: VBoxContainer = VBoxContainer.new()
	evb.add_theme_constant_override("separation", 12)
	_end_modal.add_child(evb)

	_end_title_lbl = Label.new()
	_end_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_title_lbl.add_theme_font_size_override("font_size", 26)
	evb.add_child(_end_title_lbl)

	_end_stats_lbl = Label.new()
	_end_stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_stats_lbl.add_theme_font_size_override("font_size", 15)
	evb.add_child(_end_stats_lbl)

	var restart_btn: Button = Button.new()
	restart_btn.text = "Jogar Novamente"
	restart_btn.custom_minimum_size = Vector2(200, 44)
	_style_button(restart_btn)
	restart_btn.pressed.connect(func() -> void:
		get_tree().reload_current_scene()
	)
	evb.add_child(restart_btn)


func _connect_signals() -> void:
	if game_manager == null:
		return
	game_manager.resources_changed.connect(_refresh_resources)
	game_manager.selection_changed.connect(_refresh_selection_and_commands)
	game_manager.alert_posted.connect(_show_alert)
	game_manager.game_over.connect(_on_game_over)


func _exit_tree() -> void:
	_cmd_actions.clear()


func _process(delta: float) -> void:
	if game_manager == null:
		return

	var drawing: bool = game_manager.is_drawing_selection_box()
	if drawing or _was_drawing_box:
		_was_drawing_box = drawing
		if _selection_box_overlay != null:
			_selection_box_overlay.queue_redraw()

	if _minimap_dragging and _minimap_canvas != null:
		_minimap_canvas.queue_redraw()

	if _alert_timer > 0.0:
		_alert_timer -= delta
		if _alert_timer <= 0.0 and _alert_panel != null:
			_alert_panel.visible = false

	_refresh_accum += delta
	if _refresh_accum >= 0.15:
		_refresh_accum = 0.0
		if _minimap_canvas != null:
			_minimap_canvas.queue_redraw()
		_refresh_live_panels()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ek: InputEventKey = event as InputEventKey
		if ek.pressed and not ek.echo:
			if ek.keycode == KEY_F1:
				_toggle_help_modal()
				return
			if ek.keycode == KEY_P:
				_on_toggle_edge_pan()
				return
			if ek.keycode == KEY_BACKSPACE and camera_rig != null:
				camera_rig.reset_orientation()
				return
			var bm_keys: Array[int] = [KEY_F2, KEY_F3, KEY_F4]
			var bm_idx: int = bm_keys.find(ek.keycode)
			if bm_idx != -1 and camera_rig != null:
				var slot: int = bm_idx + 2
				if ek.ctrl_pressed:
					camera_rig.save_bookmark(slot)
					if game_manager != null:
						game_manager.post_alert("Posição de câmera F%d salva!" % slot, Color(0.7, 0.88, 1.0))
				else:
					camera_rig.load_bookmark(slot)
				return
			for act in _cmd_actions:
				if int(act.get("key", 0)) == ek.keycode:
					var cb: Callable = act["cb"]
					cb.call()
					get_viewport().set_input_as_handled()
					return


func _on_toggle_edge_pan() -> void:
	if camera_rig == null:
		return
	var on: bool = camera_rig.toggle_edge_pan()
	if _edge_btn != null:
		_edge_btn.text = "Borda: %s [P]" % ("ON" if on else "OFF")
	if game_manager != null:
		game_manager.post_alert("Movimento nas bordas da tela: %s" % ("Ativado" if on else "Desativado"), Color(0.75, 0.90, 1.0))


func _toggle_help_modal() -> void:
	if _help_modal != null:
		_help_modal.visible = not _help_modal.visible


func _on_minimap_gui_input(event: InputEvent, drawer: MinimapDrawer) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_minimap_dragging = mb.pressed
			if camera_rig != null:
				camera_rig.block_edge_pan = _minimap_dragging
			if mb.pressed and camera_rig != null:
				camera_rig.focus_on(drawer.mini_to_world(mb.position), true)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if game_manager != null:
				game_manager.issue_minimap_move(drawer.mini_to_world(mb.position))
	elif event is InputEventMouseMotion and _minimap_dragging:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		if camera_rig != null:
			camera_rig.focus_on(drawer.mini_to_world(mm.position), true)


func _show_alert(msg: String, color: Color) -> void:
	if _alert_panel == null or _alert_lbl == null:
		return
	_alert_lbl.text = msg
	_alert_lbl.add_theme_color_override("font_color", color)
	_alert_panel.visible = true
	_alert_timer = 4.2


func _on_game_over(player_won: bool, st: Dictionary) -> void:
	if _end_modal == null:
		return
	_end_modal.visible = true
	if player_won:
		_end_title_lbl.text = "VITÓRIA REAL!"
		_end_title_lbl.add_theme_color_override("font_color", Color(1.0, 0.84, 0.28))
	else:
		_end_title_lbl.text = "DERROTA NA FRONTEIRA"
		_end_title_lbl.add_theme_color_override("font_color", Color(0.95, 0.30, 0.25))

	var mins: int = int(game_manager.match_time) / 60
	var secs: int = int(game_manager.match_time) % 60
	_end_stats_lbl.text = (
		"Duração da Batalha: %02d:%02d\n" % [mins, secs]
		+ "Ouro Coletado: %d  |  Madeira Coletada: %d\n" % [int(st["gold_gathered"]), int(st["wood_gathered"])]
		+ "Tropas Treinadas: %d  |  Construções Erguidas: %d\n" % [int(st["units_trained"]), int(st["buildings_built"])]
		+ "Inimigos Derrotados: %d" % int(st["enemies_slain"])
	)


func _refresh_resources() -> void:
	if game_manager == null or _gold_lbl == null:
		return
	_gold_lbl.text = "Ouro: %d" % game_manager.get_team_gold(0)
	_wood_lbl.text = "Madeira: %d" % game_manager.get_team_wood(0)
	var pop_u: int = game_manager.get_team_pop_used(0)
	var pop_c: int = game_manager.get_team_pop_cap(0)
	_pop_lbl.text = "População: %d / %d" % [pop_u, pop_c]
	if pop_u >= pop_c:
		_pop_lbl.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	else:
		_pop_lbl.add_theme_color_override("font_color", Color(0.60, 0.86, 1.0))

	var age_num: int = game_manager.get_team_age(0)
	_age_lbl.text = "Era: %s" % ("Era Real ★" if age_num >= 2 else "Era da Fronteira")


func _refresh_live_panels() -> void:
	if game_manager == null:
		return
	var mins: int = int(game_manager.match_time) / 60
	var secs: int = int(game_manager.match_time) % 60
	_time_lbl.text = "Tempo: %02d:%02d" % [mins, secs]
	if _fps_lbl != null:
		_fps_lbl.text = "FPS: %d" % int(Engine.get_frames_per_second())

	var idle_count: int = game_manager.get_idle_workers(0).size()
	_idle_btn.text = "Ociosos: %d [Tab]" % idle_count

	_refresh_selection_values_only()


func _refresh_selection_values_only() -> void:
	if game_manager == null or _sel_title_lbl == null:
		return

	if is_instance_valid(game_manager.selected_resource):
		var r: RTSResourceNode = game_manager.selected_resource
		_sel_hp_bar.visible = true
		_sel_hp_bar.max_value = r.max_amount
		_sel_hp_bar.value = r.amount_left
		_sel_hp_lbl.text = "%d / %d" % [r.amount_left, r.max_amount]
		_sel_queue_box.visible = false
		return

	if is_instance_valid(game_manager.selected_building):
		var b: RTSBuilding = game_manager.selected_building
		_sel_hp_bar.visible = true
		_sel_hp_bar.max_value = b.max_hp
		_sel_hp_bar.value = b.hp
		_sel_hp_lbl.text = "%d / %d HP" % [int(b.hp), int(b.max_hp)]
		if not b.is_constructed:
			_sel_sub_lbl.text = "%s • Em construção: %d%%" % ["Aliado" if b.team == 0 else "Inimigo", int(b.build_progress * 100.0)]
		elif b.building_type == "tower":
			_sel_sub_lbl.text = "%s • Ataque: %d | Alcance: %.0fm" % ["Aliado" if b.team == 0 else "Inimigo", int(b.attack_damage), b.attack_range]
		elif b.building_type == "house":
			_sel_sub_lbl.text = "%s • +8 População Máx. | Renda: +2 Ouro / 5s" % ("Aliado" if b.team == 0 else "Inimigo")
		else:
			_sel_sub_lbl.text = "%s • Armadura: %d | Clique direito define ponto de reunião" % ["Aliado" if b.team == 0 else "Inimigo", b.armor]

		if b.team == 0 and b.is_constructed and b.production_queue.size() > 0:
			_sel_queue_box.visible = true
			var next_name: String = String(RTSUnit.STATS[b.production_queue[0]]["name"])
			var prog: float = b.get_production_progress()
			_sel_queue_lbl.text = "Treinando: %s (%d na fila)" % [next_name, b.production_queue.size()]
			_sel_queue_bar.max_value = 100.0
			_sel_queue_bar.value = prog * 100.0
		else:
			_sel_queue_box.visible = false
		return

	if game_manager.selected_units.size() == 1 and is_instance_valid(game_manager.selected_units[0]):
		var u: RTSUnit = game_manager.selected_units[0]
		_sel_hp_bar.visible = true
		_sel_hp_bar.max_value = u.max_hp
		_sel_hp_bar.value = u.hp
		_sel_hp_lbl.text = "%d / %d HP" % [int(u.hp), int(u.max_hp)]
		_sel_sub_lbl.text = "%s • Dano: %d | Armadura: %d | Vel: %.1f\nEstado: %s" % [
			"Aliado" if u.team == 0 else "Inimigo",
			int(u.attack_damage),
			u.armor,
			u.move_speed,
			u.get_state_label()
		]
		_sel_queue_box.visible = false
		return

	if game_manager.selected_units.size() > 1:
		_sel_hp_bar.visible = false
		_sel_hp_lbl.text = ""
		_sel_queue_box.visible = false
		return

	_sel_hp_bar.visible = false
	_sel_hp_lbl.text = ""
	_sel_queue_box.visible = false


func _refresh_selection_and_commands() -> void:
	if game_manager == null or _sel_title_lbl == null:
		return

	for ch in _sel_filter_row.get_children():
		ch.queue_free()

	if is_instance_valid(game_manager.selected_resource):
		var r: RTSResourceNode = game_manager.selected_resource
		_sel_title_lbl.text = r.get_display_name()
		_sel_sub_lbl.text = "Clique com o botão direito usando Camponeses para extrair este recurso."
	elif is_instance_valid(game_manager.selected_building):
		var b: RTSBuilding = game_manager.selected_building
		_sel_title_lbl.text = b.get_display_name()
	elif game_manager.selected_units.size() == 1 and is_instance_valid(game_manager.selected_units[0]):
		var u: RTSUnit = game_manager.selected_units[0]
		_sel_title_lbl.text = u.get_display_name()
	elif game_manager.selected_units.size() > 1:
		_sel_title_lbl.text = "Esquadrão (%d Unidades)" % game_manager.selected_units.size()
		var counts: Dictionary = {}
		for u in game_manager.selected_units:
			if is_instance_valid(u):
				counts[u.unit_type] = int(counts.get(u.unit_type, 0)) + 1
		var parts: Array[String] = []
		for u_type in counts.keys():
			var c: int = int(counts[u_type])
			var uname: String = String(RTSUnit.STATS[u_type]["name"])
			parts.append("%dx %s" % [c, uname])
			var fbtn: Button = Button.new()
			fbtn.text = "%s (%d)" % [uname, c]
			_style_button(fbtn)
			var capture_type: String = String(u_type)
			fbtn.pressed.connect(func() -> void:
				_filter_selection_by_type(capture_type)
			)
			_sel_filter_row.add_child(fbtn)
		_sel_sub_lbl.text = ", ".join(parts)
	else:
		_sel_title_lbl.text = "Nenhuma Seleção"
		_sel_sub_lbl.text = "Arraste com o botão esquerdo para selecionar tropas ou clique em um prédio."

	_refresh_selection_values_only()
	_rebuild_command_card()


func _filter_selection_by_type(u_type: String) -> void:
	if game_manager == null:
		return
	var keep: Array[RTSUnit] = []
	for u in game_manager.selected_units:
		if is_instance_valid(u):
			if u.unit_type == u_type:
				keep.append(u)
			else:
				u.set_selected(false)
	game_manager.selected_units = keep
	game_manager.selection_changed.emit()


func _rebuild_command_card() -> void:
	for ch in _cmd_grid.get_children():
		ch.queue_free()
	_cmd_actions.clear()

	if is_instance_valid(game_manager.selected_building) and game_manager.selected_building.team == 0:
		var b: RTSBuilding = game_manager.selected_building
		if b.building_type == "town_center" and b.is_constructed:
			_add_cmd("Camponês\n50 Ouro [Q]", KEY_Q, func() -> void:
				if not b.queue_unit("worker"):
					game_manager.post_alert("Ouro insuficiente ou fila cheia!", Color(1.0, 0.45, 0.35))
			)
			if game_manager.get_team_age(0) < 2:
				_add_cmd("Era Real\n250O 200M [E]", KEY_E, func() -> void:
					game_manager.upgrade_age(0)
					_rebuild_command_card()
				)
			_add_cmd("Cancelar Fila\n[X]", KEY_X, func() -> void:
				b.cancel_last_production()
			)
		elif b.building_type == "barracks" and b.is_constructed:
			_add_cmd("Espadachim\n75O 25M [Q]", KEY_Q, func() -> void:
				if not b.queue_unit("soldier"):
					game_manager.post_alert("Recursos insuficientes ou fila cheia!", Color(1.0, 0.45, 0.35))
			)
			_add_cmd("Arqueiro\n60O 50M [E]", KEY_E, func() -> void:
				if not b.queue_unit("archer"):
					game_manager.post_alert("Recursos insuficientes ou fila cheia!", Color(1.0, 0.45, 0.35))
			)
			_add_cmd("Paladino\n140O 60M [R]", KEY_R, func() -> void:
				if not b.queue_unit("knight"):
					game_manager.post_alert("Recursos insuficientes ou fila cheia!", Color(1.0, 0.45, 0.35))
			)
			_add_cmd("Cancelar Fila\n[X]", KEY_X, func() -> void:
				b.cancel_last_production()
			)
		return

	var has_player_unit: bool = false
	var has_worker: bool = false
	for u in game_manager.selected_units:
		if is_instance_valid(u) and u.team == 0:
			has_player_unit = true
			if u.unit_type == "worker":
				has_worker = true

	if has_worker or not has_player_unit:
		_add_cmd("Casa\n40O 80M [Q]", KEY_Q, func() -> void:
			game_manager.start_building_placement("house")
		)
		_add_cmd("Quartel\n120O 150M [E]", KEY_E, func() -> void:
			game_manager.start_building_placement("barracks")
		)
		_add_cmd("Torre Vigia\n100O 120M [R]", KEY_R, func() -> void:
			game_manager.start_building_placement("tower")
		)
		_add_cmd("Salão Real\n300O 250M [T]", KEY_T, func() -> void:
			game_manager.start_building_placement("town_center")
		)

	if has_worker:
		_add_cmd("Coletar\nPróximo [G]", KEY_G, func() -> void:
			game_manager.command_selected_auto_gather()
		)

	if has_player_unit:
		_add_cmd("Atacar-Mover\n[X]", KEY_X, func() -> void:
			game_manager.attack_move_mode = true
			game_manager.post_alert("Modo Atacar-Mover ativo: clique no destino desejado!", Color(1.0, 0.45, 0.35))
		)
		_add_cmd("Parar\n[V]", KEY_V, func() -> void:
			game_manager.command_selected_stop()
		)
		_add_cmd("Seguir\nUnidade [F]", KEY_F, func() -> void:
			if camera_rig == null:
				return
			if camera_rig.is_following():
				camera_rig.stop_following()
				game_manager.post_alert("Câmera liberada.", Color(0.75, 0.9, 1.0))
			elif game_manager.selected_units.size() > 0 and is_instance_valid(game_manager.selected_units[0]):
				camera_rig.start_following(game_manager.selected_units[0])
				game_manager.post_alert("Seguindo unidade (mova a câmera ou pressione [F] para soltar).", Color(0.6, 0.92, 1.0))
		)


func _add_cmd(label_text: String, key_code: int, callback: Callable) -> void:
	var btn: Button = Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(114, 52)
	btn.add_theme_font_size_override("font_size", 12)
	_style_button(btn)
	btn.pressed.connect(callback)
	_cmd_grid.add_child(btn)
	_cmd_actions.append({"key": key_code, "cb": callback})
