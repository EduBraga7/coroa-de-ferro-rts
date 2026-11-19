extends StaticBody3D
class_name RTSResourceNode

## Nó de recurso coletável no mapa (Mina de Ouro ou Árvore de Madeira).

signal depleted(node: RTSResourceNode)

var resource_type: String = "gold"
var max_amount: int = 800
var amount_left: int = 800
var collision_radius: float = 2.0

var _visual_root: Node3D
var _selection_ring: MeshInstance3D
var _game_manager: Node = null
var _wobble_tween: Tween = null


func setup(r_type: String, amount: int = -1, gm: Node = null) -> void:
	resource_type = r_type
	_game_manager = gm

	if resource_type == "gold":
		max_amount = 900 if amount <= 0 else amount
		collision_radius = 2.15
	else:
		max_amount = 240 if amount <= 0 else amount
		collision_radius = 1.2

	amount_left = max_amount
	add_to_group("rts_resources")
	_build_visuals()
	_build_collision()


func _build_visuals() -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "VisualRoot"
	add_child(_visual_root)

	var model_path: String = "res://assets/models/resource_gold_mine.glb" if resource_type == "gold" else "res://assets/models/resource_tree.glb"
	var packed: PackedScene = load(model_path) as PackedScene
	if packed != null:
		var inst: Node3D = packed.instantiate() as Node3D
		if inst != null:
			_visual_root.add_child(inst)
	else:
		var fallback: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(2.2, 2.0, 2.2) if resource_type == "gold" else Vector3(1.2, 3.2, 1.2)
		fallback.mesh = box
		fallback.position.y = box.size.y * 0.5
		_visual_root.add_child(fallback)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	if resource_type == "gold":
		_visual_root.rotation.y = rng.randf_range(-0.55, 0.55)
	else:
		_visual_root.rotation.y = rng.randf_range(0.0, TAU)
	var sc: float = rng.randf_range(0.95, 1.15) if resource_type == "wood" else 1.05
	_visual_root.scale = Vector3.ONE * sc

	# Anel de seleção no solo
	_selection_ring = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = collision_radius * 0.9
	torus.outer_radius = collision_radius * 1.12
	torus.rings = 24
	torus.ring_segments = 6
	_selection_ring.mesh = torus
	_selection_ring.position.y = 0.08
	_selection_ring.scale = Vector3(1.0, 0.15, 1.0)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.84, 0.2, 0.95) if resource_type == "gold" else Color(0.3, 0.92, 0.35, 0.95)
	_selection_ring.material_override = mat
	_selection_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_selection_ring.visible = false
	add_child(_selection_ring)


func _build_collision() -> void:
	collision_layer = 1
	collision_mask = 0
	var col: CollisionShape3D = CollisionShape3D.new()
	var cyl: CylinderShape3D = CylinderShape3D.new()
	cyl.radius = collision_radius
	cyl.height = 3.8
	col.shape = cyl
	col.position.y = 1.9
	add_child(col)


func set_selected(selected: bool) -> void:
	if _selection_ring != null:
		_selection_ring.visible = selected


func get_display_name() -> String:
	return "Mina de Ouro" if resource_type == "gold" else "Árvore (Madeira)"


func harvest(amount: int) -> int:
	if amount_left <= 0 or is_queued_for_deletion():
		return 0
	var taken: int = mini(amount, amount_left)
	amount_left -= taken

	if _visual_root != null and is_inside_tree():
		if _wobble_tween != null and _wobble_tween.is_valid():
			_wobble_tween.kill()
		var base_scale: Vector3 = _visual_root.scale
		_wobble_tween = create_tween()
		_wobble_tween.tween_property(_visual_root, "scale", base_scale * Vector3(1.06, 0.93, 1.06), 0.07)
		_wobble_tween.tween_property(_visual_root, "scale", base_scale, 0.10)

	if amount_left <= 0:
		depleted.emit(self)
		if _game_manager != null and _game_manager.has_method("on_resource_depleted"):
			_game_manager.on_resource_depleted(self)
		queue_free()

	return taken
