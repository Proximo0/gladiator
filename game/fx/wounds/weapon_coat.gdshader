shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx, shadows_disabled;
// Blood on a weapon, drawn as a material_overlay over its meshes (WeaponCoat.pack). Weapon frame: +Y to the tip,
// +X the edge. `mode` 0 blade: the coat creeps from the tip toward the guard and in from the edges, with runs
// toward the grip; 1 club or bat head: the same from the tip, all around; 2 shield face and 3 fist: blotches that
// spread over the whole surface. Blots are where the hits really landed. `to_weapon` takes this mesh's local space
// into the weapon frame.

uniform mat4 to_weapon = mat4(1.0);
uniform int mode = 0;
uniform float tip_y = 0.6;
uniform float base_y = 0.1;
uniform float edge_x = 0.0;  // blade half width at the edges (0: no edge creep)
uniform float coat = 0.0;
uniform float dry = 0.0;
uniform float seed = 0.0;
uniform int blot_count = 0;
uniform vec4 blots[4];
uniform vec3 fresh : source_color = vec3(0.80, 0.012, 0.027);
uniform vec3 dried : source_color = vec3(0.24, 0.035, 0.03);
uniform float glow = 0.0;

varying vec3 v_p;

float hc(float x) {
	return fract(sin(x * 78.233) * 43758.5453);
}

float hn(vec3 q) {
	vec3 i = floor(q);
	vec3 f = fract(q);
	f = f * f * (3.0 - 2.0 * f);
	float n = i.x + i.y * 57.0 + i.z * 113.0 + seed * 31.0;
	return mix(mix(mix(hc(n), hc(n + 1.0), f.x), mix(hc(n + 57.0), hc(n + 58.0), f.x), f.y),
			mix(mix(hc(n + 113.0), hc(n + 114.0), f.x), mix(hc(n + 170.0), hc(n + 171.0), f.x), f.y), f.z);
}

void vertex() {
	v_p = (to_weapon * vec4(VERTEX, 1.0)).xyz;
	VERTEX += NORMAL * 0.0005;
}

void fragment() {
	vec3 p = v_p;
	float cov = 0.0;
	float nz = hn(p * 38.0);
	if (mode <= 1) {
		float span = max(tip_y - base_y, 0.05);
		float along = (tip_y - p.y) / span;  // 0 at the tip, 1 where the blade or head starts
		float reach = coat * 0.85;
		float front = 1.0 - smoothstep(reach - 0.08, reach, along + (nz - 0.5) * 0.25);
		// Smeared, not painted: steel shows through in streaks along the blade, fewer as the coat thickens.
		float streak = hn(vec3(p.x * 70.0, p.y * 9.0, p.z * 70.0));
		front *= 0.35 + 0.65 * smoothstep(0.55 - coat * 0.35, 0.75 - coat * 0.35, streak);
		// Runs toward the grip: narrow columns that carry the coat further down.
		float col_id = floor((p.x + p.z) * 90.0);
		float run_len = coat * 0.45 * hc(col_id + seed * 7.0);
		float in_col = 1.0 - smoothstep(0.18, 0.32, abs(fract((p.x + p.z) * 90.0) - 0.5));
		float run = in_col * (1.0 - smoothstep(reach + run_len - 0.03, reach + run_len, along)) * step(0.3, coat)
				* (1.0 - smoothstep(0.95, 1.0, along));  // runs stop at the guard
		cov = max(front, run);
		if (mode == 0 && edge_x > 0.0) {
			float ed = abs(p.x) / edge_x;
			float band = smoothstep(1.0 - coat * 0.55 - 0.08, 1.0 - coat * 0.55, ed + (nz - 0.5) * 0.15);
			cov = max(cov, band * (1.0 - smoothstep(1.05, 1.15, along)));
		}
	} else {
		float spread = smoothstep(1.0 - coat * 0.5 - 0.06, 1.0 - coat * 0.5, nz * 0.7 + hn(p * 11.0) * 0.3);
		cov = spread;
	}
	for (int i = 0; i < 4; i++) {
		if (i >= blot_count) {
			break;
		}
		vec3 d = p - blots[i].xyz;
		float r = length(d) / max(blots[i].w, 0.005);
		r *= 0.8 + 0.4 * hn(p * 60.0 + float(i) * 3.0);
		cov = max(cov, 1.0 - smoothstep(0.75, 1.0, r));
		// A run from the blot toward the grip.
		float lat = length(d.xz);
		float runb = (1.0 - smoothstep(0.004, 0.007, lat - (hn(p * 90.0) - 0.5) * 0.004)) * step(d.y, 0.0)
				* (1.0 - smoothstep(blots[i].w * 1.5, blots[i].w * 2.6, -d.y));
		cov = max(cov, runb);
	}
	if (cov <= 0.01) {
		discard;
	}
	vec3 blood = mix(fresh * 0.75, dried, smoothstep(0.0, 1.0, dry));
	blood *= 0.75 + 0.4 * nz;
	ALBEDO = blood;
	float wet = 1.0 - dry;
	ROUGHNESS = mix(0.75, 0.3, wet);
	SPECULAR = mix(0.15, 0.35, wet);
	EMISSION = blood * glow * wet;
	ALPHA = clamp(cov, 0.0, 1.0) * 0.95;
}
