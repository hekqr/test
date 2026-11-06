extends Node
## Saves screenshots. Run under a display: godot --path . res://tests/screenshot.tscn -- <out_dir>

var main: Node
var frame := 0
var out := "user://"
var _enemies: Array = []
var _door: Door


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	Game.save_path = "user://shot_save.json"
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")


func _process(_delta: float) -> void:
	frame += 1
	if frame > 175:
		if frame == 240:
			_shot("menu")
			get_tree().quit()
		return
	var p: Player = main.player
	var w: World = main.world
	if frame == 5:
		# Stand just outside a building so the roof is visible (a hut in a village if there is one).
		var bi0 := 0
		for i in w.buildings.size():
			if String(w.building_types[i]).begins_with("hut") and w.settlements[w.building_town[i]]["type"] == "village":
				bi0 = i
				break
		var b: Rect2i = w.buildings[bi0]
		p.global_position = w.center_of(Vector2i(b.end.x + 1, b.position.y + b.size.y / 2))
		p.inv.pickup({"id": "pistol", "count": 1, "mag": 5})
		p.inv.pickup(Items.make("bat"))
		p.inv.pickup({"id": "shotgun", "count": 1, "mag": 3})
		p.inv.pickup(Items.make("backpack_small"))
		p.inv.pickup(Items.make("jacket"))
		p.inv.pickup(Items.make("vest"))
		p.inv.pickup(Items.make("boots"))
		p.inv.add("ammo_9mm", 14)
		p.inv.add("ammo_12ga", 6)
		p.inv.add("food", 1)
		p.inv.add("soda")
		p.inv.add("firstaid")
		p.inv.pickup({"id": "rifle", "count": 1, "mag": 22})
		p.inv.add("cargo_pants")
		p.inv.add("sewing_kit")
		p.inv.add("toolbox")
		p.inv.add("scrap_metal", 3)
		p.inv.gear["hands"] = Items.make("scrap_armour")
		p.inv.gear["melee"]["cond"] = 42.0
		p.switch_weapon("primary")
		p.hunger = 62.0
		p.thirst = 45.0
		p.health = 78.0
		main.add_zombie(p.global_position + Vector2(260, 120))
		# Animals and a campfire next to the player
		for a in get_tree().get_nodes_in_group("animals"):
			a.queue_free()
		var deer: Animal = main.add_animal("deer", p.global_position + Vector2(-150, 70))
		var rab: Animal = main.add_animal("rabbit", p.global_position + Vector2(110, -70))
		deer.set_physics_process(false)
		rab.set_physics_process(false)
		main.add_fire(p.global_position + Vector2(-40, 30), 200.0)
		var pile := LootSpot.new()
		pile.is_bag = true
		pile.contents = [Items.make("food"), Items.make("water")]
		pile.position = p.global_position + Vector2(70, -10)
		main.entities.add_child(pile)
		var c := LootSpot.new()
		c.kind = "carcass"
		c.animal = "rabbit"
		c.contents = [Items.make("meat")]
		c.position = p.global_position + Vector2(60, 60)
		main.entities.add_child(c)
	if frame == 30:
		# Every zombie type and two bandits lined up (frozen) for a look
		_enemies = []
		var at := _open_row(w) + Vector2(-210, 0)
		var row := 0
		for t in ["walker", "runner", "brute", "axe", "armed"]:
			var z: Zombie = main.add_zombie(at + Vector2(row * 70, 0), t)
			z.facing = Vector2.DOWN
			_enemies.append(z)
			row += 1
		for i in 2:
			var b := Survivor.new()
			b.position = at + Vector2(row * 70, 0)
			main.add_survivor(b)
			_enemies.append(b)
			row += 1
		for e in _enemies:
			e.set_physics_process(false)
		p.global_position = at + Vector2(210, 110)
	if frame == 45:
		for e in _enemies:
			e._animate(false) if e is Zombie else e._animate()
			if e is Zombie and (e.type == "walker" or e.type == "brute"):
				e.health = e.max_health * 0.55 # show the health bar
				e.queue_redraw()
		await get_tree().process_frame
		_shot("enemies")
		for e in _enemies:
			e.queue_free()
		# A river / lake bank with a wolf pack
		_enemies = []
		var bank := Vector2i(-1, -1)
		for y in range(8, World.H - 8):
			for x in range(8, World.W - 8):
				var c := Vector2i(x, y)
				if bank.x < 0 and w.get_tile(c) == World.WATER and w.get_tile(c + Vector2i(0, 2)) == World.GROUND and w.get_tile(c + Vector2i(-3, 0)) == World.WATER:
					bank = c + Vector2i(0, 2)
		p.global_position = w.center_of(bank)
		for i in 3:
			var wolf: Animal = main.add_animal("wolf", p.global_position + Vector2(140 + i * 40, 60 + (i % 2) * 30))
			wolf.set_physics_process(false)
			_enemies.append(wolf)
	if frame == 62:
		_shot("water")
		for e in _enemies:
			e.queue_free()
		var b2: Rect2i = w.buildings[0]
		p.global_position = w.center_of(Vector2i(b2.end.x + 1, b2.position.y + b2.size.y / 2))
	if frame == 80:
		_shot("outside")
		var l: LootSpot = null
		for n in get_tree().get_nodes_in_group("loot"):
			if n.kind == "fridge":
				l = n
				break
		l.contents = [Items.make("water"), Items.make("soda"), Items.make("meat", 2), Items.make("soup"), Items.make("flannel"), Items.make("ammo_9mm", 12)]
		p.global_position = l.global_position + Vector2(0, 32)
	if frame == 100:
		_shot("inside")
		main.hud.set_inventory_open(true)
	if frame == 104:
		_shot("inventory")
		p.inv.add("rags", 5)
		p.inv.add("sack")
		p.inv.add("sticks", 4)
		p.inv.add("leather", 2)
		main.hud.left_tab = "craft"
		await get_tree().process_frame
		await get_tree().process_frame
		_shot("crafting")
		main.hud.left_tab = "near"
		main.hud.set_inventory_open(false)
		# Stand a few steps from a house's front door (closed)
		for d in get_tree().get_nodes_in_group("doors"):
			if d.front != null and w.building_types[w.building_id[w.idx(d.cell)]].begins_with("house"):
				_door = d
				break
		p.global_position = w.center_of(_door.cell + Vector2i(2, 3))
	if frame == 118:
		_shot("door_closed")
		p.global_position = w.center_of(_door.cell + Vector2i(0, 1)) + Vector2(0, 6)
	if frame == 126:
		_shot("door_open")
		# A little base in the rain
		var at := _open_row(w) + Vector2(64, 0)
		p.global_position = at + Vector2(0, 64)
		var c0 := w.cell_of(at)
		for k in range(-3, 4):
			main.add_structure("wall", c0 + Vector2i(k, -2))
		main.add_structure("wall", c0 + Vector2i(-3, -1))
		main.add_structure("wall", c0 + Vector2i(3, -1))
		main.add_structure("gate", c0 + Vector2i(3, 0))
		main.add_structure("bed", c0 + Vector2i(-2, -1))
		main.add_structure("chest", c0 + Vector2i(-1, -1))
		var g1: Structure = main.add_structure("garden", c0 + Vector2i(1, -1))
		g1.plant("tomato", main.world_days)
		g1.growth = 1.0
		g1.grow(main.world_days, false)
		var g2: Structure = main.add_structure("garden", c0 + Vector2i(2, -1))
		g2.plant("potato", main.world_days)
		g2.growth = 0.5
		g2.grow(main.world_days, false)
		# Utility row in front of the wall
		main.add_structure("workbench", c0 + Vector2i(-3, 1))
		main.add_structure("stove", c0 + Vector2i(-2, 1))
		var sh: Structure = main.add_structure("shelf", c0 + Vector2i(-1, 1))
		for id in ["tomato", "potato", "water", "bandage", "meat"]:
			sh.chest.contents.append(Items.make(id))
		sh.chest.refresh()
		var rk: Structure = main.add_structure("rack", c0 + Vector2i(0, 1))
		for id in ["axe", "knife"]:
			rk.chest.contents.append(Items.make(id))
		rk.chest.refresh()
		var cl: Structure = main.add_structure("collector", c0 + Vector2i(1, 1))
		cl.water = 6.0
		cl.tick(main.world_days, "clear")
		var sn: Structure = main.add_structure("snare", c0 + Vector2i(2, 2))
		sn.caught = 1
		sn.tick(main.world_days + 0.001, "clear")
		main._set_weather("rain", 500.0)
		p.inv.gear["hands"] = Items.make("fishing_rod")
	if frame == 138:
		p.health = 15.0
		p.hit_flash = 0.0
	if frame == 140:
		_shot("base_rain")
		p.health = 100.0
		main._set_weather("clear", 500.0)
		for i in w.settlements.size():
			if w.settlements[i]["type"] == "military":
				p.global_position = w.center_of(w.settlements[i]["center"]) + Vector2(0, 40)
	if frame == 160:
		_shot("camp")
		main.time_of_day = 0.02
	if frame == 175:
		_shot("night")
		main.hud.set_map_open(true)
		await get_tree().process_frame
		await get_tree().process_frame
		_shot("map")
		main.hud.set_map_open(false)
		p.inv.gear["hands"] = Items.make("map")
		main.hud._map_zoom = 1.0
		main.hud.set_map_open(true)
		main.time_of_day = 0.4
		await get_tree().process_frame
		await get_tree().process_frame
		_shot("map_full")
		main.hud.set_map_open(false)
		get_tree().paused = true
		await get_tree().process_frame
		await get_tree().process_frame
		_shot("pause")
		get_tree().paused = false
		p.take_damage(500.0)
		for k in 30:
			await get_tree().process_frame
		_shot("death")
		main.save_game()
		main.queue_free()
		add_child(load("res://scenes/menu.tscn").instantiate())


## Left end of a 16x6 tile strip of open ground (for the enemy line-up).
func _open_row(w: World) -> Vector2:
	for y in range(6, World.H - 8):
		for x in range(10, World.W - 10):
			var ok := true
			for dy in range(-2, 4):
				for dx in range(-8, 8):
					if w.get_tile(Vector2i(x + dx, y + dy)) != World.GROUND:
						ok = false
						break
				if not ok:
					break
			if ok:
				return w.center_of(Vector2i(x, y))
	return w.center_of(w.spawn_cell)
