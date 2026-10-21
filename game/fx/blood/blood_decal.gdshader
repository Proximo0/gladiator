shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_disabled, shadows_disabled;
// Blood spots and pools lying on the sand. One MultiMesh quad per decal facing up. Instance custom:
// x dryness (0 fresh .. 1 dried), y alpha, z shape seed, w 1 for a pool (bigger lobes, glossier).

varying float v_dry;
varying float v_alpha;
varying float v_seed;
varying float v_pool;

void vertex() {
	v_dry = clamp(INSTANCE_CUSTOM.x, 0.0, 1.0);
	v_alpha = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	v_seed = INSTANCE_CUSTOM.z;
	v_pool = INSTANCE_CUSTOM.w;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float ang = atan(p.y, p.x);
	float lobes = mix(0.07, 0.14, v_pool);
	float wob = 0.80 + lobes * sin(ang * 3.0 + v_seed * 6.28) + lobes * 0.7 * sin(ang * 5.0 + v_seed * 11.0)
			+ 0.05 * sin(ang * 9.0 + v_seed * 23.0);
	float d = length(p);
	float a = smoothstep(wob, wob - 0.18, d);
	float fresh = 1.0 - v_dry;
	vec3 fresh_c = vec3(0.78, 0.012, 0.025);
	vec3 old_c = vec3(0.21, 0.03, 0.028);
	vec3 col = mix(fresh_c, old_c, pow(v_dry, 0.8));
	// thicker (darker, redder) in the middle
	col *= 1.0 - 0.32 * smoothstep(0.8, 0.0, d);
	ALBEDO = col;
	ROUGHNESS = mix(0.3, 0.7, v_dry);
	SPECULAR = 0.0;
	EMISSION = col * (0.32 * fresh);
	ALPHA = a * v_alpha;
}
