extends Node3D
class_name RTSCamera

## Câmera tática RTS 3D avançada:
## - Curva dinâmica de pitch com o zoom (close-up cinematográfico vs visão estratégica)
## - Zoom direcionado ao cursor (Zoom-to-Cursor)
## - Pan suave com inércia (WASD/Setas + Shift turbo), Edge Pan ([P]) e Ground-Grab 1:1 (MMB)
## - Órbita 3D livre (Alt+MMB ou Z/C) e reset ao Norte ([Backspace])
## - Modo seguir unidade ([F]), favoritos (Ctrl+F2..F4 / F2..F4) e projeção de trapézio no minimapa

@export var pan_speed: float = 36.0
@export var zoom_speed: float = 4.8
@export var min_zoom: float = 10.0
@export var max_zoom: float = 68.0
@export var map_limit: float = 94.0
@export var rotate_speed: float = 2.0
@export var edge_pan_margin: float = 14.0

var camera: Camera3D
var audio_listener: AudioListener3D = null
var current_zoom: float = 34.0
var target_zoom: float = 34.0
var target_pos: Vector3 = Vector3(-52.0, 0.0, 52.0)
var target_yaw: float = 0.0
var current_pitch_offset_deg: float = 0.0
var target_pitch_offset_deg: float = 0.0

var edge_pan_enabled: bool = true
var block_edge_pan: bool = false

var _pan_velocity: Vector3 = Vector3.ZERO
var _is_mmb_dragging: bool = false
var _is_mmb_orbiting: bool = false
var _mmb_grab_world: Vector3 = Vector3.ZERO
var _last_mouse_pos: Vector2 = Vector2.ZERO
var _follow_target: Variant = null
var _bookmarks: Dictionary = {}
var _trauma: float = 0.0
var _shake_time: float = 0.0
var _window_focused: bool = true


func _ready() -> void:
	camera = get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		camera.far = 420.0
		camera.near = 0.5
		camera.fov = 48.0
		add_child(camera)

	audio_listener = AudioListener3D.new()
	audio_listener.name = "AudioListener3D"
	audio_listener.position = Vector3(0.0, 10.0, 6.0)
	add_child(audio_listener)
	audio_listener.make_current()

	global_position = target_pos
	rotation.y = target_yaw
	_apply_camera_transform()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_window_focused = true
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_window_focused = false
		_is_mmb_dragging = false


func focus_on(world_pos: Vector3, instant: bool = false) -> void:
	stop_following()
	target_pos = Vector3(
		clampf(world_pos.x, -map_limit, map_limit),
		0.0,
		clampf(world_pos.z, -map_limit, map_limit)
	)
	if instant:
		global_position = target_pos
		_pan_velocity = Vector3.ZERO


func set_zoom_instant(z: float) -> void:
	target_zoom = clampf(z, min_zoom, max_zoom)
	current_zoom = target_zoom
	_apply_camera_transform()


func reset_orientation() -> void:
	target_yaw = 0.0
	target_pitch_offset_deg = 0.0


func toggle_edge_pan() -> bool:
	edge_pan_enabled = not edge_pan_enabled
	return edge_pan_enabled


func start_following(node: Variant) -> void:
	if node != null and is_instance_valid(node) and not node.is_queued_for_deletion():
		_follow_target = node


func stop_following() -> void:
	_follow_target = null


func is_following() -> bool:
	return _follow_target != null and is_instance_valid(_follow_target) and not _follow_target.is_queued_for_deletion()


func save_bookmark(slot: int) -> void:
	_bookmarks[slot] = {
		"pos": target_pos,
		"zoom": target_zoom,
		"yaw": target_yaw,
		"pitch_off": target_pitch_offset_deg,
	}


func load_bookmark(slot: int) -> bool:
	if not _bookmarks.has(slot):
		return false
	stop_following()
	var data: Dictionary = _bookmarks[slot]
	target_pos = data["pos"]
	target_zoom = float(data["zoom"])
	target_yaw = float(data["yaw"])
	target_pitch_offset_deg = float(data["pitch_off"])
	return true


func add_trauma(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)


func get_view_rect_world() -> Rect2:
	var poly: PackedVector2Array = get_view_polygon_world()
	if poly.size() < 4:
		var half_w: float = current_zoom * 0.72
		var half_h: float = current_zoom * 0.48
		return Rect2(global_position.x - half_w, global_position.z - half_h, half_w * 2.0, half_h * 2.0)
	var min_x: float = poly[0].x
	var max_x: float = poly[0].x
	var min_z: float = poly[0].y
	var max_z: float = poly[0].y
	for pt in poly:
		min_x = minf(min_x, pt.x)
		max_x = maxf(max_x, pt.x)
		min_z = minf(min_z, pt.y)
		max_z = maxf(max_z, pt.y)
	return Rect2(min_x, min_z, max_x - min_x, max_z - min_z)


func get_view_polygon_world() -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	if camera == null or get_viewport() == null:
		return pts
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	if vp_size.x < 10.0 or vp_size.y < 10.0:
		return pts

	var corners: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(vp_size.x, 0.0),
		Vector2(vp_size.x, vp_size.y),
		Vector2(0.0, vp_size.y),
	]
	for sp in corners:
		var origin: Vector3 = camera.project_ray_origin(sp)
		var dir: Vector3 = camera.project_ray_normal(sp)
		if dir.y > -0.10:
			dir.y = -0.10
			dir = dir.normalized()
		var t: float = -origin.y / dir.y
		t = clampf(t, 1.0, 140.0)
		var hit: Vector3 = origin + dir * t
		pts.append(Vector2(clampf(hit.x, -GameManager.MAP_HALF, GameManager.MAP_HALF), clampf(hit.z, -GameManager.MAP_HALF, GameManager.MAP_HALF)))
	return pts


func _raycast_ground_plane(screen_pos: Vector2) -> Variant:
	if camera == null:
		return null
	var origin: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)
	if dir.y > -0.05:
		return null
	var t: float = -origin.y / dir.y
	if t < 0.0 or t > 400.0:
		return null
	return origin + dir * t


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			var prev_z: float = target_zoom
			target_zoom = clampf(target_zoom - zoom_speed, min_zoom, max_zoom)
			if target_zoom < prev_z and not is_following():
				var hit: Variant = _raycast_ground_plane(mb.position)
				if hit != null:
					var h_pos: Vector3 = hit as Vector3
					var factor: float = clampf((prev_z - target_zoom) / maxf(1.0, prev_z), 0.0, 0.25) * 0.72
					target_pos = target_pos.lerp(Vector3(h_pos.x, 0.0, h_pos.z), factor)
					target_pos.x = clampf(target_pos.x, -map_limit, map_limit)
					target_pos.z = clampf(target_pos.z, -map_limit, map_limit)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			target_zoom = clampf(target_zoom + zoom_speed, min_zoom, max_zoom)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_is_mmb_dragging = mb.pressed
			_last_mouse_pos = mb.position
			_is_mmb_orbiting = Input.is_key_pressed(KEY_ALT) or Input.is_key_pressed(KEY_SHIFT)
			if _is_mmb_dragging and not _is_mmb_orbiting:
				stop_following()
				var grab_hit: Variant = _raycast_ground_plane(mb.position)
				if grab_hit != null:
					_mmb_grab_world = grab_hit as Vector3
				else:
					_mmb_grab_world = global_position

	elif event is InputEventMouseMotion and _is_mmb_dragging:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		var delta_px: Vector2 = mm.position - _last_mouse_pos
		_last_mouse_pos = mm.position
		if _is_mmb_orbiting or Input.is_key_pressed(KEY_ALT):
			target_yaw -= delta_px.x * 0.0065
			target_pitch_offset_deg = clampf(target_pitch_offset_deg + delta_px.y * 0.14, -12.0, 12.0)
		else:
			var curr_hit: Variant = _raycast_ground_plane(mm.position)
			if curr_hit != null:
				var c_pos: Vector3 = curr_hit as Vector3
				var diff: Vector3 = _mmb_grab_world - c_pos
				diff.y = 0.0
				target_pos.x = clampf(global_position.x + diff.x, -map_limit, map_limit)
				target_pos.z = clampf(global_position.z + diff.z, -map_limit, map_limit)
				global_position = target_pos
				_pan_velocity = Vector3.ZERO
				_apply_camera_transform()


func _process(delta: float) -> void:
	# Seguir unidade selecionada caso ativo
	if is_following():
		var f_pos: Vector3 = (_follow_target as Node3D).global_position
		target_pos = Vector3(clampf(f_pos.x, -map_limit, map_limit), 0.0, clampf(f_pos.z, -map_limit, map_limit))

	var move_input: Vector2 = Vector2.ZERO
	if not Input.is_key_pressed(KEY_CTRL):
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			move_input.y -= 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			move_input.y += 1.0
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			move_input.x -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			move_input.x += 1.0

	# Edge Panning inteligente nas bordas da tela
	if edge_pan_enabled and not block_edge_pan and not _is_mmb_dragging and _window_focused and DisplayServer.get_name() != "headless":
		var vp: Viewport = get_viewport()
		if vp != null:
			var vp_rect: Rect2 = vp.get_visible_rect()
			var mp: Vector2 = vp.get_mouse_position()
			if vp_rect.has_point(mp):
				if mp.x <= edge_pan_margin:
					move_input.x -= 1.0
				elif mp.x >= vp_rect.size.x - edge_pan_margin:
					move_input.x += 1.0
				if mp.y <= edge_pan_margin:
					move_input.y -= 1.0
				elif mp.y >= vp_rect.size.y - edge_pan_margin:
					move_input.y += 1.0

	if Input.is_key_pressed(KEY_Z):
		target_yaw += rotate_speed * delta
	if Input.is_key_pressed(KEY_C):
		target_yaw -= rotate_speed * delta

	var right_vec: Vector3 = global_transform.basis.x
	var back_vec: Vector3 = global_transform.basis.z
	right_vec.y = 0.0
	back_vec.y = 0.0
	right_vec = right_vec.normalized()
	back_vec = back_vec.normalized()

	var spd: float = pan_speed * (0.52 + (current_zoom / max_zoom) * 0.85)
	if Input.is_key_pressed(KEY_SHIFT):
		spd *= 1.65

	if move_input.length_squared() > 0.01:
		stop_following()
		move_input = move_input.normalized()
		var desired_vel: Vector3 = (right_vec * move_input.x + back_vec * move_input.y) * spd
		_pan_velocity = _pan_velocity.lerp(desired_vel, minf(1.0, 14.0 * delta))
	else:
		_pan_velocity = _pan_velocity.lerp(Vector3.ZERO, minf(1.0, 16.0 * delta))

	if _pan_velocity.length_squared() > 0.005:
		target_pos += _pan_velocity * delta
		target_pos.x = clampf(target_pos.x, -map_limit, map_limit)
		target_pos.z = clampf(target_pos.z, -map_limit, map_limit)

	if _trauma > 0.0:
		_trauma = maxf(0.0, _trauma - delta * 2.2)
		_shake_time += delta * 42.0

	global_position = global_position.lerp(target_pos, minf(1.0, 14.0 * delta))
	rotation.y = lerp_angle(rotation.y, target_yaw, minf(1.0, 12.0 * delta))
	current_zoom = lerpf(current_zoom, target_zoom, minf(1.0, 13.0 * delta))
	current_pitch_offset_deg = lerpf(current_pitch_offset_deg, target_pitch_offset_deg, minf(1.0, 12.0 * delta))
	_apply_camera_transform()


func _apply_camera_transform() -> void:
	if camera == null:
		return
	var zoom_t: float = clampf((current_zoom - min_zoom) / maxf(1.0, max_zoom - min_zoom), 0.0, 1.0)
	var base_pitch_deg: float = lerpf(32.0, 58.0, pow(zoom_t, 0.85))
	var pitch_rad: float = deg_to_rad(clampf(base_pitch_deg + current_pitch_offset_deg, 24.0, 72.0))

	var horiz_dist: float = current_zoom * cos(pitch_rad)
	var vert_dist: float = current_zoom * sin(pitch_rad)

	var shake_vec: Vector3 = Vector3.ZERO
	if _trauma > 0.001:
		var s: float = _trauma * _trauma * 0.45
		shake_vec = Vector3(sin(_shake_time) * s, cos(_shake_time * 1.3) * s * 0.5, sin(_shake_time * 0.9) * s)

	camera.position = Vector3(0.0, vert_dist, horiz_dist) + shake_vec
	camera.look_at(global_position + shake_vec * 0.4, Vector3.UP)
