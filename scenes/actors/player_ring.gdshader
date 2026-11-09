// The controlled player's ring on the ice: two meters drawn as arcs on one flat disc.
// Outer, wide: sprint (stamina), green through yellow to red. Inner, thin: legs (shift
// energy), blue. Both start at the top of the screen (world -Z) and drain counter-
// clockwise back toward it, over a dark track tinted with the player's color.
// Middle: the slap shot's charge, a disc that grows from the center out to the legs ring
// while the shot is held (hidden otherwise).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform float sprint : hint_range(0.0, 1.0) = 1.0;
uniform float legs : hint_range(0.0, 1.0) = 1.0;
uniform vec4 sprint_color : source_color = vec4(0.2, 0.9, 0.3, 1.0);
uniform vec4 legs_color : source_color = vec4(0.25, 0.62, 1.0, 1.0);
uniform vec4 player_color : source_color = vec4(1.0, 0.85, 0.15, 1.0);
uniform float charge : hint_range(0.0, 1.0) = 0.0;   // 0 = not loading a slap shot
uniform vec4 charge_color : source_color = vec4(1.0, 0.45, 0.1, 1.0);
uniform float flash = 0.0;          // 0..1: sprint used up (locked out): the track pulses
uniform vec2 sprint_r = vec2(0.5, 0.62);   // inner, outer radius (m)
uniform vec2 legs_r = vec2(0.395, 0.46);

varying vec2 offs;   // world XZ offset from the ring's center

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	offs = world.xz - MODEL_MATRIX[3].xz;
}

// Coverage of the band [r0, r1], with soft one-pixel edges.
float band(float r, vec2 rr, float aa) {
	return smoothstep(rr.x - aa, rr.x + aa, r) * (1.0 - smoothstep(rr.y - aa, rr.y + aa, r));
}

// Coverage of the filled part of an arc: `frac` of the way round from the top, clockwise.
float arc(float turn, float value, float r, float aa) {
	if (value >= 0.999) return 1.0;
	float edge = (value - turn) * 6.2831853 * r;   // meters from the fill's end, along the arc
	return smoothstep(-aa, aa, edge);
}

void fragment() {
	float r = length(offs);
	float aa = max(fwidth(r), 0.002);
	// 0 at screen-up (-Z), rising clockwise as seen from the camera (toward +X).
	float turn = fract(atan(offs.x, -offs.y) / 6.2831853 + 1.0);

	float s_band = band(r, sprint_r, aa);
	float l_band = band(r, legs_r, aa);
	float s_fill = s_band * arc(turn, sprint, r, aa);
	float l_fill = l_band * arc(turn, legs, r, aa);

	// The sprint track pulses red while sprint is locked out; the legs track stays put.
	vec3 track = mix(vec3(0.02), player_color.rgb, 0.35);
	float pulse = flash * s_band;
	track = mix(track, vec3(0.95, 0.12, 0.08), pulse);
	float track_a = max(s_band, l_band) * (0.6 + 0.3 * pulse);

	// The slap shot charging: a dark well inside the legs ring, filling from the center.
	float well_r = legs_r.x - 0.025;
	float loading = step(0.001, charge);
	float well = loading * (1.0 - smoothstep(well_r - aa, well_r + aa, r));
	float c_fill = well * (1.0 - smoothstep(well_r * charge - aa, well_r * charge + aa, r));

	vec3 col = track;
	float a = track_a;
	col = mix(col, mix(vec3(0.02), charge_color.rgb, 0.2), well);
	a = max(a, well * 0.55);
	col = mix(col, charge_color.rgb, c_fill);
	col = mix(col, sprint_color.rgb, s_fill);
	col = mix(col, legs_color.rgb, l_fill);
	a = max(a, max(c_fill, max(s_fill, l_fill)));
	if (a < 0.003) discard;
	ALBEDO = col;
	ALPHA = a;
}
