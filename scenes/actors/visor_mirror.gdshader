shader_type spatial;
render_mode cull_back;
// Mirrored visor (SkaterVisual.visor_material, the "mirror" and "gold" tints): a coated
// shield that shows one color seen straight on and turns to another at a glancing angle,
// and hides the eyes. There is nothing in the arena for it to really reflect, so the
// mirror is suggested: a bright band where the surface would catch the lights overhead,
// darker where it would look down at the ice and the boards.
// Only the shield's outer skin is drawn (cull_back): with both, the inner one came through
// the outer in strips wherever it happened to be drawn second.
// On the full shield only the band over the eyes is coated (`clear_below`, a height in the
// helmet's frame): mirrored to the chin it was a blank bubble in place of a face.

uniform vec3 face_color : source_color = vec3(0.2, 0.48, 0.95);
uniform vec3 edge_color : source_color = vec3(0.72, 0.3, 0.9);
uniform float clear_below = -1000.0;   // under this height the shield is plain clear plastic
uniform vec3 clear_color : source_color = vec3(0.55, 0.65, 0.75);

varying float height;

void vertex() {
	height = VERTEX.y;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float glance = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 1.5);
	vec3 col = mix(face_color, edge_color, glance);
	// Which way the surface would reflect the eye's line, in the world: up is bright.
	vec3 r = (INV_VIEW_MATRIX * vec4(reflect(-v, n), 0.0)).xyz;
	float sky = smoothstep(-0.25, 0.45, r.y);
	float coat = smoothstep(clear_below - 0.014, clear_below, height);
	ALBEDO = mix(clear_color, col * mix(0.4, 1.0, sky), coat);
	EMISSION = col * 0.16 * sky * coat;
	METALLIC = 0.8 * coat;
	ROUGHNESS = mix(0.1, 0.14, coat);
	SPECULAR = mix(0.5, 0.8, coat);
	// Written so it is drawn with the see-through things, after the brows (the material's
	// render priority), but solid where it is coated: at 0.9 the face showed through as if
	// it were half clear.
	ALPHA = mix(0.4, 1.0, coat);
}
