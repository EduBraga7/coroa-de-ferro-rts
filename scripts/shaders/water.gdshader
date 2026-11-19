shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

varying vec3 v_world_pos;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	float p1 = wp.x * 0.85 + wp.z * 0.65 + t * 1.8;
	float p2 = wp.x * 1.45 - wp.z * 1.10 - t * 2.3;
	float ripple = (sin(p1) * 0.5 + sin(p2) * 0.5) * 0.04;
	VERTEX.y += ripple;
	v_world_pos = wp + vec3(0.0, ripple, 0.0);
}

void fragment() {
	vec2 xz = v_world_pos.xz;
	float t = TIME;

	float p1 = xz.x * 0.85 + xz.y * 0.65 + t * 1.8;
	float p2 = xz.x * 1.45 - xz.y * 1.10 - t * 2.3;
	float p3 = xz.x * 2.30 + xz.y * 1.85 + t * 2.8;
	float h0 = sin(p1) * 0.25 + sin(p2) * 0.18 + cos(p3) * 0.10 + 0.5;
	float dhdx = cos(p1) * 0.21 + cos(p2) * 0.26 - sin(p3) * 0.23;
	float dhdz = cos(p1) * 0.16 - cos(p2) * 0.20 - sin(p3) * 0.185;
	vec3 world_n = normalize(vec3(-dhdx * 0.28, 1.0, -dhdz * 0.28));
	NORMAL = normalize((VIEW_MATRIX * vec4(world_n, 0.0)).xyz);

	float fresnel = pow(max(0.0001, 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0)), 3.6);
	vec3 deep_water = vec3(0.04, 0.21, 0.34);
	vec3 shallow_water = vec3(0.11, 0.44, 0.54);
	vec3 sky_reflect = vec3(0.45, 0.70, 0.90);

	// Espuma nas bordas da faixa do rio (UV.x perto de 0 ou 1)
	float edge_dist = min(UV.x, 1.0 - UV.x) * 2.0;
	float edge_foam = smoothstep(0.24, 0.03, edge_dist + (h0 - 0.5) * 0.12);

	vec3 water_col = mix(shallow_water, deep_water, smoothstep(0.0, 0.45, edge_dist));
	water_col = mix(water_col, sky_reflect, clamp(fresnel * 0.85, 0.0, 0.85));
	water_col = mix(water_col, vec3(0.84, 0.93, 0.96), edge_foam * 0.65);

	ALBEDO = water_col;
	ROUGHNESS = mix(0.06, 0.35, edge_foam);
	METALLIC = 0.22;
	SPECULAR = 0.85;
	ALPHA = mix(0.82, 0.94, max(fresnel, edge_foam));
}
