shader_type spatial;
render_mode cull_back;

// Sand floor: vertex displacement and normals from the deformation map, damp sand and blood from the blood map,
// procedural grain, sparkle, dunes and raked lines on top. Compatibility-renderer friendly (no compute, few fetches).

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D blood_tex : filter_linear, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float extent = 11.6;
uniform float map_n = 880.0;
uniform vec3 sand_light : source_color = vec3(0.72, 0.60, 0.45);
uniform vec3 sand_dark : source_color = vec3(0.62, 0.50, 0.37);
uniform vec3 blood_fresh : source_color = vec3(0.30, 0.008, 0.012);
uniform vec3 blood_dried : source_color = vec3(0.13, 0.03, 0.02);
uniform float grain_gain = 1.0;
uniform float sparkle_gain = 1.0;

varying vec3 lpos;
varying float v_sparkle;
varying float v_gloss;
varying vec2 v_jit;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Large scale shapes: raked strokes in patches and soft dunes. Metres.
float base_h(vec2 p) {
	float warp = 0.35 * sin(p.x * 0.9 + 1.3 * sin(p.y * 0.6)) + 0.2 * sin(p.y * 1.7 + p.x * 0.3);
	float across = dot(p, vec2(-0.34, 0.94)) + warp;
	float ridge = 0.5 + 0.5 * cos(across / 0.095 * 6.2832);
	ridge = pow(ridge, 1.6);
	float mask = smoothstep(-0.1, 0.55, sin(p.x * 0.23 + 0.7 * sin(p.y * 0.31)) + 0.6 * sin(p.y * 0.17 + 1.0) + 0.3 * sin(p.x * 0.7 - p.y * 0.5));
	float dunes = 0.018 * sin(p.x * 0.42 + 0.9 * sin(p.y * 0.28)) * sin(p.y * 0.37 + 0.5 * sin(p.x * 0.5)) + 0.006 * sin(p.x * 1.3 + p.y * 0.9);
	return ridge * mask * 0.0034 + dunes;
}

void vertex() {
	vec2 uv = (VERTEX.xz + vec2(extent)) / (2.0 * extent);
	float h = textureLod(height_tex, uv, 0.0).r;
	VERTEX.y += h;
	lpos = VERTEX;
}

void fragment() {
	vec2 wp = lpos.xz;
	vec2 uv = (wp + vec2(extent)) / (2.0 * extent);
	float e = 1.0 / map_n;
	float tm = 2.0 * extent / map_n;
	float hc = texture(height_tex, uv).r;
	float hl = texture(height_tex, uv - vec2(e, 0.0)).r;
	float hr = texture(height_tex, uv + vec2(e, 0.0)).r;
	float hd = texture(height_tex, uv - vec2(0.0, e)).r;
	float hu = texture(height_tex, uv + vec2(0.0, e)).r;
	vec2 g = vec2(hr - hl, hu - hd) / (2.0 * tm);
	float lap = (hl + hr + hd + hu) * 0.25 - hc;

	vec3 bt = texture(blood_tex, uv).rgb;
	float dist = length(VERTEX);
	float fade = 1.0 - smoothstep(7.0, 20.0, dist);

	// Procedural detail.
	vec4 n1 = texture(noise_tex, wp * 14.0);
	float n1x = texture(noise_tex, wp * 14.0 + vec2(1.0 / 256.0, 0.0)).r;
	float n1z = texture(noise_tex, wp * 14.0 + vec2(0.0, 1.0 / 256.0)).r;
	vec4 n2 = texture(noise_tex, wp * 2.3 + vec2(0.37, 0.11));
	float n2x = texture(noise_tex, wp * 2.3 + vec2(0.37 + 1.0 / 256.0, 0.11)).g;
	float n2z = texture(noise_tex, wp * 2.3 + vec2(0.37, 0.11 + 1.0 / 256.0)).g;
	vec4 n3 = texture(noise_tex, wp * 0.31);

	float bc = base_h(wp);
	float rake_fade = 1.0 - smoothstep(5.0, 15.0, dist);
	vec2 bg = rake_fade * vec2(base_h(wp + vec2(0.012, 0.0)) - bc, base_h(wp + vec2(0.0, 0.012)) - bc) / 0.012;

	// Blood coverage: soft map, crisp irregular edge from noise.
	float b = bt.r;
	float cov = smoothstep(0.22, 0.34, b + (n2.g - 0.5) * 0.30 + (n1.r - 0.5) * 0.12);
	float stain = smoothstep(0.015, 0.22, b + (n3.g - 0.5) * 0.1);
	float wet = bt.g * smoothstep(0.0, 0.1, bt.g);
	float dry = bt.b;

	// Grain gradient (metres of height per metre), damped under liquid and with distance.
	float calm = (1.0 - cov * 0.8) * (1.0 - wet * 0.35) * fade;
	vec2 grain = vec2(n1x - n1.r, n1z - n1.r) * 22.0 + vec2(n2x - n2.g, n2z - n2.g) * 2.2;
	grain *= grain_gain * calm;
	vec3 nl = normalize(vec3(-(g.x + bg.x + grain.x * 0.055), 1.0, -(g.y + bg.y + grain.y * 0.055)));
	nl = normalize(mix(nl, vec3(0.0, 1.0, 0.0), cov * 0.92));
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(nl, 0.0)).xyz);

	// Sand colour: broad variation, grain speckle, compaction, loose crest, ambient occlusion in hollows.
	vec3 sand = mix(sand_dark, sand_light, 0.35 + 0.3 * smoothstep(0.25, 0.75, n3.g * 0.75 + n2.g * 0.25));
	sand *= 0.88 + 0.24 * n1.r;
	sand *= 0.95 + 0.10 * n2.r;
	float cell = hash12(floor(wp * 190.0));
	vec2 gf = fract(wp * 190.0) - 0.5;
	float dot_mask = 1.0 - smoothstep(0.18, 0.42, length(gf));
	sand *= mix(1.0, 0.76, step(0.985, cell) * dot_mask * fade);
	vec2 gf2 = fract(wp * 260.0) - 0.5;
	sand *= mix(1.0, 1.12, step(0.97, hash12(floor(wp * 260.0) + 3.0)) * (1.0 - smoothstep(0.2, 0.45, length(gf2))) * fade);
	float ao = 1.0 - clamp(lap / 0.02, 0.0, 1.0) * 0.35;
	float compact = clamp(-hc * 9.0, 0.0, 0.3);
	sand *= ao * (1.0 - compact * 0.5);
	sand *= 1.0 + clamp(hc * 3.0, 0.0, 0.12);
	// Damp sand: darker, more saturated.
	sand = mix(sand, sand * sand * vec3(1.55, 1.35, 1.2) * 0.62, wet * 0.85);
	// Soaked stain, then pooled blood on top.
	vec3 soaked = sand * mix(vec3(0.55, 0.20, 0.15), vec3(0.38, 0.17, 0.12), dry);
	vec3 col = mix(sand, soaked, stain * 0.9);
	vec3 bcol = mix(blood_fresh, blood_dried, smoothstep(0.0, 1.0, dry));
	bcol *= 0.9 + 0.2 * n2.r;
	col = mix(col, bcol, cov);
	ALBEDO = col;

	float gloss = cov * (1.0 - dry * 0.75) + wet * 0.25;
	ROUGHNESS = 1.0;
	v_gloss = gloss;
	// Sparkle: rare glints from single grains, stable per grain.
	float sp = hash12(floor(wp * 230.0) + 17.0);
	v_jit = vec2(hash12(floor(wp * 230.0) + 5.0), hash12(floor(wp * 230.0) + 9.0)) - vec2(0.5);
	v_sparkle = step(0.993, sp) * (1.0 - smoothstep(0.15, 0.4, length(fract(wp * 230.0) - 0.5))) * (1.0 - cov) * (1.0 - wet * 0.6) * (1.0 - smoothstep(4.0, 14.0, dist)) * sparkle_gain;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	// Wrapped diffuse: sand scatters light into the shadow side a little.
	float wrap = clamp((ndl + 0.2) / 1.2, 0.0, 1.0);
	DIFFUSE_LIGHT += wrap * ATTENUATION * LIGHT_COLOR / PI;
	vec3 h = normalize(LIGHT + VIEW);
	float nh = max(dot(NORMAL, h), 0.0);
	float lit = max(ndl, 0.0) * ATTENUATION;
	float gl = v_gloss;
	SPECULAR_LIGHT += LIGHT_COLOR * lit * gl * (pow(nh, 48.0) * 2.2 + 0.03);
	// Sparkle uses the light and view only, so the grain flashes as the camera moves.
	float flash = pow(max(dot(normalize(NORMAL + vec3(v_jit.x, 0.0, v_jit.y) * 1.4), h), 0.0), 40.0);
	SPECULAR_LIGHT += LIGHT_COLOR * lit * v_sparkle * (0.4 + 2.2 * flash);
}
