shader_type spatial;
// Eyelids: a unit sphere shell just over one eyeball (FaceRig scales it), cut down to
// the strip the lids cover. The face's own lids already cover the eyeball above `top`
// and below `bottom`, so with the eye open nothing draws; blinking, squinting and
// looking down bring the upper lid's edge down and the lower one up. Positions are in
// eye radii (y up, z forward, x across).

uniform float top = 0.72;
uniform float bottom = -0.66;
instance uniform vec4 tone : source_color = vec4(0.87, 0.68, 0.55, 1.0);
instance uniform float upper = 1.0;      // upper lid edge (at the middle of the eye)
instance uniform float lower = -1.0;     // lower lid edge

varying vec3 p;

void vertex() {
	p = VERTEX;
}

void fragment() {
	if (p.z < 0.05) {
		discard;
	}
	// Lid edges curve: the upper arches up in the middle, the lower dips.
	float ue = upper - 0.3 * p.x * p.x;
	float le = lower + 0.25 * p.x * p.x;
	bool up = p.y > ue && p.y < top;
	bool lo = p.y < le && p.y > bottom;
	if (!(up || lo)) {
		discard;
	}
	float edge = up ? p.y - ue : le - p.y;
	// A touch darker and rosier than the face: lids sit in the socket's shade.
	vec3 skin = tone.rgb * vec3(0.84, 0.74, 0.7) * (up ? 0.92 : 1.0);
	// Lashes along the upper edge, a faint line along the lower one.
	float lash = 1.0 - smoothstep(0.02, up ? 0.13 : 0.06, edge);
	ALBEDO = mix(skin, up ? vec3(0.03, 0.025, 0.02) : skin * 0.6, lash);
	ROUGHNESS = 0.7;
	SPECULAR = 0.15;
}
