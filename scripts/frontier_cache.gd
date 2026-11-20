extends StaticBody3D
class_name FrontierCache

## Ponto de interesse vivo na fronteira (medieval realista):
## Caravanas de Suprimentos, Baús do Tesouro, Arsenais Abandonados e Estandartes da Fronteira.
## Ocultos na névoa até serem explorados; qualquer unidade aliada próxima coleta automaticamente.

const CACHE_RES_ORDER: Array[String] = ["food", "wood", "gold", "stone"]
const CACHE_RES_NAMES: Dictionary = {"food": "Comida", "wood": "Madeira", "gold": "Ouro", "stone": "Pedra"}

const CACHE_TYPES: Dictionary = {
	"supplies": {
		"name": "Caravana de Suprimentos",
		"desc": "Caixotes intactos com provisões (+140 Comida, +110 Madeira).",
		"grant": {"food": 140, "wood": 110},
		"color": Color(0.95, 0.72, 0.28),
		"banner_color": Color(0.76, 0.44, 0.16),
	},
	"treasury": {
		"name": "Baú do Tesouro Real",
		"desc": "Arca selada com moedas e cantaria (+160 Ouro, +90 Pedra).",
		"grant": {"gold": 160, "stone": 90},
		"color": Color(1.0, 0.86, 0.24),
		"banner_color": Color(0.88, 0.68, 0.18),
	},
	"armory": {
		"name": "Arsenal Abandonado",
		"desc": "Armas reais e sobreviventes leais (+80 Madeira, +80 Ouro e 2 tropas).",
		"grant": {"wood": 80, "gold": 80},
		"units": ["soldier", "archer"],
		"color": Color(0.45, 0.82, 1.0),
		"banner_color": Color(0.20, 0.52, 0.92),
	},
	"banner": {
		"name": "Estandarte da Fronteira",
		"desc": "Relíquia dos antigos senhores (+110 Ouro e 1 Decreto Real imediato).",
		"grant": {"gold": 110},
		"decree": true,
		"color": Color(1.0, 0.76, 0.26),
		"banner_color": Color(0.92, 0.64, 0.14),
	},
}

var cache_kind: String = "supplies"
var discovered: bool = false
var fog_hidden: bool = true
var claimed: bool = false

var _game_manager: Node = null
var _visual_root: Node3D = null
var _float_marker: MeshInstance3D = null
var _beacon_ring: MeshInstance3D = null
var _check_timer: float = 0.0
var _pulse_phase: float = 0.0


func setup(kind: String, gm: Node) -> void:
	cache_kind = kind if CACHE_TYPES.has(kind) else "supplies"
	_game_manager = gm
	_pulse_phase = randf() * TAU
	add_to_group("frontier_caches")
	_build_visuals()
	_build_collision()
	set_fog_hidden(true)


func get_display_name() -> String:
	return String(CACHE_TYPES.get(cache_kind, CACHE_TYPES["supplies"])["name"])


func _build_visuals() -> void:
	var cfg: Dictionary = CACHE_TYPES.get(cache_kind, CACHE_TYPES["supplies"])
	var accent: Color = cfg["color"]
	var cloth_col: Color = cfg["banner_color"]

	_visual_root = Node3D.new()
	_visual_root.name = "VisualRoot"
	add_child(_visual_root)

	add_child(VFXManager.create_contact_ao_disc(1.45, 0.42))

	var mat_wood: StandardMaterial3D = StandardMaterial3D.new()
	mat_wood.albedo_color = Color(0.38, 0.23, 0.12)
	mat_wood.roughness = 0.78

	var mat_iron: StandardMaterial3D = StandardMaterial3D.new()
	mat_iron.albedo_color = Color(0.32, 0.34, 0.38)
	mat_iron.metallic = 0.78
	mat_iron.roughness = 0.42

	var mat_gold: StandardMaterial3D = StandardMaterial3D.new()
	mat_gold.albedo_color = accent
	mat_gold.metallic = 0.85
	mat_gold.roughness = 0.28
	mat_gold.emission_enabled = true
	mat_gold.emission = accent * 0.45

	# Baú / arca central reforçada
	var chest: MeshInstance3D = MeshInstance3D.new()
	var cbox: BoxMesh = BoxMesh.new()
	cbox.size = Vector3(1.05, 0.64, 0.72)
	chest.mesh = cbox
	chest.position = Vector3(0.0, 0.32, 0.0)
	chest.material_override = mat_wood
	_visual_root.add_child(chest)

	# Tampa arredondada com aros metálicos
	var lid: MeshInstance3D = MeshInstance3D.new()
	var lcyl: CylinderMesh = CylinderMesh.new()
	lcyl.top_radius = 0.35
	lcyl.bottom_radius = 0.35
	lcyl.height = 1.06
	lcyl.radial_segments = 10
	lid.mesh = lcyl
	lid.position = Vector3(0.0, 0.64, 0.0)
	lid.rotation.z = PI * 0.5
	lid.material_override = mat_wood
	_visual_root.add_child(lid)

	for sx in [-0.36, 0.36]:
		var strap: MeshInstance3D = MeshInstance3D.new()
		var sbox: BoxMesh = BoxMesh.new()
		sbox.size = Vector3(0.08, 0.72, 0.76)
		strap.mesh = sbox
		strap.position = Vector3(sx, 0.38, 0.0)
		strap.material_override = mat_iron
		_visual_root.add_child(strap)

	# Fecho dourado frontal
	var clasp: MeshInstance3D = MeshInstance3D.new()
	var clbox: BoxMesh = BoxMesh.new()
	clbox.size = Vector3(0.18, 0.22, 0.08)
	clasp.mesh = clbox
	clasp.position = Vector3(0.0, 0.54, 0.37)
	clasp.material_override = mat_gold
	_visual_root.add_child(clasp)

	# Caixotes / barris laterais para compor a silhueta de caravana
	var crate: MeshInstance3D = MeshInstance3D.new()
	var crbox: BoxMesh = BoxMesh.new()
	crbox.size = Vector3(0.56, 0.52, 0.56)
	crate.mesh = crbox
	crate.position = Vector3(-0.78, 0.26, 0.36)
	crate.rotation.y = 0.38
	crate.material_override = mat_wood
	_visual_root.add_child(crate)

	# Mastro e flâmula colorida
	var pole: MeshInstance3D = MeshInstance3D.new()
	var pcyl: CylinderMesh = CylinderMesh.new()
	pcyl.top_radius = 0.04
	pcyl.bottom_radius = 0.055
	pcyl.height = 2.55
	pole.mesh = pcyl
	pole.position = Vector3(0.68, 1.25, -0.32)
	pole.rotation.z = -0.09
	pole.material_override = mat_iron
	_visual_root.add_child(pole)

	var pennant: MeshInstance3D = MeshInstance3D.new()
	var penbox: BoxMesh = BoxMesh.new()
	penbox.size = Vector3(0.86, 0.42, 0.04)
	pennant.mesh = penbox
	pennant.position = Vector3(1.14, 2.24, -0.32)
	pennant.rotation.z = -0.05
	var pmat: StandardMaterial3D = StandardMaterial3D.new()
	pmat.albedo_color = cloth_col
	pmat.roughness = 0.55
	pmat.emission_enabled = true
	pmat.emission = cloth_col * 0.24
	pennant.material_override = pmat
	_visual_root.add_child(pennant)

	# Diamante / insígnia dourada flutuante para leitura rápida sem pesar na GPU
	_float_marker = MeshInstance3D.new()
	var oct: SphereMesh = SphereMesh.new()
	oct.radius = 0.22
	oct.height = 0.52
	oct.radial_segments = 4
	oct.rings = 1
	_float_marker.mesh = oct
	_float_marker.position = Vector3(0.0, 2.25, 0.0)
	_float_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_float_marker.material_override = mat_gold
	_visual_root.add_child(_float_marker)

	# Anel luminoso no solo (visível mesmo sob copas de árvore)
	_beacon_ring = MeshInstance3D.new()
	var rtor: TorusMesh = TorusMesh.new()
	rtor.inner_radius = 1.25
	rtor.outer_radius = 1.44
	rtor.rings = 24
	rtor.ring_segments = 5
	_beacon_ring.mesh = rtor
	_beacon_ring.position.y = 0.06
	_beacon_ring.scale = Vector3(1.0, 0.12, 1.0)
	var rmat: StandardMaterial3D = StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.albedo_color = Color(accent.r, accent.g, accent.b, 0.72)
	_beacon_ring.material_override = rmat
	_beacon_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beacon_ring)


func _build_collision() -> void:
	collision_layer = 1
	collision_mask = 0
	var col: CollisionShape3D = CollisionShape3D.new()
	var cyl: CylinderShape3D = CylinderShape3D.new()
	cyl.radius = 1.15
	cyl.height = 1.8
	col.shape = cyl
	col.position.y = 0.9
	add_child(col)


func set_fog_hidden(hidden: bool) -> void:
	if fog_hidden == hidden:
		return
	fog_hidden = hidden
	visible = not hidden
	if not claimed:
		collision_layer = 0 if hidden else 1


func _process(delta: float) -> void:
	if claimed or _game_manager == null:
		return

	if not fog_hidden and visible:
		_pulse_phase += delta * 2.8
		if _float_marker != null:
			_float_marker.position.y = 2.25 + sin(_pulse_phase) * 0.18
			_float_marker.rotation.y += delta * 1.6
		if _beacon_ring != null:
			var sc: float = 1.0 + sin(_pulse_phase * 1.4) * 0.08
			_beacon_ring.scale = Vector3(sc, 0.12, sc)

	if not bool(_game_manager.match_started) or bool(_game_manager.is_game_over):
		return

	_check_timer -= delta
	if _check_timer > 0.0:
		return
	_check_timer = 0.25

	var nearby: Array = _game_manager.call("query_units", global_position, 4.4)
	for raw in nearby:
		if is_instance_valid(raw) and not bool(raw._dead) and int(raw.team) == 0 and float(raw.hp) > 0.0:
			claim(raw)
			return


func claim(claimer: Variant = null) -> void:
	if claimed or _game_manager == null:
		return
	claimed = true
	discovered = true
	collision_layer = 0

	var cfg: Dictionary = CACHE_TYPES.get(cache_kind, CACHE_TYPES["supplies"])
	var grant: Dictionary = cfg.get("grant", {})
	var reward_parts: Array[String] = []
	for r in CACHE_RES_ORDER:
		var amt: int = int(grant.get(r, 0))
		if amt > 0:
			_game_manager.call("add_resource", 0, r, amt)
			reward_parts.append("+%d %s" % [amt, String(CACHE_RES_NAMES[r])])

	if cfg.has("units"):
		var spawned_names: Array[String] = []
		var unit_list: Array = cfg["units"]
		for idx in range(unit_list.size()):
			var utype: String = String(unit_list[idx])
			var off: Vector3 = Vector3(cos(float(idx) * 2.1) * 1.8, 0.0, sin(float(idx) * 2.1) * 1.8)
			var ally: RTSUnit = _game_manager.call("spawn_unit", utype, global_position + off, 0) as RTSUnit
			if ally != null:
				spawned_names.append(ally.get_display_name())
				if claimer != null and is_instance_valid(claimer) and claimer is Node3D:
					var cnode: Node3D = claimer as Node3D
					if "state" in claimer and int(claimer.state) == RTSUnit.State.MOVING:
						ally.command_attack_move(cnode.global_position)
		if not spawned_names.is_empty():
			reward_parts.append("+%d Tropas (%s)" % [spawned_names.size(), ", ".join(spawned_names)])

	if bool(cfg.get("decree", false)) and _game_manager.has_method("grant_royal_decree"):
		_game_manager.call("grant_royal_decree", "Estandarte da Fronteira recuperado!")
		reward_parts.append("+1 Decreto Real")

	var summary: String = "%s coletado: %s!" % [get_display_name(), ", ".join(reward_parts)]
	var accent: Color = cfg["color"]
	_game_manager.call("post_alert", summary, accent)
	_game_manager.call("spawn_floating_text", global_position + Vector3(0.0, 2.3, 0.0), ", ".join(reward_parts), accent)

	var sfx_node: Variant = _game_manager.get("sfx")
	if sfx_node != null:
		sfx_node.play_market_trade()
		if bool(cfg.get("decree", false)):
			sfx_node.play_age_up()

	var vfx_node: Variant = _game_manager.get("vfx")
	if vfx_node != null:
		vfx_node.spawn_hit_sparks(global_position)
		vfx_node.spawn_dust_burst(global_position, 1.8)

	var gm_caches: Variant = _game_manager.get("caches")
	if gm_caches is Array:
		(gm_caches as Array).erase(self)

	if is_inside_tree() and DisplayServer.get_name() != "headless":
		var tw: Tween = create_tween()
		tw.set_parallel(true)
		tw.tween_property(self, "scale", Vector3(1.18, 0.05, 1.18), 0.28).set_ease(Tween.EASE_IN)
		tw.tween_property(self, "position:y", -0.3, 0.28)
		tw.chain().tween_callback(queue_free)
	else:
		queue_free()
