shader_type spatial;
render_mode cull_disabled;
// Luchador hood (tools/blender/mask_gear.py). The pattern texture's channels say where
// each color goes over the base: red accent 1, green accent 2, blue accent 3 (painted in
// that order, so green lands on top). Patterns live in assets/characters/masks/ and share
// one UV layout (lucha_uv_guide.png): u around the head (0.5 the nose), v up from the hem.
// The hood is one surface drawn from both sides: its inside, seen through the eye and
// mouth holes, is darker. A fine knit and a satin sheen sell the stretch fabric.

uniform sampler2D pattern : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec3 base_color : source_color = vec3(0.86, 0.05, 0.48);
uniform vec3 accent1 : source_color = vec3(0.91, 0.71, 0.13);
uniform vec3 accent2 : source_color = vec3(0.05, 0.05, 0.05);
uniform vec3 accent3 : source_color = vec3(0.95, 0.95, 0.93);
uniform float knit_scale = 900.0;   // knit rows per UV unit around

void fragment() {
	vec3 p = texture(pattern, UV).rgb;
	vec3 c = base_color;
	c = mix(c, accent3, p.b);
	c = mix(c, accent1, p.r);
	c = mix(c, accent2, p.g);
	// Knit: faint rows, fading out with distance before they can shimmer.
	float fade = clamp(1.0 - length(VERTEX) / 4.0, 0.0, 1.0);
	float knit = sin(UV.x * knit_scale) * sin(UV.y * knit_scale * 0.6);
	c *= 1.0 - 0.06 * fade * (0.5 + 0.5 * knit);
	if (!FRONT_FACING) {
		c *= 0.35;
	}
	ALBEDO = c;
	ROUGHNESS = 0.42;
	SPECULAR = 0.55;
	// Satin: a soft sheen toward the edges.
	RIM = 0.25;
	RIM_TINT = 0.6;
}
