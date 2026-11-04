class_name WaterBanks
extends Node2D
## Muddy banks around lakes and rivers, and railings where roads cross water (bridges).

var world: World


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	var T := World.T
	var mud := Color("4e5a3a")
	var shallow := Color("4a789c")
	var rail := Color("5a4030")
	var rail_hi := Color("8a6a4a")
	var dirs := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	for y in World.H:
		for x in World.W:
			var c := Vector2i(x, y)
			var t := world.get_tile(c)
			var p := Vector2(x * T, y * T)
			if t == World.WATER:
				for d in dirs:
					var n: Vector2i = c + d
					var nt := world.get_tile(n)
					if nt == World.WATER or nt == World.ROAD:
						continue
					# land side of this water tile: a strip of mud, then shallow water
					match d:
						Vector2i(0, -1):
							draw_rect(Rect2(p, Vector2(T, 4)), mud)
							draw_rect(Rect2(p + Vector2(0, 4), Vector2(T, 2)), shallow)
						Vector2i(0, 1):
							draw_rect(Rect2(p + Vector2(0, T - 4), Vector2(T, 4)), mud)
							draw_rect(Rect2(p + Vector2(0, T - 6), Vector2(T, 2)), shallow)
						Vector2i(-1, 0):
							draw_rect(Rect2(p, Vector2(4, T)), mud)
							draw_rect(Rect2(p + Vector2(4, 0), Vector2(2, T)), shallow)
						Vector2i(1, 0):
							draw_rect(Rect2(p + Vector2(T - 4, 0), Vector2(4, T)), mud)
							draw_rect(Rect2(p + Vector2(T - 6, 0), Vector2(2, T)), shallow)
			elif t == World.ROAD:
				# bridge railings on the edges that face water
				for d in dirs:
					if world.get_tile(c + d) != World.WATER:
						continue
					match d:
						Vector2i(0, -1):
							draw_rect(Rect2(p, Vector2(T, 4)), rail)
							draw_rect(Rect2(p, Vector2(T, 1)), rail_hi)
						Vector2i(0, 1):
							draw_rect(Rect2(p + Vector2(0, T - 4), Vector2(T, 4)), rail)
							draw_rect(Rect2(p + Vector2(0, T - 4), Vector2(T, 1)), rail_hi)
						Vector2i(-1, 0):
							draw_rect(Rect2(p, Vector2(4, T)), rail)
							draw_rect(Rect2(p, Vector2(1, T)), rail_hi)
						Vector2i(1, 0):
							draw_rect(Rect2(p + Vector2(T - 4, 0), Vector2(4, T)), rail)
							draw_rect(Rect2(p + Vector2(T - 4, 0), Vector2(1, T)), rail_hi)
