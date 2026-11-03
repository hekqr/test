class_name Line2DOutline
extends Node2D
## Draws a dark pixel outline where walls meet open ground, so buildings read clearly.

var world: World


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	var T := World.T
	var col := Color(0.12, 0.06, 0.08)
	for y in World.H:
		for x in World.W:
			var c := Vector2i(x, y)
			if world.get_tile(c) != World.WALL:
				continue
			var p := Vector2(x * T, y * T)
			if world.in_bounds(c + Vector2i(0, -1)) and world.get_tile(c + Vector2i(0, -1)) != World.WALL:
				draw_rect(Rect2(p, Vector2(T, 2)), col)
			if world.in_bounds(c + Vector2i(0, 1)) and world.get_tile(c + Vector2i(0, 1)) != World.WALL:
				draw_rect(Rect2(p + Vector2(0, T - 2), Vector2(T, 2)), col)
			if world.in_bounds(c + Vector2i(-1, 0)) and world.get_tile(c + Vector2i(-1, 0)) != World.WALL:
				draw_rect(Rect2(p, Vector2(2, T)), col)
			if world.in_bounds(c + Vector2i(1, 0)) and world.get_tile(c + Vector2i(1, 0)) != World.WALL:
				draw_rect(Rect2(p + Vector2(T - 2, 0), Vector2(2, T)), col)
