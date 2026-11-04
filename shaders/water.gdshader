shader_type canvas_item;
// Slow shimmer on lakes and rivers.

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float w = sin(TIME * 1.1 + world_pos.x * 0.04 + world_pos.y * 0.025) * sin(TIME * 0.6 - world_pos.y * 0.05);
	COLOR.rgb += vec3(0.025, 0.045, 0.07) * w;
}
