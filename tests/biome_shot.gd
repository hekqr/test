extends Node
## Dev tool: generates one region of every biome, prints how long it took and what's in it, and saves a
## screenshot of each (and a tile overview).
## xvfb-run -a godot --path . res://tests/biome_shot.tscn -- <out_dir>
var out := "user://"
var f := 0
var todo := []
var world: World
var ents: Node2D
var cam: Camera2D
var seed_v := 12345

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	for b in World.BIOMES:
		for y in range(-3, 4):
			for x in range(-3, 4):
				if World.biome_of(seed_v, Vector2i(x, y)) == b and not todo.any(func(t): return t[0] == b):
					todo.append([b, Vector2i(x, y)])
	print("regions: ", todo)
	cam = Camera2D.new()
	cam.zoom = Vector2(0.6, 0.6)
	add_child(cam)

func _process(_d: float) -> void:
	f += 1
	if f % 30 != 1:
		return
	if world:
		get_viewport().get_texture().get_image().save_png(out + "/biome_%s.png" % world.biome)
		world.free()
		ents.free()
		world = null
	if todo.is_empty():
		get_tree().quit()
		return
	var t: Array = todo.pop_front()
	world = World.new()
	world.region = t[1]
	world.edge_seed = seed_v
	add_child(world)
	ents = Node2D.new()
	ents.y_sort_enabled = true
	add_child(ents)
	var t0 := Time.get_ticks_msec()
	world.generate(hash([seed_v, t[1].x, t[1].y]), ents)
	var counts := {}
	for st in world.settlements:
		counts[st["type"]] = int(counts.get(st["type"], 0)) + 1
	var water := 0
	for i in world.tiles.size():
		if world.tiles[i] == World.WATER:
			water += 1
	print("%s %s: %d ms, %d trees, water %d, towns %s, coast %s" % [t[0], t[1], Time.get_ticks_msec() - t0, world.tree_cells.size(), water, counts, world.coast_side])
	var pos := world.center_of(world.spawn_cell) + Vector2(300, 200)
	cam.global_position = pos
	world.update_stream(pos, Vector2(1400, 900), -1)
	# overview
	var img := Image.create(World.W, World.H, false, Image.FORMAT_RGB8)
	var cols := {World.GROUND: world.tint_color(Color("4a6a3a")), World.TREE: Color("1e3a1e"), World.ROAD: Color("555555"), World.WATER: Color("3a6ab0"), World.WALL: Color("aa8866")}
	for y in World.H:
		for x in World.W:
			img.set_pixel(x, y, cols.get(world.tiles[y * World.W + x], Color("998877")))
	img.save_png(out + "/map_%s.png" % t[0])
