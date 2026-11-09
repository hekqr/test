extends Node
## Headless smoke test. Run: godot --headless --path . res://tests/smoke_test.tscn

var main: Node
var frame := 0
var failures := PackedStringArray()
var z_test: Zombie
var hp_before := 0.0
var pos_before := Vector2.ZERO
var loot: LootSpot
var wolf: Animal
var home_name := ""
var marker_pos := Vector2.ZERO
var east_road_y := 0
var wall_cell := Vector2i(-1, -1)


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		print("  FAIL ", what)
		failures.append(what)


var saved_alive := {}
var main2: Node


func _ready() -> void:
	Game.save_path = "user://test_save_%d.json" % OS.get_process_id() # own file: runs can go in parallel
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
			var zn0 := get_tree().get_nodes_in_group("zombies").size()
			check(zn0 >= 5 and zn0 <= main.MAX_ZOMBIES_NIGHT, "zombies spawned around you (%d)" % zn0)
			var zfar := get_tree().get_nodes_in_group("zombies").all(func(z): return z.global_position.distance_to(p.global_position) >= 650.0)
			check(zfar, "zombies spawn out of sight")
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
			check(kinds.has("fridge") and kinds.has("wardrobe") and kinds.has("medicine") and kinds.has("trash"), "houses: fridge, wardrobe, medicine cabinet, trash can")
			check(not kinds.has("cupboard") and not kinds.has("desk") and not kinds.has("box") and not kinds.has("washer"), "kitchen counters, desks, boxes and washers can't be searched")
			check(Loot.CONTAINERS["fridge"]["rolls"].x >= 1 and Loot.CONTAINERS["wardrobe"]["rolls"].x >= 1, "fridges and wardrobes give more")
			for k in ["house_small", "house_large"]:
				var rows: Array = Buildings.TEMPLATES[k]["rows"]
				check(String(rows[0]).length() <= 11 and rows.size() <= 8, "%s is small (%dx%d)" % [k, String(rows[0]).length(), rows.size()])
			print("Clusters")
			var per := {}
			for i in w.buildings.size():
				per[w.building_town[i]] = per.get(w.building_town[i], 0) + 1
			check(not per.has(-1), "no buildings out on the roads between clusters")
			var sizes_ok := true
			var by_type := {}
			for i in w.settlements.size():
				var t: String = w.settlements[i]["type"]
				var lim: Array = {"hamlet": [2, 7], "village": [5, 12], "town": [8, 13], "city": [12, 16], "military": [5, 7]}[t]
				if per.get(i, 0) < int(lim[0]) or per.get(i, 0) > int(lim[1]):
					sizes_ok = false
				by_type[t] = by_type.get(t, 0) + 1
			check(sizes_ok, "settlement sizes: hamlets 4-7, villages ~9-12, towns ~11-13, city 16, camps 6-7 (%s)" % str(per))
			check(by_type.get("hamlet", 0) >= 5 and by_type.get("village", 0) >= 3 and by_type.get("town", 0) >= 1 and by_type.get("city", 0) == 1, "hamlets, villages, towns and a city (%s)" % str(by_type))
			var multi := 0
			for st in w.settlements:
				if st["streets"].size() > 1:
					multi += 1
			check(multi >= 4, "bigger settlements have several streets (%d)" % multi)
			var huts := 0
			for t in w.building_types:
				if String(t).begins_with("hut"):
					huts += 1
			check(huts * 2 > w.building_types.size(), "most buildings are tiny one-room huts (%d / %d)" % [huts, w.building_types.size()])
			check(World.W == 512 and World.H == 512, "map is 4x bigger (512 x 512)")
			print("Performance")
			check(w._chunk_live.size() > 0 and w._chunk_live.size() < w._chunk_specs.size() / 4, "trees / props only exist near you (%d of %d chunks)" % [w._chunk_live.size(), w._chunk_specs.size()])
			var bi := 0
			for i in w.buildings.size():
				if w.buildings[i].get_center().distance_to(Vector2(w.spawn_cell)) < w.buildings[bi].get_center().distance_to(Vector2(w.spawn_cell)):
					bi = i
			var zz: Zombie = main.add_zombie(w.center_of(w.spawn_cell))
			var inside: Vector2i = w.building_floors[bi][0]
			var t0 := Time.get_ticks_usec()
			zz._set_path(w.center_of(inside))
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			check(ms < 8.0, "a zombie after you inside a house heads for the door - no map-wide search (%.1f ms)" % ms)
			zz.free()
			var piles := get_tree().get_nodes_in_group("loot").filter(func(l): return l.is_bag)
			check(not piles.is_empty() and piles[0]._outline != null, "items on the ground have a white outline")
			print("Map / zoom")
			main.hud.set_map_open(true)
			check(main.hud._map_tex != null and main.hud._fog_tex != null, "paper map ready")
			var z0: float = main.hud._map_zoom
			var wheel := InputEventMouseButton.new()
			wheel.button_index = MOUSE_BUTTON_WHEEL_UP
			wheel.pressed = true
			wheel.position = main.hud._map_rect(main.hud.get_viewport_rect().size).get_center()
			get_viewport().push_input(wheel, true)
			check(main.hud._map_zoom > z0, "scroll zooms the map (%.2f -> %.2f)" % [z0, main.hud._map_zoom])
			main.hud.set_map_open(false)
			var cz: float = p.camera.zoom.x
			var wheel2 := InputEventMouseButton.new()
			wheel2.button_index = MOUSE_BUTTON_WHEEL_DOWN
			wheel2.pressed = true
			get_viewport().push_input(wheel2, true)
			check(p.camera.zoom.x < cz, "scroll zooms the camera out (%.2f -> %.2f)" % [cz, p.camera.zoom.x])
			p.camera.zoom = Vector2(1.5, 1.5)
			var min_gap := 9999
			for i in w.settlements.size():
				for j in range(i + 1, w.settlements.size()):
					var a: Rect2i = w.settlements[i]["rect"]
					var b: Rect2i = w.settlements[j]["rect"]
					var gx := maxi(b.position.x - a.end.x, a.position.x - b.end.x)
					var gy := maxi(b.position.y - a.end.y, a.position.y - b.end.y)
					min_gap = mini(min_gap, maxi(gx, gy))
			check(min_gap >= World.CLUSTER_GAP, "clusters are far apart (closest gap %d tiles)" % min_gap)
			print("Speed / hitbox")
			check(Player.WALK_SPEED <= 90.0 and Player.SPRINT_SPEED <= 125.0, "everyone moves much slower (walk %d, sprint %d)" % [Player.WALK_SPEED, Player.SPRINT_SPEED])
			var feet: CollisionShape2D = null
			for ch in p.get_children():
				if ch is CollisionShape2D:
					feet = ch
			var cap := feet.shape as CapsuleShape2D
			check(cap != null and absf(feet.position.y + cap.radius - 2.0) < 0.5, "the player's hitbox sits at the feet (bottom at +2)")
			check(kinds.get("car", 0) >= 5, "cars on the roads (%d)" % kinds.get("car", 0))
			check(kinds.get("bin", 0) >= 3, "garbage bins on sidewalks (%d)" % kinds.get("bin", 0))
			var lights := w.props.filter(func(pr): return String(pr["tex"]).begins_with("prop_light")).size()
			var nature := w.props.filter(func(pr): return String(pr["tex"]).begins_with("nat_")).size()
			check(lights >= 10 and nature >= 50, "street lights (%d) and wilderness nature (%d)" % [lights, nature])
			check(w.wild_spots.size() >= 3, "rare wilderness finds (%d)" % w.wild_spots.size())
			var water_n := 0
			for t in w.tiles:
				if t == World.WATER:
					water_n += 1
			check(water_n > 150, "lakes / river generated (%d water tiles)" % water_n)
			check(w.taps.size() >= 5 and get_tree().get_nodes_in_group("taps").size() == w.taps.size(), "bathroom taps in houses (%d)" % w.taps.size())
			var packs := get_tree().get_nodes_in_group("wolves")
			check(packs.size() >= 2 and packs.all(func(a): return a.global_position.distance_to(p.global_position) > 700.0), "a wolf pack roams the wild, away from you (%d)" % packs.size())
			var win := 0
			for t in w.tiles:
				if t == World.WINDOW:
					win += 1
			check(win > 20, "buildings have windows (%d)" % win)
			check(w.has_los(Vector2.ZERO, Vector2.ZERO) and not _window_see_through(w), "walls and windows block zombies' sight")
			_door_tests(w)
			print("Settlements / map")
			var kinds2 := {}
			var names := {}
			for st in w.settlements:
				kinds2[st["type"]] = kinds2.get(st["type"], 0) + 1
				names[st["name"]] = true
			check(w.settlements.size() >= 5 and kinds2.has("city") and kinds2.has("village"), "city, towns and villages placed (%s)" % str(kinds2))
			check(names.size() == w.settlements.size(), "every settlement has its own name")
			var region_names_ok := true
			for x in range(-4, 5):
				for y in range(-4, 5):
					var nm := World.region_name(main.world_seed, Vector2i(x, y))
					for o in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(2, 0), Vector2i(0, 2)]:
						if World.region_name(main.world_seed, Vector2i(x, y) + o) == nm:
							region_names_ok = false
			check(region_names_ok, "regions next to each other never share a name")
			var unreachable := 0
			for st in w.settlements:
				if st["center"] != w.spawn_cell and w.find_path(w.center_of(w.spawn_cell), w.center_of(st["center"])).size() < 2:
					unreachable += 1
			check(unreachable == 0, "every settlement reachable from the start (roads connect them)")
			check(_unsearchable(w) == 0, "every container in the region can be reached and searched (nothing blocks a door)")
			var in_towns := 0
			for i in w.buildings.size():
				if w.building_town[i] >= 0:
					in_towns += 1
			check(in_towns >= w.buildings.size() * 0.8, "buildings are in settlements (%d / %d)" % [in_towns, w.buildings.size()])
			check(w.facades.size() == w.buildings.size() and w.roofs.size() == w.buildings.size(), "every building has a front wall and a roof (3/4 view)")
			var faces := 0
			for y in World.H:
				for x in World.W:
					if w.is_face(Vector2i(x, y)):
						faces += 1
			check(faces > 50, "interior walls show their faces (%d)" % faces)
			var house_empty := 0
			var house_total := 0
			for n in get_tree().get_nodes_in_group("loot"):
				var l := n as LootSpot
				if not l.is_bag and l.kind in ["fridge", "cupboard", "wardrobe", "medicine", "washer"]:
					house_total += 1
					if l.contents.is_empty():
						house_empty += 1
			check(house_total > 0 and float(house_empty) / house_total > 0.4, "plenty of house furniture is empty (%d / %d)" % [house_empty, house_total])
			main.reveal_around(p.global_position)
			check(main.explored[w.idx(w.cell_of(p.global_position))] == 1, "map reveals where you are")
			check(main.explored[w.idx(Vector2i(1, 1))] == 1 and main.explored[w.idx(Vector2i(World.W - 2, World.H - 2))] == 1, "your home region's map starts filled in")
			check(not ("stamina" in p), "stamina removed")
			print("Bandits (spawn)")
			var bandits := get_tree().get_nodes_in_group("survivors")
			check(bandits.size() >= 1 and bandits.size() <= main.MAX_SURVIVORS, "a group of bandits spawned (%d)" % bandits.size())
			var dressed := bandits.all(func(b): return b.gear["shirt"] != null and b.gear["pants"] != null)
			var armed := bandits.all(func(b): return b.weapon_id() != "fists" or b.gear["melee"] == null)
			check(dressed and armed, "bandits wear clothes and carry weapons")
			var far := bandits.all(func(b): return b.global_position.distance_to(p.global_position) > 600.0)
			check(far, "bandits don't spawn on top of you")
			for b in bandits:
				b.set_physics_process(false) # keep them out of the other tests
			for wf in get_tree().get_nodes_in_group("wolves"):
				wf.set_physics_process(false)
			main._animal_t = 9999.0
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
			check(inv.count_of("food") == 0 and inv.count_of("water") == 0 and inv.count_of("bandage") == 0 and inv.gear["hands"] == null, "you start with nothing but your clothes")
			inv.add("food")
			inv.add("water")
			inv.pickup(Items.make("bandage")) # (the rest of the test expects a few things in your pockets)
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
				if not n.is_bag and Loot.search_time(n.kind) > 0.0:
					loot = n
					break
			loot.contents = [Items.make("bandage", 1), Items.make("bat"), Items.make("shotgun")]
			loot.opened = false
			p.global_position = loot.global_position + Vector2(5, 0)
			p._loot_t = 0.0 # look around now (it's only done every 0.1 s)
		62:
			check(p.nearest_loot == loot, "container detected nearby")
			_press("interact")
		65:
			check(p.busy_t > 0.0 and p.busy_label.begins_with("Searching") and absf(p.busy_total - 1.0) < 0.01, "searching a %s takes 1 second" % loot.kind)
			p.finish_busy()
			check(loot.opened and loot.contents.is_empty() and not Game.ui_open, "the container is searched")
			var spilled: LootSpot = null
			for n in get_tree().get_nodes_in_group("loot"):
				if n.is_bag and n.global_position.distance_to(loot.global_position) < 40.0 and n.contents.any(func(it): return it["id"] == "shotgun"):
					spilled = n
			check(spilled != null and ["bandage", "bat", "shotgun"].all(func(id): return spilled.contents.any(func(it): return it["id"] == id)), "what you find drops on the floor")
			p._find_loot()
			check(inv.near == spilled, "the pile shows in the inventory's nearby list")
			check(p.nearest_loot != loot, "a searched container isn't offered again")
			check(["trash", "bin", "car", "medicine"].all(func(k): return Loot.search_time(k) == 1.0) and ["fridge", "wardrobe", "shelf", "vending"].all(func(k): return Loot.search_time(k) == 0.0),
				"bins, car trunks and medicine boxes take 1 s; fridges, wardrobes, shop shelves and vending machines are instant")
			inv.add("rags", 2)
			var bandages := inv.count_of("bandage")
			p.craft_timed("bandage")
			check(p.busy_t <= 0.0 and inv.count_of("bandage") == bandages + 1, "crafting is instant")
			var quick: LootSpot = null
			for n in get_tree().get_nodes_in_group("loot"):
				if not n.is_bag and n.kind == "fridge" and n != loot:
					quick = n
					break
			if quick:
				var qpos := p.global_position
				quick.contents = [Items.make("soda")]
				quick.opened = false
				p.global_position = quick.global_position + Vector2(5, 0)
				p._find_loot()
				p.interact()
				check(p.busy_t <= 0.0 and quick.opened and quick.contents.is_empty(), "a fridge is searched instantly")
				var pile2: LootSpot = _pile_with("soda")
				p._find_loot()
				if pile2 and p.nearest_loot == pile2:
					p.interact()
					check(p.busy_t <= 0.0 and inv.count_of("soda") >= 1, "picking things up is instant")
					inv.remove("soda", inv.count_of("soda"))
				p.global_position = qpos
				p._find_loot()
			var bat_i := -1
			for i in spilled.contents.size():
				if spilled.contents[i]["id"] == "bat":
					bat_i = i
			check(inv.move(Inventory.near_loc(bat_i), Inventory.gear_loc("melee")) == "" and inv.gear["melee"]["id"] == "bat", "drag bat from the pile to the melee slot")
			var before := spilled.contents.size()
			inv.move(Inventory.cargo_loc("pants", 0), Inventory.near_loc(spilled.contents.size()))
			check(spilled.contents.size() == before + 1, "drop an item onto the pile")
			p.say(spilled.search(p))
			check(inv.gear["primary"] != null and inv.gear["primary"]["id"] == "shotgun", "take all: shotgun to main slot")
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
			var r0 := inv.count_of("rags")
			p.tear(Inventory.gear_loc("hands"))
			check(inv.gear["hands"] == null or inv.gear["hands"]["id"] == "rags", "shirt is gone after tearing")
			check(inv.count_of("rags") + _pile_count("rags") >= r0 + 3, "t-shirt tears into 3 rags")
			check(not p.actions_for(Inventory.gear_loc("pants")).any(func(a): return a[1] == "tear"), "jeans can't be torn")
			print("Crafting")
			var cinv: Inventory = p.inv
			var keep_gear := cinv.gear.duplicate(true)
			var keep_active := cinv.active
			cinv.gear["back"] = Items.make("backpack_large")
			cinv.gear["melee"] = null
			cinv.gear["hands"] = null
			cinv.add("rags", 6)
			cinv.add("rags", 6)
			var b0 := cinv.count_of("bandage")
			check(p.craft("bandage") and cinv.count_of("bandage") == b0 + 1, "2 rags -> bandage")
			check(p.craft("rope") and cinv.count_of("rope") >= 1, "3 rags -> rope")
			check(p.craft("rope"), "second rope")
			check(not p.craft("sack_backpack"), "sack backpack needs a sack")
			cinv.add("sack")
			check(p.craft("sack_backpack") and (cinv.count_of("sack_backpack") + _pile_count("sack_backpack")) >= 1, "sack + rope -> sack backpack")
			cinv.add("sticks", 3)
			cinv.remove("knife", 9)
			cinv.remove("axe", 9)
			check(not p.craft("spear"), "spear needs a knife or axe as a tool")
			cinv.add("knife")
			check(p.craft("spear") and cinv.count_of("knife") == 1, "spear crafted, knife kept")
			check(cinv.count_of("spear") + _pile_count("spear") >= 1 or (cinv.gear["melee"] != null and cinv.gear["melee"]["id"] == "spear"), "spear in inventory")
			check(Items.WEAPONS["spear"]["range"] > Items.WEAPONS["bat"]["range"], "spear reaches further than a bat")
			cinv.gear = keep_gear
			cinv.active = keep_active
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
			check(guns > 8, "police lockers have guns & ammo (%d)" % guns)
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
			check(not InputMap.has_action("eat") and not InputMap.has_action("drink") and not InputMap.has_action("bandage"), "no eat / drink / bandage hotkeys (done from the inventory)")
			var food_loc := {}
			for l in inv.storage_cells() + [Inventory.gear_loc("hands")]:
				if inv.get_at(l) != null and inv.get_at(l)["id"] == "food":
					food_loc = l
			main.hud.set_inventory_open(true)
			var cell: Rect2 = main.hud.cargo_cell(food_loc["s"], food_loc["i"]) if food_loc["t"] == "cargo" else main.hud.slot_rect(food_loc["s"])
			_click(cell.get_center())
			var menu: Dictionary = main.hud._menu
			check(not menu.is_empty() and menu["items"][0][0] == "Eat", "clicking an item shows what you can do with it (%s)" % str(menu.get("items", [])))
			if not main.hud._menu.is_empty():
				_click(main.hud._menu_rect().position + Vector2(20, 4 + Hud.MENU_ROW * 0.5))
			check(p.busy_t > 0.0 and absf(p.busy_total - 3.0) < 0.01, "eating takes 3 seconds")
			p.finish_busy()
			check(inv.count_of("food") == fbefore - 1 and p.hunger > 50.0, "pick Eat from the menu")
			main.hud.set_inventory_open(false)
			var old_primary = inv.gear["primary"]
			p.inv.gear["primary"] = Items.make("shotgun")
			_press("weapon_primary")
			check(p.weapon_id() == "shotgun", "1 key selects main gun")
			_press("weapon_primary")
			check(p.weapon_id() == "fists", "1 again lowers it")
			p.hunger = 20.0
			p._hunger_msg_t = 0.0
			p._need_messages(0.1)
			check(p.message == "I'm hungry", "says \"I'm hungry\" below 25%")
			p.thirst = 20.0
			p._need_messages(0.1)
			check(p.message == "I'm thirsty", "says \"I'm thirsty\" below 25%")
			p.hunger = 100.0
			p.thirst = 100.0
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
			p.cook_t = 0.5 # finish before later tests move the player away from the fire
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
			check(hp_before - z_test.health >= 33.0, "bat attacks automatically and hits hard (%.0f)" % (hp_before - z_test.health))
			z_test.set_physics_process(true)
			z_test.global_position = p.global_position + Vector2(24, 0) # zombies are slow now: start it in reach
			z_test._knock = Vector2.ZERO
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
			p.global_position = _open_spot(w) # clear field: no car / tree / wall in the line of fire
			z_test = main.add_zombie(p.global_position + Vector2(0, -60))
			z_test.set_physics_process(false)
		182:
			print("Auto-aim")
			p._moving = false
			p._update_aim(0.016)
			check(p.aim_target == z_test, "gun aims at the nearest zombie by itself")
			var to_z := (z_test.global_position + Vector2(0, -8) - (p.global_position + Player.HAND)).normalized()
			check(p.aim.dot(to_z) > 0.99, "aim points at the target")
			p.aim_spread = Items.WEAPONS["pistol"]["spread_max"]
			for i in 30:
				p._update_aim(0.016)
			var half := p.aim_spread
			for i in 40:
				p._update_aim(0.016)
			check(p.aim_spread < half and absf(p.aim_spread - Items.WEAPONS["pistol"]["spread_min"]) < 0.01, "aim settles while standing still (%.2f -> %.2f)" % [half, p.aim_spread])
			p._moving = true
			p._sprinting = false
			for i in 10:
				p._update_aim(0.016)
			var walk_spread := p.aim_spread
			p._sprinting = true
			for i in 20:
				p._update_aim(0.016)
			check(walk_spread > 0.15 and p.aim_spread > walk_spread, "walking opens the aim, sprinting more (%.2f / %.2f)" % [walk_spread, p.aim_spread])
			p._moving = false
			p._sprinting = false
			check(_settle_time("pistol") < _settle_time("rifle") and _settle_time("rifle") < _settle_time("shotgun") and _settle_time("shotgun") < _settle_time("hunting_rifle"), "pistol settles fastest, hunting rifle slowest")
			check(Items.damage_text("shotgun") == "24 - 144 damage (1 - 6 pellets)", "shotgun lists min (1 pellet) and max damage")
			check(Items.damage_text("pistol") == "45 damage" and Items.damage_text("bat") == "34 damage", "weapons list their damage")
			p.aim_spread = 0.0
			hp_before = z_test.health
			p.shoot()
			check(p.aim_spread > 0.1, "shooting kicks the aim open (recoil)")
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
			p._update_aim(0.016)
			p.aim_spread = Items.WEAPONS["shotgun"]["spread_min"]
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
			var keep := Survivor.new()
			keep.position = p.global_position + Vector2(0, 500)
			main.add_survivor(keep)
			keep.set_physics_process(false)
			main.save_game()
			saved_alive = SaveGame.read()
			check(not saved_alive.is_empty() and not saved_alive["dead"], "save written (alive)")
			check(SaveGame.can_continue(), "alive save can be continued")
			print("Death")
			var zk: Zombie = main.add_zombie(p.global_position + Vector2(0, 300), "brute")
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
				if l.get("opened", false):
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
			check(zn >= zs and zn <= zs + 2 + main.CAMP_GUARDS, "zombies restored (%d saved, %d now)" % [zs, zn])
			var typed: bool = saved_alive["zombies"].all(func(zd): return Zombie.TYPES.has(String(zd.get("type", ""))))
			check(typed, "zombie types saved")
			var sn := get_tree().get_nodes_in_group("survivors").size()
			var ss: int = saved_alive["survivors"].size()
			check(ss > 0 and sn >= ss, "bandits restored (%d saved, %d now)" % [ss, sn])
			DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
		292:
			_wear_and_repair_tests()
			print("Zombie types")
			main._spawn_t = 9999.0
			main._survivor_t = 9999.0
			_clear_zombies()
			for b in get_tree().get_nodes_in_group("survivors"):
				b.free()
			var p2: Player = main.player
			p2.global_position = _open_spot(main.world, 8)
			p2.health = 100.0
			p2.holster()
			var hp := {}
			for t in Zombie.TYPES:
				var z: Zombie = main.add_zombie(p2.global_position + Vector2(0, 900), t)
				hp[t] = z.health
				if t == "runner":
					check(z.chase_speed >= 114.0 * 0.9 - 0.01 and z.chase_speed <= 114.0 * 1.1 + 0.01, "runners run 114 (+-10%%): about as fast as you sprint (%.0f)" % z.chase_speed)
			var in_range := func(v: float, base: float): return v >= base * 0.9 - 0.01 and v <= base * 1.1 + 0.01
			check(in_range.call(hp["walker"], 100.0) and in_range.call(hp["runner"], 80.0) and in_range.call(hp["brute"], 300.0) and in_range.call(hp["axe"], 100.0) and in_range.call(hp["armed"], 100.0),
				"zombie health: walker 100, runner 80, brute 300, axe 100, armed 100 (+-10%%) (%s)" % str(hp))
			var wt: Dictionary = Zombie.TYPES["walker"]
			check(float(Zombie.TYPES["brute"]["dmg"][0]) == float(wt["dmg"][0]) * 1.5 and float(Zombie.TYPES["brute"]["dmg"][1]) == float(wt["dmg"][1]) * 1.5 and float(Zombie.TYPES["brute"]["chase"]) < float(wt["chase"]), "brutes hit 50% harder and are a bit slower")
			check(float(Zombie.TYPES["runner"]["dmg"][1]) < float(wt["dmg"][1]), "runners hit a bit softer")
			var hps := {}
			for i in 12:
				var zz: Zombie = main.add_zombie(p2.global_position + Vector2(0, 900), "walker")
				hps[snappedf(zz.health, 0.1)] = true
			check(hps.size() > 6, "every zombie's stats vary a little")
			var za: Zombie = main.add_zombie(p2.global_position + Vector2(0, 900), "armed")
			var before_a := za.health
			za.take_damage(10.0, Vector2.RIGHT, p2)
			check(absf(before_a - za.health - 7.0) < 0.01, "armed zombies wear armour (10 damage -> 7)")
			check(za.health < za.max_health, "hurt zombies show a health bar")
			check(int(Items.WEAPONS["pistol"]["noise"]) <= 400 and int(Items.WEAPONS["hunting_rifle"]["noise"]) <= 550, "gunshots carry about half as far")
			var seen := {}
			for i in 3000:
				seen[main.pick_zombie_type(0)] = true
			check(seen.size() == Zombie.TYPES.size(), "every zombie type can spawn")
			_clear_zombies()
			z_test = main.add_zombie(p2.global_position + Vector2(200, 0), "axe")
			z_test._throw_cd = 0.0
			hp_before = p2.health
		390:
			var p2: Player = main.player
			check(not z_test.has_axe, "axe zombie throws its axe")
			check(z_test._axe_waiting(), "the axe lands on the ground")
			print("     player hp %.0f -> %.0f" % [hp_before, p2.health])
			var spot: LootSpot = z_test.axe_spot
			if spot:
				z_test.global_position = spot.global_position
				z_test._pick_up_axe()
			check(z_test.has_axe and (spot == null or not spot.contents.any(func(it): return it["id"] == "axe")), "it walks over and picks the axe back up")
			z_test.free()
			_clear_zombies()
			z_test = main.add_zombie(p2.global_position + Vector2(170, 0), "armed", "pistol", 6)
			p2.health = 100.0
			hp_before = p2.health
		560:
			var p2: Player = main.player
			check(z_test.mag < 6, "armed zombie shoots at you (%d rounds left, hp %.0f)" % [z_test.mag, p2.health])
			var k: int = main.kills
			z_test.take_damage(999.0, Vector2.RIGHT, p2)
		562:
			var p2: Player = main.player
			check(_pile_with("pistol") != null, "armed zombie drops its gun")
			check(main.kills >= 1, "your kills count")
			_clear_zombies()
			print("Bandits")
			var b := Survivor.new()
			b.gear = {}
			for slot in Inventory.GEAR:
				b.gear[slot] = null
			b.gear["shirt"] = Items.make("tshirt")
			b.gear["pants"] = Items.make("jeans")
			var g := Items.make("pistol")
			g["mag"] = 8
			b.gear["secondary"] = g
			b.items = [Items.make("ammo_9mm", 16), Items.make("water")]
			b.position = p2.global_position + Vector2(-180, 0)
			main.add_survivor(b)
			p2.health = 100.0
			hp_before = p2.health
		740:
			var p2: Player = main.player
			var b: Survivor = get_tree().get_nodes_in_group("survivors")[0]
			check(b.state == Survivor.State.FIGHT and b.foe == p2, "bandit attacks you on sight")
			check(int(b.gear["secondary"]["mag"]) < 8 or b._ammo_count("ammo_9mm") < 16, "bandit fires at you (hp %.0f -> %.0f)" % [hp_before, p2.health])
			p2.inv.gear["secondary"] = {"id": "pistol", "count": 1, "mag": 8, "cond": 100.0}
			p2.switch_weapon("secondary")
			p2._update_aim(0.016)
			check(p2.aim_target == b, "your gun auto-aims at bandits too")
			var k: int = main.kills
			var hb := b.health
			b.take_damage(20.0, Vector2.RIGHT, p2)
			check(b.health < hb, "bandits can be hurt")
			b.take_damage(999.0, Vector2.RIGHT, p2)
			check(b.dead and main.kills == k + 1, "bandit killed (counts as a kill)")
		742:
			var p2: Player = main.player
			var has_all := func(l): return l.is_bag and ["pistol", "tshirt", "jeans", "ammo_9mm", "water"].all(func(id): return l.contents.any(func(it): return it["id"] == id))
			check(get_tree().get_nodes_in_group("loot").any(has_all), "dead bandit drops everything: gun, clothes, ammo, supplies")
			print("Zombies vs bandits")
			var b2 := Survivor.new()
			b2.position = p2.global_position + Vector2(0, 0)
			p2.global_position = main.world.center_of(main.world.spawn_cell)
			main.add_survivor(b2)
			var zb: Zombie = main.add_zombie(b2.position + Vector2(90, 0), "walker")
			b2.player = null
			zb.player = null
			zb._think()
			b2._think()
			check(zb.foe == b2 and zb.state == Zombie.State.CHASE, "zombies go after bandits")
			check(b2.foe == zb and b2.state == Survivor.State.FIGHT, "bandits fight zombies")
		744:
			_clear_zombies()
			for b in get_tree().get_nodes_in_group("survivors"):
				b.free()
			for a in get_tree().get_nodes_in_group("animals"):
				a.free()
			main._animal_t = 9999.0
			print("Wolves")
			var p2: Player = main.player
			p2.global_position = _open_spot(main.world, 5)
			p2.health = 100.0
			p2.holster()
			p2.inv.gear["primary"] = {"id": "rifle", "count": 1, "mag": 0, "cond": 100.0}
			p2.switch_weapon("primary") # a gun: no automatic melee, so the wolf gets to bite
			wolf = main.add_animal("wolf", p2.global_position + Vector2(90, 0))
			hp_before = p2.health
		900:
			var p2: Player = main.player
			check(wolf.prey == p2, "wolf hunts you on sight")
			check(p2.health < hp_before, "wolf bites (hp %.0f -> %.0f)" % [hp_before, p2.health])
			wolf.take_damage(999.0, Vector2.RIGHT, p2)
		902:
			var p2: Player = main.player
			var carcass: LootSpot = null
			for n in get_tree().get_nodes_in_group("loot"):
				if n.kind == "carcass" and n.animal == "wolf":
					carcass = n
			check(carcass != null and carcass.contents.any(func(it): return it["id"] == "meat" and int(it["count"]) == 2) and carcass.contents.any(func(it): return it["id"] == "leather"),
				"dead wolf: 2 meat + 1 leather")
			check(int(Animal.SPECIES["deer"]["leather"]) >= 1, "deer give leather too")
			var ws: Dictionary = Animal.SPECIES["wolf"]
			check(float(ws["run"]) == 126.0 and float(ws["run"]) > float(Zombie.TYPES["runner"]["chase"]) and float(ws["run"]) > Player.SPRINT_SPEED, "wolves run 126: faster than runners and than you")
			check(float(ws["health"]) == 40.0 and float(ws["bite"][1]) > float(Zombie.TYPES["walker"]["dmg"][1]), "wolves: 40 hp, bite a bit harder than walkers")
			_water_tests()
			_base_tests()
			_utility_tests()
			print("Regions")
			main.hud.set_map_open(false)
			var pr: Player = main.player
			pr.health = 100.0
			home_name = main.region_name
			var marker := LootSpot.new()
			marker.is_bag = true
			marker.contents = [Items.make("map")]
			marker.position = pr.global_position + Vector2(20, 0)
			main.entities.add_child(marker)
			marker_pos = marker.position
			pr.inv.gear["hands"] = Items.make("rope")
			check(main.world.edge_exit("E").x == World.W - 1 and main.world.get_tile(main.world.edge_exit("E")) == World.ROAD, "a road leaves the region at its east edge")
			east_road_y = main.world.edge_exit("E").y
			main.travel(Vector2i(1, 0))
		1100:
			var p2: Player = main.player
			check(main.region == Vector2i(1, 0) and main.region_name != home_name, "walked east into the next region (%s)" % main.region_name)
			check(p2.global_position.x < 4 * World.T and p2.global_position.x > World.T, "you arrive at its west edge")
			check(main.world.edge_exit("W").y == east_road_y and main.world.get_tile(main.world.edge_exit("W")) == World.ROAD, "the road carries on across the edge")
			check(p2.inv.gear["hands"] != null and p2.inv.gear["hands"]["id"] == "rope", "you keep your things")
			check(main.explored[main.world.idx(Vector2i(World.W - 2, World.H - 2))] == 0, "a new region's map is blank until you explore it")
			check(main.world.settlements.size() >= 5, "the new region has its own settlements (%d)" % main.world.settlements.size())
			main.travel(Vector2i(-1, 0))
		1300:
			check(main.region == Vector2i.ZERO and main.region_name == home_name, "walked back home")
			var found := false
			for n in get_tree().get_nodes_in_group("loot"):
				if n.is_bag and n.position.distance_to(marker_pos) < 2.0 and n.contents.any(func(it): return it["id"] == "map"):
					found = true
			check(found, "what you left in a region is still there when you come back")
			check(main.structure_at(wall_cell) != null and main.world.get_tile(wall_cell) == World.BUILT, "your walls are still standing when you come back")
			check(main.player.global_position.x > (World.W - 5) * World.T, "you come back in at the east edge")
			main.save_game()
			var d := SaveGame.read()
			check(d.has("regions") and d["regions"].has("1,0") and int(d["region"][0]) == 0 and int(d["region"][1]) == 0, "regions are saved")
			DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
		1302:
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


## Seconds a gun needs to settle from its widest aim to its tightest.
func _settle_time(id: String) -> float:
	var w: Dictionary = Items.WEAPONS[id]
	return float(w["aim_time"])


## Centre of a patch of open ground (nothing that blocks bullets), (2r+1) tiles wide
## (or the biggest smaller patch there is).
func _open_spot(w: World, r := 3) -> Vector2:
	for rr in range(r, 2, -1):
		var c := _open_spot_r(w, rr)
		if c != Vector2.INF:
			return c
	return w.center_of(w.spawn_cell)


func _open_spot_r(w: World, r: int) -> Vector2:
	for y in range(r + 2, World.H - r - 2):
		for x in range(r + 2, World.W - r - 2):
			var ok := true
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if w.get_tile(Vector2i(x + dx, y + dy)) != World.GROUND:
						ok = false
						break
				if not ok:
					break
			if ok:
				return w.center_of(Vector2i(x, y))
	return Vector2.INF


## Melee nerf, weapons wearing out and breaking, jams, repair kits, improvised armour.
func _wear_and_repair_tests() -> void:
	var p: Player = main.player
	var inv := p.inv
	print("Melee nerf")
	check(int(Items.WEAPONS["knife"]["damage"]) == 22 and int(Items.WEAPONS["axe"]["damage"]) == 48 and int(Items.WEAPONS["fists"]["damage"]) == 14, "melee weapons deal 20% less")
	print("Weapon wear / repair")
	_clear_zombies()
	inv.gear["melee"] = Items.make("knife")
	p.switch_weapon("melee")
	if inv.active != "melee":
		p.switch_weapon("melee")
	var z: Zombie = main.add_zombie(p.global_position + Vector2(20, 0))
	z.set_physics_process(false)
	z.health = 999.0
	p.melee(Vector2.RIGHT)
	check(float(inv.gear["melee"]["cond"]) < 100.0, "melee hits wear the weapon down (%.1f%%)" % float(inv.gear["melee"]["cond"]))
	inv.gear["melee"]["cond"] = 0.5
	p.melee(Vector2.RIGHT)
	check(Items.is_ruined(inv.gear["melee"]) and p.weapon_id() == "fists", "a worn-out knife breaks -> fists")
	p.holster()
	p.switch_weapon("melee")
	check(inv.active != "melee", "broken weapons can't be selected")
	z.free()
	var g := {"id": "pistol", "count": 1, "mag": 5, "cond": 10.0}
	inv.gear["secondary"] = g
	p.switch_weapon("secondary")
	var jams := 0
	for i in 80:
		g["cond"] = 10.0
		g["mag"] = 5
		p.shoot()
		if int(g["mag"]) == 5:
			jams += 1
	check(jams > 0 and jams < 40, "badly worn guns jam sometimes (%d / 80)" % jams)
	g["cond"] = 100.0
	p.shoot()
	check(float(g["cond"]) < 100.0, "shooting wears the gun")
	# Repairs
	var hood := Items.make("hoodie")
	hood["cond"] = 30.0
	inv.gear["coat"] = hood
	var acts: Array = p.actions_for(Inventory.gear_loc("coat"))
	check(acts.any(func(a): return a[1] == "repair" and String(a[0]).contains("needs")), "repair needs a sewing kit")
	check(not p.repair(Inventory.gear_loc("coat")), "can't repair without a kit")
	inv.gear["hands"] = Items.make("sewing_kit")
	acts = p.actions_for(Inventory.gear_loc("coat"))
	check(acts.any(func(a): return a[0] == "Repair (sewing kit)"), "right-click: Repair (sewing kit)")
	check(p.repair(Inventory.gear_loc("coat")) and absf(float(hood["cond"]) - 70.0) < 0.1 and int(inv.gear["hands"]["uses"]) == 4, "sewing kit: +40% condition, one use")
	g["cond"] = 50.0
	check(not p.repair(Inventory.gear_loc("secondary")), "a sewing kit can't fix guns")
	inv.gear["hands"] = Items.make("toolbox")
	inv.gear["hands"]["uses"] = 1
	check(p.repair(Inventory.gear_loc("secondary")) and absf(float(g["cond"]) - 90.0) < 0.1, "toolbox repairs guns")
	check(inv.gear["hands"] == null, "used-up toolbox is gone")
	inv.gear["hands"] = Items.make("toolbox")
	inv.gear["melee"]["cond"] = 0.0
	check(not p.repair(Inventory.gear_loc("melee")), "ruined things are beyond repair")
	check(Items.repair_kind("helmet") == "tool" and Items.repair_kind("jeans") == "sew" and Items.repair_kind("bat") == "tool", "helmets & weapons need a toolbox, clothes a sewing kit")
	inv.gear["hands"] = Items.make("rags", 2)
	p.quick_use(Inventory.gear_loc("hands"))
	check(inv.gear["hands"] != null, "double-clicking materials never drops them")
	inv.gear["hands"] = null
	print("Improvised armour")
	inv.gear["armour"] = null
	inv.gear["back"] = Items.make("backpack_large")
	inv.add("scrap_metal", 3)
	inv.add("rope", 2)
	var before := inv.armour_points()
	check(p.craft("scrap_armour"), "craft improvised armour (3 scrap metal + 2 rope)")
	check(inv.gear["armour"] != null and inv.gear["armour"]["id"] == "scrap_armour" and inv.armour_points() > before + 2.0, "improvised armour worn: +2.2 armour")
	var found := {}
	for i in 400:
		for it in Loot.roll("crate") + Loot.roll("wardrobe") + Loot.roll("car"):
			found[it["id"]] = true
	check(found.has("toolbox") and found.has("sewing_kit") and found.has("scrap_metal"), "toolboxes, sewing kits and scrap metal can be found")
	var used := Loot.roll("crate")
	for i in 200:
		used += Loot.roll("crate")
	check(used.any(func(it): return it.has("cond") and float(it["cond"]) < 100.0), "found weapons / clothes are worn")


## Leather crafting, water gourd, lakes / rivers and taps.
func _water_tests() -> void:
	var p: Player = main.player
	var w: World = main.world
	var inv := p.inv
	print("Leather / gourd")
	inv.gear["hands"] = null
	inv.gear["back"] = Items.make("backpack_large")
	inv.add("leather", 3)
	var sacks := inv.count_of("sack")
	check(p.craft("leather_sack") and inv.count_of("sack") == sacks + 1, "2 leather -> sack")
	check(p.craft("gourd") and inv.count_of("gourd") == 1 and inv.count_of("leather") == 0, "1 leather -> water gourd")
	var g: Dictionary = inv.all_of("gourd")[0]
	check(int(g["water"]) == 0, "a new gourd is empty")
	print("Water")
	# Stand on a river / lake bank
	var bank := Vector2i(-1, -1)
	for y in range(2, World.H - 2):
		for x in range(2, World.W - 2):
			var c := Vector2i(x, y)
			if bank.x < 0 and w.get_tile(c) == World.WATER and w.is_walkable(c + Vector2i(0, 1)) and _nothing_near(w.center_of(c + Vector2i(0, 1)), 80.0):
				bank = c + Vector2i(0, 1)
	check(bank.x >= 0, "found a lake / river bank")
	var wc := bank - Vector2i(0, 1)
	check(not w.is_walkable(wc) and w.astar.is_point_solid(wc), "you can't walk on water")
	check(not w.blocks_sight(wc), "you can see (and shoot) across water")
	p.global_position = w.center_of(bank)
	p._find_loot()
	check(p.near_lake, "standing at the water's edge")
	check(p.interact_choice() == "water" and p.action_label() == "Drink / fill gourd", "E: Drink / fill gourd")
	p.thirst = 30.0
	p.interact()
	check(p.busy_t > 0.0, "drinking from the lake takes a moment")
	p.finish_busy()
	check(p.thirst >= 90.0 and int(g["water"]) == 4, "drink your fill and fill the gourd (4/4)")
	p.thirst = 40.0
	var loc := {}
	for l in [Inventory.gear_loc("hands")] + inv.storage_cells():
		if inv.get_at(l) != null and inv.get_at(l)["id"] == "gourd":
			loc = l
	check(p.actions_for(loc).any(func(a): return a[1] == "drink_gourd"), "right-click gourd: Drink")
	check(p.drink_gourd(loc) and int(g["water"]) == 3 and absf(p.thirst - 80.0) < 0.01, "a gourd drink = a bottle of water (+40)")
	var tap := WaterSource.new()
	tap.water = 2
	tap.position = p.global_position + Vector2(20, 0)
	main.entities.add_child(tap)
	p.thirst = 0.0
	p.use_water(tap)
	check(tap.water == 0 and absf(p.thirst - 80.0) < 0.01, "taps only hold a little water")
	p.use_water(tap)
	check(p.message.contains("dry"), "a dry tap gives nothing")
	main.save_game()
	var d := SaveGame.read()
	check(d.has("taps") and d["taps"].size() == get_tree().get_nodes_in_group("taps").size(), "tap water saved")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))


## A real left click (press + release) at a screen position.
## A click at `pos` in the inventory's layout (it's centred on screens bigger than 1280 x 720).
func _click(pos: Vector2) -> void:
	pos += main.hud.inv_ofs()
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		get_viewport().push_input(ev, true)


## No loot pile, container, fire or tap within `r` px.
func _nothing_near(pos: Vector2, r: float) -> bool:
	for g in ["loot", "fires", "taps"]:
		for n in get_tree().get_nodes_in_group(g):
			if (n as Node2D).global_position.distance_to(pos) < r:
				return false
	return true


## Doors open for people, stay shut for zombies; closed doors block zombie paths and sight.
func _door_tests(w: World) -> void:
	print("Doors")
	var doors := get_tree().get_nodes_in_group("doors")
	check(doors.size() >= w.buildings.size(), "every building has doors (%d)" % doors.size())
	# A house's front door, with the room behind it
	var door: Door = null
	var inside := Vector2i.ZERO
	var outside := Vector2i.ZERO
	for d in doors:
		var dd := d as Door
		var b := w.building_id[w.idx(dd.cell)]
		if dd.front != null and w.building_types[b].begins_with("house") and w.is_walkable(dd.cell + Vector2i(0, -1)) and w.is_walkable(dd.cell + Vector2i(0, 1)):
			door = dd
			inside = dd.cell + Vector2i(0, -1)
			outside = dd.cell + Vector2i(0, 1)
			break
	check(door != null and not door.open, "doors start closed")
	if door == null:
		return
	check(w.astar_z.is_point_solid(door.cell) and not w.astar.is_point_solid(door.cell), "closed doors block zombies' paths, not people's")
	check(not w.has_los(w.center_of(outside), w.center_of(inside)), "a closed door blocks sight")
	var zpath := w.find_path(w.center_of(outside + Vector2i(0, 2)), w.center_of(inside), true)
	check(not zpath.has(w.center_of(door.cell)), "zombies can't path through a closed door")
	var hpath := w.find_path(w.center_of(outside + Vector2i(0, 2)), w.center_of(inside))
	check(hpath.has(w.center_of(door.cell)), "people walk through doors")
	var p: Player = main.player
	var back := p.global_position
	p.global_position = w.center_of(outside)
	door._t = 0.0
	door._physics_process(0.016)
	check(door.open and not w.astar_z.is_point_solid(door.cell) and w.has_los(w.center_of(outside), w.center_of(inside)), "a door opens when you walk up to it")
	p.global_position = back
	door._t = 0.0
	door._physics_process(0.016)
	check(not door.open, "and closes behind you")
	var z: Zombie = main.add_zombie(w.center_of(door.cell))
	p.global_position = w.center_of(outside)
	door._t = 0.0
	door._physics_process(0.016)
	p.global_position = back
	door._t = 0.0
	door._physics_process(0.016)
	check(door.open, "a door won't close on a zombie standing in it")
	z.free()
	door._t = 0.0
	door._physics_process(0.016)
	check(not door.open, "it closes once the doorway is clear")


## Keys, outlines, ammo in magazines, weather, fishing, base building, sleeping, crops, military camps.
func _base_tests() -> void:
	var p: Player = main.player
	var w: World = main.world
	var inv := p.inv
	p.cancel_busy()
	print("Keys / looks / ammo")
	var keys := func(action: String) -> Array:
		return InputMap.action_get_events(action).map(func(e): return e.keycode)
	check(KEY_E in keys.call("inventory") and KEY_Q in keys.call("interact"), "E = inventory, Q = action")
	main.hud.set_inventory_open(false)
	_press("inventory")
	var opened: bool = main.hud.inventory_open
	_press("inventory")
	check(opened and not main.hud.inventory_open, "E opens the inventory and E closes it again")
	main.hud.set_inventory_open(true)
	_press("interact")
	check(not main.hud.inventory_open, "Q closes the inventory (after opening a chest)")
	check(KEY_Q in keys.call("interact") and main.hud.has_method("_unhandled_input") and FileAccess.get_file_as_string("res://scripts/hud.gd").contains('get_tree().paused and not p.dead and (event.is_action_pressed("interact")'), "Q in the pause menu quits to the menu")
	var cont: LootSpot = null
	for n in get_tree().get_nodes_in_group("loot"):
		if not n.is_bag and n.kind != "carcass" and n.kind != "chest" and not n.opened:
			cont = n
			break
	check(cont != null and cont._outline != null and cont._outline.visible, "unsearched containers have a white outline")
	var pile := get_tree().get_nodes_in_group("loot").filter(func(l): return l.is_bag)
	check(pile.is_empty() or pile[0]._sprite.rotation == 0.0, "items on the ground lie straight")
	var mags_ok := true
	var big_ok := true
	for i in 200:
		for table in ["locker", "military", "car", "crate", "wild"]:
			var total := {}
			for it in Loot.roll(table):
				if Items.kind(it["id"]) == "ammo":
					total[it["id"]] = total.get(it["id"], 0) + int(it["count"])
					if int(it["count"]) > Items.max_stack(it["id"]):
						big_ok = false
			for id in total:
				if total[id] < Items.mag_size(id) or total[id] % Items.mag_size(id) != 0:
					mags_ok = false
	check(mags_ok, "ammo always comes in whole magazines (at least one)")
	check(big_ok, "big ammo finds are split into proper stacks")
	var hp0 := p.health
	p.hit_flash = 0.0
	p.take_damage(1.0)
	check(p.hit_flash == 1.0, "getting hit flashes the screen red")
	p._timers(1.0)
	check(p.hit_flash == 0.0, "the red flash fades out quickly")
	p.health = hp0
	p.bleeding = false
	var paths := {}
	for i in SaveGame.SLOTS:
		paths[SaveGame.slot_path(i + 1)] = true
	check(SaveGame.SLOTS == 3 and paths.size() == 3 and SaveGame.slot_path(1) == "user://save.json", "3 save slots, each its own file (slot 1 = the old save)")
	var keep_path: String = Game.save_path
	var keep_slot: int = Game.save_slot
	SaveGame.use_slot(2)
	check(Game.save_path == SaveGame.slot_path(2) and Game.save_slot == 2, "choosing a slot saves into it")
	Game.save_slot = keep_slot
	Game.save_path = keep_path
	Game.save_settings()
	check(["ammo_9mm", "ammo_12ga", "ammo_308"].all(func(id): return Items.max_stack(id) == 30) and Items.max_stack("ammo_556") == 100, "ammo stacks to 30 (assault rifle 5.56: 100)")
	print("Inventory edge cases")
	var keep_gear: Dictionary = inv.gear.duplicate(true)
	inv.gear["back"] = Items.make("backpack_small")
	inv.gear["hands"] = null
	for loc in inv.storage_cells():
		inv.take(loc)
	for i in inv.free_slots():
		inv.add("bandage", 1)
		inv.add("bandage", Items.max_stack("bandage"))
	var pile2 := LootSpot.new()
	pile2.is_bag = true
	pile2.contents = [Items.make("nails", 10)]
	pile2.position = p.global_position
	main.entities.add_child(pile2)
	inv.near = pile2
	inv.gear["hands"] = Items.make("rags", 1)
	p.do_action(Inventory.near_loc(0), "take")
	check(is_instance_valid(pile2) and not pile2.is_queued_for_deletion() and pile2.contents.size() == 1 and int(pile2.contents[0]["count"]) == 10,
		"taking a stack with no room leaves it on the ground (nothing lost)")
	var full_jacket := Items.make("jacket")
	full_jacket["cargo"][0] = Items.make("bandage", 2)
	inv.gear["hands"] = null
	for loc in inv.storage_cells():
		inv.take(loc)
	check(inv.can_place(full_jacket, Inventory.cargo_loc("back", 0)).contains("Empty"), "clothes with things in them can't go into a bag (empty it first)")
	pile2.free()
	inv.gear = keep_gear
	print("Weather")
	p.global_position = _open_spot(w, 3)
	main._set_weather("clear", 100.0)
	var t_clear := p.target_temp()
	main._set_weather("rain", 100.0)
	check(Game.weather == "rain" and main.weather_fx.kind == "rain", "it can rain")
	check(p.target_temp() < t_clear, "rain makes it colder")
	main._set_weather("snow", 100.0)
	check(p.target_temp() < t_clear - 8.0, "snow makes it colder still")
	main._set_weather("clear", 100.0)
	print("Fishing")
	var bank := Vector2i(-1, -1)
	for y in range(2, World.H - 2):
		for x in range(2, World.W - 2):
			if bank.x < 0 and w.get_tile(Vector2i(x, y)) == World.WATER and w.is_walkable(Vector2i(x, y + 1)) and _nothing_near(w.center_of(Vector2i(x, y + 1)), 60.0):
				bank = Vector2i(x, y + 1)
	p.global_position = w.center_of(bank)
	p._find_loot()
	inv.gear["hands"] = null
	p.cancel_busy()
	p.go_fishing()
	check(p.busy_t <= 0.0 and p.message.contains("fishing rod"), "fishing needs a rod")
	inv.gear["hands"] = Items.make("fishing_rod")
	p.go_fishing()
	check(p.busy_total >= 3.0 and p.busy_total <= 10.0, "a bite takes 3-10 seconds (%.1f)" % p.busy_total)
	var caught := 0
	for i in 40:
		p.finish_busy()
		if p.message == "Caught a fish!":
			caught += 1
		p.go_fishing()
	p.cancel_busy()
	check(caught >= 10 and caught < 40, "sometimes the fish is hooked, sometimes it gets away (%d / 40)" % caught)
	main._set_weather("rain", 100.0)
	var tmax := 0.0
	for i in 20:
		p.go_fishing()
		tmax = maxf(tmax, p.busy_total)
		p.cancel_busy()
	check(tmax <= 6.01, "fish bite faster in the rain (max %.1f s)" % tmax)
	main._set_weather("clear", 100.0)
	check(float(Items.def("cooked_fish")["hunger"]) >= 50.0, "a cooked fish is a proper meal (+%d)" % int(Items.def("cooked_fish")["hunger"]))
	print("Base building")
	for b in get_tree().get_nodes_in_group("survivors"):
		b.free()
	_clear_zombies()
	_clear_wildlife()
	p.global_position = _open_spot(w, 5)
	_clear_ground(p.global_position, 200.0)
	inv.gear["back"] = Items.make("backpack_large")
	inv.add("planks", 10)
	inv.add("planks", 10)
	inv.add("nails", 30)
	inv.add("rope", 2)
	inv.add("rags", 4)
	for k in ["kit_wall", "kit_gate", "kit_chest", "kit_bed", "kit_garden"]:
		check(p.craft(k) and inv.count_of(k) == 1, "craft " + Items.name_of(k).to_lower())
	p.facing = Vector2.RIGHT
	p.start_placing("kit_wall")
	wall_cell = p.build_cell()
	check(p.placing == "kit_wall" and p.build_problem(wall_cell) == "", "building mode: a spot in front of you")
	p.place_kit()
	p.finish_busy()
	check(main.structure_at(wall_cell) != null and w.get_tile(wall_cell) == World.BUILT, "wooden wall built")
	check(w.astar.is_point_solid(wall_cell) and w.astar_z.is_point_solid(wall_cell) and w.blocks_sight(wall_cell), "walls block people, zombies and sight")
	check(p.build_problem(wall_cell) != "", "can't build on top of a wall")
	p.start_placing("kit_gate")
	var gate_cell := _face_free(p, [Vector2.DOWN, Vector2.UP, Vector2.LEFT])
	p.place_kit()
	p.finish_busy()
	check(w.is_door(gate_cell) and main.structure_at(gate_cell).door != null, "gate built (a door zombies can't open)")
	p.start_placing("kit_chest")
	var chest_cell := _face_free(p, [Vector2.LEFT, Vector2.UP, Vector2.DOWN])
	p.place_kit()
	p.finish_busy()
	var chest_st: Structure = main.structure_at(chest_cell)
	check(chest_st != null and chest_st.chest != null, "chest built")
	p._find_loot()
	check(p.nearest_loot == chest_st.chest and p.interact_choice() == "loot", "Q opens the chest")
	p.interact()
	p._find_loot()
	check(inv.near == chest_st.chest, "the chest shows in the nearby list")
	inv.add("matches", 3)
	var mloc := inv.find("matches")
	inv.move(mloc, Inventory.near_loc(0))
	check(chest_st.chest.contents.any(func(it): return it["id"] == "matches"), "store things in your chest")
	main.hud.set_inventory_open(false)
	Game.open_inventory = false
	p.start_placing("kit_bed")
	var bed_cell := _face_free(p, [Vector2.UP, Vector2.DOWN, Vector2.LEFT])
	p.place_kit()
	p.finish_busy()
	check(main.structure_at(bed_cell) != null and main.in_base(p.global_position), "bed built - this is your base now")
	var spawned_in := false
	for i in 20:
		var z: Zombie = main.spawn_zombie(0.0, main.BASE_RADIUS * 0.9)
		if z != null:
			spawned_in = true
	check(not spawned_in, "zombies don't spawn at your base")
	_clear_zombies()
	main._crop_t = 0.0
	main._process(0.016)
	check(p.in_base, "you're at your base")
	var base_pos := p.global_position
	p.global_position = _open_spot_r(w, 6) if _open_spot_r(w, 6) != Vector2.INF else _open_spot(w, 4)
	p.in_base = true
	var zd := lerpf(380.0, 220.0, Game.night) * 0.75
	var zz: Zombie = main.add_zombie(p.global_position + Vector2(zd, 0))
	zz.set_physics_process(false)
	zz._think()
	var sees_in_base := zz.foe == p
	p.in_base = false
	zz.foe = null
	zz._think()
	check(not sees_in_base and zz.foe == p, "zombies see you from half as far at your base")
	zz.free()
	p.global_position = base_pos
	p.in_base = true
	print("Sleeping")
	main.time_of_day = 22.0 / 24.0
	var d0: int = main.day
	p.hunger = 100.0
	p.thirst = 100.0
	main.sleep()
	check(absf(main.time_of_day * 24.0 - 7.0) < 0.05 and main.day == d0 + 1, "sleep through the night until 07:00 (%s)" % main.clock_text())
	check(p.hunger < 100.0 and p.thirst < 100.0, "you wake up hungrier and thirstier")
	var zz2: Zombie = main.add_zombie(p.global_position + Vector2(200, 0))
	main.time_of_day = 22.0 / 24.0
	main.sleep()
	check(main.time_of_day * 24.0 > 21.0, "can't sleep with zombies around")
	zz2.free()
	p.bleeding = true
	main.sleep()
	check(main.time_of_day * 24.0 > 21.0 and p.message.contains("bleeding"), "can't sleep while bleeding")
	p.bleeding = false
	p.hunger = 3.0
	p.thirst = 100.0
	p.health = 100.0
	main.sleep()
	check(p.health < 95.0 and p.health >= 5.0 and p.message.contains("starving"), "sleeping while starving hurts (%.0f hp)" % p.health)
	p.health = 100.0
	p.hunger = 100.0
	print("Crops")
	_clear_wildlife()
	p.global_position = _open_spot(w, 3) + Vector2(0, 32 * 2)
	for b2 in get_tree().get_nodes_in_group("structures"):
		if b2.global_position.distance_to(p.global_position) < 120.0 and b2.kind != "bed":
			p.global_position += Vector2(0, 160)
	p.start_placing("kit_garden")
	var g_cell := _face_free(p, [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP])
	p.place_kit()
	p.finish_busy()
	var garden: Structure = main.structure_at(g_cell)
	check(garden != null and garden.kind == "garden", "garden bed built")
	inv.add("tomato_seeds", 2)
	p._find_loot()
	if not (p.interact_choice() == "build" and p.action_label() == "Plant tomatoes"):
		print("    DBG garden: choice=%s label=%s ns=%s nl=%s nf=%s lake=%s tap=%s" % [p.interact_choice(), p.action_label(), p.nearest_structure.kind if p.nearest_structure else "-", (p.nearest_loot.kind + " bag=" + str(p.nearest_loot.is_bag) + " d=" + str(int(p.nearest_loot.global_position.distance_to(p.global_position)))) if p.nearest_loot else "-", p.nearest_fire, p.near_lake, p.nearest_tap])
		print("    DBG garden d=%d g_cell=%s pcell=%s" % [int(garden.global_position.distance_to(p.global_position)) if garden else -1, g_cell, w.cell_of(p.global_position)])
	check(p.interact_choice() == "build" and p.action_label() == "Plant tomatoes", "Q at the garden bed: Plant tomatoes")
	p.interact()
	p.finish_busy()
	check(garden.crop == "tomato" and inv.count_of("tomato_seeds") == 1, "tomatoes planted (uses a seed)")
	main.world_days += 1.0
	garden.grow(main.world_days, false)
	check(not garden.ripe() and absf(garden.growth - 1.0 / 1.5) < 0.01, "tomatoes take 1.5 days (%.0f%% after 1 day)" % (garden.growth * 100.0))
	main.world_days += 0.5
	garden.grow(main.world_days, false)
	check(garden.ripe(), "ripe after 1.5 days")
	p._find_loot()
	p.interact()
	p.finish_busy()
	check(_pile_count("tomato") >= 3 and _pile_count("tomato_seeds") >= 2, "harvest: 3 tomatoes + 2 seeds on the ground")
	garden.plant("potato", main.world_days)
	main.world_days += 1.0
	garden.grow(main.world_days, true)
	check(absf(garden.growth - 0.5) < 0.01, "rain makes crops grow 1.5x faster (potato: 1 rainy day = 50%)")
	var tom: Dictionary = Structure.CROPS["tomato"]
	var pot: Dictionary = Structure.CROPS["potato"]
	var tom_day := 3.0 * float(Items.def("tomato")["hunger"]) / float(tom["days"])
	var pot_day := 5.0 * float(Items.def("potato")["hunger"]) / float(pot["days"])
	check(float(pot["days"]) == 3.0 and float(tom["days"]) == 1.5 and pot_day > tom_day and float(Items.def("potato")["hunger"]) > float(Items.def("tomato")["hunger"]),
		"potatoes: slower, more per batch, more food per day (%.0f vs %.0f hunger / day)" % [pot_day, tom_day])
	print("Dismantling / saving")
	p.global_position = w.center_of(gate_cell) + Vector2(0, 40)
	p._find_loot()
	var data: Dictionary = main.to_save()
	check(data["structures"].size() == 5 and data["structures"].any(func(d): return d["kind"] == "chest" and d["contents"].size() > 0), "your base is saved (with the chest's contents)")
	print("Military camps")
	var camp := -1
	for i in w.settlements.size():
		if w.settlements[i]["type"] == "military":
			camp = i
	check(camp >= 0, "a military camp in the region (%s)" % (w.settlements[camp]["name"] if camp >= 0 else "-"))
	if camp >= 0:
		var r: Rect2i = (w.settlements[camp]["rect"] as Rect2i).grow(1)
		var fence := 0
		for x in range(r.position.x, r.end.x):
			if w.get_tile(Vector2i(x, r.position.y)) == World.WALL:
				fence += 1
		check(fence > r.size.x / 2, "the camp is fenced in")
		var crates := w.containers.filter(func(c): return c["kind"] == "military").size()
		check(crates >= 8, "military crates (%d)" % crates)
		check(main.pick_zombie_type(camp) == "armed", "only armed zombies in the camp")
		var guns := 0
		var supplies := 0
		for i in 100:
			for it in Loot.roll("military"):
				if Items.is_weapon(it["id"]) or Items.kind(it["id"]) == "ammo":
					guns += 1
				elif Items.kind(it["id"]) in ["consumable", "medical"]:
					supplies += 1
		check(guns > 60 and supplies > 40, "military crates: lots of guns, ammo and supplies (%d / %d)" % [guns, supplies])


## Animals wander into building spots: take them out of the test world.
func _clear_wildlife() -> void:
	for a in get_tree().get_nodes_in_group("animals"):
		a.remove_from_group("animals")
		a.remove_from_group("wolves")
		a.free()
	main._animal_t = 9999.0


## Removes carcasses and piles lying around `pos`.
func _clear_ground(pos: Vector2, r: float) -> void:
	for l in get_tree().get_nodes_in_group("loot"):
		if (l.is_bag or l.kind == "carcass") and l.global_position.distance_to(pos) < r:
			l.remove_from_group("loot")
			l.free()


## A spot of open grass (r tiles around) with nothing you built nearby.
func _far_spot(w: World, r: int) -> Vector2:
	var built := get_tree().get_nodes_in_group("structures")
	for y in range(r + 2, World.H - r - 2, 3):
		for x in range(r + 2, World.W - r - 2, 3):
			var pos := w.center_of(Vector2i(x, y))
			if built.any(func(b): return b.global_position.distance_to(pos) < 300.0):
				continue
			var ok := true
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if w.get_tile(Vector2i(x + dx, y + dy)) != World.GROUND:
						ok = false
						break
				if not ok:
					break
			if ok and _nothing_near(pos, 120.0):
				return pos
	return Vector2.INF


## Builds a kit next to the player (stepping aside when every side is taken).
func _build(p: Player, kit: String) -> Structure:
	for attempt in 6:
		p.start_placing(kit)
		var cell := _face_free(p, [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP])
		if p.build_problem(cell) == "":
			p.place_kit()
			p.finish_busy()
			return main.structure_at(cell)
		p.global_position += Vector2(0, 64)
	return null


## Workbench, stove, shelves, weapon rack, rain collector, snares, fish traps, taking things apart.
func _utility_tests() -> void:
	var p: Player = main.player
	var w: World = main.world
	var inv := p.inv
	p.cancel_busy()
	p.stop_placing()
	main.hud.set_inventory_open(false)
	Game.open_inventory = false
	print("Workbench")
	_clear_zombies()
	_clear_wildlife()
	var spot := _far_spot(w, 6)
	check(spot != Vector2.INF, "an open spot for a second base")
	p.global_position = spot
	inv.gear["back"] = Items.make("backpack_large")
	inv.gear["melee"] = null
	inv.gear["hands"] = null
	for loc in inv.storage_cells():
		if inv.get_at(loc) != null:
			inv.take(loc)
	for i in 3:
		inv.add("planks", 10)
	inv.add("nails", 30)
	for i in 3:
		inv.add("scrap_metal", 5)
	for i in 2:
		inv.add("rope", 3)
	inv.add("sticks", 10)
	check(Crafting.missing(Crafting.get_recipe("kit_stove"), inv, false).contains("workbench") and not p.craft("kit_stove"), "the stove can only be made at a workbench")
	check(p.craft("kit_workbench") and inv.count_of("kit_workbench") == 1, "craft a workbench kit (anywhere)")
	var bench := _build(p, "kit_workbench")
	check(bench != null and bench.kind == "workbench" and p.near_bench(), "workbench built")
	p._find_loot()
	check(p.interact_choice() == "build" and p.action_label() == "Use workbench", "Q at the workbench: Use workbench")
	p.interact()
	check(main.hud.inventory_open and main.hud.left_tab == "craft", "Q at the workbench opens crafting")
	main.hud.set_inventory_open(false)
	for k in ["kit_stove", "kit_shelf", "kit_rack", "kit_collector", "kit_snare", "kit_fishtrap"]:
		check(p.craft(k) and inv.count_of(k) == 1, "craft " + Items.name_of(k).to_lower())
	var knife := Items.make("knife")
	knife["cond"] = 50.0
	inv.gear["melee"] = knife
	var kloc := {"t": "gear", "s": "melee"}
	var scrap := inv.count_of("scrap_metal")
	check(p.actions_for(kloc).any(func(a): return String(a[0]).begins_with("Repair at workbench")), "item menu: Repair at workbench")
	check(p.repair(kloc) and float(knife["cond"]) > 85.0 and inv.count_of("scrap_metal") == scrap - 1, "repair a weapon at the workbench with scrap metal (no toolbox)")
	var tee := Items.make("tshirt")
	tee["cond"] = 30.0
	inv.gear["shirt"] = tee
	var rags := inv.count_of("rags")
	inv.add("rags", 2)
	check(p.repair({"t": "gear", "s": "shirt"}) and float(tee["cond"]) > 65.0 and inv.count_of("rags") == rags, "repair clothing at the workbench with 2 rags")
	print("Stove")
	var stove := _build(p, "kit_stove")
	check(stove != null and stove.fire != null and stove.fire.lit and stove.fire.permanent, "stove built - it burns")
	var fuel0 := stove.fire.fuel
	stove.fire._process(100.0)
	check(stove.fire.fuel == fuel0, "the stove never burns out")
	check(p.near_fire(), "the stove keeps you warm")
	var plain_fires := get_tree().get_nodes_in_group("fires").filter(func(f): return not f.permanent).size()
	check(main.to_save()["fires"].size() == plain_fires, "the stove isn't saved as a campfire")
	inv.add("meat", 1)
	p.nearest_fire = stove.fire
	p.use_fire(stove.fire)
	check(p.cook_t > 0.0, "cook on the stove")
	p._finish_cooking()
	check(inv.count_of("cooked_meat") >= 1, "cooked meat from the stove")
	print("Shelves / weapon rack")
	var shelf := _build(p, "kit_shelf")
	var shelf_cell := shelf.cell if shelf else Vector2i.ZERO
	var shelf_pos := p.global_position
	var shelf_face := p.facing
	check(shelf != null and shelf.chest != null and shelf.chest.kind == "store_shelf", "shelves built")
	p._find_loot()
	inv.near = shelf.chest
	inv.add("matches", 2)
	inv.move(inv.find("matches"), Inventory.near_loc(0))
	check(shelf.chest.contents.any(func(it): return it["id"] == "matches") and shelf.chest._display != null, "store things on the shelves (they show on it)")
	var rack := _build(p, "kit_rack")
	check(rack != null and rack.chest != null and rack.chest.kind == "store_rack", "weapon rack built")
	inv.near = rack.chest
	check(inv.can_place(Items.make("tomato"), Inventory.near_loc(0)) != "" and inv.can_place(Items.make("knife"), Inventory.near_loc(0)) == "" and inv.can_place(Items.make("ammo_9mm"), Inventory.near_loc(0)) == "",
		"the weapon rack only takes weapons and ammo")
	check(not main.to_save()["loot"].any(func(l): return LootSpot.is_store_kind(String(l["kind"]))), "storage is saved with your base, not as loot")
	print("Rain collector")
	var col := _build(p, "kit_collector")
	check(col != null and col.kind == "collector" and col.water_units() == 0, "rain collector built (empty)")
	col.tick(col.last_day + 1.0 / 24.0, "rain")
	check(col.water_units() == 2, "an hour of rain: 2 drinks in it (%d)" % col.water_units())
	col.tick(col.last_day + 1.0 / 24.0, "clear")
	check(col.water_units() == 2, "no rain, no water")
	col.tick(col.last_day + 1.0 / 24.0, "snow")
	check(col.water_units() == 3, "snow fills it half as fast")
	col.tick(col.last_day + 5.0, "clear")
	check(col.water_units() == Structure.COLLECTOR_CAP, "fills up over days (max %d)" % Structure.COLLECTOR_CAP)
	p.thirst = 30.0
	p.cancel_busy()
	p._use_structure(col)
	p.finish_busy()
	check(p.thirst > 60.0 and col.water_units() < Structure.COLLECTOR_CAP, "drink from the rain collector")
	var cd: Dictionary = main.to_save()["structures"].filter(func(d): return d["kind"] == "collector")[0]
	check(absf(Structure.from_save(cd, w).water - col.water) < 0.02, "its water is saved")
	print("Snare")
	var sn := _build(p, "kit_snare")
	check(sn != null and sn.kind == "snare", "snare set on the grass")
	sn.tick(sn.last_day + 3.0, "clear")
	check(sn.caught == 1, "a rabbit in the snare after a few days")
	p._find_loot()
	var meat0 := _pile_count("meat")
	p._use_structure(sn)
	p.finish_busy()
	check(sn.caught == 0 and _pile_count("meat") == meat0 + 1, "take the rabbit: raw meat")
	print("Taking things apart")
	p.cancel_busy()
	p.global_position = shelf_pos
	p.facing = shelf_face
	p.placing = Player.NO_KIT
	check(p.build_cell() == shelf_cell, "building mode: aiming at the shelves")
	var planks0 := _pile_count("planks")
	p.place_kit()
	p.finish_busy()
	check(main.structure_at(shelf_cell) == null and _pile_count("matches") >= 2 and _pile_count("planks") > planks0, "Q in building mode takes it apart (materials + what was on it drop)")
	p.stop_placing()
	print("Walled-in base vs zombie paths")
	var ring_c := w.cell_of(_far_spot(w, 6))
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			if absi(dx) == 3 or absi(dy) == 3:
				main.add_structure("wall", ring_c + Vector2i(dx, dy))
	var zr: Zombie = main.add_zombie(w.center_of(ring_c + Vector2i(8, 0)))
	var t_path := Time.get_ticks_usec()
	zr._set_path(w.center_of(ring_c))
	var path_ms := (Time.get_ticks_usec() - t_path) / 1000.0
	check(zr.path.is_empty() and path_ms < 15.0, "zombies don't search the whole map for a way into a walled base (%.1f ms)" % path_ms)
	zr.free()
	print("Fish trap")
	var bank := Vector2i(-1, -1)
	var built := get_tree().get_nodes_in_group("structures")
	for y in range(2, World.H - 2):
		for x in range(2, World.W - 2):
			if bank.x < 0 and w.get_tile(Vector2i(x, y)) == World.WATER and w.is_walkable(Vector2i(x, y + 1)) and w.get_tile(Vector2i(x, y + 2)) == World.GROUND:
				var bp := w.center_of(Vector2i(x, y + 1))
				if _nothing_near(bp, 60.0) and not built.any(func(b): return b.global_position.distance_to(bp) < 120.0):
					bank = Vector2i(x, y + 1)
	check(bank.x >= 0, "a lake shore")
	if bank.x >= 0:
		p.global_position = w.center_of(bank)
		p.start_placing("kit_fishtrap")
		p.facing = Vector2.DOWN
		check(p.build_problem(p.build_cell()) != "", "fish traps don't go on land")
		p.facing = Vector2.UP
		var tc := p.build_cell()
		check(w.get_tile(tc) == World.WATER and p.build_problem(tc) == "", "a fish trap goes in the water by the shore")
		p.place_kit()
		p.finish_busy()
		var trap: Structure = main.structure_at(tc)
		check(trap != null and trap.kind == "fishtrap", "fish trap set")
		trap.tick(trap.last_day + 4.0, "rain")
		check(trap.caught == Structure.TRAP_CAP, "it fills up with fish (max %d)" % Structure.TRAP_CAP)
		p.stop_placing()
		p._find_loot()
		check(p.interact_choice() == "build" and p.action_label().begins_with("Take fish"), "Q at the trap takes the fish (not a drink from the lake)")
		var fish0 := _pile_count("fish")
		p.interact()
		p.finish_busy()
		check(trap.caught == 0 and _pile_count("fish") == fish0 + Structure.TRAP_CAP, "fish from the trap")


## Containers no walkable, connected cell is in reach of (e.g. a street light right outside a door).
func _unsearchable(w: World) -> int:
	var seen := PackedByteArray()
	seen.resize(World.W * World.H)
	var q: Array[Vector2i] = [w.spawn_cell]
	seen[w.idx(w.spawn_cell)] = 1
	while not q.is_empty():
		var c: Vector2i = q.pop_back()
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + o
			if w.in_bounds(n) and seen[w.idx(n)] == 0 and (w.is_walkable(n) or w.is_door(n)):
				seen[w.idx(n)] = 1
				q.append(n)
	var bad := 0
	for ct in w.containers:
		var pos: Vector2 = ct["pos"]
		var cc := w.cell_of(pos)
		var ok := false
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				var n := cc + Vector2i(dx, dy)
				if w.in_bounds(n) and seen[w.idx(n)] == 1 and w.center_of(n).distance_to(pos) < float(ct["reach"]) - 2.0:
					ok = true
		if not ok:
			bad += 1
			print("    can't search %s at %s" % [ct["kind"], cc])
	return bad


## Turns the player towards the first direction where the kit can be built; returns that cell.
func _face_free(p: Player, dirs: Array) -> Vector2i:
	for d in dirs:
		p.facing = d
		if p.build_problem(p.build_cell()) == "":
			return p.build_cell()
	return p.build_cell()
