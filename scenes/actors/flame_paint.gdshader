shader_type spatial;
// Flame paint (SkaterVisual.flame_material: the Stuntmen's stunt helmet). Hot-rod flames
// from the front of the shell, licking back over the top and down both sides in pointed
// tongues of different lengths: `core_color` where they start, turning to `flame_color`
// toward the tips, a pinstripe of `core_color` round their edge, on `base_color`.
// Worked out in the helmets' frame from the point's own place (no texture, no UVs): how far
// back it is from the shell's front (`front`, +Z the face), and where it is round the
// shell's long axis (over the top or down a side), which says which tongue it is in.

uniform vec3 base_color : source_color = vec3(0.08, 0.08, 0.09);
uniform vec3 flame_color : source_color = vec3(0.9, 0.15, 0.55);
uniform vec3 core_color : source_color = vec3(0.92, 0.92, 0.9);
uniform float front = 0.128;     // z of the shell's front, where the flames start
uniform float reach = 0.2;       // how far back the longest tongue goes (m)
uniform float axis_y = 0.05;     // height of the shell's long axis

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

float hash1(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

// How far back the flames reach at `u` round the shell (0..1 of the way round), as a
// share of `reach`: `count` tongues, each a different length, pointed at the tip.
float tongues(float u, float count, float seed) {
	float x = u * count + seed;
	float len = 0.4 + 0.6 * hash1(floor(x) + seed * 7.0);
	return len * pow(1.0 - abs(2.0 * fract(x) - 1.0), 2.1);
}

void fragment() {
	float back = front - lp.z;
	float u = atan(lp.x, lp.y - axis_y) / 6.28318 + 0.5;
	// The tongues waver as they go back.
	u += 0.016 * sin(back * 36.0 + u * 25.0);
	float edge = 0.014 + reach * max(tongues(u, 9.0, 0.0), 0.72 * tongues(u, 15.0, 3.7));
	float soft = max(fwidth(back) * 1.2, 0.0006);
	float inside = 1.0 - smoothstep(edge - soft, edge + soft, back);
	float stripe = 1.0 - smoothstep(0.0022, 0.0022 + soft * 2.0, abs(back - edge));
	vec3 fire = mix(core_color, flame_color, smoothstep(0.0, 0.55, clamp(back / edge, 0.0, 1.0)));
	vec3 col = mix(base_color, fire, inside);
	ALBEDO = mix(col, core_color, stripe);
	ROUGHNESS = 0.22;
	SPECULAR = 0.6;
}
