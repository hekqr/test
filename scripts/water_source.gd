class_name WaterSource
extends Node2D
## A bathroom tap in a house. The water is off, but some pipes still hold a little:
## `water` = how many drinks / gourd fills are left (0 = dry).

var water := 0


func _ready() -> void:
	add_to_group("taps")
	queue_redraw()


func label() -> String:
	return "Use tap" if water > 0 else "Tap (dry)"


func _draw() -> void:
	# A small chrome tap on the bath
	var steel := Color("a8b0b8")
	var dark := Color("1a1016")
	draw_rect(Rect2(-3, -4, 6, 8), dark)
	draw_rect(Rect2(-2, -3, 4, 6), steel)
	draw_rect(Rect2(-1, 2, 9, 3), dark)
	draw_rect(Rect2(0, 3, 7, 1), steel)
	draw_rect(Rect2(-4, -6, 8, 2), dark)
	if water > 0:
		draw_rect(Rect2(6, 5, 2, 3), Color("7ab8e0"))
