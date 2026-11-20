shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_schlick_ggx;

uniform vec4 team_color : source_color = vec4(0.18, 0.48, 0.96, 1.0);
uniform vec4 trim_color : source_color = vec4(0.92, 0.74, 0.24, 1.0);

void vertex() {
	// UV.x = 0 preso ao mastro, UV.x = 1 ponta livre que balança ao vento
	float pin = clamp(UV.x, 0.0, 1.0);
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float ph = wp.x * 0.41 + wp.z * 0.29;
	float wave = sin(TIME * 4.4 - UV.x * 5.8 + ph) * 0.095 + sin(TIME * 7.6 - UV.x * 9.5 + ph) * 0.032;
	float ripple_z = cos(TIME * 3.8 + UV.y * 4.0 + ph) * 0.025;
	VERTEX.z += wave * pin * pin + ripple_z * pin;
	VERTEX.y -= 0.05 * pin * pin;
}

void fragment() {
	// Recorte em flâmula medieval com cauda-de-andorinha
	float swallow_v = abs(UV.y - 0.5) * 2.0; // 0 no centro, 1 nas bordas sup/inf
	float cut_x = 1.0 - (1.0 - swallow_v) * 0.24 - swallow_v * 0.04;
	if (UV.x > cut_x) {
		discard;
	}

	float border_y = step(0.86, swallow_v);
	float border_tip = step(cut_x - 0.06, UV.x);
	float is_trim = clamp(border_y + border_tip, 0.0, 1.0);

	// Dobras de tecido e sombra sutil
	float fold = 0.86 + 0.14 * sin(TIME * 4.4 - UV.x * 5.8);
	vec3 col = mix(team_color.rgb * fold, trim_color.rgb, is_trim);

	ALBEDO = col;
	ROUGHNESS = mix(0.68, 0.34, is_trim);
	METALLIC = mix(0.0, 0.65, is_trim);
	EMISSION = team_color.rgb * (0.20 * (1.0 - is_trim)) + trim_color.rgb * (0.12 * is_trim);
}
