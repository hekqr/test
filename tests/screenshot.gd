extends Node
## Saves day + night screenshots. Run under a display: godot --path . res://tests/screenshot.tscn -- <out_dir>

var main: Node
var frame := 0
var out := "user://"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)


func _process(_delta: float) -> void:
	frame += 1
	var p: Player = main.player
	if frame == 5:
		# Stand next to a building with loot so there's something to see.
		var l := get_tree().get_nodes_in_group("loot")[0] as LootSpot
		p.global_position = l.global_position + Vector2(10, 0)
		main.add_zombie(p.global_position + Vector2(120, 60))
		main.add_zombie(p.global_position + Vector2(-140, -40), true)
		p.has_pistol = true
		p.weapon = 1
		p.mag = 8
	if frame == 60:
		get_viewport().get_texture().get_image().save_png(out + "/day.png")
		main.time_of_day = 0.02
	if frame == 90:
		get_viewport().get_texture().get_image().save_png(out + "/night.png")
		get_tree().quit()
