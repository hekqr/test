class_name Hud
extends Control
## On-screen UI: stat bars, hands + weapon slots, ammo, action button, inventory screen,
## messages, help, pause and death screens.

const UI_SCALE := 3.0
const CELL_SCALE := 4.0
const POCKET_COLS := 8
const SLOT_NAMES := {"primary": "PRIMARY", "secondary": "SECONDARY", "melee": "MELEE"}
const SLOT_KEYS := {"primary": "1", "secondary": "2", "melee": "3"}

# Pixel-panel palette (matches the art packs)
const C_EDGE := Color("1a1016")
const C_FILL := Color("3b2f3a")
const C_LIGHT := Color("6b5a66")
const C_TEXT := Color(0.95, 0.9, 0.82)
const C_DIM := Color(0.8, 0.75, 0.7)

var main: Node
var show_help := true
var inventory_open := false
var _font: Font
var _mouse := Vector2.ZERO
var _btn_down := false
# Drag source: {"from": "hands" | "pocket" | "slot", "i": int, "slot": String}
var _drag := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func _process(_delta: float) -> void:
	if main and main.survived > 30.0 and show_help and not get_tree().paused:
		show_help = false
	_mouse = get_viewport().get_mouse_position()
	queue_redraw()


# ---------------------------------------------------------------- layout

func cell_size(scale_px := CELL_SCALE) -> Vector2:
	return Game.tex("ui_cell").get_size() * scale_px


func hands_rect() -> Rect2:
	return Rect2(Vector2(150, 140), cell_size())


func slot_rect(slot: String) -> Rect2:
	var i := Inventory.WEAPON_SLOTS.find(slot)
	return Rect2(Vector2(150, 272 + i * 102), cell_size())


func pockets_rect() -> Rect2:
	var p: Player = main.player
	var n := p.inv.pockets.size() + 1 # always one empty slot at the end
	var rows := ceili(float(n) / POCKET_COLS)
	var cs := cell_size()
	return Rect2(Vector2(330, 140), Vector2(POCKET_COLS * (cs.x + 10) + 30, rows * (cs.y + 10) + 30))


func pocket_cell_rect(i: int) -> Rect2:
	var r := pockets_rect()
	var cs := cell_size()
	return Rect2(r.position + Vector2(20 + (i % POCKET_COLS) * (cs.x + 10), 20 + (i / POCKET_COLS) * (cs.y + 10)), cs)


func pocket_at(pos: Vector2) -> int:
	var p: Player = main.player
	for i in p.inv.pockets.size() + 1:
		if pocket_cell_rect(i).has_point(pos):
			return i
	return -1


func slot_at(pos: Vector2) -> String:
	for s in Inventory.WEAPON_SLOTS:
		if slot_rect(s).has_point(pos):
			return s
	return ""


func action_rect() -> Rect2:
	var vs := get_viewport_rect().size
	var sz := Game.tex("ui_button").get_size() * UI_SCALE
	return Rect2(Vector2((vs.x - sz.x) / 2.0, vs.y - 190), sz)


func _in_inventory_area(pos: Vector2) -> bool:
	return pockets_rect().has_point(pos) or hands_rect().has_point(pos) or slot_at(pos) != ""


# ---------------------------------------------------------------- input

func set_inventory_open(open: bool) -> void:
	inventory_open = open
	Game.ui_open = open
	_drag = {}
	Input.set_default_cursor_shape(Input.CURSOR_ARROW if open else Input.CURSOR_CROSS)


func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	var p: Player = main.player
	if not inventory_open:
		# Action button (search / pick up)
		if mb.button_index == MOUSE_BUTTON_LEFT and p.nearest_loot and not p.dead and action_rect().has_point(mb.position):
			if mb.pressed:
				_btn_down = true
				Game.click_used = true
			elif _btn_down:
				_btn_down = false
				p.interact()
			get_viewport().set_input_as_handled()
		return

	var pocket := pocket_at(mb.position)
	var slot := slot_at(mb.position)
	var on_hands := hands_rect().has_point(mb.position)
	var inv := p.inv
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			if on_hands and inv.hands != null:
				_drag = {"from": "hands"}
			elif pocket >= 0 and pocket < inv.pockets.size():
				_drag = {"from": "pocket", "i": pocket}
			elif slot != "" and inv.weapons[slot] != null:
				_drag = {"from": "slot", "slot": slot}
		elif not _drag.is_empty():
			_drop_drag(p, mb.position, slot, on_hands)
			_drag = {}
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		if on_hands:
			p.holster()
		elif slot != "":
			p.switch_weapon(slot)
		elif pocket >= 0 and pocket < inv.pockets.size():
			p.use_pocket(pocket)
	get_viewport().set_input_as_handled()


func _drop_drag(p: Player, pos: Vector2, slot: String, on_hands: bool) -> void:
	var inv := p.inv
	var from: String = _drag["from"]
	var err := ""
	if not _in_inventory_area(pos):
		match from:
			"hands":
				p.drop(true)
			"pocket":
				p.drop(false, _drag["i"])
			"slot":
				p.drop_slot(_drag["slot"])
		return
	match from:
		"pocket":
			if on_hands:
				p.hold_pocket(_drag["i"])
			elif slot != "":
				err = inv.to_slot(false, _drag["i"])
		"hands":
			if slot != "":
				err = inv.to_slot(true)
			elif pockets_rect().has_point(pos):
				err = _hands_to_pockets(inv)
		"slot":
			if on_hands:
				p.switch_weapon(_drag["slot"])
			elif pockets_rect().has_point(pos):
				var w: Dictionary = inv.weapons[_drag["slot"]]
				if inv.fits(w["id"]):
					inv.take_slot(_drag["slot"])
					inv.add_stack(w)
				else:
					err = "No room in pockets"
	if err != "":
		p.say(err)


func _hands_to_pockets(inv: Inventory) -> String:
	if not inv.fits(inv.hands["id"]):
		return "No room in pockets"
	inv.add_stack(inv.take_hands())
	return ""


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
		main.quit_to_menu()
	elif p.dead and event.is_action_pressed("pause"):
		main.quit_to_menu()


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


func _panel(r: Rect2) -> void:
	draw_rect(r, C_EDGE)
	draw_rect(r.grow(-4), C_LIGHT)
	draw_rect(r.grow(-6), C_FILL)


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


func _item_icon(item: Dictionary, cell: Rect2, scale_px: float, modulate := Color.WHITE) -> void:
	var t := Items.icon(item["id"])
	var sz := t.get_size() * scale_px
	_tex(t, cell.get_center() - sz / 2.0, scale_px, modulate)
	if int(item["count"]) > 1:
		_text(cell.end - Vector2(6, 6), str(item["count"]), 14, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 0)
	elif item.has("mag"):
		_text(cell.end - Vector2(6, 6), str(item["mag"]), 12, Color(1, 0.9, 0.6), HORIZONTAL_ALIGNMENT_RIGHT, 0)


func _cell(r: Rect2, scale_px: float, chosen := false) -> void:
	_tex(Game.tex("ui_cell_chosen" if chosen else "ui_cell"), r.position, scale_px)


## The item that belongs to a weapon slot: the slot's weapon, or the hands weapon taken from it.
func _slot_item(p: Player, slot: String) -> Variant:
	if p.inv.weapons[slot] != null:
		return p.inv.weapons[slot]
	if p.inv.hands != null and Items.slot_of(p.inv.hands["id"]) == slot:
		return p.inv.hands
	return null


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

	# Hands + weapon slots (bottom-centre)
	var cs := cell_size(UI_SCALE)
	var hx := vs.x / 2.0 - 150.0
	var hy := vs.y - cs.y - 12.0
	var hr := Rect2(Vector2(hx, hy), cs)
	_cell(hr, UI_SCALE, p.inv.hands != null)
	if p.inv.hands != null:
		_item_icon(p.inv.hands, hr, 2.0)
	_text(hr.position + Vector2(0, -6), "HANDS", 12, C_DIM)
	for i in 3:
		var slot: String = Inventory.WEAPON_SLOTS[i]
		var r := Rect2(Vector2(hr.end.x + 18 + i * (cs.x * 0.75 + 6), hy + cs.y * 0.25), cs * 0.75)
		var it = _slot_item(p, slot)
		var active: bool = it != null and p.inv.in_hands(it)
		_cell(r, UI_SCALE * 0.75, active)
		if it != null:
			_item_icon(it, r, 1.5, Color.WHITE if active else Color(1, 1, 1, 0.6))
		_text(r.position + Vector2(5, 14), SLOT_KEYS[slot], 11, C_DIM)
	_text(Vector2(hr.end.x + 18, hy + 6), "%d space left" % p.inv.space_free(), 13, C_DIM)

	# Weapon + ammo (bottom-right)
	var w := p.weapon()
	var wx := vs.x - 24.0
	var wy := vs.y - 40.0
	_text(Vector2(wx, wy), w["name"], 20, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 0)
	if not w["melee"]:
		var mag := int(p.gun()["mag"])
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
			draw_rect(rr.grow(2), C_EDGE)
			draw_rect(Rect2(rr.position, Vector2(rr.size.x * p.reload_progress, rr.size.y)), Color(0.9, 0.8, 0.5))

	# Clock / stats (top-right)
	_text(Vector2(vs.x - 20, 32), "Day %d  %s" % [main.day, main.clock_text()], 20, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 0)
	_text(Vector2(vs.x - 20, 54), "Survived %d:%02d   Kills %d" % [st / 60, st % 60, main.kills], 14, Color(0.85, 0.85, 0.85), HORIZONTAL_ALIGNMENT_RIGHT, 0)

	# Action button: appears automatically near containers / items
	if p.nearest_loot and not p.dead and not inventory_open:
		var ar := action_rect()
		var pressed := _btn_down and ar.has_point(_mouse)
		_tex(Game.tex("ui_button_pressed" if pressed else "ui_button"), ar.position + Vector2(0, 6 if pressed else 0), UI_SCALE)
		var label := p.nearest_loot.label()
		_text(Vector2(ar.position.x, ar.position.y + (44 if pressed else 38)), label, 17, C_EDGE, HORIZONTAL_ALIGNMENT_CENTER, ar.size.x)
		_text(Vector2(ar.end.x + 8, ar.position.y + 38), "[E]", 14, C_DIM)

	# Help
	if show_help and not inventory_open:
		var lines := [
			"WASD move   Shift sprint   Melee is automatic   Click to shoot",
			"E / button: search, pick up   R reload   X empty hands",
			"1 / 2 / 3 or wheel: primary / secondary / melee   Tab inventory",
			"F eat   G drink   H bandage   Esc pause   F1 hide help",
		]
		draw_rect(Rect2(14, 14, 540, 104), Color(0.08, 0.04, 0.07, 0.6))
		for i in lines.size():
			_text(Vector2(24, 38 + i * 22), lines[i], 15)
	elif not inventory_open:
		_text(Vector2(20, 28), "F1 help", 13, Color(0.8, 0.8, 0.8))

	if inventory_open:
		_draw_inventory(p, vs)

	# Message
	if p.message_t > 0.0:
		var my := 100.0 if inventory_open else vs.y - 245.0
		_text(Vector2(0, my), p.message, 18, Color(1, 1, 1, clampf(p.message_t, 0, 1)), HORIZONTAL_ALIGNMENT_CENTER, vs.x)

	# Pause
	if get_tree().paused:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.55))
		_text(Vector2(0, vs.y * 0.45), "PAUSED", 48, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		_text(Vector2(0, vs.y * 0.45 + 40), "Esc resume   Q save & quit to menu", 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		_text(Vector2(0, vs.y * 0.45 + 66), "The game saves automatically", 14, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, vs.x)

	# Death
	if p.dead:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.25, 0, 0, 0.6))
		_text(Vector2(0, vs.y * 0.42), "YOU DIED", 56, Color(1, 0.85, 0.85), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		_text(Vector2(0, vs.y * 0.42 + 44), "Survived %d:%02d   Day %d   Kills %d" % [st / 60, st % 60, main.day, main.kills], 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		_text(Vector2(0, vs.y * 0.42 + 80), "R  new survivor (new world)      Esc  main menu", 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, vs.x)


func _draw_inventory(p: Player, vs: Vector2) -> void:
	var inv := p.inv
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.05, 0.02, 0.05, 0.6))
	var drag_item = _dragged_item(p)

	# Left column: hands + weapon slots
	_panel(Rect2(130, 100, 120, 470))
	var hr := hands_rect()
	_text(Vector2(hr.position.x - 8, hr.position.y - 12), "HANDS", 16, C_TEXT)
	_cell(hr, CELL_SCALE, inv.hands != null)
	if inv.hands != null and not is_same(drag_item, inv.hands):
		_item_icon(inv.hands, hr, 3.0)
	for slot in Inventory.WEAPON_SLOTS:
		var r := slot_rect(slot)
		_text(Vector2(r.position.x - 8, r.position.y - 10), "%s %s" % [SLOT_KEYS[slot], SLOT_NAMES[slot]], 12, C_DIM)
		_cell(r, CELL_SCALE)
		var it = inv.weapons[slot]
		if it != null and not is_same(drag_item, it):
			_item_icon(it, r, 3.0)
		elif it == null and inv.hands != null and Items.slot_of(inv.hands["id"]) == slot:
			_text(Vector2(r.position.x, r.get_center().y + 6), "in hands", 12, Color(0.75, 0.7, 0.65, 0.7), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)

	# Pockets: one cell per item + always one empty cell at the end
	var pr := pockets_rect()
	_panel(pr)
	_text(Vector2(pr.position.x, pr.position.y - 14), "POCKETS", 24, C_TEXT)
	var left := inv.space_free()
	_text(Vector2(pr.end.x, pr.position.y - 14), "%d / %d space left" % [left, Inventory.CAPACITY], 18, C_TEXT if left > 0 else Color(1, 0.5, 0.45), HORIZONTAL_ALIGNMENT_RIGHT, 0)
	var hover := pocket_at(_mouse)
	for i in inv.pockets.size() + 1:
		var cell := pocket_cell_rect(i)
		_cell(cell, CELL_SCALE)
		if i < inv.pockets.size():
			if i == hover and _drag.is_empty():
				draw_rect(cell.grow(-8), Color(1, 1, 1, 0.08))
			if not is_same(drag_item, inv.pockets[i]):
				_item_icon(inv.pockets[i], cell, 3.0)
				_text(cell.position + Vector2(8, 18), str(Items.size_of(inv.pockets[i]["id"])), 11, Color(0.8, 0.75, 0.7, 0.7))
	_text(Vector2(0, vs.y - 40), "Right-click: use / hold / equip   -   Drag between hands, slots and pockets   -   Drag outside to drop   -   Tab to close", 14, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, vs.x)

	# Tooltip
	var tip_item = null
	if _drag.is_empty():
		if hover >= 0 and hover < inv.pockets.size():
			tip_item = inv.pockets[hover]
		elif hr.has_point(_mouse):
			tip_item = inv.hands
		elif slot_at(_mouse) != "":
			tip_item = inv.weapons[slot_at(_mouse)]
	if tip_item != null:
		var s: Dictionary = tip_item
		var tip := "%s   size %d" % [Items.name_of(s["id"]), Items.size_of(s["id"])]
		if s.has("mag"):
			tip += "   %d loaded" % s["mag"]
		elif int(s["count"]) > 1:
			tip += "   x%d / %d" % [s["count"], Items.max_stack(s["id"])]
		var tw := _font.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var tp := _mouse + Vector2(18, 18)
		draw_rect(Rect2(tp, Vector2(tw + 16, 26)), C_EDGE)
		draw_rect(Rect2(tp + Vector2(2, 2), Vector2(tw + 12, 22)), C_FILL)
		_text(tp + Vector2(8, 19), tip, 15)

	if drag_item != null:
		_item_icon(drag_item, Rect2(_mouse - Vector2(30, 30), Vector2(60, 60)), 3.0)


func _dragged_item(p: Player) -> Variant:
	if _drag.is_empty():
		return null
	match _drag["from"]:
		"hands":
			return p.inv.hands
		"pocket":
			return p.inv.pockets[_drag["i"]] if _drag["i"] < p.inv.pockets.size() else null
		"slot":
			return p.inv.weapons[_drag["slot"]]
	return null
