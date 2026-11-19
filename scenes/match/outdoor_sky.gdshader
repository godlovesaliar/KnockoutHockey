shader_type sky;
// The outdoor rink's sky (ArenaOutdoor): a gradient from the horizon up, the sun or the
// moon (the first directional light) with a glow round it, and stars at night.

uniform vec3 top_color : source_color = vec3(0.24, 0.45, 0.8);
uniform vec3 horizon_color : source_color = vec3(0.72, 0.8, 0.9);
uniform vec3 ground_color : source_color = vec3(0.8, 0.82, 0.86);
uniform float glow = 0.5;          // the haze round the sun
uniform float disc = 0.99955;      // cosine of the disc's radius
uniform float disc_energy = 6.0;
uniform float stars = 0.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(horizon_color, top_color, smoothstep(-0.02, 0.55, h));
	col = mix(col, ground_color, smoothstep(0.0, -0.06, h));
	if (LIGHT0_ENABLED) {
		float s = dot(d, LIGHT0_DIRECTION);
		col += LIGHT0_COLOR * glow * pow(max(s, 0.0), 12.0) * (1.0 - 0.6 * smoothstep(0.0, 0.5, h));
		col += LIGHT0_COLOR * disc_energy * smoothstep(disc, disc + 0.00015, s);
	}
	if (stars > 0.0 && h > 0.0) {
		vec3 p = d * 260.0;
		vec3 c = floor(p);
		float r = hash(c);
		float twinkle = 0.5 + 0.5 * hash(c + 7.0);
		float star = step(0.992, r) * smoothstep(0.42, 0.1, length(fract(p) - 0.5));
		col += vec3(0.9, 0.93, 1.0) * star * stars * twinkle * smoothstep(0.02, 0.3, h);
	}
	COLOR = col;
}
