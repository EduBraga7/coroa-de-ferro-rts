extends StaticBody3D
class_name RTSResourceNode

## Nó de recurso coletável: Mina de Ouro, Árvore, Pedreira, Frutos Silvestres ou Fazenda (campo cultivado).

signal depleted(node: RTSResourceNode)

const KINDS: Dictionary = {
	"gold_mine": {
		"type": "gold", "amount": 1500, "radius": 2.15, "rate": 0.72,
		"model": "res://assets/models/resource_gold_mine.glb", "name": "Mina de Ouro",
	},
	"tree": {
		"type": "wood", "amount": 150, "radius": 1.2, "rate": 0.85,
		"model": "res://assets/models/resource_tree.glb", "name": "Árvore",
	},
	"stone_quarry": {
		"type": "stone", "amount": 1000, "radius": 2.0, "rate": 0.66,
		"model": "res://assets/models/resource_stone_quarry.glb", "name": "Pedreira",
	},
	"berry_bush": {
		"type": "food", "amount": 125, "radius": 0.95, "rate": 1.0,
		"model": "res://assets/models/resource_berry_bush.glb", "name": "Frutos Silvestres",
	},
	"farm": {
		"type": "food", "amount": 450, "radius": 2.9, "rate": 0.72, "walkable": true,
		"model": "res://assets/models/building_farm.glb", "name": "Fazenda",
	},
}

var kind: String = "gold_mine"
var resource_type: String = "gold"
var max_amount: int = 800
var amount_left: int = 800
var collision_radius: float = 2.0
var gather_rate: float = 0.75
var owner_team: int = -1
var walkable: bool = false

var _visual_root: Node3D
var _selection_ring: MeshInstance3D
var _game_manager: Node = null
var _wobble_tween: Tween = null
var _base_scale: Vector3 = Vector3.ONE


## kind_or_type aceita um tipo de nó (gold_mine, tree...) ou um recurso legado (gold, wood, stone, food).
func setup(kind_or_type: String, amount: int = -1, gm: Node = null, p_owner_team: int = -1) -> void:
	kind = _normalize_kind(kind_or_type)
	_game_manager = gm
	owner_team = p_owner_team
	var cfg: Dictionary = KINDS[kind]
	resource_type = String(cfg["type"])
	max_amount = int(cfg["amount"]) if amount <= 0 else amount
	collision_radius = float(cfg["radius"])
	gather_rate = float(cfg["rate"])
	walkable = bool(cfg.get("walkable", false))
	amount_left = max_amount
	add_to_group("rts_resources")
	_build_visuals(cfg)
	_build_collision()


static func _normalize_kind(k: String) -> String:
	match k:
		"gold":
			return "gold_mine"
		"wood":
			return "tree"
		"stone":
			return "stone_quarry"
		"food", "berries":
			return "berry_bush"
	return k if KINDS.has(k) else "gold_mine"


func _build_visuals(cfg: Dictionary) -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "VisualRoot"
	add_child(_visual_root)

	var model_path: String = String(cfg["model"])
	var model_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	model_rng.seed = hash(Vector2i(roundi(position.x * 13.0), roundi(position.z * 17.0)))
	if kind == "tree":
		var roll: float = model_rng.randf()
		if roll < 0.30:
			model_path = "res://assets/models/resource_tree_pine.glb"
		elif roll < 0.45:
			model_path = "res://assets/models/resource_tree_birch.glb"

	var packed: PackedScene = load(model_path) as PackedScene
	if packed != null:
		var inst: Node3D = packed.instantiate() as Node3D
		if inst != null:
			if kind == "tree":
				WorldLook.apply_tree_wind(inst)  # copa balançando ao vento + tom variado por árvore
			_visual_root.add_child(inst)
	else:
		var fallback: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(collision_radius * 1.6, 1.6, collision_radius * 1.6)
		fallback.mesh = box
		fallback.position.y = 0.8
		_visual_root.add_child(fallback)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(roundi(position.x * 10.0), roundi(position.z * 10.0)))
	match kind:
		"tree", "berry_bush":
			_visual_root.rotation.y = rng.randf_range(0.0, TAU)
			_visual_root.scale = Vector3.ONE * rng.randf_range(0.88, 1.20)
		"farm":
			_visual_root.rotation.y = 0.0
		_:
			_visual_root.rotation.y = rng.randf_range(-0.55, 0.55)
			_visual_root.scale = Vector3.ONE * 1.05
	_base_scale = _visual_root.scale

	if walkable:
		_set_cast_shadow_recursive(_visual_root, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	else:
		var ao_rad: float = collision_radius * (1.75 if kind == "tree" else 1.48)
		add_child(VFXManager.create_contact_ao_disc(ao_rad, 0.40 if kind == "tree" else 0.44))
	if owner_team >= 0:
		_add_owner_marker()

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
	mat.albedo_color = GameManager.RES_COLORS.get(resource_type, Color.WHITE)
	_selection_ring.material_override = mat
	_selection_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_selection_ring.visible = false
	add_child(_selection_ring)


func _add_owner_marker() -> void:
	# Pequena bandeira do dono no canto da fazenda
	var team_col: Color = RTSUnit.team_color(owner_team)
	var flag: MeshInstance3D = MeshInstance3D.new()
	var fbox: BoxMesh = BoxMesh.new()
	fbox.size = Vector3(0.05, 0.42, 0.7)
	flag.mesh = fbox
	flag.position = Vector3(2.75, 1.55, 2.75 + 0.35)
	var fmat: StandardMaterial3D = StandardMaterial3D.new()
	fmat.albedo_color = team_col
	fmat.emission_enabled = true
	fmat.emission = team_col * 0.25
	flag.material_override = fmat
	_visual_root.add_child(flag)
	var pole: MeshInstance3D = MeshInstance3D.new()
	var pcyl: CylinderMesh = CylinderMesh.new()
	pcyl.top_radius = 0.035
	pcyl.bottom_radius = 0.045
	pcyl.height = 1.9
	pole.mesh = pcyl
	pole.position = Vector3(2.75, 0.95, 2.75)
	var pmat: StandardMaterial3D = StandardMaterial3D.new()
	pmat.albedo_color = Color(0.40, 0.26, 0.14)
	pole.material_override = pmat
	_visual_root.add_child(pole)


func _set_cast_shadow_recursive(node: Node, mode: GeometryInstance3D.ShadowCastingSetting) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = mode
	for child in node.get_children():
		_set_cast_shadow_recursive(child, mode)


func _build_collision() -> void:
	collision_layer = 1
	collision_mask = 0
	var col: CollisionShape3D = CollisionShape3D.new()
	var cyl: CylinderShape3D = CylinderShape3D.new()
	cyl.radius = collision_radius
	cyl.height = 0.8 if walkable else 3.8
	col.shape = cyl
	col.position.y = cyl.height * 0.5
	add_child(col)


func can_be_gathered_by(team: int) -> bool:
	return owner_team < 0 or owner_team == team


## Distância (do centro) até onde o camponês precisa chegar para coletar.
func gather_reach() -> float:
	if walkable:
		return collision_radius * 0.55
	return collision_radius + 1.0


func set_selected(selected: bool) -> void:
	if _selection_ring != null:
		_selection_ring.visible = selected


func get_display_name() -> String:
	return String(KINDS[kind]["name"])


func harvest(amount: int) -> int:
	if amount_left <= 0 or is_queued_for_deletion():
		return 0
	var taken: int = mini(amount, amount_left)
	amount_left -= taken

	if _visual_root != null and is_inside_tree() and not walkable:
		if _wobble_tween != null and _wobble_tween.is_valid():
			_wobble_tween.kill()
		_visual_root.scale = _base_scale
		_wobble_tween = create_tween()
		_wobble_tween.tween_property(_visual_root, "scale", _base_scale * Vector3(1.04, 0.95, 1.04), 0.07)
		_wobble_tween.tween_property(_visual_root, "scale", _base_scale, 0.10)

	if amount_left <= 0:
		depleted.emit(self)
		if _game_manager != null and _game_manager.has_method("on_resource_depleted"):
			_game_manager.on_resource_depleted(self)
		queue_free()

	return taken
