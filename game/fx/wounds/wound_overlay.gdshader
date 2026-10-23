shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx, shadows_disabled;
// Accumulated damage on one body part, drawn as a material_overlay over the part's own meshes (skin, outfit, armor):
// gashes, punctures, bruises (which swell the overlay surface), blood smears and sever rings (the wet band round a
// stump or a severed part's cut end), each a shape in the part's frame,
// so a mark wraps the real surface wherever the hit landed. Up to 12 marks (WoundMarks.pack); `to_part` takes this
// mesh's local space into the part frame. On armor (`armor`) cuts and holes show only as blood, never flesh.
// Palette slot 0 / 1: the two fighters' blood (fresh / dried colour, glow) and flesh colours.

uniform mat4 to_part = mat4(1.0);
uniform int count = 0;
uniform vec4 wa[12];  // pos, size (half length / radius)
uniform vec4 wb[12];  // cut direction, half width
uniform vec4 wc[12];  // outward normal (a ring: the bone axis out through the cut), kind (0 gash, 1 puncture, 2 bruise, 3 smear, 4 ring)
uniform vec4 wd[12];  // trickle direction (down), trickle length
uniform vec4 we[12];  // dryness, seed, palette slot, severity
uniform bool armor = false;
uniform float swell = 0.016;  // bruise swelling at full severity (m)
uniform float core_scale = 1.0;  // open slit / hole width multiplier (Tuning wound_core_scale)
uniform float rim_glow = 0.0;  // emission of a fresh wound's wet rim (Tuning wound_rim_glow)
uniform float rim_glow_dry = 0.05;  // dryness at which that glow is gone (WoundMarks.dryness of wound_rim_glow_s)
uniform float smear_lobe = 0.26;  // how far a smear's outline bulges (Tuning wound_smear_lobe; WoundMarks.smear_lobe)
uniform float smear_drops = 0.35;  // share of edge cells round a smear that hold a satellite drop
uniform float ring_glow = 0.0;  // emission of a sever ring's fresh blood (Tuning wound_ring_glow)
uniform float ring_glow_dry = 0.2;  // dryness at which that glow is gone (wound_ring_glow_s)
uniform vec3 fresh0 : source_color = vec3(0.80, 0.012, 0.027);
uniform vec3 dried0 : source_color = vec3(0.24, 0.035, 0.03);
uniform vec3 flesh0 : source_color = vec3(0.75, 0.04, 0.04);
uniform float glow0 = 0.0;
uniform vec3 bruise0 : source_color = vec3(0.20, 0.03, 0.16);  // fresh bruise core
uniform vec3 bruise_old0 : source_color = vec3(0.42, 0.40, 0.10);  // the rim it fades to
uniform vec3 fresh1 : source_color = vec3(0.80, 0.012, 0.027);
uniform vec3 dried1 : source_color = vec3(0.24, 0.035, 0.03);
uniform vec3 flesh1 : source_color = vec3(0.75, 0.04, 0.04);
uniform float glow1 = 0.0;
uniform vec3 bruise1 : source_color = vec3(0.20, 0.03, 0.16);
uniform vec3 bruise_old1 : source_color = vec3(0.42, 0.40, 0.10);

varying vec3 v_p;

float h11(float x) {
	return fract(sin(x * 91.3458) * 47453.5453);
}

float wn(float x, float s) {  // smooth 1D value noise, -1..1
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(h11(i + s * 17.0), h11(i + 1.0 + s * 17.0), f) * 2.0 - 1.0;
}

void vertex() {
	vec3 p = (to_part * vec4(VERTEX, 1.0)).xyz;
	v_p = p;
	float s = 0.0;
	for (int i = 0; i < 12; i++) {
		if (i >= count) {
			break;
		}
		if (wc[i].w > 1.5 && wc[i].w < 2.5 && !armor) {
			float d = length(p - wa[i].xyz) / max(wa[i].w, 0.001);
			s = max(s, (1.0 - smoothstep(0.0, 1.0, d)) * we[i].w);
		}
	}
	// A hair off the base surface so the overlay never z-fights it; bruises bulge out (cartoon swelling).
	VERTEX += NORMAL * (0.0006 + s * swell);
}

void fragment() {
	vec3 col = vec3(0.0);
	float alpha = 0.0;
	float wet = 0.0;
	float glow_sum = 0.0;
	vec3 rim_em = vec3(0.0);
	for (int i = 0; i < 12; i++) {
		if (i >= count) {
			break;
		}
		vec3 d = v_p - wa[i].xyz;
		vec3 n = wc[i].xyz;
		float depth = dot(d, n);
		float kind = wc[i].w;
		// This side of the limb only (a ring goes all the way round).
		float side = kind > 3.5 ? 1.0 : 1.0 - smoothstep(0.022, 0.05, abs(depth));
		if (side <= 0.0) {
			continue;
		}
		float sz = max(wa[i].w, 0.002);
		float seed = we[i].y;
		float dry = we[i].x;
		float sev = we[i].w;
		bool second = we[i].z > 0.5;
		vec3 fresh = second ? fresh1 : fresh0;
		vec3 dried = second ? dried1 : dried0;
		vec3 flesh = second ? flesh1 : flesh0;
		float glow = second ? glow1 : glow0;
		vec3 blood = mix(fresh, dried, smoothstep(0.0, 1.0, dry));
		vec3 t = wb[i].xyz;
		vec3 b = cross(n, t);
		float u = dot(d, t);
		float v = dot(d, b);
		vec3 c = blood;
		float a = 0.0;
		float w = 0.0;  // wet share of this layer
		float rim = 0.0;  // the wet rim of an open wound (glows while fresh)
		float rglow = rim_glow;
		float rdry = rim_glow_dry;
		if (kind < 0.5) {
			// Gash: a lens along the cut with ragged edges, dark open flesh in the slit, a bright wet rim and a smear
			// of blood around it.
			float uu = u / sz;
			float lens = max(1.0 - uu * uu, 0.0);
			float hw = wb[i].w * core_scale * sqrt(lens) * (1.0 + 0.3 * wn(u * 140.0, seed));
			float av = abs(v);
			float halo_w = wb[i].w * (1.0 + 2.2 * sqrt(max(1.0 - uu * uu * 0.6, 0.0))) + 0.014 * sev;
			float halo = (1.0 - smoothstep(halo_w * 0.6, halo_w, av)) * (1.0 - smoothstep(0.95, 1.35, abs(uu)));
			halo *= 0.55 + 0.45 * wn(u * 60.0 + v * 90.0, seed + 3.0);
			a = clamp(halo, 0.0, 1.0) * 0.9;
			c = blood;
			w = 1.0;
			rim = (1.0 - smoothstep(hw, hw * 1.7 + 0.004, av)) * (1.0 - smoothstep(0.85, 1.1, abs(uu)));
			if (!armor && av < hw && abs(uu) < 1.0) {
				float k = av / max(hw, 0.0005);
				vec3 inner = mix(flesh * 0.22, flesh * 0.95, smoothstep(0.25, 0.75, k));
				inner = mix(inner, vec3(0.06, 0.0, 0.01), (1.0 - smoothstep(0.0, 0.35, k)) * (0.5 + 0.5 * sev));
				c = mix(inner, blood * 0.7, dry * 0.5);
				a = 1.0;
				w = 0.6;
			}
		} else if (kind < 1.5) {
			// Puncture: a dark round hole, a flesh lip, a ring of blood with ragged lobes.
			float r = length(vec2(u, v)) / (sz * core_scale);
			float ang = atan(v, u);
			float lobe = 1.0 + 0.35 * wn(ang * 2.5 + 7.0, seed) * step(0.5, r);
			r /= lobe;
			a = (1.0 - smoothstep(1.4, 1.9, r)) * 0.92;
			c = blood;
			w = 1.0;
			rim = (1.0 - smoothstep(0.75, 1.3, r)) * smoothstep(0.5, 0.75, r);
			if (!armor && r < 0.75) {
				c = mix(vec3(0.05, 0.0, 0.01), flesh * 0.8, smoothstep(0.35, 0.7, r));
				c = mix(c, blood * 0.6, dry * 0.4);
				a = 1.0;
				w = 0.5;
			}
		} else if (kind < 2.5) {
			// Bruise: swollen purple core going blue, a yellow-green rim as it ages (no blood: skin only).
			if (armor) {
				continue;
			}
			float r = length(d - n * depth) / sz;
			float ang = atan(v, u);
			r *= 1.0 + 0.18 * wn(ang * 2.0, seed);
			vec3 bz = second ? bruise1 : bruise0;
			vec3 bz_old = second ? bruise_old1 : bruise_old0;
			vec3 core = mix(bz, bz * vec3(0.6, 1.3, 1.5), smoothstep(0.0, 0.6, dry));
			vec3 rim = mix(bz * 1.5, bz_old, smoothstep(0.15, 0.8, dry));
			c = mix(core * (0.75 + 0.25 * r), rim, smoothstep(0.45, 0.95, r));
			a = (1.0 - smoothstep(0.7, 1.05, r)) * (0.7 + 0.3 * sev);
			w = 0.0;
		} else if (kind < 3.5) {
			// Smear: a splashed blot with a few soft lobes (whole harmonics of the angle, so the outline closes with no
			// seam and never spikes into a star) and a few satellite drops just outside it, streaked along `t` when it
			// landed fast (narrower across: wb.w < size).
			vec2 e = vec2(u / sz, v / max(wb[i].w, 0.002));
			float r = length(e);
			float ang = atan(e.y, e.x);
			float p = seed * 6.2831853;
			float lobe = 1.0 + smear_lobe * (0.55 * sin(2.0 * ang + p) + 0.3 * sin(3.0 * ang + 2.3 * p) + 0.15 * sin(5.0 * ang + 4.1 * p));
			// A ragged edge on top: 2D value noise over the blot (no angle seam), a few percent of its radius.
			vec2 g = e * 4.0 + vec2(seed * 13.0, seed * 7.0);
			vec2 gi = floor(g);
			vec2 gf = fract(g);
			gf = gf * gf * (3.0 - 2.0 * gf);
			float gn = mix(mix(h11(dot(gi, vec2(1.0, 57.0))), h11(dot(gi + vec2(1.0, 0.0), vec2(1.0, 57.0))), gf.x),
					mix(h11(dot(gi + vec2(0.0, 1.0), vec2(1.0, 57.0))), h11(dot(gi + vec2(1.0, 1.0), vec2(1.0, 57.0))), gf.x), gf.y);
			float rl = r / lobe + (gn - 0.5) * 0.14;
			a = (1.0 - smoothstep(0.82, 1.0, rl)) * (0.8 + 0.12 * (1.0 - rl));
			vec2 q = e * 2.6 + vec2(seed * 9.0, seed * 4.0);
			vec2 cell = floor(q);
			vec2 f = fract(q) - 0.5;
			float hd = h11(dot(cell, vec2(7.1, 13.7)) + seed);
			float drop = step(1.0 - smear_drops * 0.6, hd) * (1.0 - smoothstep(0.1, 0.17, length(f)));
			a = max(a, drop * smoothstep(0.95, 1.1, rl) * (1.0 - smoothstep(1.35, 1.7, rl)) * 0.9);
			c = blood;
			w = 1.0;
		} else {
			// Sever ring: a wet band of fresh blood round the limb from the cut back into the part, a dark torn line
			// at the cut itself and a few runs hanging off its far edge. `depth` is the distance along the bone
			// axis past the cut (negative: back into the part); wa.w is the radius it reaches, wb.w the band height.
			float back = -depth;
			float rad = length(d - n * depth);
			float band = wb[i].w * (0.6 + 0.4 * sev);
			float ang = atan(v, u);
			float edge = band * (0.8 + 0.2 * sin(3.0 * ang + seed * 6.2831853));
			float run = pow(max(sin(5.0 * ang + seed * 19.0), 0.0), 10.0) * band * 1.3;
			a = (1.0 - smoothstep(edge + run, edge + run + 0.008, back)) * (1.0 - smoothstep(sz * 0.9, sz * 1.1, rad));
			a *= step(-0.02, back) * 0.97;
			float torn = 1.0 - smoothstep(0.0, 0.25 * band, back);
			c = armor ? blood : mix(blood, mix(flesh * 0.35, blood, 0.4), torn);
			w = 1.0;
			rim = (1.0 - smoothstep(0.0, edge, back)) * a;
			rglow = ring_glow;
			rdry = ring_glow_dry;
		}
		// Trickle: gashes and punctures bleed a thin run down the skin with a drop at its end.
		float tl = wd[i].w;
		if (kind < 1.5 && tl > 0.002) {
			vec3 dn = wd[i].xyz;
			vec3 sd = cross(n, dn);
			float s = dot(d, dn);
			float lat = dot(d, sd) + 0.004 * wn(s * 45.0, seed + 11.0);
			float tw = (0.0035 + 0.004 * sev) * (1.0 - 0.45 * clamp(s / tl, 0.0, 1.0));
			float bulb = 1.0 - smoothstep(tw * 1.1, tw * 1.7, length(vec2(lat, s - tl)));
			float run = (1.0 - smoothstep(tw * 0.7, tw, abs(lat))) * step(0.0, s) * (1.0 - smoothstep(tl - 0.002, tl, s));
			float ta = max(run, bulb) * 0.95;
			if (ta > 0.0) {
				c = mix(c, blood, ta * (1.0 - a));
				a = max(a, ta);
				w = max(w, ta);
			}
		}
		a *= side;
		col = mix(col, c, a);
		alpha = alpha + a * (1.0 - alpha);
		wet = max(wet, w * a * (1.0 - dry));
		glow_sum = max(glow_sum, glow * a * w * (1.0 - dry));
		rim_em = max(rim_em, blood * (rim * side * rglow * (1.0 - smoothstep(0.0, max(rdry, 0.0001), dry))));
	}
	if (alpha <= 0.002) {
		discard;
	}
	ALBEDO = col / max(alpha, 0.001);  // col is premultiplied (front layers drawn over older ones)
	// Wet blood over dark leather or metal (armor): the full wet gloss added a sky-and-sun highlight over a dark albedo
	// that read pink-white, so armor keeps a dull, low-specular wet sheen.
	ROUGHNESS = mix(0.82, armor ? 0.62 : 0.3, wet);
	SPECULAR = mix(0.12, armor ? 0.12 : 0.35, wet);
	EMISSION = ALBEDO * glow_sum + rim_em;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
