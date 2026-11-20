extends Node
class_name VFXManager

## Gerenciador central de efeitos visuais 3D (chamas, fumaça de chaminés, motes de sol,
## faíscas de combate, lascas de coleta e nuvens de poeira). Otimizado para Radeon RX 550.

const MAX_ACTIVE_BURSTS: int = 18

var _flame_shader: Shader = null
var _flame_mat_cache: Dictionary = {}
var _soft_puff_tex: ImageTexture = null
var _spark_tex: ImageTexture = null
var _quad_puff: QuadMesh = null
var _quad_spark: QuadMesh = null
var _active_bursts: int = 0


func _ready() -> void:
	_ensure_shared_resources()


func _ensure_shared_resources() -> void:
	if _flame_shader == null:
		_flame_shader = load("res://scripts/shaders/flame.gdshader") as Shader
	if _soft_puff_tex == null:
		_soft_puff_tex = _build_radial_texture(32, Color(1.0, 1.0, 1.0, 1.0), 1.8)
	if _spark_tex == null:
		_spark_tex = _build_radial_texture(16, Color(1.0, 0.92, 0.72, 1.0), 2.8)
	if _quad_puff == null:
		_quad_puff = QuadMesh.new()
		_quad_puff.size = Vector2(0.85, 0.85)
		var puff_mat: StandardMaterial3D = StandardMaterial3D.new()
		puff_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		puff_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		puff_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		puff_mat.vertex_color_use_as_albedo = true
		puff_mat.albedo_texture = _soft_puff_tex
		puff_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_quad_puff.material = puff_mat
	if _quad_spark == null:
		_quad_spark = QuadMesh.new()
		_quad_spark.size = Vector2(0.18, 0.18)
		var sp_mat: StandardMaterial3D = StandardMaterial3D.new()
		sp_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sp_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		sp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sp_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		sp_mat.vertex_color_use_as_albedo = true
		sp_mat.albedo_texture = _spark_tex
		sp_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_quad_spark.material = sp_mat


static func _build_radial_texture(size: int, tint: Color, falloff: float) -> ImageTexture:
	var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half: float = float(size - 1) * 0.5
	for y in range(size):
		for x in range(size):
			var dx: float = (float(x) - half) / half
			var dy: float = (float(y) - half) / half
			var r: float = sqrt(dx * dx + dy * dy)
			var a: float = pow(clampf(1.0 - r, 0.0, 1.0), falloff)
			img.set_pixel(x, y, Color(tint.r, tint.g, tint.b, a))
	return ImageTexture.create_from_image(img)


static func create_contact_ao_disc(radius: float, alpha_strength: float = 0.42) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(radius * 2.0, radius * 2.0)
	mi.mesh = pm
	mi.position.y = 0.018
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.albedo_color = Color(0.02, 0.03, 0.02, alpha_strength)
	mat.albedo_texture = _get_shared_ao_tex()
	mi.material_override = mat
	return mi


static var _shared_ao_tex: ImageTexture = null
static func _get_shared_ao_tex() -> ImageTexture:
	if _shared_ao_tex == null:
		_shared_ao_tex = _build_radial_texture(48, Color(0.0, 0.0, 0.0, 1.0), 1.65)
	return _shared_ao_tex


func create_torch_flame(scale_v: float = 1.0, intensity: float = 2.4) -> Node3D:
	_ensure_shared_resources()
	var root: Node3D = Node3D.new()
	root.name = "TorchFlame"
	if _flame_shader == null:
		return root

	var key: float = snappedf(intensity, 0.1)
	var mat: ShaderMaterial = _flame_mat_cache.get(key) as ShaderMaterial
	if mat == null:
		mat = ShaderMaterial.new()
		mat.shader = _flame_shader
		mat.set_shader_parameter("intensity", intensity)
		_flame_mat_cache[key] = mat

	var qm: QuadMesh = QuadMesh.new()
	qm.size = Vector2(0.46 * scale_v, 0.72 * scale_v)
	for yaw in [PI * 0.25, -PI * 0.25]:
		var quad: MeshInstance3D = MeshInstance3D.new()
		quad.mesh = qm
		quad.position.y = 0.28 * scale_v
		quad.rotation.y = yaw
		quad.material_override = mat
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		quad.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		root.add_child(quad)
	return root


func create_chimney_smoke(scale_v: float = 1.0) -> GPUParticles3D:
	_ensure_shared_resources()
	var p: GPUParticles3D = GPUParticles3D.new()
	p.name = "ChimneySmoke"
	p.amount = 7
	p.lifetime = 2.7
	p.randomness = 0.35
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.gi_mode = GeometryInstance3D.GI_MODE_DISABLED

	var pm: ParticleProcessMaterial = ParticleProcessMaterial.new()
	pm.direction = Vector3(0.28, 1.0, -0.18).normalized()
	pm.spread = 16.0
	pm.initial_velocity_min = 0.75 * scale_v
	pm.initial_velocity_max = 1.15 * scale_v
	pm.gravity = Vector3(0.22, 0.18, -0.14)
	pm.scale_min = 0.45 * scale_v
	pm.scale_max = 1.15 * scale_v
	pm.color = Color(0.76, 0.75, 0.73, 0.28)
	var grad: Gradient = Gradient.new()
	grad.set_color(0, Color(0.80, 0.78, 0.74, 0.0))
	grad.add_point(0.22, Color(0.78, 0.77, 0.74, 0.26))
	grad.set_color(1, Color(0.72, 0.74, 0.76, 0.0))
	var grad_tex: GradientTexture1D = GradientTexture1D.new()
	grad_tex.gradient = grad
	pm.color_ramp = grad_tex

	p.process_material = pm
	p.draw_pass_1 = _quad_puff
	return p


func attach_ambient_motes(camera_rig: Node3D) -> void:
	if camera_rig == null or DisplayServer.get_name() == "headless":
		return
	_ensure_shared_resources()
	var p: GPUParticles3D = GPUParticles3D.new()
	p.name = "AmbientSunMotes"
	p.amount = 22
	p.lifetime = 5.5
	p.preprocess = 2.0
	p.position = Vector3(0.0, 3.2, 0.0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.gi_mode = GeometryInstance3D.GI_MODE_DISABLED

	var pm: ParticleProcessMaterial = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(14.0, 2.8, 14.0)
	pm.direction = Vector3(0.6, 0.15, -0.4).normalized()
	pm.spread = 35.0
	pm.initial_velocity_min = 0.25
	pm.initial_velocity_max = 0.65
	pm.gravity = Vector3(0.0, 0.03, 0.0)
	pm.scale_min = 0.45
	pm.scale_max = 0.90
	var grad: Gradient = Gradient.new()
	grad.set_color(0, Color(1.0, 0.92, 0.62, 0.0))
	grad.add_point(0.45, Color(1.0, 0.92, 0.62, 0.42))
	grad.set_color(1, Color(1.0, 0.88, 0.55, 0.0))
	var grad_tex: GradientTexture1D = GradientTexture1D.new()
	grad_tex.gradient = grad
	pm.color_ramp = grad_tex

	p.process_material = pm
	p.draw_pass_1 = _quad_spark
	camera_rig.add_child(p)


func spawn_hit_sparks(pos: Vector3) -> void:
	_spawn_burst(pos + Vector3(0.0, 0.85, 0.0), Color(1.0, 0.80, 0.30, 0.95), Color(1.0, 0.40, 0.10, 0.0), 7, 0.34, 2.8, 0.85, true)


func spawn_gather_chips(res_type: String, pos: Vector3) -> void:
	var c0: Color = Color(0.65, 0.42, 0.20, 0.90)
	var c1: Color = Color(0.45, 0.28, 0.12, 0.0)
	var additive: bool = false
	match res_type:
		"gold":
			c0 = Color(1.0, 0.86, 0.26, 0.95)
			c1 = Color(1.0, 0.65, 0.12, 0.0)
			additive = true
		"stone":
			c0 = Color(0.76, 0.75, 0.72, 0.88)
			c1 = Color(0.55, 0.54, 0.52, 0.0)
		"food":
			c0 = Color(0.32, 0.68, 0.24, 0.85)
			c1 = Color(0.24, 0.52, 0.16, 0.0)
	_spawn_burst(pos + Vector3(0.0, 0.65, 0.0), c0, c1, 5, 0.42, 2.1, 0.75, additive)


func spawn_dust_burst(pos: Vector3, radius: float = 2.5) -> void:
	_spawn_burst(pos + Vector3(0.0, 0.25, 0.0), Color(0.68, 0.60, 0.48, 0.50), Color(0.55, 0.48, 0.38, 0.0), 10, 0.95, 1.4 + radius * 0.25, 1.25 + radius * 0.22, false)


func _spawn_burst(pos: Vector3, c0: Color, c1: Color, amount: int, life: float, spd: float, sc: float, additive: bool) -> void:
	if not is_inside_tree() or _active_bursts >= MAX_ACTIVE_BURSTS or DisplayServer.get_name() == "headless":
		return
	_ensure_shared_resources()
	_active_bursts += 1

	var p: GPUParticles3D = GPUParticles3D.new()
	p.position = pos
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.92
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.gi_mode = GeometryInstance3D.GI_MODE_DISABLED

	var pm: ParticleProcessMaterial = ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 72.0
	pm.initial_velocity_min = spd * 0.55
	pm.initial_velocity_max = spd
	pm.gravity = Vector3(0.0, -5.2 if additive else -1.2, 0.0)
	pm.scale_min = sc * 0.65
	pm.scale_max = sc
	var grad: Gradient = Gradient.new()
	grad.set_color(0, c0)
	grad.set_color(1, c1)
	var gt: GradientTexture1D = GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt

	p.process_material = pm
	p.draw_pass_1 = _quad_spark if additive else _quad_puff
	add_child(p)
	p.emitting = true

	get_tree().create_timer(life + 0.25).timeout.connect(func() -> void:
		_active_bursts = maxi(0, _active_bursts - 1)
		if is_instance_valid(p):
			p.queue_free()
	)
