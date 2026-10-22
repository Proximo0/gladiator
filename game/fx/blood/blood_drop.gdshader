shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Glossy blood droplet. Instance custom: xyz velocity, w radius. Instance colour: r stretch factor, g shade.
// Orients and stretches the unit rounded drop along the velocity in the vertex stage. Fresh arterial red:
// saturated, self-lit enough to stay red in shade, with a wet specular highlight.

// Palette slot 0 / 1 (the two fighters' blood, instance colour b = slot). Set by BloodFx from the outfit blood palettes;
// glow is the extra self-light of ichor (0 for red).
uniform vec3 blood_bright : source_color = vec3(0.98, 0.015, 0.034);
uniform vec3 blood_dark : source_color = vec3(0.52, 0.008, 0.018);
uniform float blood_glow = 0.0;
uniform vec3 blood_bright1 : source_color = vec3(0.98, 0.015, 0.034);
uniform vec3 blood_dark1 : source_color = vec3(0.52, 0.008, 0.018);
uniform float blood_glow1 = 0.0;
uniform float stretch_time = 0.006;
uniform float tail_cap = 3.0;  // longest tail as a multiple of the drop radius: short motion trail, never a hatch line
uniform float edge_dark = 0.55;  // how much the silhouette darkens (thick liquid absorbs light)
uniform float min_px = 2.2;  // smallest drop radius on screen in pixels: far drops stay round dots instead of sub-pixel slivers

varying float v_thick;
varying float v_shade;
varying float v_pal;

void vertex() {
	vec3 vel = INSTANCE_CUSTOM.xyz;
	float r0 = max(INSTANCE_CUSTOM.w, 0.0005);
	float dist = max(length((MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz), 0.1);
	float r = max(r0, dist * min_px / (0.5 * VIEWPORT_SIZE.y * PROJECTION_MATRIX[1][1]));
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
	v_pal = COLOR.b;
}

void fragment() {
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fr = pow(1.0 - ndv, 3.0);
	float dark = clamp(v_thick * 0.3 + v_shade * 0.25, 0.0, 0.55);
	bool second = v_pal > 0.5;
	vec3 bright = second ? blood_bright1 : blood_bright;
	vec3 dark_c = second ? blood_dark1 : blood_dark;
	float glow = second ? blood_glow1 : blood_glow;
	// Liquid look: the body is a deep translucent-looking red that darkens toward the silhouette (light is absorbed by
	// the thick edge), with a small hard highlight and a soft warm one on the lit side.
	vec3 col = mix(bright, dark_c, dark);
	col = mix(col, dark_c * 0.45, smoothstep(0.0, 1.0, 1.0 - ndv) * edge_dark);
	ALBEDO = col;
	ROUGHNESS = 0.06;
	SPECULAR = 0.05;
	METALLIC = 0.0;
	vec3 up_v = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	vec3 ld = normalize(up_v * 0.8 + vec3(0.35, 0.2, 0.5));
	float hl = pow(max(dot(NORMAL, ld), 0.0), 60.0);
	float soft = pow(max(dot(NORMAL, ld), 0.0), 6.0);
	EMISSION = col * (0.26 + glow) * (1.0 - 0.5 * fr) + bright * 0.12 * soft + vec3(1.0, 0.92, 0.85) * hl * 0.55;
}
