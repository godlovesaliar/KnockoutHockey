shader_type spatial;
// Bare body under the uniform. The skin texture's detail (shading, lips, stubble) is
// kept by dividing it by its own average color, then tinted to the player's skin tone.
// Skin under worn clothing is discarded, using the same layout as the outfit
// (uniform_regions.gdshaderinc).

#include "res://scenes/actors/uniform_regions.gdshaderinc"

uniform sampler2D skin_tex : source_color, filter_linear_mipmap;
uniform bool has_tex = false;
uniform vec3 tex_avg = vec3(0.6, 0.4, 0.3);      // linear average of skin_tex
uniform vec3 tone : source_color = vec3(0.87, 0.68, 0.55);
uniform vec4 wear = vec4(1.0);                   // jersey, pants, socks, gloves worn
uniform float wear_skates = 1.0;
instance uniform float gloves_worn = 1.0;      // 0 = bare hands (fights)

void fragment() {
	vec4 part;
	float sk;
	float tr;
	uniform_regions(COLOR, UV2, part, sk, tr);
	float cover = dot(part, wear * vec4(1.0, 1.0, 1.0, gloves_worn)) + sk * wear_skates;
	if (cover > 0.5) {
		discard;
	}
	vec3 detail = vec3(1.0);
	if (has_tex) {
		detail = clamp(texture(skin_tex, UV).rgb / max(tex_avg, vec3(0.01)), vec3(0.0), vec3(2.0));
	}
	ALBEDO = clamp(detail * tone, vec3(0.0), vec3(1.0));
	ROUGHNESS = 0.62;
	SPECULAR = 0.3;
}
