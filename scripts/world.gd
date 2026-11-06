class_name World
extends Node2D
## The map: named settlements of different sizes - hamlets (4-7 tiny huts on one street), villages (9-12
## buildings on a few streets), towns and one city (small street grids with shops, a clinic, police) - far apart
## and connected by long roads; hand-made buildings (see buildings.gd) facing the streets; street props and lootable cars;
## forests, lakes, a river, nature and animals in the wilderness between them.
## Also provides pathfinding and line of sight.

enum { GROUND, WALL, TREE, FLOOR, ROAD, WINDOW, FURN, WATER, BUILT }
enum { F_NONE, F_WOOD, F_TILE, F_CONCRETE }

const W := 512
const H := 512
## Settlements are clusters of a few buildings; at least this many tiles of wilderness between two clusters.
const CLUSTER_GAP := 42
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
var timing := false # print how long each generation step takes (dev)
## The world is an endless chain of regions; this is one of them. Roads leave it at one point on each
## edge, and the neighbouring region's road starts at the same point, so they join up.
var region := Vector2i.ZERO
var edge_seed := 0 # the game's seed (edges are shared by two regions, so they can't use the region's seed)

const REGION_NAMES := ["Ashen Vale", "Coldwater Basin", "Greyridge", "Northmarch", "Hollow Plains", "Blackpine",
	"Ironwood", "Mistfen", "Stonereach", "Redmoor", "Silverbrook", "Wolfden Hills", "Duskmarsh", "Highcairn",
	"Emberfield", "Frostmere", "Oakshade", "Thornvale", "Lowfield", "Ravenscar", "Brightwater", "Fallowmark",
	"Saltmere", "Briarwood", "Kestrel Heath", "Larchmoor", "Elderglen", "Westerling", "Cinderfall", "Rookmoor"]


## Steps of 7 east and 11 south through the list: regions next to each other (and a couple apart)
## never share a name.
static func region_name(game_seed: int, r: Vector2i) -> String:
	return REGION_NAMES[posmod(posmod(game_seed, 8) + r.x * 7 + r.y * 11, REGION_NAMES.size())]


## Where the road crosses an edge of this region ("N", "S", "W", "E"): a border cell.
func edge_exit(side: String) -> Vector2i:
	var h := 0
	match side:
		"W":
			h = hash([edge_seed, "v", region.x, region.y])
			return Vector2i(0, 40 + posmod(h, H - 80))
		"E":
			h = hash([edge_seed, "v", region.x + 1, region.y])
			return Vector2i(W - 1, 40 + posmod(h, H - 80))
		"N":
			h = hash([edge_seed, "h", region.x, region.y])
			return Vector2i(40 + posmod(h, W - 80), 0)
		_:
			h = hash([edge_seed, "h", region.x, region.y + 1])
			return Vector2i(40 + posmod(h, W - 80), H - 1)
var taps: Array[Vector2] = [] # bathroom taps (at house baths) - some still have water
var door_cells: Array = [] # every door: {"cell": Vector2i, "b": building index}
var door_closed := PackedByteArray() # per cell: 1 = a closed door (blocks zombies and sight)
## Zombies' pathfinding: like `astar`, but closed doors are solid (zombies can't open doors).
var astar_z := AStarGrid2D.new()
var _front_doors := {} # cell -> Sprite2D on the building's front wall
var _door_at := {}

const TOWN_NAMES := ["Ashford", "Millbrook", "Pine Hollow", "Greywater", "Stonebridge", "Redfield", "Elm Crossing",
	"Harrow", "Oakvale", "Cold Spring", "Linton", "Marsh End", "Westbury", "Fairhill", "Dunmore", "Northfield",
	"Bramley", "Kettle Creek", "Larkspur", "Willow Bend", "Hollins", "Birchwood", "Crow Hill", "Eastmere", "Foxley",
	"Glenrock", "Hartwell", "Ironside", "Juniper", "Kingsford", "Lowmoor", "Maple Ridge", "Netherby", "Old Mill",
	"Pebble Brook", "Quarry End", "Rookhurst", "Sandwell", "Thornby", "Upton", "Valewood", "Whitcombe", "Yarrow",
	"Ashby Cross", "Bellmoor", "Copper Hill"]
## Building mix per settlement type (weights)
const TOWN_MIX := {
	"city": {"house_small": 25, "house_large": 18, "hut_bed": 10, "hut_bath": 6, "shop": 12, "police": 6, "clinic": 6, "garage": 10},
	"town": {"house_small": 25, "house_large": 14, "hut_bed": 15, "hut_kitchen": 10, "hut_bath": 8, "shop": 8, "clinic": 4, "garage": 10},
	"village": {"hut_bed": 30, "hut_kitchen": 25, "hut_bath": 15, "hut_shed": 10, "house_small": 15, "house_large": 5, "garage": 5},
	"hamlet": {"hut_bed": 35, "hut_kitchen": 30, "hut_bath": 15, "hut_shed": 12, "house_small": 8},
	"military": {"mil_tent": 60, "mil_barracks": 20, "mil_armory": 20},
}
## Settlements to place, biggest first: [type, how many, buildings min, max]. What doesn't fit is skipped.
const CLUSTERS := [["city", 1, 16, 16], ["military", 1, 6, 7], ["town", 3, 11, 13], ["village", 8, 9, 12], ["hamlet", 26, 4, 7]]
## Buildings a settlement of a type gets first.
const FORCED := {"city": ["police", "clinic", "shop", "shop", "garage"], "town": ["shop", "clinic"],
	"military": ["mil_armory", "mil_barracks", "mil_tent", "mil_tent"]}
var _left: Array[int] = [] # buildings still to place, per settlement
var _forced: Array = [] # kinds still to place first, per settlement
## How likely a container in each building type has already been looted by someone else
const PRE_LOOTED := {"house_small": 0.4, "house_large": 0.4, "hut_bed": 0.4, "hut_kitchen": 0.4, "hut_bath": 0.4, "hut_shed": 0.35,
	"mil_tent": 0.15, "mil_barracks": 0.15, "mil_armory": 0.15, "shop": 0.5, "police": 0.3, "clinic": 0.4, "garage": 0.35}
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


## Walls, windows and closed doors block sight (so zombies can't spot you inside a closed house).
func blocks_sight(c: Vector2i) -> bool:
	var t := get_tile(c)
	return t == WALL or t == WINDOW or t == BUILT or (in_bounds(c) and door_closed[idx(c)] == 1)


# ---------------------------------------------------------------- things you build

var _built_body: StaticBody2D
var _built_shapes := {} # cell -> CollisionShape2D
var _built_prev := {} # cell -> the tile that was there


## A wall you built: blocks walking (everyone), bullets and sight.
func add_built(c: Vector2i) -> void:
	if _built_body == null:
		_built_body = StaticBody2D.new()
		_built_body.collision_layer = Game.LAYER_WALL
		_built_body.collision_mask = 0
		add_child(_built_body)
	_built_prev[c] = get_tile(c)
	set_tile(c, BUILT)
	astar.set_point_solid(c, true)
	astar_z.set_point_solid(c, true)
	var rs := RectangleShape2D.new()
	rs.size = Vector2(T, T)
	var cs := CollisionShape2D.new()
	cs.shape = rs
	cs.position = center_of(c)
	_built_body.add_child(cs)
	_built_shapes[c] = cs


func remove_built(c: Vector2i) -> void:
	set_tile(c, int(_built_prev.get(c, GROUND)))
	_built_prev.erase(c)
	astar.set_point_solid(c, not is_walkable(c))
	astar_z.set_point_solid(c, not is_walkable(c))
	if _built_shapes.has(c):
		(_built_shapes[c] as Node).queue_free()
		_built_shapes.erase(c)


## A gate you built: a door (opens for people, not for zombies).
func add_gate(c: Vector2i, door: Door) -> void:
	_door_at[c] = true
	var layer := get_node_or_null("Doors")
	if layer == null:
		layer = Node2D.new()
		layer.name = "Doors"
		layer.z_index = -6
		add_child(layer)
	layer.add_child(door)


func remove_gate(c: Vector2i) -> void:
	_door_at.erase(c)
	door_closed[idx(c)] = 0
	astar_z.set_point_solid(c, not is_walkable(c))


func is_door(c: Vector2i) -> bool:
	return _door_at.has(c)


## Called by doors: open doors let zombies through (and let them see through).
func set_door_open(c: Vector2i, o: bool) -> void:
	door_closed[idx(c)] = 0 if o else 1
	astar_z.set_point_solid(c, not o)


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
	door_closed.resize(W * H)
	door_closed.fill(0)
	var _tm := Time.get_ticks_usec()
	_make_settlements()
	if timing:
		print("  _make_settlements: %d ms" % ((Time.get_ticks_usec() - _tm) / 1000))
	_tm = Time.get_ticks_usec()
	_make_roads()
	if timing:
		print("  _make_roads: %d ms" % ((Time.get_ticks_usec() - _tm) / 1000))
	_tm = Time.get_ticks_usec()
	_make_buildings()
	_make_fences()
	if timing:
		print("  _make_buildings: %d ms" % ((Time.get_ticks_usec() - _tm) / 1000))
	_tm = Time.get_ticks_usec()
	_make_street()
	if timing:
		print("  _make_street: %d ms" % ((Time.get_ticks_usec() - _tm) / 1000))
	_tm = Time.get_ticks_usec()
	_make_water()
	if timing:
		print("  _make_water: %d ms" % ((Time.get_ticks_usec() - _tm) / 1000))
	_tm = Time.get_ticks_usec()
	_make_trees()
	if timing:
		print("  _make_trees: %d ms" % ((Time.get_ticks_usec() - _tm) / 1000))
	_tm = Time.get_ticks_usec()
	_make_nature()
	if timing:
		print("  _make_nature: %d ms" % ((Time.get_ticks_usec() - _tm) / 1000))
	_tm = Time.get_ticks_usec()
	_make_border()
	if timing:
		print("  _make_border: %d ms" % ((Time.get_ticks_usec() - _tm) / 1000))
	_tm = Time.get_ticks_usec()
	_find_spawn()
	if timing:
		print("  _find_spawn: %d ms" % ((Time.get_ticks_usec() - _tm) / 1000))
	_tm = Time.get_ticks_usec()
	_build_collision()
	if timing:
		print("  _build_collision: %d ms" % ((Time.get_ticks_usec() - _tm) / 1000))
	_tm = Time.get_ticks_usec()
	_build_astar()
	if timing:
		print("  _build_astar: %d ms" % ((Time.get_ticks_usec() - _tm) / 1000))
	_tm = Time.get_ticks_usec()
	_build_tilemaps()
	if timing:
		print("  _build_tilemaps: %d ms" % ((Time.get_ticks_usec() - _tm) / 1000))
	_tm = Time.get_ticks_usec()
	_place_trees(entities)
	if timing:
		print("  _place_trees: %d ms" % ((Time.get_ticks_usec() - _tm) / 1000))
	_tm = Time.get_ticks_usec()
	_place_props(entities)
	if timing:
		print("  _place_props: %d ms" % ((Time.get_ticks_usec() - _tm) / 1000))
	_tm = Time.get_ticks_usec()
	_place_furniture()
	if timing:
		print("  _place_furniture: %d ms" % ((Time.get_ticks_usec() - _tm) / 1000))
	_tm = Time.get_ticks_usec()
	_scatter_decor()
	if timing:
		print("  _scatter_decor: %d ms" % ((Time.get_ticks_usec() - _tm) / 1000))
	_tm = Time.get_ticks_usec()
	_build_roofs()
	if timing:
		print("  _build_roofs: %d ms" % ((Time.get_ticks_usec() - _tm) / 1000))
	_tm = Time.get_ticks_usec()
	_build_facades(entities)
	if timing:
		print("  _build_facades: %d ms" % ((Time.get_ticks_usec() - _tm) / 1000))
	_tm = Time.get_ticks_usec()
	_build_doors()
	if timing:
		print("  _build_doors: %d ms" % ((Time.get_ticks_usec() - _tm) / 1000))
	_tm = Time.get_ticks_usec()
	_build_shadows()
	if timing:
		print("  _build_shadows: %d ms" % ((Time.get_ticks_usec() - _tm) / 1000))
	_tm = Time.get_ticks_usec()


# ---------------------------------------------------------------- settlements & roads

func _make_settlements() -> void:
	var names := TOWN_NAMES.duplicate()
	for i in names.size():
		var j := rng.randi_range(i, names.size() - 1)
		var tmp = names[i]
		names[i] = names[j]
		names[j] = tmp
	for entry in CLUSTERS:
		for k in int(entry[1]):
			var kind: String = entry[0]
			var count := rng.randi_range(int(entry[2]), int(entry[3]))
			var st := _layout(kind, count)
			for attempt in 400:
				var margin := 12 + int(st["reach"])
				var c := Vector2i(rng.randi_range(margin, W - margin), rng.randi_range(margin, H - margin))
				if kind == "city":
					c = Vector2i(rng.randi_range(W / 2 - 40, W / 2 + 40), rng.randi_range(H / 2 - 40, H / 2 + 40))
				var streets := _cluster_streets(st, c)
				var r := _streets_rect(streets).grow(10)
				if r.position.x < 4 or r.position.y < 4 or r.end.x > W - 4 or r.end.y > H - 4:
					continue
				var ok := true
				for s2 in settlements:
					if (s2["rect"] as Rect2i).grow(CLUSTER_GAP).intersects(r):
						ok = false
						break
				if ok:
					st["name"] = names.pop_back() if not names.is_empty() else "Settlement %d" % settlements.size()
					if kind == "military":
						st["name"] = "Camp " + String(st["name"]).get_slice(" ", 0)
					st["center"] = c
					st["rect"] = r
					st["streets"] = streets
					settlements.append(st)
					_left.append(count)
					var forced: Array = (FORCED.get(kind, []) as Array).duplicate()
					if kind == "village" and rng.randf() < 0.5:
						forced.append("shop")
					_forced.append(forced)
					break


## Street plan for a settlement: a main street, cross streets off one side, and for towns / the city a back
## street joining the cross streets (a small grid). Lengths in tiles.
func _layout(kind: String, count: int) -> Dictionary:
	var st := {"type": kind, "vertical": rng.randf() < 0.5, "side": 1 if rng.randf() < 0.5 else -1}
	match kind:
		"military":
			st["len"] = 36
			st["cross"] = []
			st["cross_len"] = 0
			st["back"] = false
		"hamlet":
			st["len"] = maxi(24, ((count + 1) / 2) * 9 + 6)
			st["cross"] = []
			st["cross_len"] = 0
			st["back"] = false
		"village":
			st["len"] = 34
			st["cross"] = [rng.randi_range(-6, 6)]
			st["cross_len"] = 20
			st["back"] = false
		"town":
			st["len"] = 40
			st["cross"] = [-12, 12]
			st["cross_len"] = 20
			st["back"] = true
		_:
			st["len"] = 52
			st["cross"] = [-22, 0, 22]
			st["cross_len"] = 22
			st["back"] = true
	st["reach"] = maxi(int(st["len"]) / 2, int(st["cross_len"])) + 10
	return st


## Absolute street segments [vertical, at, from, to] of a settlement laid out around `c`.
func _cluster_streets(st: Dictionary, c: Vector2i) -> Array:
	var v: bool = st["vertical"]
	var lm: int = st["len"]
	var lc: int = st["cross_len"]
	var side: int = st["side"]
	var along0 := (c.y if v else c.x) - lm / 2
	var perp := c.x if v else c.y
	var out := [[v, perp - 1, along0, along0 + lm]]
	for o in st["cross"]:
		var along: int = (c.y if v else c.x) + int(o)
		var from := perp if side > 0 else perp - lc
		var to := perp + lc + 2 if side > 0 else perp + 2
		out.append([not v, along - 1, from, to])
	if st["back"]:
		out.append([v, perp + side * lc - 1, along0, along0 + lm])
	return out


func _streets_rect(streets: Array) -> Rect2i:
	var r := Rect2i()
	for i in streets.size():
		var sgm: Array = streets[i]
		var sr := Rect2i(int(sgm[1]), int(sgm[2]), 3, int(sgm[3]) - int(sgm[2])) if sgm[0] else Rect2i(int(sgm[2]), int(sgm[1]), int(sgm[3]) - int(sgm[2]), 3)
		r = sr if i == 0 else r.merge(sr)
	return r


## The settlements' streets, then long roads between the settlements.
func _make_roads() -> void:
	for ti in settlements.size():
		for sgm in settlements[ti]["streets"]:
			_add_segment(sgm[0], sgm[1], sgm[2], sgm[3], "street", ti)
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
	# Roads to the four edges of the region (they carry on in the next region)
	for side in ["N", "S", "W", "E"]:
		var ep := edge_exit(side)
		var inward: Vector2i = ep + {"N": Vector2i(0, 14), "S": Vector2i(0, -14), "W": Vector2i(14, 0), "E": Vector2i(-14, 0)}[side]
		var nearest := 0
		for i in settlements.size():
			if Vector2(settlements[i]["center"]).distance_to(Vector2(inward)) < Vector2(settlements[nearest]["center"]).distance_to(Vector2(inward)):
				nearest = i
		if side in ["W", "E"]:
			_add_segment(false, ep.y - 1, mini(ep.x, inward.x), maxi(ep.x, inward.x) + 2, "highway", -1)
		else:
			_add_segment(true, ep.x - 1, mini(ep.y, inward.y), maxi(ep.y, inward.y) + 2, "highway", -1)
		edges.append([nearest, -1, inward])
	# Each road leaves a settlement straight along its main street (so it never cuts through the building
	# lots), then bends once out in the wild.
	for e in edges:
		if int(e[1]) == -1:
			var ex := _cluster_exit(e[0], e[2])
			var ip: Vector2i = e[2]
			if rng.randf() < 0.5:
				_add_segment(false, ex.y - 1, mini(ex.x, ip.x) - 1, maxi(ex.x, ip.x) + 2, "highway", -1)
				_add_segment(true, ip.x - 1, mini(ex.y, ip.y) - 1, maxi(ex.y, ip.y) + 2, "highway", -1)
			else:
				_add_segment(true, ex.x - 1, mini(ex.y, ip.y) - 1, maxi(ex.y, ip.y) + 2, "highway", -1)
				_add_segment(false, ip.y - 1, mini(ex.x, ip.x) - 1, maxi(ex.x, ip.x) + 2, "highway", -1)
			continue
		var ea := _cluster_exit(e[0], settlements[e[1]]["center"])
		var eb := _cluster_exit(e[1], settlements[e[0]]["center"])
		var h_first := _road_overlaps(ea, eb, true) <= _road_overlaps(ea, eb, false)
		if _road_overlaps(ea, eb, true) == _road_overlaps(ea, eb, false):
			h_first = rng.randf() < 0.5
		if h_first:
			_add_segment(false, ea.y - 1, mini(ea.x, eb.x) - 1, maxi(ea.x, eb.x) + 2, "highway", -1)
			_add_segment(true, eb.x - 1, mini(ea.y, eb.y) - 1, maxi(ea.y, eb.y) + 2, "highway", -1)
		else:
			_add_segment(true, ea.x - 1, mini(ea.y, eb.y) - 1, maxi(ea.y, eb.y) + 2, "highway", -1)
			_add_segment(false, eb.y - 1, mini(ea.x, eb.x) - 1, maxi(ea.x, eb.x) + 2, "highway", -1)
	# Intersections: cells on both a horizontal and a vertical road
	for y in H:
		for x in W:
			if road_dir[y * W + x] == 3:
				intersections.append(Vector2i(x, y))


## Where a road leaves cluster `ti` towards `toward`: just past the end of its street (the street is
## extended to there).
func _cluster_exit(ti: int, toward: Vector2i) -> Vector2i:
	var st: Dictionary = settlements[ti]
	var r: Rect2i = st["rect"]
	var main: Array = st["streets"][0]
	var c: Vector2i = st["center"]
	var from: int = main[2]
	var to: int = main[3]
	if st["vertical"]:
		if toward.y < c.y:
			_add_segment(true, c.x - 1, r.position.y - 4, from + 1, "highway", -1)
			return Vector2i(c.x, r.position.y - 3)
		_add_segment(true, c.x - 1, to - 1, r.end.y + 4, "highway", -1)
		return Vector2i(c.x, r.end.y + 2)
	if toward.x < c.x:
		_add_segment(false, c.y - 1, r.position.x - 4, from + 1, "highway", -1)
		return Vector2i(r.position.x - 3, c.y)
	_add_segment(false, c.y - 1, to - 1, r.end.x + 4, "highway", -1)
	return Vector2i(r.end.x + 2, c.y)


## How many cells of an L-shaped road from a to b would run through a cluster.
func _road_overlaps(a: Vector2i, b: Vector2i, horizontal_first: bool) -> int:
	var corner := Vector2i(b.x, a.y) if horizontal_first else Vector2i(a.x, b.y)
	var n := 0
	for leg in [[a, corner], [corner, b]]:
		var p: Vector2i = leg[0]
		var q: Vector2i = leg[1]
		var steps := maxi(absi(q.x - p.x), absi(q.y - p.y))
		for i in steps + 1:
			var cell := p + (q - p) * i / maxi(steps, 1)
			for st in settlements:
				if (st["rect"] as Rect2i).grow(1).has_point(cell):
					n += 1
	return n


## Paints a 3-wide road from `from` to `to` along x (vertical = false) or y.
func _add_segment(vertical: bool, at: int, from: int, to: int, kind: String, town: int) -> void:
	from = clampi(from, 0, (H if vertical else W) - 1)
	to = clampi(to, 0, H if vertical else W) # roads may run right up to the region's edge
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
	if not in_bounds(c):
		return -1
	if _town_id.is_empty():
		_build_town_id()
	return _town_id[idx(c)]


## Settlement index per cell (its area grown by 3 tiles), -1 outside.
var _town_id := PackedInt32Array()


func _build_town_id() -> void:
	_town_id.resize(W * H)
	_town_id.fill(-1)
	for i in range(settlements.size() - 1, -1, -1):
		var r := (settlements[i]["rect"] as Rect2i).grow(3).intersection(Rect2i(0, 0, W, H))
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				_town_id[y * W + x] = i


## Cells within `r` tiles (a square) of any marked cell. Two sliding-window passes: fast on a big map.
func _dilate(src: PackedByteArray, r: int) -> PackedByteArray:
	var tmp := PackedByteArray()
	tmp.resize(W * H)
	for y in H:
		var row := y * W
		var cnt := 0
		for x in mini(r, W - 1) + 1:
			cnt += src[row + x]
		for x in W:
			tmp[row + x] = 1 if cnt > 0 else 0
			if x + r + 1 < W:
				cnt += src[row + x + r + 1]
			if x - r >= 0:
				cnt -= src[row + x - r]
	var out := PackedByteArray()
	out.resize(W * H)
	for x in W:
		var cnt := 0
		for y in mini(r, H - 1) + 1:
			cnt += tmp[y * W + x]
		for y in H:
			out[y * W + x] = 1 if cnt > 0 else 0
			if y + r + 1 < H:
				cnt += tmp[(y + r + 1) * W + x]
			if y - r >= 0:
				cnt -= tmp[(y - r) * W + x]
	return out


## 1 where the tile is one of `types`.
func _mask_of(types: Array) -> PackedByteArray:
	var m := PackedByteArray()
	m.resize(W * H)
	for i in W * H:
		if tiles[i] in types:
			m[i] = 1
	return m


# ---------------------------------------------------------------- buildings

## A few buildings close together on both sides of each cluster's street(s). Nothing along the highways:
## between clusters it's a long walk through the wild.
func _make_buildings() -> void:
	# Both sides of every street, then two more passes to fill gaps where a building didn't fit
	for pass_i in 4:
		for seg in segments:
			if seg["kind"] == "street":
				var mix: Dictionary = TOWN_MIX[settlements[seg["town"]]["type"]]
				_line_of_buildings(seg, -1 if pass_i % 2 == 0 else 1, mix, 0.04, seg["town"])


func _line_of_buildings(seg: Dictionary, side: int, mix: Dictionary, empty_lot: float, town: int) -> void:
	var vertical: bool = seg["vertical"]
	var at: int = seg["at"]
	var cursor: int = seg["from"] + rng.randi_range(1, 3)
	while cursor < int(seg["to"]) - 4:
		if town >= 0 and _left[town] <= 0:
			return
		if rng.randf() < empty_lot:
			cursor += rng.randi_range(3, 6)
			continue
		var forced: Array = _forced[town] if town >= 0 else []
		var kind: String = forced[0] if not forced.is_empty() else Buildings.pick(rng, mix)
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
			if town >= 0:
				_left[town] -= 1
				if not forced.is_empty():
					forced.pop_front()
			cursor += (bh if vertical else bw) + rng.randi_range(1, 2)
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
					if ch == "D":
						door_cells.append({"cell": c, "b": bi})
						_door_at[c] = true
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
						if ch == "A" and (kind.begins_with("house") or kind == "hut_bath"):
							taps.append(center_of(c) + Vector2(-8, -6))
	buildings.append(r)
	building_types.append(kind)
	building_town.append(town)
	var styles := {"house_small": ["beige", "white", "gray", "dark"], "house_large": ["beige", "white", "gray"],
		"hut_bed": ["beige", "white", "gray", "dark"], "hut_kitchen": ["beige", "white", "dark"], "hut_bath": ["beige", "white", "gray"],
		"hut_shed": ["dark", "gray"], "mil_tent": ["gray", "dark"], "mil_barracks": ["gray", "dark"], "mil_armory": ["dark"],
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
	# Street lights along settlement streets (not in military camps)
	for seg in segments:
		if seg["kind"] != "street" or settlements[seg["town"]]["type"] == "military":
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
				if _is_sidewalk(c) and not _near_intersection(c, 0) and not _by_door(c):
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
			if _is_sidewalk(c) and not _by_door(c):
				set_tile(c, FURN)
				props.append({"pos": center_of(c) + Vector2(0, 12), "tex": "prop_stop_down" if off.y < 0 else "prop_stop_up", "flip": false, "tall": true})
				break
	# Sidewalk clutter in settlements: hydrants, benches, garbage bins (searchable), trash bags, barrels
	var cells := []
	for st in settlements:
		if st["type"] == "military":
			continue # no benches, hydrants or bins in a military camp
		var sr := (st["rect"] as Rect2i).grow(3).intersection(Rect2i(2, 2, W - 4, H - 4))
		for y in range(sr.position.y, sr.end.y):
			for x in range(sr.position.x, sr.end.x):
				cells.append(Vector2i(x, y))
	for c0 in cells:
		var c: Vector2i = c0
		if true:
			if _is_sidewalk(c) and not _near_intersection(c, 1) and not _by_door(c):
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
		if seg["kind"] == "street" and settlements[seg["town"]]["type"] == "military":
			continue
		var town: bool = seg["kind"] == "street"
		var gap_min := 9 if town else 34
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


## Marks cells far from roads and buildings (at least 4 tiles) and outside settlements.
func _build_wild_mask() -> void:
	var near := _dilate(_mask_of([ROAD, WALL, WINDOW]), 3)
	if _town_id.is_empty():
		_build_town_id()
	_wild.resize(W * H)
	for i in W * H:
		_wild[i] = 1 if near[i] == 0 and _town_id[i] < 0 else 0


func _make_trees() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.05
	var built := _dilate(_mask_of([ROAD, WALL, FLOOR, WINDOW, FURN]), 1)
	if _town_id.is_empty():
		_build_town_id()
	for y in H:
		for x in W:
			var i := y * W + x
			if tiles[i] != GROUND or built[i] == 1:
				continue
			var p := 0.35 if noise.get_noise_2d(x, y) > 0.15 else 0.02
			if _town_id[i] >= 0:
				if settlements[_town_id[i]]["type"] == "military":
					continue # a cleared camp: no trees inside the fence
				p *= 0.12 # gardens, not forests, inside towns
			if rng.randf() >= p:
				continue
			var c := Vector2i(x, y)
			tiles[i] = TREE
			tree_cells.append(c)
			tree_tex.append("nat_drytree" if rng.randf() < 0.06 else TREES[rng.randi() % TREES.size()])


## Rocks, stumps, logs, sticks, flowers and mushrooms out in the wild, plus rare item finds.
func _make_nature() -> void:
	for k in int(W * H * 0.076):
		var c := Vector2i(rng.randi_range(2, W - 3), rng.randi_range(2, H - 3))
		if true:
			if not _is_wild(c):
				continue
			var r := rng.randf() * 0.076
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
			elif r < 0.0675:
				wild_spots.append(c) # rare finds (the map is big - keep them rare)
			elif r < 0.076:
				stick_spots.append(c)


# ---------------------------------------------------------------- water

## Lakes out in the wilderness and (usually) a river across the map. Roads cross the river on bridges.
func _make_water() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.12
	_near_built = _dilate(_mask_of([WALL, WINDOW, FLOOR, FURN]), 2)
	var near_road2 := _dilate(_mask_of([ROAD]), 2)
	var near_road6 := _dilate(_mask_of([ROAD]), 6)
	if rng.randf() < 0.85:
		# Try a few river courses and keep the one that stays clear of towns and buildings.
		var best: Array = []
		var best_bad := 1 << 30
		for attempt in 8:
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
	var lakes := rng.randi_range(W * H / 20000, W * H / 13000)
	for attempt in 600:
		if lakes <= 0:
			break
		var c := Vector2i(rng.randi_range(12, W - 13), rng.randi_range(12, H - 13))
		if not _water_ok(c, 8) or near_road6[idx(c)] == 1:
			continue
		var rx := rng.randf_range(3.5, 7.5)
		var ry := rng.randf_range(3.0, 6.0)
		for dy in range(-8, 9):
			for dx in range(-9, 10):
				var n := c + Vector2i(dx, dy)
				var v := pow(dx / rx, 2.0) + pow(dy / ry, 2.0) + noise.get_noise_2d(n.x * 2.0, n.y * 2.0) * 0.5
				if v < 1.0 and in_bounds(n) and _water_ok(n, 2) and near_road2[idx(n)] == 0:
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


var _near_built := PackedByteArray() # cells near buildings (set up by _make_water)


## Open ground away from towns (by `margin` tiles) and buildings.
func _water_ok(c: Vector2i, margin: int) -> bool:
	if c.x < 2 or c.y < 2 or c.x >= W - 2 or c.y >= H - 2 or get_tile(c) != GROUND:
		return false
	for st in settlements:
		if (st["rect"] as Rect2i).grow(margin).has_point(c):
			return false
	return _near_built[idx(c)] == 0


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


## The region's edge is open: you walk on into the next region. Zombies, animals and bandits stay in
## (an invisible wall on their own physics layer, see _build_collision).
func _make_border() -> void:
	pass


## You start on the main street of a village.
func _find_spawn() -> void:
	var options := []
	for seg in segments:
		if seg["kind"] == "street" and settlements[seg["town"]]["type"] in ["hamlet", "village"]:
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

## Static collision (walls, windows, furniture, cars, water, trees, the region edge) lives straight in the
## physics server: tens of thousands of CollisionShape2D nodes took seconds to free when you changed region.
var _bodies: Array[RID] = []
var _shapes := {} # size / radius -> shape RID (shared)
var _block_bodies := {} # [layer, 64x64-tile block] -> body: many small bodies keep the physics step quick


func _make_body(layer: int) -> RID:
	var b := PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(b, PhysicsServer2D.BODY_MODE_STATIC)
	PhysicsServer2D.body_set_collision_layer(b, layer)
	PhysicsServer2D.body_set_collision_mask(b, 0)
	PhysicsServer2D.body_attach_object_instance_id(b, get_instance_id())
	_bodies.append(b)
	return b


func _rect_shape(size: Vector2) -> RID:
	if not _shapes.has(size):
		var r := PhysicsServer2D.rectangle_shape_create()
		PhysicsServer2D.shape_set_data(r, size * 0.5)
		_shapes[size] = r
	return _shapes[size]


func _add_rect(body: RID, rect: Rect2) -> void:
	PhysicsServer2D.body_add_shape(body, _rect_shape(rect.size), Transform2D(0.0, rect.get_center()))


## The body for static collision of `layer` around `pos` (one per 64x64-tile block).
func _block_body(layer: int, pos: Vector2) -> RID:
	var k := [layer, int(pos.x) >> 11, int(pos.y) >> 11] # 64 tiles x 32 px = 2048 = 2^11
	if not _block_bodies.has(k):
		_block_bodies[k] = _make_body(layer)
	return _block_bodies[k]


## Horizontal runs of `kinds` tiles, one rectangle per run (split at block edges).
func _add_runs(layer: int, kinds: Array) -> void:
	for y in H:
		var x := 0
		while x < W:
			if not kinds.has(tiles[y * W + x]):
				x += 1
				continue
			var start := x
			while x < W and kinds.has(tiles[y * W + x]) and (x == start or x % 64 != 0):
				x += 1
			var rr := Rect2(start * T, y * T, (x - start) * T, T)
			_add_rect(_block_body(layer, rr.position), rr)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for b in _bodies:
			# Last shape first: removing from the front shifts every other shape (seconds for the trees).
			for i in range(PhysicsServer2D.body_get_shape_count(b) - 1, -1, -1):
				PhysicsServer2D.body_remove_shape(b, i)
			PhysicsServer2D.free_rid(b)
		for k in _shapes:
			PhysicsServer2D.free_rid(_shapes[k])
		_bodies.clear()
		_shapes.clear()
		_block_bodies.clear()


func _build_collision() -> void:
	_add_runs(Game.LAYER_WALL, [WALL, WINDOW, FURN])
	for r in car_rects:
		_add_rect(_block_body(Game.LAYER_WALL, r.get_center()), r)
	# Region edge: keeps creatures in; you can walk out (into the next region)
	var edge := _make_body(Game.LAYER_EDGE)
	var sz := size_px()
	for rr in [Rect2(-32, -32, sz.x + 64, 32), Rect2(-32, sz.y, sz.x + 64, 32), Rect2(-32, 0, 32, sz.y), Rect2(sz.x, 0, 32, sz.y)]:
		_add_rect(edge, rr)
	# Water blocks walking, not bullets or sight (its own layer).
	_add_runs(Game.LAYER_WATER, [WATER])
	# Trees: one body per 64x64-tile block (a single body with ~20k shapes made the physics step crawl).
	var circle := PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(circle, 10.0)
	_shapes["tree"] = circle
	for c in tree_cells:
		PhysicsServer2D.body_add_shape(_block_body(Game.LAYER_WALL, center_of(c)), circle, Transform2D(0.0, center_of(c) + Vector2(0, 6)))
	# Into the physics space once all their shapes are added (adding shapes to a body already in the
	# space updates the broadphase every time).
	for b in _bodies:
		PhysicsServer2D.body_set_space(b, get_world_2d().space)


func _build_astar() -> void:
	for a in [astar, astar_z]:
		var g := a as AStarGrid2D
		g.region = Rect2i(0, 0, W, H)
		g.cell_size = Vector2(T, T)
		g.offset = Vector2(T * 0.5, T * 0.5)
		g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		g.update()
	# Solid runs per row (much quicker than a call per cell)
	for y in H:
		var row := y * W
		var x := 0
		while x < W:
			var t := tiles[row + x]
			if t == GROUND or t == FLOOR or t == ROAD:
				x += 1
				continue
			var start := x
			while x < W:
				t = tiles[row + x]
				if t == GROUND or t == FLOOR or t == ROAD:
					break
				x += 1
			var r := Rect2i(start, y, x - start, 1)
			astar.fill_solid_region(r, true)
			astar_z.fill_solid_region(r, true)


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

	# Grass: one big repeating background instead of a tile in every cell (fast on a big map)
	var grass := Sprite2D.new()
	grass.texture = _make_grass()
	grass.centered = false
	grass.region_enabled = true
	grass.region_rect = Rect2(Vector2.ZERO, size_px() / 2.0)
	grass.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	grass.scale = Vector2(2, 2)
	grass.z_index = -11
	add_child(grass)
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
	_add_region_drawers(WaterBanks, -10)
	var walls := TileMapLayer.new()
	walls.tile_set = ts
	walls.scale = Vector2(2, 2)
	walls.z_index = -9
	add_child(walls)

	for y in H:
		for x in W:
			var t := tiles[y * W + x]
			var fk := floor_kind[y * W + x]
			if (t == GROUND or t == TREE) and fk == F_NONE:
				continue # grass background
			var c := Vector2i(x, y)
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
			elif t != WATER:
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
	_add_region_drawers(Line2DOutline, -8)
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


## Overlays that draw per map region (so the renderer can skip the regions that are off screen).
const REGION := 64


func _add_region_drawers(script: GDScript, z: int) -> void:
	for ry in range(0, H, REGION):
		for rx in range(0, W, REGION):
			var n = script.new()
			n.world = self
			n.region = Rect2i(rx, ry, mini(REGION, W - rx), mini(REGION, H - ry))
			n.z_index = z
			add_child(n)


## A 128x128 patch of random grass tiles (repeats across the map), with a few flowery / darker tiles.
func _make_grass() -> Texture2D:
	var src := Game.tex("tiles_ground").get_image()
	src.convert(Image.FORMAT_RGBA8)
	var img := Image.create_empty(128, 128, false, Image.FORMAT_RGBA8)
	for ty in 8:
		for tx in 8:
			var g: Array = GRASS_DECOR_TILES if rng.randf() < 0.06 else GRASS_TILES
			var t: Vector2i = g[rng.randi() % g.size()]
			img.blit_rect(src, Rect2i(t * 16, Vector2i(16, 16)), Vector2i(tx * 16, ty * 16))
	return ImageTexture.create_from_image(img)


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
	return t == WALL or t == WINDOW or t == BUILT


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


# Trees, props and decor are only turned into sprites near the player (streamed in 16x16-tile chunks):
# a big map would otherwise need tens of thousands of nodes.
const CHUNK := 16
var _chunk_specs := {} # chunk -> [{tex, pos, flip, layer (0 tall / 1 flat / 2 decor), offset, centered, alpha}]
var _chunk_live := {} # chunk -> [tall, flat, decor] nodes
var _stream_roots: Array[Node2D] = []


func _add_static(spec: Dictionary) -> void:
	var pos: Vector2 = spec["pos"]
	var ck := Vector2i(floori(pos.x / (T * CHUNK)), floori(pos.y / (T * CHUNK)))
	if not _chunk_specs.has(ck):
		_chunk_specs[ck] = []
	_chunk_specs[ck].append(spec)


func _place_trees(entities: Node2D) -> void:
	var tall := Node2D.new()
	tall.name = "Trees"
	tall.y_sort_enabled = true
	entities.add_child(tall)
	var flat := Node2D.new()
	flat.z_index = -6
	add_child(flat)
	var decor := Node2D.new()
	decor.z_index = -7
	add_child(decor)
	_stream_roots = [tall, flat, decor]
	for i in tree_cells.size():
		var c := tree_cells[i]
		var sz := Game.tex(tree_tex[i]).get_size()
		_add_static({"tex": tree_tex[i], "pos": center_of(c) + Vector2(0, 10), "flip": rng.randf() < 0.5, "layer": 0,
			"offset": Vector2(-floorf(sz.x / 2.0), -sz.y + 2.0), "centered": false})


## Street props and nature. Tall ones are y-sorted with the player; flat ones lie on the ground.
func _place_props(_entities: Node2D) -> void:
	for pr in props:
		var h := Game.tex(pr["tex"]).get_height()
		_add_static({"tex": pr["tex"], "pos": pr["pos"], "flip": pr["flip"], "layer": 0 if pr["tall"] else 1,
			"offset": Vector2(0, -h / 2.0 + 1.0) if pr["tall"] else Vector2.ZERO, "centered": true})


## Builds the chunks around `center` (within `half` px + a margin) and frees the far ones.
## `budget` = how many chunks may be built this call (-1 = all, used when the game starts).
func update_stream(center: Vector2, half: Vector2, budget := 2) -> void:
	if _stream_roots.is_empty():
		return
	var span := T * CHUNK
	var lo := Vector2i(floori((center.x - half.x) / span) - 1, floori((center.y - half.y) / span) - 1)
	var hi := Vector2i(floori((center.x + half.x) / span) + 1, floori((center.y + half.y) / span) + 1)
	for cy in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			var ck := Vector2i(cx, cy)
			if _chunk_live.has(ck) or not _chunk_specs.has(ck):
				continue
			if budget == 0:
				continue
			_build_chunk(ck)
			budget -= 1
	for ck in _chunk_live.keys():
		var c: Vector2i = ck
		if c.x < lo.x - 1 or c.x > hi.x + 1 or c.y < lo.y - 1 or c.y > hi.y + 1:
			for n in _chunk_live[c]:
				(n as Node).queue_free()
			_chunk_live.erase(c)


func _build_chunk(ck: Vector2i) -> void:
	var nodes: Array[Node2D] = []
	for k in 3:
		var n := Node2D.new()
		n.y_sort_enabled = k == 0
		_stream_roots[k].add_child(n)
		nodes.append(n)
	for spec in _chunk_specs[ck]:
		var sp := Sprite2D.new()
		sp.texture = Game.tex(spec["tex"])
		sp.scale = Vector2(2, 2)
		sp.position = spec["pos"]
		sp.flip_h = spec["flip"]
		sp.centered = spec.get("centered", true)
		sp.offset = spec.get("offset", Vector2.ZERO)
		sp.modulate.a = spec.get("alpha", 1.0)
		nodes[int(spec["layer"])].add_child(sp)
	_chunk_live[ck] = nodes


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
	for i in W * H / 72:
		var c := Vector2i(rng.randi_range(1, W - 2), rng.randi_range(1, H - 2))
		var t := get_tile(c)
		var tex := ""
		var alpha := 1.0
		if t == GROUND and not _near_type(c, WALL, 1):
			tex = ("bush_%d" % rng.randi_range(1, 2)) if rng.randf() < 0.25 else ("grass_%d" % rng.randi_range(1, 5))
		elif (t == ROAD or t == FLOOR) and rng.randf() < 0.25:
			tex = "blood_%d" % rng.randi_range(1, 5)
			alpha = 0.7
		else:
			continue
		_add_static({"tex": tex, "pos": center_of(c) + Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8)),
			"flip": rng.randf() < 0.5, "layer": 2, "alpha": alpha})


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
		if String(building_types[bi]).begins_with("mil_"):
			base = 0 # military: the grey-blue roof, painted olive
			roof.self_modulate = Color(0.72, 0.84, 0.5)
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
		var door_tex := "door_wood" if _wooden(building_types[bi]) else ("door_rusty" if building_types[bi] in ["garage", "hut_shed"] else "door_metal")
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
				# doorway (the door itself is a separate sprite that opens and closes, see door.gd)
				img.fill_rect(Rect2i(x * 16, 7, 16, 25), Color("1a1016"))
		var spr := Sprite2D.new()
		spr.texture = ImageTexture.create_from_image(img)
		spr.centered = false
		spr.scale = Vector2(2, 2)
		spr.offset = Vector2(0, -32)
		spr.position = Vector2(r.position.x * T, r.end.y * T)
		holder.add_child(spr)
		facades.append(spr)
		for x in w:
			var dc := Vector2i(r.position.x + x, y_row)
			if get_tile(dc) == FLOOR:
				var ds := Sprite2D.new()
				ds.centered = false
				ds.position = Vector2(x * 16, -25)
				ds.set_meta("door_tex", door_tex)
				spr.add_child(ds)
				_front_doors[dc] = ds


## Next to a building's door (keep it clear: no benches or bins blocking the way in).
func _by_door(c: Vector2i) -> bool:
	for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 2), Vector2i(0, -2), Vector2i(2, 0), Vector2i(-2, 0)]:
		if _door_at.has(c + d):
			return true
	return false


## Military camps are fenced in (gaps where the roads come in).
func _make_fences() -> void:
	for st in settlements:
		if st["type"] != "military":
			continue
		var r: Rect2i = (st["rect"] as Rect2i).grow(1)
		for x in range(r.position.x, r.end.x):
			for y in [r.position.y, r.end.y - 1]:
				_fence(Vector2i(x, y))
		for y in range(r.position.y, r.end.y):
			for x in [r.position.x, r.end.x - 1]:
				_fence(Vector2i(x, y))


func _fence(c: Vector2i) -> void:
	if in_bounds(c) and get_tile(c) == GROUND:
		set_tile(c, WALL)


## Homes have wooden doors; shops, garages, sheds and the like metal ones.
func _wooden(kind: String) -> bool:
	return kind.begins_with("house") or kind in ["hut_bed", "hut_kitchen", "hut_bath"]


## A Door for every doorway: opens for people, stays shut for zombies and animals.
func _build_doors() -> void:
	var layer := Node2D.new()
	layer.name = "Doors"
	layer.z_index = -6
	add_child(layer)
	for d in door_cells:
		var door := Door.new()
		door.world = self
		door.cell = d["cell"]
		var kind := building_types[int(d["b"])]
		door.metal = not _wooden(kind)
		door.tex_closed = "door_wood_closed" if _wooden(kind) else ("door_rusty" if kind in ["garage", "hut_shed"] else "door_metal")
		door.tex_open = "door_wood" if _wooden(kind) else ""
		door.front = _front_doors.get(d["cell"])
		layer.add_child(door)


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

## Walls, windows and closed doors block sight; furniture, cars and water don't.
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


## The cells you can walk to from `c` (zombies: not through closed doors), if there are fewer than
## `limit` of them - a closed-in spot like a walled base or a shut house. Empty when the area is bigger.
## Lets a zombie give up on an unreachable spot without searching the whole map.
func small_pocket(c: Vector2i, limit: int, zombie := true) -> Dictionary:
	var g := astar_z if zombie else astar
	if not in_bounds(c) or g.is_point_solid(c) or not _built_within(c, 40):
		return {} # only walls you built close spots in (houses are handled by their doors)
	return _pocket(c, limit, g)


## Is there a wall you built within `r` tiles?
func _built_within(c: Vector2i, r: int) -> bool:
	for k in _built_prev:
		var b: Vector2i = k
		if absi(b.x - c.x) <= r and absi(b.y - c.y) <= r:
			return true
	return false


func _pocket(c: Vector2i, limit: int, g: AStarGrid2D) -> Dictionary:
	var seen := {c: true}
	var q: Array[Vector2i] = [c]
	var i := 0
	while i < q.size():
		var cur: Vector2i = q[i]
		i += 1
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + o
			if not seen.has(n) and in_bounds(n) and not g.is_point_solid(n):
				seen[n] = true
				if seen.size() >= limit:
					return {}
				q.append(n)
	return seen


## Path between two points. Zombies (zombie = true) can't go through closed doors: they get as close
## as they can instead.
func find_path(from: Vector2, to: Vector2, zombie := false) -> PackedVector2Array:
	var a := nearest_walkable(cell_of(from))
	var b := nearest_walkable(cell_of(to))
	if not in_bounds(a) or not in_bounds(b) or not is_walkable(a) or not is_walkable(b):
		return PackedVector2Array()
	var t0 := Time.get_ticks_usec()
	var out := (astar_z if zombie else astar).get_point_path(a, b, true)
	if timing and Time.get_ticks_usec() - t0 > 4000:
		print("    slow path %s -> %s (zombie %s): %d ms" % [a, b, zombie, (Time.get_ticks_usec() - t0) / 1000])
	return out


func random_walkable_near(p: Vector2, radius_tiles: int) -> Vector2:
	var c := cell_of(p)
	for i in 10:
		var n := c + Vector2i(rng.randi_range(-radius_tiles, radius_tiles), rng.randi_range(-radius_tiles, radius_tiles))
		if is_walkable(n):
			return center_of(n)
	return p
