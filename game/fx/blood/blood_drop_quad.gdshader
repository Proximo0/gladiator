shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, skip_vertex_transform, diffuse_burley, specular_schlick_ggx;
// Glossy blood droplet as a camera-facing impostor: 2 triangles instead of a 160-336 triangle teardrop mesh.
// Same instance data and look as blood_drop.gdshader (custom: xyz velocity, w radius; colour: r stretch, g shade,
// b palette slot). The quad (BloodMesh.quad, x across, y along, both -1..1) is laid out in view space along the
// velocity as the screen sees it; the fragment cuts the teardrop out (round head, elliptical tail) and builds the
// rounded normal, so the silhouette stays smooth at any size.

uniform vec3 blood_bright : source_color = vec3(0.98, 0.015, 0.034);
uniform vec3 blood_dark : source_color = vec3(0.52, 0.008, 0.018);
uniform float blood_glow = 0.0;
uniform vec3 blood_bright1 : source_color = vec3(0.98, 0.015, 0.034);
uniform vec3 blood_dark1 : source_color = vec3(0.52, 0.008, 0.018);
uniform float blood_glow1 = 0.0;
uniform float stretch_time = 0.006;
uniform float tail_cap = 3.0;
uniform float edge_dark = 0.55;
uniform float min_px = 2.2;

varying float v_thick;
varying float v_shade;
varying float v_pal;
varying vec2 v_ab;  // position in drop radii: x along the velocity (head centre 0, head tip +1), y across
varying float v_tail;  // tail length in drop radii (>= 1)
varying vec3 v_ax;
varying vec3 v_ay;
varying vec3 v_az;

void vertex() {
	vec3 vel = INSTANCE_CUSTOM.xyz;
	float r0 = max(INSTANCE_CUSTOM.w, 0.0005);
	vec3 c = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float dist = max(length(c), 0.1);
	float r = max(r0, dist * min_px / (0.5 * VIEWPORT_SIZE.y * PROJECTION_MATRIX[1][1]));
	float sp = length(vel);
	float tail = min(r + sp * stretch_time * COLOR.r, r * tail_cap);
	vec3 vz = -c / dist;  // towards the camera
	vec3 vv = (MODELVIEW_MATRIX * vec4(vel, 0.0)).xyz;
	vec3 vp = vv - vz * dot(vv, vz);  // velocity in the screen plane
	float pl = length(vp);
	vec3 ax = pl > 0.0001 ? vp / pl : normalize(cross(vz, vec3(1.0, 0.0, 0.0)));
	vec3 ay = cross(vz, ax);
	// A drop flying at the camera shows little tail.
	float t_eff = r + (tail - r) * (sp > 0.0001 ? clamp(pl / sp, 0.0, 1.0) : 0.0);
	float along = mix(-t_eff, r, VERTEX.y * 0.5 + 0.5);
	float across = VERTEX.x * r;
	VERTEX = c + ax * along + ay * across;
	NORMAL = vz;
	v_ab = vec2(along, across) / r;
	v_tail = max(t_eff / r, 1.0);
	v_ax = ax;
	v_ay = ay;
	v_az = vz;
	v_thick = clamp(r / 0.012, 0.0, 1.0);
	v_shade = COLOR.g;
	v_pal = COLOR.b;
}

void fragment() {
	float a = v_ab.x;
	float b = v_ab.y;
	vec3 nl;
	if (a >= 0.0) {
		float d2 = a * a + b * b;
		if (d2 > 1.0) {
			discard;
		}
		nl = vec3(a, b, sqrt(1.0 - d2));
	} else {
		float at = a / v_tail;
		float e = at * at + b * b;
		if (e > 1.0) {
			discard;
		}
		nl = normalize(vec3(at / v_tail, b, sqrt(1.0 - e)));
	}
	NORMAL = normalize(v_ax * nl.x + v_ay * nl.y + v_az * nl.z);
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fr = pow(1.0 - ndv, 3.0);
	float dark = clamp(v_thick * 0.3 + v_shade * 0.25, 0.0, 0.55);
	bool second = v_pal > 0.5;
	vec3 bright = second ? blood_bright1 : blood_bright;
	vec3 dark_c = second ? blood_dark1 : blood_dark;
	float glow = second ? blood_glow1 : blood_glow;
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
