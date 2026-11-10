class_name FloatText
extends Node2D
## A short text that floats up and fades (damage numbers, "Sneak attack!").

var text := ""
var color := Color.WHITE
var size := 14
var _t := 0.0
const LIFE := 0.8


static func spawn(parent: Node, pos: Vector2, txt: String, col := Color.WHITE, px := 14) -> void:
	if parent == null:
		return
	var f := FloatText.new()
	f.text = txt
	f.color = col
	f.size = px
	f.position = pos + Vector2(randf_range(-6, 6), -26)
	f.z_index = 20
	parent.add_child(f)


func _process(delta: float) -> void:
	_t += delta
	position.y -= 26.0 * delta
	if _t >= LIFE:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var a := clampf(1.0 - _t / LIFE, 0.0, 1.0)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2(-w / 2.0 + 1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.08, 0.04, 0.07, a))
	draw_string(font, Vector2(-w / 2.0, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(color, a))
