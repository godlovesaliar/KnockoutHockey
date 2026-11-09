shader_type spatial;
// Mouth cavity: a unit sphere FaceRig squashes behind the lips, dark red and darker
// toward the back, showing wherever the mouth's own lining doesn't.
render_mode cull_back;

varying vec3 p;

void vertex() {
	p = VERTEX;
}

void fragment() {
	ALBEDO = mix(vec3(0.03, 0.008, 0.008), vec3(0.14, 0.035, 0.035), smoothstep(-0.2, 0.9, p.z));
	ROUGHNESS = 0.5;
	SPECULAR = 0.2;
}
