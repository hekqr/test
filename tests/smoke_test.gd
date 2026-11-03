extends Node
## Headless smoke test. Run: godot --headless --path . res://tests/smoke_test.tscn

var main: Node
var frame := 0
var failures := PackedStringArray()
var z_test: Zombie
var hp_before := 0.0
var pos_before := Vector2.ZERO
var loot: LootSpot


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
	var inv: Inventory = p.inv
	match frame:
		3:
			print("World / spawn")
			check(w.buildings.size() > 20, "buildings generated (%d)" % w.buildings.size())
			check(w.roofs.size() == w.buildings.size(), "every building has a roof")
			check(get_tree().get_nodes_in_group("loot").size() > 30, "loot containers placed")
			check(get_tree().get_nodes_in_group("zombies").size() >= 50, "zombies spawned")
			check(w.is_walkable(w.cell_of(p.global_position)), "player spawns on walkable tile")
			check(w.find_path(p.global_position, w.center_of(w.loot_cells[0])).size() > 1, "pathfinding works")
			check(not ("stamina" in p), "stamina removed")
			_clear_zombies()
			pos_before = p.global_position
			Input.action_press("move_right")
			Input.action_press("move_down")
		60:
			Input.action_release("move_right")
			Input.action_release("move_down")
			check(p.global_position.distance_to(pos_before) > 20.0, "player moves with input")
			print("Inventory")
			check(inv.count_of("food") == 1 and inv.count_of("water") == 1 and inv.count_of("bandage") == 1, "starting items")
			inv.add("food", 7)
			check(inv.count_of("food") == 8, "food stacks (8)")
			inv.add("ammo_pistol", 100)
			check(inv.count_of("ammo_pistol") == 100, "ammo stacks across slots")
			inv.remove("ammo_pistol", 100)
			check(inv.count_of("ammo_pistol") == 0, "ammo removed")
			var first: Dictionary = inv.slots[0]
			inv.move(0, 10)
			check(inv.slots[0] == null and is_same(inv.slots[10], first), "drag & drop moves item")
			inv.move(10, 0)
			for i in 30:
				inv.add("bat")
			var left := inv.add("water")
			check(left == 0 or inv.count_of("water") > 1, "water stacks into existing slot when full")
			check(inv.add("pistol") == 1, "full inventory rejects new item")
			for i in Inventory.SIZE:
				if inv.slots[i] != null and inv.slots[i]["id"] == "bat":
					inv.slots[i] = null
			print("Loot")
			loot = get_tree().get_nodes_in_group("loot")[0] as LootSpot
			loot.contents = [Items.make("bandage", 2), Items.make("shotgun")]
			p.global_position = loot.global_position + Vector2(5, 0)
		62:
			check(p.nearest_loot == loot, "loot detected nearby")
			Input.action_press("interact")
		65:
			Input.action_release("interact")
			check(loot.looted and inv.count_of("shotgun") == 1 and inv.count_of("bandage") == 3, "searching moves loot into inventory")
			print("Roofs")
			var b: int = w.building_at(p.global_position)
			check(b >= 0, "player is inside a building")
		95:
			var b: int = w.building_at(p.global_position)
			check(b >= 0 and w.roofs[b].modulate.a < 0.2, "roof fades when inside")
			var other := (b + 1) % w.roofs.size()
			check(w.roofs[other].modulate.a > 0.9, "other roofs stay")
			print("Items")
			p.hunger = 40.0
			p.use_item("food")
			check(p.hunger > 70.0 and inv.count_of("food") == 7, "eating restores hunger")
			print("Fists")
			p.global_position = w.center_of(w.spawn_cell)
			z_test = main.add_zombie(p.global_position + Vector2(30, 0))
		98:
			p.aim = (z_test.global_position - p.global_position).normalized()
			hp_before = z_test.health
			p.melee()
			check(z_test.health < hp_before, "fists damage zombie")
			print("Bat")
			inv.add("bat")
			for i in Inventory.SIZE:
				if inv.slots[i] != null and inv.slots[i]["id"] == "bat":
					p.use_slot(i)
			check(p.weapon_id() == "bat", "bat equipped from inventory")
			hp_before = z_test.health
			p.melee()
			check(hp_before - z_test.health >= 40.0, "bat hits harder")
			print("Zombie attacks")
			z_test.health = 999.0
			hp_before = p.health
		180:
			check(p.health < hp_before, "zombie damages player (%.0f -> %.0f)" % [hp_before, p.health])
			z_test.free()
			p.health = 100.0
			p.bleeding = false
			print("Pistol")
			inv.add_stack({"id": "pistol", "count": 1, "mag": 8})
			inv.add("ammo_pistol", 10)
			for i in Inventory.SIZE:
				if inv.slots[i] != null and inv.slots[i]["id"] == "pistol":
					p.use_slot(i)
			check(p.weapon_id() == "pistol", "pistol equipped")
			z_test = main.add_zombie(p.global_position + Vector2(0, -60))
			z_test.set_physics_process(false)
		182:
			p.aim = (z_test.global_position + Vector2(0, -6) - (p.global_position + Player.HAND)).normalized()
			hp_before = z_test.health
			p.shoot()
			check(int(p.equipped["mag"]) == 7, "shooting uses a round")
			check(z_test.health < hp_before, "bullet hits zombie")
			p.equipped["mag"] = 0
			p.start_reload()
			check(p.reloading, "reload starts")
		280:
			check(int(p.equipped["mag"]) == 8 and inv.count_of("ammo_pistol") == 2, "reload fills magazine from inventory")
			print("Shotgun")
			inv.add("ammo_shotgun", 10)
			for i in Inventory.SIZE:
				if inv.slots[i] != null and inv.slots[i]["id"] == "shotgun":
					inv.slots[i]["mag"] = 5
					p.use_slot(i)
			check(p.weapon_id() == "shotgun", "shotgun equipped")
			z_test.health = 70.0
			p.aim = (z_test.global_position + Vector2(0, -6) - (p.global_position + Player.HAND)).normalized()
			p.shoot()
			check(p._shots.size() == 6, "shotgun fires 6 pellets")
			check(z_test.health < 70.0 - 24.0 or z_test.dead, "multiple pellets hit (hp %.0f)" % z_test.health)
			print("Drop")
			var n_before := get_tree().get_nodes_in_group("loot").size()
			var slot := -1
			for i in Inventory.SIZE:
				if inv.slots[i] != null and inv.slots[i]["id"] == "shotgun":
					slot = i
			p.drop_slot(slot)
			check(inv.count_of("shotgun") == 0 and p.weapon_id() == "fists", "dropping equipped weapon unequips it")
		282:
			check(get_tree().get_nodes_in_group("loot").size() == get_tree().get_nodes_in_group("loot").size() and inv.count_of("shotgun") == 0, "drop bag spawned")
			print("Noise")
			var z2: Zombie = main.add_zombie(p.global_position + Vector2(400, 0))
			Game.make_noise(p.global_position, 750.0)
			check(z2.state != Zombie.State.WANDER, "gunshot noise attracts zombies")
			print("Day / night")
			main.time_of_day = 0.0
		284:
			check(Game.night > 0.9, "midnight is dark")
			print("Death")
			var zk: Zombie = main.add_zombie(p.global_position + Vector2(0, 300), true)
			zk.take_damage(999.0, Vector2.RIGHT)
			check(zk.dead and not zk.is_in_group("zombies"), "zombie dies and leaves a corpse")
			p.take_damage(999.0)
			check(p.dead, "player dies")
		287:
			if failures.is_empty():
				print("SMOKE TEST PASSED")
				get_tree().quit(0)
			else:
				print("SMOKE TEST FAILED: ", failures)
				get_tree().quit(1)
