shader_type spatial;
render_mode cull_back;
// Spectator crowd. Vertex colour masks: R clothing, G skin, B hair. Per-instance data (INSTANCE_CUSTOM):
// xyz clothing colour, w a small integer seed (0..2047) from which skin, hair, phase and cheer threshold derive.
// mode: 0 standing calm, 1 standing cheering, 2 seated, 3 noble. A standing seat owns a calm and a cheering twin
// with the same seed. Which twin is drawn is decided on the CPU (crowd_cull.gd: a hidden twin would still cost its
// vertices), so this shader only animates.
uniform float excitement : hint_range(0.0, 1.0) = 0.08;
uniform int mode = 0;
uniform int dbg = 0;
uniform vec3 rest_tint : source_color = vec3(0.45, 0.34, 0.24);

varying flat vec3 v_cloth;
varying flat vec3 v_skin;
varying flat vec3 v_hair;
varying float v_y;
varying flat float v_shade;

const vec3 SKINS[4] = vec3[4](vec3(0.8, 0.6, 0.45), vec3(0.66, 0.46, 0.33), vec3(0.52, 0.36, 0.26), vec3(0.86, 0.68, 0.54));
const vec3 HAIRS[6] = vec3[6](vec3(0.04, 0.03, 0.03), vec3(0.1, 0.06, 0.04), vec3(0.17, 0.1, 0.06), vec3(0.26, 0.17, 0.09), vec3(0.4, 0.38, 0.36), vec3(0.5, 0.36, 0.18));

void vertex() {
	float seed = INSTANCE_CUSTOM.w;
	float phase = fract(seed * 0.61803399);
	float skin_u = fract(seed * 0.75487767);
	float hair_u = fract(seed * 0.56984029);
	// Worn, sun-bleached wool: each spectator's cloth a little duller or darker (the palette alone read as confetti).
	float wear = fract(seed * 0.4142136);
	v_cloth = mix(INSTANCE_CUSTOM.xyz, vec3(dot(INSTANCE_CUSTOM.xyz, vec3(0.3, 0.55, 0.15))), 0.12 + 0.3 * wear) * mix(0.78, 1.0, fract(seed * 0.2360680));
	v_shade = mix(0.86, 1.0, fract(seed * 0.1180340));
	v_skin = SKINS[int(skin_u * 4.0) % 4] * mix(0.9, 1.05, fract(seed * 0.3247179));
	v_hair = HAIRS[int(hair_u * 6.0) % 6];
	if (mode == 3) {
		v_skin = SKINS[3];
	}
	v_y = VERTEX.y;
	float e = excitement;
	float rate = fract(seed * 0.7071068);
	float t = TIME;
	float w = sin(t * (0.7 + 0.5 * rate) * 6.2832 + phase * 6.2832);
	float bounce = abs(sin(t * (1.1 + 0.5 * rate) * 3.1416 + phase * 6.2832));
	if (mode == 0) {
		float h = smoothstep(0.1, 1.3, VERTEX.y);
		VERTEX.x += w * (0.012 + 0.02 * e) * h;
		VERTEX.y += bounce * 0.012 * e;
	} else if (mode == 1) {
		float h = smoothstep(0.1, 1.3, VERTEX.y);
		VERTEX.y += bounce * (0.05 + 0.12 * e);
		VERTEX.x += w * 0.035 * h;
	} else if (mode == 2) {
		float h = smoothstep(0.45, 1.0, VERTEX.y);
		VERTEX.z += w * (0.008 + 0.03 * e) * h;
		VERTEX.y += bounce * 0.05 * e * h;
	} else {
		float h = smoothstep(0.45, 1.0, VERTEX.y);
		VERTEX.x += w * 0.006 * h;
	}
}

void fragment() {
	vec3 m = COLOR.rgb;
	float rest = max(0.0, 1.0 - m.r - m.g - m.b);
	vec3 c = m.r * v_cloth + m.g * v_skin + m.b * v_hair + rest * rest_tint;
	// Packed stands: legs and laps sit in the shade of the row in front, heads catch the light.
	c *= mix(0.5, 1.0, smoothstep(0.0, 1.1, v_y));
	c *= v_shade;
	ALBEDO = (dbg == 1) ? m : (dbg == 2) ? v_cloth : c;
	ROUGHNESS = 0.95;
	SPECULAR = 0.0;
}
