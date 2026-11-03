class_name World
extends Node2D
## Procedurally generated map: roads, buildings, forests. Provides pathfinding and line of sight.

enum { GROUND, WALL, TREE, FLOOR, ROAD }

const W := 140
const H := 140
const T := 32

var tiles := PackedByteArray()
var astar := AStarGrid2D.new()
var rng := RandomNumberGenerator.new()
var buildings: Array[Rect2i] = []
var loot_cells: Array[Vector2i] = []
var tree_cells: Array[Vector2i] = []
var spawn_cell := Vector2i(W / 2, H / 2)
var _ground_tex: ImageTexture


func idx(c: Vector2i) -> int:
	return c.y * W + c.x


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H


func get_tile(c: Vector2i) -> int:
	if not in_bounds(c):
		return WALL
	return tiles[idx(c)]


func set_tile(c: Vector2i, v: int) -> void:
	if in_bounds(c):
		tiles[idx(c)] = v


func is_walkable(c: Vector2i) -> bool:
	var t := get_tile(c)
	return t == GROUND or t == FLOOR or t == ROAD


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / T), floori(p.y / T))


func center_of(c: Vector2i) -> Vector2:
	return Vector2(c.x * T + T * 0.5, c.y * T + T * 0.5)


func size_px() -> Vector2:
	return Vector2(W * T, H * T)


func generate(seed_value: int) -> void:
	rng.seed = seed_value
	tiles.resize(W * H)
	tiles.fill(GROUND)
	_make_roads()
	_make_buildings()
	_make_trees()
	_make_border()
	_find_spawn()
	_build_collision()
	_build_astar()
	_build_texture()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	queue_redraw()


# ---------------------------------------------------------------- generation

func _make_roads() -> void:
	var x := rng.randi_range(10, 25)
	while x < W - 8:
		_road_line(true, x)
		x += rng.randi_range(28, 42)
	var y := rng.randi_range(10, 25)
	while y < H - 8:
		_road_line(false, y)
		y += rng.randi_range(28, 42)


func _road_line(vertical: bool, at: int) -> void:
	for i in W:
		for k in 3:
			if vertical:
				set_tile(Vector2i(at + k, i), ROAD)
			else:
				set_tile(Vector2i(i, at + k), ROAD)


func _make_buildings() -> void:
	var attempts := 0
	while attempts < 800 and buildings.size() < 75:
		attempts += 1
		var bw := rng.randi_range(6, 14)
		var bh := rng.randi_range(5, 11)
		var r := Rect2i(rng.randi_range(3, W - bw - 3), rng.randi_range(3, H - bh - 3), bw, bh)
		if not _area_is(r.grow(2), GROUND):
			continue
		if not _near_type_rect(r, ROAD, 5):
			continue
		buildings.append(r)
		_place_building(r)


func _area_is(r: Rect2i, t: int) -> bool:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if get_tile(Vector2i(x, y)) != t:
				return false
	return true


func _near_type_rect(r: Rect2i, t: int, dist: int) -> bool:
	var g := r.grow(dist)
	for y in range(g.position.y, g.end.y):
		for x in range(g.position.x, g.end.x):
			if get_tile(Vector2i(x, y)) == t:
				return true
	return false


func _place_building(r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var edge := x == r.position.x or y == r.position.y or x == r.end.x - 1 or y == r.end.y - 1
			set_tile(Vector2i(x, y), WALL if edge else FLOOR)
	# Interior wall with a gap, for bigger buildings.
	if r.size.x >= 10 and rng.randf() < 0.6:
		var dx := r.position.x + r.size.x / 2
		for y in range(r.position.y + 1, r.end.y - 1):
			set_tile(Vector2i(dx, y), WALL)
		var gy := rng.randi_range(r.position.y + 1, r.end.y - 3)
		set_tile(Vector2i(dx, gy), FLOOR)
		set_tile(Vector2i(dx, gy + 1), FLOOR)
	for i in rng.randi_range(1, 2):
		_make_door(r)
	var n := rng.randi_range(1, 3) + (1 if r.size.x * r.size.y > 80 else 0)
	for i in n:
		var c := Vector2i(rng.randi_range(r.position.x + 1, r.end.x - 2), rng.randi_range(r.position.y + 1, r.end.y - 2))
		if get_tile(c) == FLOOR and not loot_cells.has(c):
			loot_cells.append(c)


func _make_door(r: Rect2i) -> void:
	var side := rng.randi_range(0, 3)
	if side < 2:
		var x := rng.randi_range(r.position.x + 1, r.end.x - 3)
		var y := r.position.y if side == 0 else r.end.y - 1
		set_tile(Vector2i(x, y), FLOOR)
		set_tile(Vector2i(x + 1, y), FLOOR)
	else:
		var y := rng.randi_range(r.position.y + 1, r.end.y - 3)
		var x := r.position.x if side == 2 else r.end.x - 1
		set_tile(Vector2i(x, y), FLOOR)
		set_tile(Vector2i(x, y + 1), FLOOR)


func _near_type(c: Vector2i, t: int, radius: int) -> bool:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if get_tile(c + Vector2i(dx, dy)) == t:
				return true
	return false


func _make_trees() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.05
	for y in H:
		for x in W:
			var c := Vector2i(x, y)
			if get_tile(c) != GROUND:
				continue
			var p := 0.35 if noise.get_noise_2d(x, y) > 0.15 else 0.02
			if rng.randf() >= p:
				continue
			if _near_type(c, ROAD, 1) or _near_type(c, WALL, 1) or _near_type(c, FLOOR, 1):
				continue
			set_tile(c, TREE)
			tree_cells.append(c)


func _make_border() -> void:
	for i in W:
		set_tile(Vector2i(i, 0), WALL)
		set_tile(Vector2i(i, H - 1), WALL)
		set_tile(Vector2i(0, i), WALL)
		set_tile(Vector2i(W - 1, i), WALL)


func _find_spawn() -> void:
	var mid := Vector2(W * 0.5, H * 0.5)
	var best_d := INF
	for y in H:
		for x in W:
			if tiles[y * W + x] == ROAD:
				var d := Vector2(x, y).distance_squared_to(mid)
				if d < best_d:
					best_d = d
					spawn_cell = Vector2i(x, y)


func _build_collision() -> void:
	var walls := StaticBody2D.new()
	walls.collision_layer = Game.LAYER_WALL
	walls.collision_mask = 0
	add_child(walls)
	for y in H:
		var x := 0
		while x < W:
			if tiles[y * W + x] != WALL:
				x += 1
				continue
			var start := x
			while x < W and tiles[y * W + x] == WALL:
				x += 1
			var rs := RectangleShape2D.new()
			rs.size = Vector2((x - start) * T, T)
			var cs := CollisionShape2D.new()
			cs.shape = rs
			cs.position = Vector2(start * T + (x - start) * T * 0.5, y * T + T * 0.5)
			walls.add_child(cs)
	var trees := StaticBody2D.new()
	trees.collision_layer = Game.LAYER_WALL
	trees.collision_mask = 0
	add_child(trees)
	var circle := CircleShape2D.new()
	circle.radius = 12.0
	for c in tree_cells:
		var cs := CollisionShape2D.new()
		cs.shape = circle
		cs.position = center_of(c)
		trees.add_child(cs)


func _build_astar() -> void:
	astar.region = Rect2i(0, 0, W, H)
	astar.cell_size = Vector2(T, T)
	astar.offset = Vector2(T * 0.5, T * 0.5)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for y in H:
		for x in W:
			var c := Vector2i(x, y)
			if not is_walkable(c):
				astar.set_point_solid(c, true)


func _build_texture() -> void:
	var img := Image.create_empty(W, H, false, Image.FORMAT_RGB8)
	for y in H:
		for x in W:
			var col: Color
			match tiles[y * W + x]:
				ROAD:
					col = Color(0.27, 0.27, 0.29)
				FLOOR:
					col = Color(0.46, 0.37, 0.27)
				WALL:
					col = Color(0.58, 0.55, 0.50)
				_:
					col = Color(0.29, 0.40, 0.21)
			var v := rng.randf_range(-0.025, 0.025)
			img.set_pixel(x, y, Color(col.r + v, col.g + v, col.b + v))
	_ground_tex = ImageTexture.create_from_image(img)


func _draw() -> void:
	draw_texture_rect(_ground_tex, Rect2(Vector2.ZERO, size_px()), false)
	for c in tree_cells:
		var p := center_of(c)
		draw_circle(p + Vector2(4, 5), 16.0, Color(0, 0, 0, 0.25))
		draw_circle(p, 16.0, Color(0.12, 0.28, 0.13))
		draw_circle(p + Vector2(-4, -4), 9.0, Color(0.17, 0.36, 0.17))


# ---------------------------------------------------------------- queries

func has_los(a: Vector2, b: Vector2) -> bool:
	var d := b - a
	var steps := int(d.length() / 8.0) + 1
	for i in range(1, steps):
		if get_tile(cell_of(a + d * (float(i) / steps))) == WALL:
			return false
	return true


func nearest_walkable(c: Vector2i) -> Vector2i:
	if is_walkable(c):
		return c
	for r in range(1, 4):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var n := c + Vector2i(dx, dy)
				if is_walkable(n):
					return n
	return c


func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var a := nearest_walkable(cell_of(from))
	var b := nearest_walkable(cell_of(to))
	if not in_bounds(a) or not in_bounds(b) or not is_walkable(a) or not is_walkable(b):
		return PackedVector2Array()
	return astar.get_point_path(a, b, true)


func random_walkable_near(p: Vector2, radius_tiles: int) -> Vector2:
	var c := cell_of(p)
	for i in 10:
		var n := c + Vector2i(rng.randi_range(-radius_tiles, radius_tiles), rng.randi_range(-radius_tiles, radius_tiles))
		if is_walkable(n):
			return center_of(n)
	return p
