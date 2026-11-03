class_name Line2DOutline
extends Node2D
## Draws a dark pixel outline where walls meet open ground, and glass panes in windows.

var world: World


func _ready() -> void:
	queue_redraw()


func _solid(c: Vector2i) -> bool:
	var t := world.get_tile(c)
	return t == World.WALL or t == World.WINDOW


func _draw() -> void:
	var T := World.T
	var col := Color(0.12, 0.06, 0.08)
	var glass := Color("7fa8c4")
	var glass_hi := Color("c4dcea")
	for y in World.H:
		for x in World.W:
			var c := Vector2i(x, y)
			if not _solid(c):
				continue
			var p := Vector2(x * T, y * T)
			if world.in_bounds(c + Vector2i(0, -1)) and not _solid(c + Vector2i(0, -1)):
				draw_rect(Rect2(p, Vector2(T, 2)), col)
			if world.in_bounds(c + Vector2i(0, 1)) and not _solid(c + Vector2i(0, 1)):
				draw_rect(Rect2(p + Vector2(0, T - 2), Vector2(T, 2)), col)
			if world.in_bounds(c + Vector2i(-1, 0)) and not _solid(c + Vector2i(-1, 0)):
				draw_rect(Rect2(p, Vector2(2, T)), col)
			if world.in_bounds(c + Vector2i(1, 0)) and not _solid(c + Vector2i(1, 0)):
				draw_rect(Rect2(p + Vector2(T - 2, 0), Vector2(2, T)), col)
			if world.get_tile(c) == World.WINDOW:
				# Glass pane along the wall's direction
				var horizontal := _solid(c + Vector2i(-1, 0)) or _solid(c + Vector2i(1, 0))
				var r := Rect2(p + Vector2(4, 11), Vector2(T - 8, 10)) if horizontal else Rect2(p + Vector2(11, 4), Vector2(10, T - 8))
				draw_rect(r.grow(2), col)
				draw_rect(r, glass)
				if horizontal:
					draw_rect(Rect2(r.position + Vector2(3, 2), Vector2(6, 2)), glass_hi)
					draw_rect(Rect2(r.position + Vector2(r.size.x / 2.0 - 1, 0), Vector2(2, r.size.y)), col)
				else:
					draw_rect(Rect2(r.position + Vector2(2, 3), Vector2(2, 6)), glass_hi)
					draw_rect(Rect2(r.position + Vector2(0, r.size.y / 2.0 - 1), Vector2(r.size.x, 2)), col)
