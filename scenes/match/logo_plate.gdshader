shader_type spatial;
// A painted plate with a picture set in its middle: the resurfacer's side plates wear the
// home team's crest (Zamboni.set_logo). UV: v runs 0..1 up the plate and u is in the same
// units, centered on 0.5, so on a wide plate it runs past 0..1 and the picture keeps its shape.

uniform vec3 plate_color : source_color = vec3(0.92, 0.92, 0.9);
uniform sampler2D logo : source_color, repeat_disable, filter_linear_mipmap;
uniform float logo_aspect = 1.0;   // the picture's width over its height
uniform float logo_size = 0.84;    // its height, as a share of the plate's

void fragment() {
	vec2 t = vec2((UV.x - 0.5) / (logo_size * logo_aspect), (UV.y - 0.5) / logo_size) + 0.5;
	vec4 c = texture(logo, t);
	float inside = step(0.0, t.x) * step(t.x, 1.0) * step(0.0, t.y) * step(t.y, 1.0);
	ALBEDO = mix(plate_color, c.rgb, c.a * inside);
	ROUGHNESS = 0.4;
}
