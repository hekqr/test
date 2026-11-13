extends Node
## Dev tool: you inside a house (away from its door, so it stays shut) and a crowd of zombies outside
## that know where you are, for 40 s. None may get in, and none may hurt you through the walls / windows.
## godot --headless --path . res://tests/house_siege.tscn

var main: Node
var f := 0
var house := -1
var spot := Vector2i.ZERO
var hp0 := 0.0
var inside_hits := 0
var t := 0.0



func _ready() -> void:
	Game.save_path = "user://siege_%d.json" % OS.get_process_id()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)


func _open_spot(w: World, r: int) -> Vector2i:
	for y in range(40, World.H - 40, 3):
		for x in range(40, World.W - 40, 3):
			var ok := true
			for dy in range(-r - 3, r + 4):
				for dx in range(-r - 3, r + 4):
					if w.get_tile(Vector2i(x + dx, y + dy)) != World.GROUND:
						ok = false
						break
				if not ok:
					break
			if ok and w.settlement_at(Vector2i(x, y)) < 0:
				return Vector2i(x, y)
	return Vector2i(-1, -1)





func _process(delta: float) -> void:
	f += 1
	var w: World = main.world
	var p: Player = main.player
	if f == 10:
		for z in get_tree().get_nodes_in_group("zombies"):
			z.free()
		for sv in get_tree().get_nodes_in_group("survivors"):
			sv.free()
		main._spawn_t = 1e9
		main._survivor_t = 1e9
		main._animal_t = 1e9
		# A house with a room at least 3 tiles from every door
		house = -1
		for i in w.buildings.size():
			if String(w.building_types[i]).begins_with("house"):
				for fc in w.building_floors[i]:
					var far := true
					for d in w.building_doors[i]:
						if (fc as Vector2i).distance_to(d) < 3.5:
							far = false
					if far and w.is_walkable(fc):
						house = i
						spot = fc
						break
			if house >= 0:
				break
		if house < 0:
			print("HOUSE SIEGE: no house")
			get_tree().quit()
			return
		var r: Rect2i = w.buildings[house]
		p.global_position = w.center_of(spot)
		var types := ["walker", "runner", "brute", "axe", "armed", "walker", "runner", "armed", "crawler"]
		var placed := 0
		for k in 400:
			if placed >= types.size():
				break
			var c := Vector2i(randi_range(r.position.x - 4, r.end.x + 3), randi_range(r.position.y - 4, r.end.y + 3))
			if w.is_walkable(c) and w.building_at(w.center_of(c)) < 0:
				var z: Zombie = main.add_zombie(w.center_of(c), types[placed], "pistol" if types[placed] == "armed" else "", 8)
				placed += 1
		print("HOUSE SIEGE: %s, you at %s, %d zombies outside" % [w.building_types[house], spot, placed])
		hp0 = p.health
	if f <= 10:
		return
	t += delta
	# Keep the player inside, away from the door, alive; zombies know where you are.
	p.global_position = w.center_of(spot)
	p.velocity = Vector2.ZERO
	if p.health < hp0 - 0.5: # (bleeding ticks don't count)
		inside_hits += 1
		if inside_hits <= 12:
			var near := []
			for g in ["zombies", "animals", "survivors"]:
				for n in get_tree().get_nodes_in_group(g):
					var d := (n as Node2D).global_position.distance_to(p.global_position)
					if d < 70.0:
						near.append("%s %s d=%.0f cell %s" % [g, n.get("type") if g == "zombies" else (n.get("species") if g == "animals" else "bandit"), d, w.cell_of((n as Node2D).global_position) - spot])
			print("  hit -%.1f at %.1fs  bleeding %s  near: %s" % [hp0 - p.health, t, p.bleeding, near])
		hp0 = p.health
	p.health = maxf(p.health, 50.0)
	hp0 = p.health
	p.hunger = 100.0
	p.bleeding = false
	p.thirst = 100.0
	for z in get_tree().get_nodes_in_group("zombies"):
		if int(t * 10) % 20 == 0:
			z.hear(p.global_position) # they keep hearing you
	for n in get_tree().get_nodes_in_group("zombies"):
		if w.building_at((n as Node2D).global_position) == house:
			print("  BREACH: a %s zombie got inside at %.1fs" % [n.type, t])
			(n as Node2D).queue_free()
	if t >= 40.0:
		print("HOUSE SIEGE DONE: hit %d times through walls / windows in 40 s" % inside_hits)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
		get_tree().quit()
