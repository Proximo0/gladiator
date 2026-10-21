shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;
// Blood stain on a body or weapon: an irregular wet blob, glossy, with a darker core.

uniform float seed = 0.0;
uniform vec3 blood_color : source_color = vec3(0.30, 0.01, 0.015);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float ang = atan(p.y, p.x);
	float wob = 0.78 + 0.13 * sin(ang * 3.0 + seed * 6.28) + 0.09 * sin(ang * 7.0 + seed * 17.0);
	float d = length(p);
	float a = smoothstep(wob, wob - 0.22, d);
	ALBEDO = blood_color * (1.0 - 0.45 * smoothstep(0.7, 0.0, d));
	ROUGHNESS = 0.12;
	SPECULAR = 0.9;
	ALPHA = a * 0.92;
}
