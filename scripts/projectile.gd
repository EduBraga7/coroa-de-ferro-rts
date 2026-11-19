extends Node3D
class_name RTSProjectile

## Flecha 3D com trajetória parabólica disparada por Arqueiros e Torres.

var _start_pos: Vector3 = Vector3.ZERO
var _target: Variant = null
var _target_last_pos: Vector3 = Vector3.ZERO
var _damage: float = 10.0
var _attacker: Variant = null
var _team: int = 0
var _speed: float = 26.0
var _arc_height: float = 2.0
var _progress: float = 0.0
var _duration: float = 0.5
var _active: bool = false


func launch(from_pos: Vector3, target_node: Variant, dmg: float, src: Variant, src_team: int) -> void:
	_start_pos = from_pos
	_target = target_node
	_damage = dmg
	_attacker = src
	_team = src_team
	global_position = from_pos

	if _target != null and is_instance_valid(_target) and not _target.is_queued_for_deletion():
		_target_last_pos = _target.global_position + Vector3(0.0, 1.1, 0.0)
	else:
		_target_last_pos = from_pos + Vector3(0.0, 0.0, -5.0)

	var dist: float = _start_pos.distance_to(_target_last_pos)
	_duration = maxf(0.14, dist / _speed)
	_arc_height = clampf(dist * 0.13, 0.6, 3.6)
	_progress = 0.0
	_active = true
	_build_arrow_mesh()


func _build_arrow_mesh() -> void:
	var shaft: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.03
	cyl.bottom_radius = 0.03
	cyl.height = 0.95
	shaft.mesh = cyl
	shaft.rotation.x = PI * 0.5
	var mat_wood: StandardMaterial3D = StandardMaterial3D.new()
	mat_wood.albedo_color = Color(0.55, 0.34, 0.16)
	shaft.material_override = mat_wood
	add_child(shaft)

	var tip: MeshInstance3D = MeshInstance3D.new()
	var cone: PrismMesh = PrismMesh.new()
	cone.size = Vector3(0.12, 0.22, 0.12)
	tip.mesh = cone
	tip.position = Vector3(0.0, 0.0, -0.52)
	tip.rotation.x = -PI * 0.5
	var mat_steel: StandardMaterial3D = StandardMaterial3D.new()
	mat_steel.albedo_color = Color(0.85, 0.88, 0.92)
	mat_steel.metallic = 0.85
	tip.material_override = mat_steel
	add_child(tip)

	var fletch: MeshInstance3D = MeshInstance3D.new()
	var fbox: BoxMesh = BoxMesh.new()
	fbox.size = Vector3(0.14, 0.14, 0.22)
	fletch.mesh = fbox
	fletch.position = Vector3(0.0, 0.0, 0.42)
	var mat_team: StandardMaterial3D = StandardMaterial3D.new()
	mat_team.albedo_color = Color(0.25, 0.65, 1.0) if _team == 0 else Color(0.95, 0.28, 0.25)
	mat_team.emission_enabled = true
	mat_team.emission = mat_team.albedo_color * 0.5
	fletch.material_override = mat_team
	add_child(fletch)


func _process(delta: float) -> void:
	if not _active:
		return

	if _target != null and is_instance_valid(_target) and not _target.is_queued_for_deletion():
		_target_last_pos = _target.global_position + Vector3(0.0, 1.1, 0.0)

	_progress += delta / _duration
	var t: float = clampf(_progress, 0.0, 1.0)
	var prev_pos: Vector3 = global_position

	var linear_pos: Vector3 = _start_pos.lerp(_target_last_pos, t)
	var arc_offset: float = 4.0 * _arc_height * t * (1.0 - t)
	var next_pos: Vector3 = linear_pos + Vector3(0.0, arc_offset, 0.0)
	global_position = next_pos

	var dir: Vector3 = next_pos - prev_pos
	if dir.length_squared() > 0.0001:
		look_at(next_pos + dir.normalized(), Vector3.UP)

	if _progress >= 1.0:
		_active = false
		if _target != null and is_instance_valid(_target) and not _target.is_queued_for_deletion() and _target.has_method("take_damage"):
			var att: Variant = _attacker if (_attacker != null and is_instance_valid(_attacker) and not _attacker.is_queued_for_deletion()) else null
			_target.take_damage(_damage, att)
		queue_free()
