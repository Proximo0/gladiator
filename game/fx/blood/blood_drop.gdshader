shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Glossy blood droplet. Instance custom: xyz velocity, w radius. Instance colour: r stretch factor, g shade.
// Orients and stretches the unit rounded drop along the velocity in the vertex stage. Fresh arterial red:
// saturated, self-lit enough to stay red in shade, with a wet specular highlight.

uniform vec3 blood_bright : source_color = vec3(0.98, 0.03, 0.05);
uniform vec3 blood_dark : source_color = vec3(0.52, 0.0, 0.025);
uniform float stretch_time = 0.006;
uniform float tail_cap = 7.0;

varying float v_thick;
varying float v_shade;

void vertex() {
	vec3 vel = INSTANCE_CUSTOM.xyz;
	float r = max(INSTANCE_CUSTOM.w, 0.0005);
	float sp = length(vel);
	vec3 d = sp > 0.05 ? vel / sp : vec3(0.0, -1.0, 0.0);
	vec3 up = abs(d.y) > 0.95 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
	vec3 ax = normalize(cross(up, d));
	vec3 ay = cross(d, ax);
	float tail = min(r + sp * stretch_time * COLOR.r, r * tail_cap);
	float zs = VERTEX.z > 0.0 ? r : tail;
	VERTEX = ax * VERTEX.x * r + ay * VERTEX.y * r + d * VERTEX.z * zs;
	vec3 n = ax * NORMAL.x / r + ay * NORMAL.y / r + d * NORMAL.z / zs;
	NORMAL = normalize(n);
	v_thick = clamp(r / 0.012, 0.0, 1.0);
	v_shade = COLOR.g;
}

void fragment() {
	float fr = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float dark = clamp(v_thick * 0.3 + v_shade * 0.25, 0.0, 0.55);
	vec3 col = mix(blood_bright, blood_dark, dark);
	ALBEDO = col;
	ROUGHNESS = 0.04;
	SPECULAR = 1.0;
	METALLIC = 0.0;
	// glints: a wet highlight toward the sky, so drops catch the light
	vec3 up_v = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	float hl = pow(max(dot(NORMAL, normalize(up_v * 0.8 + vec3(0.35, 0.2, 0.5))), 0.0), 22.0);
	EMISSION = col * 0.32 + vec3(0.55, 0.03, 0.04) * fr * 0.5 + vec3(0.9, 0.2, 0.2) * hl * 0.4;
}
