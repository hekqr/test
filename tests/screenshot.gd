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
		p.inv.add("ammo_pistol", 14)
		p.inv.add("ammo_shotgun", 6)
		p.inv.add("food", 1)
		p.switch_weapon("primary")
		p.hunger = 62.0
		p.thirst = 45.0
		p.health = 78.0
		main.add_zombie(p.global_position + Vector2(140, 60))
		main.add_zombie(p.global_position + Vector2(160, -60), true)
	if frame == 60:
		_shot("outside")
		var l: LootSpot = null
		for n in get_tree().get_nodes_in_group("loot"):
			if n.is_bag:
				l = n
				break
		p.global_position = l.global_position + Vector2(10, 0)
	if frame == 100:
		_shot("inside")
		main.hud.set_inventory_open(true)
	if frame == 104:
		_shot("inventory")
		main.hud.set_inventory_open(false)
		main.time_of_day = 0.02
	if frame == 130:
		_shot("night")
		main.save_game()
		main.queue_free()
		add_child(load("res://scenes/menu.tscn").instantiate())
