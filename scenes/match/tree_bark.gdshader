shader_type spatial;
render_mode specular_disabled;
// The outdoor rink's trees (ArenaOutdoor): bark, darkened to winter wood, with snow lying
// on whatever faces up. tools/blender/trees.py does the same for the far trees' cut-outs.

uniform sampler2D bark : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint = vec3(0.42, 0.38, 0.36);       // linear, as trees.py's BARK_TINT
uniform vec3 snow : source_color = vec3(0.9, 0.92, 0.96);
uniform float snow_from = 0.45;                   // how far a face tips up before snow lies on it
uniform float snow_full = 0.85;

varying float up;

void vertex() {
	up = normalize(MODEL_NORMAL_MATRIX * NORMAL).y;
}

void fragment() {
	vec3 wood = texture(bark, UV).rgb * tint;
	ALBEDO = mix(wood, snow, smoothstep(snow_from, snow_full, up));
	ROUGHNESS = 1.0;
}
