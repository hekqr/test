extends Node
## Saves screenshots. Run under a display: godot --path . res://tests/screenshot.tscn -- <out_dir>

var main: Node
var frame := 0
var out := "user://"


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
	if frame > 130:
		if frame == 140:
			_shot("menu")
			get_tree().quit()
		return
	var p: Player = main.player
	var w: World = main.world
	if frame == 5:
		# Stand just outside a building so the roof is visible.
		var b: Rect2i = w.buildings[0]
		p.global_position = w.center_of(Vector2i(b.end.x + 1, b.position.y + b.size.y / 2))
		p.inv.pickup({"id": "pistol", "count": 1, "mag": 5})
		p.inv.pickup(Items.make("bat"))
		p.inv.pickup({"id": "shotgun", "count": 1, "mag": 3})
		p.inv.pickup(Items.make("backpack_small"))
		p.inv.pickup(Items.make("hoodie"))
		p.inv.pickup(Items.make("vest"))
		p.inv.pickup(Items.make("boots"))
		p.inv.add("ammo_9mm", 14)
		p.inv.add("ammo_12ga", 6)
		p.inv.add("food", 1)
		p.inv.add("soda")
		p.inv.add("firstaid")
		p.inv.pickup({"id": "rifle", "count": 1, "mag": 22})
		p.inv.add("cargo_pants")
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
		var c := LootSpot.new()
		c.kind = "carcass"
		c.animal = "rabbit"
		c.contents = [Items.make("meat")]
		c.position = p.global_position + Vector2(60, 60)
		main.entities.add_child(c)
	if frame == 60:
		_shot("outside")
		var l: LootSpot = null
		for n in get_tree().get_nodes_in_group("loot"):
			if n.kind == "fridge":
				l = n
				break
		l.contents = [Items.make("water"), Items.make("soda"), Items.make("meat"), Items.make("soup")]
		p.global_position = l.global_position + Vector2(0, 32)
	if frame == 100:
		_shot("inside")
		main.hud.set_inventory_open(true)
		var sl := Inventory.gear_loc("shirt")
		main.hud._menu = {"loc": sl, "pos": main.hud.gear_cell("shirt").get_center() + Vector2(-150, 20), "items": p.actions_for(sl)}
	if frame == 104:
		_shot("inventory")
		main.hud.set_inventory_open(false)
		main.time_of_day = 0.02
	if frame == 130:
		_shot("night")
		main.save_game()
		main.queue_free()
		add_child(load("res://scenes/menu.tscn").instantiate())
