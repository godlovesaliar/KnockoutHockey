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

varying vec2 rink_pos;

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

	ALBEDO = col;
	ROUGHNESS = ice_roughness;
	SPECULAR = 0.6;
}
