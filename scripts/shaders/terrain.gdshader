shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_schlick_ggx;

#include "res://scripts/shaders/world_common.gdshaderinc"

uniform sampler2D baked_albedo : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D splat_mask : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform sampler2D cobble_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D cobble_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D micro_detail : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float splat_ready = 0.0;
// Meia largura coberta pela textura baked (tools/generate_terrain_textures.py) e início das colinas de borda.
uniform float terrain_half = 130.0;
uniform float hills_start = 98.0;

varying vec3 v_world_pos;

float river_distance(vec2 xz) {
	float meander = sin((xz.x + xz.y) * 0.038) * 1.35 + cos((xz.x + xz.y) * 0.09) * 0.45;
	return abs(xz.x - xz.y + meander);
}

float hill_noise(vec2 p) {
	return sin(p.x * 1.3 + cos(p.y * 1.1)) * 0.5 + cos(p.y * 1.7 - sin(p.x * 0.9)) * 0.5;
}

float get_terrain_height(vec2 xz) {
	// Canal do rio ao longo de x == z (perfil suave para água sem serrilhado)
	float dr = river_distance(xz);
	float river_cut = (1.0 - smoothstep(1.8, 6.4, dr)) * -1.15;

	// Colinas panorâmicas fora da área jogável
	float border_dist = max(abs(xz.x), abs(xz.y));
	float hills = 0.0;
	if (border_dist > hills_start) {
		float outer_mask = smoothstep(hills_start, hills_start + 30.0, border_dist);
		float n = hill_noise(xz * 0.045) * 0.5 + 0.5;
		hills = outer_mask * (2.6 + n * 8.5) * smoothstep(4.0, 9.0, dr);
	}

	return river_cut + hills;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = get_terrain_height(wp.xz);
	VERTEX.y += h;
	wp.y += h;

	vec3 n = vec3(0.0, 1.0, 0.0);
	vec3 tang = vec3(1.0, 0.0, 0.0);
	vec3 binorm = vec3(0.0, 0.0, 1.0);
	if (abs(h) > 0.001 || river_distance(wp.xz) < 7.5 || max(abs(wp.x), abs(wp.z)) > hills_start - 0.5) {
		float eps = 0.45;
		float hx = get_terrain_height(wp.xz + vec2(eps, 0.0));
		float hz = get_terrain_height(wp.xz + vec2(0.0, eps));
		n = normalize(vec3(h - hx, eps, h - hz));
		tang = normalize(vec3(eps, hx - h, 0.0));
		binorm = normalize(vec3(0.0, hz - h, eps));
	}
	NORMAL = n;
	TANGENT = tang;
	BINORMAL = binorm;
	v_world_pos = wp;
}

void fragment() {
	vec2 xz = v_world_pos.xz;
	vec2 world_uv = clamp((xz + terrain_half) / (2.0 * terrain_half), 0.0005, 0.9995);

	vec3 base_alb = texture(baked_albedo, world_uv).rgb;
	vec3 detail_nrm = texture(detail_normal, xz * 0.38).rgb;
	vec3 final_alb = base_alb;
	vec3 final_nrm = detail_nrm;
	float nrm_depth = 1.15;
	float base_rough = 0.88;

	if (splat_ready > 0.5) {
		vec4 splat = texture(splat_mask, world_uv);
		// Multi-escala do micro detalhe para matar qualquer repetição no zoom próximo ou distante
		vec3 md_near = texture(micro_detail, xz * 0.26).rgb;
		vec3 md_far = texture(micro_detail, xz * 0.085 + vec2(0.37, 0.61)).rgb;
		vec3 md = mix(md_near, md_far, 0.35);

		float grass_w = clamp(1.0 - splat.r - splat.g * 0.8 - splat.b * 0.8, 0.0, 1.0);
		float mod_g = 1.0 + (md.r - 0.5) * 0.42 * grass_w;
		float mod_road = 1.0 + (md.g - 0.5) * 0.48 * splat.g;
		float mod_rock = 1.0 + (md.b - 0.5) * 0.52 * splat.b;
		final_alb = base_alb * (mod_g * mod_road * mod_rock);
		// Manchas macro (seca/viçosa) e verde natural: a grama 3D usa as mesmas funções e casa com o chão.
		// Sem "if" em volta: amostrar textura em ramo divergente quebra o mipmap nas bordas.
		vec3 graded = grade_grass(final_alb * grass_macro_tint(xz));
		final_alb = mix(final_alb, graded, grass_w);

		// Calçamento de alta nitidez com borda gasta e irregular: o ruído empurra o limite ~1 m para
		// dentro/fora e abre falhas de pedra, para a praça não parecer um disco perfeito.
		float edge_n = texture(world_noise, xz * 0.085 + vec2(0.13, 0.71)).r;
		float cobble_blend = smoothstep(0.16, 0.64, splat.r + (md.r - 0.5) * 0.26 * splat.r + (edge_n - 0.53) * 0.85);
		// Faixa de terra batida entre a grama e as pedras
		float worn = smoothstep(0.02, 0.30, cobble_blend) * (1.0 - smoothstep(0.30, 0.85, cobble_blend));
		final_alb = mix(final_alb, vec3(0.19, 0.145, 0.10) * (0.85 + md.g * 0.3), worn * 0.50);
		if (cobble_blend > 0.005) {
			vec2 cob_uv = xz * 0.31;
			vec3 c_alb = texture(cobble_albedo, cob_uv).rgb;
			vec3 c_nrm = texture(cobble_normal, cob_uv).rgb;
			// Tintura sutil do baked para manter variação orgânica de desgaste na praça
			vec3 macro_var = clamp(base_alb / vec3(0.33, 0.32, 0.30), vec3(0.75), vec3(1.22));
			c_alb *= mix(vec3(1.0), macro_var, 0.45);
			// Manchas de sujeira e pedras mais claras/escuras em escala de alguns metros
			c_alb *= mix(0.84, 1.07, edge_n);
			final_alb = mix(final_alb, c_alb, cobble_blend);
			final_nrm = mix(final_nrm, c_nrm, cobble_blend);
			nrm_depth = mix(nrm_depth, 1.45, cobble_blend);
			float stone_top = smoothstep(0.18, 0.42, dot(c_alb, vec3(0.333)));
			base_rough = mix(base_rough, mix(0.92, 0.66, stone_top), cobble_blend);
		}
		base_rough = mix(base_rough, 0.91, splat.g * 0.5);
	}

	float dr = river_distance(xz);
	float bed_ao = 1.0 - smoothstep(4.2, 5.5, dr);
	final_alb *= (1.0 - bed_ao * 0.24);
	float wet_mask = 1.0 - smoothstep(2.5, 5.2, dr);
	float final_rough = mix(base_rough, 0.22, wet_mask);

	ALBEDO = final_alb;
	NORMAL_MAP = final_nrm;
	NORMAL_MAP_DEPTH = nrm_depth;
	ROUGHNESS = final_rough;
	METALLIC = 0.0;
}
