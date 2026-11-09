shader_type spatial;
render_mode cull_disabled;
// Hockey glove and its cuff (tools/blender/hand_gear.py). The model's vertex colors are
// baked in Blender:
//   COLOR.r  how open the surface is: 1 on the pads, toward 0 in creases, between the
//            finger rolls and under the knuckle roll (ambient occlusion)
//   COLOR.g  palm leather: the palm and the inside of the fingers and thumb
//   COLOR.b  stitched seams: 1 along the seam lines carved into the padding
//   COLOR.a  1 - trim: the cuff's strap band and rolled rim are in the trim color
// The padding is a nylon shell (a visible weave, a soft sheen); the palm a darker,
// rougher grained leather. Detail is pinned to the model (its own vertex positions) and
// fades out with distance before it can shimmer.

uniform vec3 shell : source_color = vec3(0.55, 0.08, 0.1);
uniform vec3 palm : source_color = vec3(0.2, 0.19, 0.18);
uniform vec3 trim : source_color = vec3(0.94, 0.94, 0.92);
uniform float occlusion = 1.0;      // how dark the creases get (0 = no baked shading)
uniform float seam_dark = 0.45;     // how dark a stitched seam is
uniform float weave_scale = 320.0;  // nylon weave cells per meter (model space)
uniform float grain_scale = 380.0;  // leather grain cells per meter
uniform float stitch_scale = 260.0; // stitches per meter along the seams
uniform float bump = 1.0;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
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

// 1 while a pattern of `freq` cells per meter is still several pixels per cell.
float keep(vec3 p, float freq) {
	return 1.0 - smoothstep(0.3, 0.7, length(fwidth(p)) * freq);
}

void fragment() {
	float open = COLOR.r;
	float pm = smoothstep(0.2, 0.8, COLOR.g);
	float seam = smoothstep(0.15, 0.85, COLOR.b);
	float tr = (1.0 - smoothstep(0.2, 0.8, COLOR.a)) * (1.0 - pm);
	float ao = mix(1.0, smoothstep(0.3, 0.97, open), occlusion);

	// Nylon: a crosshatched weave; leather: pebbled grain.
	float wk = keep(lp, weave_scale);
	vec3 wp = lp * weave_scale * 3.14159;
	float weave = (sin(wp.x + wp.y) * sin(wp.y - wp.z + wp.x * 0.5)) * 0.5 + 0.5;
	weave *= wk;
	float grain = noise3(lp * grain_scale) * 0.7 + noise3(lp * grain_scale * 2.3) * 0.3;
	grain *= keep(lp, grain_scale * 2.3);
	// Stitches: dashes along the seams (lighter thread on the dark seam line).
	float sk = keep(lp, stitch_scale);
	float dash = step(0.45, fract((lp.x + lp.y * 0.7 + lp.z * 0.4) * stitch_scale)) * sk;
	float thread = seam * (1.0 - seam) * 4.0 * dash;     // along the seam's shoulders

	vec3 base = mix(mix(shell, trim, tr), palm, pm);
	float shade = (0.35 + 0.65 * ao) * (1.0 - seam_dark * seam) * (1.0 - 0.08 * weave * (1.0 - pm)) * (1.0 - 0.07 * grain * pm);
	ALBEDO = mix(base * shade, base * 1.15 + 0.08, thread * 0.5);
	ROUGHNESS = mix(0.45, 0.78, pm) + 0.12 * (1.0 - ao);
	SPECULAR = mix(0.5, 0.3, pm);
	AO = ao;
	AO_LIGHT_AFFECT = 0.6;
	RIM = 0.12 * (1.0 - pm) * ao;      // the nylon's sheen at grazing angles
	RIM_TINT = 0.5;

	// Screen-space bump from the height detail (kept small: the shapes carry the form).
	float h = mix(weave * 0.14, grain * 0.5, pm) - seam * 0.6;
	h *= bump;
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
		NORMAL = normalize(abs(det) * nrm - grad * 0.0006);
	}
}
