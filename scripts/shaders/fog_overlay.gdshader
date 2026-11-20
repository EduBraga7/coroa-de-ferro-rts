shader_type spatial;
// Um único passe de tela cheia (sem depth_texture -> barato na RX 550) que desenha:
//  1. sombras de nuvens derivando devagar sobre o mapa;
//  2. vinheta suave nas bordas da tela;
//  3. névoa de guerra: bruma clara com volume onde nunca foi explorado e véu frio no explorado.
// A posição no mundo de cada pixel vem do raio da câmera cruzando o plano médio y = 0.8.
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_premul_alpha, shadows_disabled, fog_disabled;

uniform sampler2D vis_tex : filter_linear, repeat_disable;
uniform sampler2D vis_prev_tex : filter_linear, repeat_disable;
uniform sampler2D exp_tex : filter_linear, repeat_disable;
uniform sampler2D exp_prev_tex : filter_linear, repeat_disable;
// WorldLook.noise_texture(): FBM sem emenda (substitui o ruído por hash, bem mais caro por pixel)
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float map_half = 100.0;
uniform float blend = 1.0;
uniform float fog_enabled = 1.0;
uniform float explored_alpha = 0.40;
uniform float cloud_shadow_strength = 0.30;
uniform float vignette_strength = 0.24;
uniform vec3 mist_low : source_color = vec3(0.26, 0.31, 0.38);
uniform vec3 mist_high : source_color = vec3(0.66, 0.69, 0.72);
uniform vec3 mist_warm : source_color = vec3(0.92, 0.84, 0.70);
uniform vec3 memory_tint : source_color = vec3(0.20, 0.25, 0.33);

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec4 clip_pt = vec4(SCREEN_UV * 2.0 - 1.0, 0.5, 1.0);
	vec4 view_pt = INV_PROJECTION_MATRIX * clip_pt;
	view_pt.xyz /= view_pt.w;
	vec3 world_pt = (INV_VIEW_MATRIX * vec4(view_pt.xyz, 1.0)).xyz;
	vec3 cam_pos = CAMERA_POSITION_WORLD;
	vec3 ray_dir = normalize(world_pt - cam_pos);

	float ground_fade = smoothstep(0.0, -0.07, ray_dir.y);
	float t_hit = clamp((0.8 - cam_pos.y) / min(ray_dir.y, -0.015), 0.0, 420.0);
	vec2 wxz = cam_pos.xz + ray_dir.xz * t_hit;

	// 1. Nuvens: duas camadas com ventos levemente diferentes (~0,8 m/s), cobrindo ~1/3 do mapa.
	// Limiares pela distribuição medida do ruído (mistura 70/30: p50 = 0,53, p90 = 0,70).
	vec2 wind = vec2(0.82, 0.57);
	float c1 = texture(noise_tex, wxz * 0.0042 + wind * (TIME * 0.0034)).r;
	float c2 = texture(noise_tex, wxz * 0.0113 - wind.yx * (TIME * 0.0052) + vec2(0.37, 0.11)).r;
	float cloud = smoothstep(0.54, 0.68, c1 * 0.70 + c2 * 0.30);
	float shade = cloud * cloud_shadow_strength * ground_fade;

	// 2. Vinheta: escurece só os cantos e puxa o olho para o centro da ação
	vec2 vc = (SCREEN_UV - 0.5) * vec2(VIEWPORT_SIZE.x / max(VIEWPORT_SIZE.y, 1.0), 1.0);
	float vig = smoothstep(0.45, 1.10, length(vc)) * vignette_strength;
	shade = 1.0 - (1.0 - shade) * (1.0 - vig);

	// 3. Névoa de guerra
	vec3 fog_col = vec3(0.0);
	float fog_a = 0.0;
	if (fog_enabled > 0.5) {
		vec2 uv = clamp((wxz + map_half) / (2.0 * map_half), vec2(0.0), vec2(1.0));
		float vis_raw = mix(texture(vis_prev_tex, uv).r, texture(vis_tex, uv).r, blend);
		float expl_raw = mix(texture(exp_prev_tex, uv).r, texture(exp_tex, uv).r, blend);

		float m1 = texture(noise_tex, wxz * 0.0158 + vec2(TIME * 0.0042, -TIME * 0.0027)).r;
		float m2 = texture(noise_tex, wxz * 0.0467 - vec2(TIME * 0.0061, TIME * 0.0038) + vec2(0.52, 0.21)).r;
		float mist = clamp(m1 * 0.68 + m2 * 0.32, 0.0, 1.0);

		// Borda orgânica (esconde a escada da grade de 2 m) sem esconder unidades no limite da visão
		float jitter = (mist - 0.53) * 0.30;
		float vis = smoothstep(0.24, 0.86, vis_raw + jitter * 0.6);
		float expl = smoothstep(0.10, 0.74, expl_raw + jitter * 0.5);

		// Nunca explorado: vales frios, cristas claras e um toque do sol da tarde nas cristas
		float crest = smoothstep(0.30, 0.86, mist);
		vec3 unexplored = mix(mist_low, mist_high, crest);
		unexplored = mix(unexplored, mist_warm, smoothstep(0.64, 0.95, mist) * 0.30);
		// Explorado mas fora de visão: véu frio e translúcido (a lembrança do terreno)
		vec3 col = mix(unexplored, memory_tint, expl);
		float a = mix(0.95, explored_alpha, expl);
		// Filete claro na borda da bruma, como luz atravessando a neblina
		float unexp = (1.0 - expl) * (1.0 - vis);
		float rim = smoothstep(0.04, 0.45, unexp) * (1.0 - smoothstep(0.55, 0.95, unexp));
		col = mix(col, mist_high * 1.08, rim * 0.30);
		fog_col = col;
		fog_a = mix(a, 0.0, vis) * ground_fade;
	}

	// Composição pré-multiplicada: névoa por cima da cena já escurecida por nuvem e vinheta
	ALBEDO = fog_col * fog_a;
	ALPHA = 1.0 - (1.0 - fog_a) * (1.0 - shade);
}
