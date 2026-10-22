shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx, shadows_disabled;
// Blood spots and pools lying on the sand. One MultiMesh quad per decal facing up. Instance custom:
// x dryness (0 fresh .. 1 dried), y alpha, z shape seed, w = (1 for a pool: bigger lobes, glossier) + 2 x palette slot.
// Palette slot 0 / 1 are the two fighters' blood colours (BloodFx sets them from the outfit blood palettes).
uniform vec3 fresh_c0 : source_color = vec3(0.48, 0.007, 0.017);
uniform vec3 old_c0 : source_color = vec3(0.17, 0.025, 0.021);
uniform float glow0 = 0.0;
uniform vec3 fresh_c1 : source_color = vec3(0.48, 0.007, 0.017);
uniform vec3 old_c1 : source_color = vec3(0.17, 0.025, 0.021);
uniform float glow1 = 0.0;

uniform float edge_soft = 0.2;  // width of the soft alpha fall-off at the rim (share of the radius)
uniform float rim_width = 0.3;  // width of the soaked, darker rim
uniform float rim_dark = 0.7;
uniform float wet_rough = 0.38;  // not mirror-like: a low value reflected the pale sky as pink blotches

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
	float a = smoothstep(wob, wob - edge_soft, d);
	float fresh = 1.0 - v_dry;
	bool second = v_pal > 0.5;
	vec3 fresh_c = second ? fresh_c1 : fresh_c0;
	vec3 old_c = second ? old_c1 : old_c0;
	float glow = second ? glow1 : glow0;
	vec3 col = mix(fresh_c, old_c, smoothstep(0.0, 1.0, v_dry));
	// Soaked rim: the sand drinks the edge, so it is darker (and not glossy); the middle stays a wet, lighter body
	// with slow mottling, so a pool is no longer one flat colour.
	float rim_t = smoothstep(wob - rim_width, wob - 0.02, d);
	float mott = vnoise(p * 3.1 + vec2(v_seed * 13.0, v_seed * 5.0));
	col *= 1.0 + 0.16 * (mott - 0.5) * (0.4 + v_pool);
	col = mix(col, col * vec3(0.5, 0.62, 0.7), rim_t * rim_dark);
	ALBEDO = col;
	ROUGHNESS = mix(wet_rough, 0.75, max(v_dry, 1.0 - smoothstep(0.25, 0.8, clamp(dot(NORMAL, VIEW), 0.0, 1.0))));
	// Fresnel at grazing view mirrors the pale sky and turns spots pink, so the sheen fades out at low view angles.
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	SPECULAR = (0.1 + 0.12 * v_pool) * fresh * (1.0 - rim_t) * smoothstep(0.25, 0.8, ndv);
	EMISSION = col * (0.04 * fresh + glow * fresh);
	ALPHA = a * v_alpha;
}
