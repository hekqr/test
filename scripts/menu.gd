extends Control
## Title screen: Continue (auto-save), New Game, Quit.

const SCALE := 4.0
const C_EDGE := Color("1a1016")
const C_TEXT := Color(0.95, 0.9, 0.82)
const C_DIM := Color(0.8, 0.75, 0.7)

var _font: Font
var _save := {}
var _confirm_new := false
var _down := ""
var _mouse := Vector2.ZERO
var _bg_tiles: Array = []
var _loading := false


func _ready() -> void:
	get_tree().set_auto_accept_quit(true)
	get_tree().paused = false
	Game.ui_open = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	_font = ThemeDB.fallback_font
	_save = SaveGame.read()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 400:
		_bg_tiles.append(rng.randi() % 9)


func _process(_d: float) -> void:
	_mouse = get_viewport().get_mouse_position()
	queue_redraw()


func _buttons() -> Array:
	var vs := get_viewport_rect().size
	var sz := Game.tex("ui_button").get_size() * SCALE
	var out := []
	var names := ["continue", "new", "quit"]
	for i in names.size():
		out.append([names[i], Rect2(Vector2((vs.x - sz.x) / 2.0, vs.y * 0.42 + i * (sz.y + 22)), sz)])
	return out


func _enabled(id: String) -> bool:
	return id != "continue" or SaveGame.can_continue()


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return
	for b in _buttons():
		if b[1].has_point(event.position) and _enabled(b[0]):
			if event.pressed:
				_down = b[0]
			elif _down == b[0]:
				_press(b[0])
	if not event.pressed:
		_down = ""


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and SaveGame.can_continue():
		_press("continue")


func _press(id: String) -> void:
	match id:
		"continue":
			Game.pending_load = SaveGame.read()
			_load_world()
		"new":
			if SaveGame.can_continue() and not _confirm_new:
				_confirm_new = true # click again to overwrite the living survivor
				return
			Game.pending_load = {}
			_load_world()
		"quit":
			get_tree().quit()


func _text(pos: Vector2, s: String, size_px: int, col: Color, width: float) -> void:
	draw_string(_font, pos + Vector2(3, 3), s, HORIZONTAL_ALIGNMENT_CENTER, width, size_px, Color(0.08, 0.04, 0.07, 0.9))
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_CENTER, width, size_px, col)


## Shows "Generating the world..." for a moment, then builds the game (takes a couple of seconds).
func _load_world() -> void:
	if _loading:
		return
	_loading = true
	queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _draw() -> void:
	var vs := get_viewport_rect().size
	if _loading:
		draw_rect(Rect2(Vector2.ZERO, vs), Color("1a1016"))
		var msg := "Generating the world..."
		draw_string(_font, Vector2(0, vs.y / 2.0), msg, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 28, Color("e8dcc0"))
		return
	# Background: dark grass made from the ground tiles
	var ground := Game.tex("tiles_ground")
	var grass := [Vector2i(0, 0), Vector2i(2, 0), Vector2i(5, 0), Vector2i(14, 0), Vector2i(16, 0), Vector2i(0, 2), Vector2i(2, 2), Vector2i(14, 2), Vector2i(16, 2)]
	var t := 16.0 * SCALE
	var i := 0
	for y in ceili(vs.y / t):
		for x in ceili(vs.x / t):
			var c: Vector2i = grass[_bg_tiles[i % _bg_tiles.size()]]
			draw_texture_rect_region(ground, Rect2(x * t, y * t, t, t), Rect2(c.x * 16, c.y * 16, 16, 16), Color(0.35, 0.4, 0.62))
			i += 1
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.04, 0.02, 0.06, 0.45))

	_text(Vector2(0, vs.y * 0.24), "PROJECT 0", 84, C_TEXT, vs.x)
	_text(Vector2(0, vs.y * 0.24 + 40), "survive the outbreak", 20, C_DIM, vs.x)

	for b in _buttons():
		var id: String = b[0]
		var r: Rect2 = b[1]
		var on := _enabled(id)
		var pressed := _down == id and r.has_point(_mouse)
		var mod := Color.WHITE if on else Color(0.5, 0.45, 0.5)
		if on and r.has_point(_mouse) and not pressed:
			mod = Color(1.1, 1.08, 1.0)
		draw_texture_rect(Game.tex("ui_button_pressed" if pressed else "ui_button"), Rect2(r.position + Vector2(0, 8 if pressed else 0), Game.tex("ui_button_pressed" if pressed else "ui_button").get_size() * SCALE), false, mod)
		var label: String = {"continue": "Continue", "new": "New Game", "quit": "Quit"}[id]
		if id == "new" and _confirm_new:
			label = "Overwrite?"
		draw_string(_font, Vector2(r.position.x, r.position.y + (58 if pressed else 50)), label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 26, C_EDGE if on else Color(0.2, 0.15, 0.2, 0.7))

	# Save summary under the buttons
	var info := "No survivor yet"
	var col := C_DIM
	if not _save.is_empty():
		var st := int(_save.get("survived", 0.0))
		if int(_save.get("version", 0)) != SaveGame.VERSION:
			info = "Old save from an earlier version - start a New Game"
			col = Color(1, 0.75, 0.4)
		elif _save.get("dead", false):
			info = "Your survivor died on day %d  (survived %d:%02d, %d kills)" % [int(_save["day"]), st / 60, st % 60, int(_save["kills"])]
			col = Color(1, 0.55, 0.5)
		else:
			info = "Day %d   survived %d:%02d   %d kills" % [int(_save["day"]), st / 60, st % 60, int(_save["kills"])]
	_text(Vector2(0, _buttons()[2][1].end.y + 50), info, 18, col, vs.x)
	if _confirm_new:
		_text(Vector2(0, _buttons()[2][1].end.y + 78), "Starting a new game replaces your current survivor. Click New Game again to confirm.", 15, C_DIM, vs.x)
	_text(Vector2(0, vs.y - 24), "The game saves automatically", 14, C_DIM, vs.x)
