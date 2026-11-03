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
var road_v: Array[int] = [] # x of vertical roads (3 wide)
var road_h: Array[int] = [] # y of horizontal roads (3 wide)

# Atlas coords in tiles_ground.png / tiles_building.png (16x16 tiles)
const GRASS_TILES := [Vector2i(0, 0), Vector2i(2, 0), Vector2i(5, 0), Vector2i(14, 0), Vector2i(16, 0),
	Vector2i(0, 2), Vector2i(2, 2), Vector2i(14, 2), Vector2i(16, 2)]
const GRASS_DECOR_TILES := [Vector2i(3, 1), Vector2i(3, 2), Vector2i(4, 2), Vector2i(4, 1), Vector2i(5, 1)]
const FLOOR_TILES := [Vector2i(3, 11), Vector2i(4, 11), Vector2i(5, 11)]
const WALL_H_TILES := [Vector2i(7, 4), Vector2i(7, 4), Vector2i(6, 1), Vector2i(8, 4)]
const WALL_V_TILES := [Vector2i(1, 2), Vector2i(1, 3)]
const TREES := ["tree_1", "tree_2", "tree_3", "tree_4", "tree_5", "tree_6", "tree_7", "tree_8", "tree_9"]


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


func generate(seed_value: int, entities: Node2D) -> void:
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
	_build_tilemaps()
	_place_trees(entities)
	_scatter_decor()


# ---------------------------------------------------------------- generation

func _make_roads() -> void:
	var x := rng.randi_range(10, 25)
	while x < W - 8:
		road_v.append(x)
		_road_line(true, x)
		x += rng.randi_range(28, 42)
	var y := rng.randi_range(10, 25)
	while y < H - 8:
		road_h.append(y)
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
	circle.radius = 10.0
	for c in tree_cells:
		var cs := CollisionShape2D.new()
		cs.shape = circle
		cs.position = center_of(c) + Vector2(0, 6)
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


func _build_tilemaps() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	var ground_src := _atlas(Game.tex("tiles_ground"), GRASS_TILES + GRASS_DECOR_TILES + FLOOR_TILES)
	var ground_id := ts.add_source(ground_src)
	var wall_src := _atlas(Game.tex("tiles_building"), WALL_H_TILES + WALL_V_TILES)
	var wall_id := ts.add_source(wall_src)
	var road_src := _atlas(_make_asphalt(), [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)])
	var road_id := ts.add_source(road_src)

	var ground := TileMapLayer.new()
	ground.tile_set = ts
	ground.scale = Vector2(2, 2)
	ground.z_index = -10
	add_child(ground)
	var walls := TileMapLayer.new()
	walls.tile_set = ts
	walls.scale = Vector2(2, 2)
	walls.z_index = -9
	add_child(walls)

	for y in H:
		for x in W:
			var c := Vector2i(x, y)
			match tiles[y * W + x]:
				ROAD:
					ground.set_cell(c, road_id, _road_tile(c))
				FLOOR:
					ground.set_cell(c, ground_id, FLOOR_TILES[rng.randi() % FLOOR_TILES.size()])
				WALL:
					ground.set_cell(c, ground_id, FLOOR_TILES[0])
					var vertical := get_tile(c + Vector2i(0, -1)) == WALL and get_tile(c + Vector2i(0, 1)) == WALL \
						and get_tile(c + Vector2i(-1, 0)) != WALL and get_tile(c + Vector2i(1, 0)) != WALL
					var arr: Array = WALL_V_TILES if vertical else WALL_H_TILES
					walls.set_cell(c, wall_id, arr[rng.randi() % arr.size()])
				_:
					var g: Array = GRASS_DECOR_TILES if rng.randf() < 0.06 else GRASS_TILES
					ground.set_cell(c, ground_id, g[rng.randi() % g.size()])
	# dark outline around walls
	var outline := Line2DOutline.new()
	outline.world = self
	outline.z_index = -8
	add_child(outline)


func _atlas(t: Texture2D, coords: Array) -> TileSetAtlasSource:
	var src := TileSetAtlasSource.new()
	src.texture = t
	src.texture_region_size = Vector2i(16, 16)
	for c in coords:
		if not src.has_tile(c):
			src.create_tile(c)
	return src


func _road_tile(c: Vector2i) -> Vector2i:
	var on_v := false
	var on_h := false
	for rx in road_v:
		if c.x >= rx and c.x < rx + 3:
			on_v = true
			if c.x == rx + 1 and not _in_h_road(c.y) and c.y % 3 != 0:
				return Vector2i(3, 0)
	for ry in road_h:
		if c.y >= ry and c.y < ry + 3:
			on_h = true
			if c.y == ry + 1 and not on_v and c.x % 3 != 0:
				return Vector2i(2, 0)
	return Vector2i(rng.randi() % 2, 0)


func _in_h_road(y: int) -> bool:
	for ry in road_h:
		if y >= ry and y < ry + 3:
			return true
	return false


## Seamless asphalt tiles generated from the ground tileset's asphalt colours.
## Tiles: 0,1 plain; 2 horizontal centre dash; 3 vertical centre dash.
func _make_asphalt() -> Texture2D:
	var src := Game.tex("tiles_ground").get_image()
	var palette: Array[Color] = []
	for y in range(8 * 16 + 2, 8 * 16 + 14):
		for x in range(5 * 16 + 2, 5 * 16 + 12):
			var col := src.get_pixel(x, y)
			if col.a > 0.9 and col.get_luminance() < 0.5:
				palette.append(col)
	if palette.is_empty():
		palette.append(Color(0.35, 0.33, 0.4))
	var img := Image.create_empty(64, 16, false, Image.FORMAT_RGBA8)
	for t in 4:
		for y in 16:
			var streak := palette[rng.randi() % palette.size()]
			for x in 16:
				var col := streak if rng.randf() < 0.35 else palette[rng.randi() % palette.size()]
				img.set_pixel(t * 16 + x, y, col)
	var paint := Color(0.78, 0.76, 0.70)
	for i in range(3, 13):
		img.set_pixel(2 * 16 + i, 7, paint)
		img.set_pixel(2 * 16 + i, 8, paint)
		img.set_pixel(3 * 16 + 7, i, paint)
		img.set_pixel(3 * 16 + 8, i, paint)
	return ImageTexture.create_from_image(img)


func _place_trees(entities: Node2D) -> void:
	var holder := Node2D.new()
	holder.name = "Trees"
	holder.y_sort_enabled = true
	entities.add_child(holder)
	for c in tree_cells:
		var s := Game.make_sprite(TREES[rng.randi() % TREES.size()])
		s.centered = false
		var sz := s.texture.get_size()
		s.offset = Vector2(-floorf(sz.x / 2.0), -sz.y + 2.0)
		s.position = center_of(c) + Vector2(0, 10)
		s.flip_h = rng.randf() < 0.5
		holder.add_child(s)


func _scatter_decor() -> void:
	var decor := Node2D.new()
	decor.z_index = -7
	add_child(decor)
	for i in 900:
		var c := Vector2i(rng.randi_range(1, W - 2), rng.randi_range(1, H - 2))
		var t := get_tile(c)
		var s: Sprite2D
		if t == GROUND and not _near_type(c, WALL, 1):
			var bush := rng.randf() < 0.25
			s = Game.make_sprite(("bush_%d" % rng.randi_range(1, 2)) if bush else ("grass_%d" % rng.randi_range(1, 5)))
		elif (t == ROAD or t == FLOOR) and rng.randf() < 0.25:
			s = Game.make_sprite("blood_%d" % rng.randi_range(1, 5))
			s.modulate.a = 0.7
		else:
			continue
		s.position = center_of(c) + Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8))
		s.flip_h = rng.randf() < 0.5
		decor.add_child(s)


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
