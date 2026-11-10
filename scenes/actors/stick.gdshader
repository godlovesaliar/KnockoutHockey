shader_type spatial;
render_mode cull_disabled;
// Hockey stick finish (SkaterVisual.stick_material): one shader for the stick body and,
// with `tape_layer`, for its tape surface. Works in the stick model's own space
// (tools/blender/stick_gear.py): the heel at the origin, the shaft up +Y to `shaft_len`,
// the blade running toward +Z, its faces toward +-X.
//
// Body styles (`style`):
//   0 wood        a tan laminate with grain along the stick, the blade a little darker
//   1 solid       one color, a satin clear coat
//   2 two-tone    `graphic` on `base`: the top of the shaft (the grip) in the graphic
//                 color, a band of slashes down the middle of the shaft, and a sleeve
//                 over the hosel above the blade
// Tape layer: the butt-end knob (above `knob_from`) in `knob_color`; on the blade a wrap
// of `tape_color` round its middle only (`tape_span`, shares of the heel-to-toe length),
// the heel and toe showing the stick's own finish either side. `bare_blade`: no tape at
// all on the blade.

uniform int style = 1;
uniform vec3 base : source_color = vec3(0.05, 0.05, 0.06);
uniform vec3 graphic : source_color = vec3(0.94, 0.94, 0.92);
uniform float shaft_len = 1.5;
uniform bool tape_layer = false;
uniform vec3 tape_color : source_color = vec3(0.93, 0.93, 0.9);
uniform vec3 knob_color : source_color = vec3(0.93, 0.93, 0.9);
uniform bool bare_blade = false;
uniform float knob_from = 0.9;   // share of shaft_len: tape above this is the knob
uniform vec3 blade_vec = vec3(0.0, -0.2369, 0.2369);   // heel to toe along the bottom line
uniform vec2 tape_span = vec2(0.2, 0.8);   // where the wrap starts and ends along the blade

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

float hash2(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1, 0)), f.x),
			mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), f.x), f.y);
}

// The finish of the stick body at this point: albedo, roughness.
void body_finish(out vec3 col, out float rough) {
	float h = lp.y / shaft_len;
	bool on_blade = lp.y < 0.04 && lp.z > 0.01;   // the blade drops away from the heel toward +Z
	if (style == 0) {
		// Grain runs along the shaft (and on along the blade): stretched noise warped a
		// little, light and dark bands with fine pores.
		// x: along the grain, y: across it (the shaft's length / the blade's length).
		vec2 g = on_blade ? vec2((lp.z - lp.y) * 6.4, (lp.z + lp.y + lp.x) * 184.0)
				: vec2(lp.y * 9.0, (lp.z + lp.x) * 260.0);
		float warp = noise2(g * vec2(1.0, 0.05)) * 3.0;
		float band = 0.5 + 0.5 * sin(g.y * 0.55 + warp * 2.2);
		float pores = noise2(g * vec2(30.0, 1.6));
		vec3 light = vec3(0.80, 0.60, 0.36);
		vec3 dark = vec3(0.56, 0.37, 0.19);
		col = mix(dark, light, band * 0.75 + pores * 0.25);
		if (on_blade) {
			col *= 0.78;
		}
		rough = 0.5;
	} else {
		col = base;
		rough = 0.32;
		if (style == 2) {
			bool g = false;
			// The grip: the top of the shaft, cut at a slant.
			if (h > 0.8 + lp.z * 0.6) {
				g = true;
			}
			// A band of slashes down the middle of the shaft.
			if (h > 0.42 && h < 0.68) {
				float s = fract((lp.y + lp.z * 1.4) * 22.0);
				g = g || s < 0.34;
			}
			// A thin stripe either side of the band.
			if (abs(h - 0.4) < 0.006 || abs(h - 0.7) < 0.006) {
				g = true;
			}
			// The hosel sleeve above the blade.
			if (h > 0.06 && h < 0.17 && !on_blade) {
				g = true;
			}
			if (g) {
				col = graphic;
			}
		}
	}
}

// How far along the blade this point is: 0 at the heel, 1 at the toe.
float along_blade() {
	return dot(lp, blade_vec) / dot(blade_vec, blade_vec);
}

void fragment() {
	vec3 col;
	float rough;
	if (tape_layer) {
		if (lp.y > knob_from * shaft_len) {
			// The knob: tape wound round the butt end, strips around the shaft.
			float w = fract(lp.y * 70.0);
			col = knob_color * (0.9 + 0.1 * smoothstep(0.0, 0.12, w));
			rough = 0.75;
		} else if (bare_blade || abs(along_blade() - 0.5 * (tape_span.x + tape_span.y)) > 0.5 * (tape_span.y - tape_span.x)) {
			body_finish(col, rough);
		} else {
			// Cloth tape wrapped along the blade: overlapping strips (a darker edge where
			// each one lies on the last) and a fine weave.
			float w = fract((lp.z * 0.8 - lp.y) * 55.0);
			float edge = smoothstep(0.0, 0.08, w);
			float weave = noise2(vec2(lp.z, lp.y) * 900.0);
			// Each end of the wrap a touch darker, where the roll was torn off.
			float u = along_blade();
			float end = min(u - tape_span.x, tape_span.y - u);
			col = tape_color * (0.82 + 0.13 * edge + 0.06 * weave) * mix(0.82, 1.0, smoothstep(0.0, 0.02, end));
			rough = 0.85;
		}
	} else {
		body_finish(col, rough);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.4;
}
