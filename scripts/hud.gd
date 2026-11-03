class_name Hud
extends Control
## On-screen UI: stat bars, hotbar, ammo, inventory screen, messages, help, pause and death screens.

const UI_SCALE := 3.0
const INV_SCALE := 4.0
const INV_CELL_X := [7, 29, 51, 73, 95, 117]
const INV_CELL_Y := [12, 35, 59]
const INV_CELL_SIZE := Vector2(19, 20)
const HOT_CELL_STEP := 21.0
const HOT_CELL_SIZE := Vector2(19, 19)

var main: Node
var show_help := true
var inventory_open := false
var _font: Font
var _drag_from := -1
var _mouse := Vector2.ZERO


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func _process(_delta: float) -> void:
	if main and main.survived > 30.0 and show_help and not get_tree().paused:
		show_help = false
	_mouse = get_viewport().get_mouse_position()
	queue_redraw()


# ---------------------------------------------------------------- input

func set_inventory_open(open: bool) -> void:
	inventory_open = open
	Game.ui_open = open
	_drag_from = -1
	Input.set_default_cursor_shape(Input.CURSOR_ARROW if open else Input.CURSOR_CROSS)


func _input(event: InputEvent) -> void:
	if not inventory_open:
		return
	var p: Player = main.player
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var slot := inv_slot_at(mb.position)
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if slot >= 0 and p.inv.slots[slot] != null:
					_drag_from = slot
			elif _drag_from >= 0:
				if slot >= 0:
					p.inv.move(_drag_from, slot)
				elif not inv_rect().has_point(mb.position):
					p.drop_slot(_drag_from)
				_drag_from = -1
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and slot >= 0:
			p.use_slot(slot)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	var p: Player = main.player
	if event.is_action_pressed("fullscreen"):
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif event.is_action_pressed("help"):
		show_help = not show_help
	elif p.dead and event.is_action_pressed("reload"):
		main.restart()
	elif event.is_action_pressed("inventory") and not p.dead and not get_tree().paused:
		set_inventory_open(not inventory_open)
	elif event.is_action_pressed("pause") and inventory_open:
		set_inventory_open(false)
	elif event.is_action_pressed("pause") and not p.dead:
		get_tree().paused = not get_tree().paused
	elif get_tree().paused and event.is_action_pressed("quit"):
		get_tree().quit()


# ---------------------------------------------------------------- layout helpers

func inv_rect() -> Rect2:
	var sz := Game.tex("ui_inventory").get_size() * INV_SCALE
	var vs := get_viewport_rect().size
	return Rect2((vs - sz) / 2.0 - Vector2(0, 20), sz)


func inv_cell_rect(i: int) -> Rect2:
	var r := inv_rect()
	var cx: int = INV_CELL_X[i % 6]
	var cy: int = INV_CELL_Y[i / 6]
	return Rect2(r.position + Vector2(cx, cy) * INV_SCALE, INV_CELL_SIZE * INV_SCALE)


func inv_slot_at(pos: Vector2) -> int:
	for i in Inventory.SIZE:
		if inv_cell_rect(i).has_point(pos):
			return i
	return -1


func hotbar_rect() -> Rect2:
	var sz := Game.tex("ui_hotbar").get_size() * UI_SCALE
	var vs := get_viewport_rect().size
	return Rect2(Vector2((vs.x - sz.x) / 2.0, vs.y - sz.y - 14), sz)


func hot_cell_rect(i: int) -> Rect2:
	var r := hotbar_rect()
	return Rect2(r.position + Vector2(i * HOT_CELL_STEP, 0) * UI_SCALE, HOT_CELL_SIZE * UI_SCALE)


# ---------------------------------------------------------------- drawing helpers

func _text(pos: Vector2, s: String, size_px := 16, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	if align == HORIZONTAL_ALIGNMENT_RIGHT and width <= 0.0:
		pos.x -= _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		align = HORIZONTAL_ALIGNMENT_LEFT
		width = -1.0
	draw_string(_font, pos + Vector2(2, 2), s, align, width, size_px, Color(0.08, 0.04, 0.07, 0.85))
	draw_string(_font, pos, s, align, width, size_px, col)


func _tex(t: Texture2D, pos: Vector2, scale_px: float, modulate := Color.WHITE) -> void:
	draw_texture_rect(t, Rect2(pos.round(), t.get_size() * scale_px), false, modulate)


## Pixel-art stat bar: fill drawn under the frame, cropped to the value.
func _stat_bar(pos: Vector2, frame: Texture2D, fill: Texture2D, fill_at: Vector2, value: float, low: bool) -> void:
	var v := clampf(value / 100.0, 0.0, 1.0)
	var fsz := fill.get_size()
	var src := Rect2(Vector2.ZERO, Vector2(ceilf(fsz.x * v), fsz.y))
	var blink := low and fmod(Time.get_ticks_msec() / 250.0, 2.0) < 1.0
	var mod := Color(1.4, 1.4, 1.4) if blink else Color.WHITE
	if src.size.x > 0:
		draw_texture_rect_region(fill, Rect2(pos + fill_at * UI_SCALE, src.size * UI_SCALE), src, mod)
	_tex(frame, pos, UI_SCALE)


func _item_icon(item: Dictionary, cell: Rect2, scale_px: float) -> void:
	var t := Items.icon(item["id"])
	var sz := t.get_size() * scale_px
	_tex(t, cell.get_center() - sz / 2.0, scale_px)
	if int(item["count"]) > 1:
		_text(cell.end - Vector2(6, 6), str(item["count"]), 14, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 0)
	elif item.has("mag"):
		_text(cell.end - Vector2(6, 6), str(item["mag"]), 12, Color(1, 0.9, 0.6), HORIZONTAL_ALIGNMENT_RIGHT, 0)


# ---------------------------------------------------------------- draw

func _draw() -> void:
	if main == null or main.player == null:
		return
	var p: Player = main.player
	var vs := get_viewport_rect().size
	var st := int(main.survived)

	# Stat bars (bottom-left)
	var bx := 18.0
	var by := vs.y - 150.0
	_stat_bar(Vector2(bx, by), Game.tex("ui_hp_bar"), Game.tex("ui_hp_fill"), Vector2(11, 4), p.health, p.health < 25.0)
	_stat_bar(Vector2(bx + 9, by + 44), Game.tex("ui_hunger_bar"), Game.tex("ui_hunger_fill"), Vector2(11, 6), p.hunger, p.hunger < 20.0)
	_stat_bar(Vector2(bx, by + 92), Game.thirst_bar(), Game.thirst_fill(), Vector2(11, 4), p.thirst, p.thirst < 20.0)
	if p.bleeding:
		_tex(Game.tex("blood_2"), Vector2(bx + 176, by + 4), 3.0)
		_text(Vector2(bx + 210, by + 26), "Bleeding [H]", 15, Color(1, 0.4, 0.4))

	# Hotbar (bottom-centre)
	_tex(Game.tex("ui_hotbar"), hotbar_rect().position, UI_SCALE)
	for i in Inventory.HOTBAR:
		var cell := hot_cell_rect(i)
		var s = p.inv.slots[i]
		if s != null and is_same(s, p.equipped):
			_tex(Game.tex("ui_cell_chosen"), cell.position, UI_SCALE)
		if s != null and not (inventory_open and _drag_from == i):
			_item_icon(s, cell, 2.0)
		_text(cell.position + Vector2(7, 17), str(i + 1), 12, Color(0.85, 0.8, 0.75, 0.8))

	# Weapon + ammo (bottom-right)
	var w := p.weapon()
	var wx := vs.x - 24.0
	var wy := vs.y - 40.0
	_text(Vector2(wx, wy), w["name"], 20, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 0)
	if not w["melee"]:
		var mag := int(p.equipped["mag"])
		var full := Game.tex(w["bullet_ui"])
		var empty := Game.tex(w["bullet_ui"] + "_empty")
		var step := full.get_width() * 2.0 + 2.0
		var n := int(w["mag"])
		var start := wx - n * step - 70.0
		for i in n:
			_tex(full if i < mag else empty, Vector2(start + i * step, wy - 58), 2.0)
		_text(Vector2(wx, wy - 32), "+%d" % p.inv.count_of(w["ammo"]), 18, Color(0.95, 0.85, 0.6), HORIZONTAL_ALIGNMENT_RIGHT, 0)
		if p.reloading:
			var rr := Rect2(Vector2(start, wy - 16), Vector2(n * step, 6))
			draw_rect(rr.grow(2), Color(0.1, 0.05, 0.08))
			draw_rect(Rect2(rr.position, Vector2(rr.size.x * p.reload_progress, rr.size.y)), Color(0.9, 0.8, 0.5))

	# Clock / stats (top-right)
	_text(Vector2(vs.x - 20, 32), "Day %d  %s" % [main.day, main.clock_text()], 20, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 0)
	_text(Vector2(vs.x - 20, 54), "Survived %d:%02d   Kills %d" % [st / 60, st % 60, main.kills], 14, Color(0.85, 0.85, 0.85), HORIZONTAL_ALIGNMENT_RIGHT, 0)

	# Search prompt above the player
	if p.nearest_loot and not p.dead and not inventory_open:
		var sp := p.get_global_transform_with_canvas().origin
		_text(sp + Vector2(-60, -50), "[E] Search", 15, Color(1, 0.95, 0.6), HORIZONTAL_ALIGNMENT_CENTER, 120)

	# Message
	if p.message_t > 0.0:
		_text(Vector2(0, vs.y - 170), p.message, 18, Color(1, 1, 1, clampf(p.message_t, 0, 1)), HORIZONTAL_ALIGNMENT_CENTER, vs.x)

	# Help
	if show_help and not inventory_open:
		var lines := [
			"WASD move   Shift sprint   Mouse aim   Left click attack",
			"E search   R reload   1-6 hotbar   Tab inventory",
			"F eat   G drink   H bandage",
			"Esc pause   F11 fullscreen   F1 hide help",
		]
		draw_rect(Rect2(14, 14, 480, 104), Color(0.08, 0.04, 0.07, 0.6))
		for i in lines.size():
			_text(Vector2(24, 38 + i * 22), lines[i], 15)
	elif not inventory_open:
		_text(Vector2(20, 28), "F1 help", 13, Color(0.8, 0.8, 0.8))

	if inventory_open:
		_draw_inventory(p, vs)

	# Pause
	if get_tree().paused:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.55))
		_text(Vector2(0, vs.y * 0.45), "PAUSED", 48, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		_text(Vector2(0, vs.y * 0.45 + 40), "Esc resume   Q quit", 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, vs.x)

	# Death
	if p.dead:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.25, 0, 0, 0.6))
		_text(Vector2(0, vs.y * 0.42), "YOU DIED", 56, Color(1, 0.85, 0.85), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		_text(Vector2(0, vs.y * 0.42 + 44), "Survived %d:%02d   Day %d   Kills %d" % [st / 60, st % 60, main.day, main.kills], 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		_text(Vector2(0, vs.y * 0.42 + 80), "Press R to try again", 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, vs.x)


func _draw_inventory(p: Player, vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.05, 0.02, 0.05, 0.55))
	var r := inv_rect()
	_tex(Game.tex("ui_inventory"), r.position, INV_SCALE)
	_text(Vector2(r.position.x, r.position.y - 14), "INVENTORY", 24, Color(0.95, 0.9, 0.82))
	_text(Vector2(r.end.x, r.position.y - 14), "Tab to close", 14, Color(0.8, 0.75, 0.7), HORIZONTAL_ALIGNMENT_RIGHT, 0)
	_text(Vector2(r.position.x + 28, r.position.y + 40), "HOTBAR", 11, Color(0.8, 0.75, 0.7, 0.8))

	var hover := inv_slot_at(_mouse)
	for i in Inventory.SIZE:
		var cell := inv_cell_rect(i)
		var s = p.inv.slots[i]
		if s != null and is_same(s, p.equipped):
			_tex(Game.tex("ui_cell_chosen"), cell.position, INV_SCALE)
		elif i == hover:
			draw_rect(cell.grow(-8), Color(1, 1, 1, 0.08))
		if s != null and i != _drag_from:
			_item_icon(s, cell, 3.0)

	_text(Vector2(0, r.end.y + 30), "Drag to move   -   Right-click to use / equip   -   Drag outside to drop", 15, Color(0.85, 0.8, 0.75), HORIZONTAL_ALIGNMENT_CENTER, vs.x)

	# Tooltip
	if hover >= 0 and p.inv.slots[hover] != null and _drag_from < 0:
		var s: Dictionary = p.inv.slots[hover]
		var tip := Items.name_of(s["id"])
		if s.has("mag"):
			tip += "  (%d loaded)" % s["mag"]
		elif int(s["count"]) > 1:
			tip += "  x%d" % s["count"]
		var tw := _font.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var tp := _mouse + Vector2(18, 18)
		draw_rect(Rect2(tp, Vector2(tw + 16, 26)), Color(0.12, 0.07, 0.1, 0.95))
		draw_rect(Rect2(tp, Vector2(tw + 16, 26)), Color(0.75, 0.68, 0.6), false, 2.0)
		_text(tp + Vector2(8, 19), tip, 15)

	# Dragged item follows the mouse
	if _drag_from >= 0 and p.inv.slots[_drag_from] != null:
		_item_icon(p.inv.slots[_drag_from], Rect2(_mouse - Vector2(30, 30), Vector2(60, 60)), 3.0)
