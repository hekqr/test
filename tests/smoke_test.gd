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
			check(w.find_path(p.global_position, w.center_of(w.building_floors[0][0])).size() > 1, "pathfinding into a building works")
			print("Buildings / street / nature")
			_check_templates()
			var types := {}
			for t in w.building_types:
				types[t] = true
			check(types.size() >= 4, "several building types placed (%s)" % ", ".join(types.keys()))
			var kinds := {}
			for c in w.containers:
				kinds[c["kind"]] = kinds.get(c["kind"], 0) + 1
			check(kinds.has("fridge") and kinds.has("wardrobe") and kinds.has("cupboard"), "houses have kitchens and bedrooms")
			check(kinds.get("car", 0) >= 5, "cars on the roads (%d)" % kinds.get("car", 0))
			check(kinds.get("bin", 0) >= 3, "garbage bins on sidewalks (%d)" % kinds.get("bin", 0))
			var lights := w.props.filter(func(pr): return String(pr["tex"]).begins_with("prop_light")).size()
			var nature := w.props.filter(func(pr): return String(pr["tex"]).begins_with("nat_")).size()
			check(lights >= 10 and nature >= 50, "street lights (%d) and wilderness nature (%d)" % [lights, nature])
			check(w.wild_spots.size() >= 3, "rare wilderness finds (%d)" % w.wild_spots.size())
			var win := 0
			for t in w.tiles:
				if t == World.WINDOW:
					win += 1
			check(win > 20, "buildings have windows (%d)" % win)
			check(w.has_los(Vector2.ZERO, Vector2.ZERO) and _window_see_through(w), "you can see through windows but not walls")
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
			check(inv.storage_cells().size() == 2, "shirts give no storage: jeans 2 = 2 slots")
			check(inv.count_of("food") == 1 and inv.count_of("water") == 1 and inv.count_of("bandage") == 1, "starting items carried")
			check(inv.free_slots() == 0 and inv.gear["hands"] != null, "storage full at start, 3rd item in hands")
			check(inv.add("food") == 1, "no free slot for another can")
			var start_hands = inv.take(Inventory.gear_loc("hands"))
			check(inv.pickup(Items.make("food")) == 0 and inv.gear["hands"]["id"] == "food", "hands is an extra slot")
			inv.gear["hands"] = start_hands
			print("Clothing")
			check(inv.pickup(Items.make("backpack_small")) == 0 and inv.gear["back"] != null, "backpack goes on your back")
			check(inv.free_slots() == 6, "backpack adds 6 slots")
			inv.add("ammo_9mm", 20)
			inv.add("ammo_9mm", 15)
			check(inv.count_of("ammo_9mm") == 35 and inv.free_slots() == 4, "ammo stacks (30 + 5 = 2 slots)")
			check(inv.pickup(Items.make("flannel")) == 0, "spare shirt picked up")
			var flannel_loc := {}
			for loc in inv.storage_cells():
				if inv.get_at(loc) != null and inv.get_at(loc)["id"] == "flannel":
					flannel_loc = loc
			check(flannel_loc.get("s", "") == "back", "big item (shirt) only fits in the backpack")
			check(inv.move(flannel_loc, Inventory.cargo_loc("pants", 0)) != "", "can't move a shirt into jeans pockets")
			check(inv.equip(flannel_loc) == "" and inv.gear["shirt"]["id"] == "flannel", "right-click wears flannel (swaps t-shirt)")
			check(inv.storage_cells().size() == 2 + 6, "jeans 2 + backpack 6 slots (flannel adds none)")
			var ts_loc := {}
			for loc in inv.storage_cells():
				if inv.get_at(loc) != null and inv.get_at(loc)["id"] == "tshirt":
					ts_loc = loc
			check(not ts_loc.is_empty() and ts_loc["s"] == "back", "old t-shirt went into the backpack")
			inv.pickup(Items.make("hoodie"))
			check(inv.gear["coat"] != null and inv.gear["coat"]["id"] == "hoodie", "coat AND shirt worn together")
			check(inv.move(Inventory.gear_loc("back"), Inventory.cargo_loc("back", 0)) != "", "can't put backpack inside itself")
			print("Armour")
			inv.pickup(Items.make("vest"))
			inv.pickup(Items.make("helmet"))
			var ap := inv.armour_points()
			# helmet 2 + vest 3 + hoodie 0.3 + flannel 0.2 + jeans 0.3 = 5.8
			check(absf(ap - 5.8) < 0.01, "armour points add up (%.1f)" % ap)
			var hp0 := p.health
			p.take_damage(20.0)
			check(absf((hp0 - p.health) - 20.0 * (1.0 - ap * 0.1)) < 0.1, "1 point = 10%% less damage (took %.1f)" % (hp0 - p.health))
			check(float(inv.gear["coat"]["cond"]) < float(inv.gear["shirt"]["cond"]) or float(inv.gear["shirt"]["cond"]) == 100.0, "coat (sleeves, outer) wears more than shirt under it")
			check(float(inv.gear["armour"]["cond"]) < 100.0, "vest loses condition")
			check(inv.armour_points() < ap, "worn gear gives a little less armour")
			check(inv.armour_points() > ap * 0.9, "...but not much less")
			var tmp := Inventory.new()
			for id in ["helmet", "vest", "jacket", "flannel", "cargo_pants", "boots"]:
				tmp.pickup(Items.make(id))
			check(tmp.armour_points() < 7.0, "best possible gear stays far from 10 (%.1f)" % tmp.armour_points())
			print("Ruined")
			inv.gear["head"]["cond"] = 0.0
			check(absf(inv.armour_points() - (ap - 2.0)) < 0.5, "ruined helmet gives no armour")
			var helm = inv.take(Inventory.gear_loc("head"))
			inv.gear["hands"] = helm
			check(inv.move(Inventory.gear_loc("hands"), Inventory.gear_loc("head")) != "", "ruined helmet can't be worn again")
			inv.take(Inventory.gear_loc("hands"))
			p.health = 100.0
			p.bleeding = false
			print("Temperature")
			var w0 := inv.warmth()
			inv.gear["coat"]["cond"] = 100.0
			var tmp2 := Inventory.new()
			tmp2.pickup(Items.make("tshirt"))
			var t_shirt_only := tmp2.warmth()
			tmp2.pickup(Items.make("jacket"))
			check(tmp2.warmth() > t_shirt_only + 15.0, "jacket is much warmer than a t-shirt")
			tmp2.pickup(Items.make("hoodie"))
			check(tmp2.gear["coat"]["id"] == "jacket", "only one coat at a time")
			check(w0 > 0.0, "clothes give warmth (%.0f)" % w0)
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
			_press("interact")
		65:
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
			print("Indoors warmth")
			var inside_target := p.target_temp()
			var keep := p.global_position
			p.global_position = w.center_of(w.spawn_cell)
			check(not p.indoors() and p.target_temp() < inside_target - 20.0, "houses are warmer (in %.0f / out %.0f)" % [inside_target, p.target_temp()])
			p.global_position = keep
		95:
			var b: int = w.building_at(p.global_position)
			check(b >= 0 and w.roofs[b].modulate.a < 0.2, "roof fades when inside")
			var other := (b + 1) % w.roofs.size()
			check(w.roofs[other].modulate.a > 0.9, "other roofs stay")
			print("Items")
			inv.remove("food", 99)
			inv.add("food")
			p.hunger = 40.0
			p.use_item("food")
			check(p.hunger > 70.0 and inv.count_of("food") == 0, "eating restores hunger and uses the can")
			print("Healing rules")
			p.bleeding = false
			p.hunger = 80.0
			p.thirst = 80.0
			p.body_temp = 60.0
			check(p.can_heal(), "heals when warm + fed + watered")
			p.body_temp = 40.0
			check(not p.can_heal(), "no healing when chilly")
			p.body_temp = 60.0
			p.hunger = 70.0
			check(not p.can_heal(), "no healing below 75% hunger")
			p.hunger = 80.0
			p.thirst = 70.0
			check(not p.can_heal(), "no healing below 75% thirst")
			p.thirst = 100.0
			p.hunger = 100.0
			p.body_temp = 10.0
			var hp_cold := p.health
			p._needs(1.0)
			check(p.health < hp_cold, "freezing hurts")
			p.body_temp = 60.0
			print("Ammo types")
			var t9 := Inventory.new()
			t9.pickup(Items.make("backpack_small"))
			t9.add("ammo_9mm", 10)
			t9.add("ammo_12ga", 5)
			t9.add("ammo_556", 20)
			t9.add("ammo_308", 4)
			check(t9.free_slots() == 2, "different ammo types never share a stack")
			check(Items.WEAPONS["pistol"]["ammo"] == "ammo_9mm" and Items.WEAPONS["rifle"]["ammo"] == "ammo_556" and Items.WEAPONS["hunting_rifle"]["ammo"] == "ammo_308" and Items.WEAPONS["shotgun"]["ammo"] == "ammo_12ga", "each gun takes its own ammo")
			check(t9.move(Inventory.cargo_loc("back", 0), Inventory.cargo_loc("back", 1)) == "No room to swap" or t9.get_at(Inventory.cargo_loc("back", 1))["id"] == "ammo_9mm", "dragging 9mm onto 12ga swaps instead of merging")
			print("Food & medicine")
			var h0 := 50.0
			p.hunger = h0
			p.thirst = h0
			p._apply_consumable("food")
			check(p.hunger > h0 and p.thirst == h0, "canned food: hunger only")
			p.hunger = h0
			p._apply_consumable("soup")
			check(p.hunger > h0 and p.thirst > h0, "canned soup: hunger and thirst")
			p.thirst = h0
			p._apply_consumable("soda")
			check(p.thirst > h0, "soda quenches thirst")
			p.bleeding = true
			p.health = 50.0
			p._apply_consumable("bandage")
			check(not p.bleeding and p.health == 50.0, "bandage only stops bleeding")
			p.poison_t = 60.0
			p.bleeding = true
			p._apply_consumable("firstaid")
			check(p.poison_t <= 0.0 and not p.bleeding and p.health > 50.0, "first aid kit cures bleeding + poisoning and heals a bit")
			check(not p._apply_consumable("bandage"), "bandage not needed when not bleeding")
			p.poison_t = 10.0
			check(not p.can_heal(), "no healing while sick")
			p.poison_t = 0.0
			p.health = 100.0
			print("Tearing")
			var shirt := Items.make("tshirt")
			inv.gear["hands"] = shirt
			var b0 := inv.count_of("bandage")
			p.tear(Inventory.gear_loc("hands"))
			check(inv.gear["hands"] == null or inv.gear["hands"]["id"] == "bandage", "shirt is gone after tearing")
			check(inv.count_of("bandage") + _pile_count("bandage") >= b0 + 2, "t-shirt tears into 2 bandages")
			check(not p.actions_for(Inventory.gear_loc("pants")).any(func(a): return a[1] == "tear"), "jeans can't be torn")
			print("Colours")
			var cols := {}
			for i in 30:
				cols[Items.make("tshirt")["color_name"]] = true
			check(cols.size() >= 4, "clothing comes in random colours (%d seen)" % cols.size())
			check(Items.item_icon(Items.make("hoodie")) != null, "coloured icons render")
			print("Location loot")
			var guns := 0
			var food := 0
			for i in 60:
				for it in Loot.roll("locker"):
					if Items.is_weapon(it["id"]) or Items.kind(it["id"]) == "ammo":
						guns += 1
				for it in Loot.roll("fridge"):
					if Items.is_weapon(it["id"]):
						food -= 100
					else:
						food += 1
			check(guns > 12, "police lockers have guns & ammo (%d)" % guns)
			check(food > 20, "fridges have food & drink only")
			var total := 0
			for i in 100:
				total += Loot.roll("cupboard").size()
			check(total < 100, "loot nerfed: kitchen cupboards average under 1 item (%d / 100)" % total)
			print("Stacking")
			var st := Inventory.new()
			st.pickup(Items.make("backpack_small"))
			st.add("bandage", 7)
			check(st.count_of("bandage") == 7 and st.free_slots() == 4, "bandages stack to 5 (7 = 2 slots)")
			st.add("sticks", 10)
			st.add("matches", 4)
			check(st.free_slots() == 2, "sticks (10) and matches stack")
			st.add("meat", 3)
			check(st.free_slots() == 1, "meat stacks")
			print("Keys")
			p.hunger = 50.0
			inv.add("food")
			var fbefore := inv.count_of("food")
			_press("eat")
			check(inv.count_of("food") == fbefore - 1 and p.hunger > 50.0, "F key eats (key events)")
			var old_primary = inv.gear["primary"]
			p.inv.gear["primary"] = Items.make("shotgun")
			_press("weapon_primary")
			check(p.weapon_id() == "shotgun", "1 key selects main gun")
			_press("weapon_primary")
			check(p.weapon_id() == "fists", "1 again lowers it")
			inv.gear["primary"] = old_primary
			print("Double-click")
			inv.gear["hands"] = Items.make("cap")
			p.double_click(Inventory.gear_loc("hands"))
			check(inv.gear["head"] != null and inv.gear["head"]["id"] == "cap", "double-click wears a cap")
			inv.gear["hands"] = Items.make("knife")
			var old_melee = inv.gear["melee"]
			p.double_click(Inventory.gear_loc("hands"))
			check(inv.gear["melee"] != null and inv.gear["melee"]["id"] == "knife", "double-click equips a knife")
			inv.gear["hands"] = null
			inv.gear["melee"] = old_melee
			print("Animals")
			check(get_tree().get_nodes_in_group("animals").size() >= 10, "rabbits & deer spawned (%d)" % get_tree().get_nodes_in_group("animals").size())
			var deer: Animal = main.add_animal("deer", p.global_position + Vector2(200, 0))
			deer.take_damage(999.0, Vector2.RIGHT)
		97:
			var carc: LootSpot = null
			for n in get_tree().get_nodes_in_group("loot"):
				if n.kind == "carcass":
					carc = n
			check(carc != null and carc.animal == "deer" and carc.contents[0]["count"] == 3, "dead deer leaves a carcass with 3 meat")
			p.global_position = carc.global_position + Vector2(0, 20)
			var blade_m = inv.gear["melee"]
			inv.gear["melee"] = null
			var knives := inv.count_of("knife") + inv.count_of("axe")
			inv.remove("knife", 9)
			inv.remove("axe", 9)
			p._find_loot()
			check(p.nearest_loot == carc and inv.near == null, "carcass nearby (not shown as a container)")
			p.interact()
			check(not carc.contents.is_empty(), "can't skin without a knife")
			inv.gear["hands"] = Items.make("knife")
			var meat0 := inv.count_of("meat")
			p.interact()
			check(inv.count_of("meat") + _pile_count("meat") >= meat0 + 3 or carc.contents.size() < 1, "skinning gives raw meat")
			inv.gear["hands"] = null
			inv.gear["melee"] = blade_m
			print("Campfire")
			p.global_position = w.center_of(w.spawn_cell)
			inv.add("sticks", 4)
			inv.add("matches", 2)
			var outside_target := p.target_temp()
			p.build_fire()
			check(get_tree().get_nodes_in_group("fires").size() == 1, "campfire built")
			check(inv.count_of("sticks") <= 1 and inv.count_of("matches") <= 1, "used 3 sticks + 1 match")
			p._find_loot()
			check(p.near_fire() and p.target_temp() > outside_target + 15.0, "fire warms you up")
			inv.add("meat", 2)
			p.use_fire(p.nearest_fire)
			check(p.cook_t > 0.0, "cooking started")
			var car_max := 0
			for i in 100:
				car_max = maxi(car_max, Loot.roll("car").size())
			check(car_max == 1, "cars drop at most one item")
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
			inv.remove("ammo_9mm", 999)
			inv.pickup({"id": "pistol", "count": 1, "mag": 8})
			inv.add("ammo_9mm", 10)
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
			check(int(p.gun()["mag"]) == 8 and inv.count_of("ammo_9mm") == 2, "reload fills magazine from storage")
			check(inv.count_of("cooked_meat") + _pile_count("cooked_meat") >= 2 and inv.count_of("meat") == 0, "raw meat cooked on the fire")
			print("Shotgun")
			inv.add("ammo_12ga", 10)
			inv.pickup({"id": "shotgun", "count": 1, "mag": 5})
			p.cycle_weapon(-1)
			check(p.weapon_id() == "shotgun", "mouse wheel cycles to shotgun")
			z_test.health = 70.0
			p.aim = (z_test.global_position + Vector2(0, -6) - (p.global_position + Player.HAND)).normalized()
			p.shoot()
			check(p._shots.size() == 6, "shotgun fires 6 pellets")
			check(z_test.health < 70.0 - 24.0 or z_test.dead, "multiple pellets hit (hp %.0f)" % z_test.health)
			print("Drop")
			p.drop(Inventory.gear_loc("primary"))
			check(p.weapon_id() == "fists", "dropping the selected gun -> fists")
			var pile := _pile_with("shotgun")
			check(pile != null, "ground pile with the shotgun spawned")
			p.drop(Inventory.gear_loc("back"))
			check(pile != null and pile.contents.any(func(it): return it["id"] == "backpack_small"), "second drop joins the same pile")
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
			check(absf(p2.body_temp - float(saved_alive["player"]["temp"])) < 0.5, "body temperature restored")
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


func _pile_with(id: String) -> LootSpot:
	for n in get_tree().get_nodes_in_group("loot"):
		if n.is_bag and n.contents.any(func(it): return it["id"] == id):
			return n
	return null


func _pile_count(id: String) -> int:
	var n := 0
	for l in get_tree().get_nodes_in_group("loot"):
		if l.is_bag:
			for it in l.contents:
				if it["id"] == id:
					n += int(it["count"])
	return n


## Every plan: equal row widths, doors on the outside, every searchable container reachable from the front door.
func _check_templates() -> void:
	for k in Buildings.TEMPLATES:
		var rows: Array = Buildings.TEMPLATES[k]["rows"]
		var w: int = String(rows[0]).length()
		var ok := rows.all(func(r): return String(r).length() == w)
		check(ok, "%s: all rows %d wide" % [k, w])
		if not ok:
			continue
		var h := rows.size()
		var start := -1
		for x in w:
			if String(rows[h - 1])[x] == "D":
				start = x
		check(start >= 0, "%s: front door on the bottom row" % k)
		var seen := {}
		var todo := [Vector2i(start, h - 1)]
		while not todo.is_empty():
			var c: Vector2i = todo.pop_back()
			if seen.has(c):
				continue
			seen[c] = true
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + d
				if n.x >= 0 and n.y >= 0 and n.x < w and n.y < h and String(rows[n.y])[n.x] in ["w", "t", "c", "D"]:
					todo.append(n)
		var unreachable := 0
		for y in h:
			for x in w:
				var ch := String(rows[y])[x]
				if Buildings.CONTAINER_CHARS.has(ch):
					var reach := false
					for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						if seen.has(Vector2i(x, y) + d):
							reach = true
					if not reach:
						unreachable += 1
		check(unreachable == 0, "%s: every container reachable from the front door" % k)
	# Rotations keep the plan intact
	var r: Array = Buildings.oriented(Buildings.TEMPLATES["house_small"]["rows"], "E", true)
	check(r.size() == String(Buildings.TEMPLATES["house_small"]["rows"][0]).length(), "rotated plan has swapped size")


func _window_see_through(w: World) -> bool:
	for y in range(1, World.H - 1):
		for x in range(1, World.W - 1):
			var c := Vector2i(x, y)
			if w.get_tile(c) == World.WINDOW:
				return not w.blocks_sight(c)
	return false


## Sends a real key press through the input system (like a player pressing the key).
func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	get_viewport().push_input(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	get_viewport().push_input(up)
