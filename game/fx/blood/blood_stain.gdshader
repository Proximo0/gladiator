shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;
// Blood stain on a body, clothing or weapon: an irregular wet blob, glossy, darker core. The colour comes from
// the material (BloodFx swaps the fresh / drying / dried materials as the stain ages).

uniform float seed = 0.0;
uniform vec3 blood_color : source_color = vec3(0.86, 0.02, 0.035);
uniform float gloss = 0.9;
uniform float glow = 0.3;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float ang = atan(p.y, p.x);
	float wob = 0.78 + 0.13 * sin(ang * 3.0 + seed * 6.28) + 0.09 * sin(ang * 7.0 + seed * 17.0);
	float d = length(p);
	float a = smoothstep(wob, wob - 0.22, d);
	vec3 col = blood_color * (1.0 - 0.38 * smoothstep(0.7, 0.0, d));
	ALBEDO = col;
	ROUGHNESS = mix(0.55, 0.14, gloss);
	SPECULAR = 0.1 + 0.15 * gloss;
	EMISSION = col * glow;
	ALPHA = a * 0.95;
}
