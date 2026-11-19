shader_type spatial;
// A goalie mask's paint job (tools/blender/goalie_mask_paint.py). The pattern texture's
// channels say where each color goes over the base: red accent 1, green accent 2, blue the
// detail color (outlines, teeth, stars), painted in that order. Patterns live in
// assets/characters/masks/mask_<mask>_<design>.png, one per mask shape, in the shell's own
// layout: a fisheye view of the mask from the front.

uniform sampler2D pattern : hint_default_black, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 base_color : source_color = vec3(0.93, 0.93, 0.9);
uniform vec3 accent1 : source_color = vec3(0.1, 0.25, 0.75);
uniform vec3 accent2 : source_color = vec3(0.95, 0.75, 0.1);
uniform vec3 detail : source_color = vec3(0.05, 0.05, 0.06);

void fragment() {
	vec3 p = texture(pattern, UV).rgb;
	vec3 c = base_color;
	c = mix(c, accent1, p.r);
	c = mix(c, accent2, p.g);
	c = mix(c, detail, p.b);
	ALBEDO = c;
	ROUGHNESS = 0.32;   // gloss paint over fiberglass
	SPECULAR = 0.55;
}
