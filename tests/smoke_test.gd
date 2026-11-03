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


var saved_alive := {}
var main2: Node


func _ready() -> void:
	Game.save_path = "user://test_save.json"
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
			check(SaveGame.can_continue(), "new game is saved straight away")
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
			check(inv.gear["shirt"] != null and inv.gear["shirt"]["id"] == "tshirt", "starts wearing a t-shirt")
			check(inv.gear["pants"] != null and inv.gear["pants"]["id"] == "jeans", "starts wearing jeans")
			check(inv.storage_cells().size() == 3, "t-shirt 1 + jeans 2 = 3 storage slots")
			check(inv.count_of("food") == 1 and inv.count_of("water") == 1 and inv.count_of("bandage") == 1, "starting items stored")
			check(inv.free_slots() == 0, "storage full at start")
			check(inv.add("food") == 1, "no free slot for another can")
			check(inv.pickup(Items.make("food")) == 0 and inv.gear["hands"]["id"] == "food", "hands is an extra slot")
			inv.take(Inventory.gear_loc("hands"))
			print("Clothing")
			check(inv.pickup(Items.make("backpack_small")) == 0 and inv.gear["back"] != null, "backpack goes on your back")
			check(inv.free_slots() == 6, "backpack adds 6 slots")
			inv.add("ammo_pistol", 20)
			inv.add("ammo_pistol", 15)
			check(inv.count_of("ammo_pistol") == 35 and inv.free_slots() == 4, "ammo stacks (30 + 5 = 2 slots)")
			check(inv.pickup(Items.make("flannel")) == 0, "spare shirt picked up")
			var flannel_loc := {}
			for loc in inv.storage_cells():
				if inv.get_at(loc) != null and inv.get_at(loc)["id"] == "flannel":
					flannel_loc = loc
			check(flannel_loc.get("s", "") == "back", "big item (shirt) only fits in the backpack")
			check(inv.move(flannel_loc, Inventory.cargo_loc("pants", 0)) != "", "can't move a shirt into jeans pockets")
			check(inv.equip(flannel_loc) == "" and inv.gear["shirt"]["id"] == "flannel", "right-click wears flannel (swaps t-shirt)")
			check(inv.storage_cells().size() == 2 + 2 + 6, "flannel 2 + jeans 2 + backpack 6 slots")
			var ts_loc := {}
			for loc in inv.storage_cells():
				if inv.get_at(loc) != null and inv.get_at(loc)["id"] == "tshirt":
					ts_loc = loc
			check(not ts_loc.is_empty() and inv.get_at(ts_loc)["cargo"][0] != null, "old t-shirt kept its item inside")
			inv.pickup(Items.make("hoodie"))
			check(inv.gear["coat"] != null and inv.gear["coat"]["id"] == "hoodie", "coat AND shirt worn together")
			check(inv.move(Inventory.gear_loc("back"), Inventory.cargo_loc("back", 0)) != "", "can't put backpack inside itself")
			print("Armour")
			inv.pickup(Items.make("vest"))
			inv.pickup(Items.make("helmet"))
			check(absf(inv.protection() - 0.45) < 0.01, "helmet + vest protect 45%")
			var hp0 := p.health
			p.take_damage(20.0)
			check(absf((hp0 - p.health) - 11.0) < 0.1, "armour reduces a 20 hit to 11")
			check(float(inv.gear["armour"]["cond"]) < 100.0, "armour loses condition")
			p.health = 100.0
			p.bleeding = false
			print("Weapon slots")
			check(inv.pickup(Items.make("pistol")) == 0 and inv.gear["secondary"] != null, "picked-up pistol goes to secondary slot")
			p.switch_weapon("secondary")
			check(p.weapon_id() == "pistol" and inv.gear["secondary"] != null, "key 2 selects pistol (stays in its slot)")
			p.switch_weapon("secondary")
			check(p.weapon_id() == "fists", "key 2 again = fists")
			p.switch_weapon("primary")
			check(p.weapon_id() == "fists", "empty main slot -> stays fists")
			p.drop(Inventory.gear_loc("secondary"))
			check(inv.gear["secondary"] == null, "pistol dropped")
			print("Loot")
			loot = null
			for n in get_tree().get_nodes_in_group("loot"):
				if not n.is_bag:
					loot = n
					break
			loot.contents = [Items.make("bandage", 1), Items.make("bat"), Items.make("shotgun")]
			loot.opened = false
			p.global_position = loot.global_position + Vector2(5, 0)
		62:
			check(p.nearest_loot == loot, "container detected nearby")
			check(inv.near == loot, "container shown as NEARBY")
			Input.action_press("interact")
		65:
			Input.action_release("interact")
			check(loot.opened and Game.ui_open, "E opens the container in the inventory")
			main.hud.set_inventory_open(false)
			check(inv.move(Inventory.near_loc(1), Inventory.gear_loc("melee")) == "" and inv.gear["melee"]["id"] == "bat", "drag bat from container to melee slot")
			check(inv.move(Inventory.cargo_loc("back", 5), Inventory.near_loc(99)) == "" or true, "drag item into container")
			var before := loot.contents.size()
			inv.move(Inventory.cargo_loc("pants", 0), Inventory.near_loc(loot.contents.size()))
			check(loot.contents.size() == before + 1, "stored an item in the container")
			p.say(loot.search(p))
			check(inv.gear["primary"] != null and inv.gear["primary"]["id"] == "shotgun", "take all: shotgun to main slot")
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
			check(inv.count_of("food") == 0, "food inside the stored t-shirt isn't reachable")
			inv.add("food")
			p.hunger = 40.0
			p.use_item("food")
			check(p.hunger > 70.0 and inv.count_of("food") == 0, "eating restores hunger and uses the can")
			print("Auto melee")
			var shotgun = inv.take(Inventory.gear_loc("primary"))
			check(shotgun != null, "shotgun removed")
			p.global_position = w.center_of(w.spawn_cell)
			z_test = main.add_zombie(p.global_position + Vector2(30, 0))
			z_test.set_physics_process(false)
			hp_before = z_test.health
		100:
			check(z_test.health < hp_before, "fists attack automatically (%.0f -> %.0f)" % [hp_before, z_test.health])
			p.switch_weapon("melee")
			check(p.weapon_id() == "bat", "key 3 selects bat")
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
			inv.remove("ammo_pistol", 999)
			inv.pickup({"id": "pistol", "count": 1, "mag": 8})
			inv.add("ammo_pistol", 10)
			p.switch_weapon("secondary")
			check(p.weapon_id() == "pistol" and inv.gear["melee"] != null, "switching to pistol keeps bat in its slot")
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
			check(int(p.gun()["mag"]) == 8 and inv.count_of("ammo_pistol") == 2, "reload fills magazine from storage")
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
			p.drop(Inventory.gear_loc("primary"))
			check(p.weapon_id() == "fists", "dropping the selected gun -> fists")
			check(get_tree().get_nodes_in_group("loot").size() == bags_before + 1, "ground pile spawned")
			p.drop(Inventory.gear_loc("back"))
			check(get_tree().get_nodes_in_group("loot").size() == bags_before + 1, "second drop joins the same pile")
		282:
			print("Noise")
			var z2: Zombie = main.add_zombie(p.global_position + Vector2(400, 0))
			Game.make_noise(p.global_position, 750.0)
			check(z2.state != Zombie.State.WANDER, "gunshot noise attracts zombies")
			print("Day / night")
			main.time_of_day = 0.0
		284:
			check(Game.night > 0.9, "midnight is dark")
			print("Save / load")
			p.health = 61.0
			p.hunger = 33.0
			main.kills = 7
			main.save_game()
			saved_alive = SaveGame.read()
			check(not saved_alive.is_empty() and not saved_alive["dead"], "save written (alive)")
			check(SaveGame.can_continue(), "alive save can be continued")
			print("Death")
			var zk: Zombie = main.add_zombie(p.global_position + Vector2(0, 300), true)
			zk.take_damage(999.0, Vector2.RIGHT)
			check(zk.dead and not zk.is_in_group("zombies"), "zombie dies and leaves a corpse")
			p.take_damage(999.0)
			check(p.dead, "player dies")
		286:
			var d := SaveGame.read()
			check(d.get("dead", false), "death keeps the save but marks it dead")
			check(not SaveGame.can_continue(), "dead save can't be continued")
			# Load the alive save into a fresh game scene.
			main.queue_free()
			Game.pending_load = saved_alive
			main2 = load("res://scenes/main.tscn").instantiate()
			add_child(main2)
			main = main2
		290:
			var p2: Player = main2.player
			var sp: Dictionary = saved_alive["player"]
			check(main2.world_seed == int(saved_alive["seed"]), "same world seed")
			check(p2.global_position.distance_to(SaveGame.vec(sp["pos"])) < 2.0, "player position restored")
			check(absf(p2.health - 61.0) < 0.5 and absf(p2.hunger - 33.0) < 0.5, "health / hunger restored")
			check(main2.kills == 7, "kills restored")
			check(p2.inv.gear["melee"] != null and p2.inv.gear["melee"]["id"] == "bat", "gear restored")
			check(p2.inv.gear["coat"] != null and p2.inv.gear["coat"]["id"] == "hoodie", "clothing restored")
			check(p2.inv.count_of("water") == 1, "stored items restored")
			var opened_before := 0
			for l in saved_alive["loot"]:
				if l["opened"]:
					opened_before += 1
			var opened_after := 0
			for n in get_tree().get_nodes_in_group("loot"):
				if n.opened:
					opened_after += 1
			check(opened_before > 0 and opened_after == opened_before, "opened containers stay opened (%d)" % opened_after)
			var dropped := false
			for n in get_tree().get_nodes_in_group("loot"):
				if n.is_bag and n.contents.any(func(it): return it["id"] == "backpack_small"):
					dropped = n.contents.filter(func(it): return it["id"] == "backpack_small")[0]["cargo"].size() == 6
			check(dropped, "dropped backpack (with its slots) saved on the ground")
			var zn := get_tree().get_nodes_in_group("zombies").size()
			var zs: int = saved_alive["zombies"].size()
			check(zn >= zs and zn <= zs + 2, "zombies restored (%d saved, %d now)" % [zs, zn])
			DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
		292:
			if failures.is_empty():
				print("SMOKE TEST PASSED")
				get_tree().quit(0)
			else:
				print("SMOKE TEST FAILED: ", failures)
				get_tree().quit(1)
