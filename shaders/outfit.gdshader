shader_type canvas_item;
// Recolours the player sprite to match worn clothing.
// Source colours (from the character sheet): shirt = #43735b, jacket/sleeves = #404351,
// jacket highlight = #728591, zipper = #9eafad, hair = #452c34 / #704f48.

uniform vec4 shirt_col : source_color = vec4(0.263, 0.451, 0.357, 1.0);
uniform vec4 coat_col : source_color = vec4(0.251, 0.263, 0.318, 1.0);
uniform vec4 coat_hi : source_color = vec4(0.447, 0.522, 0.569, 1.0);
uniform vec4 zip_col : source_color = vec4(0.62, 0.686, 0.678, 1.0);
uniform vec4 hair_dark : source_color = vec4(0.271, 0.173, 0.204, 1.0);
uniform vec4 hair_light : source_color = vec4(0.439, 0.31, 0.282, 1.0);

bool near(vec3 a, vec3 b) {
	return distance(a, b) < 0.03;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (near(c.rgb, vec3(0.263, 0.451, 0.357))) c.rgb = shirt_col.rgb;
	else if (near(c.rgb, vec3(0.251, 0.263, 0.318))) c.rgb = coat_col.rgb;
	else if (near(c.rgb, vec3(0.447, 0.522, 0.569))) c.rgb = coat_hi.rgb;
	else if (near(c.rgb, vec3(0.62, 0.686, 0.678))) c.rgb = zip_col.rgb;
	else if (near(c.rgb, vec3(0.271, 0.173, 0.204))) c.rgb = hair_dark.rgb;
	else if (near(c.rgb, vec3(0.439, 0.31, 0.282))) c.rgb = hair_light.rgb;
	COLOR = c * COLOR;
}
