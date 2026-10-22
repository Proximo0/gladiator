shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_disabled, shadows_disabled;
// Blood spots and pools lying on the sand. One MultiMesh quad per decal facing up. Instance custom:
// x dryness (0 fresh .. 1 dried), y alpha, z shape seed, w = (1 for a pool: bigger lobes, glossier) + 2 x palette slot.
// Palette slot 0 / 1 are the two fighters' blood colours (BloodFx sets them from the outfit blood palettes).
uniform vec3 fresh_c0 : source_color = vec3(0.48, 0.007, 0.017);
uniform vec3 old_c0 : source_color = vec3(0.17, 0.025, 0.021);
uniform float glow0 = 0.0;
uniform vec3 fresh_c1 : source_color = vec3(0.48, 0.007, 0.017);
uniform vec3 old_c1 : source_color = vec3(0.17, 0.025, 0.021);
uniform float glow1 = 0.0;

varying float v_dry;
varying float v_alpha;
varying float v_seed;
varying float v_pool;
varying float v_pal;

void vertex() {
	v_dry = clamp(INSTANCE_CUSTOM.x, 0.0, 1.0);
	v_alpha = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	v_seed = INSTANCE_CUSTOM.z;
	v_pal = step(1.5, INSTANCE_CUSTOM.w);
	v_pool = INSTANCE_CUSTOM.w - 2.0 * v_pal;
}

float h21(vec2 q) {
	return fract(sin(dot(q, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 q) {
	vec2 i = floor(q);
	vec2 f = fract(q);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	// A round blob with an irregular, noise-driven edge. No low-order angle lobes (they drew hearts) and no centre
	// gradient (overlapping decals showed a bright core each). The interior is flat and opaque so overlaps merge
	// into one continuous pool; only the rim is soft.
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	vec2 dir = p / max(d, 0.0001);
	float n = vnoise(dir * 2.2 + vec2(v_seed * 31.0, v_seed * 17.0)) * 0.6 + vnoise(dir * 5.5 + vec2(v_seed * 7.0, 3.0)) * 0.4;
	float rim = mix(0.05, 0.10, v_pool);
	float wob = 0.86 - rim + rim * 2.0 * n;
	float a = smoothstep(wob, wob - 0.10, d);
	float fresh = 1.0 - v_dry;
	bool second = v_pal > 0.5;
	vec3 fresh_c = second ? fresh_c1 : fresh_c0;
	vec3 old_c = second ? old_c1 : old_c0;
	float glow = second ? glow1 : glow0;
	vec3 col = mix(fresh_c, old_c, smoothstep(0.0, 1.0, v_dry));
	ALBEDO = col;
	ROUGHNESS = mix(0.3, 0.7, v_dry);
	SPECULAR = 0.0;
	EMISSION = col * (0.04 * fresh + glow * fresh);
	ALPHA = a * v_alpha;
}
