shader_type spatial;
// Seated fans (one MultiMesh instance each). The mesh is built by Arena._fan_mesh with
// its body part in UV.x (0.1 legs, 0.12 shoes, 0.35 torso, 0.6 arms, 0.65 hands,
// 0.8 neck, 0.85 head, 0.86 nose, 0.97 cap brim) and the position along the part in UV.y.
// Instance color = outfit color A. INSTANCE_CUSTOM: x seed (idle phase and looks: skin,
// hair, pants, face), y how easily they stand (0 = first up), z color B packed 8 bits a
// channel, w outfit + 4 * hat + 16 * hat color (see Arena._recolor). `excitement` (0 calm
// .. 1 a home goal) is set by the arena from crowd reactions: the keenest fans stand,
// bounce, throw their arms up and yell.
// Hair, hats, jersey stripes and faces are painted here from the rest pose, and fade out
// when a fan is only a few pixels tall so the stands don't shimmer.

uniform float excitement : hint_range(0.0, 1.0) = 0.0;
// Jersey crests (Arena._crest): transparent when a team has no logo.
uniform sampler2D home_logo : source_color, hint_default_transparent, filter_linear_mipmap, repeat_disable;
uniform sampler2D away_logo : source_color, hint_default_transparent, filter_linear_mipmap, repeat_disable;

const vec3 HEAD = vec3(0.0, 1.21, -0.19);

const vec3 PANTS[6] = vec3[6](vec3(0.18, 0.24, 0.38), vec3(0.1, 0.12, 0.18), vec3(0.06, 0.06, 0.07),
		vec3(0.5, 0.45, 0.36), vec3(0.33, 0.33, 0.35), vec3(0.24, 0.3, 0.45));
const vec3 HAIR[6] = vec3[6](vec3(0.04, 0.03, 0.025), vec3(0.12, 0.07, 0.04), vec3(0.3, 0.18, 0.09),
		vec3(0.68, 0.54, 0.3), vec3(0.55, 0.53, 0.5), vec3(0.45, 0.17, 0.07));

varying vec3 rest;        // the vertex before animation (model space)
// The rest are the same on every vertex of a fan: `flat` skips interpolating them per
// pixel (same result, less work for the GPU).
varying flat vec3 col_a;
varying flat vec3 col_b;
varying flat vec3 skin;
varying flat vec3 pants;
varying flat vec3 hair;
varying flat vec3 hat_col;
varying flat vec4 look;   // outfit, hat, cheer (mouth open), seed
varying flat vec4 traits; // hair style, beard, glasses, short sleeves / print (0..1 each)
varying flat float crest; // jersey logo: 0 none, 1 home, 2 away

vec3 lin(vec3 c) {
	return pow(max(c, vec3(0.0)), vec3(2.2));
}

float hash(float n) {
	return fract(sin(n * 127.1 + 31.7) * 43758.5453);
}

// Per-fan fabric: a little faded or darker, so a section in one jersey isn't one flat color.
vec3 fabric(vec3 c, float h1, float h2) {
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	return mix(c, vec3(l), h1 * 0.32) * (0.8 + h2 * 0.28);
}

void vertex() {
	vec4 c = INSTANCE_CUSTOM;
	float seed = c.x * 7919.0;
	float ph = c.x * 6.2831;
	float part = UV.x;
	float style = floor(c.w + 0.5);
	float outfit = mod(style, 4.0);
	float hat = mod(floor(style / 4.0), 4.0);
	float hat_pick = mod(floor(style / 16.0), 4.0);
	crest = floor(style / 64.0);
	rest = VERTEX;

	float stand = smoothstep(c.y, c.y + 0.12, excitement);
	float bounce = stand * max(0.0, sin(TIME * (7.0 + c.x * 3.0) + ph)) * 0.1 * excitement;
	float raise = stand * clamp(0.75 + 0.35 * sin(TIME * (4.0 + c.x * 2.0) + ph * 2.0), 0.0, 1.0);
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	if (part > 0.9) {
		// Cap brim: folded into the head unless they wear a cap; some wear it backwards.
		if (hat < 1.5 || hat > 2.5) {
			v = HEAD;
		} else if (hash(seed + 9.0) < 0.22) {
			v.z = 2.0 * HEAD.z - v.z;
			n.z = -n.z;
		}
	} else if (part > 0.84 && hat > 0.5 && hat < 1.5) {
		// A beanie sits a bit proud of the crown.
		vec3 d = v - HEAD;
		v = HEAD + d * (1.0 + 0.09 * smoothstep(0.0, 0.06, d.y));
	}
	if (part > 0.5 && part < 0.7) {
		// Arms swing up about the shoulder (around local X), spreading into a V.
		float sx = sign(v.x);
		vec3 piv = vec3(sx * 0.21, 0.98, -0.2);
		vec3 d = v - piv;
		vec3 dn = n;
		float a = -2.6 * raise;
		d = vec3(d.x, d.y * cos(a) - d.z * sin(a), d.y * sin(a) + d.z * cos(a));
		dn = vec3(dn.x, dn.y * cos(a) - dn.z * sin(a), dn.y * sin(a) + dn.z * cos(a));
		d.x += sx * max(d.y, 0.0) * 0.45;
		v = piv + d;
		n = dn;
	}
	if (part > 0.2) {
		v.y += stand * 0.38 + bounce;
	}
	// A little idle sway so the stands never freeze.
	v.x += sin(TIME * 1.1 + ph) * 0.02 * v.y;
	v.z += sin(TIME * 0.7 + ph * 1.7) * 0.012 * v.y;
	VERTEX = v;
	NORMAL = normalize(n);

	vec3 b = vec3(mod(c.z, 256.0), mod(floor(c.z / 256.0), 256.0), floor(c.z / 65536.0)) / 255.0;
	col_a = lin(fabric(COLOR.rgb, hash(seed + 1.0), hash(seed + 2.0)));
	col_b = lin(fabric(b, hash(seed + 3.0) * 0.6, hash(seed + 2.0)));
	float t = pow(hash(seed + 4.0), 1.5);
	vec3 s = t < 0.5 ? mix(vec3(0.96, 0.8, 0.68), vec3(0.76, 0.55, 0.4), t * 2.0)
			: mix(vec3(0.76, 0.55, 0.4), vec3(0.28, 0.18, 0.11), t * 2.0 - 1.0);
	skin = lin(s);
	pants = lin(PANTS[int(hash(seed + 5.0) * 5.999)]);
	float hc = hash(seed + 6.0);
	// Darker hair is commoner; grey mostly goes with the bald and short styles below.
	hair = lin(HAIR[hc < 0.35 ? 0 : hc < 0.6 ? 1 : hc < 0.75 ? 2 : hc < 0.85 ? 3 : hc < 0.95 ? 4 : 5]);
	vec3 hcol = hat_pick < 0.5 ? COLOR.rgb : hat_pick < 1.5 ? b : hat_pick < 2.5 ? vec3(0.06) : vec3(0.9);
	hat_col = lin(hcol);
	look = vec4(outfit, hat, stand * (0.5 + 0.5 * sin(TIME * 5.0 + ph * 3.0)), seed);
	traits = vec4(hash(seed + 7.0), hash(seed + 8.0), hash(seed + 10.0), hash(seed + 11.0));
}

// Coverage of the band a..b around x for a pixel `px` wide; thin bands fade out far away.
float band(float x, float a, float b, float px) {
	float cov = clamp(min(x - a, b - x) / px + 0.5, 0.0, 1.0);
	return cov * clamp((b - a) / px - 0.5, 0.0, 1.0);
}

// Inside the ellipse (unit at 1), antialiased for a pixel `px` wide against size `r`.
float blob(vec2 d, vec2 r, float px) {
	float k = length(d / r);
	return clamp((1.0 - k) * min(r.x, r.y) / px + 0.5, 0.0, 1.0);
}

// The crest 0.17 m wide centered on `q` (meters across the chest), in linear color.
vec4 crest_at(vec2 q, bool away) {
	vec2 ts = away ? vec2(textureSize(away_logo, 0)) : vec2(textureSize(home_logo, 0));
	float w = 0.17;
	vec2 uv = vec2(q.x / w + 0.5, 0.5 - q.y / (w * ts.y / max(ts.x, 1.0)));
	vec4 t = away ? texture(away_logo, uv) : texture(home_logo, uv);
	vec2 inside = step(vec2(0.0), uv) * step(uv, vec2(1.0));
	return t * inside.x * inside.y;
}

vec3 torso(float px) {
	float outfit = look.x;
	vec3 c = col_a;
	bool front = rest.z > -0.2;
	if (outfit < 0.5) {
		// Tee: some have a print on the chest, a block with a line of "lettering" under it.
		if (traits.w > 0.6 && front) {
			float l = dot(col_a, vec3(0.3, 0.59, 0.11));
			vec3 ink = l > 0.12 ? col_a * 0.25 : vec3(0.55);
			float wide = 0.05 + 0.03 * hash(look.w + 13.0);
			float p = band(rest.x, -wide, wide, px) * band(rest.y, 0.8, 0.86, px);
			p = max(p, band(rest.x, -wide * 0.8, wide * 0.8, px) * band(rest.y, 0.765, 0.785, px));
			c = mix(c, ink, p * 0.8);
		}
	} else if (outfit < 1.5) {
		// Jersey: hem stripes, a contrasting yoke and the team's crest.
		float s = max(band(rest.y, 0.53, 0.575, px), band(rest.y, 0.6, 0.62, px));
		s = max(s, band(rest.y, 0.955, 2.0, px));
		c = mix(c, col_b, s);
		if (front && crest > 0.5) {
			vec4 logo = crest_at(vec2(rest.x, rest.y - 0.79), crest > 1.5);
			c = mix(c, logo.rgb, logo.a);
		}
	} else if (outfit < 2.5) {
		// Open jacket over a shirt.
		if (front) {
			float w = mix(0.035, 0.085, smoothstep(0.55, 0.98, rest.y));
			c = mix(c, col_b, band(rest.x, -w, w, px) * step(rest.y, 1.0));
		}
	} else {
		// Hoodie: a front pocket and the hood bunched at the back of the neck.
		if (front) {
			c *= 1.0 - 0.3 * band(rest.y, 0.55, 0.68, px) * band(rest.x, -0.1, 0.1, px);
		} else {
			c *= 1.0 - 0.35 * smoothstep(0.85, 1.0, rest.y);
		}
	}
	return c;
}

vec3 sleeve(float along, float px) {
	float outfit = look.x;
	if (outfit < 0.5 && traits.w < 0.5 && along > 0.3) {
		return skin;                       // short sleeves
	}
	vec3 c = col_a;
	if (outfit > 0.5 && outfit < 1.5) {
		c = mix(c, col_b, max(band(along, 0.55, 0.63, px), band(along, 0.67, 0.71, px)));
	}
	return c;
}

vec3 head(float px) {
	vec3 h = rest - HEAD;
	float front = h.z / max(length(h.xz), 1e-4);    // 1 facing ahead .. -1 the back
	float hat = look.y;
	float detail = 1.0 - smoothstep(0.004, 0.009, px);
	vec3 c = skin;
	// Hair: a style from bald to long, the hairline lower at the back.
	float st = traits.x;
	float fore = st < 0.1 ? 0.2 : 0.045 + 0.02 * hash(look.w + 12.0);
	float back = st < 0.1 ? -0.05 : st < 0.65 ? -0.06 : st < 0.85 ? -0.09 : -0.12;
	float line = mix(back, fore, smoothstep(-0.4, 0.5, front));
	float hm = smoothstep(line - px, line + px, h.y);
	if (st < 0.1) {
		hm = band(h.y, -0.06, 0.03, px) * (1.0 - smoothstep(0.1, 0.3, front));   // bald, a fringe round the back
	}
	c = mix(c, hair, hm);
	// Face.
	if (front > 0.45 && h.y < fore) {
		float f = 0.0;
		vec3 ink = vec3(0.03, 0.02, 0.02);
		vec2 e = vec2(abs(h.x) - 0.034, h.y - 0.012);
		if (traits.z < 0.06) {
			c = mix(c, vec3(0.02), band(h.y, -0.002, 0.026, px) * band(h.x, -0.065, 0.065, px) * detail);
		} else {
			c = mix(c, ink, blob(e, vec2(0.012, 0.008), px) * detail);
		}
		// Brows.
		c = mix(c, hair * 0.7, band(h.y, 0.032, 0.041, px) * band(abs(h.x), 0.016, 0.052, px) * detail);
		// Beard.
		if (traits.y < 0.18 && h.y < -0.012) {
			c = mix(c, hair, 0.9 * (1.0 - smoothstep(-0.03, -0.012, h.y + 0.012 * (1.0 - front))));
		}
		// Mouth, open when they yell.
		float open = look.z;
		vec2 m = vec2(h.x, h.y + 0.05 + 0.006 * open);
		c = mix(c, vec3(0.2, 0.04, 0.04), blob(m, vec2(0.022 + 0.004 * open, 0.004 + 0.013 * open), px) * detail);
	}
	// Hats over everything above the brow.
	if (hat > 0.5 && hat < 1.5 && h.y > 0.025) {
		c = hat_col * (h.y < 0.05 ? 0.75 : 1.0);   // beanie with a folded cuff
	} else if (hat > 1.5 && h.y > 0.045) {
		c = hat_col;
	}
	return c;
}

void fragment() {
	float part = UV.x;
	float px = max(length(fwidth(rest)), 1e-4);   // meters a pixel spans, about
	vec3 col;
	float ao = 1.0;
	if (part < 0.11) {
		col = pants;
		ao = 0.72 * mix(0.75, 1.0, smoothstep(0.1, 0.45, rest.y));
	} else if (part < 0.2) {
		col = traits.y > 0.7 ? lin(vec3(0.85)) : lin(vec3(0.08));   // shoes
		ao = 0.6;
	} else if (part < 0.5) {
		col = torso(px);
		ao = mix(0.55, 1.0, smoothstep(0.42, 0.92, rest.y));
	} else if (part < 0.62) {
		col = sleeve(UV.y, px);
		ao = 0.92;
	} else if (part < 0.7) {
		col = skin;
		ao = 0.9;
	} else if (part < 0.83) {
		col = skin;
		ao = 0.65;
	} else if (part < 0.855) {
		col = head(px);
	} else if (part < 0.9) {
		col = skin;                            // nose
	} else {
		col = hat_col * 0.9;                   // cap brim
	}
	ALBEDO = col * ao * 0.85;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
}
