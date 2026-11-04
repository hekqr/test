extends Node2D
## Builds a run: world, loot, player, zombies, day/night, HUD.

const MAX_ZOMBIES_DAY := 110
const MAX_ZOMBIES_NIGHT := 160
const DAY_LENGTH := 480.0 # seconds for a full day/night cycle
const AUTOSAVE_EVERY := 20.0
const MAX_RABBITS := 22
const MAX_DEER := 11

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
## Map exploration: 1 = you've seen this cell (W x H)
var explored := PackedByteArray()
var _reveal_t := 0.0
const REVEAL_RADIUS := 15


func _ready() -> void:
	randomize()
	get_tree().set_auto_accept_quit(false)
	Game.ui_open = false
	Game.click_used = false
	var save: Dictionary = Game.pending_load
	Game.pending_load = {}
	world_seed = int(save["seed"]) if not save.is_empty() else randi()
	world = World.new()
	add_child(world)
	entities = Node2D.new()
	entities.name = "Entities"
	entities.y_sort_enabled = true
	add_child(entities)
	world.generate(world_seed, entities)
	explored.resize(World.W * World.H)
	explored.fill(0)
	if save.is_empty():
		_spawn_loot()
	else:
		for d in save["loot"]:
			entities.add_child(LootSpot.from_save(d))

	zombies = Node2D.new()
	zombies.name = "Zombies"
	zombies.y_sort_enabled = true
	entities.add_child(zombies)

	player = Player.new()
	player.world = world
	player.position = world.center_of(world.spawn_cell)
	entities.add_child(player)
	player.died.connect(_on_player_died)

	if save.is_empty():
		for i in MAX_ZOMBIES_DAY:
			spawn_zombie(500.0)
	else:
		_apply_save(save)
	for i in MAX_RABBITS:
		spawn_animal("rabbit", 400.0)
	for i in MAX_DEER:
		spawn_animal("deer", 400.0)

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

	Game.noise_made.connect(_on_noise)
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	if save.is_empty():
		save_game() # a new survivor replaces the old save straight away


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


func _spawn_loot() -> void:
	# Furniture, garbage bins and cars (each with its own loot table)
	for c in world.containers:
		var l := LootSpot.new()
		l.kind = c["kind"]
		l.tex_name = c["tex"]
		l.flip = c["flip"]
		l.reach = c["reach"]
		l.position = c["pos"]
		if randf() < float(c.get("empty_chance", 0.0)):
			l.loaded = true # someone got here first: starts empty
		entities.add_child(l)
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
	for n in get_tree().get_nodes_in_group("loot"):
		if not n.is_queued_for_deletion():
			loot.append((n as LootSpot).to_save())
	var zs := []
	for n in get_tree().get_nodes_in_group("zombies"):
		var z := n as Zombie
		zs.append({"pos": [z.position.x, z.position.y], "big": z.big, "health": z.health})
	var p := player
	return {
		"seed": world_seed, "dead": p.dead, "day": day, "time_of_day": time_of_day,
		"survived": survived, "kills": kills,
		"player": {
			"pos": [p.position.x, p.position.y], "health": p.health, "hunger": p.hunger,
			"thirst": p.thirst, "bleeding": p.bleeding, "temp": p.body_temp, "poison": p.poison_t,
			"inv": p.inv.to_save(),
		},
		"loot": loot, "zombies": zs,
		"fires": get_tree().get_nodes_in_group("fires").map(func(f): return f.to_save()),
		"explored": Marshalls.raw_to_base64(explored.compress(FileAccess.COMPRESSION_DEFLATE)),
	}


func save_game() -> void:
	SaveGame.write(to_save())


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
	for fd in s.get("fires", []):
		add_fire(SaveGame.vec(fd["pos"]), fd["fuel"])
	for zd in s["zombies"]:
		var z := add_zombie(SaveGame.vec(zd["pos"]), zd["big"])
		z.health = zd["health"]
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
			save_game()

	_animal_t -= delta
	if _animal_t <= 0.0:
		_animal_t = 15.0
		var n := {"rabbit": 0, "deer": 0}
		for a in get_tree().get_nodes_in_group("animals"):
			n[a.species] += 1
		if n["rabbit"] < MAX_RABBITS:
			spawn_animal("rabbit", 900.0)
		if n["deer"] < MAX_DEER:
			spawn_animal("deer", 900.0)

	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = 3.0
		var cap := int(lerpf(MAX_ZOMBIES_DAY, MAX_ZOMBIES_NIGHT, 1.0 - light))
		if get_tree().get_nodes_in_group("zombies").size() < cap:
			spawn_zombie(900.0)


func daylight() -> float:
	var sun := -cos(time_of_day * TAU) # -1 at midnight, 1 at noon
	return clampf((sun + 0.35) / 0.7, 0.0, 1.0)


func clock_text() -> String:
	var minutes := int(time_of_day * 24.0 * 60.0)
	return "%02d:%02d" % [minutes / 60, minutes % 60]


## Zombies gather where people used to live: mostly in settlements (more in the city), some in the wild.
func spawn_zombie(min_dist: float) -> Zombie:
	var weights := {"city": 5.0, "town": 2.5, "village": 1.2}
	for attempt in 40:
		var c: Vector2i
		if randf() < 0.8 and not world.settlements.is_empty():
			var total := 0.0
			for st in world.settlements:
				total += weights[st["type"]]
			var pick := randf() * total
			var r: Rect2i = world.settlements[0]["rect"]
			for st in world.settlements:
				pick -= weights[st["type"]]
				if pick <= 0.0:
					r = st["rect"]
					break
			c = Vector2i(randi_range(r.position.x, r.end.x - 1), randi_range(r.position.y, r.end.y - 1))
		else:
			c = Vector2i(randi_range(2, World.W - 3), randi_range(2, World.H - 3))
		if not world.is_walkable(c):
			continue
		var p := world.center_of(c)
		if p.distance_to(player.position) < min_dist:
			continue
		return add_zombie(p, randf() < 0.12)
	return null


func add_zombie(p: Vector2, big := false) -> Zombie:
	var z := Zombie.new()
	z.big = big
	z.world = world
	z.player = player
	z.position = p
	z.died.connect(_on_zombie_died)
	zombies.add_child(z)
	return z


## Animals live in the wilderness, away from roads and buildings.
func spawn_animal(species: String, min_dist: float) -> Animal:
	for attempt in 60:
		var c := Vector2i(randi_range(3, World.W - 4), randi_range(3, World.H - 4))
		if not world._is_wild(c):
			continue
		var p := world.center_of(c)
		if p.distance_to(player.position) < min_dist:
			continue
		return add_animal(species, p)
	return null


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
	for n in get_tree().get_nodes_in_group("zombies"):
		var z := n as Zombie
		if z.position.distance_to(pos) <= radius:
			z.hear(pos)


func _on_zombie_died(_z: Zombie) -> void:
	kills += 1


func _on_player_died() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	save_game() # kept, but marked dead: it can't be continued


## New game with a new world.
func restart() -> void:
	Game.pending_load = {}
	get_tree().paused = false
	get_tree().reload_current_scene()
