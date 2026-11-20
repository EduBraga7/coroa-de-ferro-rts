extends RefCounted
class_name WorldLook

## Recursos visuais compartilhados pelo terreno, pela vegetação e pela névoa/nuvens.
## Cada textura é criada uma vez e reaproveitada (sem VRAM duplicada nem draw calls a mais).
##
## Direção de arte (docs/DESIGN.md "Visual"): tarde dourada de verão, medieval realista e acolhedora.
## Sol quente de lado, sombras levantadas pelo céu frio, grama com manchas secas/viçosas,
## bruma clara na névoa de guerra e sombras de nuvens passando devagar.

static var _noise: NoiseTexture2D = null
static var _mipmapped: Dictionary = {}
static var _tree_wind_shader: Shader = null
static var _tree_wind_cache: Dictionary = {}


## Ruído FBM 256x256 que se repete sem emenda. Usado em escala de dezenas de metros:
## manchas de grama, sombras de nuvens e volume da bruma.
static func noise_texture() -> NoiseTexture2D:
	if _noise == null:
		var fn: FastNoiseLite = FastNoiseLite.new()
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.seed = 1337
		fn.frequency = 0.011
		fn.fractal_type = FastNoiseLite.FRACTAL_FBM
		fn.fractal_octaves = 4
		fn.fractal_lacunarity = 2.0
		fn.fractal_gain = 0.5
		var tex: NoiseTexture2D = NoiseTexture2D.new()
		tex.width = 256
		tex.height = 256
		tex.seamless = true
		tex.generate_mipmaps = true
		tex.normalize = true
		tex.noise = fn
		_noise = tex
	return _noise


## Carrega uma textura do projeto garantindo mipmaps (as texturas do terreno são importadas sem).
## A mesma instância é devolvida para todos que pedirem o mesmo caminho.
static func load_mipmapped(path: String) -> Texture2D:
	if _mipmapped.has(path):
		return _mipmapped[path] as Texture2D
	var tex: Texture2D = load(path) as Texture2D
	if tex != null:
		var img: Image = tex.get_image()
		if img != null and not img.has_mipmaps():
			img.generate_mipmaps()
			tex = ImageTexture.create_from_image(img)
	_mipmapped[path] = tex
	return tex


## Troca os materiais de uma árvore (casca e folhas) por variantes com vento suave na copa e
## leve variação de tom por árvore (tree_wind.gdshader). As variantes ficam em cache por material
## de origem, então todas as árvores continuam compartilhando poucos materiais (sem draw calls a mais).
static func apply_tree_wind(root: Node) -> void:
	if _tree_wind_shader == null:
		_tree_wind_shader = load("res://scripts/shaders/tree_wind.gdshader") as Shader
		if _tree_wind_shader == null:
			return
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var src: StandardMaterial3D = mi.get_active_material(s) as StandardMaterial3D
			if src != null:
				mi.set_surface_override_material(s, _tree_wind_variant(src))


static func _tree_wind_variant(src: StandardMaterial3D) -> ShaderMaterial:
	if _tree_wind_cache.has(src):
		return _tree_wind_cache[src] as ShaderMaterial
	var sm: ShaderMaterial = ShaderMaterial.new()
	sm.shader = _tree_wind_shader
	sm.set_shader_parameter("albedo", src.albedo_color)
	sm.set_shader_parameter("texture_albedo", src.albedo_texture)
	sm.set_shader_parameter("roughness", src.roughness)
	sm.set_shader_parameter("texture_roughness", src.roughness_texture)
	var ch: Vector4 = Vector4(1.0, 0.0, 0.0, 0.0)
	match src.roughness_texture_channel:
		BaseMaterial3D.TEXTURE_CHANNEL_GREEN:
			ch = Vector4(0.0, 1.0, 0.0, 0.0)
		BaseMaterial3D.TEXTURE_CHANNEL_BLUE:
			ch = Vector4(0.0, 0.0, 1.0, 0.0)
		BaseMaterial3D.TEXTURE_CHANNEL_ALPHA:
			ch = Vector4(0.0, 0.0, 0.0, 1.0)
		BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE:
			ch = Vector4(0.333, 0.333, 0.333, 0.0)
	sm.set_shader_parameter("roughness_channel", ch)
	var has_normal: bool = src.normal_enabled and src.normal_texture != null
	sm.set_shader_parameter("use_normal_map", 1.0 if has_normal else 0.0)
	if has_normal:
		sm.set_shader_parameter("texture_normal", src.normal_texture)
		sm.set_shader_parameter("normal_scale", src.normal_scale)
	sm.set_shader_parameter("metallic", src.metallic)
	sm.set_shader_parameter("specular", src.metallic_specular)
	sm.set_shader_parameter("uv1_scale", src.uv1_scale)
	sm.set_shader_parameter("uv1_offset", src.uv1_offset)
	sm.set_shader_parameter("tint_amount", 1.0 if String(src.resource_name).contains("Foliage") else 0.0)
	_tree_wind_cache[src] = sm
	return sm
