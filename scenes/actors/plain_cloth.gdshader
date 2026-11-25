shader_type spatial;
render_mode cull_disabled; // the inside of sleeves and trouser legs shows at the hems
// Plain clothes on the people who aren't players (tools/blender/plain_clothes.py ->
// tools/build_fans.gd): a knit sweatshirt, jeans, boots. One shader; `kind` picks the cloth.
// The weave is procedural, pinned to the cloth by the rest-pose position the build step
// bakes into CUSTOM0, and fades out with distance before it can shimmer.
// COLOR.r is the part: 0 cloth or upper, 0.5 collar band or waistband, 1 sole. COLOR.g is
// how far it is to the end of the sleeve or the hem, 0..1 over 10 cm: the cuffs' and the
// hem's rib knit is everything within `rib_width` of them, its edge drawn per pixel.

uniform int kind = 0;   // 0 fleece knit, 1 denim, 2 leather
instance uniform vec3 cloth : source_color = vec3(0.3, 0.32, 0.38);
instance uniform vec3 second : source_color = vec3(0.25, 0.27, 0.33);   // rib knit; soles
uniform float rib_width = 0.45;        // of COLOR.g's 10 cm
// A crest printed on the chest (kind 0): the picture, its width / height, and where it
// goes in rest space: center x and y, half width, and the z its cloth lies ahead of.
uniform sampler2D crest : source_color, filter_linear_mipmap, repeat_disable;
uniform bool has_crest = false;
uniform float crest_aspect = 1.0;
instance uniform vec4 crest_box = vec4(0.0, 1.3, 0.1, 0.0);

varying vec3 rest_p;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	rest_p = CUSTOM0.xyz;
}

void fragment() {
	float part = COLOR.r;
	float rib = smoothstep(0.3, 0.45, part) * (1.0 - smoothstep(0.7, 0.8, part));
	float ew = max(fwidth(COLOR.g), 0.004);
	rib = max(rib, 1.0 - smoothstep(rib_width - ew, rib_width + ew, COLOR.g));
	float sole = smoothstep(0.7, 0.8, part);
	vec3 base = mix(cloth, second, max(rib, sole));
	float fine = 1.0 - smoothstep(2.0, 6.0, length(VERTEX));
	float rough = 0.9;
	float spec = 0.25;
	if (kind == 0) {
		// Fleece: a fine heathered speckle over soft mottling; the rib knit a shade deeper.
		base *= 1.0 + (vnoise(rest_p * 700.0) - 0.5) * 0.2 * fine + (vnoise(rest_p * 45.0) - 0.5) * 0.07;
		rough = 0.96;
		spec = 0.15;
		if (has_crest) {
			float hw = max(crest_box.z, 0.001);
			vec2 uv = vec2((rest_p.x - crest_box.x) / (2.0 * hw), (crest_box.y - rest_p.y) / (2.0 * hw / crest_aspect)) + 0.5;
			float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0) * step(crest_box.w, rest_p.z);
			vec4 c = texture(crest, uv);
			base = mix(base, c.rgb, c.a * inside);
		}
	} else if (kind == 1) {
		// Denim: diagonal twill up close, and paler where it wears (fronts of the thighs,
		// knees, seat), in broad soft patches.
		float twill = sin((rest_p.x + rest_p.y * 0.8 + rest_p.z * 0.6) * 2100.0);
		base *= 1.0 + twill * 0.07 * fine + (vnoise(rest_p * 500.0) - 0.5) * 0.12 * fine;
		float wear = vnoise(rest_p * vec3(7.0, 3.5, 7.0) + vec3(3.7));
		base = mix(base, base * 1.3 + 0.025, smoothstep(0.45, 0.85, wear) * 0.4);
		base *= mix(1.0, 0.9, rib);
		rough = 0.86;
	} else {
		// Leather uppers, a rubber sole.
		base *= 1.0 + (vnoise(rest_p * 260.0) - 0.5) * 0.14 * fine;
		rough = mix(0.5, 0.9, sole);
		spec = mix(0.45, 0.2, sole);
	}
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
		base *= 0.75;
	}
	ALBEDO = clamp(base, vec3(0.0), vec3(1.0));
	ROUGHNESS = rough;
	SPECULAR = spec;
}
