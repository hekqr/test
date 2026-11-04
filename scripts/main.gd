extends Node2D
## Builds a run: world, loot, player, zombies, day/night, HUD.

# Creatures live around the player: they spawn in a ring out of sight (SPAWN_MIN..SPAWN_MAX px away)
# and are removed when they wander far away (DESPAWN px), so a big map costs nothing extra.
const SPAWN_MIN := 1000.0
const SPAWN_MAX := 2400.0
const DESPAWN := 3200.0
const MAX_ZOMBIES_DAY := 10 # alive at once (around you)
const MAX_ZOMBIES_NIGHT := 15
const ZOMBIE_SPAWN_EVERY := 12.0 # seconds between new zombies (when below the cap)
const DAY_LENGTH := 480.0 # seconds for a full day/night cycle
const AUTOSAVE_EVERY := 30.0
const MAX_RABBITS := 8
const MAX_DEER := 4
const MAX_WOLVES := 5 # in packs of 2-3
const MAX_SURVIVORS := 3 # hostile bandits alive at once
## Zombie mix: [type, weight]. Runners show up more at night, armed zombies more in the city.
const ZOMBIE_MIX := [["walker", 62.0], ["runner", 12.0], ["brute", 10.0], ["axe", 7.0], ["armed", 9.0]]

var world: World
var player: Player
var zombies: Node2D
var entities: Node2D
var hud: Hud
var night_tint: CanvasModulate
var time_of_day := 0.3 # 0 = midnight, 0.5 = noon
var day := 1
var survived := 0.0
var kills := 0
var world_seed := 0
var _spawn_t := 0.0
var _save_t := AUTOSAVE_EVERY
var _animal_t := 0.0
var _survivor_t := 0.0
var _despawn_t := 0.0
var _glint_t := 0.0
var _save_task := -1
var survivors: Node2D
## Map exploration: 1 = you've seen this cell (W x H)
var explored := PackedByteArray()
var explored_coarse := PackedByteArray() # the same at 1/4 size (for the map's fog)
var _reveal_t := 0.0
const REVEAL_RADIUS := 15


func _ready() -> void:
	randomize()
	get_tree().set_auto_accept_quit(false)
	Game.noise_made.connect(_on_noise)
	var save: Dictionary = Game.pending_load
	Game.pending_load = {}
	_setup(save)


## The world is a chain of regions. Region (0, 0) is where you start; walk off an edge of the map to
## travel to the next one. Each region remembers what you left there (searched containers, piles,
## fires, tap water, the map you've explored).
var region := Vector2i.ZERO
var region_name := ""
var regions_state := {} # "x,y" -> {loot, taps, fires, explored} for the regions you're not in
var _travelling := false


static func _rkey(r: Vector2i) -> String:
	return "%d,%d" % [r.x, r.y]


func region_seed() -> int:
	return world_seed if region == Vector2i.ZERO else hash([world_seed, region.x, region.y])


## Builds the current region and everything in it from a save (empty = a new game).
func _setup(save: Dictionary) -> void:
	Game.ui_open = false
	Game.click_used = false
	world_seed = int(save["seed"]) if not save.is_empty() else randi()
	var rr: Array = save.get("region", [0, 0])
	region = Vector2i(int(rr[0]), int(rr[1]))
	regions_state = save.get("regions", {})
	region_name = World.region_name(world_seed, region)
	var fresh: bool = save.is_empty() or save.get("fresh_region", false)
	world = World.new()
	world.region = region
	world.edge_seed = world_seed
	add_child(world)
	entities = Node2D.new()
	entities.name = "Entities"
	entities.y_sort_enabled = true
	entities.add_to_group("entities")
	add_child(entities)
	world.generate(region_seed(), entities)
	explored.resize(World.W * World.H)
	explored_coarse.resize((World.W >> 2) * (World.H >> 2))
	# You know your home region: its map starts filled in. Other regions you have to explore.
	var known := 1 if (save.is_empty() and region == Vector2i.ZERO) else 0
	explored.fill(known)
	explored_coarse.fill(known)
	if fresh:
		_spawn_loot()
	else:
		var saved_at := {}
		for d in save["loot"]:
			var l := LootSpot.from_save(d)
			if not l.is_bag:
				saved_at[Vector2i(l.position.round())] = true
			entities.add_child(l)
		for c in world.containers:
			if not saved_at.has(Vector2i((c["pos"] as Vector2).round())):
				_spawn_container(c)
	# Bathroom taps: about half still have a little water in the pipes
	var tap_water: Array = save.get("taps", [])
	for i in world.taps.size():
		var t := WaterSource.new()
		t.position = world.taps[i]
		if tap_water.size() == world.taps.size():
			t.water = int(tap_water[i])
		else:
			t.water = randi_range(1, 6) if randf() < 0.45 else 0
		entities.add_child(t)

	zombies = Node2D.new()
	zombies.name = "Zombies"
	zombies.y_sort_enabled = true
	entities.add_child(zombies)

	player = Player.new()
	player.world = world
	player.position = world.center_of(world.spawn_cell)
	entities.add_child(player)
	player.died.connect(_on_player_died)

	survivors = Node2D.new()
	survivors.name = "Survivors"
	survivors.y_sort_enabled = true
	entities.add_child(survivors)

	if not save.is_empty():
		_apply_save(save)
	if save.has("arrive"):
		_arrive(String(save["arrive"]["side"]), float(save["arrive"]["along"]))
		player.say("Entering " + region_name)
	if fresh:
		for i in MAX_ZOMBIES_DAY:
			spawn_zombie(700.0)
		for k in 6:
			if not spawn_survivor_group(1300.0, 3200.0).is_empty():
				break
	for i in MAX_RABBITS:
		spawn_animal("rabbit", 500.0)
	for i in MAX_DEER:
		spawn_animal("deer", 500.0)
	spawn_wolf_pack(1100.0)
	world.update_stream(player.position, Vector2(1000, 600), -1) # trees & props around you

	night_tint = CanvasModulate.new()
	add_child(night_tint)

	var grade_layer := CanvasLayer.new()
	grade_layer.layer = 1
	add_child(grade_layer)
	var grade := ColorRect.new()
	grade.set_anchors_preset(Control.PRESET_FULL_RECT)
	grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/color_grade.gdshader")
	grade.material = mat
	grade_layer.add_child(grade)

	var layer := CanvasLayer.new()
	layer.layer = 2
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	hud = Hud.new()
	hud.main = self
	layer.add_child(hud)

	Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	hud.prepare_map() # build the paper map now, not when it's first opened
	if save.is_empty():
		save_game() # a new survivor replaces the old save straight away


## Puts you just inside the edge of the region you arrived at (`side`), across from where you left.
func _arrive(side: String, along: float) -> void:
	var a := clampi(int(along / World.T), 3, World.W - 4)
	for depth in range(2, 60):
		for k in 25:
			var off := (k + 1) / 2 * (1 if k % 2 == 1 else -1)
			var c: Vector2i
			match side:
				"W":
					c = Vector2i(depth, a + off)
				"E":
					c = Vector2i(World.W - 1 - depth, a + off)
				"N":
					c = Vector2i(a + off, depth)
				_:
					c = Vector2i(a + off, World.H - 1 - depth)
			if world.is_walkable(c) and world.building_at(world.center_of(c)) < 0:
				player.position = world.center_of(c)
				return


## Walks you into the neighbouring region (dir = which way you went off the map).
func travel(dir: Vector2i) -> void:
	if _travelling or player.dead:
		return
	_travelling = true
	var data: Dictionary = to_save().duplicate(true)
	regions_state[_rkey(region)] = {"loot": data["loot"], "taps": data["taps"], "fires": data["fires"],
		"explored": Marshalls.raw_to_base64(explored.compress(FileAccess.COMPRESSION_DEFLATE))}
	var nr := region + dir
	var nk := _rkey(nr)
	data.erase("explored_raw")
	data.erase("explored")
	data["zombies"] = []
	data["survivors"] = []
	if regions_state.has(nk):
		var st: Dictionary = regions_state[nk]
		data["loot"] = st["loot"]
		data["taps"] = st["taps"]
		data["fires"] = st["fires"]
		data["explored"] = st["explored"]
		regions_state.erase(nk)
		data.erase("fresh_region")
	else:
		data["loot"] = []
		data["taps"] = []
		data["fires"] = []
		data["fresh_region"] = true
	data["region"] = [nr.x, nr.y]
	data["regions"] = regions_state.duplicate(true)
	var sides := {Vector2i(1, 0): "W", Vector2i(-1, 0): "E", Vector2i(0, 1): "N", Vector2i(0, -1): "S"}
	data["arrive"] = {"side": sides[dir], "along": player.position.y if dir.x != 0 else player.position.x}
	hud.travel_text = "Travelling to %s..." % World.region_name(world_seed, nr)
	await get_tree().process_frame
	await get_tree().process_frame
	if _save_task != -1:
		WorkerThreadPool.wait_for_task_completion(_save_task)
		_save_task = -1
	for c in get_children():
		remove_child(c)
		c.free()
	_setup(data)
	_travelling = false
	save_game()


## Marks the area around a position as explored on the map.
func reveal_around(pos: Vector2) -> void:
	var c := world.cell_of(pos)
	var r := REVEAL_RADIUS
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= r * r:
				var n := c + Vector2i(dx, dy)
				if world.in_bounds(n):
					explored[world.idx(n)] = 1
					explored_coarse[(n.y >> 2) * (World.W >> 2) + (n.x >> 2)] = 1


func _spawn_container(c: Dictionary) -> void:
	var l := LootSpot.new()
	l.kind = c["kind"]
	l.tex_name = c["tex"]
	l.flip = c["flip"]
	l.reach = c["reach"]
	l.position = c["pos"]
	if randf() < float(c.get("empty_chance", 0.0)):
		l.loaded = true # someone got here first: starts empty
	entities.add_child(l)


func _spawn_loot() -> void:
	# Furniture, garbage bins and cars (each with its own loot table)
	for c in world.containers:
		_spawn_container(c)
	# Loose items lying on building floors
	for i in world.buildings.size():
		var floors: Array = world.building_floors[i]
		if floors.is_empty() or randf() > 0.15:
			continue
		var g := LootSpot.new()
		g.is_bag = true
		g.position = world.center_of(floors[randi() % floors.size()]) + Vector2(randf_range(-8, 8), randf_range(-8, 8))
		entities.add_child(g)
	# Sticks in the woods
	for c in world.stick_spots:
		var g := LootSpot.new()
		g.is_bag = true
		g.contents = [Items.make("sticks", randi_range(1, 3))]
		g.position = world.center_of(c) + Vector2(randf_range(-8, 8), randf_range(-8, 8))
		entities.add_child(g)
	# Rare finds out in the wild
	for c in world.wild_spots:
		var g := LootSpot.new()
		g.is_bag = true
		g.contents = Loot.roll("wild")
		g.position = world.center_of(c)
		entities.add_child(g)


# ---------------------------------------------------------------- saving

func to_save() -> Dictionary:
	var loot := []
	# Containers you haven't opened aren't saved (they're filled again when the game loads) - keeps saves small.
	for n in get_tree().get_nodes_in_group("loot"):
		var l := n as LootSpot
		if not l.is_queued_for_deletion() and (l.is_bag or l.opened or l.kind == "carcass"):
			loot.append(l.to_save())
	var zs := []
	for n in get_tree().get_nodes_in_group("zombies"):
		zs.append((n as Zombie).to_save())
	var ss := []
	for n in get_tree().get_nodes_in_group("survivors"):
		ss.append((n as Survivor).to_save())
	var p := player
	return {
		"seed": world_seed, "dead": p.dead, "day": day, "time_of_day": time_of_day,
		"region": [region.x, region.y], "regions": regions_state,
		"survived": survived, "kills": kills,
		"player": {
			"pos": [p.position.x, p.position.y], "health": p.health, "hunger": p.hunger,
			"thirst": p.thirst, "bleeding": p.bleeding, "temp": p.body_temp, "poison": p.poison_t,
			"inv": p.inv.to_save(),
		},
		"loot": loot, "zombies": zs, "survivors": ss,
		"taps": get_tree().get_nodes_in_group("taps").map(func(t): return t.water),
		"fires": get_tree().get_nodes_in_group("fires").map(func(f): return f.to_save()),
		"explored_raw": explored, # compressed when written (see SaveGame.write)
	}


## Saves the game. Autosaves run in the background (a worker thread turns the snapshot into JSON and
## writes it), so the game doesn't hitch; quitting / dying saves right away.
func save_game(background := false) -> void:
	var data := to_save().duplicate(true) # a snapshot the game can keep changing while it's written
	if _save_task != -1:
		if background and not WorkerThreadPool.is_task_completed(_save_task):
			return # still writing the last one
		WorkerThreadPool.wait_for_task_completion(_save_task)
		_save_task = -1
	if background:
		_save_task = WorkerThreadPool.add_task(SaveGame.write.bind(data))
	else:
		SaveGame.write(data)


func _apply_save(s: Dictionary) -> void:
	day = int(s["day"])
	time_of_day = s["time_of_day"]
	survived = s["survived"]
	kills = int(s["kills"])
	var ps: Dictionary = s["player"]
	player.position = SaveGame.vec(ps["pos"])
	player.health = ps["health"]
	player.hunger = ps["hunger"]
	player.thirst = ps["thirst"]
	player.bleeding = ps["bleeding"]
	player.body_temp = ps.get("temp", 60.0)
	player.poison_t = ps.get("poison", 0.0)
	player.update_outfit()
	if ps.has("inv"):
		player.inv.load_save(ps["inv"])
	if s.has("explored"):
		var raw := Marshalls.base64_to_raw(s["explored"]).decompress(World.W * World.H, FileAccess.COMPRESSION_DEFLATE)
		if raw.size() == World.W * World.H:
			explored = raw
			for i in raw.size():
				if raw[i] == 1:
					explored_coarse[((i / World.W) >> 2) * (World.W >> 2) + ((i % World.W) >> 2)] = 1
	for fd in s.get("fires", []):
		add_fire(SaveGame.vec(fd["pos"]), fd["fuel"])
	for zd in s["zombies"]:
		var z := add_zombie(SaveGame.vec(zd["pos"]), String(zd.get("type", "walker")), String(zd.get("gun", "")), int(zd.get("mag", 0)))
		z.health = zd["health"]
		z.has_axe = zd.get("has_axe", true)
	for sd in s.get("survivors", []):
		add_survivor(Survivor.from_save(sd))
	player.say("Welcome back. Day %d." % day)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if not player.dead:
			save_game()
		get_tree().quit()


func quit_to_menu() -> void:
	if not player.dead:
		save_game()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _process(delta: float) -> void:
	if not player.dead:
		survived += delta
		# Walked off the edge of the map: on to the next region
		var pp := player.position
		var szp := world.size_px()
		if not _travelling:
			if pp.x < 6.0:
				travel(Vector2i(-1, 0))
			elif pp.x > szp.x - 6.0:
				travel(Vector2i(1, 0))
			elif pp.y < 6.0:
				travel(Vector2i(0, -1))
			elif pp.y > szp.y - 6.0:
				travel(Vector2i(0, 1))
	world.update_roofs(player.global_position, delta)
	time_of_day += delta / DAY_LENGTH
	if time_of_day >= 1.0:
		time_of_day -= 1.0
	if time_of_day >= 0.25 and time_of_day - delta / DAY_LENGTH < 0.25:
		day += 1
	var light := daylight()
	Game.night = 1.0 - light
	night_tint.color = Color(0.30, 0.36, 0.66).lerp(Color.WHITE, light)
	player.set_night(1.0 - light)

	_reveal_t -= delta
	if _reveal_t <= 0.0:
		_reveal_t = 0.4
		reveal_around(player.global_position)

	if not player.dead:
		_save_t -= delta
		if _save_t <= 0.0:
			_save_t = AUTOSAVE_EVERY
			save_game(true)

	# Trees / props around the camera
	var cam_zoom: float = player.camera.zoom.x if player.camera else 1.5
	world.update_stream(player.global_position, get_viewport().get_visible_rect().size / (2.0 * cam_zoom))

	# Unsearched containers near you glint now and then
	_glint_t -= delta
	if _glint_t <= 0.0:
		_glint_t = 0.15
		for n in get_tree().get_nodes_in_group("loot"):
			var l := n as LootSpot
			if not l.opened and not l.is_bag and l.position.distance_squared_to(player.position) < 1400.0 * 1400.0:
				l.queue_redraw()

	# Creatures far away from you are removed (new ones spawn around you)
	_despawn_t -= delta
	if _despawn_t <= 0.0:
		_despawn_t = 3.0
		_despawn_far()

	_animal_t -= delta
	if _animal_t <= 0.0:
		_animal_t = 10.0
		var n := {"rabbit": 0, "deer": 0, "wolf": 0}
		for a in get_tree().get_nodes_in_group("animals"):
			n[a.species] += 1
		if n["rabbit"] < MAX_RABBITS:
			spawn_animal("rabbit", SPAWN_MIN)
		if n["deer"] < MAX_DEER:
			spawn_animal("deer", SPAWN_MIN)
		if n["wolf"] < MAX_WOLVES - 1:
			spawn_wolf_pack(SPAWN_MIN + 200.0)

	_survivor_t -= delta
	if _survivor_t <= 0.0:
		_survivor_t = 30.0
		if get_tree().get_nodes_in_group("survivors").size() < MAX_SURVIVORS:
			spawn_survivor_group(SPAWN_MIN + 300.0)

	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = ZOMBIE_SPAWN_EVERY
		var cap := int(lerpf(MAX_ZOMBIES_DAY, MAX_ZOMBIES_NIGHT, 1.0 - light))
		if get_tree().get_nodes_in_group("zombies").size() < cap:
			spawn_zombie(SPAWN_MIN)


func daylight() -> float:
	var sun := -cos(time_of_day * TAU) # -1 at midnight, 1 at noon
	return clampf((sun + 0.35) / 0.7, 0.0, 1.0)


func clock_text() -> String:
	var minutes := int(time_of_day * 24.0 * 60.0)
	return "%02d:%02d" % [minutes / 60, minutes % 60]


## A random spot SPAWN-ring away from you that passes `ok`: in a nearby settlement (`town_chance`, bigger
## settlements more likely) or anywhere in the ring. Vector2.INF if nothing was found.
func _ring_point(min_d: float, max_d: float, town_chance: float, ok: Callable) -> Vector2:
	var pp := player.global_position
	var weights := {"city": 5.0, "town": 3.0, "village": 1.8, "hamlet": 1.0}
	var near := []
	var total := 0.0
	for i in world.settlements.size():
		var st: Dictionary = world.settlements[i]
		var d := world.center_of(st["center"]).distance_to(pp)
		if d > min_d - 1500.0 and d < max_d + 1500.0:
			near.append(i)
			total += weights.get(st["type"], 1.0)
	for attempt in 120:
		var c: Vector2i
		if not near.is_empty() and randf() < town_chance:
			var pick := randf() * total
			var r: Rect2i = world.settlements[near[0]]["rect"]
			for i in near:
				pick -= weights.get(world.settlements[i]["type"], 1.0)
				if pick <= 0.0:
					r = world.settlements[i]["rect"]
					break
			c = Vector2i(randi_range(r.position.x, r.end.x - 1), randi_range(r.position.y, r.end.y - 1))
		else:
			c = world.cell_of(pp + Vector2.from_angle(randf() * TAU) * randf_range(min_d, max_d))
		if not world.in_bounds(c):
			continue
		var p := world.center_of(c)
		var d2 := p.distance_to(pp)
		if d2 < min_d or d2 > max_d or not ok.call(c):
			continue
		return p
	return Vector2.INF


## Zombies gather where people used to live: mostly in settlements (more in the bigger ones), some in the wild.
func spawn_zombie(min_dist: float, max_dist := SPAWN_MAX) -> Zombie:
	var p := _ring_point(min_dist, max_dist, 0.8, func(c: Vector2i): return world.is_walkable(c) and not world.is_door(c))
	if p == Vector2.INF:
		return null
	return add_zombie(p, pick_zombie_type(world.settlement_at(world.cell_of(p))))


## Removes zombies, animals and bandits that are far away and not busy with you.
func _despawn_far() -> void:
	var pp := player.global_position
	for n in get_tree().get_nodes_in_group("zombies"):
		var z := n as Zombie
		if z.state != Zombie.State.CHASE and z.global_position.distance_to(pp) > DESPAWN:
			z.remove_from_group("zombies")
			z.queue_free()
	for n in get_tree().get_nodes_in_group("animals"):
		var a := n as Animal
		if a.prey == null and a.global_position.distance_to(pp) > DESPAWN + 400.0:
			a.remove_from_group("animals")
			a.remove_from_group("wolves")
			a.queue_free()
	for n in get_tree().get_nodes_in_group("survivors"):
		var b := n as Survivor
		if b.state != Survivor.State.FIGHT and b.global_position.distance_to(pp) > DESPAWN + 600.0:
			b.remove_from_group("survivors")
			b.queue_free()


func pick_zombie_type(town := -1) -> String:
	var city: bool = town >= 0 and world.settlements[town]["type"] == "city"
	var total := 0.0
	var mix := []
	for row in ZOMBIE_MIX:
		var w: float = row[1]
		if row[0] == "runner":
			w *= 1.0 + Game.night
		elif row[0] == "armed":
			w *= 1.8 if city else (0.4 if town < 0 else 1.0)
		mix.append([row[0], w])
		total += w
	var r := randf() * total
	for row in mix:
		r -= float(row[1])
		if r <= 0.0:
			return row[0]
	return "walker"


func add_zombie(p: Vector2, type := "walker", gun := "", mag := 0) -> Zombie:
	var z := Zombie.new()
	z.type = type
	z.gun = gun
	z.mag = mag
	z.world = world
	z.player = player
	z.position = p
	z.died.connect(_on_zombie_died)
	zombies.add_child(z)
	return z


## Bandits travel in small groups (1-3) and camp in settlements or along the roads.
func spawn_survivor_group(min_dist: float, max_dist := SPAWN_MAX + 400.0) -> Array:
	var out := []
	var center := _ring_point(min_dist, max_dist, 0.6, func(c: Vector2i):
		return world.is_walkable(c) and world.building_at(world.center_of(c)) < 0 \
			and (world.settlement_at(c) >= 0 or world.get_tile(c) == World.ROAD))
	if center == Vector2.INF:
		return out
	for i in randi_range(1, 3):
		var s := Survivor.new()
		s.position = world.random_walkable_near(center, 2)
		s.home = center
		out.append(add_survivor(s))
	return out


func add_survivor(s: Survivor) -> Survivor:
	s.world = world
	s.player = player
	s.died.connect(_on_survivor_died)
	survivors.add_child(s)
	return s


func _on_survivor_died(s: Survivor) -> void:
	if s.last_hit_by == player:
		kills += 1


## Animals live in the wilderness, away from roads and buildings.
func spawn_animal(species: String, min_dist: float, max_dist := SPAWN_MAX + 200.0) -> Animal:
	var p := _ring_point(min_dist, max_dist, 0.0, func(c: Vector2i): return world._is_wild(c))
	if p == Vector2.INF:
		return null
	return add_animal(species, p)


## Wolves roam the wilderness in packs of 2-3.
func spawn_wolf_pack(min_dist: float) -> Array:
	var out := []
	var leader := spawn_animal("wolf", min_dist)
	if leader == null:
		return out
	out.append(leader)
	for i in randi_range(1, 2):
		out.append(add_animal("wolf", world.random_walkable_near(leader.position, 2)))
	for w in out:
		(w as Animal).home = leader.position
	return out


func add_animal(species: String, p: Vector2) -> Animal:
	var a := Animal.new()
	a.species = species
	a.world = world
	a.player = player
	a.position = p
	a.died.connect(_on_animal_died)
	entities.add_child(a)
	return a


## Dead animals leave a carcass to skin.
func _on_animal_died(a: Animal) -> void:
	var c := LootSpot.new()
	c.kind = "carcass"
	c.animal = a.species
	c.flip = randf() < 0.5
	c.contents = [Items.make("meat", Animal.SPECIES[a.species]["meat"])]
	if int(Animal.SPECIES[a.species]["leather"]) > 0:
		c.contents.append(Items.make("leather", Animal.SPECIES[a.species]["leather"]))
	c.position = a.global_position
	entities.call_deferred("add_child", c)


func add_fire(p: Vector2, fuel: float) -> Campfire:
	var f := Campfire.new()
	f.position = p
	f.fuel = fuel
	entities.add_child(f)
	return f


func _on_noise(pos: Vector2, radius: float) -> void:
	for n in get_tree().get_nodes_in_group("animals"):
		if (n as Animal).global_position.distance_to(pos) <= radius * 1.3:
			(n as Animal).scare(pos)
	# Walls muffle sound: through a wall (or a closed door) it only carries half as far.
	for n in get_tree().get_nodes_in_group("zombies"):
		var z := n as Zombie
		var d := z.position.distance_to(pos)
		if d <= radius and (d <= radius * 0.5 or world.has_los(z.position, pos)):
			z.hear(pos)
	for n in get_tree().get_nodes_in_group("survivors"):
		var s := n as Survivor
		if s.position.distance_to(pos) <= radius * 0.8:
			s.hear(pos)


## Only your own kills count.
func _on_zombie_died(z: Zombie) -> void:
	if z.last_hit_by == player:
		kills += 1


func _on_player_died() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	save_game() # kept, but marked dead: it can't be continued


## New game with a new world.
func restart() -> void:
	Game.pending_load = {}
	get_tree().paused = false
	get_tree().reload_current_scene()
