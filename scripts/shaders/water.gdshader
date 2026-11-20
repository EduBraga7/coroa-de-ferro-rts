shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;

varying vec3 v_world_pos;

// Centros das pontes (RTSUnit.BRIDGES, enviados por main.gd) para a esteira de espuma nos pilares
uniform vec2 bridge_pos[4];

float river_distance(vec2 xz) {
	float meander = sin((xz.x + xz.y) * 0.038) * 1.35 + cos((xz.x + xz.y) * 0.09) * 0.45;
	return abs(xz.x - xz.y + meander);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	float p1 = wp.x * 0.72 + wp.z * 0.55 + t * 1.45;
	float p2 = wp.x * 1.25 - wp.z * 0.98 - t * 1.95;
	float ripple = (sin(p1) * 0.5 + sin(p2) * 0.5) * 0.028;
	VERTEX.y += ripple;
	v_world_pos = wp + vec3(0.0, ripple, 0.0);
}

void fragment() {
	vec2 xz = v_world_pos.xz;
	float t = TIME;
	float dr = river_distance(xz);

	// Corrente principal flui ao longo da diagonal do rio (x + z)
	float flow = (xz.x + xz.y) * 0.48 - t * 0.92;
	float cross_v = (xz.x - xz.y) * 0.65;

	float p1 = xz.x * 0.85 + xz.y * 0.65 + t * 1.65;
	float p2 = xz.x * 1.45 - xz.y * 1.10 - t * 2.10;
	float p3 = xz.x * 2.40 + xz.y * 1.90 + t * 2.65;
	float p4 = flow * 2.8 + sin(cross_v * 1.7 + t * 0.8) * 1.2;
	float p5 = xz.x * 4.1 - xz.y * 3.5 - t * 3.1;

	float h0 = sin(p1) * 0.22 + sin(p2) * 0.16 + cos(p3) * 0.10 + sin(p4) * 0.08 + cos(p5) * 0.05 + 0.5;
	float dhdx = cos(p1) * 0.19 + cos(p2) * 0.23 - sin(p3) * 0.24 + cos(p4) * 0.12 - sin(p5) * 0.16;
	float dhdz = cos(p1) * 0.14 - cos(p2) * 0.17 - sin(p3) * 0.19 + cos(p4) * 0.12 + sin(p5) * 0.14;

	float shore_wave = (h0 - 0.5) * 0.22;
	float bank_edge = 1.0 - smoothstep(4.36, 4.90, dr + shore_wave);
	if (bank_edge <= 0.002) {
		discard;
	}

	vec3 world_n = normalize(vec3(-dhdx * 0.30, 1.0, -dhdz * 0.30));
	NORMAL = normalize((VIEW_MATRIX * vec4(world_n, 0.0)).xyz);

	float fresnel = pow(max(0.0001, 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0)), 3.4);
	float depth_t = clamp((4.85 - dr) / 3.2, 0.0, 1.0);

	// Rio de vale: verde-azulado e profundo, não ciano de piscina
	vec3 shallow_water = vec3(0.10, 0.28, 0.26);
	vec3 deep_water = vec3(0.025, 0.095, 0.13);
	vec3 sky_reflect = vec3(0.50, 0.62, 0.70);
	vec3 sun_warm = vec3(1.0, 0.88, 0.65);

	// Cáusticas animadas sutis visíveis na água rasa e média
	float c1 = sin(flow * 2.1 + sin(cross_v * 2.6 + t * 0.9) * 1.4);
	float c2 = cos(flow * 3.1 - cross_v * 2.3 + t * 1.3);
	float caustics = pow(clamp(0.5 + 0.5 * (c1 * c2), 0.0, 1.0), 4.0) * (1.0 - depth_t * 0.55);

	// Espuma orgânica acompanhando o meandro exato do rio
	float foam_noise = h0 * 0.7 + 0.3 * sin(flow * 3.4 + cross_v * 2.1);
	float bank_foam = smoothstep(4.12, 4.65, dr + (foam_noise - 0.5) * 0.35) * (1.0 - smoothstep(4.74, 4.92, dr));

	// Esteira de espuma ao redor dos pilares das pontes
	float d_bridge = 1.0e6;
	for (int i = 0; i < 4; i++) {
		d_bridge = min(d_bridge, length(xz - bridge_pos[i]));
	}
	float pier_ring = smoothstep(6.0, 3.8, d_bridge) * smoothstep(2.0, 4.4, d_bridge);
	float bridge_wake = pier_ring * smoothstep(0.52, 0.82, foam_noise) * 0.75;

	float foam = clamp(bank_foam * 0.82 + bridge_wake, 0.0, 1.0);

	// Brilho especular direcional dourado do sol sobre as marolas
	vec3 sun_dir_w = normalize(vec3(0.52, 0.62, 0.58));
	vec3 sun_dir_v = normalize((VIEW_MATRIX * vec4(sun_dir_w, 0.0)).xyz);
	vec3 half_v = normalize(VIEW + sun_dir_v);
	float glint = pow(max(dot(NORMAL, half_v), 0.0), 96.0) * (1.0 - foam);

	vec3 water_col = mix(shallow_water, deep_water, smoothstep(0.0, 0.78, depth_t));
	water_col += vec3(0.10, 0.24, 0.22) * caustics * 0.55;
	water_col = mix(water_col, sky_reflect, clamp(fresnel * 0.82, 0.0, 0.82));
	water_col = mix(water_col, vec3(0.88, 0.94, 0.96), foam * 0.72);
	water_col += sun_warm * glint * 0.65;

	ALBEDO = water_col;
	// Reflexo do céu mais contido: era ele que deixava o rio inteiro azul-claro vista de cima
	ROUGHNESS = mix(0.08, 0.38, foam);
	METALLIC = 0.06;
	SPECULAR = 0.55;
	// Apenas os picos estreitos de reflexo solar ativam bloom seletivo (>1.15)
	EMISSION = sun_warm * smoothstep(0.32, 0.85, glint) * 1.45;
	ALPHA = bank_edge * mix(0.62, 0.94, max(depth_t * 0.84, max(fresnel * 0.88, foam)));
}
