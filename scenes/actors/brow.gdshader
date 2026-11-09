shader_type spatial;
// Eyebrows: ribbons laid on the brow ridge (FaceRig), UV.x 0 at the inner end to 1 at
// the outer, UV.y across. `raise` lifts them, `furrow` pulls the inner ends down and
// together (anger, effort). Positions are face space: +X the character's left, +Y up.
render_mode blend_mix, depth_draw_opaque, cull_disabled;

instance uniform vec4 brow_color : source_color = vec4(0.1, 0.07, 0.05, 1.0);
instance uniform float raise = 0.0;      // -1..1
instance uniform float furrow = 0.0;     // 0..1
instance uniform float thick = 1.0;      // 0.5..1: how much of the ribbon's width is hair

varying vec2 b_uv;

void vertex() {
	float inner = 1.0 - UV.x;
	VERTEX.y += raise * 0.0035 * (0.6 + 0.4 * inner) - furrow * 0.004 * inner * inner;
	VERTEX.x -= sign(VERTEX.x) * furrow * 0.002 * inner;
	b_uv = UV;
}

void fragment() {
	float t = b_uv.x;
	float across = abs(b_uv.y - 0.5) * 2.0;
	// Thin toward the tail; the inner end stays full.
	float w = thick * mix(1.0, 0.75, t);
	float a = 1.0 - smoothstep(w * 0.55, w, across);
	a *= smoothstep(0.0, 0.1, t) * (1.0 - smoothstep(0.8, 1.0, t));
	// Hairs: fine strokes slanting toward the tail.
	float strokes = 0.86 + 0.14 * sin(t * 160.0 + b_uv.y * 7.0) * sin(t * 41.0 - b_uv.y * 3.0);
	// Denser along the middle line, wispier at the edges.
	ALPHA = clamp(a * strokes * mix(1.1, 0.75, across), 0.0, 1.0);
	ALBEDO = brow_color.rgb;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
}
