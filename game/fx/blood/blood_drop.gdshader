shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Glossy blood droplet. Instance custom: xyz velocity, w radius. Instance colour: r stretch factor, g shade.
// Orients and stretches the unit teardrop along the velocity in the vertex stage.

uniform vec3 blood_bright : source_color = vec3(0.85, 0.03, 0.04);
uniform vec3 blood_dark : source_color = vec3(0.24, 0.0, 0.012);
uniform float stretch_time = 0.007;

varying float v_thick;
varying float v_shade;

void vertex() {
	vec3 vel = INSTANCE_CUSTOM.xyz;
	float r = INSTANCE_CUSTOM.w;
	float sp = length(vel);
	vec3 d = sp > 0.05 ? vel / sp : vec3(0.0, -1.0, 0.0);
	vec3 up = abs(d.y) > 0.95 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
	vec3 ax = normalize(cross(up, d));
	vec3 ay = cross(d, ax);
	float tail = min(r + sp * stretch_time * COLOR.r, r * 16.0);
	float zs = VERTEX.z > 0.0 ? r : tail;
	VERTEX = ax * VERTEX.x * r + ay * VERTEX.y * r + d * VERTEX.z * zs;
	vec3 n = ax * NORMAL.x / r + ay * NORMAL.y / r + d * NORMAL.z / zs;
	NORMAL = normalize(n);
	v_thick = clamp(r / 0.008, 0.0, 1.0);
	v_shade = COLOR.g;
}

void fragment() {
	float fr = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float dark = clamp(v_thick * 0.75 + v_shade * 0.35, 0.0, 1.0);
	ALBEDO = mix(blood_bright, blood_dark, dark);
	ROUGHNESS = 0.05;
	SPECULAR = 1.0;
	METALLIC = 0.0;
	EMISSION = blood_bright * 0.28 + vec3(0.55, 0.05, 0.05) * fr * 0.55;
}
