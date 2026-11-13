class_name SettingsMenu
extends Control
## Settings screen (from the title screen and the pause menu): sound volumes, window / resolution / vsync,
## aim mode, and every key (click a key, then press the new one). Saved in settings.cfg right away.

signal closed

const C_EDGE := Color("1a1016")
const C_TEXT := Color(0.95, 0.9, 0.82)
const C_DIM := Color(0.8, 0.75, 0.7)
const C_CARD := Color("3a3040")
const C_HOVER := Color("4e4250")
const C_ON := Color("6e5a4a")
const PANEL := Vector2(760, 600)
const ROW_H := 36.0
const ROWS_SHOWN := 11

var tab := "general" # or "controls"
var _font: Font
var _mouse := Vector2.ZERO
var _waiting := "" # action waiting for its new key
var _note := ""
var _scroll := 0
var _drag := "" # volume slider being dragged


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font


func _process(_d: float) -> void:
	_mouse = get_local_mouse_position()
	queue_redraw()


func _panel_rect() -> Rect2:
	var vs := get_viewport_rect().size
	return Rect2((vs - PANEL) / 2.0, PANEL)


## Rows of the General tab: [id, label]
func _general_rows() -> Array:
	return [["master", "Master volume"], ["sfx", "Effects volume"], ["ambience", "Ambience volume"],
		["mode", "Window"], ["res", "Window size"], ["vsync", "VSync"], ["aim", "Aim mode"]]


## Clickable things: [id, rect]
func _buttons() -> Array:
	var r := _panel_rect()
	var out := []
	out.append(["tab_general", Rect2(r.position.x + 20, r.position.y + 58, 160, 34)])
	out.append(["tab_controls", Rect2(r.position.x + 186, r.position.y + 58, 160, 34)])
	var y0 := r.position.y + 110
	if tab == "general":
		var rows := _general_rows()
		for i in rows.size():
			var rr := Rect2(r.position.x + 300, y0 + i * (ROW_H + 8), 420, ROW_H)
			out.append([rows[i][0], rr])
	else:
		var actions := Game.KEYS.keys()
		_scroll = clampi(_scroll, 0, maxi(actions.size() - ROWS_SHOWN, 0))
		for k in mini(ROWS_SHOWN, actions.size() - _scroll):
			var rr := Rect2(r.position.x + 360, y0 + k * ROW_H, 360, ROW_H - 4)
			out.append(["key:" + String(actions[_scroll + k]), rr])
		out.append(["reset", Rect2(r.position.x + 20, r.end.y - 58, 200, 40)])
	out.append(["back", Rect2(r.end.x - 180, r.end.y - 58, 160, 40)])
	return out


func _hit(pos: Vector2) -> String:
	for b in _buttons():
		if (b[1] as Rect2).has_point(pos):
			return b[0]
	return ""


func _vol_of(id: String) -> float:
	return {"master": Game.vol_master, "sfx": Game.vol_sfx, "ambience": Game.vol_ambience}[id]


func _set_vol(id: String, v: float) -> void:
	v = clampf(snappedf(v, 0.05), 0.0, 1.0)
	match id:
		"master":
			Game.vol_master = v
		"sfx":
			Game.vol_sfx = v
		"ambience":
			Game.vol_ambience = v
	Game.apply_audio()


func _slider_value(id: String, x: float) -> void:
	for b in _buttons():
		if b[0] == id:
			var rr: Rect2 = b[1]
			_set_vol(id, (x - rr.position.x - 10.0) / (rr.size.x - 80.0))


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _waiting != "" and event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_ESCAPE or k.physical_keycode == KEY_ESCAPE:
			if _waiting != "pause":
				_waiting = ""
				_note = ""
				get_viewport().set_input_as_handled()
				return
		var other := Game.rebind(_waiting, k)
		_note = "%s: %s" % [Game.KEYS[_waiting][0], Game.keys_text(_waiting)] + ("   (swapped with %s)" % other if other != "" else "")
		_waiting = ""
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.is_action("pause"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if tab == "controls" and mb.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_UP]:
			_scroll += 1 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1
			get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion and _drag != "":
		_slider_value(_drag, get_local_mouse_position().x)
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if not event.pressed:
		if _drag != "":
			_drag = ""
			Game.save_settings()
		return
	var id := _hit(event.position)
	_press(id, event.position)


func _cycle(list: Array, cur, step := 1):
	var i := list.find(cur)
	return list[posmod(i + step, list.size())]


func _press(id: String, pos := Vector2.ZERO) -> void:
	_waiting = ""
	if id != "":
		Sfx.ui("ui_click", -4.0)
	match id:
		"tab_general":
			tab = "general"
			_note = ""
		"tab_controls":
			tab = "controls"
			_note = "Click a key, then press the new one (Esc cancels)"
		"back":
			close()
			return
		"reset":
			Game.reset_keys()
			_note = "Keys reset to the defaults"
		"master", "sfx", "ambience":
			_drag = id
			_slider_value(id, pos.x)
			return
		"mode":
			Game.window_mode = _cycle(["windowed", "borderless", "fullscreen"], Game.window_mode, -1 if _left_half(id, pos) else 1)
			Game.apply_display()
		"res":
			Game.resolution = _cycle(Game.RESOLUTIONS, Game.resolution, -1 if _left_half(id, pos) else 1)
			if Game.window_mode != "windowed":
				Game.window_mode = "windowed"
			Game.apply_display()
		"vsync":
			Game.vsync = not Game.vsync
			Game.apply_display()
		"aim":
			Game.aim_mode = "mouse" if Game.aim_mode == "auto" else "auto"
		_:
			if id.begins_with("key:"):
				_waiting = id.substr(4)
				_note = "Press the new key for %s (Esc cancels)" % Game.KEYS[_waiting][0]
				return
			return
	Game.save_settings()


func _left_half(id: String, pos: Vector2) -> bool:
	for b in _buttons():
		if b[0] == id:
			return pos.x < (b[1] as Rect2).get_center().x
	return false


func open() -> void:
	visible = true
	_waiting = ""
	_note = ""
	_scroll = 0


func close() -> void:
	_waiting = ""
	_drag = ""
	Game.save_settings()
	visible = false
	closed.emit()


func _text(pos: Vector2, s: String, size_px: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(_font, pos + Vector2(2, 2), s, align, width, size_px, Color(0.08, 0.04, 0.07, 0.9))
	draw_string(_font, pos, s, align, width, size_px, col)


func _box(r: Rect2, col: Color) -> void:
	draw_rect(r, C_EDGE)
	draw_rect(r.grow(-2), col)


func _draw() -> void:
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.03, 0.02, 0.04, 0.75))
	var r := _panel_rect()
	_box(r, Color("2a2230"))
	_text(r.position + Vector2(24, 40), "SETTINGS", 26, C_TEXT)
	var hover := _hit(_mouse)
	for b in _buttons():
		var id: String = b[0]
		var rr: Rect2 = b[1]
		var hv := hover == id
		if id.begins_with("tab_"):
			var on := id == "tab_" + tab
			_box(rr, C_ON if on else (C_HOVER if hv else C_CARD))
			_text(Vector2(rr.position.x, rr.position.y + 23), "General" if id == "tab_general" else "Controls", 17, C_TEXT if on else C_DIM, HORIZONTAL_ALIGNMENT_CENTER, rr.size.x)
		elif id in ["back", "reset"]:
			_box(rr, C_HOVER if hv else C_CARD)
			_text(Vector2(rr.position.x, rr.position.y + 27), "Back" if id == "back" else "Reset keys", 18, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, rr.size.x)
		elif id.begins_with("key:"):
			var action := id.substr(4)
			_text(Vector2(r.position.x + 30, rr.position.y + 23), String(Game.KEYS[action][0]), 16, C_TEXT)
			var waiting := _waiting == action
			_box(rr, Color("8a6a3a") if waiting else (C_HOVER if hv else C_CARD))
			_text(Vector2(rr.position.x, rr.position.y + 22), "press a key..." if waiting else Game.keys_text(action), 16, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, rr.size.x)
		else:
			_draw_setting(id, rr, hv, r)
	if tab == "controls":
		var n := Game.KEYS.size()
		if n > ROWS_SHOWN:
			_text(Vector2(r.end.x - 300, r.position.y + 81), "Keys %d-%d of %d - scroll for more" % [_scroll + 1, mini(_scroll + ROWS_SHOWN, n), n], 13, C_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 270)
	if _note != "":
		_text(Vector2(r.position.x + 30, r.end.y - 72), _note, 14, Color(0.95, 0.85, 0.55), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 60)


func _draw_setting(id: String, rr: Rect2, hv: bool, r: Rect2) -> void:
	var label := ""
	for row in _general_rows():
		if row[0] == id:
			label = row[1]
	_text(Vector2(r.position.x + 30, rr.position.y + 24), label, 17, C_TEXT)
	match id:
		"master", "sfx", "ambience":
			var v := _vol_of(id)
			var track := Rect2(rr.position.x + 10, rr.position.y + rr.size.y / 2.0 - 4, rr.size.x - 80, 8)
			draw_rect(track.grow(2), C_EDGE)
			draw_rect(track, C_CARD)
			draw_rect(Rect2(track.position, Vector2(track.size.x * v, track.size.y)), Color(0.85, 0.7, 0.4))
			var kx := track.position.x + track.size.x * v
			draw_rect(Rect2(kx - 6, rr.position.y + 4, 12, rr.size.y - 8), C_EDGE)
			draw_rect(Rect2(kx - 4, rr.position.y + 6, 8, rr.size.y - 12), C_TEXT if hv or _drag == id else C_DIM)
			_text(Vector2(rr.end.x - 60, rr.position.y + 24), "%d%%" % int(round(v * 100.0)), 16, C_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, 56)
		_:
			var val := ""
			match id:
				"mode":
					val = {"windowed": "Window", "borderless": "Borderless fullscreen", "fullscreen": "Fullscreen"}.get(Game.window_mode, "Window")
				"res":
					val = "%d x %d" % [Game.resolution.x, Game.resolution.y]
					if Game.window_mode != "windowed":
						val += "  (windowed only)"
				"vsync":
					val = "On" if Game.vsync else "Off"
				"aim":
					val = "Auto aim (Space shoots)" if Game.aim_mode == "auto" else "Mouse aim (click shoots)"
			_box(rr, C_HOVER if hv else C_CARD)
			if id in ["mode", "res"]:
				_text(Vector2(rr.position.x + 10, rr.position.y + 24), "<", 18, C_DIM)
				_text(Vector2(rr.end.x - 22, rr.position.y + 24), ">", 18, C_DIM)
			_text(Vector2(rr.position.x, rr.position.y + 24), val, 16, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, rr.size.x)
