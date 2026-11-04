extends Node
## Dev tool: renders a generated world as a PNG (1 px per tile) and prints generation info.
## godot --headless --path . res://tests/map_preview.tscn -- <out.png> [seed]
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var w := World.new()
	add_child(w)
	var ent := Node2D.new()
	add_child(ent)
	var t0 := Time.get_ticks_msec()
	w.generate(int(args[1]) if args.size() > 1 else 12345, ent)
	print("generated in %d ms, %d buildings, %d settlements, %d containers, %d segments" % [Time.get_ticks_msec() - t0, w.buildings.size(), w.settlements.size(), w.containers.size(), w.segments.size()])
	for st in w.settlements:
		print("  ", st["type"], " ", st["name"], " ", st["rect"])
	var img := Image.create_empty(World.W, World.H, false, Image.FORMAT_RGB8)
	var cols := {World.GROUND: Color("5a6a3a"), World.TREE: Color("2e4024"), World.ROAD: Color("8a8478"), World.FLOOR: Color("b08860"), World.WALL: Color("3a2420"), World.WINDOW: Color("7fa8c4"), World.FURN: Color("6a5040")}
	for y in World.H:
		for x in World.W:
			img.set_pixel(x, y, cols[w.get_tile(Vector2i(x, y))])
	img.set_pixel(w.spawn_cell.x, w.spawn_cell.y, Color.RED)
	img.resize(World.W * 4, World.H * 4, Image.INTERPOLATE_NEAREST)
	img.save_png(args[0])
	get_tree().quit()
