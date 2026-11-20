shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_schlick_ggx;

#include "res://scripts/shaders/world_common.gdshaderinc"

// Vegetação instanciada (MultiMesh): vento, cor casada com o chão e sumiço suave à distância.
uniform float wind_strength = 0.08;
uniform float wind_speed = 1.85;
uniform float roughness_val = 0.78;
// 1 = pega a cor do terreno embaixo (grama, samambaia); 0 = cor própria do vértice/instância (flores)
uniform float ground_match = 0.0;
// Altura do modelo (m) para o degradê raiz escura -> ponta clara
uniform float blade_height = 0.35;
// A planta encolhe até sumir entre estas distâncias da câmera: longe ela teria 1-2 px (só ruído e custo)
uniform float fade_start = 44.0;
uniform float fade_end = 60.0;
uniform sampler2D ground_albedo : source_color, filter_linear_mipmap, repeat_disable;
uniform float terrain_half = 130.0;

varying vec3 v_ground;
varying float v_h;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float fade = 1.0 - smoothstep(fade_start, fade_end, distance(CAMERA_POSITION_WORLD, origin));
	v_h = clamp(VERTEX.y / blade_height, 0.0, 1.0);
	VERTEX *= fade;

	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h_factor = clamp(VERTEX.y * 1.4, 0.0, 1.5);
	float sway_weight = h_factor * h_factor;
	float phase = TIME * wind_speed + wp.x * 0.34 + wp.z * 0.27;
	float gust = sin(TIME * 0.72 + wp.x * 0.09 - wp.z * 0.11) * 0.5 + 0.5;
	float disp = (sin(phase) + 0.35 * sin(phase * 2.13 + 1.1)) * wind_strength * (0.65 + 0.65 * gust) * sway_weight;
	VERTEX.x += disp;
	VERTEX.z += disp * 0.58;

	v_ground = vec3(0.0);
	if (ground_match > 0.0) {
		vec2 uv = clamp((origin.xz + terrain_half) / (2.0 * terrain_half), vec2(0.0005), vec2(0.9995));
		vec3 g = textureLod(ground_albedo, uv, 2.0).rgb;
		// Pequena variação por touceira (sem custo de memória: hash da posição)
		float var_n = fract(sin(dot(origin.xz, vec2(12.9898, 78.233))) * 43758.5453);
		v_ground = grade_grass(g * grass_macro_tint(origin.xz)) * mix(0.90, 1.12, var_n);
	}
}

void fragment() {
	// Godot inverte a normal das faces de trás com cull_disabled; desfaz isso para os dois lados
	// receberem a luz de cima (antes as flores e metade das folhas ficavam quase pretas).
	vec3 n = FRONT_FACING ? NORMAL : -NORMAL;
	vec3 up_v = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	NORMAL = normalize(mix(n, up_v, 0.78));

	vec3 own = COLOR.rgb;
	// Raiz um pouco mais escura que o chão, ponta mais clara e quente (luz do sol na ponta da folha)
	vec3 matched = v_ground * mix(0.80, 1.34, v_h) + vec3(0.025, 0.02, 0.0) * v_h;
	ALBEDO = mix(own, matched, ground_match);
	ROUGHNESS = roughness_val;
	METALLIC = 0.0;
	SPECULAR = 0.25;
}
