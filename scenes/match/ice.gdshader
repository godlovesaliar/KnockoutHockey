shader_type spatial;
// Procedural ice markings. All colors are uniforms so the arena editor can repaint the ice.

uniform vec3 ice_color : source_color = vec3(0.84, 0.88, 0.92);
uniform vec3 red_color : source_color = vec3(0.80, 0.07, 0.10);
uniform vec3 blue_color : source_color = vec3(0.06, 0.22, 0.68);
uniform vec3 crease_color : source_color = vec3(0.40, 0.66, 0.95);
uniform float ice_roughness = 0.12;

// Dimensions (meters) — set from RinkSpec by rink.gd.
uniform float half_w = 12.954;
uniform float half_l = 30.48;
uniform float corner_r = 8.5344;
uniform float goal_line_z = 27.1272;
uniform float blue_line_z = 7.62;
uniform float line_wide = 0.3048;
uniform float line_thin = 0.0508;
uniform float faceoff_r = 4.572;
uniform float end_dot_x = 6.7056;
uniform float end_dot_z = 21.0312;
uniform float neutral_dot_z = 6.096;
uniform float crease_r = 1.8288;

// Center-ice logo (Rink.set_center_logo), over the red line, under the blue. Text runs along +x.
uniform sampler2D center_logo : source_color, filter_linear_mipmap, repeat_disable;
uniform bool has_logo = false;
uniform vec2 logo_size = vec2(6.4, 4.0);   // meters: across (x), along (z)
uniform float logo_strength = 0.92;        // a touch of ice shows through the paint
uniform float logo_flip = 1.0;             // 1 or -1: which end of the rink the top of the logo faces

// Wear (IceWear): blade cuts, snow, haze, and the Zamboni's fresh sheet.
uniform sampler2D wear_cuts : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform sampler2D wear_map : hint_default_black, filter_linear, repeat_disable;
uniform vec2 wear_ext = vec2(13.06, 30.6);
uniform float dull = 0.0;       // the whole sheet's lost shine (0 fresh .. ~0.75 end of period)
uniform float wet = 0.0;        // fresh off the Zamboni: glassy
uniform float sweeping = 0.0;   // 1 during a Zamboni pass: wear_map.b is where it has been

varying vec2 rink_pos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	rink_pos = VERTEX.xz;
}

float rink_sdf(vec2 p) {
	vec2 q = abs(p) - vec2(half_w - corner_r, half_l - corner_r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner_r;
}

float fill(float d, float aa) {
	return 1.0 - smoothstep(-aa, aa, d);
}

// Lines never get thinner than ~2 pixels so they stay readable from the broadcast camera.
float ring(vec2 p, vec2 c, float r, float w, float aa) {
	w = max(w, aa * 2.5);
	return fill(abs(length(p - c) - r) - w * 0.5, aa);
}

float disc(vec2 p, vec2 c, float r, float aa) {
	return fill(length(p - c) - r, aa);
}

float band(float v, float at, float w, float aa) {
	w = max(w, aa * 2.5);
	return fill(abs(v - at) - w * 0.5, aa);
}

void fragment() {
	vec2 p = rink_pos;
	float aa = max(fwidth(p.x), fwidth(p.y)) * 0.75;
	if (rink_sdf(p) > 0.0) {
		discard;
	}

	float az = abs(p.y);
	vec2 mirrored = vec2(abs(p.x), az);
	float in_front = step(az, goal_line_z);

	vec3 col = ice_color;

	// Goal creases (semicircles in front of each goal line).
	float crease = fill(length(vec2(p.x, az - goal_line_z)) - crease_r, aa) * in_front;
	col = mix(col, crease_color, crease);


	// Red: center line, goal lines, end-zone circles and dots, neutral-zone dots, crease outline.
	float red = band(p.y, 0.0, line_wide, aa);
	red = max(red, band(az, goal_line_z, line_thin, aa));
	red = max(red, ring(mirrored, vec2(end_dot_x, end_dot_z), faceoff_r, line_thin, aa));
	red = max(red, disc(mirrored, vec2(end_dot_x, end_dot_z), 0.3048, aa));
	red = max(red, disc(mirrored, vec2(end_dot_x, neutral_dot_z), 0.3048, aa));
	red = max(red, ring(vec2(p.x, az), vec2(0.0, goal_line_z), crease_r, line_thin, aa) * in_front);

	// Blue: blue lines, center circle and dot.
	float blue = band(az, blue_line_z, line_wide, aa);
	blue = max(blue, ring(p, vec2(0.0), faceoff_r, line_thin, aa));
	blue = max(blue, disc(p, vec2(0.0), 0.1524, aa));

	col = mix(col, red_color, red);
	// The logo goes over the red line (as many arenas paint it), under the blue circle.
	if (has_logo) {
		vec2 uv = vec2(p.x * logo_flip, p.y * logo_flip) / logo_size + 0.5;
		if (uv.x > 0.0 && uv.x < 1.0 && uv.y > 0.0 && uv.y < 1.0) {
			vec4 lg = texture(center_logo, uv);
			col = mix(col, lg.rgb, lg.a * logo_strength);
		}
	}
	col = mix(col, blue_color, blue);

	// Wear: everything above is the paint under the ice; the scuffed surface over it
	// frosts white and loses its shine.
	vec2 wuv = p / wear_ext * 0.5 + 0.5;
	vec4 wm = texture(wear_map, wuv);
	float keep = 1.0 - wm.b * sweeping;          // swept by the Zamboni this pass: clean
	float laid = mix(1.0, wm.b, sweeping);       // ...and wet
	float cut = clamp(texture(wear_cuts, wuv).r * 2.5, 0.0, 1.0) * keep;
	float grain = vnoise(p * 3.1) * 0.6 + vnoise(p * 11.0) * 0.4;
	float snow = smoothstep(0.05, 0.7, wm.r * (0.55 + grain * 0.9)) * keep;
	float haze = clamp(dull * (0.55 + 0.45 * grain) + wm.g * 1.4, 0.0, 1.0) * keep;
	// Clean ice is glassy: it mirrors the dark of the arena, more at a grazing angle, and
	// reads deeper and a touch darker; fresh off the Zamboni (wet) all the more. Wear takes
	// that away: haze turns the sheet a flat matte white, the cuts are fine grey gouges
	// that hold shadow and rubber, snow piles up bright white.
	float wet_k = wet * laid;
	float gloss = clamp((1.0 - haze) * (1.0 - snow) * (0.55 + 0.45 * wet_k), 0.0, 1.0);
	float graze = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	col *= 1.0 - 0.07 * gloss - 0.08 * wet_k;
	col = mix(col, col * vec3(0.9, 0.95, 1.0), wet_k * 0.6);   // wet: a cool, clear tint
	col = mix(col, vec3(0.30, 0.33, 0.40), clamp(graze * gloss * 0.75, 0.0, 0.6));
	col = mix(col, vec3(0.95, 0.96, 0.97) * max(col.r, max(col.g, col.b)) / 0.92, haze * 0.25);
	col = mix(col, vec3(0.47, 0.5, 0.54), cut * 0.75);
	col = mix(col, vec3(0.97, 0.98, 1.0), clamp(snow, 0.0, 1.0));

	float rough = mix(ice_roughness, 0.42, haze);
	rough = mix(rough, 0.75, max(cut * 0.8, snow));
	rough = mix(rough, 0.03, wet_k);
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = mix(0.6, 0.35, max(haze, snow)) + 0.15 * wet_k;
}
