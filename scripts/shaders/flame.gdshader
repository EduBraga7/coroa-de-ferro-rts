shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float intensity = 2.4;

void vertex() {
	// Ondulação suave da ponta da chama (base em UV.y = 1.0 fica fixa, ponta em UV.y = 0.0 dança)
	float tip = 1.0 - UV.y;
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float ph = wp.x * 1.7 + wp.z * 2.3;
	float sway = sin(TIME * 11.5 + ph + tip * 4.5) * 0.06 + cos(TIME * 17.0 - ph) * 0.03;
	VERTEX.x += sway * tip;
	VERTEX.z += cos(TIME * 10.2 + ph) * 0.04 * tip;
}

void fragment() {
	vec2 uv = UV;
	float y_up = 1.0 - uv.y; // 0 na base -> 1 no topo
	float x_c = (uv.x - 0.5) * 2.0;

	float ph = fract(sin(dot(NODE_POSITION_WORLD.xz, vec2(12.9898, 78.233))) * 43758.5453) * 6.283;
	float wave = sin(y_up * 7.5 - TIME * 12.0 + ph) * 0.14 * y_up
	           + sin(y_up * 13.0 - TIME * 18.0 + x_c * 3.0) * 0.07 * y_up;

	float half_w = mix(0.68, 0.06, pow(y_up, 0.85));
	float dx = abs(x_c + wave) / max(0.04, half_w);
	float v_mask = smoothstep(0.0, 0.14, y_up) * (1.0 - smoothstep(0.55, 1.0, y_up));
	float shape = clamp(1.0 - dx * dx, 0.0, 1.0) * v_mask;

	// Faísca/língua interna
	float core = pow(shape, 2.2) * (1.0 - y_up * 0.45);
	vec3 c_outer = vec3(1.0, 0.24, 0.03);
	vec3 c_mid = vec3(1.0, 0.62, 0.12);
	vec3 c_core = vec3(1.0, 0.95, 0.68);
	vec3 col = mix(c_outer, c_mid, smoothstep(0.15, 0.65, shape));
	col = mix(col, c_core, clamp(core * 1.4, 0.0, 1.0));

	float a = smoothstep(0.08, 0.55, shape);
	ALBEDO = col * intensity;
	ALPHA = a;
}
