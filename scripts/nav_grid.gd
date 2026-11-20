extends RefCounted
class_name NavGrid

## Grade de navegação (A* nativo do Godot via AStarGrid2D) para rotas longas das unidades.
## O rio só é atravessável sobre as pontes; florestas, minas e prédios bloqueiam células.
## Desvio fino entre unidades e obstáculos continua sendo feito pelo steering em RTSUnit.

const CELL: float = 2.0
const CLEARANCE: float = 0.45

var half: float = 100.0
var size: int = 100
var astar: AStarGrid2D = AStarGrid2D.new()
var _occ: PackedInt32Array = PackedInt32Array()
var _static_solid: PackedByteArray = PackedByteArray()


func setup(map_half: float, bound: float) -> void:
	half = map_half
	size = int(ceil((map_half * 2.0) / CELL))
	astar.region = Rect2i(0, 0, size, size)
	astar.cell_size = Vector2(CELL, CELL)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	_occ.resize(size * size)
	_occ.fill(0)
	_static_solid.resize(size * size)
	_static_solid.fill(0)
	for cz in range(size):
		for cx in range(size):
			var w: Vector3 = cell_to_world(Vector2i(cx, cz))
			var solid: bool = false
			if absf(w.x) > bound or absf(w.z) > bound:
				solid = true
			elif RTSUnit.is_in_river_water(w.x, w.z, 1.1) and not RTSUnit.is_on_bridge_deck(w.x, w.z, 0.55):
				solid = true
			elif _is_bridge_side_band(w):
				# Faixa ao lado dos parapeitos: a ponte só pode ser acessada pelas cabeceiras
				solid = true
			if solid:
				_static_solid[cz * size + cx] = 1
				astar.set_point_solid(Vector2i(cx, cz), true)


static func _is_bridge_side_band(w: Vector3) -> bool:
	for b in RTSUnit.BRIDGES:
		var along: float = absf(((w.x + w.z) - (b.x + b.z)) * 0.70710678)
		var across: float = absf((w.x - w.z) * 0.70710678)
		if across <= RTSUnit.BRIDGE_HALF_LEN + 0.6 and along > RTSUnit.BRIDGE_HALF_WIDTH - 0.55 and along < 4.55 + 1.2:
			return true
	return false


func world_to_cell(p: Vector3) -> Vector2i:
	var cx: int = clampi(int(floor((p.x + half) / CELL)), 0, size - 1)
	var cz: int = clampi(int(floor((p.z + half) / CELL)), 0, size - 1)
	return Vector2i(cx, cz)


func cell_to_world(c: Vector2i) -> Vector3:
	return Vector3(-half + (float(c.x) + 0.5) * CELL, 0.0, -half + (float(c.y) + 0.5) * CELL)


func _in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size and c.y < size


func is_cell_walkable(c: Vector2i) -> bool:
	if not _in_bounds(c):
		return false
	return not astar.is_point_solid(c)


func is_walkable_world(p: Vector3) -> bool:
	return is_cell_walkable(world_to_cell(p))


func _apply_circle(pos: Vector3, radius: float, delta_count: int) -> void:
	var r: float = radius + CLEARANCE
	var c_min: Vector2i = world_to_cell(Vector3(pos.x - r, 0.0, pos.z - r))
	var c_max: Vector2i = world_to_cell(Vector3(pos.x + r, 0.0, pos.z + r))
	var r_sq: float = r * r
	for cz in range(c_min.y, c_max.y + 1):
		for cx in range(c_min.x, c_max.x + 1):
			var w: Vector3 = cell_to_world(Vector2i(cx, cz))
			var dx: float = w.x - pos.x
			var dz: float = w.z - pos.z
			if dx * dx + dz * dz > r_sq:
				continue
			var idx: int = cz * size + cx
			_occ[idx] = maxi(0, _occ[idx] + delta_count)
			var solid: bool = _occ[idx] > 0 or _static_solid[idx] == 1
			astar.set_point_solid(Vector2i(cx, cz), solid)


func add_circle(pos: Vector3, radius: float) -> void:
	_apply_circle(pos, radius, 1)


func remove_circle(pos: Vector3, radius: float) -> void:
	_apply_circle(pos, radius, -1)


func _nearest_walkable(c: Vector2i, max_ring: int = 6) -> Vector2i:
	if is_cell_walkable(c):
		return c
	for ring in range(1, max_ring + 1):
		var best: Vector2i = Vector2i(-1, -1)
		var best_d: int = 1 << 30
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if absi(dx) != ring and absi(dz) != ring:
					continue
				var n: Vector2i = Vector2i(c.x + dx, c.y + dz)
				if is_cell_walkable(n):
					var d: int = dx * dx + dz * dz
					if d < best_d:
						best_d = d
						best = n
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


## Verifica se a linha reta entre dois pontos só passa por células livres.
func segment_clear(a: Vector3, b: Vector3) -> bool:
	var dist: float = Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
	var steps: int = maxi(1, int(ceil(dist / (CELL * 0.5))))
	for i in range(1, steps + 1):
		var t: float = float(i) / float(steps)
		var p: Vector3 = a.lerp(b, t)
		if not is_cell_walkable(world_to_cell(p)):
			# Tolerância: o próprio destino pode estar dentro de um obstáculo (árvore, prédio-alvo)
			if i == steps:
				return true
			return false
	return true


func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	var c_from: Vector2i = _nearest_walkable(world_to_cell(from), 4)
	var c_to: Vector2i = _nearest_walkable(world_to_cell(to), 8)
	if c_from.x < 0 or c_to.x < 0:
		return out
	if c_from == c_to:
		out.append(Vector3(to.x, 0.0, to.z))
		return out
	var ids: Array[Vector2i] = astar.get_id_path(c_from, c_to, true)
	if ids.is_empty():
		return out
	var raw: PackedVector3Array = PackedVector3Array()
	for id in ids:
		raw.append(cell_to_world(id))
	# Suaviza a rota pulando pontos com linha de visão livre
	var i: int = 0
	var start: Vector3 = Vector3(from.x, 0.0, from.z)
	var cur: Vector3 = start
	while i < raw.size():
		var far: int = i
		var limit: int = mini(raw.size() - 1, i + 10)
		for j in range(limit, i, -1):
			if segment_clear(cur, raw[j]):
				far = j
				break
		cur = raw[far]
		out.append(cur)
		i = far + 1
	if not out.is_empty():
		var exact_to: Vector3 = Vector3(to.x, 0.0, to.z)
		var prev_anchor: Vector3 = out[out.size() - 2] if out.size() >= 2 else start
		if is_walkable_world(exact_to) and segment_clear(prev_anchor, exact_to):
			if not RTSUnit.is_in_river_water(exact_to.x, exact_to.z, 0.8):
				out[out.size() - 1] = exact_to
	return out
