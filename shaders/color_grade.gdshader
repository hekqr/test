shader_type canvas_item;
// Full-screen colour grade: deeper, richer colours + soft vignette.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float saturation = 1.3;
uniform float contrast = 1.18;
uniform float brightness = 0.9;
uniform vec3 tint = vec3(0.96, 0.97, 1.06);
uniform float vignette = 1.1;

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	c = (c - 0.5) * contrast + 0.5;
	c *= brightness * tint;
	vec2 d = SCREEN_UV - 0.5;
	c *= 1.0 - dot(d, d) * vignette;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
