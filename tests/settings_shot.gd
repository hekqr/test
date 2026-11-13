extends Node
## Dev tool: screenshots of the settings screen (both tabs) and a key rebind round trip.
## xvfb-run -a godot --path . res://tests/settings_shot.tscn -- <out_dir>
var out := "user://"
var f := 0
var menu: Control
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	menu = load("res://scenes/menu.tscn").instantiate()
	add_child(menu)
func _process(_d: float) -> void:
	f += 1
	if f == 10:
		get_viewport().get_texture().get_image().save_png(out + "/menu.png")
		menu._press("settings")
	if f == 20:
		get_viewport().get_texture().get_image().save_png(out + "/settings_general.png")
		menu._settings._press("tab_controls")
		menu._settings._press("key:interact")
	if f == 30:
		get_viewport().get_texture().get_image().save_png(out + "/settings_controls.png")
		get_tree().quit()
