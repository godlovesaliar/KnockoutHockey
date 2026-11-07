// Uniform layout, shared by uniform.gdshader (the outfit) and skin.gdshader (the body
// under it). The build step (tools/build_characters.gd, region_of) bakes:
//   COLOR = (torso, arm, leg, hand) and UV2.x = foot: which part a vertex belongs to;
//   UV2.y = position along that part: torso 0 at the hips joint .. 1 at the neck,
//           arm 0 at the shoulder .. 1 at the wrist, leg 0 at the hip .. 1 at the ankle.
// Edges are drawn here per pixel, so stripes are clean bands whatever the mesh density.

uniform float pants_top = 0.17;                  // torso: pants below this
uniform vec2 hem_band = vec2(0.17, 0.25);        // torso: stripe at the jersey's bottom
uniform vec2 sleeve_band = vec2(0.6, 0.68);      // arm: stripe below the elbow
uniform float cuff_start = 0.93;                 // arm: cuff to the wrist
uniform float pants_leg = 0.4;                   // leg: pants down to here, socks below
uniform vec2 sock_band = vec2(0.62, 0.69);       // leg: stripe on the socks
// Team design (Teams.DESIGNS): how many stripes each band splits into (0 = none) and
// whether they alternate trim / accent. (The yoke is drawn in uniform.gdshader.)
uniform int hem_stripes = 1;
uniform int sleeve_stripes = 1;
uniform int sock_stripes = 1;
uniform bool alternate = false;                  // multi-stripe bands: every other stripe in accent

float region_band(float x, float lo, float hi) {
	float w = max(fwidth(x) * 0.75, 0.002);
	return smoothstep(lo - w, lo + w, x) * (1.0 - smoothstep(hi - w, hi + w, x));
}

float region_below(float x, float edge) {
	float w = max(fwidth(x) * 0.75, 0.002);
	return 1.0 - smoothstep(edge - w, edge + w, x);
}

// A band [lo, hi] split into n stripes with equal gaps (2n - 1 equal slices, odd ones
// solid). x = stripe coverage, y = the share of it in odd-numbered stripes (accent).
vec2 region_stripes(float f, vec2 band, int n) {
	if (n <= 0) {
		return vec2(0.0);
	}
	if (n == 1) {
		return vec2(region_band(f, band.x, band.y), 0.0);
	}
	float slice = (band.y - band.x) / float(2 * n - 1);
	float total = 0.0;
	float odd = 0.0;
	for (int i = 0; i < n; i++) {
		float lo = band.x + float(2 * i) * slice;
		float b = region_band(f, lo, lo + slice);
		total += b;
		odd += b * float(i % 2);
	}
	return vec2(total, odd);
}

// part = coverage of (jersey, pants, socks, gloves); skates = skate coverage;
// trim = the share of jersey + socks drawn in the trim color (accent included);
// accent = the part of that drawn in the accent color instead. Bare skin: all zero.
void uniform_regions_full(vec4 c, vec2 u, out vec4 part, out float skates, out float trim, out float accent) {
	float f = u.y;
	float torso_pants = region_below(f, pants_top);
	float leg_pants = region_below(f, pants_leg);
	part = vec4(
		c.r * (1.0 - torso_pants) + c.g,
		c.r * torso_pants + c.b * leg_pants,
		c.b * (1.0 - leg_pants),
		c.a);
	skates = u.x;
	// Stripes only where a triangle belongs to one part: across a part boundary (armpit,
	// shoulder) the position blends between the parts' scales and would sweep through
	// a stripe's range, drawing slivers.
	vec3 pure = smoothstep(vec3(0.9), vec3(1.0), c.rgb);
	vec2 hem = region_stripes(f, hem_band, hem_stripes) * pure.r * (1.0 - torso_pants);
	vec2 sleeve = region_stripes(f, sleeve_band, sleeve_stripes) * pure.g;
	vec2 sock = region_stripes(f, sock_band, sock_stripes) * pure.b * (1.0 - leg_pants);
	float cuff = pure.g * (1.0 - region_below(f, cuff_start));
	trim = clamp(hem.x + sleeve.x + sock.x + cuff, 0.0, 1.0);
	accent = alternate ? clamp(hem.y + sleeve.y + sock.y, 0.0, 1.0) : 0.0;
}

void uniform_regions(vec4 c, vec2 u, out vec4 part, out float skates, out float trim) {
	float accent;
	uniform_regions_full(c, u, part, skates, trim, accent);
}
