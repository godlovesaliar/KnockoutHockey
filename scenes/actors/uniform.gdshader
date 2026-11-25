shader_type spatial;
render_mode cull_disabled; // the inside of sleeves and collars shows at the hems
// Team uniform on the outfit layer. Layout: uniform_regions.gdshaderinc.
//
// Detail is procedural, pinned to the cloth by the rest-pose position / normal the build
// step bakes into CUSTOM0 / CUSTOM1 (arms in a T-pose, origin at the base of the neck,
// torso scaled to 0.6 m), so it doesn't swim when the body moves and fits every body:
//   jersey  knit dimples, coarser mesh panels down the sides and under the arms, drape
//           folds (around the sleeves, down the body), sewn seams at every stripe edge
//   pants   nylon shell with sheen, quilted padding channels; or matte canvas (the old-time
//           kit); or a smooth long shell to the skates, striped down the side
//   socks   ribbed knit; or heavy wool; clear tape round the shin on taped ones
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
// With a skate model on (SkaterVisual.add_skates): the sock ends here, over the boot's collar
// (position along the leg, 1 = the ankle joint), and the foot inside the boot is not drawn.
instance uniform float sock_end = 2.0;
// With gloves on, the sleeve ends here, inside the glove's cuff (position along the arm,
// 1 = the wrist): SkaterVisual sets it where a cuffed glove is worn.
instance uniform float sleeve_end = 2.0;
// What this player wears on the legs (SkaterVisual.dress_legs): their own choice, or the
// team's kit. Pants: 0 the padded nylon shell, 1 old-time canvas, 2 long pants over the
// socks. Socks: 0 knit, 1 knit with clear tape below the knee and over the ankle, 2 wool.
instance uniform float pants_style = 0.0;
instance uniform float sock_style = 0.0;

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
// Officials: `vstripes` vertical stripes in the accent color around the torso (and in
// proportion around each sleeve), alternating with the jersey color. 0 = none.
uniform float vstripes = 0.0;
// Officials: long pants down over the legs instead of socks (socks drawn as pants).
uniform bool long_pants = false;
const vec2 TAPE_KNEE = vec2(0.555, 0.6);     // leg: the tape below the knee
const vec2 TAPE_ANKLE = vec2(0.085, 0.035);  // leg: the tape over the ankle, back from the sock's end
uniform vec3 yoke_shape = vec3(0.8, 2.6, 0.0);   // z 0: depth ignored, so pads poking through the jersey agree with it
// Prints: the crest on the chest, the number and the nameplate on the back. Part of the
// cloth (placed in its rest space, like the rest of the detail), so they bend and fold
// with the jersey and never land on an arm, a glove or a stick passing in front of it.
// Each box: center x, center y, 1 / width, 1 / height in rest space (0 = no print).
// Set per player on their own copy of the material (SkaterVisual._print).
uniform sampler2D crest_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D number_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D name_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 crest_box = vec4(0.0);
uniform vec4 number_box = vec4(0.0);
uniform vec4 name_box = vec4(0.0);

varying vec3 rest_p;
varying vec3 rest_n;

// 1 on the two bands of tape round a taped sock, at `f` along the leg (`w`: edge softness).
float tape_at(float f, float w) {
	float e = min(sock_end, 0.96);
	return smoothstep(TAPE_KNEE.x - w, TAPE_KNEE.x + w, f) * (1.0 - smoothstep(TAPE_KNEE.y - w, TAPE_KNEE.y + w, f))
			+ smoothstep(e - TAPE_ANKLE.x - w, e - TAPE_ANKLE.x + w, f) * (1.0 - smoothstep(e - TAPE_ANKLE.y - w, e - TAPE_ANKLE.y + w, f));
}

void vertex() {
	rest_p = CUSTOM0.xyz;
	rest_n = CUSTOM1.xyz;
	// Over a skate model the sock's front lies flat on the shin for its last few centimeters:
	// the skate's tongue stands in front of it.
	if (sock_end < 1.5 && COLOR.b > 0.5) {
		VERTEX -= NORMAL * 0.012 * smoothstep(sock_end - 0.09, sock_end - 0.02, UV2.y) * smoothstep(0.2, 0.8, rest_n.z);
	}
	if (COLOR.b > 0.5) {
		if (pants_style > 1.5) {
			// Long pants hang a little clear of the shin.
			VERTEX += NORMAL * 0.007 * smoothstep(pants_leg, pants_leg + 0.12, UV2.y);
		} else if (sock_style > 0.5 && sock_style < 1.5) {
			// Tape pulls the sock in.
			VERTEX -= NORMAL * 0.007 * tape_at(UV2.y, 0.008);
		}
	}
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

// A print at rest position `p`: its color, and in alpha how much of it covers the cloth
// here. `side` 1 on the chest (picture right = the wearer's left), -1 on the back.
vec4 print(sampler2D tex, vec4 box, vec2 p, float side) {
	vec2 uv = vec2((p.x - box.x) * box.z * side, (box.y - p.y) * box.w) + 0.5;
	vec4 c = texture(tex, uv);
	vec2 in_box = step(vec2(0.0), uv) * step(uv, vec2(1.0));
	c.a *= in_box.x * in_box.y;
	return c;
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
	if (gloves_worn > 0.5 && COLOR.g > 0.5 && UV2.y > sleeve_end) {
		discard;
	}
	if (sock_end < 1.5 && (sk > 0.5 || (COLOR.b > 0.25 && UV2.y > sock_end * COLOR.b))) {
		discard;
	}
	// Long pants: the socks' part of the leg is pants too, and carries no sock stripes.
	float long_k = step(1.5, pants_style);
	float canvas_k = step(0.5, pants_style) * (1.0 - long_k);
	if (long_k > 0.5) {
		part.y += part.z;
		part.z = 0.0;
		float leg = smoothstep(0.9, 1.0, COLOR.b);
		tr *= 1.0 - leg;
		acc *= 1.0 - leg;
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
	vec3 jcol = jersey;
	if (vstripes > 0.0) {
		// Around the torso's vertical axis, or around the arm (T-pose: arms along x).
		float torso_u = atan(rest_p.x, rest_p.z) / 6.2831853 * vstripes;
		float arm_u = atan(rest_p.y, rest_p.z) / 6.2831853 * max(floor(vstripes * 0.32 + 0.5), 2.0);
		float aw = COLOR.g / max(COLOR.r + COLOR.g, 1e-3);
		float u = mix(torso_u, arm_u, step(0.5, aw));
		float fr = fract(u);
		float aa = clamp(fwidth(u) * 1.5, 0.002, 0.25);
		float band = smoothstep(0.25 - aa, 0.25 + aa, fr) * (1.0 - smoothstep(0.75 - aa, 0.75 + aa, fr));
		jcol = mix(jersey, accent_color, band);
	}
	float sock_k = long_pants ? 0.0 : 1.0;
	vec3 c = jcol * (part.x - tr) + jersey * part.z * sock_k + trim * (tr - acc) + accent_color * acc
			+ pants * (part.y + part.z * (1.0 - sock_k)) + gloves * part.w + skates * sk;
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
	// How squarely the cloth faces out to the wearer's side (1 on the outside of a leg).
	float out_x = n.x * sign(p.x);
	if (long_k > 0.5) {
		// A stripe in the trim color down the outside of each leg, waist to skate.
		float sw = max(fwidth(out_x), 0.004);
		c = mix(c, trim, smoothstep(0.945 - sw, 0.945 + sw, out_x) * pants_k);
	}

	// Prints, on the outside of the jersey's body: the chest faces forward at rest, the
	// back backward (fading out where the cloth turns to the sides). Under the fabric
	// detail below, so the folds and the knit run through them.
	// (The branches are on uniforms only: the texture lookups keep their mip levels.)
	float print_k = jersey_k * COLOR.r * (FRONT_FACING ? 1.0 : 0.0);
	float chest = print_k * smoothstep(0.0, 0.3, n.z);
	float back = print_k * smoothstep(0.0, 0.3, -n.z);
	if (crest_box.z > 0.0) {
		vec4 t = print(crest_tex, crest_box, p.xy, 1.0);
		c = mix(c, t.rgb, t.a * chest);
	}
	if (number_box.z > 0.0) {
		vec4 t = print(number_tex, number_box, p.xy, -1.0);
		c = mix(c, t.rgb, t.a * back);
	}
	if (name_box.z > 0.0) {
		vec4 t = print(name_tex, name_box, p.xy, -1.0);
		c = mix(c, t.rgb, t.a * back);
	}

	float h = 0.0;          // height detail (bump)
	float shade = 1.0;      // albedo multiplier
	float rough = 0.8;
	float spec = 0.35;
	float rim = 0.0;
	float tape_k = 0.0;     // clear tape over the sock: milky, and glossy

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
		// The modelled jersey (UV2.x < 0) has its folds in the mesh: only a faint body
		// ripple here, and none of the sleeve rings (they follow UV2.y, which jumps where
		// the torso hands over to the sleeve).
		float modelled = step(0.1, -UV2.x);
		float fold = mix(fold_body, fold_arm, COLOR.g * (1.0 - modelled));
		fold = smoothstep(0.15, 0.85, fold);
		float elbow = COLOR.g * exp(-pow((f - 0.45) * 9.0, 2.0)) * (1.0 - modelled);
		fold = mix(fold, fold * 1.4, elbow);
		fold = mix(fold, 0.5 + (fold - 0.5) * 0.3, modelled);
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
		float crinkle = noise3(p * 40.0) * keep(p, 40.0);
		if (canvas_k > 0.5) {
			// Old-time canvas: a matte plain weave, unevenly worn, creased across the lap
			// and down the legs, with a stitched seam down the outside and a hem at the knee.
			float weave = tri_dots(p, w, 300.0, 0.3) * keep(p, 300.0);
			float wear = noise3(p * 11.0) * 0.6 + noise3(p * 34.0) * 0.4;
			float crease = smoothstep(0.3, 0.8, noise3(vec3(p.x * 9.0, p.y * 5.0, p.z * 9.0)));
			float sw = max(fwidth(out_x), 0.002);
			float side_seam = 1.0 - smoothstep(0.0, sw * 1.5 + 0.004, abs(out_x - 0.985));
			float hem = pure.b * seam(f, pants_leg - 0.025);
			float st = clamp(side_seam + hem, 0.0, 1.0);
			h += (crease * 1.0 - weave * 0.25 - st * 0.6 + crinkle * 0.2) * pants_k;
			shade = mix(shade, (0.8 + 0.2 * wear) * (0.86 + 0.14 * crease) * (1.0 - 0.1 * weave) * (1.0 - 0.3 * st), pants_k);
			rough = mix(rough, 0.93, pants_k);
			spec = mix(spec, 0.2, pants_k);
			rim += 0.2 * pants_k;
		} else if (long_k > 0.5) {
			// Long pants: one smooth nylon shell, no padding channels, long folds down the leg.
			float fold = smoothstep(0.25, 0.8, noise3(vec3(p.x * 14.0, p.y * 3.0, p.z * 14.0)));
			h += (fold * 0.9 + crinkle * 0.25) * pants_k;
			shade = mix(shade, 0.8 + 0.2 * fold, pants_k);
			rough = mix(rough, 0.36 + 0.15 * crinkle, pants_k);
			spec = mix(spec, 0.6, pants_k);
			rim += 0.12 * pants_k;
		} else {
			float y = p.y / quilt_step;
			float channel = fract(y);
			float pillow = sin(3.14159 * channel);                     // puffed padding
			float groove = 1.0 - smoothstep(0.0, 0.08, min(channel, 1.0 - channel));
			float ph = pillow * 0.5 - groove * 0.6 + crinkle * 0.15;
			h += ph * pants_k;
			shade = mix(shade, (0.82 + 0.18 * pillow) * (1.0 - 0.25 * groove), pants_k);
			rough = mix(rough, 0.42 + 0.15 * crinkle, pants_k);
			spec = mix(spec, 0.55, pants_k);
			rim += 0.1 * pants_k;
		}
	}

	// --- Socks: vertical knit ribs ------------------------------------------------
	if (socks_k > 0.01) {
		// Around the leg by the rest normal's heading: ribs stay vertical all the way round.
		float ang = atan(n.z, n.x);
		float wool_k = step(1.5, sock_style);
		// Wool: half as many ribs, twice as heavy.
		float ribs = sock_ribs * mix(1.0, 0.5, wool_k);
		float rib = 0.5 + 0.5 * sin(ang * ribs);
		rib *= 1.0 - smoothstep(0.25, 0.6, fwidth(ang) * ribs / 6.2832);
		float fold = smoothstep(0.25, 0.85, noise3(vec3(p.x * 8.0, f * 20.0, p.z * 8.0)));
		float sh = rib * 0.4 + fold * 0.4;
		float ss = (0.88 + 0.12 * rib) * (0.9 + 0.1 * fold);
		float sr = 0.9;
		float sp = spec;
		float srim = 0.3;
		if (wool_k > 0.5) {
			// Knit rows across the ribs, fuzz, uneven yarn, and the sock sagging in rings
			// toward the ankle.
			float rows = (0.5 + 0.5 * sin(f * 520.0)) * (1.0 - smoothstep(0.25, 0.6, fwidth(f) * 520.0 / 6.2832));
			float fuzz = noise3(p * 260.0) * keep(p, 260.0);
			float yarn = noise3(p * 60.0);
			float sag = smoothstep(0.3, 0.8, noise3(vec3(p.x * 5.0, f * 60.0, p.z * 5.0))) * smoothstep(0.62, 0.88, f);
			sh = rib * 0.75 + rows * 0.2 + fuzz * 0.2 + fold * 0.4 + sag * 1.1;
			ss = (0.78 + 0.22 * rib) * (0.92 + 0.08 * rows) * (0.86 + 0.14 * yarn) * (0.9 + 0.1 * fold) * (0.84 + 0.16 * sag);
			sr = 1.0;
			srim = 0.55;
		} else if (sock_style > 0.5) {
			// Clear tape: glossy, the knit pressed flat under it, its windings showing as
			// faint rings.
			float tape = tape_at(f, max(fwidth(f), 0.0015));
			float wind = 0.5 + 0.5 * sin(f * 420.0);
			sh = mix(sh, wind * 0.12 - 0.35, tape);
			ss = mix(ss, 1.0 + 0.06 * wind, tape);
			tape_k = tape * socks_k;
			sr = mix(sr, 0.14, tape);
			sp = mix(sp, 0.8, tape);
			srim = mix(srim, 0.0, tape);
		}
		h += sh * socks_k;
		shade = mix(shade, ss, socks_k);
		rough = mix(rough, sr, socks_k);
		spec = mix(spec, sp, socks_k);
		rim += srim * socks_k;
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
	ALBEDO = mix(c * shade, vec3(0.9), tape_k * 0.22) * darken;
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
