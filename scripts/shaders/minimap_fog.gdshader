shader_type canvas_item;
// Névoa de guerra do minimapa (mesmas texturas da névoa 3D). UV.y = 0 corresponde a z = -map_half (Norte).

uniform sampler2D vis_tex : filter_linear, repeat_disable;
uniform sampler2D vis_prev_tex : filter_linear, repeat_disable;
uniform sampler2D exp_tex : filter_linear, repeat_disable;
uniform sampler2D exp_prev_tex : filter_linear, repeat_disable;
uniform float blend = 1.0;
uniform float fog_enabled = 1.0;
uniform float map_half = 100.0;

void fragment() {
	if (fog_enabled < 0.5) {
		COLOR = vec4(0.0);
	} else {
		float vis = mix(texture(vis_prev_tex, UV).r, texture(vis_tex, UV).r, blend);
		float expl = mix(texture(exp_prev_tex, UV).r, texture(exp_tex, UV).r, blend);
		float expl_t = smoothstep(0.1, 0.8, expl);
		float a = mix(0.96, 0.45, expl_t);
		a = mix(a, 0.0, smoothstep(0.1, 0.9, vis));
		// Ardósia azulada (combina com a bruma 3D) em vez de preto; o explorado fica um véu mais escuro
		COLOR = vec4(mix(vec3(0.31, 0.35, 0.42), vec3(0.11, 0.13, 0.17), expl_t), a);
	}
}
