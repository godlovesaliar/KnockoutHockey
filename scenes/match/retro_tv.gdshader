shader_type canvas_item;
// Retro Broadcast (a store extra): the game as an old tube TV shows it. A full-screen
// rect on its own CanvasLayer over the game and its TV graphics (MatchDirector): a
// gently bulged picture with dark rounded corners, scan lines, color bleeding at the
// edges of things, softer and warmer color, a vignette and a little snow.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float curve = 0.045;        // how far the picture bulges
uniform float lines = 240.0;        // scan lines down the screen
uniform float line_depth = 0.16;    // how dark the gaps between them are
uniform float bleed = 0.0016;       // red / blue pulled apart sideways (share of the width)
uniform float snow = 0.035;

void fragment() {
	vec2 c = SCREEN_UV * 2.0 - 1.0;
	vec2 d = c * (1.0 + curve * dot(c, c)) / (1.0 + curve);
	vec2 uv = d * 0.5 + 0.5;
	float inside = smoothstep(1.0, 0.985, abs(d.x)) * smoothstep(1.0, 0.985, abs(d.y));
	vec3 col = vec3(texture(screen_tex, uv + vec2(bleed, 0.0)).r, texture(screen_tex, uv).g, texture(screen_tex, uv - vec2(bleed, 0.0)).b);
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(luma), col, 0.84) * vec3(1.04, 1.0, 0.93) + 0.02;
	col *= 1.0 - line_depth * (0.5 + 0.5 * sin(uv.y * lines * 6.28318));
	col *= 1.0 - 0.3 * pow(dot(c, c) * 0.5, 1.6);
	float n = fract(sin(dot(floor(uv / SCREEN_PIXEL_SIZE) + floor(TIME * 30.0) * 17.0, vec2(12.9898, 78.233))) * 43758.5453);
	col += (n - 0.5) * snow;
	COLOR = vec4(col * inside, 1.0);
}
