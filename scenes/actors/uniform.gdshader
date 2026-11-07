shader_type spatial;
render_mode cull_disabled; // the inside of sleeves and collars shows at the hems
// Team uniform on the outfit layer. Layout: uniform_regions.gdshaderinc.
//
// Detail is procedural, pinned to the cloth by the rest-pose position / normal the build
// step bakes into CUSTOM0 / CUSTOM1 (arms in a T-pose, origin at the base of the neck,
// torso scaled to 0.6 m), so it doesn't swim when the body moves and fits every body:
//   jersey  knit dimples, coarser mesh panels down the sides and under the arms, drape
//           folds (around the sleeves, down the body), sewn seams at every stripe edge
//   pants   nylon shell with sheen, quilted padding channels
//   socks   ribbed knit
//   gloves  leather grain, darker palms
// Height detail turns into normals per pixel (screen-space bump), and fine patterns fade
// out with distance before they can shimmer.

#include "res://scenes/actors/uniform_regions.gdshaderinc"

uniform vec3 jersey : source_color = vec3(0.78, 0.1, 0.12);
uniform vec3 trim : source_color = vec3(0.95, 0.95, 0.95);
uniform vec3 accent_color : source_color = vec3(0.1, 0.1, 0.1);   // alternate stripes (Teams.DESIGNS)
uniform vec3 pants : source_color = vec3(0.1, 0.1, 0.12);
uniform vec3 gloves : source_color = vec3(0.35, 0.05, 0.06);
uniform vec3 helmet : source_color = vec3(0.3, 0.04, 0.05); // unused here (the helmet is a model)
uniform vec3 skates : source_color = vec3(0.04, 0.04, 0.05);
uniform float darken = 1.0; // Alpha_Joints use a slightly darker shade
instance uniform float gloves_worn = 1.0;   // 0 = gloves off (fights): the hands show bare

uniform float detail = 1.0;          // 0 = flat colors (old look)
uniform float knit_scale = 230.0;    // jersey knit cells per meter
uniform float mesh_scale = 120.0;    // side-panel mesh holes per meter
uniform float sock_ribs = 44.0;      // sock ribs around the leg
uniform float quilt_step = 0.075;    // pants padding channel spacing (m)
uniform float bump = 1.0;
// Shoulder yoke in the trim color: everything within `yoke_r` of the base of the neck,
// distance stretched by `yoke_shape` (y: shallower down the chest and back). One smooth
// shape across body and sleeves, so its edge doesn't step where they meet. 0 = none.
uniform float yoke_r = 0.0;
uniform vec3 yoke_shape = vec3(0.8, 2.6, 0.0);   // z 0: depth ignored, so pads poking through the jersey agree with it

varying vec3 rest_p;
varying vec3 rest_n;

void vertex() {
	rest_p = CUSTOM0.xyz;
	rest_n = CUSTOM1.xyz;
}

float hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// 1 when a pattern of `freq` cells per meter is still several pixels per cell, 0 when it
// would alias.
float keep(vec3 p, float freq) {
	float px = length(fwidth(p)) * freq;
	return 1.0 - smoothstep(0.25, 0.6, px);
}

vec3 tri_w(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / max(w.x + w.y + w.z, 1e-4);
}

// Round dimples on a grid (knit or mesh): 1 in a hole, 0 on the yarn.
float dots(vec2 uv, float r) {
	vec2 g = uv;
	g.x += step(1.0, mod(floor(g.y), 2.0)) * 0.5;   // staggered rows
	float d = length(fract(g) - 0.5);
	return 1.0 - smoothstep(r - 0.1, r + 0.05, d);
}

float tri_dots(vec3 p, vec3 w, float freq, float r) {
	return dots(p.zy * freq, r) * w.x + dots(p.xz * freq, r) * w.y + dots(p.xy * freq, r) * w.z;
}

// Groove at `edge` along a part's position (stripe and hem seams): 1 on the seam.
float seam(float f, float edge) {
	float w = max(fwidth(f), 0.0015);
	return 1.0 - smoothstep(0.0, w * 1.5 + 0.004, abs(f - edge));
}

void fragment() {
	vec4 part;
	float sk;
	float tr;
	float acc;
	uniform_regions_full(COLOR, UV2, part, sk, tr, acc);
	if (part.w > 0.5 && gloves_worn < 0.5) {
		discard;
	}
	float total = max(part.x + part.y + part.z + part.w + sk, 0.001);
	// Above the base of the neck (collar, tops of the pads) everything is yoke: the
	// vertical stretch only applies going down the chest and back.
	vec3 ys = yoke_shape;
	ys.y *= mix(1.0, 0.1, smoothstep(-0.02, 0.02, rest_p.y));
	float yoke_d = length(rest_p * ys);
	if (yoke_r > 0.0) {
		float w = max(fwidth(yoke_d), 0.001);
		float yk = (1.0 - smoothstep(yoke_r - w, yoke_r + w, yoke_d)) * part.x;
		tr = max(tr - acc, yk) + acc * (1.0 - yk);
		acc *= 1.0 - yk;
	}
	vec3 c = jersey * (part.x + part.z - tr) + trim * (tr - acc) + accent_color * acc + pants * part.y + gloves * part.w + skates * sk;
	c = c / total;

	vec3 p = rest_p;
	vec3 n = normalize(rest_n + vec3(1e-4));
	vec3 w = tri_w(n);
	float f = UV2.y;
	vec3 pure = smoothstep(vec3(0.9), vec3(1.0), COLOR.rgb);
	float jersey_k = clamp((part.x) / total, 0.0, 1.0);
	float pants_k = clamp(part.y / total, 0.0, 1.0);
	float socks_k = clamp(part.z / total, 0.0, 1.0);
	float glove_k = clamp(part.w / total, 0.0, 1.0);

	float h = 0.0;          // height detail (bump)
	float shade = 1.0;      // albedo multiplier
	float rough = 0.8;
	float spec = 0.35;
	float rim = 0.0;

	// --- Jersey -------------------------------------------------------------------
	if (jersey_k > 0.01) {
		// Mesh ventilation panels: down the torso's sides and along the underside of the
		// sleeves (arms hang down in A-pose bodies, out in T-pose: "under" is facing down
		// or facing the body).
		float side = COLOR.r * smoothstep(0.55, 0.8, abs(n.x)) * step(0.3, f) * (1.0 - step(0.9, f));
		float under = COLOR.g * smoothstep(0.35, 0.7, -n.y);
		float panel = clamp(side + under, 0.0, 1.0) * (1.0 - tr);
		float knit = tri_dots(p, w, knit_scale, 0.22) * keep(p, knit_scale);
		float holes = tri_dots(p, w, mesh_scale, 0.3) * keep(p, mesh_scale);
		float weave = mix(knit, holes, panel);
		// Drape folds: rings around the sleeves (bunched at the elbow), long folds down
		// the body.
		float fold_arm = noise3(vec3(f * 26.0, p.y * 4.0, p.z * 4.0));
		float fold_body = noise3(vec3(p.x * 7.0, p.y * 2.0, p.z * 7.0)) * 0.7 + noise3(p * 16.0) * 0.3;
		float fold = mix(fold_body, fold_arm, COLOR.g);
		fold = smoothstep(0.15, 0.85, fold);
		float elbow = COLOR.g * exp(-pow((f - 0.45) * 9.0, 2.0));
		fold = mix(fold, fold * 1.4, elbow);
		// Sewn seams: both edges of every stripe, the hem, the cuff and the shoulder.
		float s = 0.0;
		s += pure.r * (seam(f, hem_band.x) + seam(f, hem_band.y));
		s += pure.g * (seam(f, sleeve_band.x) + seam(f, sleeve_band.y) + seam(f, cuff_start) + seam(f, 0.04));
		if (yoke_r > 0.0) {
			s += seam(yoke_d, yoke_r);
		}
		s = clamp(s, 0.0, 1.0);
		float jh = fold * 1.2 - weave * 0.3 - s * 0.6;
		float js = (0.74 + 0.3 * fold) * (1.0 - 0.14 * weave - 0.14 * panel) * (1.0 - 0.35 * s);
		h += jh * jersey_k;
		shade = mix(shade, js, jersey_k);
		rough = mix(rough, 0.82 - 0.1 * fold, jersey_k);
		rim += 0.25 * jersey_k;
	}

	// --- Pants (breezers) ---------------------------------------------------------
	if (pants_k > 0.01) {
		float y = p.y / quilt_step;
		float channel = fract(y);
		float pillow = sin(3.14159 * channel);                     // puffed padding
		float groove = 1.0 - smoothstep(0.0, 0.08, min(channel, 1.0 - channel));
		float crinkle = noise3(p * 40.0) * keep(p, 40.0);
		float ph = pillow * 0.5 - groove * 0.6 + crinkle * 0.15;
		h += ph * pants_k;
		shade = mix(shade, (0.82 + 0.18 * pillow) * (1.0 - 0.25 * groove), pants_k);
		rough = mix(rough, 0.42 + 0.15 * crinkle, pants_k);
		spec = mix(spec, 0.55, pants_k);
		rim += 0.1 * pants_k;
	}

	// --- Socks: vertical knit ribs ------------------------------------------------
	if (socks_k > 0.01) {
		// Around the leg by the rest normal's heading: ribs stay vertical all the way round.
		float ang = atan(n.z, n.x);
		float rib = 0.5 + 0.5 * sin(ang * sock_ribs);
		rib *= 1.0 - smoothstep(0.25, 0.6, fwidth(ang) * sock_ribs / 6.2832);
		float fold = smoothstep(0.25, 0.85, noise3(vec3(p.x * 8.0, f * 20.0, p.z * 8.0)));
		h += (rib * 0.4 + fold * 0.4) * socks_k;
		shade = mix(shade, (0.88 + 0.12 * rib) * (0.9 + 0.1 * fold), socks_k);
		rough = mix(rough, 0.9, socks_k);
		rim += 0.3 * socks_k;
	}

	// --- Gloves (outfit hands, mostly under the glove models) ----------------------
	if (glove_k > 0.01) {
		float grain = noise3(p * 180.0) * keep(p, 180.0);
		h += grain * 0.2 * glove_k;
		shade = mix(shade, 0.9 + 0.1 * grain, glove_k);
		rough = mix(rough, 0.5, glove_k);
		spec = mix(spec, 0.5, glove_k);
	}

	rough = mix(rough, 0.35, clamp(sk, 0.0, 1.0));
	shade = mix(1.0, shade, detail);
	ALBEDO = c * shade * darken;
	ROUGHNESS = rough;
	SPECULAR = spec;
	RIM = rim * detail;
	RIM_TINT = 0.6;

	// Screen-space bump from the height detail.
	h *= detail * bump;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhx = dFdx(h);
	float dhy = dFdy(h);
	vec3 nrm = normalize(NORMAL);
	vec3 r1 = cross(dpdy, nrm);
	vec3 r2 = cross(nrm, dpdx);
	float det = dot(dpdx, r1);
	if (abs(det) > 1e-12) {
		vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
		NORMAL = normalize(abs(det) * nrm - grad * 0.004);
	}
}
