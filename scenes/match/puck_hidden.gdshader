shader_type spatial;
// Second pass on the puck: a see-through silhouette drawn ONLY where something
// (a skater, the boards, the net) is actually in front of the puck. Where the puck
// is in plain view this pass discards every pixel, so nothing is drawn over it.
// Compares this fragment's view depth to the opaque scene's depth buffer; the puck
// writes its own depth, so it never counts as covering itself.
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_back, blend_mix, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec4 fill_color : source_color = vec4(0.04, 0.04, 0.06, 0.55);
uniform vec4 rim_color : source_color = vec4(0.75, 0.82, 0.95, 0.8);
// Whatever covers the puck must be at least this much nearer the camera (m), so the ice
// at the puck's own edge and a stick blade resting on it don't trigger the silhouette.
uniform float min_gap = 0.2;

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_dist = -view.z / view.w;
	if (scene_dist > -VERTEX.z - min_gap) {
		discard;
	}
	float rim = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);
	vec4 c = mix(fill_color, rim_color, rim);
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
