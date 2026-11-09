shader_type spatial;
// Seated fans (one MultiMesh instance each). The mesh is built by Arena._fan_mesh with
// its body part in UV.x: 0.1 legs, 0.35 torso, 0.6 arms, 0.85 skin (head), 0.95 hair.
// Instance color = shirt. INSTANCE_CUSTOM: x phase, y how easily they stand (0 = first
// up), z skin tone, w pants / hair shade. `excitement` (0 calm .. 1 a home goal) is set
// by the arena from crowd reactions: the keenest fans stand, bounce and throw their arms up.

uniform float excitement : hint_range(0.0, 1.0) = 0.0;

varying vec3 shirt;
varying vec3 skin;
varying vec3 pants;
varying vec3 hair;

vec3 lin(vec3 c) {
	return pow(c, vec3(2.2));
}

void vertex() {
	vec4 c = INSTANCE_CUSTOM;
	float ph = c.x * 6.2831;
	float part = UV.x;
	float stand = smoothstep(c.y, c.y + 0.12, excitement);
	float bounce = stand * max(0.0, sin(TIME * (7.0 + c.x * 3.0) + ph)) * 0.1 * excitement;
	float raise = stand * clamp(0.75 + 0.35 * sin(TIME * (4.0 + c.x * 2.0) + ph * 2.0), 0.0, 1.0);
	vec3 v = VERTEX;
	if (part > 0.5 && part < 0.7) {
		// Arms swing up about the shoulder (around local X), spreading into a V.
		float sx = sign(v.x);
		vec3 piv = vec3(sx * 0.23, 1.0, -0.19);
		vec3 d = v - piv;
		float a = -2.6 * raise;
		d = vec3(d.x, d.y * cos(a) - d.z * sin(a), d.y * sin(a) + d.z * cos(a));
		d.x += sx * max(d.y, 0.0) * 0.45;
		v = piv + d;
	}
	if (part > 0.2) {
		v.y += stand * 0.38 + bounce;
	}
	// A little idle sway so the stands never freeze.
	v.x += sin(TIME * 1.1 + ph) * 0.02 * v.y;
	v.z += sin(TIME * 0.7 + ph * 1.7) * 0.012 * v.y;
	VERTEX = v;
	shirt = lin(COLOR.rgb);
	skin = lin(mix(vec3(0.96, 0.8, 0.68), vec3(0.3, 0.19, 0.12), c.z));
	pants = lin(mix(vec3(0.07, 0.08, 0.11), vec3(0.42, 0.4, 0.36), c.w * c.w));
	hair = lin(mix(vec3(0.06, 0.04, 0.03), vec3(0.55, 0.4, 0.22), fract(c.w * 7.3)));
}

void fragment() {
	float part = UV.x;
	vec3 col = pants;
	if (part > 0.9) {
		col = hair;
	} else if (part > 0.75) {
		col = skin;
	} else if (part > 0.2) {
		col = shirt;
	}
	ALBEDO = col * 0.85;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
}
