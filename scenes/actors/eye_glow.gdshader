shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
// The Chupacabras' eyes (SkaterVisual.HELMET_DRESS "chupa"): a glow on each of the
// player's own eyes, inside the helmet. The mesh is a unit quad set just in front of an
// eyeball and turned to the camera here; on it, a hot core fading out into a soft halo,
// added over the picture. It keeps its place in depth: the brow, the bridge of the nose
// and the helmet hide it as they would hide the eye, and it shifts behind the visor as
// the head turns. The material is drawn after the visor (its render priority), so the
// smoked shield dims the face behind it but not the light.
// (Two earlier versions drew the eyes on the visor, as a red shape and then as a soft
// glow just behind it: both read as paint on the visor, with no depth.)

uniform vec3 color : source_color = vec3(1.0, 0.06, 0.03);
uniform vec3 hot : source_color = vec3(1.0, 0.7, 0.45);
uniform float energy = 2.2;

void vertex() {
	// Face the camera, keeping the node's size (its x and y scale).
	vec2 size = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * size.x, INV_VIEW_MATRIX[1] * size.y, INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float r = length((UV - 0.5) * 2.0);                 // 0 at the middle, 1 at the quad's edge
	float core = 1.0 - smoothstep(0.1, 0.3, r);
	float halo = exp(-5.0 * r * r);
	float flicker = 0.94 + 0.06 * sin(TIME * 2.3 + NODE_POSITION_WORLD.x * 7.0);
	float light = (core + halo * 0.6) * (1.0 - smoothstep(0.75, 1.0, r)) * flicker;
	ALBEDO = mix(color, hot, core * core) * light * energy;
}
