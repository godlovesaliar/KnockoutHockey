shader_type spatial;
render_mode cull_disabled;
// Hair under a hat (SkaterVisual._build_hat): the player's whole hairstyle, as
// SkaterVisual.hair_material draws it, cut off above the hat's edge so none of it comes
// through the crown. (The cut under a helmet, pressed flat, is made for a helmet's cover
// over the temples and the nape, and looked patchy where a hat leaves them bare.)
// The edge is a plane in the hair model's own space: everything with dot(p, clip_n) over
// clip_d is left out. A hat open on top (the golf visor) has a second plane, its band's
// upper edge: hair over that one (dot(p, open_n) over open_d) shows again, out of the top.
// `above` turns the cut over: only what is over the edge is drawn. That is for the hair
// pressed flat under a helmet and the scalp cap, where they show in an open crown (the
// leather head guard's, between its straps) and must not show below the band.

uniform sampler2D strands : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_strands = false;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 clip_n = vec3(0.0, 1.0, 0.0);
uniform float clip_d = 1000.0;
uniform vec3 open_n = vec3(0.0, 1.0, 0.0);
uniform float open_d = 1000.0;
uniform bool above = false;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float e = dot(lp, clip_n);
	if (above ? e <= clip_d : (e > clip_d && dot(lp, open_n) < open_d)) {
		discard;
	}
	vec3 col = tint * COLOR.rgb;
	if (has_strands) {
		col *= texture(strands, UV).rgb;
	}
	ALBEDO = col;
	ROUGHNESS = 0.7;
}
