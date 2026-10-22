shader_type spatial;
render_mode cull_back, ambient_light_disabled;

// Sand floor: vertex displacement and normals from the deformation map plus the permanent relief (wall drifts and
// heaps, base_tex), damp sand and blood from the blood map, procedural grain, pebbles, rake lines, wind ripples and
// sparkle on top. Compatibility-renderer friendly (no compute, few fetches).
// Ambient is supplied here (sand_ambient, a warm tint scaled by the scene's ambient energy): the sky's blue ambient
// times orange sand is olive green in shadow, so the shader never uses the engine's ambient.
// Colour rules: every tint is a multiplier on warm sand, never an additive or sky term. SPECULAR = 0 keeps the
// sky's blue reflection off the sand (it turned shaded and dim sand teal-green); damp sand darkens toward warm
// brown and blood-soaked sand is red (fresh 0.45,0.02,0.03 drying to 0.20,0.04,0.03).

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D base_tex : filter_linear, repeat_disable;  // R height, G dh/dx, B dh/dz of the permanent piles
uniform sampler2D blood_tex : filter_linear, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float extent = 11.6;
uniform float map_n = 880.0;
uniform vec3 sand_light : source_color = vec3(0.60, 0.54, 0.45);
uniform vec3 sand_dark : source_color = vec3(0.52, 0.46, 0.37);
uniform vec3 sand_buff : source_color = vec3(0.68, 0.62, 0.50);
uniform vec3 sand_ochre : source_color = vec3(0.58, 0.45, 0.31);
uniform vec3 blood_fresh : source_color = vec3(0.45, 0.02, 0.03);
uniform vec3 blood_dried : source_color = vec3(0.20, 0.04, 0.03);
// Second blood palette (the other fighter's blood); the blood map's alpha says which one a texel holds. blood_glow is
// the self-light of fresh ichor (0 for red).
uniform vec3 blood_fresh1 : source_color = vec3(0.45, 0.02, 0.03);
uniform vec3 blood_dried1 : source_color = vec3(0.20, 0.04, 0.03);
uniform float blood_glow = 0.0;
uniform float blood_glow1 = 0.0;
uniform float grain_gain = 1.0;
uniform float sparkle_gain = 1.0;
uniform float pebble_gain = 1.0;
uniform float arena_radius = 11.0;
uniform vec3 sand_ambient = vec3(0.52, 0.43, 0.38);
// Quality: 0 cheap (no fine grain slopes or rake lines either), 1 no pebbles, speckle or glints, 2 full.
uniform int detail = 2;
// Depth: the whole surface sits `lift` above the flat collider (fading out under the wall), hollows read darker and damper,
// berm crests lighter and drier.
uniform float lift = 0.03;
uniform float vtx_cell = 0.1;  // mesh vertex spacing: the vertex height is box-filtered over it so hollows do not alias into saw teeth
uniform float hollow_dark = 0.55;
uniform float rim_light = 0.3;
// Contact shadows: dark blobs under the fighters' feet and pelvis (x, z, radius, strength), packed by ContactShadow
// once a frame; the live ones come first and the first zero strength ends the list.
uniform vec4 contact[8];
uniform vec4 contact_bound = vec4(0.0);  // x, z, radius holding every live blob (ContactShadow.bound); radius 0 = none

varying vec3 lpos;
varying float v_sparkle;
varying float v_gloss;
varying vec2 v_jit;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Raked lines: straight strokes in some patches, concentric rings in others, soft dunes over all. Metres.
float base_h(vec2 p) {
	float warp = 0.35 * sin(p.x * 0.9 + 1.3 * sin(p.y * 0.6)) + 0.2 * sin(p.y * 1.7 + p.x * 0.3);
	float straight = dot(p, vec2(-0.34, 0.94)) + warp;
	float ring = length(p) + warp * 0.6;
	float sel = smoothstep(-0.15, 0.15, sin(p.x * 0.19 + 1.1 * sin(p.y * 0.23)) + 0.7 * sin(p.y * 0.14 + 2.0));
	float across = mix(straight, ring, sel);
	float ridge = 0.5 + 0.5 * cos(across / 0.085 * 6.2832);
	ridge = pow(ridge, 1.5);
	float mask = smoothstep(-0.2, 0.45, sin(p.x * 0.23 + 0.7 * sin(p.y * 0.31)) + 0.6 * sin(p.y * 0.17 + 1.0) + 0.3 * sin(p.x * 0.7 - p.y * 0.5));
	float dunes = 0.018 * sin(p.x * 0.42 + 0.9 * sin(p.y * 0.28)) * sin(p.y * 0.37 + 0.5 * sin(p.x * 0.5)) + 0.006 * sin(p.x * 1.3 + p.y * 0.9);
	return ridge * mask * 0.0028 + dunes;
}

void vertex() {
	vec2 uv = (VERTEX.xz + vec2(extent)) / (2.0 * extent);
	vec2 o = vec2(vtx_cell * 0.5 / (2.0 * extent));
	float hd = textureLod(height_tex, uv, 0.0).r * 0.4
			+ (textureLod(height_tex, uv + vec2(o.x, o.y), 0.0).r + textureLod(height_tex, uv + vec2(-o.x, o.y), 0.0).r
			+ textureLod(height_tex, uv + vec2(o.x, -o.y), 0.0).r + textureLod(height_tex, uv + vec2(-o.x, -o.y), 0.0).r) * 0.15;
	float h = hd + textureLod(base_tex, uv, 0.0).r;
	VERTEX.y += h + lift * (1.0 - smoothstep(arena_radius - 0.7, arena_radius + 0.2, length(VERTEX.xz)));
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
	vec4 bs = texture(base_tex, uv);
	float hb = bs.r;
	vec2 bgrad = bs.gb;

	vec4 bt4 = texture(blood_tex, uv);
	vec3 bt = bt4.rgb;
	// Which blood: sharpened so the seam between a red and an ichor pool stays a seam, not a grey blend.
	float bpal = smoothstep(0.35, 0.65, bt4.a);
	float dist = length(VERTEX);
	float fade = 1.0 - smoothstep(7.0, 20.0, dist);

	// Procedural detail.
	vec4 n1 = texture(noise_tex, wp * 14.0);
	vec4 n2 = texture(noise_tex, wp * 2.3 + vec2(0.37, 0.11));
	float n1x = n1.r;
	float n1z = n1.r;
	float n2x = n2.g;
	float n2z = n2.g;
	if (detail >= 1) {
		n1x = texture(noise_tex, wp * 14.0 + vec2(1.0 / 256.0, 0.0)).r;
		n1z = texture(noise_tex, wp * 14.0 + vec2(0.0, 1.0 / 256.0)).r;
		n2x = texture(noise_tex, wp * 2.3 + vec2(0.37 + 1.0 / 256.0, 0.11)).g;
		n2z = texture(noise_tex, wp * 2.3 + vec2(0.37, 0.11 + 1.0 / 256.0)).g;
	}
	vec4 n3 = texture(noise_tex, wp * 0.31);
	vec4 n4 = texture(noise_tex, wp * 0.071 + vec2(0.5, 0.2));

	float rake_fade = 1.0 - smoothstep(3.0, 10.0, dist);
	vec2 bg = vec2(0.0);
	float rake = 0.0;
	if (detail >= 1) {
		float bc = base_h(wp);
		bg = rake_fade * vec2(base_h(wp + vec2(0.012, 0.0)) - bc, base_h(wp + vec2(0.0, 0.012)) - bc) / 0.012;
		rake = clamp(bc * 220.0, -1.0, 1.0) * rake_fade;
	}

	// Blood coverage: soft map, crisp irregular edge from noise.
	float b = bt.r;
	float cov = smoothstep(0.22, 0.34, b + (n2.g - 0.5) * 0.30 + (n1.r - 0.5) * 0.12);
	float stain = smoothstep(0.015, 0.22, b + (n3.g - 0.5) * 0.1);
	float wet = bt.g * smoothstep(0.0, 0.1, bt.g);
	float dry = bt.b;

	// Piles: wind ripples along the contours of drifts and heaps.
	float pile = smoothstep(0.012, 0.08, hb);
	vec2 rdir = normalize(bgrad + vec2(0.0001));
	float rph = hb * 420.0 + (n3.b - 0.5) * 5.0 + dot(wp, vec2(0.7, 0.3)) * 1.5;
	vec2 ripple = rdir * (pile * 0.07 * cos(rph) * rake_fade);

	// Pebbles: one per sparse grid cell, a dome with a soft shadow ring around it.
	float pmask = 0.0;
	float pring = 0.0;
	vec2 pgrad = vec2(0.0);
	vec3 pcol = vec3(0.4, 0.33, 0.26);
	float pvis = fade * pebble_gain * (1.0 - smoothstep(0.003, 0.012, abs(hc))) * (1.0 - smoothstep(0.02, 0.06, hb)) * (1.0 - cov);
	if (detail >= 2 && pvis > 0.01) {
		vec2 cell = floor(wp / 0.42);
		if (hash12(cell + 71.0) > 0.72) {
			vec2 pc = (cell + 0.14 + 0.72 * vec2(hash12(cell + 3.1), hash12(cell + 8.7))) * 0.42;
			float pr = mix(0.008, 0.026, hash12(cell + 19.3) * hash12(cell + 2.2));
			vec2 dv = wp - pc;
			float d = length(dv);
			pmask = (1.0 - smoothstep(pr * 0.78, pr, d)) * pvis;
			pring = (1.0 - smoothstep(pr, pr * 2.2, d)) * pvis;
			pgrad = dv / pr * pmask * 1.1;
			float pk = hash12(cell + 33.3);
			pcol = mix(vec3(0.36, 0.29, 0.22), vec3(0.62, 0.52, 0.40), pk) * (0.8 + 0.4 * hash12(floor(wp * 400.0)));
			pcol = mix(pcol, vec3(0.5, 0.2, 0.12) * (0.7 + 0.3 * pk), step(0.88, pk) * 0.6);
		}
	}

	// Grain gradient (metres of height per metre), damped under liquid and with distance.
	float calm = (1.0 - cov * 0.8) * (1.0 - wet * 0.35) * fade;
	vec2 grain = vec2(n1x - n1.r, n1z - n1.r) * 22.0 + vec2(n2x - n2.g, n2z - n2.g) * 2.2;
	grain *= grain_gain * calm;
	vec2 slope = g + bgrad + bg + ripple + grain * 0.055 + pgrad * 0.5;
	vec3 nl = normalize(vec3(-slope.x, 1.0, -slope.y));
	nl = normalize(mix(nl, vec3(0.0, 1.0, 0.0), cov * 0.92));
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(nl, 0.0)).xyz);

	// Sand colour: warm base, ochre and buff patches, grain speckle, compaction, loose crests, hollows darker.
	vec3 sand = mix(sand_dark, sand_light, 0.35 + 0.3 * smoothstep(0.25, 0.75, n3.g * 0.75 + n2.g * 0.25));
	sand = mix(sand, sand_ochre, smoothstep(0.55, 0.78, n4.g * 0.7 + n3.b * 0.3) * 0.4);
	sand = mix(sand, sand_buff, smoothstep(0.52, 0.8, n4.b * 0.75 + n3.b * 0.25) * 0.35);
	sand *= 0.92 + 0.16 * n1.r;
	sand *= 0.96 + 0.08 * n2.r;
	if (detail >= 2) {
		float cell2 = hash12(floor(wp * 190.0));
		vec2 gf = fract(wp * 190.0) - 0.5;
		float dot_mask = 1.0 - smoothstep(0.18, 0.42, length(gf));
		sand *= mix(1.0, 0.72, step(0.985, cell2) * dot_mask * fade);
		vec2 gf2 = fract(wp * 260.0) - 0.5;
		sand *= mix(1.0, 1.14, step(0.97, hash12(floor(wp * 260.0) + 3.0)) * (1.0 - smoothstep(0.2, 0.45, length(gf2))) * fade);
	}
	float ao = 1.0 - clamp(lap / 0.02, 0.0, 1.0) * 0.35;
	float compact = clamp(-hc * 9.0, 0.0, 0.3);
	sand *= ao * (1.0 - compact * 0.5);
	sand *= 1.0 + clamp(hc * 3.0, 0.0, 0.12);
	// Depth read: hollows darker and damper (rim of the hollow falls off with the wall slope), crests lit and dry.
	float hollow = smoothstep(0.006, 0.09, -hc);
	sand = mix(sand, sand * vec3(0.66, 0.54, 0.43), hollow * hollow_dark);
	float crest = smoothstep(0.008, 0.06, hc);
	sand = mix(sand, sand_buff * (0.95 + 0.2 * n1.r), crest * rim_light * 0.25) * (1.0 + crest * rim_light * 0.12);
	sand *= 1.0 + rake * 0.04 + pile * (0.07 + 0.05 * cos(rph)) - pring * 0.16;
	sand *= 1.0 + clamp(hb * 2.5, 0.0, 0.5) * 0.35;
	// Contact shade where the sand meets the wall.
	sand *= mix(0.62, 1.0, smoothstep(0.0, 0.55, arena_radius - dist));
	sand = mix(sand, pcol, pmask);
	// Damp sand: darker and warmer (never a squared term: that only pushes the hue around).
	sand = mix(sand, sand * vec3(0.62, 0.48, 0.37), wet * 0.85 * (1.0 - stain));
	// Soaked stain, then pooled blood on top. The stain is the blood colour itself, lit by the sand's grain
	// (a multiplier on a red, never sand * orange: that read brown-olive and pink).
	vec3 bfresh = mix(blood_fresh, blood_fresh1, bpal);
	vec3 bdried = mix(blood_dried, blood_dried1, bpal);
	float bglow = mix(blood_glow, blood_glow1, bpal) * (1.0 - dry);
	vec3 bcol = mix(bfresh, bdried, smoothstep(0.0, 1.0, dry));
	float sand_lum = dot(sand, vec3(0.35, 0.45, 0.2));
	vec3 soaked = bcol * (0.55 + 0.9 * sand_lum);
	vec3 col = mix(sand, soaked, stain * (0.4 + 0.55 * smoothstep(0.05, 0.5, b)));
	bcol *= 0.9 + 0.2 * n2.r;
	col = mix(col, bcol, cov);
	// Contact shadows: each blob multiplies by 1 - strength * (1 - d²/r²)² (ContactShadow.shade_at mirrors this).
	float cshade = 1.0;
	vec2 cbd = wp - contact_bound.xy;
	int cn = dot(cbd, cbd) < contact_bound.z * contact_bound.z ? 8 : 0;
	for (int i = 0; i < cn; i++) {
		vec4 cb = contact[i];
		if (cb.w <= 0.0) {
			break;
		}
		vec2 cd = wp - cb.xy;
		float cq = clamp(1.0 - dot(cd, cd) / (cb.z * cb.z), 0.0, 1.0);
		cshade *= 1.0 - cb.w * cq * cq;
	}
	col *= cshade;
	ALBEDO = col;
	EMISSION = col * sand_ambient + bcol * bglow * cov;

	float gloss = cov * (1.0 - dry * 0.75) + wet * 0.2;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	v_gloss = gloss;
	// Sparkle: rare glints from single grains, stable per grain.
	v_jit = vec2(0.0);
	v_sparkle = 0.0;
	if (detail >= 2) {
	float sp = hash12(floor(wp * 230.0) + 17.0);
	v_jit = vec2(hash12(floor(wp * 230.0) + 5.0), hash12(floor(wp * 230.0) + 9.0)) - vec2(0.5);
	v_sparkle = step(0.993, sp) * (1.0 - smoothstep(0.15, 0.4, length(fract(wp * 230.0) - 0.5))) * (1.0 - cov) * (1.0 - wet * 0.6) * (1.0 - smoothstep(4.0, 14.0, dist)) * sparkle_gain;
	}
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
	// Wet sheen: a tight, faint highlight. Facing the low sun a flat pool is a mirror: anything stronger blows the whole
	// pool out to cream.
	SPECULAR_LIGHT += LIGHT_COLOR / PI * lit * gl * (pow(nh, 64.0) * 0.14 + 0.004);
	// Sparkle uses the light and view only, so the grain flashes as the camera moves.
	float flash = pow(max(dot(normalize(NORMAL + vec3(v_jit.x, 0.0, v_jit.y) * 1.4), h), 0.0), 40.0);
	SPECULAR_LIGHT += LIGHT_COLOR * lit * v_sparkle * (0.4 + 2.2 * flash);
}
