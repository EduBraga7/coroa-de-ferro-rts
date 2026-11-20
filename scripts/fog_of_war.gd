extends Node
class_name FogOfWar

## Névoa de guerra do jogador (time 0):
## - preto = nunca explorado, escurecido = explorado mas fora de visão, claro = visível agora.
## - unidades inimigas só aparecem quando visíveis; prédios inimigos ficam marcados após descobertos.
## A grade é carimbada com Image.fill_rect (nativo) e enviada à GPU como texturas L8; o shader
## faz a transição suave entre a atualização anterior e a atual.

signal enemy_base_discovered(building: RTSBuilding)

const GRID: int = 100
const UPDATE_INTERVAL: float = 0.2

var game_manager: GameManager = null
var enabled: bool = true
var map_half: float = 100.0
var cell_size: float = 2.0

var vis_tex: ImageTexture
var vis_prev_tex: ImageTexture
var exp_tex: ImageTexture
var exp_prev_tex: ImageTexture
var blend: float = 1.0

var _vis_img: Image
var _vis_prev_img: Image
var _exp_img: Image
var _exp_prev_img: Image
var _vis_data: PackedByteArray = PackedByteArray()
var _exp_data: PackedByteArray = PackedByteArray()
var _timer: float = 0.0
var _materials: Array[ShaderMaterial] = []
var _enemy_seen: bool = false


func setup(gm: GameManager, p_map_half: float) -> void:
	game_manager = gm
	map_half = p_map_half
	cell_size = (map_half * 2.0) / float(GRID)
	_vis_img = Image.create(GRID, GRID, false, Image.FORMAT_L8)
	_vis_prev_img = Image.create(GRID, GRID, false, Image.FORMAT_L8)
	_exp_img = Image.create(GRID, GRID, false, Image.FORMAT_L8)
	_exp_prev_img = Image.create(GRID, GRID, false, Image.FORMAT_L8)
	for img in [_vis_img, _vis_prev_img, _exp_img, _exp_prev_img]:
		(img as Image).fill(Color(0, 0, 0))
	vis_tex = ImageTexture.create_from_image(_vis_img)
	vis_prev_tex = ImageTexture.create_from_image(_vis_prev_img)
	exp_tex = ImageTexture.create_from_image(_exp_img)
	exp_prev_tex = ImageTexture.create_from_image(_exp_prev_img)
	_vis_data = _vis_img.get_data()
	_exp_data = _exp_img.get_data()


func register_material(mat: ShaderMaterial) -> void:
	if mat == null:
		return
	_materials.append(mat)
	mat.set_shader_parameter("vis_tex", vis_tex)
	mat.set_shader_parameter("vis_prev_tex", vis_prev_tex)
	mat.set_shader_parameter("exp_tex", exp_tex)
	mat.set_shader_parameter("exp_prev_tex", exp_prev_tex)
	mat.set_shader_parameter("map_half", map_half)
	mat.set_shader_parameter("fog_enabled", 1.0 if enabled else 0.0)
	mat.set_shader_parameter("blend", blend)


func set_enabled(on: bool) -> void:
	enabled = on
	for m in _materials:
		m.set_shader_parameter("fog_enabled", 1.0 if enabled else 0.0)
	update_now()


func _process(delta: float) -> void:
	if game_manager == null:
		return
	if blend < 1.0:
		blend = minf(1.0, blend + delta / UPDATE_INTERVAL)
		for m in _materials:
			m.set_shader_parameter("blend", blend)
	_timer -= delta
	if _timer <= 0.0:
		_timer = UPDATE_INTERVAL
		update_now()


func world_to_cell(p: Vector3) -> Vector2i:
	var cx: int = clampi(int(floor((p.x + map_half) / cell_size)), 0, GRID - 1)
	var cz: int = clampi(int(floor((p.z + map_half) / cell_size)), 0, GRID - 1)
	return Vector2i(cx, cz)


func is_visible_at(p: Vector3) -> bool:
	if not enabled:
		return true
	var c: Vector2i = world_to_cell(p)
	return _vis_data[c.y * GRID + c.x] > 127


func is_explored_at(p: Vector3) -> bool:
	if not enabled:
		return true
	var c: Vector2i = world_to_cell(p)
	return _exp_data[c.y * GRID + c.x] > 127


func is_enemy_discovered() -> bool:
	return _enemy_seen


func _stamp_circle(center: Vector3, radius: float) -> void:
	var c: Vector2i = world_to_cell(center)
	var r: int = maxi(1, int(round(radius / cell_size)))
	for dy in range(-r, r + 1):
		var row: int = c.y + dy
		if row < 0 or row >= GRID:
			continue
		var w: int = int(floor(sqrt(float(r * r - dy * dy))))
		var x0: int = maxi(0, c.x - w)
		var x1: int = mini(GRID - 1, c.x + w)
		var rect: Rect2i = Rect2i(x0, row, x1 - x0 + 1, 1)
		_vis_img.fill_rect(rect, Color(1, 1, 1))
		_exp_img.fill_rect(rect, Color(1, 1, 1))
		# Suavizado visual de 1 célula fora do círculo (< 127, não altera is_visible_at/is_explored_at)
		var fringe: Color = Color(0.42, 0.42, 0.42)
		if x0 - 1 >= 0:
			if _vis_img.get_pixel(x0 - 1, row).r < 0.42:
				_vis_img.set_pixel(x0 - 1, row, fringe)
			if _exp_img.get_pixel(x0 - 1, row).r < 0.42:
				_exp_img.set_pixel(x0 - 1, row, fringe)
		if x1 + 1 < GRID:
			if _vis_img.get_pixel(x1 + 1, row).r < 0.42:
				_vis_img.set_pixel(x1 + 1, row, fringe)
			if _exp_img.get_pixel(x1 + 1, row).r < 0.42:
				_exp_img.set_pixel(x1 + 1, row, fringe)


func reveal_all_explored() -> void:
	_exp_img.fill(Color(1, 1, 1))
	_exp_data = _exp_img.get_data()


func update_now() -> void:
	if game_manager == null or _vis_img == null:
		return
	_vis_prev_img.copy_from(_vis_img)
	_exp_prev_img.copy_from(_exp_img)

	if enabled:
		_vis_img.fill(Color(0, 0, 0))
		for u in game_manager.units:
			if is_instance_valid(u) and not u._dead and u.team == 0:
				_stamp_circle(u.global_position, u.sight_range)
		for b in game_manager.buildings:
			if is_instance_valid(b) and not b._dead and b.team == 0:
				_stamp_circle(b.global_position, b.sight_range if b.is_constructed else b.sight_range * 0.6)
	else:
		_vis_img.fill(Color(1, 1, 1))
		_exp_img.fill(Color(1, 1, 1))

	_vis_data = _vis_img.get_data()
	_exp_data = _exp_img.get_data()
	vis_prev_tex.update(_vis_prev_img)
	exp_prev_tex.update(_exp_prev_img)
	vis_tex.update(_vis_img)
	exp_tex.update(_exp_img)
	blend = 0.0
	for m in _materials:
		m.set_shader_parameter("blend", blend)

	_refresh_enemy_visibility()


func _refresh_enemy_visibility() -> void:
	var deselected: bool = false
	for u in game_manager.units:
		if not is_instance_valid(u) or u._dead or u.team == 0:
			continue
		var hide: bool = not is_visible_at(u.global_position)
		u.set_fog_hidden(hide)
		if hide and u in game_manager.selected_units:
			u.set_selected(false)
			game_manager.selected_units.erase(u)
			deselected = true
	if deselected:
		game_manager.selection_changed.emit()
	for b in game_manager.buildings:
		if not is_instance_valid(b) or b._dead or b.team == 0:
			continue
		if not b.discovered and _is_building_seen(b):
			b.discovered = true
			if not _enemy_seen:
				_enemy_seen = true
				enemy_base_discovered.emit(b)
		b.set_fog_hidden(not b.discovered)
	for c in game_manager.caches:
		if not is_instance_valid(c) or bool(c.claimed):
			continue
		if not bool(c.discovered) and (not enabled or is_visible_at(c.global_position)):
			c.discovered = true
			if game_manager.match_started and not game_manager.ai_controllers.has(0):
				game_manager.post_alert("Ponto de interesse avistado: %s!" % c.get_display_name(), Color(1.0, 0.86, 0.38))
				game_manager.add_ping(c.global_position, Color(1.0, 0.86, 0.32), false)
		c.set_fog_hidden(not bool(c.discovered))
	if not enabled:
		_enemy_seen = true


func _is_building_seen(b: RTSBuilding) -> bool:
	if not enabled:
		return true
	if is_visible_at(b.global_position):
		return true
	var r: float = b.footprint_radius * 0.8
	for off in [Vector3(r, 0.0, 0.0), Vector3(-r, 0.0, 0.0), Vector3(0.0, 0.0, r), Vector3(0.0, 0.0, -r)]:
		if is_visible_at(b.global_position + off):
			return true
	return false
