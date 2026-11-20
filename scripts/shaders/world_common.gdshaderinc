// Funções compartilhadas pelo terreno e pela vegetação, para a grama 3D ter exatamente a cor do chão.
// O ruído vem de WorldLook.noise_texture() (FBM 256x256 sem emenda).
uniform sampler2D world_noise : hint_default_white, filter_linear_mipmap, repeat_enable;

// Manchas grandes de grama: secas/douradas (~50 m) e viçosas/frias, quebrando o verde uniforme.
// Limiares pela distribuição medida do ruído (mistura ~70/30: p25 = 0,43, p50 = 0,53, p90 = 0,70).
vec3 grass_macro_tint(vec2 xz) {
	float n1 = texture(world_noise, xz * 0.0061).r;
	float n2 = texture(world_noise, xz * 0.0215 + vec2(0.31, 0.77)).r;
	float n = n1 * 0.72 + n2 * 0.28;
	float dry = smoothstep(0.57, 0.70, n);
	float lush = 1.0 - smoothstep(0.36, 0.47, n);
	vec3 tint = mix(vec3(1.0), vec3(1.22, 1.06, 0.66), dry * 0.62);
	return mix(tint, vec3(0.80, 0.95, 0.94), lush * 0.42);
}

// Verde natural em vez de neon: tira um pouco da saturação e esquenta o tom.
vec3 grade_grass(vec3 c) {
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(l), c, 0.80);
	return c * vec3(1.07, 1.0, 0.86);
}
