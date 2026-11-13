extends Control
## Title screen: 3 save slots (click one to continue it, or to start in an empty one; New starts over
## in that slot), Quit. Q continues the slot you played last.

const SCALE := 4.0
const C_EDGE := Color("1a1016")
const C_TEXT := Color(0.95, 0.9, 0.82)
const C_DIM := Color(0.8, 0.75, 0.7)

var _font: Font
var _saves: Array = [] # each slot's save (empty = free slot)
var _confirm_new := 0 # slot waiting for a second click on New
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
	for i in SaveGame.SLOTS:
		_saves.append(SaveGame.read_slot(i + 1))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 400:
		_bg_tiles.append(rng.randi() % 9)


func _process(_d: float) -> void:
	_mouse = get_viewport().get_mouse_position()
	queue_redraw()


const PANEL_W := 600.0
const PANEL_H := 74.0


## [id, rect]: "slot1".."slot3" (play / continue), "new1".."new3" (start over), "quit".
func _buttons() -> Array:
	var vs := get_viewport_rect().size
	var out := []
	for i in SaveGame.SLOTS:
		var r := Rect2((vs.x - PANEL_W) / 2.0, vs.y * 0.33 + i * (PANEL_H + 14), PANEL_W, PANEL_H)
		out.append(["slot%d" % (i + 1), r])
		if not _saves[i].is_empty():
			out.append(["new%d" % (i + 1), Rect2(r.end.x - 118, r.position.y + 15, 104, PANEL_H - 30)])
	var sz := Game.tex("ui_button").get_size() * SCALE
	var by := vs.y * 0.33 + SaveGame.SLOTS * (PANEL_H + 14) + 20
	out.append(["settings", Rect2(Vector2(vs.x / 2.0 - sz.x - 10, by), sz)])
	out.append(["quit", Rect2(Vector2(vs.x / 2.0 + 10, by), sz)])
	return out


## The button under the mouse (the small New button wins over its slot panel).
func _hit(pos: Vector2) -> String:
	var hit := ""
	for b in _buttons():
		if b[1].has_point(pos):
			hit = b[0]
	return hit


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var id := _hit(event.position)
	if event.pressed:
		_down = id
	elif _down == id and id != "":
		_press(id)
	if not event.pressed:
		_down = ""


## Q: continue the last slot you played.
func _unhandled_input(event: InputEvent) -> void:
	if _settings and _settings.visible:
		return
	if event.is_action_pressed("interact") and SaveGame.slot_can_continue(Game.save_slot):
		_press("slot%d" % Game.save_slot)


var _settings: SettingsMenu


func _press(id: String) -> void:
	Sfx.ui("ui_click", -4.0)
	if id == "quit":
		get_tree().quit()
		return
	if id == "settings":
		if _settings == null:
			_settings = SettingsMenu.new()
			add_child(_settings)
		_settings.open()
		return
	var slot := int(id.right(1))
	if id.begins_with("slot"):
		SaveGame.use_slot(slot)
		if SaveGame.slot_can_continue(slot):
			Game.pending_load = SaveGame.read_slot(slot)
		else:
			Game.pending_load = {} # empty, dead or old: a new survivor
		_load_world()
	elif id.begins_with("new"):
		if SaveGame.slot_can_continue(slot) and _confirm_new != slot:
			_confirm_new = slot # click again to replace the living survivor
			return
		SaveGame.use_slot(slot)
		Game.pending_load = {}
		_load_world()


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
		var hover := _hit(_mouse) == id
		if id in ["quit", "settings"]:
			var pressed := _down == id and hover
			var mod := Color(1.1, 1.08, 1.0) if hover and not pressed else Color.WHITE
			var tn := "ui_button_pressed" if pressed else "ui_button"
			draw_texture_rect(Game.tex(tn), Rect2(r.position + Vector2(0, 8 if pressed else 0), Game.tex(tn).get_size() * SCALE), false, mod)
			draw_string(_font, Vector2(r.position.x, r.position.y + (58 if pressed else 50)), "Quit" if id == "quit" else "Settings", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 26 if id == "quit" else 22, C_EDGE)
		elif id.begins_with("slot"):
			_draw_slot(int(id.right(1)), r, hover)
		else:
			var slot := int(id.right(1))
			var sure := _confirm_new == slot
			draw_rect(r, C_EDGE)
			draw_rect(r.grow(-3), Color("8a3a32") if sure else (Color("6e5a4a") if hover else Color("54443a")))
			draw_string(_font, Vector2(r.position.x, r.position.y + 29), "Sure?" if sure else "New", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 18, C_TEXT)
	if _confirm_new > 0:
		_text(Vector2(0, _buttons()[-1][1].end.y + 40), "This replaces the survivor in slot %d. Click Sure? to confirm." % _confirm_new, 15, Color(1, 0.75, 0.6), vs.x)
	_text(Vector2(0, vs.y - 24), "The game saves automatically   -   %s continues your last game" % Game.key("interact"), 14, C_DIM, vs.x)


## One save slot: its number and what's in it.
func _draw_slot(slot: int, r: Rect2, hover: bool) -> void:
	var save: Dictionary = _saves[slot - 1]
	var last := slot == Game.save_slot and not save.is_empty()
	draw_rect(r, C_EDGE)
	draw_rect(r.grow(-3), Color("4e4250") if hover else Color("3a3040"))
	if last:
		draw_rect(r.grow(-3), Color(0.9, 0.8, 0.5, 0.6), false, 2.0)
	var x := r.position.x + 22
	draw_string(_font, Vector2(x, r.position.y + 32), "Slot %d" % slot, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, C_TEXT)
	var info := "Empty - click to start a new game"
	var col := C_DIM
	var action := ""
	if not save.is_empty():
		var st := int(save.get("survived", 0.0))
		if int(save.get("version", 0)) != SaveGame.VERSION:
			info = "Old save from an earlier version - click to start over"
			col = Color(1, 0.75, 0.4)
		elif save.get("dead", false):
			info = "Died on day %d  (survived %d:%02d, %d kills) - click to start over" % [int(save["day"]), st / 60, st % 60, int(save["kills"])]
			col = Color(1, 0.55, 0.5)
		else:
			info = "Day %d   survived %d:%02d   %d kills" % [int(save["day"]), st / 60, st % 60, int(save["kills"])]
			col = Color(0.75, 0.95, 0.65)
			action = "Continue"
	draw_string(_font, Vector2(x, r.position.y + 58), info, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 160, 15, col)
	if action != "":
		draw_string(_font, Vector2(r.position.x + 130, r.position.y + 32), action + (" (%s)" % Game.key("interact") if last else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, C_DIM)
