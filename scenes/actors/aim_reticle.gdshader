// The shot reticle on the goal mouth: a ring and a center dot, always facing the camera
// and drawn over everything (the goalie mustn't hide it).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.85, 0.15, 0.9);

void vertex() {
	// Billboard: keep the quad's size, face the camera.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float aa = max(fwidth(r), 0.01);
	float ring = smoothstep(0.66 - aa, 0.66 + aa, r) * (1.0 - smoothstep(0.92 - aa, 0.92 + aa, r));
	float dot = 1.0 - smoothstep(0.2 - aa, 0.2 + aa, r);
	// A dark outline so it reads against white ice and white netting.
	float edge = smoothstep(0.56 - aa, 0.56 + aa, r) * (1.0 - smoothstep(1.0 - aa, 1.0, r)) + (1.0 - smoothstep(0.3 - aa, 0.3 + aa, r));
	float a = max(ring + dot, clamp(edge, 0.0, 1.0) * 0.6);
	if (a < 0.01) discard;
	ALBEDO = mix(vec3(0.02), color.rgb, clamp(ring + dot, 0.0, 1.0));
	ALPHA = a * color.a;
}
