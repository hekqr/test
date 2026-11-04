class_name World
extends Node2D
## The map: roads, hand-made buildings (see buildings.gd) placed facing the roads, street props and
## lootable cars along the roads, forests and nature in the wilderness.
## Also provides pathfinding and line of sight.

enum { GROUND, WALL, TREE, FLOOR, ROAD, WINDOW, FURN }
enum { F_NONE, F_WOOD, F_TILE, F_CONCRETE }

const W := 140
const H := 140
const T := 32

var tiles := PackedByteArray()
var floor_kind := PackedByteArray()
var astar := AStarGrid2D.new()
var rng := RandomNumberGenerator.new()
var buildings: Array[Rect2i] = []
var building_types: Array[String] = []
var building_doors: Array = [] # per building: exterior door cells
var building_floors: Array = [] # per building: walkable floor cells
var containers: Array = [] # {"pos": Vector2, "kind": String, "tex": String, "flip": bool, "reach": float}
var furniture: Array = [] # {"cell": Vector2i, "name": String} (non-searchable furniture)
var wild_spots: Array[Vector2i] = []
var stick_spots: Array[Vector2i] = [] # sticks lying in the woods (for campfires)
var tree_cells: Array[Vector2i] = []
var tree_tex: Array[String] = []
var props: Array = [] # street props / nature: {"pos": Vector2, "tex": String, "flip": bool, "tall": bool}
var car_rects: Array[Rect2] = []
var spawn_cell := Vector2i(W / 2, H / 2)
var road_v: Array[int] = [] # x of vertical roads (3 wide)
var road_h: Array[int] = [] # y of horizontal roads (3 wide)
var roofs: Array[TileMapLayer] = [] # one per building, same order as `buildings`

# Atlas coords in tiles_ground.png / tiles_building.png (16x16 tiles)
const GRASS_TILES := [Vector2i(0, 0), Vector2i(2, 0), Vector2i(5, 0), Vector2i(14, 0), Vector2i(16, 0),
	Vector2i(0, 2), Vector2i(2, 2), Vector2i(14, 2), Vector2i(16, 2)]
const GRASS_DECOR_TILES := [Vector2i(3, 1), Vector2i(3, 2), Vector2i(4, 2), Vector2i(4, 1), Vector2i(5, 1)]
const WOOD_TILES := [Vector2i(3, 11), Vector2i(4, 11), Vector2i(5, 11)]
const WALL_H_TILES := [Vector2i(7, 4), Vector2i(7, 4), Vector2i(6, 1), Vector2i(8, 4)]
const WALL_V_TILES := [Vector2i(1, 2), Vector2i(1, 3)]
const TREES := ["tree_1", "tree_2", "tree_3", "tree_4", "tree_5", "tree_6", "tree_7", "tree_8", "tree_9"]
const CAR_COLORS := ["blue", "gray", "green", "orange", "red", "yellow"]


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


func blocks_sight(c: Vector2i) -> bool:
	return get_tile(c) == WALL


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
	floor_kind.resize(W * H)
	floor_kind.fill(F_NONE)
	_make_roads()
	_make_buildings()
	_make_street()
	_make_trees()
	_make_nature()
	_make_border()
	_find_spawn()
	_build_collision()
	_build_astar()
	_build_tilemaps()
	_place_trees(entities)
	_place_props(entities)
	_place_furniture()
	_scatter_decor()
	_build_roofs()


# ---------------------------------------------------------------- roads

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


func _in_h_road(y: int) -> bool:
	for ry in road_h:
		if y >= ry and y < ry + 3:
			return true
	return false


func _in_v_road(x: int) -> bool:
	for rx in road_v:
		if x >= rx and x < rx + 3:
			return true
	return false


# ---------------------------------------------------------------- buildings

## Walks along both sides of every road and places buildings facing it.
func _make_buildings() -> void:
	for rx in road_v:
		_line_of_buildings(true, rx, -1)
		_line_of_buildings(true, rx, 1)
	for ry in road_h:
		_line_of_buildings(false, ry, -1)
		_line_of_buildings(false, ry, 1)


func _line_of_buildings(vertical: bool, at: int, side: int) -> void:
	var cursor := rng.randi_range(2, 8)
	while cursor < W - 4:
		if rng.randf() < 0.25: # empty lot
			cursor += rng.randi_range(4, 9)
			continue
		var kind := Buildings.pick(rng)
		var front := ""
		if vertical:
			front = "E" if side < 0 else "W"
		else:
			front = "S" if side < 0 else "N"
		var plan := Buildings.oriented(Buildings.TEMPLATES[kind]["rows"], front, rng.randf() < 0.5)
		var bw := String(plan[0]).length()
		var bh := plan.size()
		var setback := rng.randi_range(1, 2)
		var pos: Vector2i
		if vertical:
			var x0 := at - setback - bw if side < 0 else at + 3 + setback
			pos = Vector2i(x0, cursor)
		else:
			var y0 := at - setback - bh if side < 0 else at + 3 + setback
			pos = Vector2i(cursor, y0)
		var r := Rect2i(pos, Vector2i(bw, bh))
		if r.position.x >= 2 and r.position.y >= 2 and r.end.x <= W - 2 and r.end.y <= H - 2 and _area_is(r.grow(1), GROUND):
			_place_building(r, kind, plan)
			cursor += (bh if vertical else bw) + rng.randi_range(2, 4)
		else:
			cursor += 3


func _area_is(r: Rect2i, t: int) -> bool:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if get_tile(Vector2i(x, y)) != t:
				return false
	return true


func _place_building(r: Rect2i, kind: String, plan: Array) -> void:
	var doors: Array[Vector2i] = []
	var floors: Array[Vector2i] = []
	for y in r.size.y:
		var row: String = plan[y]
		for x in r.size.x:
			var ch := row[x]
			var c := r.position + Vector2i(x, y)
			floor_kind[idx(c)] = Buildings.FLOOR_OF.get(ch, F_WOOD)
			match ch:
				"#":
					set_tile(c, WALL)
				"W":
					set_tile(c, WINDOW)
				"w", "t", "c", "D":
					set_tile(c, FLOOR)
					floors.append(c)
					if ch == "D" and (x == 0 or y == 0 or x == r.size.x - 1 or y == r.size.y - 1):
						doors.append(c)
				_:
					set_tile(c, FURN)
					if Buildings.CONTAINER_CHARS.has(ch):
						var k: String = Buildings.CONTAINER_CHARS[ch]
						var tex := ""
						if k == "vending":
							tex = "prop_vending_red" if rng.randf() < 0.5 else "prop_vending_blue"
						elif k == "box":
							tex = "loot_box_1" if rng.randf() < 0.5 else "loot_box_2"
						elif k == "trash":
							tex = "loot_trash_1" if rng.randf() < 0.5 else "loot_trash_2"
						elif k == "crate":
							tex = "prop_pallet_1" if rng.randf() < 0.5 else "prop_pallet_2"
						containers.append({"pos": center_of(c), "kind": k, "tex": tex, "flip": false, "reach": 44.0})
					elif Buildings.FURNITURE_CHARS.has(ch):
						furniture.append({"cell": c, "name": Buildings.FURNITURE_CHARS[ch]})
	buildings.append(r)
	building_types.append(kind)
	building_doors.append(doors)
	building_floors.append(floors)


# ---------------------------------------------------------------- street props & cars

func _is_sidewalk(c: Vector2i) -> bool:
	if get_tile(c) != GROUND:
		return false
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if get_tile(c + d) == ROAD:
			return true
	return false


func _near_intersection(c: Vector2i, dist: int) -> bool:
	for rx in road_v:
		if c.x >= rx - dist and c.x < rx + 3 + dist and _in_h_road_near(c.y, dist):
			return true
	return false


func _in_h_road_near(y: int, dist: int) -> bool:
	for ry in road_h:
		if y >= ry - dist and y < ry + 3 + dist:
			return true
	return false


func _make_street() -> void:
	# Street lights along every road
	for rx in road_v:
		var y := rng.randi_range(2, 8)
		while y < H - 2:
			for side in [-1, 3]:
				var c := Vector2i(rx + side, y + (0 if side < 0 else 5))
				if _is_sidewalk(c):
					set_tile(c, FURN)
					props.append({"pos": center_of(c) + Vector2(0, 12), "tex": "prop_light_side", "flip": side < 0, "tall": true})
			y += 11
	for ry in road_h:
		var x := rng.randi_range(2, 8)
		while x < W - 2:
			for side in [-1, 3]:
				var c := Vector2i(x + (0 if side < 0 else 5), ry + side)
				if _is_sidewalk(c):
					set_tile(c, FURN)
					props.append({"pos": center_of(c) + Vector2(0, 12), "tex": "prop_light_down" if side < 0 else "prop_light_up", "flip": false, "tall": true})
			x += 11
	# Stop signs at intersection corners
	for rx in road_v:
		for ry in road_h:
			var c := Vector2i(rx - 1, ry - 1)
			if _is_sidewalk(c):
				set_tile(c, FURN)
				props.append({"pos": center_of(c) + Vector2(0, 12), "tex": "prop_stop_down", "flip": false, "tall": true})
			c = Vector2i(rx + 3, ry + 3)
			if _is_sidewalk(c):
				set_tile(c, FURN)
				props.append({"pos": center_of(c) + Vector2(0, 12), "tex": "prop_stop_up", "flip": false, "tall": true})
	# Sidewalk clutter: hydrants, benches, garbage bins (searchable), trash bags, barrels, tires
	for y in range(2, H - 2):
		for x in range(2, W - 2):
			var c := Vector2i(x, y)
			if _is_sidewalk(c) and not _near_intersection(c, 1):
				var r := rng.randf()
				var vert_road := _in_v_road(x - 1) or _in_v_road(x + 1)
				if r < 0.012:
					set_tile(c, FURN)
					props.append({"pos": center_of(c) + Vector2(0, 12), "tex": "prop_hydrant_%d" % rng.randi_range(1, 2), "flip": false, "tall": true})
				elif r < 0.022:
					set_tile(c, FURN)
					props.append({"pos": center_of(c) + Vector2(0, 12), "tex": "prop_bench_side" if vert_road else "prop_bench_down", "flip": rng.randf() < 0.5, "tall": true})
				elif r < 0.036:
					set_tile(c, FURN)
					containers.append({"pos": center_of(c), "kind": "bin", "tex": "prop_bin_%d" % rng.randi_range(1, 4), "flip": rng.randf() < 0.5, "reach": 48.0})
				elif r < 0.06:
					props.append({"pos": center_of(c) + Vector2(rng.randf_range(-6, 6), rng.randf_range(-4, 8)), "tex": "prop_bag_%d" % rng.randi_range(1, 2), "flip": rng.randf() < 0.5, "tall": false})
				elif r < 0.068:
					props.append({"pos": center_of(c), "tex": ["prop_tire", "prop_barrel_1", "prop_barrel_2", "prop_barrel_3", "prop_pallet_2", "prop_debris"][rng.randi() % 6], "flip": rng.randf() < 0.5, "tall": true})
			elif get_tile(c) == ROAD and not _near_intersection(c, 0):
				var r2 := rng.randf()
				if r2 < 0.004:
					props.append({"pos": center_of(c), "tex": "prop_manhole", "flip": false, "tall": false})
				elif r2 < 0.007:
					props.append({"pos": center_of(c) + Vector2(rng.randf_range(-8, 8), 0), "tex": "prop_cone", "flip": false, "tall": false})
				elif r2 < 0.009:
					props.append({"pos": center_of(c), "tex": "prop_plates", "flip": rng.randf() < 0.5, "tall": false})
	# Shopping carts outside shops
	for i in buildings.size():
		if building_types[i] == "shop":
			for d in building_doors[i]:
				for off in [Vector2i(2, 1), Vector2i(-2, 1), Vector2i(1, 2), Vector2i(-1, -2)]:
					var c: Vector2i = d + off
					if get_tile(c) == GROUND and rng.randf() < 0.5:
						props.append({"pos": center_of(c), "tex": "prop_cart", "flip": rng.randf() < 0.5, "tall": true})
						break
	_make_cars()


## Abandoned cars on the roads. Each can be searched once (one item at most).
func _make_cars() -> void:
	for rx in road_v:
		var y := rng.randi_range(3, 12)
		while y < H - 6:
			if not _in_h_road_near(y, 3) and not _in_h_road_near(y + 3, 3) and rng.randf() < 0.6:
				var lane := rng.randi_range(0, 1)
				var col: String = CAR_COLORS[rng.randi() % CAR_COLORS.size()]
				var tex: String = ["car_front_", "car_front_", "car_flipped_", "car_moto_"][rng.randi() % 4] + col
				var cx := rx * T + (24 if lane == 0 else 72)
				_add_car(tex, Vector2(cx, y * T + 40), rng.randf() < 0.5)
			y += rng.randi_range(9, 20)
	for ry in road_h:
		var x := rng.randi_range(3, 12)
		while x < W - 8:
			if not _in_v_road_near(x, 3) and not _in_v_road_near(x + 4, 3) and rng.randf() < 0.6:
				var lane := rng.randi_range(0, 1)
				var col: String = CAR_COLORS[rng.randi() % CAR_COLORS.size()]
				var pick := rng.randi() % 10
				var tex := "car_side_" + col
				if pick == 0:
					tex = "car_bus_%d" % rng.randi_range(1, 5)
				elif pick <= 2:
					tex = "car_van_%d" % rng.randi_range(1, 2)
				elif pick <= 4:
					tex = "car_scrap_" + col
				var cy := ry * T + (24 if lane == 0 else 72)
				_add_car(tex, Vector2(x * T + 64, cy), rng.randf() < 0.5)
			x += rng.randi_range(10, 22)


func _in_v_road_near(x: int, dist: int) -> bool:
	for rx in road_v:
		if x >= rx - dist and x < rx + 3 + dist:
			return true
	return false


func _add_car(tex: String, center: Vector2, flip: bool) -> void:
	var size := Game.tex(tex).get_size() * 2.0
	var rect := Rect2(center - size / 2.0, size).grow(-4)
	car_rects.append(rect)
	for y in range(cell_of(rect.position).y, cell_of(rect.end).y + 1):
		for x in range(cell_of(rect.position).x, cell_of(rect.end).x + 1):
			var c := Vector2i(x, y)
			if rect.has_point(center_of(c)) and get_tile(c) == ROAD:
				set_tile(c, FURN)
	# The LootSpot's sprite stands on its position, so put it at the car's bottom edge.
	containers.append({"pos": Vector2(center.x, center.y + size.y / 2.0 - 15.0), "kind": "car", "tex": tex, "flip": flip, "reach": maxf(size.x, size.y) * 0.5 + 20.0})


# ---------------------------------------------------------------- wilderness

func _near_type(c: Vector2i, t: int, radius: int) -> bool:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if get_tile(c + Vector2i(dx, dy)) == t:
				return true
	return false


func _is_wild(c: Vector2i) -> bool:
	return get_tile(c) == GROUND and not _near_type(c, ROAD, 3) and not _near_type(c, WALL, 3) and not _near_type(c, WINDOW, 3)


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
			if _near_type(c, ROAD, 1) or _near_type(c, WALL, 1) or _near_type(c, FLOOR, 1) or _near_type(c, WINDOW, 1) or _near_type(c, FURN, 1):
				continue
			set_tile(c, TREE)
			tree_cells.append(c)
			tree_tex.append("nat_drytree" if rng.randf() < 0.06 else TREES[rng.randi() % TREES.size()])


## Rocks, stumps, logs, sticks, flowers and mushrooms out in the wild, plus rare item finds.
func _make_nature() -> void:
	for y in range(2, H - 2):
		for x in range(2, W - 2):
			var c := Vector2i(x, y)
			if not _is_wild(c):
				continue
			var r := rng.randf()
			var pos := center_of(c) + Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8))
			if r < 0.012:
				props.append({"pos": pos, "tex": "nat_rock_%d" % rng.randi_range(1, 7), "flip": rng.randf() < 0.5, "tall": false})
			elif r < 0.016:
				props.append({"pos": pos, "tex": "nat_rock_grass", "flip": rng.randf() < 0.5, "tall": false})
			elif r < 0.022:
				props.append({"pos": pos, "tex": "nat_stump_%d" % rng.randi_range(1, 2), "flip": rng.randf() < 0.5, "tall": false})
			elif r < 0.026:
				props.append({"pos": pos, "tex": "nat_trunk_%d" % rng.randi_range(1, 2), "flip": rng.randf() < 0.5, "tall": false})
			elif r < 0.04:
				props.append({"pos": pos, "tex": "nat_stick_%d" % rng.randi_range(1, 2), "flip": rng.randf() < 0.5, "tall": false})
			elif r < 0.058:
				props.append({"pos": pos, "tex": "nat_flower_%d" % rng.randi_range(1, 6), "flip": rng.randf() < 0.5, "tall": false})
			elif r < 0.066:
				props.append({"pos": pos, "tex": "nat_mushroom_%d" % rng.randi_range(1, 3), "flip": rng.randf() < 0.5, "tall": false})
			elif r < 0.071:
				wild_spots.append(c)
			elif r < 0.085:
				stick_spots.append(c)


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


# ---------------------------------------------------------------- physics / pathing

func _build_collision() -> void:
	var walls := StaticBody2D.new()
	walls.collision_layer = Game.LAYER_WALL
	walls.collision_mask = 0
	add_child(walls)
	for y in H:
		var x := 0
		while x < W:
			var t := tiles[y * W + x]
			if t != WALL and t != WINDOW and t != FURN:
				x += 1
				continue
			var start := x
			while x < W and tiles[y * W + x] in [WALL, WINDOW, FURN]:
				x += 1
			var rs := RectangleShape2D.new()
			rs.size = Vector2((x - start) * T, T)
			var cs := CollisionShape2D.new()
			cs.shape = rs
			cs.position = Vector2(start * T + (x - start) * T * 0.5, y * T + T * 0.5)
			walls.add_child(cs)
	for r in car_rects:
		var rs := RectangleShape2D.new()
		rs.size = r.size
		var cs := CollisionShape2D.new()
		cs.shape = rs
		cs.position = r.get_center()
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


# ---------------------------------------------------------------- rendering

func _build_tilemaps() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	var ground_id := ts.add_source(_atlas(Game.tex("tiles_ground"), GRASS_TILES + GRASS_DECOR_TILES + WOOD_TILES))
	var wall_id := ts.add_source(_atlas(Game.tex("tiles_building"), WALL_H_TILES + WALL_V_TILES))
	var road_id := ts.add_source(_atlas(_make_asphalt(), [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]))
	var floor_id := ts.add_source(_atlas(_make_floors(), [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]))

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
			var t := tiles[y * W + x]
			var fk := floor_kind[y * W + x]
			if t == ROAD:
				ground.set_cell(c, road_id, _road_tile(c))
			elif fk == F_TILE:
				ground.set_cell(c, floor_id, Vector2i((x + y) % 2, 0))
			elif fk == F_CONCRETE:
				ground.set_cell(c, floor_id, Vector2i(2 + rng.randi() % 2, 0))
			elif fk == F_WOOD:
				ground.set_cell(c, ground_id, WOOD_TILES[rng.randi() % WOOD_TILES.size()])
			else:
				var g: Array = GRASS_DECOR_TILES if rng.randf() < 0.06 else GRASS_TILES
				ground.set_cell(c, ground_id, g[rng.randi() % g.size()])
			if t == WALL or t == WINDOW:
				var vertical := _is_wallish(c + Vector2i(0, -1)) and _is_wallish(c + Vector2i(0, 1)) \
					and not _is_wallish(c + Vector2i(-1, 0)) and not _is_wallish(c + Vector2i(1, 0))
				var arr: Array = WALL_V_TILES if vertical else WALL_H_TILES
				walls.set_cell(c, wall_id, arr[rng.randi() % arr.size()])
	# dark outline around walls + glass in windows
	var outline := Line2DOutline.new()
	outline.world = self
	outline.z_index = -8
	add_child(outline)


func _is_wallish(c: Vector2i) -> bool:
	var t := get_tile(c)
	return t == WALL or t == WINDOW


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
	for rx in road_v:
		if c.x >= rx and c.x < rx + 3:
			on_v = true
			if c.x == rx + 1 and not _in_h_road(c.y) and c.y % 3 != 0:
				return Vector2i(3, 0)
	for ry in road_h:
		if c.y >= ry and c.y < ry + 3:
			if c.y == ry + 1 and not on_v and c.x % 3 != 0:
				return Vector2i(2, 0)
	return Vector2i(rng.randi() % 2, 0)


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


## Indoor floors: 0,1 = tiles (kitchens, bathrooms, shops), 2,3 = concrete (garages, police).
func _make_floors() -> Texture2D:
	var img := Image.create_empty(64, 16, false, Image.FORMAT_RGBA8)
	var tile_a := Color("b8b0a4")
	var tile_b := Color("a49c92")
	var grout := Color("7a7068")
	for t in 2:
		for y in 16:
			for x in 16:
				var checker := ((x / 8) + (y / 8) + t) % 2 == 0
				var col := tile_a if checker else tile_b
				if x % 8 == 0 or y % 8 == 0:
					col = grout
				col = col.darkened(rng.randf_range(0.0, 0.04))
				img.set_pixel(t * 16 + x, y, col)
	var conc := Color("6e6a6c")
	for t in range(2, 4):
		for y in 16:
			for x in 16:
				img.set_pixel(t * 16 + x, y, conc.lightened(rng.randf_range(-0.05, 0.06)))
		img.set_pixel(t * 16 + rng.randi_range(2, 13), rng.randi_range(2, 13), conc.darkened(0.25))
	return ImageTexture.create_from_image(img)


func _place_trees(entities: Node2D) -> void:
	var holder := Node2D.new()
	holder.name = "Trees"
	holder.y_sort_enabled = true
	entities.add_child(holder)
	for i in tree_cells.size():
		var c := tree_cells[i]
		var s := Game.make_sprite(tree_tex[i])
		s.centered = false
		var sz := s.texture.get_size()
		s.offset = Vector2(-floorf(sz.x / 2.0), -sz.y + 2.0)
		s.position = center_of(c) + Vector2(0, 10)
		s.flip_h = rng.randf() < 0.5
		holder.add_child(s)


## Street props and nature. Tall ones are y-sorted with the player; flat ones lie on the ground.
func _place_props(entities: Node2D) -> void:
	var tall := Node2D.new()
	tall.name = "Props"
	tall.y_sort_enabled = true
	entities.add_child(tall)
	var flat := Node2D.new()
	flat.z_index = -6
	add_child(flat)
	for p in props:
		var s := Game.make_sprite(p["tex"])
		s.flip_h = p["flip"]
		s.position = p["pos"]
		if p["tall"]:
			s.offset = Vector2(0, -s.texture.get_height() / 2.0 + 1.0)
			tall.add_child(s)
		else:
			flat.add_child(s)


## Beds, tables, sofas, toilets, baths (furniture you can't search).
func _place_furniture() -> void:
	var layer := Node2D.new()
	layer.z_index = -6
	add_child(layer)
	for f in furniture:
		var s := Sprite2D.new()
		s.texture = Game.furniture(f["name"])
		s.scale = Vector2(2, 2)
		s.position = center_of(f["cell"])
		layer.add_child(s)


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


# ---------------------------------------------------------------- roofs

## Roofs cover every building and fade out while the player is inside it.
func _build_roofs() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	var coords := []
	for col in [0, 1, 2, 8, 9, 10]:
		for row in 5:
			coords.append(Vector2i(col, row))
	var src_id := ts.add_source(_atlas(Game.tex("tiles_roof"), coords))
	for bi in buildings.size():
		var r := buildings[bi]
		var roof := TileMapLayer.new()
		roof.tile_set = ts
		roof.scale = Vector2(2, 2)
		roof.z_index = 5
		var base := 8 if rng.randf() < 0.5 else 0
		var mid := r.position.y + r.size.y / 2
		var doors: Array = building_doors[bi]
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var c := Vector2i(x, y)
				if c in doors:
					continue # doorways stay open so entrances are visible
				var col := 0 if x == r.position.x else (2 if x == r.end.x - 1 else 1)
				var row := 0
				if y == r.end.y - 1:
					row = 4
				elif y == mid:
					row = 2
				elif y > r.position.y:
					row = 1 if (y - r.position.y) % 2 == 1 else 3
				roof.set_cell(c, src_id, Vector2i(base + col, row))
		add_child(roof)
		roofs.append(roof)


func building_at(p: Vector2) -> int:
	var c := cell_of(p)
	for i in buildings.size():
		if buildings[i].has_point(c):
			return i
	return -1


func update_roofs(player_pos: Vector2, delta: float) -> void:
	var inside := building_at(player_pos)
	for i in roofs.size():
		var target := 0.0 if i == inside else 1.0
		var r := roofs[i]
		r.modulate.a = move_toward(r.modulate.a, target, delta * 4.0)
		r.visible = r.modulate.a > 0.01


# ---------------------------------------------------------------- queries

## Walls block sight; windows, furniture and cars don't.
func has_los(a: Vector2, b: Vector2) -> bool:
	var d := b - a
	var steps := int(d.length() / 8.0) + 1
	for i in range(1, steps):
		if blocks_sight(cell_of(a + d * (float(i) / steps))):
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
