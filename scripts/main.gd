extends Node2D
## Builds a run: world, loot, player, zombies, day/night, HUD.

const MAX_ZOMBIES_DAY := 60
const MAX_ZOMBIES_NIGHT := 95
const DAY_LENGTH := 480.0 # seconds for a full day/night cycle
const AUTOSAVE_EVERY := 20.0

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


func _spawn_loot() -> void:
	for c in world.loot_cells:
		var l := LootSpot.new()
		l.position = world.center_of(c)
		entities.add_child(l)
	# Loose items lying on floors.
	for b in world.buildings:
		if randf() < 0.6:
			var c := Vector2i(randi_range(b.position.x + 1, b.end.x - 2), randi_range(b.position.y + 1, b.end.y - 2))
			if world.get_tile(c) == World.FLOOR:
				var g := LootSpot.new()
				g.is_bag = true
				g.position = world.center_of(c) + Vector2(randf_range(-8, 8), randf_range(-8, 8))
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
			"thirst": p.thirst, "bleeding": p.bleeding,
			"inv": p.inv.to_save(),
		},
		"loot": loot, "zombies": zs,
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
	if ps.has("inv"):
		player.inv.load_save(ps["inv"])
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

	if not player.dead:
		_save_t -= delta
		if _save_t <= 0.0:
			_save_t = AUTOSAVE_EVERY
			save_game()

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


func spawn_zombie(min_dist: float) -> Zombie:
	for attempt in 40:
		var c := Vector2i(randi_range(2, World.W - 3), randi_range(2, World.H - 3))
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


func _on_noise(pos: Vector2, radius: float) -> void:
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
