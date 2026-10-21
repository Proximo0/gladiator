shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
// Billboard mist puff. Instance custom: x size, y alpha, z rotation.

uniform vec3 mist_color : source_color = vec3(0.82, 0.03, 0.045);

varying float v_alpha;

void vertex() {
	float size = INSTANCE_CUSTOM.x;
	float rot = INSTANCE_CUSTOM.z;
	mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * bb;
	float c = cos(rot);
	float s = sin(rot);
	VERTEX.xy = vec2(VERTEX.x * c - VERTEX.y * s, VERTEX.x * s + VERTEX.y * c) * size;
	v_alpha = INSTANCE_CUSTOM.y;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float lump = 0.75 + 0.25 * sin(atan(p.y, p.x) * 3.0 + v_alpha * 7.0);
	float a = smoothstep(lump, 0.15, d);
	ALBEDO = mist_color;
	ALPHA = clamp(a * v_alpha * 1.25, 0.0, 1.0);
}
