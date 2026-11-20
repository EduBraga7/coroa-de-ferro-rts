shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

// Equivalente ao StandardMaterial3D das árvores (albedo, normal map e rugosidade por textura)
// com vento suave na copa e variação leve de tom por árvore. Montado por WorldLook.apply_tree_wind().
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D texture_albedo : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D texture_roughness : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 roughness_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform sampler2D texture_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_scale = 1.0;
uniform float use_normal_map = 1.0;
uniform float metallic = 0.0;
uniform float specular = 0.5;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);
// Vento: deslocamento máximo (m) no alto da copa; o tronco abaixo de bend_start fica parado
uniform float wind_amplitude = 0.12;
uniform float bend_start = 1.0;
uniform float bend_end = 5.5;
// 1 = folhagem (recebe a variação de tom por árvore); 0 = casca
uniform float tint_amount = 1.0;

varying vec3 v_tint;

void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float seed = fract(sin(dot(origin.xz, vec2(12.9898, 78.233))) * 43758.5453);

	// Mesmo vento das nuvens (fog_overlay), levado para o espaço do modelo (cada árvore tem giro próprio)
	vec3 wind_w = normalize(vec3(0.82, 0.0, 0.57));
	vec3 wind_m = normalize(transpose(mat3(MODEL_MATRIX)) * wind_w);
	float bend = smoothstep(bend_start, bend_end, VERTEX.y);
	float t = TIME * 1.15 + seed * 6.2831;
	float gust = 0.55 + 0.45 * sin(TIME * 0.29 + origin.x * 0.045 + origin.z * 0.031);
	float sway = (sin(t) * 0.72 + sin(t * 2.37 + 1.7) * 0.28) * gust;
	// Tremor rápido e pequeno das folhas
	float flutter = sin(TIME * 5.3 + dot(VERTEX, vec3(3.1, 2.3, 2.7)) + seed * 20.0) * 0.18;
	VERTEX += wind_m * (sway + flutter * gust) * wind_amplitude * bend;
	VERTEX.y -= abs(sway) * wind_amplitude * bend * 0.15;

	// Nem toda árvore tem o mesmo verde: umas mais escuras, outras um pouco mais douradas
	vec3 tint = mix(vec3(0.88, 0.94, 0.90), vec3(1.07, 1.04, 0.88), seed);
	v_tint = mix(vec3(1.0), tint, tint_amount);
}

void fragment() {
	vec4 albedo_tex = texture(texture_albedo, UV);
	ALBEDO = albedo.rgb * albedo_tex.rgb * v_tint;
	METALLIC = metallic;
	SPECULAR = specular;
	ROUGHNESS = dot(texture(texture_roughness, UV), roughness_channel) * roughness;
	if (use_normal_map > 0.5) {
		NORMAL_MAP = texture(texture_normal, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
}
