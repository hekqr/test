class_name World
extends Node2D
## The map: named settlements (a city, towns, villages) with their own street layouts, connected by
## highways; hand-made buildings (see buildings.gd) facing the streets; street props and lootable cars;
## forests, lakes, a river, nature and animals in the wilderness between them.
## Also provides pathfinding and line of sight.

enum { GROUND, WALL, TREE, FLOOR, ROAD, WINDOW, FURN, WATER }
enum { F_NONE, F_WOOD, F_TILE, F_CONCRETE }

const W := 200
const H := 200
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
## Road segments, each 3 tiles wide: {"vertical": bool, "at": first lane x (vertical) or y, "from", "to", "kind": "street"/"highway", "town": index}
var segments: Array = []
var road_dir := PackedByteArray() # per cell: 1 = part of a horizontal road, 2 = vertical
var intersections: Array[Vector2i] = []
## Settlements: {"name", "type": "city"/"town"/"village", "rect": Rect2i, "center": Vector2i}
var settlements: Array = []
var building_town: Array[int] = [] # settlement index per building (-1 = roadside)
var building_style: Array[String] = [] # wall colour: dark / beige / gray / white
var building_id := PackedInt32Array() # per cell: building index, or -1
var facades: Array[Sprite2D] = [] # front wall of each building (3/4 view), fades with the roof
var _face_windows: Array = [] # [{cell, tex}] windows on interior wall faces
var taps: Array[Vector2] = [] # bathroom taps (at house baths) - some still have water

const TOWN_NAMES := ["Ashford", "Millbrook", "Pine Hollow", "Greywater", "Stonebridge", "Redfield", "Elm Crossing",
	"Harrow", "Oakvale", "Cold Spring", "Linton", "Marsh End", "Westbury", "Fairhill", "Dunmore", "Northfield",
	"Bramley", "Kettle Creek", "Larkspur", "Willow Bend"]
## Building mix per settlement type (weights)
const TOWN_MIX := {
	"city": {"house_small": 18, "house_large": 20, "shop": 18, "police": 9, "clinic": 9, "garage": 10},
	"town": {"house_small": 32, "house_large": 26, "shop": 12, "police": 4, "clinic": 6, "garage": 12},
	"village": {"house_small": 45, "house_large": 25, "shop": 6, "garage": 14},
}
## How likely a container in each building type has already been looted by someone else
const PRE_LOOTED := {"house_small": 0.45, "house_large": 0.45, "shop": 0.35, "police": 0.3, "clinic": 0.35, "garage": 0.35}
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
	road_dir.resize(W * H)
	road_dir.fill(0)
	building_id.resize(W * H)
	building_id.fill(-1)
	_make_settlements()
	_make_roads()
	_make_buildings()
	_make_street()
	_make_water()
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
	_build_facades(entities)
	_build_shadows()


# ---------------------------------------------------------------- settlements & roads

func _make_settlements() -> void:
	var names := TOWN_NAMES.duplicate()
	for i in names.size():
		var j := rng.randi_range(i, names.size() - 1)
		var tmp = names[i]
		names[i] = names[j]
		names[j] = tmp
	var plan := [["city", 76], ["town", 52], ["town", 48], ["village", 34], ["village", 30], ["village", 34], ["village", 30], ["village", 32]]
	for entry in plan:
		var kind: String = entry[0]
		var size: int = entry[1]
		for attempt in 600:
			var margin := size / 2 + 6
			var c := Vector2i(rng.randi_range(margin, W - margin), rng.randi_range(margin, H - margin))
			if kind == "city":
				c = Vector2i(rng.randi_range(W / 2 - 20, W / 2 + 20), rng.randi_range(H / 2 - 20, H / 2 + 20))
			var r := Rect2i(c - Vector2i(size, size) / 2, Vector2i(size, size))
			var ok := true
			for s2 in settlements:
				if (s2["rect"] as Rect2i).grow(10).intersects(r):
					ok = false
					break
			if ok:
				settlements.append({"name": names.pop_back(), "type": kind, "rect": r, "center": c})
				break


func _make_roads() -> void:
	for ti in settlements.size():
		var st: Dictionary = settlements[ti]
		var r: Rect2i = st["rect"]
		match st["type"]:
			"city":
				# Street grid
				var x := r.position.x + rng.randi_range(2, 6)
				while x < r.end.x - 4:
					_add_segment(true, x, r.position.y, r.end.y, "street", ti)
					x += rng.randi_range(25, 29)
				var y := r.position.y + rng.randi_range(2, 6)
				while y < r.end.y - 4:
					_add_segment(false, y, r.position.x, r.end.x, "street", ti)
					y += rng.randi_range(25, 29)
			"town":
				# Main street + a few cross streets
				var main_v := rng.randf() < 0.5
				var c: Vector2i = st["center"]
				_add_segment(main_v, (c.x if main_v else c.y) - 1, r.position.y if main_v else r.position.x, r.end.y if main_v else r.end.x, "street", ti)
				var n := rng.randi_range(2, 3)
				for k in n:
					var at := (r.position.y if main_v else r.position.x) + 6 + k * (r.size.x - 12) / maxi(n - 1, 1)
					var half := rng.randi_range(10, r.size.x / 2)
					var mid := c.x if main_v else c.y
					_add_segment(not main_v, at, mid - half, mid + half, "street", ti)
			"village":
				# One road through, sometimes a short side lane
				var main_v := rng.randf() < 0.5
				var c: Vector2i = st["center"]
				_add_segment(main_v, (c.x if main_v else c.y) - 1, r.position.y if main_v else r.position.x, r.end.y if main_v else r.end.x, "street", ti)
				if rng.randf() < 0.6:
					var at := (c.y if main_v else c.x) + rng.randi_range(-6, 6)
					var dir := 1 if rng.randf() < 0.5 else -1
					var mid := c.x if main_v else c.y
					_add_segment(not main_v, at, mini(mid, mid + dir * 11), maxi(mid, mid + dir * 11), "street", ti)
	# Highways: connect every settlement (minimum spanning tree + one extra link)
	var connected := [0]
	var edges := []
	while connected.size() < settlements.size():
		var best := [-1, -1, INF]
		for a in connected:
			for b in settlements.size():
				if b in connected:
					continue
				var d := Vector2(settlements[a]["center"]).distance_to(Vector2(settlements[b]["center"]))
				if d < best[2]:
					best = [a, b, d]
		connected.append(best[1])
		edges.append([best[0], best[1]])
	if settlements.size() > 3:
		edges.append([settlements.size() - 1, settlements.size() - 2])
	for e in edges:
		var a: Vector2i = settlements[e[0]]["center"]
		var b: Vector2i = settlements[e[1]]["center"]
		if rng.randf() < 0.5:
			_add_segment(false, a.y - 1, mini(a.x, b.x) - 1, maxi(a.x, b.x) + 2, "highway", -1)
			_add_segment(true, b.x - 1, mini(a.y, b.y) - 1, maxi(a.y, b.y) + 2, "highway", -1)
		else:
			_add_segment(true, a.x - 1, mini(a.y, b.y) - 1, maxi(a.y, b.y) + 2, "highway", -1)
			_add_segment(false, b.y - 1, mini(a.x, b.x) - 1, maxi(a.x, b.x) + 2, "highway", -1)
	# Intersections: cells on both a horizontal and a vertical road
	for y in H:
		for x in W:
			if road_dir[y * W + x] == 3:
				intersections.append(Vector2i(x, y))


## Paints a 3-wide road from `from` to `to` along x (vertical = false) or y.
func _add_segment(vertical: bool, at: int, from: int, to: int, kind: String, town: int) -> void:
	from = clampi(from, 1, (H if vertical else W) - 2)
	to = clampi(to, 1, (H if vertical else W) - 1)
	at = clampi(at, 1, (W if vertical else H) - 4)
	segments.append({"vertical": vertical, "at": at, "from": from, "to": to, "kind": kind, "town": town})
	for i in range(from, to):
		for k in 3:
			var c := Vector2i(at + k, i) if vertical else Vector2i(i, at + k)
			if not in_bounds(c):
				continue
			set_tile(c, ROAD)
			road_dir[idx(c)] |= 2 if vertical else 1


func settlement_at(c: Vector2i) -> int:
	for i in settlements.size():
		if (settlements[i]["rect"] as Rect2i).grow(3).has_point(c):
			return i
	return -1


# ---------------------------------------------------------------- buildings

## Buildings line both sides of every settlement street; a few stand alone along highways.
func _make_buildings() -> void:
	for seg in segments:
		if seg["kind"] == "street":
			var mix: Dictionary = TOWN_MIX[settlements[seg["town"]]["type"]]
			_line_of_buildings(seg, -1, mix, 0.2, seg["town"])
			_line_of_buildings(seg, 1, mix, 0.2, seg["town"])
		else:
			var lone := {"house_small": 5, "garage": 3, "house_large": 2}
			_line_of_buildings(seg, -1, lone, 0.96, -1)
			_line_of_buildings(seg, 1, lone, 0.96, -1)


func _line_of_buildings(seg: Dictionary, side: int, mix: Dictionary, empty_lot: float, town: int) -> void:
	var vertical: bool = seg["vertical"]
	var at: int = seg["at"]
	var cursor: int = seg["from"] + rng.randi_range(1, 4)
	while cursor < int(seg["to"]) - 4:
		if rng.randf() < empty_lot:
			cursor += rng.randi_range(4, 9)
			continue
		var kind := Buildings.pick(rng, mix)
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
		# Need open ground around it (and room behind the roof edge)
		if r.position.x >= 3 and r.position.y >= 4 and r.end.x <= W - 3 and r.end.y <= H - 3 and _area_is(r.grow(1), GROUND):
			_place_building(r, kind, plan, town)
			cursor += (bh if vertical else bw) + rng.randi_range(2, 4)
		else:
			cursor += 2


func _area_is(r: Rect2i, t: int) -> bool:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if get_tile(Vector2i(x, y)) != t:
				return false
	return true


func _place_building(r: Rect2i, kind: String, plan: Array, town := -1) -> void:
	var doors: Array[Vector2i] = []
	var floors: Array[Vector2i] = []
	var bi := buildings.size()
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			building_id[idx(Vector2i(x, y))] = bi
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
						containers.append({"pos": center_of(c), "kind": k, "tex": tex, "flip": false, "reach": 44.0,
							"empty_chance": PRE_LOOTED.get(kind, 0.4)})
					elif Buildings.FURNITURE_CHARS.has(ch):
						furniture.append({"cell": c, "name": Buildings.FURNITURE_CHARS[ch]})
						if ch == "A" and kind.begins_with("house"):
							taps.append(center_of(c) + Vector2(-8, -6))
	buildings.append(r)
	building_types.append(kind)
	building_town.append(town)
	var styles := {"house_small": ["beige", "white", "gray", "dark"], "house_large": ["beige", "white", "gray"],
		"shop": ["gray", "white"], "police": ["gray", "white"], "clinic": ["white"], "garage": ["dark", "gray"]}
	var options: Array = styles.get(kind, ["gray"])
	building_style.append(options[rng.randi() % options.size()])
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
	var r := dist + 1
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var n := c + Vector2i(dx, dy)
			if in_bounds(n) and road_dir[idx(n)] == 3:
				return true
	return false


func _is_vertical_road(c: Vector2i) -> bool:
	return in_bounds(c) and (road_dir[idx(c)] & 2) != 0


func _make_street() -> void:
	# Street lights along settlement streets
	for seg in segments:
		if seg["kind"] != "street":
			continue
		var i: int = seg["from"] + rng.randi_range(2, 8)
		while i < int(seg["to"]) - 2:
			for side in [-1, 3]:
				var c: Vector2i
				var tex := ""
				if seg["vertical"]:
					c = Vector2i(int(seg["at"]) + side, i + (0 if side < 0 else 5))
					tex = "prop_light_side"
				else:
					c = Vector2i(i + (0 if side < 0 else 5), int(seg["at"]) + side)
					tex = "prop_light_down" if side < 0 else "prop_light_up"
				if _is_sidewalk(c) and not _near_intersection(c, 0):
					set_tile(c, FURN)
					props.append({"pos": center_of(c) + Vector2(0, 12), "tex": tex, "flip": seg["vertical"] and side < 0, "tall": true})
			i += 11
	# Stop signs at intersections in towns
	var done := {}
	for c0 in intersections:
		var key := Vector2i(c0.x / 4, c0.y / 4)
		if done.has(key) or settlement_at(c0) < 0:
			continue
		done[key] = true
		for off in [Vector2i(-2, -2), Vector2i(2, 2)]:
			var c: Vector2i = c0 + off
			if _is_sidewalk(c):
				set_tile(c, FURN)
				props.append({"pos": center_of(c) + Vector2(0, 12), "tex": "prop_stop_down" if off.y < 0 else "prop_stop_up", "flip": false, "tall": true})
				break
	# Sidewalk clutter in settlements: hydrants, benches, garbage bins (searchable), trash bags, barrels
	for y in range(2, H - 2):
		for x in range(2, W - 2):
			var c := Vector2i(x, y)
			var town := settlement_at(c)
			if town < 0:
				continue
			if _is_sidewalk(c) and not _near_intersection(c, 1):
				var r := rng.randf()
				var vert_road := _is_vertical_road(c + Vector2i(-1, 0)) or _is_vertical_road(c + Vector2i(1, 0))
				if r < 0.012:
					set_tile(c, FURN)
					props.append({"pos": center_of(c) + Vector2(0, 12), "tex": "prop_hydrant_%d" % rng.randi_range(1, 2), "flip": false, "tall": true})
				elif r < 0.022:
					set_tile(c, FURN)
					props.append({"pos": center_of(c) + Vector2(0, 12), "tex": "prop_bench_side" if vert_road else "prop_bench_down", "flip": rng.randf() < 0.5, "tall": true})
				elif r < 0.034:
					set_tile(c, FURN)
					containers.append({"pos": center_of(c), "kind": "bin", "tex": "prop_bin_%d" % rng.randi_range(1, 4), "flip": rng.randf() < 0.5, "reach": 48.0})
				elif r < 0.058:
					props.append({"pos": center_of(c) + Vector2(rng.randf_range(-6, 6), rng.randf_range(-4, 8)), "tex": "prop_bag_%d" % rng.randi_range(1, 2), "flip": rng.randf() < 0.5, "tall": false})
				elif r < 0.066:
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


## Abandoned cars: plenty in town streets, a few along highways. Each can be searched once (one item at most).
func _make_cars() -> void:
	for seg in segments:
		var town: bool = seg["kind"] == "street"
		var gap_min := 9 if town else 22
		var gap_max := 20 if town else 45
		var i: int = seg["from"] + rng.randi_range(3, 12)
		while i < int(seg["to"]) - 6:
			var lane := rng.randi_range(0, 1)
			var col: String = CAR_COLORS[rng.randi() % CAR_COLORS.size()]
			if seg["vertical"]:
				var c := Vector2i(int(seg["at"]) + 1, i)
				if not _near_intersection(c, 4) and rng.randf() < 0.6:
					var tex: String = ["car_front_", "car_front_", "car_flipped_", "car_moto_"][rng.randi() % 4] + col
					_add_car(tex, Vector2(int(seg["at"]) * T + (24 if lane == 0 else 72), i * T + 40), rng.randf() < 0.5)
			else:
				var c := Vector2i(i, int(seg["at"]) + 1)
				if not _near_intersection(c, 4) and not _near_intersection(c + Vector2i(4, 0), 4) and rng.randf() < 0.6:
					var pick := rng.randi() % 10
					var tex := "car_side_" + col
					if pick == 0:
						tex = "car_bus_%d" % rng.randi_range(1, 5)
					elif pick <= 2:
						tex = "car_van_%d" % rng.randi_range(1, 2)
					elif pick <= 4:
						tex = "car_scrap_" + col
					_add_car(tex, Vector2(i * T + 64, int(seg["at"]) * T + (24 if lane == 0 else 72)), rng.randf() < 0.5)
			i += rng.randi_range(gap_min, gap_max)


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


var _wild := PackedByteArray() # 1 = open ground at least 3 tiles from roads / buildings, outside towns


func _is_wild(c: Vector2i) -> bool:
	if _wild.is_empty():
		_build_wild_mask()
	return in_bounds(c) and _wild[idx(c)] == 1 and get_tile(c) == GROUND


## Marks cells far from roads and buildings (two passes of a 7-wide box, much faster than checking each cell's area).
func _build_wild_mask() -> void:
	var built := PackedByteArray()
	built.resize(W * H)
	for i in W * H:
		var t := tiles[i]
		built[i] = 1 if (t == ROAD or t == WALL or t == WINDOW) else 0
	var horiz := PackedByteArray()
	horiz.resize(W * H)
	for y in H:
		for x in W:
			var v := 0
			for dx in range(-3, 4):
				var xx := x + dx
				if xx >= 0 and xx < W and built[y * W + xx] == 1:
					v = 1
					break
			horiz[y * W + x] = v
	_wild.resize(W * H)
	for y in H:
		for x in W:
			var v := 0
			for dy in range(-3, 4):
				var yy := y + dy
				if yy >= 0 and yy < H and horiz[yy * W + x] == 1:
					v = 1
					break
			_wild[y * W + x] = 1 if v == 0 and settlement_at(Vector2i(x, y)) < 0 else 0


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
			if settlement_at(c) >= 0:
				p *= 0.12 # gardens, not forests, inside towns
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


# ---------------------------------------------------------------- water

## Lakes out in the wilderness and (usually) a river across the map. Roads cross the river on bridges.
func _make_water() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.12
	if rng.randf() < 0.85:
		# Try a few river courses and keep the one that stays clear of towns and buildings.
		var best: Array = []
		var best_bad := 1 << 30
		for attempt in 14:
			var cells := _river_cells(noise)
			var bad := 0
			for c in cells:
				if get_tile(c) == ROAD:
					bad += 1
				elif not _water_ok(c, 4):
					bad += 3
			if bad < best_bad:
				best_bad = bad
				best = cells
		for c in best:
			if _water_ok(c, 1):
				set_tile(c, WATER)
	var lakes := rng.randi_range(3, 5)
	for attempt in 300:
		if lakes <= 0:
			break
		var c := Vector2i(rng.randi_range(12, W - 13), rng.randi_range(12, H - 13))
		if not _water_ok(c, 8) or _near_type(c, ROAD, 6):
			continue
		var rx := rng.randf_range(3.5, 7.5)
		var ry := rng.randf_range(3.0, 6.0)
		for dy in range(-8, 9):
			for dx in range(-9, 10):
				var n := c + Vector2i(dx, dy)
				var v := pow(dx / rx, 2.0) + pow(dy / ry, 2.0) + noise.get_noise_2d(n.x * 2.0, n.y * 2.0) * 0.5
				if v < 1.0 and _water_ok(n, 2) and not _near_type(n, ROAD, 2):
					set_tile(n, WATER)
		lakes -= 1


## A meandering river from one edge of the map to the other, 2-3 tiles wide.
func _river_cells(noise: FastNoiseLite) -> Array:
	var vertical := rng.randf() < 0.5
	var across := W if vertical else H
	var along := H if vertical else W
	var pos := rng.randf_range(30.0, across - 30.0)
	var drift := 0.0
	var cells := []
	for t in range(1, along - 1):
		drift = clampf(drift + rng.randf_range(-0.3, 0.3), -0.9, 0.9)
		pos = clampf(pos + drift, 6.0, across - 8.0)
		var width := 2 + (1 if noise.get_noise_1d(t * 1.5) > 0.1 else 0)
		for k in width:
			cells.append(Vector2i(int(pos) + k, t) if vertical else Vector2i(t, int(pos) + k))
	return cells


## Open ground away from towns (by `margin` tiles) and buildings.
func _water_ok(c: Vector2i, margin: int) -> bool:
	if c.x < 2 or c.y < 2 or c.x >= W - 2 or c.y >= H - 2 or get_tile(c) != GROUND:
		return false
	for st in settlements:
		if (st["rect"] as Rect2i).grow(margin).has_point(c):
			return false
	return not (_near_type(c, WALL, 2) or _near_type(c, WINDOW, 2) or _near_type(c, FLOOR, 2) or _near_type(c, FURN, 1))


## True when a position is close enough to a lake or river to drink / fill a gourd.
func water_near(p: Vector2, reach := 26.0) -> bool:
	var c := cell_of(p)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n := c + Vector2i(dx, dy)
			if get_tile(n) == WATER:
				var r := Rect2(Vector2(n * T), Vector2(T, T))
				var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
				if q.distance_to(p) <= reach:
					return true
	return false


func _make_border() -> void:
	for i in W:
		set_tile(Vector2i(i, 0), WALL)
		set_tile(Vector2i(i, H - 1), WALL)
		set_tile(Vector2i(0, i), WALL)
		set_tile(Vector2i(W - 1, i), WALL)


## You start on the main street of a village.
func _find_spawn() -> void:
	var options := []
	for seg in segments:
		if seg["kind"] == "street" and settlements[seg["town"]]["type"] == "village":
			options.append(seg)
	if options.is_empty():
		options = segments
	var seg: Dictionary = options[rng.randi() % options.size()]
	for attempt in 50:
		var i := rng.randi_range(int(seg["from"]) + 2, int(seg["to"]) - 3)
		var c := Vector2i(int(seg["at"]) + 1, i) if seg["vertical"] else Vector2i(i, int(seg["at"]) + 1)
		if is_walkable(c):
			spawn_cell = c
			return
	spawn_cell = Vector2i(int(seg["at"]) + 1, int(seg["from"]) + 2) if seg["vertical"] else Vector2i(int(seg["from"]) + 2, int(seg["at"]) + 1)


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
	# Water blocks walking, not bullets or sight (its own layer).
	var water := StaticBody2D.new()
	water.collision_layer = Game.LAYER_WATER
	water.collision_mask = 0
	add_child(water)
	for y in H:
		var x := 0
		while x < W:
			if tiles[y * W + x] != WATER:
				x += 1
				continue
			var start := x
			while x < W and tiles[y * W + x] == WATER:
				x += 1
			var rs := RectangleShape2D.new()
			rs.size = Vector2((x - start) * T, T)
			var cs := CollisionShape2D.new()
			cs.shape = rs
			cs.position = Vector2(start * T + (x - start) * T * 0.5, y * T + T * 0.5)
			water.add_child(cs)
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
	var face_ids := {}
	for st in ["dark", "beige", "gray", "white"]:
		face_ids[st] = ts.add_source(_atlas(Game.tex("bld_" + st), FACE_TILES))
	var top_id := ts.add_source(_atlas(_make_wall_tops(), [Vector2i(0, 0), Vector2i(1, 0)]))
	var road_id := ts.add_source(_atlas(_make_asphalt(), [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]))
	var floor_id := ts.add_source(_atlas(_make_floors(), [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]))

	var ground := TileMapLayer.new()
	ground.tile_set = ts
	ground.scale = Vector2(2, 2)
	ground.z_index = -10
	add_child(ground)
	var water_id := ts.add_source(_atlas(_make_water_tiles(), [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]))
	var water := TileMapLayer.new()
	water.tile_set = ts
	water.scale = Vector2(2, 2)
	water.z_index = -10
	var wmat := ShaderMaterial.new()
	wmat.shader = load("res://shaders/water.gdshader")
	water.material = wmat
	add_child(water)
	var banks := WaterBanks.new()
	banks.world = self
	banks.z_index = -10
	add_child(banks)
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
			if t == WATER:
				water.set_cell(c, water_id, Vector2i(rng.randi() % 4, 0))
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
				# 3/4 view: a wall with room floor in front of it shows its face; other walls are thin dark tops.
				if is_face(c):
					var st: String = building_style[building_id[idx(c)]]
					walls.set_cell(c, face_ids[st], FACE_TILES[0] if rng.randf() < 0.75 else FACE_TILES[rng.randi() % FACE_TILES.size()])
					if t == WINDOW:
						_face_windows.append({"cell": c, "tex": _window_tex(building_style[building_id[idx(c)]])})
				else:
					walls.set_cell(c, top_id, Vector2i(rng.randi() % 2, 0))
	# dark outline around walls + glass in top-view windows
	var outline := Line2DOutline.new()
	outline.world = self
	outline.z_index = -8
	add_child(outline)
	# windows on interior wall faces
	var wins := Node2D.new()
	wins.z_index = -8
	add_child(wins)
	for fw in _face_windows:
		var spr := Sprite2D.new()
		spr.texture = Game.tex(fw["tex"])
		spr.scale = Vector2(2, 2)
		spr.position = center_of(fw["cell"]) + Vector2(0, 1)
		wins.add_child(spr)


## Face tiles from the building tilesets (plain wall, cracked wall, worn wall)
const FACE_TILES := [Vector2i(7, 4), Vector2i(8, 4), Vector2i(6, 1)]


## True for a wall / window that has room floor right in front of it (south), so you see its face.
func is_face(c: Vector2i) -> bool:
	var t := get_tile(c)
	if t != WALL and t != WINDOW:
		return false
	var b := building_id[idx(c)] if in_bounds(c) else -1
	var s := c + Vector2i(0, 1)
	if b < 0 or not in_bounds(s) or building_id[idx(s)] != b:
		return false
	var ts := get_tile(s)
	return ts == FLOOR or ts == FURN


func _window_tex(style: String) -> String:
	var base: String = {"dark": "win_gray", "gray": "win_gray", "beige": "win_beige", "white": "win_wood"}[style]
	var r := rng.randf()
	return base + ("_broken" if r < 0.2 else ("_boarded" if r < 0.3 else ""))


## Thin dark wall tops (what you see of a wall from above).
func _make_wall_tops() -> Texture2D:
	var img := Image.create_empty(32, 16, false, Image.FORMAT_RGBA8)
	for t in 2:
		for y in 16:
			for x in 16:
				var c := Color("3a2c30").lightened(rng.randf_range(-0.04, 0.05))
				img.set_pixel(t * 16 + x, y, c)
	return ImageTexture.create_from_image(img)


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
	var dir := road_dir[idx(c)]
	if dir == 2:
		# vertical road: dash on the middle lane
		if road_dir[idx(c + Vector2i(-1, 0))] & 2 and road_dir[idx(c + Vector2i(1, 0))] & 2 and c.y % 3 != 0:
			return Vector2i(3, 0)
	elif dir == 1:
		if road_dir[idx(c + Vector2i(0, -1))] & 1 and road_dir[idx(c + Vector2i(0, 1))] & 1 and c.x % 3 != 0:
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


## Deep water with ripples (4 variants).
func _make_water_tiles() -> Texture2D:
	var img := Image.create_empty(64, 16, false, Image.FORMAT_RGBA8)
	var base := Color("2e4f73")
	for t in 4:
		for y in 16:
			for x in 16:
				img.set_pixel(t * 16 + x, y, base.lightened(rng.randf_range(-0.03, 0.03)))
		for k in 3:
			var rx := rng.randi_range(0, 11)
			var ry := rng.randi_range(1, 14)
			for i in rng.randi_range(2, 4):
				img.set_pixel(t * 16 + rx + i, ry, Color("5a86ad"))
			if rng.randf() < 0.5:
				img.set_pixel(t * 16 + rx + 1, ry - 1, Color("8ab4d4"))
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

## Roofs sit one tile higher than the building (3/4 view), above the 2-tile front wall.
## Both fade out while the player is inside the building.
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
		var top := r.position.y - 1
		var bottom := r.end.y - 3 # last roof row; the front wall covers the 2 rows below it
		var mid := (top + bottom) / 2
		var cut_cells := {}
		for d in building_doors[bi]:
			var dc: Vector2i = d
			if dc.y < r.end.y - 1: # doors on the back / sides: leave a gap in the roof
				cut_cells[dc + Vector2i(0, -1)] = true
				cut_cells[dc] = true
		for y in range(top, bottom + 1):
			for x in range(r.position.x, r.end.x):
				var c := Vector2i(x, y)
				if cut_cells.has(c):
					continue
				var col := 0 if x == r.position.x else (2 if x == r.end.x - 1 else 1)
				var row := 0
				if y == bottom:
					row = 4
				elif y == mid:
					row = 2
				elif y > top:
					row = 1 if (y - top) % 2 == 1 else 3
				roof.set_cell(c, src_id, Vector2i(base + col, row))
		add_child(roof)
		roofs.append(roof)


## The front (south) wall of every building, 2 tiles tall, built from the pack's wall tiles with windows and doors.
## Sorted with the player, so you walk in front of it and zombies inside are hidden behind it.
func _build_facades(entities: Node2D) -> void:
	var holder := Node2D.new()
	holder.name = "Facades"
	holder.y_sort_enabled = true
	entities.add_child(holder)
	for bi in buildings.size():
		var r := buildings[bi]
		var style := building_style[bi]
		var src := Game.tex("bld_" + style).get_image()
		src.convert(Image.FORMAT_RGBA8)
		var w := r.size.x
		var img := Image.create_empty(w * 16, 32, false, Image.FORMAT_RGBA8)
		var y_row := r.end.y - 1
		var door_tex := "door_wood" if building_types[bi].begins_with("house") else ("door_rusty" if building_types[bi] == "garage" else "door_metal")
		var win_tex := _window_tex(style)
		for x in w:
			# Plain pieces of the tileset: column 4 = left end, 9 = right end, 5-8 middle
			var top_col: int = 4 if x == 0 else (9 if x == w - 1 else [5, 6][x % 2])
			var face_col := 4 if x == 0 else (9 if x == w - 1 else (8 if rng.randf() < 0.2 else 7))
			# top half: wall with a top lip, bottom half: wall face, then a base strip
			img.blend_rect(src, Rect2i(top_col * 16, 3 * 16, 16, 16), Vector2i(x * 16, 0))
			img.blend_rect(src, Rect2i(face_col * 16, 4 * 16, 16, 16), Vector2i(x * 16, 16))
			img.blend_rect(src, Rect2i(top_col * 16, 5 * 16, 16, 6), Vector2i(x * 16, 26))
			var t := get_tile(Vector2i(r.position.x + x, y_row))
			if t == WINDOW:
				var win := Game.tex(win_tex if rng.randf() < 0.7 else _window_tex(style)).get_image()
				win.convert(Image.FORMAT_RGBA8)
				img.blend_rect(win, Rect2i(Vector2i.ZERO, win.get_size()), Vector2i(x * 16 + (16 - win.get_width()) / 2, 9))
			elif t == FLOOR:
				# doorway
				img.fill_rect(Rect2i(x * 16, 7, 16, 25), Color("1a1016"))
				var door := Game.tex(door_tex).get_image()
				door.convert(Image.FORMAT_RGBA8)
				img.blend_rect(door, Rect2i(Vector2i.ZERO, door.get_size()), Vector2i(x * 16, 32 - door.get_height()))
		var spr := Sprite2D.new()
		spr.texture = ImageTexture.create_from_image(img)
		spr.centered = false
		spr.scale = Vector2(2, 2)
		spr.offset = Vector2(0, -32)
		spr.position = Vector2(r.position.x * T, r.end.y * T)
		holder.add_child(spr)
		facades.append(spr)


## Soft shadows to the right of each building (light from the top-left).
func _build_shadows() -> void:
	var layer := Node2D.new()
	layer.z_index = -7
	add_child(layer)
	for r in buildings:
		var x := r.end.x * T
		var y0 := (r.position.y - 1) * T + 10
		var y1 := r.end.y * T
		var poly := Polygon2D.new()
		poly.polygon = PackedVector2Array([Vector2(x, y0), Vector2(x + 22, y0 + 22), Vector2(x + 22, y1 + 10), Vector2(x - (r.size.x * T) + 14, y1 + 10), Vector2(x - (r.size.x * T) + 4, y1)])
		poly.color = Color(0, 0, 0, 0.22)
		layer.add_child(poly)


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
		if i < facades.size():
			facades[i].modulate.a = r.modulate.a
			facades[i].visible = r.visible


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
