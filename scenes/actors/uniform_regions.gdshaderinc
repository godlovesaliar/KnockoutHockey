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
// How the socks are striped (Teams.SOCK_PATTERNS): 0 `sock_stripes` stripes in `sock_band`;
// 1 barber pole: even rings all the way down (`sock_stripes` + 2 of them; none at 0);
// 2 two-tone: the lower sock in the trim color, `sock_stripes` thin stripes above it;
// 3 block: one broad band (edged in the accent color with `alternate`).
uniform int sock_pattern = 0;
const float SOCK_POLE_TOP = 0.43;                // leg: where the barber pole's rings start
const float SOCK_SPLIT = 0.67;                   // leg: where a two-tone sock changes color
const float SOCK_FEATHER = 0.022;                // a two-tone sock's thin stripes, and the gaps
const vec2 SOCK_BLOCK = vec2(0.55, 0.8);         // leg: the block
const float SOCK_BLOCK_EDGE = 0.03;

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

// The socks' stripes at `f` along the leg, by `sock_pattern`: x and y as region_stripes.
vec2 region_sock(float f) {
	if (sock_pattern == 1) {
		if (sock_stripes <= 0) {
			return vec2(0.0);
		}
		// Rings and gaps of one width, from under the pants to the ankle.
		float u = (f - SOCK_POLE_TOP) / (1.0 - SOCK_POLE_TOP) * float(sock_stripes + 2);
		float w = clamp(fwidth(u) * 0.75, 0.002, 0.25);
		float ring = 1.0 - smoothstep(0.25 - w, 0.25 + w, abs(fract(u + 0.25) - 0.5));
		ring *= step(0.0, u);
		return vec2(ring, ring * mod(floor(u + 0.25), 2.0));
	}
	if (sock_pattern == 2) {
		float lower = 1.0 - region_below(f, SOCK_SPLIT);
		float top = SOCK_SPLIT - SOCK_FEATHER * float(2 * sock_stripes);
		float thin = region_stripes(f, vec2(top, SOCK_SPLIT - SOCK_FEATHER), sock_stripes).x;
		return vec2(clamp(lower + thin, 0.0, 1.0), thin);
	}
	if (sock_pattern == 3) {
		float block = region_band(f, SOCK_BLOCK.x, SOCK_BLOCK.y);
		float edges = region_band(f, SOCK_BLOCK.x, SOCK_BLOCK.x + SOCK_BLOCK_EDGE)
				+ region_band(f, SOCK_BLOCK.y - SOCK_BLOCK_EDGE, SOCK_BLOCK.y);
		return vec2(block, min(edges, block));
	}
	return region_stripes(f, sock_band, sock_stripes);
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
	// UV2.x: 1 = foot (skates); negative = the modelled jersey (tools/build_characters.gd,
	// _jersey): -0.25 its cloth, -1 its collar and laces, drawn in the trim color.
	skates = max(u.x, 0.0);
	float collar = smoothstep(0.5, 0.75, -u.x);
	// Stripes only where a triangle belongs to one part: across a part boundary (armpit,
	// shoulder) the position blends between the parts' scales and would sweep through
	// a stripe's range, drawing slivers.
	vec3 pure = smoothstep(vec3(0.9), vec3(1.0), c.rgb);
	vec2 hem = region_stripes(f, hem_band, hem_stripes) * pure.r * (1.0 - torso_pants);
	vec2 sleeve = region_stripes(f, sleeve_band, sleeve_stripes) * pure.g;
	vec2 sock = region_sock(f) * pure.b * (1.0 - leg_pants);
	float cuff = pure.g * (1.0 - region_below(f, cuff_start));
	trim = clamp(hem.x + sleeve.x + sock.x + cuff + collar, 0.0, 1.0);
	accent = alternate ? clamp(hem.y + sleeve.y + sock.y, 0.0, 1.0) * (1.0 - collar) : 0.0;
}

void uniform_regions(vec4 c, vec2 u, out vec4 part, out float skates, out float trim) {
	float accent;
	uniform_regions_full(c, u, part, skates, trim, accent);
}
