extends CanvasLayer
class_name RTSHUD

## Interface medieval profissional do RTS 'Coroa de Ferro: Crônicas da Fronteira':
## - Topbar com brasão, pílulas de recursos (comida/madeira/ouro/pedra/pop), fase Trégua/Guerra e atalhos icônicos
## - Objetivos com selos visuais, banner heráldico com fade suave e minimapa com moldura e bússola
## - Painel de seleção com retrato 3D emoldurado, barras metálicas, chips de atributos, fila visual e cards de esquadrão
## - Cartão de comandos com abas Economia/Militar, ladrilhos 3D, keycaps dourados e custos com ícones
## - Modais ornamentados (Menu Inicial, Manual, Pausa e Vitória/Derrota)

signal start_requested(difficulty: String, fog_on: bool)

const ECO_BUILDINGS: Array[String] = ["house", "farm", "mill", "lumber_camp", "mining_camp", "market", "town_center"]
const MIL_BUILDINGS: Array[String] = ["barracks", "archery_range", "siege_workshop", "tower", "castle"]
const SLOT_KEYS: Array[int] = [KEY_Q, KEY_E, KEY_R, KEY_T, KEY_Y, KEY_U, KEY_I]
const SLOT_KEY_NAMES: Array[String] = ["Q", "E", "R", "T", "Y", "U", "I"]

const UNIT_SHORT_NAMES: Dictionary = {
	"worker": "Camponês",
	"scout": "Batedor",
	"soldier": "Espadachim",
	"spearman": "Lanceiro",
	"archer": "Arqueiro",
	"knight": "Paladino",
	"ram": "Aríete",
	"captain": "Capitão",
}

const BLD_SHORT_NAMES: Dictionary = {
	"house": "Casa",
	"farm": "Fazenda",
	"mill": "Moinho",
	"lumber_camp": "Serraria",
	"mining_camp": "Mineração",
	"market": "Mercado",
	"town_center": "Salão Real",
	"barracks": "Quartel",
	"archery_range": "Campo Tiro",
	"siege_workshop": "Ofic. Cerco",
	"tower": "Torre Vigia",
	"castle": "Castelo",
}

const RES_STAT_COLORS: Dictionary = {
	"food": Color(1.0, 0.72, 0.56),
	"wood": Color(0.66, 0.94, 0.56),
	"gold": Color(1.0, 0.88, 0.42),
	"stone": Color(0.84, 0.88, 0.94),
}

var game_manager: GameManager = null
var camera_rig: RTSCamera = null
var ai_controller: Node = null  # WaveDirector (modo de ondas): get_threat_info()

var _portraits: Dictionary = {}
var _icons: Dictionary = {}
var _chrome: Dictionary = {}

var _font_serif: SystemFont
var _font_serif_bold: SystemFont
var _font_ui: SystemFont
var _font_ui_bold: SystemFont

var _root: Control
var _res_lbls: Dictionary = {}
var _pop_lbl: Label
var _time_lbl: Label
var _phase_lbl: Label
var _phase_icon: TextureRect
var _fps_lbl: Label
var _idle_btn: Button
var _idle_lbl: Label
var _mute_btn: Button
var _mute_icon: TextureRect
var _edge_btn: Button
var _edge_icon: TextureRect
var _hud_gameplay_panels: Array[CanvasItem] = []

var _alert_panel: PanelContainer
var _alert_lbl: Label
var _alert_timer: float = 0.0

var _obj_panel: PanelContainer
var _obj_find_icon: TextureRect
var _obj_find_lbl: Label
var _obj_destroy_icon: TextureRect
var _obj_destroy_lbl: Label
var _obj_protect_icon: TextureRect
var _obj_protect_lbl: Label

var _selection_box_overlay: Control
var _minimap_canvas: Control
var _minimap_fog_mat: ShaderMaterial

var _sel_single_box: HBoxContainer
var _sel_squad_box: VBoxContainer
var _sel_empty_box: HBoxContainer
var _sel_portrait_bg: ColorRect
var _sel_portrait_rect: TextureRect
var _sel_title_lbl: Label
var _sel_badge_panel: PanelContainer
var _sel_badge_lbl: Label
var _sel_sub_lbl: Label
var _sel_hp_bar: ProgressBar
var _sel_hp_lbl: Label
var _sel_stats_row: HFlowContainer
var _sel_queue_box: VBoxContainer
var _sel_queue_lbl: Label
var _sel_queue_bar: ProgressBar
var _sel_queue_slots: Array[PanelContainer] = []
var _sel_queue_icons: Array[TextureRect] = []
var _sel_filter_row: HFlowContainer

var _cmd_tab_row: HBoxContainer
var _cmd_tab_eco_btn: Button
var _cmd_tab_mil_btn: Button
var _cmd_hdr_row: HBoxContainer
var _cmd_hdr: Label
var _cmd_grid: GridContainer
var _cmd_actions: Array[Dictionary] = []
var _cmd_page: String = "eco"

var _help_modal: Control
var _pause_modal: Control
var _start_modal: Control
var _end_modal: Control
var _decree_modal: Control
var _decree_cards_box: HBoxContainer
var _decree_sub_lbl: Label
var _decree_btn: Button
var _decree_btn_lbl: Label
var _early_wave_btn: Button
var _war_cry_tile_lbl: Label = null
var _hold_tile_lbl: Label = null
var _bell_tile_lbl: Label = null
var _end_title_lbl: Label
var _end_reason_lbl: Label
var _end_stats_lbl: Label
var _end_res_lbls: Dictionary = {}
var _start_diff: String = "normal"
var _start_fog_check: CheckButton

var _minimap_dragging: bool = false
var _was_drawing_box: bool = false
var _refresh_accum: float = 0.0
var _enemy_found: bool = false
var _last_bar_fill_key: String = ""
var _last_sel_signature: String = ""


class SelectionOverlay extends Control:
	var gm: GameManager = null
	func _draw() -> void:
		if gm == null or not gm.is_drawing_selection_box():
			return
		var rect: Rect2 = gm.get_selection_box_rect()
		draw_rect(rect, Color(0.22, 0.85, 0.45, 0.16), true)
		draw_rect(rect, Color(0.92, 0.80, 0.35, 0.94), false, 2.0)


class MinimapDrawer extends Control:
	var gm: GameManager = null
	var cam_rig: RTSCamera = null
	var map_half: float = GameManager.MAP_HALF

	func _world_to_mini(pos: Vector3) -> Vector2:
		var u: float = clampf((pos.x + map_half) / (map_half * 2.0), 0.0, 1.0)
		var v: float = clampf((pos.z + map_half) / (map_half * 2.0), 0.0, 1.0)
		return Vector2(u * size.x, v * size.y)

	func mini_to_world(local_pt: Vector2) -> Vector3:
		var u: float = clampf(local_pt.x / maxf(1.0, size.x), 0.0, 1.0)
		var v: float = clampf(local_pt.y / maxf(1.0, size.y), 0.0, 1.0)
		return Vector3(u * map_half * 2.0 - map_half, 0.0, v * map_half * 2.0 - map_half)

	func _draw() -> void:
		var sc: float = size.x / (map_half * 2.0)
		for bp in RTSUnit.BRIDGES:
			var p: Vector2 = _world_to_mini(bp)
			draw_rect(Rect2(p - Vector2(4.0, 4.0), Vector2(8.0, 8.0)), Color(0.65, 0.59, 0.48), true)
		if gm == null:
			return
		var fog: FogOfWar = gm.fog

		for r in gm.resources:
			if not is_instance_valid(r) or r.is_queued_for_deletion():
				continue
			if fog != null and not fog.is_explored_at(r.global_position):
				continue
			var mp: Vector2 = _world_to_mini(r.global_position)
			match r.kind:
				"gold_mine":
					draw_circle(mp, 3.2, Color(0.98, 0.82, 0.18))
				"stone_quarry":
					draw_circle(mp, 3.0, Color(0.78, 0.80, 0.86))
				"berry_bush":
					draw_circle(mp, 1.6, Color(0.92, 0.32, 0.36))
				"farm":
					var fs: float = maxf(3.0, r.collision_radius * 1.6 * sc)
					draw_rect(Rect2(mp - Vector2(fs, fs) * 0.5, Vector2(fs, fs)), Color(0.82, 0.70, 0.32, 0.9), true)
				_:
					draw_circle(mp, 1.3, Color(0.10, 0.36, 0.12))

		for b in gm.buildings:
			if not is_instance_valid(b) or b._dead:
				continue
			if b.team != 0 and b.fog_hidden:
				continue
			var mp: Vector2 = _world_to_mini(b.global_position)
			if b.building_type == "lair":
				# Covil descoberto: marcador vermelho com X
				draw_circle(mp, 6.5, Color(0.55, 0.06, 0.05))
				draw_arc(mp, 6.5, 0.0, TAU, 20, Color(1.0, 0.35, 0.3), 1.6, true)
				draw_line(mp + Vector2(-3.5, -3.5), mp + Vector2(3.5, 3.5), Color(1.0, 0.85, 0.8), 1.6)
				draw_line(mp + Vector2(-3.5, 3.5), mp + Vector2(3.5, -3.5), Color(1.0, 0.85, 0.8), 1.6)
				continue
			var col: Color = Color(0.24, 0.65, 1.0) if b.team == 0 else Color(0.95, 0.25, 0.22)
			var sz: float = 8.0 if b.is_main_structure else 5.0
			draw_rect(Rect2(mp - Vector2(sz * 0.5, sz * 0.5), Vector2(sz, sz)), col, true)
			if b.is_main_structure:
				draw_rect(Rect2(mp - Vector2(sz * 0.5, sz * 0.5), Vector2(sz, sz)), Color(1, 1, 1, 0.82), false, 1.0)

		for c in gm.caches:
			if not is_instance_valid(c) or bool(c.claimed) or bool(c.fog_hidden):
				continue
			var mp_c: Vector2 = _world_to_mini(c.global_position)
			var diam: PackedVector2Array = PackedVector2Array([
				mp_c + Vector2(0.0, -4.0),
				mp_c + Vector2(4.0, 0.0),
				mp_c + Vector2(0.0, 4.0),
				mp_c + Vector2(-4.0, 0.0),
			])
			draw_colored_polygon(diam, Color(1.0, 0.86, 0.28, 0.95))
			diam.append(diam[0])
			draw_polyline(diam, Color(1.0, 0.98, 0.82, 0.95), 1.0, true)

		for u in gm.units:
			if not is_instance_valid(u) or u._dead:
				continue
			if u.team != 0 and u.fog_hidden:
				continue
			var mp: Vector2 = _world_to_mini(u.global_position)
			var col: Color = Color(0.55, 0.9, 1.0) if u.team == 0 else Color(1.0, 0.42, 0.38)
			draw_circle(mp, 2.1 if u.unit_type != "ram" else 3.0, col)

		for pg in gm.pings:
			var t: float = float(pg["t"])
			var mp: Vector2 = _world_to_mini(pg["pos"])
			var pulse: float = fmod(t, 1.0)
			var c: Color = pg["color"]
			c.a = clampf(1.0 - t / 5.0, 0.0, 1.0)
			draw_arc(mp, 4.0 + pulse * 12.0, 0.0, TAU, 24, c, 2.0, true)

		if cam_rig != null:
			var poly_world: PackedVector2Array = cam_rig.get_view_polygon_world()
			if poly_world.size() >= 4:
				var pts: PackedVector2Array = PackedVector2Array()
				for wp in poly_world:
					pts.append(_world_to_mini(Vector3(wp.x, 0.0, wp.y)))
				pts.append(pts[0])
				draw_polyline(pts, Color(1.0, 0.96, 0.84, 0.92), 1.6, true)

		draw_rect(Rect2(Vector2(0.5, 0.5), size - Vector2(1.0, 1.0)), Color(0.76, 0.60, 0.27, 0.72), false, 1.2)


# ==============================================================================
# INICIALIZAÇÃO E CARREGAMENTO DE ASSETS VISUAIS
# ==============================================================================

func setup(gm: GameManager, cam: RTSCamera, ai: Node) -> void:
	game_manager = gm
	camera_rig = cam
	ai_controller = ai
	_load_ui_assets()
	_build_ui()
	_connect_signals()
	_refresh_resources()
	_refresh_selection_and_commands()


func _load_ui_assets() -> void:
	_font_serif = SystemFont.new()
	_font_serif.font_names = PackedStringArray(["Palatino Linotype", "Georgia", "Cambria", "Constantia", "Times New Roman"])
	_font_serif.font_weight = 600
	_font_serif_bold = SystemFont.new()
	_font_serif_bold.font_names = _font_serif.font_names
	_font_serif_bold.font_weight = 700

	_font_ui = SystemFont.new()
	_font_ui.font_names = PackedStringArray(["Segoe UI", "Trebuchet MS", "Arial"])
	_font_ui.font_weight = 500
	_font_ui_bold = SystemFont.new()
	_font_ui_bold.font_names = _font_ui.font_names
	_font_ui_bold.font_weight = 700

	var portrait_names: Array[String] = [
		"unit_worker", "unit_scout", "unit_soldier", "unit_spearman", "unit_archer", "unit_knight", "unit_ram",
		"building_town_center", "building_house", "building_farm", "building_mill", "building_lumber_camp",
		"building_mining_camp", "building_market", "building_barracks", "building_archery_range",
		"building_siege_workshop", "building_tower", "building_castle", "building_lair",
		"resource_berry_bush", "resource_tree", "resource_gold_mine", "resource_stone_quarry",
	]
	for pn in portrait_names:
		var t: Texture2D = load("res://assets/ui/portraits/%s.png" % pn) as Texture2D
		if t != null:
			_portraits[pn] = t

	var icon_names: Array[String] = [
		"res_food", "res_wood", "res_gold", "res_stone", "res_pop",
		"stat_attack", "stat_armor", "stat_speed", "stat_sight", "stat_range",
		"cmd_attack_move", "cmd_stop", "cmd_gather", "cmd_follow", "cmd_cancel",
		"tab_eco", "tab_mil", "market_buy", "market_sell", "emblem_crown",
		"ui_idle_worker", "ui_base", "ui_alert", "ui_sound_on", "ui_sound_off",
		"ui_edge_pan", "ui_pause", "ui_help", "phase_peace", "phase_war",
		"obj_done", "obj_todo", "obj_warn",
	]
	for ic in icon_names:
		var t: Texture2D = load("res://assets/ui/icons/%s.png" % ic) as Texture2D
		if t != null:
			_icons[ic] = t

	var chrome_names: Array[String] = [
		"panel_ornate", "panel_topbar", "panel_subtle", "panel_banner",
		"minimap_frame", "portrait_frame",
		"slot_normal", "slot_hover", "slot_pressed", "slot_disabled",
		"pill_bg", "keycap_bg", "tab_active", "tab_inactive",
		"btn_primary_normal", "btn_primary_hover", "btn_danger_normal", "btn_danger_hover",
		"bar_track", "bar_fill_ally", "bar_fill_warn", "bar_fill_enemy", "bar_fill_queue", "bar_fill_resource",
		"divider_gold",
	]
	for ch in chrome_names:
		var t: Texture2D = load("res://assets/ui/chrome/%s.png" % ch) as Texture2D
		if t != null:
			_chrome[ch] = t


func _get_icon(key: String) -> Texture2D:
	return _icons.get(key, null) as Texture2D


func _get_portrait(key: String) -> Texture2D:
	return _portraits.get(key, null) as Texture2D


func _tex_box(key: String, tm_l: float, tm_t: float, tm_r: float, tm_b: float,
		cm_l: float = -1.0, cm_t: float = -1.0, cm_r: float = -1.0, cm_b: float = -1.0,
		mod: Color = Color.WHITE) -> StyleBox:
	var tex: Texture2D = _chrome.get(key, null) as Texture2D
	if tex == null:
		var fb: StyleBoxFlat = StyleBoxFlat.new()
		fb.bg_color = Color(0.09, 0.11, 0.15, 0.94)
		fb.border_color = Color(0.76, 0.60, 0.27, 0.9)
		fb.set_border_width_all(2)
		fb.set_corner_radius_all(6)
		return fb
	var sb: StyleBoxTexture = StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = tm_l
	sb.texture_margin_top = tm_t
	sb.texture_margin_right = tm_r
	sb.texture_margin_bottom = tm_b
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.content_margin_left = tm_l if cm_l < 0.0 else cm_l
	sb.content_margin_top = tm_t if cm_t < 0.0 else cm_t
	sb.content_margin_right = tm_r if cm_r < 0.0 else cm_r
	sb.content_margin_bottom = tm_b if cm_b < 0.0 else cm_b
	sb.modulate_color = mod
	return sb


func _label(text: String, size: int, color: Color, serif: bool = false, bold: bool = false) -> Label:
	var l: Label = Label.new()
	l.text = text
	var fnt: Font = (_font_serif_bold if bold else _font_serif) if serif else (_font_ui_bold if bold else _font_ui)
	if fnt != null:
		l.add_theme_font_override("font", fnt)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


func _icon_rect(key: String, sz: Vector2, stretch: int = TextureRect.STRETCH_KEEP_ASPECT_CENTERED) -> TextureRect:
	var tr: TextureRect = TextureRect.new()
	tr.texture = _get_icon(key)
	tr.custom_minimum_size = sz
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = stretch
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


func _divider(width: float = 0.0) -> TextureRect:
	var div: TextureRect = TextureRect.new()
	div.texture = _chrome.get("divider_gold", null) as Texture2D
	div.custom_minimum_size = Vector2(width, 10)
	div.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	div.stretch_mode = TextureRect.STRETCH_SCALE
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return div


func _style_slot_button(btn: Button, disabled_look: bool = false) -> void:
	if disabled_look:
		btn.add_theme_stylebox_override("normal", _tex_box("slot_disabled", 14, 14, 14, 14, 4, 4, 4, 4))
	else:
		btn.add_theme_stylebox_override("normal", _tex_box("slot_normal", 14, 14, 14, 14, 4, 4, 4, 4))
	btn.add_theme_stylebox_override("hover", _tex_box("slot_hover", 14, 14, 14, 14, 4, 4, 4, 4))
	btn.add_theme_stylebox_override("pressed", _tex_box("slot_pressed", 14, 14, 14, 14, 4, 4, 4, 4))
	btn.add_theme_stylebox_override("focus", _tex_box("slot_hover", 14, 14, 14, 14, 4, 4, 4, 4))
	btn.add_theme_color_override("font_color", Color(0.95, 0.92, 0.84))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.72))


func _style_action_button(btn: Button, kind: String = "slot") -> void:
	btn.focus_mode = Control.FOCUS_NONE
	if kind == "primary":
		btn.add_theme_stylebox_override("normal", _tex_box("btn_primary_normal", 18, 12, 18, 12, 16, 8, 16, 8))
		btn.add_theme_stylebox_override("hover", _tex_box("btn_primary_hover", 18, 12, 18, 12, 16, 8, 16, 8))
		btn.add_theme_stylebox_override("pressed", _tex_box("btn_primary_normal", 18, 12, 18, 12, 16, 8, 16, 8, Color(0.85, 0.85, 0.85)))
	elif kind == "danger":
		btn.add_theme_stylebox_override("normal", _tex_box("btn_danger_normal", 18, 12, 18, 12, 14, 8, 14, 8))
		btn.add_theme_stylebox_override("hover", _tex_box("btn_danger_hover", 18, 12, 18, 12, 14, 8, 14, 8))
		btn.add_theme_stylebox_override("pressed", _tex_box("btn_danger_normal", 18, 12, 18, 12, 14, 8, 14, 8, Color(0.85, 0.85, 0.85)))
	else:
		_style_slot_button(btn, false)
	if _font_serif_bold != null and kind != "slot":
		btn.add_theme_font_override("font", _font_serif_bold)
	elif _font_ui_bold != null:
		btn.add_theme_font_override("font", _font_ui_bold)
	btn.add_theme_color_override("font_color", Color(0.97, 0.94, 0.86))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.72))
	btn.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	btn.add_theme_constant_override("shadow_offset_x", 1)
	btn.add_theme_constant_override("shadow_offset_y", 1)


func _play_ui_click() -> void:
	if game_manager != null and game_manager.sfx != null:
		game_manager.sfx.play_ui_click()


# ==============================================================================
# CONSTRUÇÃO DO HUD PRINCIPAL
# ==============================================================================

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var ov: SelectionOverlay = SelectionOverlay.new()
	ov.gm = game_manager
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(ov)
	_selection_box_overlay = ov

	_build_top_bar()
	_build_alert_banner()
	_build_objectives()
	_build_decree_banner()
	_build_minimap()
	_build_selection_panel()
	_build_command_card()
	_build_help_modal()
	_build_pause_modal()
	_build_decree_modal()
	_build_end_modal()
	_build_start_modal()


func _make_resource_pill(icon_key: String, col: Color, tip: String) -> Dictionary:
	var pill: PanelContainer = PanelContainer.new()
	pill.custom_minimum_size = Vector2(74, 28)
	pill.tooltip_text = tip
	pill.mouse_filter = Control.MOUSE_FILTER_PASS
	pill.add_theme_stylebox_override("panel", _tex_box("pill_bg", 10, 8, 10, 8, 8, 3, 10, 3))

	var hb: HBoxContainer = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(hb)

	hb.add_child(_icon_rect(icon_key, Vector2(17, 17)))
	var lbl: Label = _label("0", 14, col, false, true)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(lbl)
	return {"pill": pill, "lbl": lbl}


func _make_icon_util_btn(icon_key: String, tip: String, cb: Callable) -> Dictionary:
	var btn: Button = Button.new()
	btn.custom_minimum_size = Vector2(32, 28)
	btn.tooltip_text = tip
	btn.focus_mode = Control.FOCUS_NONE
	_style_slot_button(btn, false)
	btn.pressed.connect(func() -> void:
		_play_ui_click()
		cb.call()
	)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(center)
	var ic: TextureRect = _icon_rect(icon_key, Vector2(18, 18))
	center.add_child(ic)
	return {"btn": btn, "icon": ic}


func _build_top_bar() -> void:
	var top_bar: PanelContainer = PanelContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_left = 0
	top_bar.offset_right = 0
	top_bar.offset_top = 0
	top_bar.offset_bottom = 46
	top_bar.add_theme_stylebox_override("panel", _tex_box("panel_topbar", 24, 8, 24, 12, 14, 4, 14, 8))
	top_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(top_bar)
	_hud_gameplay_panels.append(top_bar)

	var hb: HBoxContainer = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	top_bar.add_child(hb)

	# Brasão + Título Real
	var crest: TextureRect = _icon_rect("emblem_crown", Vector2(26, 26))
	hb.add_child(crest)
	var title: Label = _label("COROA DE FERRO", 15, Color(0.95, 0.80, 0.38), true, true)
	hb.add_child(title)

	var sep1: ColorRect = ColorRect.new()
	sep1.custom_minimum_size = Vector2(1, 22)
	sep1.color = Color(0.68, 0.54, 0.24, 0.55)
	sep1.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(sep1)

	# Pílulas de Recursos (4 recursos + População)
	var res_tips: Dictionary = {
		"food": "Comida — Frutos silvestres, fazendas e coleta. Treina tropas.",
		"wood": "Madeira — Cortada de florestas. Constrói estruturas.",
		"gold": "Ouro — Minerado em veios e Mercado. Tropas de elite.",
		"stone": "Pedra — Extraída de pedreiras. Torres, Salões e Castelos.",
	}
	for r in GameManager.RES_TYPES:
		var pdata: Dictionary = _make_resource_pill("res_" + r, GameManager.RES_COLORS[r], String(res_tips[r]))
		_res_lbls[r] = pdata["lbl"]
		hb.add_child(pdata["pill"])

	var pop_data: Dictionary = _make_resource_pill("res_pop", Color(0.65, 0.88, 1.0), "População atual / capacidade máxima. Construa Casas (+8).")
	_pop_lbl = pop_data["lbl"]
	hb.add_child(pop_data["pill"])

	var sp_l: Control = Control.new()
	sp_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(sp_l)

	# Pílula central de Fase & Relógio
	var phase_pill: PanelContainer = PanelContainer.new()
	phase_pill.custom_minimum_size = Vector2(210, 28)
	phase_pill.add_theme_stylebox_override("panel", _tex_box("pill_bg", 10, 8, 10, 8, 10, 3, 10, 3))
	hb.add_child(phase_pill)
	var phb: HBoxContainer = HBoxContainer.new()
	phb.add_theme_constant_override("separation", 7)
	phb.alignment = BoxContainer.ALIGNMENT_CENTER
	phase_pill.add_child(phb)
	_phase_icon = _icon_rect("phase_peace", Vector2(16, 16))
	phb.add_child(_phase_icon)
	_phase_lbl = _label("Trégua 10:00", 13, Color(0.58, 0.94, 0.62), false, true)
	phb.add_child(_phase_lbl)
	phb.add_child(_label("•", 12, Color(0.62, 0.56, 0.42)))
	_time_lbl = _label("00:00", 13, Color(0.84, 0.88, 0.94), false, true)
	phb.add_child(_time_lbl)

	_early_wave_btn = Button.new()
	_early_wave_btn.custom_minimum_size = Vector2(96, 28)
	_early_wave_btn.tooltip_text = "Convocar próxima onda antes do tempo [K] — Ganhe Ouro bônus!"
	_early_wave_btn.focus_mode = Control.FOCUS_NONE
	_style_action_button(_early_wave_btn, "danger")
	_early_wave_btn.visible = false
	_early_wave_btn.pressed.connect(func() -> void:
		_play_ui_click()
		_on_call_early_wave()
	)
	var ewb_hb: HBoxContainer = HBoxContainer.new()
	ewb_hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ewb_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	ewb_hb.add_theme_constant_override("separation", 4)
	ewb_hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_early_wave_btn.add_child(ewb_hb)
	ewb_hb.add_child(_icon_rect("cmd_attack_move", Vector2(14, 14)))
	var ewb_lbl: Label = _label("Onda [K]", 11, Color(1.0, 0.92, 0.72), false, true)
	ewb_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ewb_hb.add_child(ewb_lbl)
	hb.add_child(_early_wave_btn)

	var sp_r: Control = Control.new()
	sp_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(sp_r)

	# Botão de Camponês Ocioso com contador
	_idle_btn = Button.new()
	_idle_btn.custom_minimum_size = Vector2(68, 28)
	_idle_btn.tooltip_text = "Selecionar próximo camponês ocioso [Tab]"
	_idle_btn.focus_mode = Control.FOCUS_NONE
	_idle_btn.add_theme_stylebox_override("normal", _tex_box("pill_bg", 10, 8, 10, 8, 8, 3, 8, 3))
	_idle_btn.add_theme_stylebox_override("hover", _tex_box("slot_hover", 14, 14, 14, 14, 8, 3, 8, 3))
	_idle_btn.add_theme_stylebox_override("pressed", _tex_box("slot_pressed", 14, 14, 14, 14, 8, 3, 8, 3))
	_idle_btn.pressed.connect(func() -> void:
		_play_ui_click()
		if game_manager != null:
			game_manager.select_next_idle_worker()
	)
	var idle_hb: HBoxContainer = HBoxContainer.new()
	idle_hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	idle_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	idle_hb.add_theme_constant_override("separation", 5)
	idle_hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_idle_btn.add_child(idle_hb)
	idle_hb.add_child(_icon_rect("ui_idle_worker", Vector2(16, 16)))
	_idle_lbl = _label("0", 13, Color(0.85, 0.88, 0.92), false, true)
	_idle_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	idle_hb.add_child(_idle_lbl)
	var tab_hint: Label = _label("[Tab]", 10, Color(0.70, 0.65, 0.50))
	tab_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	idle_hb.add_child(tab_hint)
	hb.add_child(_idle_btn)

	# Botões icônicos de utilidade
	var b_base: Dictionary = _make_icon_util_btn("ui_base", "Centralizar câmera no Salão Real [Espaço]", func() -> void:
		if game_manager != null:
			game_manager.focus_camera_on_base()
	)
	hb.add_child(b_base["btn"])

	var b_alert: Dictionary = _make_icon_util_btn("ui_alert", "Ir até o último alerta de combate [H]", func() -> void:
		if game_manager != null:
			game_manager.focus_last_alert()
	)
	hb.add_child(b_alert["btn"])

	var b_mute: Dictionary = _make_icon_util_btn("ui_sound_on", "Silenciar / ativar efeitos sonoros [M]", _on_toggle_mute)
	_mute_btn = b_mute["btn"]
	_mute_icon = b_mute["icon"]
	hb.add_child(_mute_btn)

	var b_edge: Dictionary = _make_icon_util_btn("ui_edge_pan", "Rolagem na borda da tela: ATIVADA [P]", _on_toggle_edge_pan)
	_edge_btn = b_edge["btn"]
	_edge_icon = b_edge["icon"]
	hb.add_child(_edge_btn)

	var b_pause: Dictionary = _make_icon_util_btn("ui_pause", "Pausar partida [F10]", _toggle_pause)
	hb.add_child(b_pause["btn"])

	var b_help: Dictionary = _make_icon_util_btn("ui_help", "Manual do Comandante [F1]", _toggle_help_modal)
	hb.add_child(b_help["btn"])

	_fps_lbl = _label("60 FPS", 11, Color(0.56, 0.68, 0.64))
	_fps_lbl.custom_minimum_size.x = 48
	_fps_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hb.add_child(_fps_lbl)


func _build_alert_banner() -> void:
	_alert_panel = PanelContainer.new()
	_alert_panel.anchor_left = 0.5
	_alert_panel.anchor_right = 0.5
	_alert_panel.anchor_top = 0.0
	_alert_panel.offset_left = -390
	_alert_panel.offset_right = 390
	_alert_panel.offset_top = 52
	_alert_panel.offset_bottom = 100
	_alert_panel.add_theme_stylebox_override("panel", _tex_box("panel_banner", 48, 10, 48, 10, 44, 8, 44, 10))
	_alert_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_alert_panel.visible = false
	_root.add_child(_alert_panel)

	_alert_lbl = _label("", 14, Color(1.0, 0.90, 0.55), false, true)
	_alert_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_alert_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_alert_panel.add_child(_alert_lbl)


func _build_objectives() -> void:
	_obj_panel = PanelContainer.new()
	_obj_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_obj_panel.offset_left = 12
	_obj_panel.offset_top = 54
	_obj_panel.offset_right = 342
	_obj_panel.offset_bottom = 148
	_obj_panel.add_theme_stylebox_override("panel", _tex_box("panel_subtle", 18, 18, 18, 18, 12, 8, 12, 8))
	_obj_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_obj_panel)
	_hud_gameplay_panels.append(_obj_panel)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	_obj_panel.add_child(vb)

	vb.add_child(_label("OBJETIVOS DA FRONTEIRA", 11, Color(0.93, 0.78, 0.36), true, true))
	vb.add_child(_divider())

	var rows: Array = []
	for _i in range(3):
		var rhb: HBoxContainer = HBoxContainer.new()
		rhb.add_theme_constant_override("separation", 6)
		var ic: TextureRect = _icon_rect("obj_todo", Vector2(14, 14))
		var lbl: Label = _label("", 12, Color(0.90, 0.91, 0.94))
		rhb.add_child(ic)
		rhb.add_child(lbl)
		vb.add_child(rhb)
		rows.append([ic, lbl])

	_obj_find_icon = rows[0][0]
	_obj_find_lbl = rows[0][1]
	_obj_destroy_icon = rows[1][0]
	_obj_destroy_lbl = rows[1][1]
	_obj_protect_icon = rows[2][0]
	_obj_protect_lbl = rows[2][1]


func _build_decree_banner() -> void:
	_decree_btn = Button.new()
	_decree_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_decree_btn.offset_left = 12
	_decree_btn.offset_top = 156
	_decree_btn.offset_right = 342
	_decree_btn.offset_bottom = 194
	_decree_btn.focus_mode = Control.FOCUS_NONE
	_decree_btn.tooltip_text = "Escolha um Decreto Real para fortalecer todo o seu reino [N]"
	_style_action_button(_decree_btn, "primary")
	_decree_btn.visible = false
	_decree_btn.pressed.connect(func() -> void:
		_play_ui_click()
		_open_decree_modal()
	)
	var hb: HBoxContainer = HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_decree_btn.add_child(hb)
	hb.add_child(_icon_rect("emblem_crown", Vector2(20, 20)))
	_decree_btn_lbl = _label("DECRETO REAL DISPONÍVEL [N]", 12, Color(1.0, 0.92, 0.56), true, true)
	_decree_btn_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(_decree_btn_lbl)
	_root.add_child(_decree_btn)


func _build_minimap() -> void:
	var mini_root: Control = Control.new()
	mini_root.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	mini_root.offset_left = 14
	mini_root.offset_top = -246
	mini_root.offset_right = 246
	mini_root.offset_bottom = -14
	mini_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(mini_root)
	_hud_gameplay_panels.append(mini_root)

	var mini_panel: PanelContainer = PanelContainer.new()
	mini_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mini_panel.add_theme_stylebox_override("panel", _tex_box("minimap_frame", 22, 22, 22, 22, 12, 12, 12, 12))
	mini_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	mini_root.add_child(mini_panel)

	var view: Control = Control.new()
	view.custom_minimum_size = Vector2(208, 208)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mini_panel.add_child(view)

	var terrain_tex: Texture2D = load("res://assets/textures/terrain_baked_albedo.png") as Texture2D
	if terrain_tex != null:
		var atlas: AtlasTexture = AtlasTexture.new()
		atlas.atlas = terrain_tex
		var tex_size: Vector2 = terrain_tex.get_size()
		var frac: float = (GameManager.TERRAIN_HALF - GameManager.MAP_HALF) / (GameManager.TERRAIN_HALF * 2.0)
		atlas.region = Rect2(tex_size * frac, tex_size * (1.0 - frac * 2.0))
		var tr: TextureRect = TextureRect.new()
		tr.texture = atlas
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.modulate = Color(1.15, 1.15, 1.15)
		view.add_child(tr)

	var fog_rect: ColorRect = ColorRect.new()
	fog_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fog_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fog_shader: Shader = load("res://scripts/shaders/minimap_fog.gdshader") as Shader
	if fog_shader != null:
		_minimap_fog_mat = ShaderMaterial.new()
		_minimap_fog_mat.shader = fog_shader
		fog_rect.material = _minimap_fog_mat
		if game_manager != null and game_manager.fog != null:
			game_manager.fog.register_material(_minimap_fog_mat)
	else:
		fog_rect.color = Color(0, 0, 0, 0)
	view.add_child(fog_rect)

	var md: MinimapDrawer = MinimapDrawer.new()
	md.gm = game_manager
	md.cam_rig = camera_rig
	md.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	md.mouse_filter = Control.MOUSE_FILTER_STOP
	md.gui_input.connect(_on_minimap_gui_input.bind(md))
	view.add_child(md)
	_minimap_canvas = md

	# Marcadores discretos da bússola sobre a moldura (irmão de mini_panel para não ser realocado pelo PanelContainer)
	for spec in [
		["N", Vector2(109, 0), Vector2(14, 12)],
		["S", Vector2(109, 219), Vector2(14, 12)],
		["O", Vector2(1, 109), Vector2(12, 14)],
		["L", Vector2(218, 109), Vector2(12, 14)],
	]:
		var cl: Label = _label(String(spec[0]), 9, Color(0.96, 0.84, 0.44, 0.95), true, true)
		cl.position = spec[1]
		cl.size = spec[2]
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mini_root.add_child(cl)


func _build_selection_panel() -> void:
	var sel_panel: PanelContainer = PanelContainer.new()
	sel_panel.anchor_left = 0.5
	sel_panel.anchor_right = 0.5
	sel_panel.anchor_top = 1.0
	sel_panel.anchor_bottom = 1.0
	sel_panel.offset_left = -310
	sel_panel.offset_right = 210
	sel_panel.offset_top = -192
	sel_panel.offset_bottom = -14
	sel_panel.add_theme_stylebox_override("panel", _tex_box("panel_ornate", 24, 24, 24, 24, 13, 12, 13, 12))
	sel_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(sel_panel)
	_hud_gameplay_panels.append(sel_panel)

	var holder: Control = Control.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sel_panel.add_child(holder)

	# --- 1. MODO ENTIDADE ÚNICA (Retrato 3D + Barra HP + Título/Badge + Chips + Fila Visual) ---
	_sel_single_box = HBoxContainer.new()
	_sel_single_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sel_single_box.add_theme_constant_override("separation", 12)
	holder.add_child(_sel_single_box)

	var left_col: VBoxContainer = VBoxContainer.new()
	left_col.custom_minimum_size = Vector2(108, 0)
	left_col.add_theme_constant_override("separation", 6)
	left_col.alignment = BoxContainer.ALIGNMENT_CENTER
	_sel_single_box.add_child(left_col)

	var p_frame: PanelContainer = PanelContainer.new()
	p_frame.custom_minimum_size = Vector2(106, 106)
	p_frame.add_theme_stylebox_override("panel", _tex_box("portrait_frame", 18, 18, 18, 18, 6, 6, 6, 6))
	left_col.add_child(p_frame)

	var p_stage: Control = Control.new()
	p_stage.clip_contents = true
	p_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p_frame.add_child(p_stage)

	_sel_portrait_bg = ColorRect.new()
	_sel_portrait_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sel_portrait_bg.color = Color(0.08, 0.14, 0.24, 0.65)
	_sel_portrait_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p_stage.add_child(_sel_portrait_bg)

	_sel_portrait_rect = TextureRect.new()
	_sel_portrait_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sel_portrait_rect.offset_left = 2
	_sel_portrait_rect.offset_top = 2
	_sel_portrait_rect.offset_right = -2
	_sel_portrait_rect.offset_bottom = -2
	_sel_portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sel_portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sel_portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p_stage.add_child(_sel_portrait_rect)

	var hp_wrap: Control = Control.new()
	hp_wrap.custom_minimum_size = Vector2(106, 20)
	left_col.add_child(hp_wrap)
	_sel_hp_bar = ProgressBar.new()
	_sel_hp_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sel_hp_bar.show_percentage = false
	_sel_hp_bar.add_theme_stylebox_override("background", _tex_box("bar_track", 6, 4, 6, 4, 2, 2, 2, 2))
	_sel_hp_bar.add_theme_stylebox_override("fill", _tex_box("bar_fill_ally", 6, 4, 6, 4, 0, 0, 0, 0))
	hp_wrap.add_child(_sel_hp_bar)
	_sel_hp_lbl = _label("75 / 75", 11, Color(0.98, 0.98, 0.98), false, true)
	_sel_hp_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sel_hp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sel_hp_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_wrap.add_child(_sel_hp_lbl)

	var right_col: VBoxContainer = VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 5)
	_sel_single_box.add_child(right_col)

	var title_row: HBoxContainer = HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	right_col.add_child(title_row)
	_sel_title_lbl = _label("Camponês", 18, Color(0.98, 0.86, 0.48), true, true)
	_sel_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_sel_title_lbl)

	_sel_badge_panel = PanelContainer.new()
	_sel_badge_panel.add_theme_stylebox_override("panel", _tex_box("pill_bg", 10, 8, 10, 8, 8, 2, 8, 2))
	title_row.add_child(_sel_badge_panel)
	_sel_badge_lbl = _label("ALIADO", 10, Color(0.45, 0.80, 1.0), false, true)
	_sel_badge_panel.add_child(_sel_badge_lbl)

	_sel_sub_lbl = _label("", 12, Color(0.80, 0.85, 0.92))
	_sel_sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_col.add_child(_sel_sub_lbl)

	_sel_stats_row = HFlowContainer.new()
	_sel_stats_row.add_theme_constant_override("h_separation", 6)
	_sel_stats_row.add_theme_constant_override("v_separation", 4)
	right_col.add_child(_sel_stats_row)

	# Fila de produção visual (5 retratos + progresso)
	_sel_queue_box = VBoxContainer.new()
	_sel_queue_box.add_theme_constant_override("separation", 4)
	_sel_queue_box.visible = false
	right_col.add_child(_sel_queue_box)

	var q_top: HBoxContainer = HBoxContainer.new()
	q_top.add_theme_constant_override("separation", 6)
	_sel_queue_box.add_child(q_top)
	_sel_queue_lbl = _label("Treinando:", 12, Color(0.65, 0.90, 1.0), false, true)
	_sel_queue_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	q_top.add_child(_sel_queue_lbl)

	var q_slots_row: HBoxContainer = HBoxContainer.new()
	q_slots_row.add_theme_constant_override("separation", 5)
	_sel_queue_box.add_child(q_slots_row)
	for qi in range(5):
		var slot: PanelContainer = PanelContainer.new()
		slot.custom_minimum_size = Vector2(32, 32)
		slot.add_theme_stylebox_override("panel", _tex_box("slot_hover" if qi == 0 else "pill_bg", 10, 10, 10, 10, 3, 3, 3, 3))
		var qimg: TextureRect = TextureRect.new()
		qimg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		qimg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		slot.add_child(qimg)
		q_slots_row.add_child(slot)
		_sel_queue_slots.append(slot)
		_sel_queue_icons.append(qimg)

	_sel_queue_bar = ProgressBar.new()
	_sel_queue_bar.custom_minimum_size = Vector2(260, 10)
	_sel_queue_bar.show_percentage = false
	_sel_queue_bar.add_theme_stylebox_override("background", _tex_box("bar_track", 6, 4, 6, 4, 1, 1, 1, 1))
	_sel_queue_bar.add_theme_stylebox_override("fill", _tex_box("bar_fill_queue", 6, 4, 6, 4, 0, 0, 0, 0))
	_sel_queue_box.add_child(_sel_queue_bar)

	# --- 2. MODO ESQUADRÃO (Cartões visuais filtráveis) ---
	_sel_squad_box = VBoxContainer.new()
	_sel_squad_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sel_squad_box.add_theme_constant_override("separation", 6)
	_sel_squad_box.visible = false
	holder.add_child(_sel_squad_box)

	var sq_hdr: HBoxContainer = HBoxContainer.new()
	_sel_squad_box.add_child(sq_hdr)
	var sq_title: Label = _label("ESQUADRÃO SELECIONADO", 14, Color(0.98, 0.85, 0.45), true, true)
	sq_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sq_hdr.add_child(sq_title)
	sq_hdr.add_child(_label("Clique no retrato para filtrar o tipo", 11, Color(0.68, 0.74, 0.84)))

	_sel_filter_row = HFlowContainer.new()
	_sel_filter_row.add_theme_constant_override("h_separation", 8)
	_sel_filter_row.add_theme_constant_override("v_separation", 6)
	_sel_squad_box.add_child(_sel_filter_row)

	# --- 3. MODO NENHUMA SELEÇÃO ---
	_sel_empty_box = HBoxContainer.new()
	_sel_empty_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sel_empty_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_sel_empty_box.add_theme_constant_override("separation", 16)
	_sel_empty_box.visible = false
	holder.add_child(_sel_empty_box)

	var empty_crest: TextureRect = _icon_rect("emblem_crown", Vector2(54, 54))
	empty_crest.modulate = Color(1.0, 1.0, 1.0, 0.82)
	_sel_empty_box.add_child(empty_crest)
	var empty_vb: VBoxContainer = VBoxContainer.new()
	empty_vb.alignment = BoxContainer.ALIGNMENT_CENTER
	empty_vb.add_theme_constant_override("separation", 4)
	_sel_empty_box.add_child(empty_vb)
	empty_vb.add_child(_label("Coroa de Ferro — Aguardando Ordens", 16, Color(0.92, 0.78, 0.40), true, true))
	empty_vb.add_child(_label("Arraste com o botão esquerdo para tropas ou clique em um prédio / recurso.", 12, Color(0.72, 0.78, 0.86)))


func _build_command_card() -> void:
	var cmd_panel: PanelContainer = PanelContainer.new()
	cmd_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	cmd_panel.offset_left = -444
	cmd_panel.offset_top = -272
	cmd_panel.offset_right = -14
	cmd_panel.offset_bottom = -14
	cmd_panel.add_theme_stylebox_override("panel", _tex_box("panel_ornate", 24, 24, 24, 24, 12, 11, 12, 11))
	cmd_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(cmd_panel)
	_hud_gameplay_panels.append(cmd_panel)

	var cmd_vb: VBoxContainer = VBoxContainer.new()
	cmd_vb.add_theme_constant_override("separation", 6)
	cmd_panel.add_child(cmd_vb)

	# Cabeçalho padrão (Prédios & Unidades Militares)
	_cmd_hdr_row = HBoxContainer.new()
	_cmd_hdr_row.custom_minimum_size = Vector2(0, 28)
	_cmd_hdr_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_cmd_hdr_row.add_theme_constant_override("separation", 8)
	cmd_vb.add_child(_cmd_hdr_row)
	_cmd_hdr = _label("ORDENS E CONSTRUÇÕES", 13, Color(0.96, 0.82, 0.42), true, true)
	_cmd_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cmd_hdr_row.add_child(_cmd_hdr)

	# Abas Economia / Militar [B] (Camponês / Nenhuma seleção)
	_cmd_tab_row = HBoxContainer.new()
	_cmd_tab_row.custom_minimum_size = Vector2(0, 28)
	_cmd_tab_row.add_theme_constant_override("separation", 6)
	_cmd_tab_row.visible = false
	cmd_vb.add_child(_cmd_tab_row)

	_cmd_tab_eco_btn = _make_tab_button("tab_eco", "Economia", func() -> void:
		_cmd_page = "eco"
		_rebuild_command_card()
	)
	_cmd_tab_mil_btn = _make_tab_button("tab_mil", "Militar", func() -> void:
		_cmd_page = "mil"
		_rebuild_command_card()
	)
	_cmd_tab_row.add_child(_cmd_tab_eco_btn)
	_cmd_tab_row.add_child(_cmd_tab_mil_btn)

	_cmd_grid = GridContainer.new()
	_cmd_grid.columns = 4
	_cmd_grid.add_theme_constant_override("h_separation", 6)
	_cmd_grid.add_theme_constant_override("v_separation", 5)
	cmd_vb.add_child(_cmd_grid)


func _make_tab_button(icon_key: String, title: String, cb: Callable) -> Button:
	var b: Button = Button.new()
	b.custom_minimum_size = Vector2(0, 28)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void:
		_play_ui_click()
		cb.call()
	)
	var hb: HBoxContainer = HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 6)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(hb)
	hb.add_child(_icon_rect(icon_key, Vector2(16, 16)))
	var lbl: Label = _label(title, 12, Color(0.95, 0.90, 0.74), true, true)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.name = "TabLabel"
	hb.add_child(lbl)
	return b


func _style_command_tabs() -> void:
	for spec in [
		[_cmd_tab_eco_btn, _cmd_page == "eco", "Economia"],
		[_cmd_tab_mil_btn, _cmd_page == "mil", "Militar"],
	]:
		var btn: Button = spec[0]
		var active: bool = bool(spec[1])
		var base_txt: String = String(spec[2])
		var sb_k: String = "tab_active" if active else "tab_inactive"
		btn.add_theme_stylebox_override("normal", _tex_box(sb_k, 12, 10, 12, 10, 6, 3, 6, 3))
		btn.add_theme_stylebox_override("hover", _tex_box("tab_active", 12, 10, 12, 10, 6, 3, 6, 3))
		btn.add_theme_stylebox_override("pressed", _tex_box("tab_active", 12, 10, 12, 10, 6, 3, 6, 3))
		var lbl: Label = btn.find_child("TabLabel", true, false) as Label
		if lbl != null:
			lbl.text = base_txt if active else ("%s [B]" % base_txt)
			lbl.add_theme_color_override("font_color", Color(1.0, 0.90, 0.56) if active else Color(0.70, 0.75, 0.84))


# ==============================================================================
# MODAIS ORNAMENTADOS (MENU INICIAL, MANUAL, PAUSA E VITÓRIA/DERROTA)
# ==============================================================================

func _make_modal_backdrop(dim: float) -> Control:
	var backdrop: ColorRect = ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.03, 0.05, dim)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.visible = false
	_root.add_child(backdrop)
	return backdrop


func _centered_panel(parent: Control, w: float, h: float) -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.5
	p.anchor_bottom = 0.5
	p.offset_left = -w * 0.5
	p.offset_right = w * 0.5
	p.offset_top = -h * 0.5
	p.offset_bottom = h * 0.5
	p.add_theme_stylebox_override("panel", _tex_box("panel_ornate", 24, 24, 24, 24, 22, 18, 22, 18))
	parent.add_child(p)
	return p


func _build_help_modal() -> void:
	_help_modal = _make_modal_backdrop(0.58)
	var p: PanelContainer = _centered_panel(_help_modal, 760, 560)

	var hvb: VBoxContainer = VBoxContainer.new()
	hvb.add_theme_constant_override("separation", 10)
	p.add_child(hvb)

	var top_hdr: HBoxContainer = HBoxContainer.new()
	top_hdr.alignment = BoxContainer.ALIGNMENT_CENTER
	top_hdr.add_theme_constant_override("separation", 10)
	top_hdr.add_child(_icon_rect("emblem_crown", Vector2(28, 28)))
	top_hdr.add_child(_label("MANUAL DO COMANDANTE", 20, Color(0.98, 0.84, 0.42), true, true))
	hvb.add_child(top_hdr)
	hvb.add_child(_divider())

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hvb.add_child(scroll)

	var svb: VBoxContainer = VBoxContainer.new()
	svb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	svb.add_theme_constant_override("separation", 8)
	scroll.add_child(svb)

	var sections: Array = [
		["phase_war", "OBJETIVO DE CAMPANHA",
			"Monte e defenda sua base. Os covis do Barão Corvo Vermelho ficam em pontos sorteados além do rio, ocultos pela névoa, e enviam ondas cada vez mais fortes enquanto existirem. Encontre e destrua todos os covis para vencer; você perde se ficar sem Salão Real e sem Castelo. As minas mais ricas ficam perto dos covis."],
		["res_gold", "ECONOMIA E PONTOS DE ENTREGA",
			"Camponeses coletam Comida (frutos/fazendas), Madeira (árvores), Ouro (minas) e Pedra (pedreiras). Erga Moinhos, Serrarias e Minerações junto aos recursos para acelerar as entregas. Casas dão +8 de população."],
		["stat_attack", "EXÉRCITO, TÁTICAS E VETERANIA",
			"Lanceiros destroem Paladinos e Batedores; Paladinos esmagam Arqueiros; Aríetes derrubam Torres e Covis e resistem a flechas. Tropas sobem de patente ao abater inimigos (★ Veterano / ★★ Campeão / ★★★ Lenda) e rendem Ouro por abate. Use [Q] Investida e [E] Postura nas tropas selecionadas, e [R] Sino de Defesa no Salão Real."],
		["ui_edge_pan", "EXPLORAÇÃO, DECRETOS, CÂMERA E ATALHOS",
			"Caravanas e Baús perdidos pela névoa dão recursos, tropas e Decretos Reais [N] (bônus permanentes estilo roguelite). Use [K] para provocar ondas antecipadas e ganhar Ouro bônus.\n"
			+ "WASD/Setas (+Shift turbo) • Borda [P] • Botão do meio arrasta • Roda zoom • Z/C giram • Clique/arraste seleciona (duplo clique: tipo) • Ctrl+1..5 grupos • [Tab] ocioso • [Espaço] base • [H] alerta • [M] som • [B] aba • [F9] gráficos • [F10] pausa."],
	]
	for sec in sections:
		var card: PanelContainer = PanelContainer.new()
		card.add_theme_stylebox_override("panel", _tex_box("pill_bg", 10, 8, 10, 8, 12, 8, 12, 8))
		var cvb: VBoxContainer = VBoxContainer.new()
		cvb.add_theme_constant_override("separation", 4)
		card.add_child(cvb)
		var chb: HBoxContainer = HBoxContainer.new()
		chb.add_theme_constant_override("separation", 8)
		chb.add_child(_icon_rect(String(sec[0]), Vector2(18, 18)))
		chb.add_child(_label(String(sec[1]), 13, Color(0.95, 0.82, 0.42), true, true))
		cvb.add_child(chb)
		var txt: Label = _label(String(sec[2]), 13, Color(0.88, 0.90, 0.94))
		txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cvb.add_child(txt)
		svb.add_child(card)

	var hclose: Button = Button.new()
	hclose.text = "Fechar Manual [F1]"
	hclose.custom_minimum_size = Vector2(220, 40)
	hclose.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_action_button(hclose, "primary")
	hclose.pressed.connect(func() -> void:
		_play_ui_click()
		_toggle_help_modal()
	)
	hvb.add_child(hclose)


func _build_pause_modal() -> void:
	_pause_modal = _make_modal_backdrop(0.58)
	var p: PanelContainer = _centered_panel(_pause_modal, 390, 290)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(vb)

	var crest: TextureRect = _icon_rect("emblem_crown", Vector2(40, 40))
	crest.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(crest)
	var t: Label = _label("JOGO PAUSADO", 22, Color(0.98, 0.84, 0.42), true, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	vb.add_child(_divider())

	for spec in [
		["Continuar [F10]", _toggle_pause, "primary"],
		["Nova Partida", _restart_game, "slot"],
		["Sair do Jogo", _quit_game, "danger"],
	]:
		var b: Button = Button.new()
		b.text = String(spec[0])
		b.custom_minimum_size = Vector2(250, 42)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_style_action_button(b, String(spec[2]))
		var cb: Callable = spec[1]
		b.pressed.connect(func() -> void:
			_play_ui_click()
			cb.call()
		)
		vb.add_child(b)


func _build_end_modal() -> void:
	_end_modal = _make_modal_backdrop(0.56)
	var p: PanelContainer = _centered_panel(_end_modal, 620, 420)
	var evb: VBoxContainer = VBoxContainer.new()
	evb.add_theme_constant_override("separation", 10)
	p.add_child(evb)

	var crest: TextureRect = _icon_rect("emblem_crown", Vector2(48, 48))
	crest.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	evb.add_child(crest)

	_end_title_lbl = _label("", 28, Color(1.0, 0.84, 0.30), true, true)
	_end_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	evb.add_child(_end_title_lbl)
	_end_reason_lbl = _label("", 14, Color(0.90, 0.91, 0.94))
	_end_reason_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_reason_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	evb.add_child(_end_reason_lbl)
	evb.add_child(_divider())

	# Linha de pílulas com recursos coletados na partida
	var res_row: HBoxContainer = HBoxContainer.new()
	res_row.alignment = BoxContainer.ALIGNMENT_CENTER
	res_row.add_theme_constant_override("separation", 10)
	evb.add_child(res_row)
	for r in GameManager.RES_TYPES:
		var rp: Dictionary = _make_resource_pill("res_" + r, GameManager.RES_COLORS[r], String(GameManager.RES_NAMES[r]))
		_end_res_lbls[r] = rp["lbl"]
		res_row.add_child(rp["pill"])

	_end_stats_lbl = _label("", 14, Color(0.84, 0.89, 0.95))
	_end_stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	evb.add_child(_end_stats_lbl)

	var sp: Control = Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	evb.add_child(sp)

	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	evb.add_child(row)
	var again: Button = Button.new()
	again.text = "Nova Partida"
	again.custom_minimum_size = Vector2(210, 46)
	_style_action_button(again, "primary")
	again.pressed.connect(func() -> void:
		_play_ui_click()
		_restart_game()
	)
	row.add_child(again)
	var quit_b: Button = Button.new()
	quit_b.text = "Sair"
	quit_b.custom_minimum_size = Vector2(140, 46)
	_style_action_button(quit_b, "danger")
	quit_b.pressed.connect(func() -> void:
		_play_ui_click()
		_quit_game()
	)
	row.add_child(quit_b)


func _build_start_modal() -> void:
	_start_modal = _make_modal_backdrop(0.76)
	var p: PanelContainer = _centered_panel(_start_modal, 720, 600)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	p.add_child(vb)

	var crest: TextureRect = _icon_rect("emblem_crown", Vector2(68, 68))
	crest.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(crest)

	var title: Label = _label("COROA DE FERRO", 36, Color(1.0, 0.85, 0.34), true, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var sub: Label = _label("Crônicas da Fronteira", 16, Color(0.86, 0.78, 0.58), true, false)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	vb.add_child(_divider())

	# Três pilares visuais da partida em vez de muro de texto
	var pillars: HBoxContainer = HBoxContainer.new()
	pillars.add_theme_constant_override("separation", 10)
	vb.add_child(pillars)
	for spec in [
		["res_food", "INÍCIO", "Colete os 4 recursos durante a trégua e explore a névoa."],
		["stat_armor", "MEIO DE JOGO", "Cada covil do Barão envia ondas cada vez mais fortes. Segure-as com torres e tropas."],
		["phase_war", "VITÓRIA", "Encontre os covis escondidos além do rio e destrua todos eles."],
	]:
		var card: PanelContainer = PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", _tex_box("pill_bg", 10, 8, 10, 8, 10, 8, 10, 8))
		var cvb: VBoxContainer = VBoxContainer.new()
		cvb.add_theme_constant_override("separation", 4)
		card.add_child(cvb)
		var chb: HBoxContainer = HBoxContainer.new()
		chb.add_theme_constant_override("separation", 6)
		chb.add_child(_icon_rect(String(spec[0]), Vector2(18, 18)))
		chb.add_child(_label(String(spec[1]), 12, Color(0.95, 0.82, 0.42), true, true))
		cvb.add_child(chb)
		var desc: Label = _label(String(spec[2]), 12, Color(0.86, 0.89, 0.94))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cvb.add_child(desc)
		pillars.add_child(card)

	var diff_hdr: Label = _label("DIFICULDADE DA FRONTEIRA", 13, Color(0.95, 0.80, 0.38), true, true)
	diff_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(diff_hdr)

	var diff_row: HBoxContainer = HBoxContainer.new()
	diff_row.alignment = BoxContainer.ALIGNMENT_CENTER
	diff_row.add_theme_constant_override("separation", 12)
	vb.add_child(diff_row)
	var group: ButtonGroup = ButtonGroup.new()
	var diff_btns: Dictionary = {}
	var update_diff_styles := func() -> void:
		for k in diff_btns.keys():
			var db: Button = diff_btns[k]
			var active: bool = (String(k) == _start_diff)
			db.add_theme_stylebox_override("normal", _tex_box("slot_hover" if active else "slot_normal", 14, 14, 14, 14, 8, 6, 8, 6))
			db.add_theme_stylebox_override("hover", _tex_box("slot_hover", 14, 14, 14, 14, 8, 6, 8, 6))
			db.add_theme_stylebox_override("pressed", _tex_box("slot_pressed", 14, 14, 14, 14, 8, 6, 8, 6))

	for key in ["facil", "normal", "dificil"]:
		var d: Dictionary = WaveDirector.DIFFICULTY[key]
		var b: Button = Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.text = "%s\n%d covis • 1ª onda ~%d min" % [String(d["name"]), int(d["lairs"]), int(float(d["first_wave"]) / 60.0)]
		b.custom_minimum_size = Vector2(194, 58)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_color_override("font_color", Color(0.96, 0.93, 0.84))
		b.button_pressed = (key == _start_diff)
		diff_btns[key] = b
		var cap_key: String = key
		b.pressed.connect(func() -> void:
			_play_ui_click()
			_start_diff = cap_key
			update_diff_styles.call()
		)
		diff_row.add_child(b)
	update_diff_styles.call()

	_start_fog_check = CheckButton.new()
	_start_fog_check.text = "Névoa de guerra (recomendado)"
	_start_fog_check.button_pressed = true
	_start_fog_check.add_theme_font_size_override("font_size", 14)
	_start_fog_check.add_theme_color_override("font_color", Color(0.88, 0.90, 0.94))
	_start_fog_check.focus_mode = Control.FOCUS_NONE
	_start_fog_check.pressed.connect(_play_ui_click)
	var fog_row: HBoxContainer = HBoxContainer.new()
	fog_row.alignment = BoxContainer.ALIGNMENT_CENTER
	fog_row.add_child(_start_fog_check)
	vb.add_child(fog_row)

	var start_b: Button = Button.new()
	start_b.text = "Iniciar Batalha"
	start_b.custom_minimum_size = Vector2(280, 52)
	start_b.add_theme_font_size_override("font_size", 19)
	_style_action_button(start_b, "primary")
	start_b.pressed.connect(func() -> void:
		_play_ui_click()
		_start_modal.visible = false
		start_requested.emit(_start_diff, _start_fog_check.button_pressed)
	)
	var start_row: HBoxContainer = HBoxContainer.new()
	start_row.alignment = BoxContainer.ALIGNMENT_CENTER
	start_row.add_theme_constant_override("separation", 14)
	start_row.add_child(start_b)
	var quit_start: Button = Button.new()
	quit_start.text = "Sair"
	quit_start.custom_minimum_size = Vector2(120, 52)
	quit_start.add_theme_font_size_override("font_size", 15)
	_style_action_button(quit_start, "danger")
	quit_start.pressed.connect(func() -> void:
		_play_ui_click()
		_quit_game()
	)
	start_row.add_child(quit_start)
	vb.add_child(start_row)

	var hint: Label = _label("[F1] manual completo durante o jogo • [M] áudio • [F9] qualidade gráfica • [F10] pausa", 12, Color(0.68, 0.72, 0.78))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(hint)


func _build_decree_modal() -> void:
	_decree_modal = _make_modal_backdrop(0.68)
	var p: PanelContainer = _centered_panel(_decree_modal, 840, 440)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	p.add_child(vb)

	var hdr: HBoxContainer = HBoxContainer.new()
	hdr.alignment = BoxContainer.ALIGNMENT_CENTER
	hdr.add_theme_constant_override("separation", 10)
	hdr.add_child(_icon_rect("emblem_crown", Vector2(32, 32)))
	hdr.add_child(_label("DECRETO REAL DA FRONTEIRA", 22, Color(1.0, 0.85, 0.34), true, true))
	vb.add_child(hdr)

	_decree_sub_lbl = _label("Escolha um edito permanente para fortalecer todo o seu reino:", 13, Color(0.86, 0.90, 0.96))
	_decree_sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_decree_sub_lbl)
	vb.add_child(_divider())

	_decree_cards_box = HBoxContainer.new()
	_decree_cards_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_decree_cards_box.add_theme_constant_override("separation", 14)
	vb.add_child(_decree_cards_box)

	var close_b: Button = Button.new()
	close_b.text = "Escolher Depois [N]"
	close_b.custom_minimum_size = Vector2(210, 38)
	close_b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_action_button(close_b, "slot")
	close_b.pressed.connect(func() -> void:
		_play_ui_click()
		_close_decree_modal()
	)
	vb.add_child(close_b)


func _set_gameplay_hud_visible(vis: bool) -> void:
	for pan in _hud_gameplay_panels:
		if is_instance_valid(pan):
			pan.visible = vis
	if _decree_btn != null:
		_decree_btn.visible = vis and game_manager != null and game_manager.pending_decrees > 0 and not game_manager.ai_controllers.has(0)


func show_start_menu(difficulty: String, fog_on: bool) -> void:
	_start_diff = difficulty if WaveDirector.DIFFICULTY.has(difficulty) else "normal"
	if _start_fog_check != null:
		_start_fog_check.button_pressed = fog_on
	_set_gameplay_hud_visible(false)
	if _alert_panel != null:
		_alert_panel.visible = false
	_start_modal.visible = true


func on_match_started() -> void:
	if _start_modal != null:
		_start_modal.visible = false
	_set_gameplay_hud_visible(true)
	_refresh_objectives()
	_refresh_resources()
	_refresh_decree_banner()


func on_enemy_discovered() -> void:
	_enemy_found = true
	_refresh_objectives()


# ==============================================================================
# CONEXÕES, LOOP E ENTRADA
# ==============================================================================

func _connect_signals() -> void:
	if game_manager == null:
		return
	game_manager.resources_changed.connect(_refresh_resources)
	game_manager.selection_changed.connect(_refresh_selection_and_commands)
	game_manager.alert_posted.connect(_show_alert)
	game_manager.game_over.connect(_on_game_over)
	game_manager.decree_available.connect(func(_cnt: int) -> void: _refresh_decree_banner())
	game_manager.decree_applied.connect(func(_id: String, _info: Dictionary) -> void: _refresh_decree_banner())


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
		if _alert_panel != null:
			if _alert_timer <= 0.0:
				_alert_panel.visible = false
			elif _alert_timer < 0.8:
				_alert_panel.modulate.a = clampf(_alert_timer / 0.8, 0.0, 1.0)
			else:
				_alert_panel.modulate.a = 1.0

	_refresh_accum += delta
	if _refresh_accum >= 0.15:
		_refresh_accum = 0.0
		if _minimap_canvas != null:
			_minimap_canvas.queue_redraw()
		_refresh_live_panels()


func _modal_open() -> bool:
	return (_start_modal != null and _start_modal.visible) or (_pause_modal != null and _pause_modal.visible) or (_end_modal != null and _end_modal.visible) or (_decree_modal != null and _decree_modal.visible)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var ek: InputEventKey = event as InputEventKey
	if not ek.pressed or ek.echo:
		return
	if ek.keycode == KEY_F10 or ek.keycode == KEY_PAUSE:
		if game_manager != null and game_manager.match_started and not game_manager.is_game_over:
			if _decree_modal != null and _decree_modal.visible:
				_close_decree_modal()
			_toggle_pause()
			get_viewport().set_input_as_handled()
		return
	if ek.keycode == KEY_M:
		_on_toggle_mute()
		get_viewport().set_input_as_handled()
		return
	if _modal_open():
		if _decree_modal != null and _decree_modal.visible and (ek.keycode == KEY_ESCAPE or ek.keycode == KEY_N):
			_close_decree_modal()
			get_viewport().set_input_as_handled()
			return
		if ek.keycode == KEY_ESCAPE and _pause_modal.visible:
			_toggle_pause()
			get_viewport().set_input_as_handled()
		return
	if ek.keycode == KEY_F1:
		_toggle_help_modal()
		get_viewport().set_input_as_handled()
		return
	if ek.keycode == KEY_ESCAPE and _help_modal.visible:
		_help_modal.visible = false
		get_viewport().set_input_as_handled()
		return
	if ek.keycode == KEY_K:
		_on_call_early_wave()
		get_viewport().set_input_as_handled()
		return
	if ek.keycode == KEY_N:
		if game_manager != null and game_manager.pending_decrees > 0:
			_open_decree_modal()
		elif game_manager != null:
			game_manager.post_alert("Nenhum Decreto Real disponível agora (ache Estandartes ou vença batalhas).", Color(0.76, 0.88, 1.0))
		get_viewport().set_input_as_handled()
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
	if ek.ctrl_pressed:
		return
	for act in _cmd_actions:
		if int(act.get("key", 0)) == ek.keycode:
			var cb: Callable = act["cb"]
			cb.call()
			get_viewport().set_input_as_handled()
			return


func _toggle_pause() -> void:
	if game_manager == null or not game_manager.match_started or game_manager.is_game_over:
		return
	var now_paused: bool = not _pause_modal.visible
	_pause_modal.visible = now_paused
	get_tree().paused = now_paused


func _restart_game() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _quit_game() -> void:
	get_tree().quit()


func _on_toggle_mute() -> void:
	if game_manager == null or game_manager.sfx == null:
		return
	var muted: bool = game_manager.sfx.toggle_muted()
	if _mute_icon != null:
		_mute_icon.texture = _get_icon("ui_sound_off" if muted else "ui_sound_on")
	if _mute_btn != null:
		_mute_btn.tooltip_text = "Áudio silenciado [M] — clique para ativar" if muted else "Efeitos sonoros ativos [M]"
	if not muted:
		_play_ui_click()


func _on_toggle_edge_pan() -> void:
	if camera_rig == null:
		return
	var on: bool = camera_rig.toggle_edge_pan()
	if _edge_icon != null:
		_edge_icon.modulate = Color(1.0, 1.0, 1.0, 1.0) if on else Color(0.55, 0.58, 0.65, 0.55)
	if _edge_btn != null:
		_edge_btn.tooltip_text = "Rolagem na borda da tela: %s [P]" % ("ATIVADA" if on else "DESATIVADA")
	if game_manager != null:
		game_manager.post_alert("Rolagem nas bordas da tela: %s" % ("Ativada" if on else "Desativada"), Color(0.75, 0.90, 1.0))


func _toggle_help_modal() -> void:
	if _help_modal != null:
		_help_modal.visible = not _help_modal.visible


func _on_call_early_wave() -> void:
	if ai_controller == null or not ai_controller.has_method("call_next_wave_early"):
		return
	var res: Dictionary = ai_controller.call_next_wave_early()
	if not bool(res.get("ok", false)) and game_manager != null:
		game_manager.post_alert("A próxima onda já está se reunindo para marchar!", Color(1.0, 0.72, 0.36))
	_refresh_live_panels()


func _refresh_decree_banner() -> void:
	if _decree_btn == null or game_manager == null:
		return
	var pend: int = game_manager.pending_decrees
	var can_show: bool = pend > 0 and game_manager.match_started and not game_manager.is_game_over and not game_manager.ai_controllers.has(0) and (_start_modal == null or not _start_modal.visible)
	_decree_btn.visible = can_show
	if can_show and _decree_btn_lbl != null:
		_decree_btn_lbl.text = "★ DECRETO REAL (%d) — ESCOLHER [N]" % pend if pend > 1 else "★ DECRETO REAL DISPONÍVEL — ESCOLHER [N]"


func _open_decree_modal() -> void:
	if _decree_modal == null or game_manager == null or game_manager.pending_decrees <= 0 or game_manager.is_game_over:
		return
	var choices: Array[Dictionary] = game_manager.get_or_roll_decree_choices()
	if choices.is_empty():
		return
	for ch in _decree_cards_box.get_children():
		ch.queue_free()

	_decree_sub_lbl.text = "Restam %d decreto(s) para promulgar. Escolha um edito permanente:" % game_manager.pending_decrees
	for c in choices:
		var cid: String = String(c["id"])
		var card: PanelContainer = PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", _tex_box("pill_bg", 10, 8, 10, 8, 14, 14, 14, 14))
		var cvb: VBoxContainer = VBoxContainer.new()
		cvb.add_theme_constant_override("separation", 10)
		cvb.alignment = BoxContainer.ALIGNMENT_CENTER
		card.add_child(cvb)

		var ic: TextureRect = _icon_rect(String(c.get("icon", "emblem_crown")), Vector2(44, 44))
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cvb.add_child(ic)

		var t_lbl: Label = _label(String(c["title"]), 16, Color(1.0, 0.86, 0.36), true, true)
		t_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cvb.add_child(t_lbl)

		var d_lbl: Label = _label(String(c["desc"]), 13, Color(0.90, 0.92, 0.96))
		d_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cvb.add_child(d_lbl)

		var pick_btn: Button = Button.new()
		pick_btn.text = "Promulgar Decreto"
		pick_btn.custom_minimum_size = Vector2(0, 42)
		_style_action_button(pick_btn, "primary")
		pick_btn.pressed.connect(func() -> void:
			_play_ui_click()
			game_manager.apply_royal_decree(cid)
			if game_manager.pending_decrees > 0:
				_open_decree_modal()
			else:
				_close_decree_modal()
		)
		cvb.add_child(pick_btn)
		_decree_cards_box.add_child(card)

	_decree_modal.visible = true
	get_tree().paused = true


func _close_decree_modal() -> void:
	if _decree_modal != null:
		_decree_modal.visible = false
	if (_pause_modal == null or not _pause_modal.visible) and (_start_modal == null or not _start_modal.visible):
		get_tree().paused = false
	_refresh_decree_banner()


func _on_minimap_gui_input(event: InputEvent, drawer: MinimapDrawer) -> void:
	if game_manager == null or not game_manager.match_started:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_minimap_dragging = mb.pressed
			if camera_rig != null:
				camera_rig.block_edge_pan = _minimap_dragging
			if mb.pressed and camera_rig != null:
				camera_rig.focus_on(drawer.mini_to_world(mb.position), true)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
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
	_alert_panel.modulate.a = 1.0
	_alert_panel.visible = true
	_alert_timer = 5.0


func _on_game_over(player_won: bool, st: Dictionary) -> void:
	if _end_modal == null:
		return
	_pause_modal.visible = false
	_help_modal.visible = false
	if _decree_modal != null:
		_decree_modal.visible = false
	if _decree_btn != null:
		_decree_btn.visible = false
	if _early_wave_btn != null:
		_early_wave_btn.visible = false
	get_tree().paused = false
	_end_modal.visible = true
	var w_info: Dictionary = ai_controller.get_threat_info() if ai_controller != null and ai_controller.has_method("get_threat_info") else {}
	if player_won:
		_end_title_lbl.text = "VITÓRIA REAL!"
		_end_title_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
		_end_reason_lbl.text = "Todos os covis do Barão Corvo Vermelho foram destruídos. A fronteira está em paz!"
	else:
		_end_title_lbl.text = "DERROTA NA FRONTEIRA"
		_end_title_lbl.add_theme_color_override("font_color", Color(0.95, 0.32, 0.26))
		_end_reason_lbl.text = "Seu último Salão Real e Castelo caíram diante das ondas do Barão."

	for r in GameManager.RES_TYPES:
		var l: Label = _end_res_lbls.get(r, null) as Label
		if l != null:
			l.text = str(int(st.get(r + "_gathered", 0)))

	var mins: int = int(game_manager.match_time) / 60
	var secs: int = int(game_manager.match_time) % 60
	_end_stats_lbl.text = (
		"Duração da partida: %02d:%02d\n" % [mins, secs]
		+ "Ondas enfrentadas: %d  •  Covis destruídos: %d de %d\n\n" % [int(w_info.get("waves", 0)), int(st.get("lairs_destroyed", 0)), int(w_info.get("lairs_total", 0))]
		+ "Unidades treinadas: %d  •  Construções erguidas: %d\n" % [int(st["units_trained"]), int(st["buildings_built"])]
		+ "Inimigos derrotados: %d  •  Unidades perdidas: %d  •  Prédios perdidos: %d" % [int(st["enemies_slain"]), int(st["units_lost"]), int(st["buildings_lost"])]
	)
	if game_manager.sfx != null:
		if player_won:
			game_manager.sfx.play_victory()
		else:
			game_manager.sfx.play_defeat()


# ==============================================================================
# ATUALIZAÇÃO EM TEMPO REAL (TOP BAR, OBJETIVOS E SELEÇÃO)
# ==============================================================================

func _refresh_resources() -> void:
	if game_manager == null or _pop_lbl == null:
		return
	for r in GameManager.RES_TYPES:
		var l: Label = _res_lbls[r]
		l.text = str(game_manager.get_res(0, r))
	var pop_u: int = game_manager.get_team_pop_used(0)
	var pop_c: int = game_manager.get_team_pop_cap(0)
	_pop_lbl.text = "%d/%d" % [pop_u, pop_c]
	if pop_u >= pop_c:
		_pop_lbl.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	else:
		_pop_lbl.add_theme_color_override("font_color", Color(0.66, 0.88, 1.0))


func _refresh_objectives() -> void:
	if game_manager == null or _obj_find_lbl == null:
		return
	var done_col: Color = Color(0.54, 0.94, 0.58)
	var todo_col: Color = Color(0.90, 0.91, 0.94)
	var warn_col: Color = Color(1.0, 0.50, 0.42)

	var w_info: Dictionary = ai_controller.get_threat_info() if ai_controller != null and ai_controller.has_method("get_threat_info") else {}
	var total: int = int(w_info.get("lairs_total", 0))
	var found_n: int = int(w_info.get("lairs_found", 0))
	var destroyed_n: int = int(w_info.get("lairs_destroyed", 0))
	var all_found: bool = total > 0 and found_n >= total
	_obj_find_icon.texture = _get_icon("obj_done" if all_found else "obj_todo")
	_obj_find_lbl.text = "Encontre os covis na névoa (%d de %d)" % [found_n, total]
	_obj_find_lbl.add_theme_color_override("font_color", done_col if all_found else todo_col)

	var all_destroyed: bool = total > 0 and destroyed_n >= total
	_obj_destroy_icon.texture = _get_icon("obj_done" if all_destroyed else "obj_todo")
	_obj_destroy_lbl.text = "Destrua todos os covis (%d de %d)" % [destroyed_n, total]
	_obj_destroy_lbl.add_theme_color_override("font_color", done_col if all_destroyed else todo_col)

	var my_mains: int = 0
	for b in game_manager.buildings:
		if is_instance_valid(b) and not b._dead and b.team == 0 and b.is_main_structure:
			my_mains += 1
	_obj_protect_icon.texture = _get_icon("obj_warn" if my_mains == 0 else "obj_todo")
	_obj_protect_lbl.text = "Proteja seus Salões e Castelos (%d de pé)" % my_mains
	_obj_protect_lbl.add_theme_color_override("font_color", warn_col if my_mains == 0 else todo_col)


func _refresh_live_panels() -> void:
	if game_manager == null:
		return
	var secs_total: int = int(game_manager.match_time)
	_time_lbl.text = "%02d:%02d" % [secs_total / 60, secs_total % 60]
	if _fps_lbl != null:
		_fps_lbl.text = "%d FPS" % int(Engine.get_frames_per_second())

	if ai_controller != null and ai_controller.has_method("get_threat_info") and game_manager.match_started and not game_manager.ai_controllers.has(0):
		var info: Dictionary = ai_controller.get_threat_info()
		var peace: float = float(info.get("peace_left", 0.0))
		if peace > 0.0:
			_phase_lbl.text = "Trégua %02d:%02d" % [int(peace) / 60, int(peace) % 60]
			_phase_lbl.add_theme_color_override("font_color", Color(0.58, 0.94, 0.62) if peace > 60.0 else Color(1.0, 0.80, 0.35))
			_phase_icon.texture = _get_icon("phase_peace")
		else:
			var nxt: float = float(info.get("next_wave_in", -1.0))
			var wave_num: int = int(info.get("waves", info.get("wave", 0))) + 1
			var phase_txt: String = "Covis %d" % int(info.get("lairs_alive", 0))
			if nxt >= 0.0:
				phase_txt += " • Onda %d em %02d:%02d" % [wave_num, int(nxt) / 60, int(nxt) % 60]
			if int(info.get("marching", 0)) > 0:
				phase_txt += " • %d em marcha" % int(info["marching"])
			_phase_lbl.text = phase_txt
			_phase_lbl.add_theme_color_override("font_color", Color(1.0, 0.52, 0.40))
			_phase_icon.texture = _get_icon("phase_war")
	else:
		_phase_lbl.text = "Batalha"
		_phase_icon.texture = _get_icon("phase_war")

	var idle_count: int = game_manager.get_idle_workers(0).size()
	if _idle_lbl != null:
		_idle_lbl.text = str(idle_count)
		_idle_lbl.add_theme_color_override("font_color", Color(1.0, 0.82, 0.34) if idle_count > 0 else Color(0.84, 0.88, 0.92))

	if _early_wave_btn != null:
		_early_wave_btn.visible = (ai_controller != null and ai_controller.has_method("can_call_wave_early") and ai_controller.can_call_wave_early() and not game_manager.ai_controllers.has(0))

	_refresh_decree_banner()
	_refresh_resources()
	_refresh_objectives()
	_refresh_selection_values_only()
	_refresh_command_affordability()


func _set_hp_fill_style(fill_key: String) -> void:
	if fill_key == _last_bar_fill_key or _sel_hp_bar == null:
		return
	_last_bar_fill_key = fill_key
	_sel_hp_bar.add_theme_stylebox_override("fill", _tex_box(fill_key, 6, 4, 6, 4, 0, 0, 0, 0))


func _set_sel_badge(text: String, col: Color) -> void:
	if _sel_badge_lbl == null:
		return
	_sel_badge_lbl.text = text
	_sel_badge_lbl.add_theme_color_override("font_color", col)


func _rebuild_stat_chips(chips: Array) -> void:
	for ch in _sel_stats_row.get_children():
		ch.queue_free()
	for spec in chips:
		var chip: PanelContainer = PanelContainer.new()
		chip.tooltip_text = String(spec[2])
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		chip.add_theme_stylebox_override("panel", _tex_box("pill_bg", 10, 8, 10, 8, 7, 2, 8, 2))
		var hb: HBoxContainer = HBoxContainer.new()
		hb.add_theme_constant_override("separation", 5)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(hb)
		hb.add_child(_icon_rect(String(spec[0]), Vector2(14, 14)))
		var lbl: Label = _label(String(spec[1]), 11, spec[3], false, true)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(lbl)
		_sel_stats_row.add_child(chip)


func _refresh_selection_values_only() -> void:
	if game_manager == null or _sel_title_lbl == null:
		return

	if is_instance_valid(game_manager.selected_resource):
		var r: RTSResourceNode = game_manager.selected_resource
		_sel_hp_bar.max_value = r.max_amount
		_sel_hp_bar.value = r.amount_left
		_sel_hp_lbl.text = "%d / %d" % [r.amount_left, r.max_amount]
		_set_hp_fill_style("bar_fill_resource")
		_sel_queue_box.visible = false
		return

	if is_instance_valid(game_manager.selected_building):
		var b: RTSBuilding = game_manager.selected_building
		_sel_hp_bar.max_value = b.max_hp
		_sel_hp_bar.value = b.hp
		_sel_hp_lbl.text = "%d / %d" % [int(b.hp), int(b.max_hp)]
		var ratio: float = b.hp / maxf(1.0, b.max_hp)
		_set_hp_fill_style("bar_fill_enemy" if b.team != 0 else ("bar_fill_warn" if ratio < 0.45 else "bar_fill_ally"))

		if not b.is_constructed:
			_sel_sub_lbl.text = "Em construção: %d%%" % int(b.build_progress * 100.0)
		else:
			_sel_sub_lbl.text = b.get_description()

		var sig_b: String = "B:%d:%d:%s" % [b.get_instance_id(), 1 if b.is_constructed else 0, str(b.armor)]
		if sig_b != _last_sel_signature:
			_last_sel_signature = sig_b
			var b_chips: Array = [["stat_armor", str(b.armor), "Armadura da estrutura", Color(0.84, 0.88, 0.96)]]
			if b.attack_damage > 0.0:
				b_chips.append(["stat_attack", "%dx%d" % [int(b.attack_damage), b.arrows_per_volley], "Dano de flechas e rajada", Color(1.0, 0.72, 0.54)])
				b_chips.append(["stat_range", "%.0fm" % b.attack_range, "Alcance defensivo", Color(0.75, 0.90, 1.0)])
			if b.pop_bonus > 0:
				b_chips.append(["res_pop", "+%d" % b.pop_bonus, "Bônus de população máxima", Color(0.66, 0.90, 1.0)])
			for dt in b.drop_types:
				b_chips.append(["res_" + String(dt), "Entrega", "Recebe " + String(GameManager.RES_NAMES[dt]), RES_STAT_COLORS.get(String(dt), Color.WHITE)])
			_rebuild_stat_chips(b_chips)

		if b.team == 0 and b.is_constructed and b.production_queue.size() > 0:
			_sel_queue_box.visible = true
			var prog: float = b.get_production_progress()
			var first_name: String = String(RTSUnit.STATS[b.production_queue[0]]["name"])
			if b.is_production_blocked():
				_sel_queue_lbl.text = "População cheia! Construa Casas."
				_sel_queue_lbl.add_theme_color_override("font_color", Color(1.0, 0.48, 0.38))
			else:
				_sel_queue_lbl.text = "Treinando %s (%d%%)" % [first_name, int(prog * 100.0)]
				_sel_queue_lbl.add_theme_color_override("font_color", Color(0.66, 0.90, 1.0))
			for qi in range(5):
				if qi < b.production_queue.size():
					var qt: String = b.production_queue[qi]
					_sel_queue_icons[qi].texture = _get_portrait("unit_" + qt)
					_sel_queue_icons[qi].visible = true
					_sel_queue_slots[qi].modulate = Color.WHITE
				else:
					_sel_queue_icons[qi].visible = false
					_sel_queue_slots[qi].modulate = Color(0.65, 0.65, 0.70, 0.55)
			_sel_queue_bar.max_value = 100.0
			_sel_queue_bar.value = prog * 100.0
		else:
			_sel_queue_box.visible = false
		return

	if game_manager.selected_units.size() == 1 and is_instance_valid(game_manager.selected_units[0]):
		var u: RTSUnit = game_manager.selected_units[0]
		_sel_hp_bar.max_value = u.max_hp
		_sel_hp_bar.value = u.hp
		_sel_hp_lbl.text = "%d / %d" % [int(u.hp), int(u.max_hp)]
		var ratio_u: float = u.hp / maxf(1.0, u.max_hp)
		_set_hp_fill_style("bar_fill_enemy" if u.team != 0 else ("bar_fill_warn" if ratio_u < 0.45 else "bar_fill_ally"))
		var rank_str: String = u.get_rank_title()
		_sel_title_lbl.text = ("%s (%s)" % [u.get_display_name(), rank_str]) if rank_str != "" else u.get_display_name()
		var sub_str: String = u.get_state_label()
		if u.kills > 0:
			sub_str += " • %d abate%s" % [u.kills, "s" if u.kills > 1 else ""]
		_sel_sub_lbl.text = sub_str
		_sel_queue_box.visible = false

		var sig_u: String = "U:%d:%s:%d:%d:%d" % [u.get_instance_id(), u.carrying_type, u.carrying_amount, u.vet_rank, 1 if u._war_cry_timer > 0.0 else 0]
		if sig_u != _last_sel_signature:
			_last_sel_signature = sig_u
			var u_chips: Array = [
				["stat_attack", str(int(u.attack_damage)), "Dano de ataque", Color(1.0, 0.74, 0.56)],
				["stat_armor", str(u.armor), "Armadura física", Color(0.84, 0.88, 0.96)],
				["stat_speed", "%.1f" % u.move_speed, "Velocidade de marcha", Color(0.66, 0.92, 0.96)],
				["stat_sight", "%.0fm" % u.sight_range, "Alcance de visão na névoa", Color(0.95, 0.85, 0.52)],
			]
			if u.is_ranged:
				u_chips.insert(2, ["stat_range", "%.0fm" % u.attack_range, "Alcance de disparo", Color(0.75, 0.90, 1.0)])
			if u.carrying_amount > 0 and u.carrying_type != "":
				u_chips.append([
					"res_" + u.carrying_type,
					"%d/10" % u.carrying_amount,
					"Carregando " + String(GameManager.RES_NAMES.get(u.carrying_type, "")),
					RES_STAT_COLORS.get(u.carrying_type, Color.WHITE),
				])
			_rebuild_stat_chips(u_chips)


func _refresh_selection_and_commands() -> void:
	if game_manager == null or _sel_title_lbl == null:
		return

	_last_sel_signature = ""
	for ch in _sel_filter_row.get_children():
		ch.queue_free()

	if is_instance_valid(game_manager.selected_resource):
		var r: RTSResourceNode = game_manager.selected_resource
		_sel_single_box.visible = true
		_sel_squad_box.visible = false
		_sel_empty_box.visible = false
		_sel_portrait_bg.color = Color(0.20, 0.16, 0.08, 0.65)
		var pkey: String = "building_farm" if r.kind == "farm" else ("resource_" + r.kind)
		_sel_portrait_rect.texture = _get_portrait(pkey)
		_sel_title_lbl.text = r.get_display_name()
		_set_sel_badge("RECURSO", Color(0.98, 0.82, 0.36))
		if r.owner_team == 0:
			_sel_sub_lbl.text = "Sua fazenda. Até 2 camponeses colhem comida aqui com eficiência."
		elif r.owner_team == 1:
			_sel_sub_lbl.text = "Campo de cultivo inimigo."
		else:
			_sel_sub_lbl.text = "Clique com o botão direito usando Camponeses para coletar."
		_rebuild_stat_chips([["res_" + r.resource_type, String(GameManager.RES_NAMES[r.resource_type]), "Tipo de recurso", RES_STAT_COLORS.get(r.resource_type, Color.WHITE)]])
	elif is_instance_valid(game_manager.selected_building):
		var b: RTSBuilding = game_manager.selected_building
		_sel_single_box.visible = true
		_sel_squad_box.visible = false
		_sel_empty_box.visible = false
		_sel_portrait_bg.color = Color(0.08, 0.16, 0.30, 0.72) if b.team == 0 else Color(0.30, 0.09, 0.09, 0.72)
		_sel_portrait_rect.texture = _get_portrait("building_" + b.building_type)
		_sel_title_lbl.text = b.get_display_name()
		_set_sel_badge("ALIADO" if b.team == 0 else "INIMIGO", Color(0.45, 0.82, 1.0) if b.team == 0 else Color(1.0, 0.44, 0.38))
	elif game_manager.selected_units.size() == 1 and is_instance_valid(game_manager.selected_units[0]):
		var u: RTSUnit = game_manager.selected_units[0]
		_sel_single_box.visible = true
		_sel_squad_box.visible = false
		_sel_empty_box.visible = false
		_sel_portrait_bg.color = Color(0.08, 0.16, 0.30, 0.72) if u.team == 0 else Color(0.30, 0.09, 0.09, 0.72)
		var u_pkey: String = "unit_knight" if u.unit_type == "captain" else ("unit_" + u.unit_type)
		_sel_portrait_rect.texture = _get_portrait(u_pkey)
		_sel_title_lbl.text = u.get_display_name()
		_set_sel_badge("ALIADO" if u.team == 0 else "INIMIGO", Color(0.45, 0.82, 1.0) if u.team == 0 else Color(1.0, 0.44, 0.38))
	elif game_manager.selected_units.size() > 1:
		_sel_single_box.visible = false
		_sel_squad_box.visible = true
		_sel_empty_box.visible = false
		var groups: Dictionary = {}
		for u in game_manager.selected_units:
			if not is_instance_valid(u):
				continue
			if not groups.has(u.unit_type):
				groups[u.unit_type] = {"count": 0, "hp": 0.0, "max_hp": 0.0}
			var g: Dictionary = groups[u.unit_type]
			g["count"] = int(g["count"]) + 1
			g["hp"] = float(g["hp"]) + u.hp
			g["max_hp"] = float(g["max_hp"]) + u.max_hp

		for u_type in groups.keys():
			var g: Dictionary = groups[u_type]
			var c: int = int(g["count"])
			var hp_frac: float = clampf(float(g["hp"]) / maxf(1.0, float(g["max_hp"])), 0.0, 1.0)
			var card: Button = Button.new()
			card.custom_minimum_size = Vector2(74, 82)
			card.focus_mode = Control.FOCUS_NONE
			card.tooltip_text = "%dx %s — Clique para selecionar só este tipo" % [c, String(RTSUnit.STATS[u_type]["name"])]
			_style_slot_button(card, false)
			var cap_t: String = String(u_type)
			card.pressed.connect(func() -> void:
				_play_ui_click()
				_filter_selection_by_type(cap_t)
			)

			var cvb: VBoxContainer = VBoxContainer.new()
			cvb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			cvb.offset_left = 4
			cvb.offset_top = 4
			cvb.offset_right = -4
			cvb.offset_bottom = -4
			cvb.add_theme_constant_override("separation", 2)
			cvb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(cvb)

			var p_wrap: Control = Control.new()
			p_wrap.custom_minimum_size = Vector2(64, 46)
			p_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cvb.add_child(p_wrap)
			var img: TextureRect = TextureRect.new()
			img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			var sq_pkey: String = "unit_knight" if String(u_type) == "captain" else ("unit_" + String(u_type))
			img.texture = _get_portrait(sq_pkey)
			img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			img.mouse_filter = Control.MOUSE_FILTER_IGNORE
			p_wrap.add_child(img)

			var badge: PanelContainer = PanelContainer.new()
			badge.position = Vector2(36, 0)
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			badge.add_theme_stylebox_override("panel", _tex_box("keycap_bg", 6, 6, 6, 6, 4, 1, 4, 1))
			var blbl: Label = _label("x%d" % c, 10, Color(1.0, 0.88, 0.44), false, true)
			blbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			badge.add_child(blbl)
			p_wrap.add_child(badge)

			var nl: Label = _label(String(UNIT_SHORT_NAMES.get(u_type, RTSUnit.STATS[u_type]["name"])), 10, Color(0.92, 0.90, 0.84), false, true)
			nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cvb.add_child(nl)

			var bar_bg: ColorRect = ColorRect.new()
			bar_bg.custom_minimum_size = Vector2(0, 4)
			bar_bg.color = Color(0.08, 0.09, 0.12, 0.95)
			bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cvb.add_child(bar_bg)
			var bar_fg: ColorRect = ColorRect.new()
			bar_fg.anchor_left = 0.0
			bar_fg.anchor_top = 0.0
			bar_fg.anchor_bottom = 1.0
			bar_fg.anchor_right = hp_frac
			bar_fg.color = Color(0.32, 0.88, 0.48) if hp_frac > 0.45 else Color(0.95, 0.72, 0.24)
			bar_fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bar_bg.add_child(bar_fg)

			_sel_filter_row.add_child(card)
	else:
		_sel_single_box.visible = false
		_sel_squad_box.visible = false
		_sel_empty_box.visible = true

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


# ==============================================================================
# CARTÃO DE COMANDOS VISUAL
# ==============================================================================

func _rebuild_command_card() -> void:
	for ch in _cmd_grid.get_children():
		ch.queue_free()
	_cmd_actions.clear()
	_war_cry_tile_lbl = null
	_hold_tile_lbl = null
	_bell_tile_lbl = null
	_cmd_hdr_row.visible = true
	_cmd_tab_row.visible = false
	_cmd_hdr.text = "ORDENS E CONSTRUÇÕES"

	if is_instance_valid(game_manager.selected_building):
		var b: RTSBuilding = game_manager.selected_building
		if b.team != 0 or not b.is_constructed:
			return
		_cmd_hdr.text = b.get_display_name().to_upper()
		var i: int = 0
		for u_type in b.trainable:
			var cfg: Dictionary = RTSUnit.STATS[u_type]
			var cost: Dictionary = cfg["cost"]
			var cap_type: String = String(u_type)
			var tip: String = "%s — %s\n%s\nPV %d • Dano %d • Armadura %d • População %d • %ds" % [
				String(cfg["name"]), GameManager.format_cost_long(cost), String(cfg.get("desc", "")),
				int(cfg["hp"]), int(cfg["damage"]), int(cfg["armor"]), int(cfg["pop"]), int(cfg["train_time"])]
			_add_cmd_tile(
				String(UNIT_SHORT_NAMES.get(u_type, cfg["name"])),
				SLOT_KEYS[i], SLOT_KEY_NAMES[i],
				_get_portrait("unit_" + cap_type), "",
				func() -> void: _train(b, cap_type),
				tip, cost
			)
			i += 1
		if b.building_type == "town_center":
			var bell_btn: Button = _add_cmd_tile(
				"Sino Defesa", KEY_R, "R",
				_get_icon("ui_alert"), "",
				func() -> void:
					_play_ui_click()
					game_manager.trigger_defense_bell(),
				"Badala o sino real: Salões, Torres e Castelos disparam +50% mais rápido por 12s (Recarga: 55s)."
			)
			_bell_tile_lbl = bell_btn.find_child("TileLabel", true, false) as Label
		if not b.trainable.is_empty():
			_add_cmd_tile(
				"Cancelar", KEY_X, "X",
				_get_icon("cmd_cancel"), "",
				func() -> void: b.cancel_last_production(),
				"Cancela o último item da fila e devolve os recursos."
			)
		if b.building_type == "market":
			_build_market_card()
		return

	var has_player_unit: bool = false
	var has_worker: bool = false
	var has_military: bool = false
	for u in game_manager.selected_units:
		if is_instance_valid(u) and u.team == 0:
			has_player_unit = true
			if u.unit_type == "worker":
				has_worker = true
			else:
				has_military = true

	if has_worker or not has_player_unit:
		_cmd_hdr_row.visible = false
		_cmd_tab_row.visible = true
		_style_command_tabs()

		var page_list: Array[String] = ECO_BUILDINGS if _cmd_page == "eco" else MIL_BUILDINGS
		for i in range(page_list.size()):
			var b_type: String = page_list[i]
			var cfg_b: Dictionary = RTSBuilding.STATS[b_type]
			var tip_b: String = "%s — %s\n%s" % [String(cfg_b["name"]), GameManager.format_cost_long(cfg_b["cost"]), String(cfg_b.get("desc", ""))]
			var cap_b: String = b_type
			_add_cmd_tile(
				String(BLD_SHORT_NAMES.get(b_type, cfg_b["name"])),
				SLOT_KEYS[i], SLOT_KEY_NAMES[i],
				_get_portrait("building_" + cap_b), "",
				func() -> void:
					_play_ui_click()
					game_manager.start_building_placement(cap_b),
				tip_b, cfg_b["cost"]
			)

		# Registra atalho [B] nas abas preservando o fluxo e contrato de _cmd_actions
		var toggle_tab_cb: Callable = func() -> void:
			_play_ui_click()
			_cmd_page = "mil" if _cmd_page == "eco" else "eco"
			_rebuild_command_card()
		_cmd_actions.append({
			"key": KEY_B,
			"cb": toggle_tab_cb,
			"btn": _cmd_tab_mil_btn if _cmd_page == "eco" else _cmd_tab_eco_btn,
			"cost": {},
			"cost_labels": {},
		})

		if not has_worker:
			return
		_add_cmd_tile(
			"Coletar", KEY_G, "G",
			_get_icon("cmd_gather"), "",
			func() -> void: game_manager.command_selected_auto_gather(),
			"Manda os camponeses selecionados coletarem o recurso mais próximo."
		)
		_add_cmd_tile(
			"Parar", KEY_V, "V",
			_get_icon("cmd_stop"), "",
			func() -> void:
				_play_ui_click()
				game_manager.command_selected_stop(),
			"Interrompe a ordem atual."
		)
		if has_military:
			_add_cmd_tile(
				"Atacar-Mov", KEY_X, "X",
				_get_icon("cmd_attack_move"), "",
				func() -> void:
					_play_ui_click()
					_enter_attack_move(),
				"Move atacando tudo no caminho."
			)
		return

	if has_player_unit:
		_cmd_hdr.text = "ORDENS MILITARES"
		var wc_btn: Button = _add_cmd_tile(
			"Investida", KEY_Q, "Q",
			_get_icon("stat_attack"), "",
			func() -> void:
				_play_ui_click()
				game_manager.trigger_war_cry(),
			"Grito de Guerra: +28% velocidade e ataque rápido para o esquadrão e aliados próximos por 6.5s (Recarga: 26s)."
		)
		_war_cry_tile_lbl = wc_btn.find_child("TileLabel", true, false) as Label
		var hold_btn: Button = _add_cmd_tile(
			"Postura", KEY_E, "E",
			_get_icon("stat_armor"), "",
			func() -> void:
				_play_ui_click()
				game_manager.toggle_selected_hold_position(),
			"Alterna Manter Posição (segura o terreno sem sair perseguindo inimigos)."
		)
		_hold_tile_lbl = hold_btn.find_child("TileLabel", true, false) as Label
		_add_cmd_tile(
			"Atacar-Mov", KEY_X, "X",
			_get_icon("cmd_attack_move"), "",
			func() -> void:
				_play_ui_click()
				_enter_attack_move(),
			"Clique no destino: as tropas atacam tudo no caminho."
		)
		_add_cmd_tile(
			"Parar", KEY_V, "V",
			_get_icon("cmd_stop"), "",
			func() -> void:
				_play_ui_click()
				game_manager.command_selected_stop(),
			"Interrompe a ordem atual."
		)
		_add_cmd_tile(
			"Seguir", KEY_F, "F",
			_get_icon("cmd_follow"), "",
			func() -> void:
				_play_ui_click()
				if camera_rig == null:
					return
				if camera_rig.is_following():
					camera_rig.stop_following()
					game_manager.post_alert("Câmera liberada.", Color(0.75, 0.9, 1.0))
				elif game_manager.selected_units.size() > 0 and is_instance_valid(game_manager.selected_units[0]):
					camera_rig.start_following(game_manager.selected_units[0])
					game_manager.post_alert("Seguindo unidade (mova a câmera ou pressione [F] para soltar).", Color(0.6, 0.92, 1.0)),
			"A câmera acompanha a unidade."
		)


func _enter_attack_move() -> void:
	game_manager.attack_move_mode = true
	game_manager.post_alert("Atacar-Mover: clique no destino desejado!", Color(1.0, 0.45, 0.35))


func _train(b: RTSBuilding, u_type: String) -> void:
	if not is_instance_valid(b):
		return
	if b.production_queue.size() >= 5:
		game_manager.post_alert("Fila cheia (máximo 5).", Color(1.0, 0.45, 0.35))
		if game_manager.sfx != null:
			game_manager.sfx.play_ui_error()
		return
	var cost: Dictionary = RTSUnit.get_cost(u_type)
	if not b.queue_unit(u_type):
		game_manager.post_alert("Recursos insuficientes! Falta: %s." % game_manager.missing_cost_text(0, cost), Color(1.0, 0.45, 0.35))
		if game_manager.sfx != null:
			game_manager.sfx.play_ui_error()
		return
	_refresh_selection_values_only()


func _build_market_card() -> void:
	var keys_buy: Array[int] = [KEY_Q, KEY_E, KEY_R]
	var keys_sell: Array[int] = [KEY_T, KEY_Y, KEY_U]
	var names_buy: Array[String] = ["Q", "E", "R"]
	var names_sell: Array[String] = ["T", "Y", "U"]
	var res_list: Array[String] = ["food", "wood", "stone"]
	for i in range(res_list.size()):
		var r: String = res_list[i]
		var cap_r: String = r
		var buy_cost: int = game_manager.get_market_buy_cost(r)
		_add_cmd_tile(
			"+100 %s" % String(GameManager.RES_NAMES[r]),
			keys_buy[i], names_buy[i],
			_get_icon("res_" + r), "market_buy",
			func() -> void:
				if not game_manager.market_buy(0, cap_r):
					game_manager.post_alert("Ouro insuficiente para comprar %s." % String(GameManager.RES_NAMES[cap_r]), Color(1.0, 0.45, 0.35))
					if game_manager.sfx != null:
						game_manager.sfx.play_ui_error()
				_rebuild_command_card(),
			"Compra 100 de %s por %d ouro. O preço sobe a cada compra." % [String(GameManager.RES_NAMES[r]), buy_cost],
			{"gold": buy_cost}
		)
	for i in range(res_list.size()):
		var r2: String = res_list[i]
		var cap_r2: String = r2
		var gain: int = game_manager.get_market_sell_gain(r2)
		_add_cmd_tile(
			"Vender (+%dO)" % gain,
			keys_sell[i], names_sell[i],
			_get_icon("res_" + r2), "market_sell",
			func() -> void:
				if not game_manager.market_sell(0, cap_r2):
					game_manager.post_alert("Você precisa de 100 de %s para vender." % String(GameManager.RES_NAMES[cap_r2]), Color(1.0, 0.45, 0.35))
					if game_manager.sfx != null:
						game_manager.sfx.play_ui_error()
				_rebuild_command_card(),
			"Vende 100 de %s e recebe %d ouro. O preço cai a cada venda." % [String(GameManager.RES_NAMES[r2]), gain],
			{r2: 100}
		)


func _add_cmd_tile(label_text: String, key_code: int, key_label: String, main_tex: Texture2D,
		badge_icon_key: String, callback: Callable, tooltip: String = "", cost: Dictionary = {}) -> Button:
	var btn: Button = Button.new()
	btn.custom_minimum_size = Vector2(95, 62)
	btn.tooltip_text = tooltip
	btn.focus_mode = Control.FOCUS_NONE
	_style_slot_button(btn, false)
	btn.pressed.connect(callback)

	var layer: Control = Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(layer)

	# Keycap no canto superior esquerdo
	if key_label != "":
		var kc: PanelContainer = PanelContainer.new()
		kc.position = Vector2(4, 4)
		kc.custom_minimum_size = Vector2(18, 17)
		kc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		kc.add_theme_stylebox_override("panel", _tex_box("keycap_bg", 5, 5, 5, 5, 2, 1, 2, 1))
		var kl: Label = _label(key_label, 9, Color(0.98, 0.85, 0.46), false, true)
		kl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		kl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		kl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		kc.add_child(kl)
		layer.add_child(kc)

	# Conteúdo principal: Ícone/Retrato 3D + Título + Custos com ícones
	var vb: VBoxContainer = VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 4
	vb.offset_top = 4
	vb.offset_right = -4
	vb.offset_bottom = -5
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 0)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(vb)

	var icon_sz: int = 23 if not cost.is_empty() else 28
	var tr: TextureRect = TextureRect.new()
	tr.texture = main_tex
	tr.custom_minimum_size = Vector2(icon_sz, icon_sz)
	tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(tr)

	if badge_icon_key != "":
		var bg_ic: TextureRect = _icon_rect(badge_icon_key, Vector2(14, 14))
		bg_ic.position = Vector2(77, 4)
		layer.add_child(bg_ic)

	var nl: Label = _label(label_text, 10, Color(0.95, 0.92, 0.84), false, true)
	nl.name = "TileLabel"
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.clip_text = true
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(nl)

	var cost_lbls: Dictionary = {}
	if not cost.is_empty():
		var chb: HBoxContainer = HBoxContainer.new()
		chb.alignment = BoxContainer.ALIGNMENT_CENTER
		chb.add_theme_constant_override("separation", 4)
		chb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(chb)
		for r in GameManager.RES_TYPES:
			if cost.has(r) and int(cost[r]) > 0:
				chb.add_child(_icon_rect("res_" + r, Vector2(11, 11)))
				var cl: Label = _label(str(int(cost[r])), 9, Color(0.92, 0.88, 0.76), false, true)
				cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
				chb.add_child(cl)
				cost_lbls[r] = cl

	_cmd_grid.add_child(btn)
	_cmd_actions.append({
		"key": key_code,
		"cb": callback,
		"btn": btn,
		"cost": cost,
		"cost_labels": cost_lbls,
		"disabled_styled": false,
	})
	return btn


func _refresh_command_affordability() -> void:
	if game_manager == null:
		return
	if _war_cry_tile_lbl != null and is_instance_valid(_war_cry_tile_lbl):
		_war_cry_tile_lbl.text = ("Invest. %ds" % ceili(game_manager.war_cry_cd)) if game_manager.war_cry_cd > 0.0 else "Investida"
	if _bell_tile_lbl != null and is_instance_valid(_bell_tile_lbl):
		_bell_tile_lbl.text = ("Sino %ds" % ceili(game_manager.defense_bell_cd)) if game_manager.defense_bell_cd > 0.0 else "Sino Defesa"
	if _hold_tile_lbl != null and is_instance_valid(_hold_tile_lbl):
		var any_hold: bool = false
		for u in game_manager.selected_units:
			if is_instance_valid(u) and not u._dead and u.team == 0 and u.unit_type != "worker" and u.hold_position:
				any_hold = true
				break
		_hold_tile_lbl.text = "Manter: ON" if any_hold else "Postura"
	for act in _cmd_actions:
		var btn: Button = act.get("btn", null)
		if btn == null or not is_instance_valid(btn):
			continue
		var cost: Dictionary = act.get("cost", {})
		if cost.is_empty():
			continue
		var can: bool = game_manager.can_afford_cost(0, cost)
		var was_dis: bool = bool(act.get("disabled_styled", false))
		if (not can) != was_dis:
			act["disabled_styled"] = not can
			_style_slot_button(btn, not can)
		btn.modulate = Color(1.0, 1.0, 1.0, 1.0) if can else Color(0.88, 0.72, 0.70, 0.90)
		var clbls: Dictionary = act.get("cost_labels", {})
		for r in clbls.keys():
			var cl: Label = clbls[r] as Label
			if is_instance_valid(cl):
				var enough: bool = game_manager.get_res(0, String(r)) >= int(cost.get(r, 0))
				cl.add_theme_color_override("font_color", Color(0.92, 0.88, 0.76) if enough else Color(1.0, 0.44, 0.38))
