shader_type spatial;
render_mode cull_disabled;
// Far-tier spectator impostor: a 2-triangle card (Houdini <variant>_lod3.glb) whose texture holds the same masks as the
// meshes (R clothing, G skin, B hair, alpha the silhouette). Per-instance colours and seed as in crowd.gdshader.
// Alpha scissor, not blend: no sorting, and the cards are small on screen.
uniform sampler2D card_tex : filter_linear_mipmap, repeat_disable;
uniform float excitement : hint_range(0.0, 1.0) = 0.08;
uniform int mode = 0;

varying flat vec3 v_cloth;
varying flat vec3 v_skin;
varying flat vec3 v_hair;
varying flat float v_shade;
varying float v_y;

const vec3 SKINS[4] = vec3[4](vec3(0.8, 0.6, 0.45), vec3(0.66, 0.46, 0.33), vec3(0.52, 0.36, 0.26), vec3(0.86, 0.68, 0.54));
const vec3 HAIRS[6] = vec3[6](vec3(0.04, 0.03, 0.03), vec3(0.1, 0.06, 0.04), vec3(0.17, 0.1, 0.06), vec3(0.26, 0.17, 0.09), vec3(0.4, 0.38, 0.36), vec3(0.5, 0.36, 0.18));

void vertex() {
	float seed = INSTANCE_CUSTOM.w;
	float phase = fract(seed * 0.61803399);
	float wear = fract(seed * 0.4142136);
	v_cloth = mix(INSTANCE_CUSTOM.xyz, vec3(dot(INSTANCE_CUSTOM.xyz, vec3(0.3, 0.55, 0.15))), 0.12 + 0.3 * wear) * mix(0.78, 1.0, fract(seed * 0.2360680));
	v_shade = mix(0.86, 1.0, fract(seed * 0.1180340));
	v_skin = SKINS[int(fract(seed * 0.75487767) * 4.0) % 4] * mix(0.9, 1.05, fract(seed * 0.3247179));
	v_hair = HAIRS[int(fract(seed * 0.56984029) * 6.0) % 6];
	v_y = VERTEX.y;
	float bounce = abs(sin(TIME * (1.1 + 0.5 * fract(seed * 0.7071068)) * 3.1416 + phase * 6.2832));
	VERTEX.y += bounce * (mode == 1 ? 0.05 + 0.12 * excitement : 0.012 * excitement);
	// Light the card as a body facing the arena and the sky, not as a flat board.
	NORMAL = normalize(NORMAL + vec3(0.0, 0.6, 0.0));
}

void fragment() {
	vec4 t = texture(card_tex, UV);
	if (t.a < 0.5) {
		discard;
	}
	// The impostor render is soft and lit: re-normalise its masks so cloth is cloth (a raw blend washed the cards out),
	// and darken a little for the self-shadowing a flat card cannot have.
	vec3 m = t.rgb / max(t.r + t.g + t.b, 0.001);
	m *= m;
	m /= max(m.r + m.g + m.b, 0.001);
	vec3 c = m.r * v_cloth + m.g * v_skin + m.b * v_hair;
	c *= mix(0.5, 1.0, smoothstep(0.0, 1.1, v_y)) * v_shade * 0.85;
	ALBEDO = c;
	ROUGHNESS = 0.95;
	SPECULAR = 0.0;
}
