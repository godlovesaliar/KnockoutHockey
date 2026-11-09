shader_type spatial;
// Eyeballs (both eyes, one skinned mesh): the body's eye texture with the iris slid
// across the eyeball to where the player is looking (gaze) and tinted to their eye
// color. FaceRig measures, per body, where each eye's straight-ahead ray lands on the
// texture (front_*) and how far the UVs move per radian of gaze (axes_*).

uniform sampler2D eye_tex : source_color, filter_linear_mipmap, repeat_disable;
// Iris centers in the texture (both bodies share the layout): right eye, left eye.
uniform vec2 iris_r = vec2(0.290, 0.288);
uniform vec2 iris_l = vec2(0.706, 0.700);
uniform float iris_radius = 0.118;
uniform float pupil_radius = 0.038;
uniform vec2 front_r = vec2(0.29, 0.29);
uniform vec2 front_l = vec2(0.70, 0.70);
uniform vec4 axes_r = vec4(-0.24, 0.0, 0.0, 0.25);   // UV per radian: xy = to the left (+X), zw = up
uniform vec4 axes_l = vec4(0.24, 0.0, 0.0, 0.25);

instance uniform vec4 eye_color : source_color = vec4(0.33, 0.19, 0.09, 1.0);
instance uniform vec2 gaze = vec2(0.0);              // radians: x to the character's left, y up

void fragment() {
	bool right = distance(UV, front_r) < distance(UV, front_l);
	vec2 c = right ? iris_r : iris_l;
	vec2 f = right ? front_r : front_l;
	vec4 ax = right ? axes_r : axes_l;
	// Where this point sits on the eyeball, in radians from straight ahead (for shading).
	vec2 rel = UV - f;
	float up = dot(rel, normalize(ax.zw)) / max(length(ax.zw), 1e-4);
	float side = dot(rel, normalize(ax.xy)) / max(length(ax.xy), 1e-4);
	// The iris goes where the eye looks: sample the texture shifted so its iris lands there.
	vec2 target = f + ax.xy * gaze.x + ax.zw * gaze.y;
	vec2 uv = UV - (target - c);
	vec3 tex = texture(eye_tex, uv).rgb;
	float d = distance(uv, c);
	float iris = 1.0 - smoothstep(iris_radius * 0.9, iris_radius, d);
	// The texture's iris is red-brown: keep its fibers (luminance) in the player's color.
	float lum = dot(tex, vec3(0.3, 0.59, 0.11));
	vec3 col = eye_color.rgb * clamp(lum / 0.12, 0.25, 2.0);
	col *= mix(1.0, 0.45, smoothstep(iris_radius * 0.62, iris_radius * 0.98, d));   // limbal ring
	col = mix(col, vec3(0.008), 1.0 - smoothstep(pupil_radius * 0.85, pupil_radius * 1.15, d));
	vec3 sclera = tex * vec3(0.93, 0.9, 0.88);
	vec3 albedo = mix(sclera, col, iris);
	// Under the upper lid and toward the corners the eyeball sits in shadow.
	albedo *= mix(1.0, 0.5, smoothstep(0.05, 0.4, up));
	albedo *= mix(1.0, 0.7, smoothstep(0.45, 0.9, abs(side)));
	ALBEDO = albedo;
	ROUGHNESS = 0.06;
	SPECULAR = 0.6;
	// A small fixed catchlight so the eyes read as wet and alive in any lighting.
	float glint = pow(max(dot(normalize(NORMAL), normalize(vec3(-0.35, 0.45, 1.0))), 0.0), 220.0);
	EMISSION = vec3(glint) * 0.9 * (1.0 - smoothstep(0.15, 0.35, up));
}
