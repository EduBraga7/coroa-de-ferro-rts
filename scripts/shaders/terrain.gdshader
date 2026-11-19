shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_schlick_ggx;

uniform sampler2D baked_albedo : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap, repeat_enable;

varying vec3 v_world_pos;

float river_distance(vec2 xz) {
	float meander = sin((xz.x + xz.y) * 0.038) * 1.35 + cos((xz.x + xz.y) * 0.09) * 0.45;
	return abs(xz.x - xz.y + meander);
}

float hill_noise(vec2 p) {
	return sin(p.x * 1.3 + cos(p.y * 1.1)) * 0.5 + cos(p.y * 1.7 - sin(p.x * 0.9)) * 0.5;
}

float get_terrain_height(vec2 xz) {
	// Canal do rio ao longo de x == z
	float dr = river_distance(xz);
	float river_cut = (1.0 - smoothstep(2.2, 6.2, dr)) * -1.05;

	// Colinas e terraços panorâmicos fora da área jogável (além de 72m)
	float border_dist = max(abs(xz.x), abs(xz.y));
	float hills = 0.0;
	if (border_dist > 72.0) {
		float outer_mask = smoothstep(72.0, 104.0, border_dist);
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
	if (abs(h) > 0.001 || river_distance(wp.xz) < 7.0 || max(abs(wp.x), abs(wp.z)) > 71.5) {
		float eps = 0.5;
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
	vec2 world_uv = clamp((xz + 110.0) / 220.0, 0.0005, 0.9995);

	vec3 final_alb = texture(baked_albedo, world_uv).rgb;
	vec3 detail_nrm = texture(detail_normal, xz * 0.42).rgb;

	float dr = river_distance(xz);
	float wet_mask = 1.0 - smoothstep(2.5, 5.2, dr);
	float final_rough = mix(0.84, 0.28, wet_mask);

	ALBEDO = final_alb;
	NORMAL_MAP = detail_nrm;
	NORMAL_MAP_DEPTH = 1.15;
	ROUGHNESS = final_rough;
	METALLIC = 0.0;
}
