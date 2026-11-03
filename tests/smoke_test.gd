extends Node
## Headless smoke test. Run: godot --headless --path . res://tests/smoke_test.tscn

var main: Node
var frame := 0
var failures := PackedStringArray()
var z_test: Zombie
var hp_before := 0.0
var pos_before := Vector2.ZERO


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		print("  FAIL ", what)
		failures.append(what)


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)


func _clear_zombies() -> void:
	for z in main.zombies.get_children():
		z.free()


func _physics_process(_delta: float) -> void:
	frame += 1
	var p: Player = main.player
	var w: World = main.world
	match frame:
		3:
			print("World / spawn")
			check(w.buildings.size() > 20, "buildings generated (%d)" % w.buildings.size())
			check(w.loot_cells.size() > 30, "loot spots generated (%d)" % w.loot_cells.size())
			check(main.zombies.get_child_count() >= 50, "zombies spawned (%d)" % main.zombies.get_child_count())
			check(w.is_walkable(w.cell_of(p.global_position)), "player spawns on walkable tile")
			var far := w.find_path(p.global_position, w.center_of(w.loot_cells[0]))
			check(far.size() > 1, "pathfinding to a building works")
			_clear_zombies()
			pos_before = p.global_position
			Input.action_press("move_right")
			Input.action_press("move_down")
		60:
			Input.action_release("move_right")
			Input.action_release("move_down")
			check(p.global_position.distance_to(pos_before) > 20.0, "player moves with input")
			print("Loot")
			var l := w.get_children().filter(func(n): return n is LootSpot)[0] as LootSpot
			p.global_position = l.global_position + Vector2(5, 0)
		62:
			check(p.nearest_loot != null, "loot detected nearby")
			Input.action_press("interact")
		65:
			Input.action_release("interact")
			var any_looted := false
			for n in get_tree().get_nodes_in_group("loot"):
				if n.looted:
					any_looted = true
			check(any_looted, "loot spot searched")
			print("Items")
			p.inventory["food"] = 1
			p.hunger = 40.0
			p.use_item("food")
			check(p.hunger > 70.0 and p.inventory["food"] == 0, "eating restores hunger")
			print("Melee")
			p.global_position = w.center_of(w.spawn_cell)
			z_test = main.add_zombie(p.global_position + Vector2(30, 0))
		66:
			p.aim = (z_test.global_position - p.global_position).normalized()
			hp_before = z_test.health
			p.melee()
			check(z_test.health < hp_before, "knife damages zombie")
			print("Zombie attacks")
			hp_before = p.health
		150:
			check(p.health < hp_before, "zombie damages player (%.0f -> %.0f)" % [hp_before, p.health])
			z_test.free()
			print("Pistol")
			p.health = 100.0
			p.bleeding = false
			p.has_pistol = true
			p.weapon = 1
			p.mag = 8
			p.inventory["ammo"] = 10
			z_test = main.add_zombie(p.global_position + Vector2(0, -60))
			z_test.set_physics_process(false)
		152:
			p.aim = (z_test.global_position - p.global_position).normalized()
			hp_before = z_test.health
			p.shoot()
			check(p.mag == 7, "shooting uses ammo")
			check(z_test.health < hp_before, "bullet hits zombie")
			p.mag = 0
			p.start_reload()
			check(p.reloading, "reload starts")
		250:
			check(p.mag == 8 and p.inventory["ammo"] == 2, "reload fills magazine (mag %d, ammo %d)" % [p.mag, p.inventory["ammo"]])
			print("Noise")
			var z2: Zombie = main.add_zombie(p.global_position + Vector2(400, 0))
			Game.make_noise(p.global_position, 750.0)
			check(z2.state != Zombie.State.WANDER, "gunshot noise attracts zombies")
			print("Day / night")
			main.time_of_day = 0.0
		252:
			check(Game.night > 0.9, "midnight is dark")
			print("Death")
			p.take_damage(999.0)
			check(p.dead, "player dies")
		255:
			if failures.is_empty():
				print("SMOKE TEST PASSED")
				get_tree().quit(0)
			else:
				print("SMOKE TEST FAILED: ", failures)
				get_tree().quit(1)
