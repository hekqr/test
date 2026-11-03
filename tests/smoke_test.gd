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
			check(inv.count_of("food") == 1 and inv.count_of("water") == 1 and inv.count_of("bandage") == 1, "starting items in pockets")
			check(inv.hands == null and inv.space_used() == 3, "hands empty, 3 space used")
			inv.add("food", 3)
			check(inv.pockets.size() == 6, "food does NOT stack (separate items)")
			inv.add("ammo_pistol", 20)
			inv.add("ammo_pistol", 15)
			check(inv.count_of("ammo_pistol") == 35 and inv.space_used() == 8, "ammo stacks automatically (30 + 5 = 2 space)")
			check(inv.add("shotgun") == 1, "shotgun (size 6) doesn't fit in 4 free space")
			check(inv.add("water") == 0 and inv.add("water") == 0, "small items still fit")
			check(inv.space_free() == 2, "2 space left")
			inv.remove("ammo_pistol", 35)
			inv.remove("food", 3)
			inv.remove("water", 2)
			check(inv.space_used() == 3, "items removed")
			print("Weapon slots")
			check(inv.pickup(Items.make("pistol")) == 0 and inv.weapons["secondary"] != null and inv.space_used() == 3, "picked-up pistol goes to secondary slot (no pocket space)")
			inv.pickup(Items.make("pistol"))
			check(inv.space_used() == 6, "second pistol goes to pockets")
			inv.remove("pistol", 1)
			p.switch_weapon("secondary")
			check(inv.hands != null and inv.hands["id"] == "pistol" and inv.weapons["secondary"] == null, "key 2 takes pistol into hands")
			p.switch_weapon("secondary")
			check(inv.hands == null and inv.weapons["secondary"] != null, "key 2 again puts it back (fists)")
			p.switch_weapon("primary")
			check(inv.hands == null, "empty primary slot -> stays fists")
			p.switch_weapon("secondary")
			p.drop(true)
			check(inv.weapons["secondary"] == null and inv.hands == null, "pistol dropped")
			print("Loot")
			loot = get_tree().get_nodes_in_group("loot")[0] as LootSpot
			loot.contents = [Items.make("bandage", 1), Items.make("bat"), Items.make("shotgun")]
			p.global_position = loot.global_position + Vector2(5, 0)
		62:
			check(p.nearest_loot == loot, "loot detected nearby")
			Input.action_press("interact")
		65:
			Input.action_release("interact")
			check(inv.count_of("bandage") == 2, "search puts loot in pockets")
			check(inv.weapons["melee"] != null and inv.weapons["primary"] != null, "searched weapons go to their slots")
			check(p.nearest_loot == null or p.nearest_loot != loot, "looted container no longer offers action")
			check(loot.looted, "container emptied")
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
			check(p.hunger > 70.0 and inv.count_of("food") == 0, "eating restores hunger and uses the can")
			print("Auto melee")
			p.drop_slot("primary")
			check(inv.weapons["primary"] == null, "dropped shotgun from slot")
			p.global_position = w.center_of(w.spawn_cell)
			z_test = main.add_zombie(p.global_position + Vector2(30, 0))
			z_test.set_physics_process(false)
			hp_before = z_test.health
		100:
			check(z_test.health < hp_before, "fists attack automatically (%.0f -> %.0f)" % [hp_before, z_test.health])
			p.switch_weapon("melee")
			check(p.weapon_id() == "bat", "key 3 takes bat into hands")
			z_test.health = 200.0
			hp_before = z_test.health
		140:
			check(hp_before - z_test.health >= 42.0, "bat attacks automatically and hits hard")
			z_test.set_physics_process(true)
			print("Zombie attacks")
			z_test.health = 999.0
			hp_before = p.health
		180:
			check(p.health < hp_before, "zombie damages player (%.0f -> %.0f)" % [hp_before, p.health])
			z_test.free()
			p.health = 100.0
			p.bleeding = false
			print("Pistol")
			inv.pickup({"id": "pistol", "count": 1, "mag": 8})
			inv.add("ammo_pistol", 10)
			p.switch_weapon("secondary")
			check(p.weapon_id() == "pistol" and inv.weapons["melee"] != null, "switching to pistol puts bat back in its slot")
			z_test = main.add_zombie(p.global_position + Vector2(0, -60))
			z_test.set_physics_process(false)
		182:
			p.aim = (z_test.global_position + Vector2(0, -6) - (p.global_position + Player.HAND)).normalized()
			hp_before = z_test.health
			p.shoot()
			check(int(p.gun()["mag"]) == 7, "shooting uses a round")
			check(z_test.health < hp_before, "bullet hits zombie")
			p.gun()["mag"] = 0
			p.start_reload()
			check(p.reloading, "reload starts")
		280:
			check(int(p.gun()["mag"]) == 8 and inv.count_of("ammo_pistol") == 2, "reload fills magazine from pockets")
			print("Shotgun")
			inv.add("ammo_shotgun", 10)
			inv.pickup({"id": "shotgun", "count": 1, "mag": 5})
			p.cycle_weapon(-1)
			check(p.weapon_id() == "shotgun", "mouse wheel cycles to shotgun")
			z_test.health = 70.0
			p.aim = (z_test.global_position + Vector2(0, -6) - (p.global_position + Player.HAND)).normalized()
			p.shoot()
			check(p._shots.size() == 6, "shotgun fires 6 pellets")
			check(z_test.health < 70.0 - 24.0 or z_test.dead, "multiple pellets hit (hp %.0f)" % z_test.health)
			print("Drop")
			var bags_before := get_tree().get_nodes_in_group("loot").size()
			p.drop(true)
			check(inv.hands == null and p.weapon_id() == "fists", "dropping hands item -> fists")
			check(get_tree().get_nodes_in_group("loot").size() == bags_before + 1, "drop bag spawned")
		282:
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
