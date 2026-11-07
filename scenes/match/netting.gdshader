shader_type spatial;
render_mode cull_disabled;
// Procedural mesh netting. UVs are in meters.

uniform vec3 mesh_color : source_color = vec3(0.95, 0.95, 0.95);
uniform float cells_per_meter = 11.0;
uniform float thread = 0.14;

void fragment() {
	vec2 g = UV * cells_per_meter;
	vec2 d = 0.5 - abs(fract(g) - 0.5); // distance to nearest thread, in cells
	vec2 w = fwidth(g);
	vec2 m = 1.0 - smoothstep(vec2(thread * 0.5) - w, vec2(thread * 0.5) + w, d);
	float line_mask = max(m.x, m.y);
	// Fade toward average coverage when cells shrink below a pixel (avoids shimmering).
	float coverage = 1.0 - (1.0 - thread) * (1.0 - thread);
	line_mask = mix(line_mask, coverage, clamp(max(w.x, w.y) * 1.5 - 0.5, 0.0, 1.0));
	ALBEDO = mesh_color;
	ALPHA = clamp(line_mask * 0.9 + 0.05, 0.0, 1.0);
	ROUGHNESS = 0.9;
}
