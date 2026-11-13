extends Node
## Dev tool: close-up screenshot of the character wearing different gear, in every direction.
## xvfb-run -a godot --path . res://tests/gear_shot.tscn -- <out_dir>
var main: Node
var f := 0
var out := "user://"
const OUTFITS := [
	{},
	{"head": "cap", "coat": "hoodie", "back": "backpack_small"},
	{"head": "helmet", "armour": "vest", "coat": "field_jacket", "back": "backpack_large"},
	{"head": "beanie", "armour": "scrap_armour", "coat": "parka"},
]
var dummies := []
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	Game.save_path = "user://gear_shot_%d.json" % OS.get_process_id()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
func _process(_d: float) -> void:
	f += 1
	var p: Player = main.player
	if f == 5:
		for g in ["zombies", "survivors", "animals"]:
			for n in get_tree().get_nodes_in_group(g):
				n.free()
		main._spawn_t = 1e9
		main._survivor_t = 1e9
		main._animal_t = 1e9
		p.camera.zoom = Vector2(2.5, 2.5)
		main.hud.visible = false
		var w: World = main.world
		for y in range(40, World.H - 40, 3):
			var found := false
			for x in range(40, World.W - 40, 3):
				var ok := true
				for dy in range(-6, 7):
					for dx in range(-8, 9):
						if w.get_tile(Vector2i(x + dx, y + dy)) != World.GROUND:
							ok = false
				if ok:
					p.global_position = w.center_of(Vector2i(x, y))
					found = true
					break
			if found:
				break
		var dirs := [Vector2.DOWN, Vector2.RIGHT, Vector2.UP, Vector2.LEFT]
		for i in OUTFITS.size():
			for j in 4:
				var s := Survivor.new()
				for slot in Inventory.GEAR:
					s.gear[slot] = null
				s.gear["shirt"] = Items.make("tshirt")
				for slot in OUTFITS[i]:
					s.gear[slot] = Items.make(OUTFITS[i][slot])
				s.position = p.global_position + Vector2(-90 + j * 50, -90 + i * 55)
				s.facing = dirs[j]
				s.aim = dirs[j]
				main.entities.add_child(s)
				for c in s.get_children():
					if c is Label:
						c.visible = false
				s.process_mode = Node.PROCESS_MODE_DISABLED
				dummies.append(s)
		p.global_position += Vector2(1000, 0)
		p.camera.global_position = dummies[0].position
	if f == 10:
		for s in dummies:
			s.process_mode = Node.PROCESS_MODE_INHERIT
			s._animate()
			s.process_mode = Node.PROCESS_MODE_DISABLED
			s._overlay.process_mode = Node.PROCESS_MODE_ALWAYS
			s._overlay.facing = s.facing
		p.global_position = dummies[0].position + Vector2(75, 70)
		p.camera.position_smoothing_enabled = false
		main.time_of_day = 0.5
		p.visible = false
		p.process_mode = Node.PROCESS_MODE_DISABLED
	if f == 40:
		get_viewport().get_texture().get_image().save_png(out + "/gear.png")
		get_tree().quit()
