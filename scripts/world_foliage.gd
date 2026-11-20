extends Node3D
class_name WorldFoliage

## Vegetação 3D e micro-detalhes naturais instanciados por GPU via MultiMeshInstance3D.
## Total de apenas 5 draw calls no mapa inteiro (sem sombras projetadas), mantendo FPS alto na RX 550.

# A grama encolhe até sumir longe da câmera (foliage_wind.gdshader), então mais touceiras
# só custam vértices; os pixels desenhados ficam perto da câmera.
const GRASS_COUNT: int = 7600
const FLOWER_COUNT: int = 760
const REED_COUNT: int = 560
const PEBBLE_COUNT: int = 460
const FERN_COUNT: int = 420

var instanced_groups: int = 0
var total_instances: int = 0


func generate(map_gen: MapGenerator, zones: Array, map_rng: RandomNumberGenerator) -> void:
	# Gerador próprio (derivado da semente do mapa, sem consumir o dela): mudar a quantidade de
	# grama ou flores não pode mudar onde nascem as bases e os covis.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(str(map_rng.seed) + ":foliage")
	var wind_shader: Shader = load("res://scripts/shaders/foliage_wind.gdshader") as Shader
	# ground_match: quanto a planta herda a cor do chão embaixo (grama casa com o terreno; flores não)
	var grass_mat: Material = _make_foliage_mat(wind_shader, 0.085, 1.9, 0.78, map_gen, 1.0, 0.35, 40.0, 56.0)
	var flower_mat: Material = _make_foliage_mat(wind_shader, 0.095, 2.2, 0.68, map_gen, 0.0, 0.32, 40.0, 56.0)
	var reed_mat: Material = _make_foliage_mat(wind_shader, 0.14, 1.55, 0.74, map_gen, 0.35, 1.05, 50.0, 66.0)
	var fern_mat: Material = _make_foliage_mat(wind_shader, 0.085, 1.9, 0.78, map_gen, 0.75, 0.24, 40.0, 56.0)

	var pebble_mat: StandardMaterial3D = StandardMaterial3D.new()
	pebble_mat.vertex_color_use_as_albedo = true
	pebble_mat.roughness = 0.80
	pebble_mat.metallic = 0.02

	_build_grass_tufts(map_gen, rng, grass_mat)
	_build_wildflowers(map_gen, rng, flower_mat)
	_build_river_reeds(map_gen, rng, reed_mat)
	_build_pebbles(map_gen, rng, pebble_mat)
	_build_forest_ferns(map_gen, zones, rng, fern_mat)


func _make_foliage_mat(shader: Shader, strength: float, speed: float, rough: float, map_gen: MapGenerator,
		ground_match: float, blade_height: float, fade_start: float, fade_end: float) -> Material:
	if shader != null:
		var sm: ShaderMaterial = ShaderMaterial.new()
		sm.shader = shader
		sm.set_shader_parameter("wind_strength", strength)
		sm.set_shader_parameter("wind_speed", speed)
		sm.set_shader_parameter("roughness_val", rough)
		sm.set_shader_parameter("ground_match", ground_match)
		sm.set_shader_parameter("blade_height", blade_height)
		sm.set_shader_parameter("fade_start", fade_start)
		sm.set_shader_parameter("fade_end", fade_end)
		sm.set_shader_parameter("terrain_half", map_gen.terrain_half)
		sm.set_shader_parameter("world_noise", WorldLook.noise_texture())
		sm.set_shader_parameter("ground_albedo", WorldLook.load_mipmapped("res://assets/textures/terrain_baked_albedo.png"))
		return sm
	var fb: StandardMaterial3D = StandardMaterial3D.new()
	fb.vertex_color_use_as_albedo = true
	fb.cull_mode = BaseMaterial3D.CULL_DISABLED
	fb.roughness = rough
	return fb


static func _river_distance(x: float, z: float) -> float:
	var meander: float = sin((x + z) * 0.038) * 1.35 + cos((x + z) * 0.09) * 0.45
	return absf(x - z + meander)


static func _river_meander(x_plus_z: float) -> float:
	return sin(x_plus_z * 0.038) * 1.35 + cos(x_plus_z * 0.09) * 0.45


static func _terrain_height(x: float, z: float) -> float:
	var dr: float = _river_distance(x, z)
	var t: float = clampf((dr - 1.8) / (6.4 - 1.8), 0.0, 1.0)
	var ss: float = t * t * (3.0 - 2.0 * t)
	return (1.0 - ss) * -1.15


func _near_plaza_center(map_gen: MapGenerator, p: Vector3, margin: float) -> bool:
	var limit: float = map_gen.plaza_radius + margin
	for s in map_gen.slots:
		var sp: Vector3 = s["pos"]
		if Vector2(p.x - sp.x, p.z - sp.z).length() < limit:
			return true
	return false


func _spawn_multimesh(node_name: String, mesh: Mesh, transforms: Array[Transform3D], colors: Array[Color]) -> void:
	if transforms.is_empty():
		return
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = transforms.size()
	mm.mesh = mesh
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])

	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mmi)
	instanced_groups += 1
	total_instances += transforms.size()


func _build_grass_tufts(map_gen: MapGenerator, rng: RandomNumberGenerator, mat: Material) -> void:
	var mesh: ArrayMesh = _create_grass_mesh(mat)
	var xforms: Array[Transform3D] = []
	var cols: Array[Color] = []

	var palette: Array[Color] = [
		Color(0.76, 0.94, 0.66),
		Color(0.86, 0.98, 0.72),
		Color(0.68, 0.88, 0.62),
		Color(0.94, 0.96, 0.64),
	]
	var attempts: int = 0
	while xforms.size() < GRASS_COUNT and attempts < GRASS_COUNT * 4:
		attempts += 1
		var cx: float = rng.randf_range(-93.0, 93.0)
		var cz: float = rng.randf_range(-93.0, 93.0)
		var base_p: Vector3 = Vector3(cx, 0.0, cz)
		if _river_distance(cx, cz) < 6.0:
			continue
		if _near_plaza_center(map_gen, base_p, -1.0) or map_gen._near_road(base_p, 0.8) or map_gen._near_bridge(base_p, 9.2):
			continue
		if not map_gen._is_free(base_p, 0.3, 0.3):
			continue

		var cluster_n: int = rng.randi_range(3, 6)
		for _j in range(cluster_n):
			if xforms.size() >= GRASS_COUNT:
				break
			var px: float = clampf(cx + rng.randf_range(-1.7, 1.7), -94.0, 94.0)
			var pz: float = clampf(cz + rng.randf_range(-1.7, 1.7), -94.0, 94.0)
			var p: Vector3 = Vector3(px, 0.0, pz)
			if _river_distance(px, pz) < 6.0 or _near_plaza_center(map_gen, p, -1.0) or map_gen._near_road(p, 0.7):
				continue
			var s: float = rng.randf_range(0.78, 1.32)
			var b: Basis = Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(s, s * rng.randf_range(0.75, 1.15), s))
			xforms.append(Transform3D(b, Vector3(px, _terrain_height(px, pz) - 0.02, pz)))
			cols.append(palette[rng.randi_range(0, palette.size() - 1)])

	_spawn_multimesh("GrassTufts", mesh, xforms, cols)


func _build_wildflowers(map_gen: MapGenerator, rng: RandomNumberGenerator, mat: Material) -> void:
	var mesh: ArrayMesh = _create_flower_mesh(mat)
	var xforms: Array[Transform3D] = []
	var cols: Array[Color] = []

	var flower_colors: Array[Color] = [
		Color(1.0, 0.84, 0.22),
		Color(0.98, 0.96, 0.86),
		Color(0.78, 0.64, 0.96),
		Color(0.96, 0.44, 0.34),
		Color(1.0, 0.74, 0.28),
	]
	var attempts: int = 0
	while xforms.size() < FLOWER_COUNT and attempts < FLOWER_COUNT * 6:
		attempts += 1
		var cx: float = rng.randf_range(-90.0, 90.0)
		var cz: float = rng.randf_range(-90.0, 90.0)
		var patch_col: Color = flower_colors[rng.randi_range(0, flower_colors.size() - 1)]
		var count: int = rng.randi_range(3, 7)
		for _j in range(count):
			if xforms.size() >= FLOWER_COUNT:
				break
			var px: float = clampf(cx + rng.randf_range(-2.2, 2.2), -93.0, 93.0)
			var pz: float = clampf(cz + rng.randf_range(-2.2, 2.2), -93.0, 93.0)
			var p: Vector3 = Vector3(px, 0.0, pz)
			if _river_distance(px, pz) < 6.5 or _near_plaza_center(map_gen, p, 0.0) or map_gen._near_road(p, 1.0) or map_gen._near_bridge(p, 10.0):
				continue
			if not map_gen._is_free(p, 0.25, 0.25):
				continue
			var s: float = rng.randf_range(0.78, 1.28)
			var b: Basis = Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * s)
			xforms.append(Transform3D(b, Vector3(px, _terrain_height(px, pz) - 0.01, pz)))
			cols.append(patch_col)

	_spawn_multimesh("Wildflowers", mesh, xforms, cols)


func _build_river_reeds(map_gen: MapGenerator, rng: RandomNumberGenerator, mat: Material) -> void:
	var mesh: ArrayMesh = _create_reed_mesh(mat)
	var xforms: Array[Transform3D] = []
	var cols: Array[Color] = []
	var palette: Array[Color] = [
		Color(0.24, 0.44, 0.16),
		Color(0.30, 0.50, 0.18),
		Color(0.42, 0.46, 0.22),
	]

	var attempts: int = 0
	while xforms.size() < REED_COUNT and attempts < REED_COUNT * 6:
		attempts += 1
		var u: float = rng.randf_range(-92.0, 92.0) # x ≈ z ≈ u
		var side: float = -1.0 if rng.randf() < 0.5 else 1.0
		var dr_target: float = rng.randf_range(4.45, 6.45)
		var meander: float = _river_meander(2.0 * u)
		var x: float = u + 0.5 * (side * dr_target - meander)
		var z: float = u - 0.5 * (side * dr_target - meander)
		if absf(x) > 95.0 or absf(z) > 95.0:
			continue
		var p: Vector3 = Vector3(x, 0.0, z)
		if map_gen._near_bridge(p, 9.6):
			continue
		var s: float = rng.randf_range(0.75, 1.32)
		var b: Basis = Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(s, s * rng.randf_range(0.85, 1.35), s))
		xforms.append(Transform3D(b, Vector3(x, _terrain_height(x, z) - 0.03, z)))
		cols.append(palette[rng.randi_range(0, palette.size() - 1)])

	_spawn_multimesh("RiverReeds", mesh, xforms, cols)


func _build_pebbles(map_gen: MapGenerator, rng: RandomNumberGenerator, mat: Material) -> void:
	var mesh: ArrayMesh = _create_pebble_mesh(mat)
	var xforms: Array[Transform3D] = []
	var cols: Array[Color] = []
	var stone_palette: Array[Color] = [
		Color(0.46, 0.45, 0.42),
		Color(0.36, 0.36, 0.35),
		Color(0.52, 0.48, 0.41),
		Color(0.30, 0.32, 0.34),
	]

	var attempts: int = 0
	while xforms.size() < PEBBLE_COUNT and attempts < PEBBLE_COUNT * 6:
		attempts += 1
		var x: float
		var z: float
		if rng.randf() < 0.72:
			var u: float = rng.randf_range(-93.0, 93.0)
			var side: float = -1.0 if rng.randf() < 0.5 else 1.0
			var dr_target: float = rng.randf_range(3.95, 6.70)
			var meander: float = _river_meander(2.0 * u)
			x = u + 0.5 * (side * dr_target - meander)
			z = u - 0.5 * (side * dr_target - meander)
		else:
			x = rng.randf_range(-90.0, 90.0)
			z = rng.randf_range(-90.0, 90.0)
		if absf(x) > 95.0 or absf(z) > 95.0:
			continue
		var p: Vector3 = Vector3(x, 0.0, z)
		if map_gen._near_bridge(p, 8.8) or _near_plaza_center(map_gen, p, -1.5):
			continue
		var sx: float = rng.randf_range(0.65, 1.65)
		var sy: float = rng.randf_range(0.42, 0.95)
		var sz: float = rng.randf_range(0.65, 1.55)
		var b: Basis = Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(sx, sy, sz))
		xforms.append(Transform3D(b, Vector3(x, _terrain_height(x, z) - 0.02, z)))
		cols.append(stone_palette[rng.randi_range(0, stone_palette.size() - 1)])

	_spawn_multimesh("RiverPebbles", mesh, xforms, cols)


func _build_forest_ferns(map_gen: MapGenerator, zones: Array, rng: RandomNumberGenerator, mat: Material) -> void:
	if zones.is_empty():
		return
	var mesh: ArrayMesh = _create_fern_mesh(mat)
	var xforms: Array[Transform3D] = []
	var cols: Array[Color] = []
	var palette: Array[Color] = [
		Color(0.24, 0.48, 0.16),
		Color(0.19, 0.42, 0.14),
		Color(0.32, 0.56, 0.19),
	]

	var attempts: int = 0
	while xforms.size() < FERN_COUNT and attempts < FERN_COUNT * 8:
		attempts += 1
		var zone: Array = zones[rng.randi_range(0, zones.size() - 1)]
		var zx: float = float(zone[0])
		var zz: float = float(zone[1])
		var zr: float = float(zone[2])
		var ang: float = rng.randf() * TAU
		var d: float = rng.randf_range(0.2, zr + 2.8)
		var px: float = zx + cos(ang) * d
		var pz: float = zz + sin(ang) * d
		if absf(px) > 94.0 or absf(pz) > 94.0:
			continue
		var p: Vector3 = Vector3(px, 0.0, pz)
		if _river_distance(px, pz) < 6.4 or _near_plaza_center(map_gen, p, 0.5) or map_gen._near_road(p, 1.0) or map_gen._near_bridge(p, 10.0):
			continue
		if not map_gen._is_free(p, 0.3, 0.2):
			continue
		var s: float = rng.randf_range(0.8, 1.35)
		var b: Basis = Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * s)
		xforms.append(Transform3D(b, Vector3(px, _terrain_height(px, pz) - 0.02, pz)))
		cols.append(palette[rng.randi_range(0, palette.size() - 1)])

	_spawn_multimesh("ForestFerns", mesh, xforms, cols)


func _create_grass_mesh(mat: Material) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c_root: Color = Color(0.11, 0.24, 0.07)
	var c_mid: Color = Color(0.18, 0.38, 0.10)
	var c_tip: Color = Color(0.28, 0.50, 0.14)

	for i in range(4):
		var a: float = float(i) * (TAU / 4.0) + 0.25
		var dir: Vector3 = Vector3(cos(a), 0.0, sin(a))
		var side: Vector3 = Vector3(-dir.z, 0.0, dir.x)
		var lean: Vector3 = dir * 0.12
		var p_bl: Vector3 = -side * 0.055 + dir * 0.04
		var p_br: Vector3 = side * 0.055 + dir * 0.04
		var p_ml: Vector3 = -side * 0.036 + lean * 0.55 + Vector3(0.0, 0.18, 0.0)
		var p_mr: Vector3 = side * 0.036 + lean * 0.55 + Vector3(0.0, 0.18, 0.0)
		var p_top: Vector3 = lean * 1.15 + Vector3(0.0, 0.35, 0.0)

		_add_tri(st, p_bl, p_br, p_mr, c_root, c_root, c_mid)
		_add_tri(st, p_bl, p_mr, p_ml, c_root, c_mid, c_mid)
		_add_tri(st, p_ml, p_mr, p_top, c_mid, c_mid, c_tip)

	st.index()  # 20 vértices únicos por touceira em vez de 36: menos trabalho no vertex shader
	st.generate_normals()
	var m: ArrayMesh = st.commit()
	m.surface_set_material(0, mat)
	return m


func _create_flower_mesh(mat: Material) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem_c: Color = Color(0.16, 0.36, 0.10)
	var petal_c: Color = Color(1.0, 1.0, 1.0) # tintado por instância

	# Folhinhas basais + caule cruzado
	for rot_a in [0.0, PI * 0.5]:
		var s_dir: Vector3 = Vector3(cos(rot_a), 0.0, sin(rot_a)) * 0.04
		_add_tri(st, -s_dir, s_dir, Vector3(0.02, 0.30, 0.01), stem_c, stem_c, stem_c)

	# Corola aberta com 5 pétalas visíveis
	var head: Vector3 = Vector3(0.02, 0.29, 0.01)
	for i in range(5):
		var a: float = float(i) * (TAU / 5.0) + 0.2
		var out: Vector3 = Vector3(cos(a), 0.22, sin(a)) * 0.18
		var side: Vector3 = Vector3(-sin(a), 0.0, cos(a)) * 0.08
		_add_tri(st, head, head + out + side, head + out - side, petal_c, petal_c, petal_c)

	st.generate_normals()
	var m: ArrayMesh = st.commit()
	m.surface_set_material(0, mat)
	return m


func _create_reed_mesh(mat: Material) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Luminância neutra em escala de cinza para NÃO escurecer duplamente a paleta de instância
	var c_base: Color = Color(0.48, 0.52, 0.44)
	var c_mid: Color = Color(0.84, 0.88, 0.82)
	var c_top: Color = Color(1.0, 0.98, 0.88)

	for i in range(4):
		var a: float = float(i) * (TAU / 4.0) + 0.15
		var dir: Vector3 = Vector3(cos(a), 0.0, sin(a))
		var side: Vector3 = Vector3(-dir.z, 0.0, dir.x)
		var off: Vector3 = dir * 0.08
		var h: float = 0.82 + float(i % 2) * 0.26
		var lean: Vector3 = dir * 0.18
		_add_tri(st, off - side * 0.035, off + side * 0.035, off + side * 0.02 + lean * 0.5 + Vector3(0, h * 0.5, 0), c_base, c_base, c_mid)
		_add_tri(st, off - side * 0.035, off + side * 0.02 + lean * 0.5 + Vector3(0, h * 0.5, 0), off - side * 0.02 + lean * 0.5 + Vector3(0, h * 0.5, 0), c_base, c_mid, c_mid)
		_add_tri(st, off - side * 0.02 + lean * 0.5 + Vector3(0, h * 0.5, 0), off + side * 0.02 + lean * 0.5 + Vector3(0, h * 0.5, 0), off + lean + Vector3(0, h, 0), c_mid, c_mid, c_top)

	st.generate_normals()
	var m: ArrayMesh = st.commit()
	m.surface_set_material(0, mat)
	return m


func _create_pebble_mesh(mat: Material) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c_bot: Color = Color(0.48, 0.48, 0.48)
	var c_mid: Color = Color(0.85, 0.85, 0.84)
	var c_top: Color = Color(1.0, 1.0, 1.0)
	var top: Vector3 = Vector3(0.02, 0.14, -0.01)
	var bot: Vector3 = Vector3(0.0, -0.04, 0.0)
	var ring: Array[Vector3] = [
		Vector3(0.18, 0.04, 0.02),
		Vector3(0.06, 0.06, 0.16),
		Vector3(-0.15, 0.05, 0.11),
		Vector3(-0.16, 0.04, -0.10),
		Vector3(0.05, 0.05, -0.15),
	]
	for i in range(ring.size()):
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % ring.size()]
		_add_tri(st, a, b, top, c_mid, c_mid, c_top)
		_add_tri(st, b, a, bot, c_mid, c_mid, c_bot)
	st.generate_normals()
	var m: ArrayMesh = st.commit()
	m.surface_set_material(0, mat)
	return m


func _create_fern_mesh(mat: Material) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Gradiente neutro luminoso para preservar o verde vivo das instâncias (evita samambaia escura!)
	var c0: Color = Color(0.55, 0.58, 0.52)
	var c1: Color = Color(0.98, 1.0, 0.94)
	for i in range(5):
		var a: float = float(i) * (TAU / 5.0)
		var dir: Vector3 = Vector3(cos(a), 0.0, sin(a))
		var side: Vector3 = Vector3(-dir.z, 0.0, dir.x)
		var p0: Vector3 = dir * 0.04 + Vector3(0.0, 0.02, 0.0)
		var p1: Vector3 = dir * 0.28 - side * 0.14 + Vector3(0.0, 0.24, 0.0)
		var p2: Vector3 = dir * 0.28 + side * 0.14 + Vector3(0.0, 0.24, 0.0)
		var p3: Vector3 = dir * 0.56 + Vector3(0.0, 0.16, 0.0)
		_add_tri(st, p0, p2, p1, c0, c1, c1)
		_add_tri(st, p1, p2, p3, c1, c1, c1)
	st.generate_normals()
	var m: ArrayMesh = st.commit()
	m.surface_set_material(0, mat)
	return m


static func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_color(cc)
	st.add_vertex(c)
