extends RefCounted
class_name MapGenerator

## Gera o mapa "Vale da Fronteira" a partir de data/map_layout.json:
## - 6 posições de base (3 de cada lado do rio). O jogador nasce em uma posição sorteada e o
##   Barão Corvo Vermelho em uma posição sorteada do outro lado, escondido pela névoa.
## - Cada posição tem ouro, pedra, frutos silvestres e bosque próprios; posições vazias viram expansões.
## - Recursos neutros disputados, florestas, ruínas e penhascos completam o mapa.

const LAYOUT_PATH: String = "res://data/map_layout.json"
const TREE_SPACING: float = 4.2

var layout: Dictionary = {}
var map_half: float = 100.0
var terrain_half: float = 130.0
var plaza_radius: float = 12.0
var slots: Array[Dictionary] = []
var neutral: Dictionary = {}
var roads: Array = []

var _placed: Dictionary = {}
var _cell: float = 8.0


func load_layout() -> bool:
	var f: FileAccess = FileAccess.open(LAYOUT_PATH, FileAccess.READ)
	if f == null:
		push_error("MapGenerator: não foi possível abrir " + LAYOUT_PATH)
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("MapGenerator: JSON inválido em " + LAYOUT_PATH)
		return false
	layout = parsed
	map_half = float(layout.get("map_half", 100.0))
	terrain_half = float(layout.get("terrain_half", 130.0))
	plaza_radius = float(layout.get("plaza_radius", 12.0))
	_build_mirrored_data()
	return true


static func mirror_xz(x: float, z: float) -> Vector2:
	return Vector2(-x, -z)


func _mirror_list(src: Array) -> Array:
	var out: Array = []
	for e in src:
		var arr: Array = (e as Array).duplicate()
		var m: Vector2 = mirror_xz(float(arr[0]), float(arr[1]))
		arr[0] = m.x
		arr[1] = m.y
		out.append(arr)
	return out


func _build_mirrored_data() -> void:
	slots.clear()
	var src_slots: Array = layout.get("slots", [])
	var mirror_names: Dictionary = {"sudoeste": "Nordeste", "oeste": "Leste", "sul": "Norte"}
	for side in [0, 1]:
		for s in src_slots:
			var sd: Dictionary = s
			var p: Array = sd["pos"]
			var pos: Vector2 = Vector2(float(p[0]), float(p[1]))
			var entry: Dictionary = {
				"id": String(sd["id"]) if side == 0 else String(sd["id"]) + "_espelho",
				"name": String(sd["name"]) if side == 0 else String(mirror_names.get(String(sd["id"]), "Oposto")),
				"side": side,
				"pos": Vector3(pos.x, 0.0, pos.y) if side == 0 else Vector3(-pos.x, 0.0, -pos.y),
			}
			for key in ["gold", "stone", "berries", "forests"]:
				var lst: Array = sd.get(key, [])
				entry[key] = lst.duplicate(true) if side == 0 else _mirror_list(lst)
			slots.append(entry)

	var src_neutral: Dictionary = layout.get("neutral", {})
	neutral = {}
	for key in src_neutral.keys():
		var lst: Array = src_neutral[key]
		var mirrored: Array = []
		for e in lst:
			var arr: Array = (e as Array).duplicate()
			var m: Vector2 = mirror_xz(float(arr[0]), float(arr[1]))
			arr[0] = m.x
			arr[1] = m.y
			if String(key) == "ruins" and arr.size() >= 3:
				arr[2] = float(arr[2]) + PI
			mirrored.append(arr)
		var combined: Array = lst.duplicate(true)
		combined.append_array(mirrored)
		neutral[key] = combined

	roads = []
	for r in layout.get("roads", []):
		var arr: Array = r
		roads.append(arr.duplicate())
		roads.append([-float(arr[0]), -float(arr[1]), -float(arr[2]), -float(arr[3]), float(arr[4])])


## Sorteia o lado do rio do jogador e as posições das duas bases (sempre em lados opostos).
func choose_start_slots(rng: RandomNumberGenerator) -> Dictionary:
	var player_side: int = rng.randi_range(0, 1)
	var player_opts: Array[int] = []
	var enemy_opts: Array[int] = []
	for i in range(slots.size()):
		if int(slots[i]["side"]) == player_side:
			player_opts.append(i)
		else:
			enemy_opts.append(i)
	var p_idx: int = player_opts[rng.randi_range(0, player_opts.size() - 1)]
	var e_idx: int = enemy_opts[rng.randi_range(0, enemy_opts.size() - 1)]
	return {"player": p_idx, "enemy": e_idx}


func get_slot(idx: int) -> Dictionary:
	return slots[clampi(idx, 0, slots.size() - 1)]


## Pontos candidatos a covil inimigo, todos do lado do rio oposto ao jogador, em ordem sorteada:
## as 3 posições de base desse lado + pontos remotos (data/map_layout.json "lair_spots").
func lair_candidates(player_side: int, rng: RandomNumberGenerator) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for s in slots:
		if int(s["side"]) != player_side:
			out.append(s["pos"])
	for e in layout.get("lair_spots", []):
		var p: Vector3 = Vector3(float(e[0]), 0.0, float(e[1]))
		if player_side == 0:
			p = Vector3(-p.x, 0.0, -p.z)
		out.append(p)
	for i in range(out.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Vector3 = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out


# ==============================================================================
# POPULAÇÃO DO MAPA
# ==============================================================================

func _key(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / _cell)), int(floor(p.z / _cell)))


func _register(p: Vector3, radius: float) -> void:
	var k: Vector2i = _key(p)
	if not _placed.has(k):
		_placed[k] = []
	(_placed[k] as Array).append([p, radius])


func _is_free(p: Vector3, radius: float, extra: float) -> bool:
	var k: Vector2i = _key(p)
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var kk: Vector2i = Vector2i(k.x + dx, k.y + dz)
			if not _placed.has(kk):
				continue
			for e in _placed[kk]:
				var q: Vector3 = e[0]
				var rr: float = float(e[1])
				if Vector2(p.x - q.x, p.z - q.z).length() < radius + rr + extra:
					return false
	return true


static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq < 0.0001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _near_road(p: Vector3, margin: float) -> bool:
	var p2: Vector2 = Vector2(p.x, p.z)
	for r in roads:
		var a: Vector2 = Vector2(float(r[0]), float(r[1]))
		var b: Vector2 = Vector2(float(r[2]), float(r[3]))
		if _dist_to_segment(p2, a, b) < float(r[4]) + margin:
			return true
	return false


func _near_slot(p: Vector3, margin: float) -> bool:
	for s in slots:
		var sp: Vector3 = s["pos"]
		if Vector2(p.x - sp.x, p.z - sp.z).length() < plaza_radius + margin:
			return true
	return false


func _near_bridge(p: Vector3, dist: float) -> bool:
	for b in RTSUnit.BRIDGES:
		if Vector2(p.x - b.x, p.z - b.z).length() < dist:
			return true
	return false


func _valid_open_spot(p: Vector3, radius: float, bound: float = 95.0) -> bool:
	if absf(p.x) > bound - radius or absf(p.z) > bound - radius:
		return false
	if RTSUnit.river_distance_at(p.x, p.z) < 9.5 + radius * 1.414:
		return false
	return true


func populate(gm: GameManager, props_root: Node3D, rng: RandomNumberGenerator) -> void:
	_placed.clear()
	# Reserva as praças das bases e a área das pontes
	for s in slots:
		_register(s["pos"], plaza_radius - 2.0)

	# 1. Recursos de cada posição de base
	for s in slots:
		for g in s["gold"]:
			_spawn_res(gm, "gold_mine", Vector3(float(g[0]), 0.0, float(g[1])), int(g[2]))
		for st in s["stone"]:
			_spawn_res(gm, "stone_quarry", Vector3(float(st[0]), 0.0, float(st[1])), int(st[2]))
		for be in s["berries"]:
			_spawn_berry_cluster(gm, Vector3(float(be[0]), 0.0, float(be[1])), int(be[2]))

	# 2. Recursos neutros disputados
	for g in neutral.get("gold", []):
		_spawn_res(gm, "gold_mine", Vector3(float(g[0]), 0.0, float(g[1])), int(g[2]))
	for st in neutral.get("stone", []):
		_spawn_res(gm, "stone_quarry", Vector3(float(st[0]), 0.0, float(st[1])), int(st[2]))
	for be in neutral.get("berries", []):
		_spawn_berry_cluster(gm, Vector3(float(be[0]), 0.0, float(be[1])), int(be[2]))

	# 3. Marcos de cenário (ruínas e penhascos)
	_spawn_landmarks(gm, props_root, rng)

	# 4. Florestas (bosques das bases + florestas neutras)
	var zones: Array = []
	for s in slots:
		zones.append_array(s["forests"])
	zones.append_array(neutral.get("forests", []))
	for z in zones:
		_spawn_forest(gm, Vector3(float(z[0]), 0.0, float(z[1])), float(z[2]), rng)

	# 5. Arbustos decorativos espalhados
	_spawn_shrubs(gm, props_root, rng, zones)

	# 6. Vegetação 3D instanciada via MultiMesh (grama, flores, juncos ribeirinhos, seixos, samambaias)
	var foliage: WorldFoliage = WorldFoliage.new()
	foliage.name = "WorldFoliage"
	props_root.add_child(foliage)
	foliage.generate(self, zones, rng)


func _spawn_res(gm: GameManager, kind: String, pos: Vector3, amount: int) -> void:
	var r: RTSResourceNode = gm.spawn_resource(kind, pos, amount)
	if r != null:
		_register(pos, r.collision_radius)


func _spawn_berry_cluster(gm: GameManager, center: Vector3, count: int) -> void:
	var pts: Array[Vector3] = [center]
	var ring: int = maxi(1, count - 1)
	for i in range(ring):
		var a: float = TAU * float(i) / float(ring) + 0.4
		pts.append(center + Vector3(cos(a), 0.0, sin(a)) * 2.45)
	for i in range(mini(count, pts.size())):
		_spawn_res(gm, "berry_bush", pts[i], 125)


func _spawn_forest(gm: GameManager, center: Vector3, radius: float, rng: RandomNumberGenerator) -> void:
	var target: int = maxi(2, int(PI * radius * radius / 15.0))
	var placed: int = 0
	var attempts: int = target * 14
	while attempts > 0 and placed < target:
		attempts -= 1
		var ang: float = rng.randf() * TAU
		var dist: float = sqrt(rng.randf()) * radius
		var p: Vector3 = center + Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
		if not _valid_open_spot(p, 1.2):
			continue
		if _near_bridge(p, 17.0) or _near_slot(p, 3.0) or _near_road(p, 1.8):
			continue
		if not _is_free(p, 1.2, TREE_SPACING - 2.4):
			continue
		var t: RTSResourceNode = gm.spawn_resource("tree", p, 150)
		if t != null:
			_register(p, 1.2)
			placed += 1


func _spawn_landmarks(gm: GameManager, props_root: Node3D, rng: RandomNumberGenerator) -> void:
	var ruins_scene: PackedScene = load("res://assets/models/prop_ruins_arch.glb") as PackedScene
	if ruins_scene != null:
		for rs in neutral.get("ruins", []):
			var inst: Node3D = ruins_scene.instantiate() as Node3D
			if inst == null:
				continue
			inst.position = Vector3(float(rs[0]), 0.0, float(rs[1]))
			inst.rotation.y = float(rs[2]) if rs.size() > 2 else 0.0
			_attach_static_cylinder_collider(inst, 2.25, 3.6)
			gm.register_static_obstacle(inst.position, 2.25, "ruin")
			_register(inst.position, 2.25)
			props_root.add_child(inst)

	var cliff_scene: PackedScene = load("res://assets/models/prop_cliff_rock.glb") as PackedScene
	if cliff_scene != null:
		for cp in neutral.get("cliffs", []):
			var c_inst: Node3D = cliff_scene.instantiate() as Node3D
			if c_inst == null:
				continue
			c_inst.position = Vector3(float(cp[0]), 0.1, float(cp[1]))
			c_inst.rotation.y = rng.randf_range(0.0, TAU)
			var cs: float = rng.randf_range(1.05, 1.45)
			c_inst.scale = Vector3(cs, cs * rng.randf_range(0.85, 1.15), cs)
			_set_cast_shadow_recursive(c_inst, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			_attach_static_cylinder_collider(c_inst, 1.75 * cs, 2.8)
			gm.register_static_obstacle(c_inst.position, 1.75 * cs, "cliff")
			_register(c_inst.position, 1.75 * cs)
			props_root.add_child(c_inst)


func _spawn_shrubs(gm: GameManager, props_root: Node3D, rng: RandomNumberGenerator, zones: Array) -> void:
	var shrub_scene: PackedScene = load("res://assets/models/prop_shrub_cluster.glb") as PackedScene
	if shrub_scene == null:
		return
	var wanted: int = 46
	var attempts: int = 900
	var made: int = 0
	while attempts > 0 and made < wanted:
		attempts -= 1
		var p: Vector3
		if rng.randf() < 0.6 and not zones.is_empty():
			var z: Array = zones[rng.randi_range(0, zones.size() - 1)]
			var ang: float = rng.randf() * TAU
			var d: float = float(z[2]) + rng.randf_range(1.0, 4.0)
			p = Vector3(float(z[0]) + cos(ang) * d, 0.0, float(z[1]) + sin(ang) * d)
		else:
			p = Vector3(rng.randf_range(-90.0, 90.0), 0.0, rng.randf_range(-90.0, 90.0))
		if not _valid_open_spot(p, 0.8):
			continue
		if _near_bridge(p, 15.0) or _near_slot(p, 4.0) or _near_road(p, 1.5):
			continue
		if not _is_free(p, 0.8, 1.6):
			continue
		var s_inst: Node3D = shrub_scene.instantiate() as Node3D
		if s_inst == null:
			continue
		s_inst.position = p
		s_inst.rotation.y = rng.randf_range(0.0, TAU)
		var ss: float = rng.randf_range(0.85, 1.25)
		s_inst.scale = Vector3.ONE * ss
		_set_cast_shadow_recursive(s_inst, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		_attach_static_cylinder_collider(s_inst, 0.68 * ss, 1.4)
		gm.register_static_obstacle(p, 0.68 * ss, "shrub")
		_register(p, 0.68 * ss)
		props_root.add_child(s_inst)
		made += 1


static func _attach_static_cylinder_collider(target: Node3D, radius: float, height: float = 3.0) -> void:
	var sb: StaticBody3D = StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	# Compensa a escala do nó pai para que o colisor físico tenha o raio exato no espaço do mundo
	sb.scale = Vector3(
		1.0 / maxf(0.01, target.scale.x),
		1.0 / maxf(0.01, target.scale.y),
		1.0 / maxf(0.01, target.scale.z)
	)
	var col: CollisionShape3D = CollisionShape3D.new()
	var cyl: CylinderShape3D = CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = height
	col.shape = cyl
	col.position.y = height * 0.5
	sb.add_child(col)
	target.add_child(sb)


static func _set_cast_shadow_recursive(node: Node, mode: GeometryInstance3D.ShadowCastingSetting) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = mode
	for child in node.get_children():
		_set_cast_shadow_recursive(child, mode)
