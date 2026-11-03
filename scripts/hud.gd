class_name Hud
extends Control
## On-screen UI: stat bars, weapon slots, ammo, action button, inventory screen,
## messages, help, pause and death screens.
##
## Inventory screen: NEARBY (container / ground) | STORAGE (cards for worn clothing + backpack) | GEAR slots.

const UI_SCALE := 3.0
const CELL := 3.0 # inventory cell scale (19x20 px -> 57x60)
const STEP := Vector2(64, 66)
const GEAR_GRID := [
	["head", "armour", "back"],
	["coat", "shirt", "pants"],
	["boots", "hands", ""],
	["primary", "secondary", "melee"],
]
const GEAR_NAMES := {
	"head": "HEAD", "armour": "ARMOUR", "back": "BACK", "coat": "COAT", "shirt": "SHIRT",
	"pants": "PANTS", "boots": "BOOTS", "hands": "HANDS", "primary": "1 MAIN",
	"secondary": "2 SECONDARY", "melee": "3 MELEE",
}
const SLOT_KEYS := {"primary": "1", "secondary": "2", "melee": "3"}

# Pixel-panel palette (matches the art packs)
const C_EDGE := Color("1a1016")
const C_FILL := Color("3b2f3a")
const C_CARD := Color("4a3d48")
const C_LIGHT := Color("6b5a66")
const C_TEXT := Color(0.95, 0.9, 0.82)
const C_DIM := Color(0.8, 0.75, 0.7)

const NEAR_RECT := Rect2(16, 70, 284, 580)
const STORE_RECT := Rect2(312, 70, 560, 580)
const GEAR_RECT := Rect2(884, 70, 380, 580)

var main: Node
var show_help := true
var inventory_open := false
var _font: Font
var _mouse := Vector2.ZERO
var _btn_down := false
var _drag := {} # location being dragged


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func _process(_delta: float) -> void:
	if main and main.survived > 30.0 and show_help and not get_tree().paused:
		show_help = false
	if Game.open_inventory:
		Game.open_inventory = false
		set_inventory_open(true)
	_mouse = get_viewport().get_mouse_position()
	queue_redraw()


# ---------------------------------------------------------------- layout

func cell_size() -> Vector2:
	return Game.tex("ui_cell").get_size() * CELL


func near_cell(i: int) -> Rect2:
	return Rect2(NEAR_RECT.position + Vector2(14 + (i % 4) * STEP.x, 44 + (i / 4) * STEP.y), cell_size())


func take_all_rect() -> Rect2:
	var sz := Game.tex("ui_button").get_size() * 2.0
	return Rect2(Vector2(NEAR_RECT.get_center().x - sz.x / 2.0, NEAR_RECT.end.y - sz.y - 12), sz)


## Storage cards: [[owner_slot, card_rect], ...]
func storage_cards() -> Array:
	var p: Player = main.player
	var out := []
	var x := STORE_RECT.position.x + 12
	var y := STORE_RECT.position.y + 44
	var row_h := 0.0
	for s in Inventory.STORAGE:
		var g = p.inv.gear[s]
		if g == null or g["cargo"].size() == 0:
			continue
		var n: int = g["cargo"].size()
		var cols := mini(n, 8)
		var w := maxf(cols, 3) * STEP.x + 16
		var h := 34 + ceili(float(n) / 8) * STEP.y + 6
		if x + w > STORE_RECT.end.x - 8:
			x = STORE_RECT.position.x + 12
			y += row_h + 10
			row_h = 0.0
		out.append([s, Rect2(x, y, w, h)])
		x += w + 10
		row_h = maxf(row_h, h)
	return out


func cargo_cell(card: Rect2, i: int) -> Rect2:
	return Rect2(card.position + Vector2(8 + (i % 8) * STEP.x, 34 + (i / 8) * STEP.y), cell_size())


func gear_cell(slot: String) -> Rect2:
	for r in GEAR_GRID.size():
		var c: int = GEAR_GRID[r].find(slot)
		if c >= 0:
			return Rect2(GEAR_RECT.position + Vector2(30 + c * 120, 62 + r * 128), cell_size())
	return Rect2()


func action_rect() -> Rect2:
	var vs := get_viewport_rect().size
	var sz := Game.tex("ui_button").get_size() * UI_SCALE
	return Rect2(Vector2((vs.x - sz.x) / 2.0, vs.y - 190), sz)


## Inventory location under the mouse, or {}.
func loc_at(pos: Vector2) -> Dictionary:
	var inv: Inventory = main.player.inv
	for s in Inventory.GEAR:
		if gear_cell(s).has_point(pos):
			return Inventory.gear_loc(s)
	for card in storage_cards():
		var n: int = inv.gear[card[0]]["cargo"].size()
		for i in n:
			if cargo_cell(card[1], i).has_point(pos):
				return Inventory.cargo_loc(card[0], i)
	var near_n: int = inv.near.contents.size() + 1 if inv.near else 1
	for i in near_n:
		if near_cell(i).has_point(pos):
			return Inventory.near_loc(i)
	return {}


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

	var inv := p.inv
	var loc := loc_at(mb.position)
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			if inv.near and not inv.near.contents.is_empty() and take_all_rect().has_point(mb.position):
				p.say(inv.near.search(p))
			elif not loc.is_empty() and inv.get_at(loc) != null:
				_drag = loc
		elif not _drag.is_empty():
			_drop_drag(p, mb.position, loc)
			_drag = {}
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and not loc.is_empty():
		p.quick_use(loc)
	get_viewport().set_input_as_handled()


func _drop_drag(p: Player, pos: Vector2, loc: Dictionary) -> void:
	var inv := p.inv
	if loc.is_empty():
		if NEAR_RECT.has_point(pos) and _drag["t"] != "near":
			if inv.near:
				loc = Inventory.near_loc(inv.near.contents.size())
			else:
				p.drop(_drag) # starts a new pile on the ground
				return
		elif not (STORE_RECT.has_point(pos) or GEAR_RECT.has_point(pos) or NEAR_RECT.has_point(pos)):
			p.drop(_drag) # outside every panel: drop on the ground
			return
		else:
			return
	var err := inv.move(_drag, loc)
	if err != "":
		p.say(err)


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


func _panel(r: Rect2, fill := C_FILL) -> void:
	draw_rect(r, C_EDGE)
	draw_rect(r.grow(-4), C_LIGHT)
	draw_rect(r.grow(-6), fill)


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


## Draws the item at loc into a cell (skipping it while it's being dragged).
func _cell_item(inv: Inventory, loc: Dictionary, r: Rect2, chosen := false) -> void:
	_cell(r, CELL, chosen)
	var it = inv.get_at(loc)
	if it == null:
		return
	if r.has_point(_mouse) and _drag.is_empty():
		draw_rect(r.grow(-8), Color(1, 1, 1, 0.08))
	if not _drag.is_empty() and _drag == loc:
		return
	_item_icon(it, r, 2.5)


func _cond_text(it: Dictionary) -> String:
	return "%d%%" % int(round(float(it.get("cond", 100.0))))


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

	# Weapon slots 1 / 2 / 3 (bottom-centre)
	var cs := Game.tex("ui_cell").get_size() * UI_SCALE
	var hx := vs.x / 2.0 - cs.x * 1.5 - 8
	var hy := vs.y - cs.y - 12.0
	for i in (0 if inventory_open else 3):
		var slot: String = Inventory.WEAPON_SLOTS[i]
		var r := Rect2(Vector2(hx + i * (cs.x + 8), hy), cs)
		var it = p.inv.gear[slot]
		var active := p.inv.active == slot
		_cell(r, UI_SCALE, active)
		if it != null:
			_item_icon(it, r, 2.0, Color.WHITE if active else Color(1, 1, 1, 0.55))
		_text(r.position + Vector2(7, 17), SLOT_KEYS[slot], 12, C_DIM)
	if not inventory_open:
		_text(Vector2(hx + 3 * (cs.x + 8) + 6, hy + 36), "%d free slots" % p.inv.free_slots(), 13, C_DIM)

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
		_text(Vector2(ar.position.x, ar.position.y + (44 if pressed else 38)), label, 16, C_EDGE, HORIZONTAL_ALIGNMENT_CENTER, ar.size.x)
		_text(Vector2(ar.end.x + 8, ar.position.y + 38), "[E]", 14, C_DIM)

	# Help
	if show_help and not inventory_open:
		var lines := [
			"WASD move   Shift sprint   Melee is automatic   Click to shoot",
			"E / button: search, pick up   R reload   X lower weapon",
			"1 / 2 / 3 or wheel: main / secondary / melee   Tab inventory",
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
		var my := 52.0 if inventory_open else vs.y - 245.0
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
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.05, 0.02, 0.05, 0.65))

	# ---- NEARBY: container / ground
	_panel(NEAR_RECT)
	var near_title := inv.near.title().to_upper() if inv.near else "GROUND"
	_text(NEAR_RECT.position + Vector2(14, 30), near_title, 20, C_TEXT)
	var near_n: int = inv.near.contents.size() if inv.near else 0
	for i in near_n + 1:
		var r := near_cell(i)
		if r.end.y > take_all_rect().position.y - 6:
			break
		_cell_item(inv, Inventory.near_loc(i), r)
	if near_n == 0:
		_text(Vector2(NEAR_RECT.position.x, near_cell(4).position.y + 30), "Drag items here to drop them", 13, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, NEAR_RECT.size.x)
	else:
		var tr := take_all_rect()
		_tex(Game.tex("ui_button"), tr.position, 2.0)
		_text(Vector2(tr.position.x, tr.position.y + 27), "Take all", 15, C_EDGE, HORIZONTAL_ALIGNMENT_CENTER, tr.size.x)

	# ---- STORAGE: one card per worn clothing item / backpack
	_panel(STORE_RECT)
	_text(STORE_RECT.position + Vector2(14, 30), "STORAGE", 20, C_TEXT)
	_text(Vector2(STORE_RECT.end.x - 14, STORE_RECT.position.y + 30), "%d free slots" % inv.free_slots(), 15, C_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 0)
	var cards := storage_cards()
	if cards.is_empty():
		_text(Vector2(STORE_RECT.position.x, STORE_RECT.get_center().y), "Wear clothes or a backpack to carry items", 15, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, STORE_RECT.size.x)
	for card in cards:
		var s: String = card[0]
		var cr: Rect2 = card[1]
		var g: Dictionary = inv.gear[s]
		draw_rect(cr, C_EDGE)
		draw_rect(cr.grow(-2), C_CARD)
		_tex(Items.icon(g["id"]), cr.position + Vector2(8, 6), 1.5)
		_text(cr.position + Vector2(34, 22), Items.name_of(g["id"]), 14, C_TEXT)
		_text(Vector2(cr.end.x - 8, cr.position.y + 22), _cond_text(g), 12, C_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 0)
		for i in g["cargo"].size():
			_cell_item(inv, Inventory.cargo_loc(s, i), cargo_cell(cr, i))

	# ---- GEAR slots
	_panel(GEAR_RECT)
	_text(GEAR_RECT.position + Vector2(14, 30), "GEAR", 20, C_TEXT)
	var prot := int(round(minf(inv.protection(), 0.6) * 100))
	_text(Vector2(GEAR_RECT.end.x - 14, GEAR_RECT.position.y + 30), "Protection %d%%" % prot, 14, C_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 0)
	for s in Inventory.GEAR:
		var r := gear_cell(s)
		_text(Vector2(r.position.x - 20, r.position.y - 8), GEAR_NAMES[s], 12, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x + 40)
		_cell_item(inv, Inventory.gear_loc(s), r, inv.active == s)
		var it = inv.gear[s]
		if it != null and it.has("cond"):
			_text(Vector2(r.position.x, r.end.y + 14), _cond_text(it), 11, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)

	_text(Vector2(0, vs.y - 30), "Drag to move   -   Right-click: use / wear / equip / take   -   Drag outside to drop   -   Tab to close", 14, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, vs.x)

	# Tooltip
	if _drag.is_empty():
		var hover := loc_at(_mouse)
		var tip_item = inv.get_at(hover) if not hover.is_empty() else null
		if tip_item != null:
			var d: Dictionary = tip_item
			var tip := Items.name_of(d["id"])
			if Items.is_clothing(d["id"]):
				tip += "   %d slots   %s" % [Items.cargo_of(d["id"]), _cond_text(d)]
				if Items.DEFS[d["id"]].has("protect"):
					tip += "   protects %d%%" % int(Items.DEFS[d["id"]]["protect"] * 100)
			elif d.has("mag"):
				tip += "   %d loaded" % d["mag"]
			elif int(d["count"]) > 1:
				tip += "   x%d / %d" % [d["count"], Items.max_stack(d["id"])]
			var tw := _font.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			var tp := _mouse + Vector2(18, 18)
			if tp.x + tw + 16 > vs.x:
				tp.x = vs.x - tw - 20
			draw_rect(Rect2(tp, Vector2(tw + 16, 26)), C_EDGE)
			draw_rect(Rect2(tp + Vector2(2, 2), Vector2(tw + 12, 22)), C_FILL)
			_text(tp + Vector2(8, 19), tip, 15)
	else:
		var dragged = inv.get_at(_drag)
		if dragged != null:
			_item_icon(dragged, Rect2(_mouse - Vector2(30, 30), Vector2(60, 60)), 2.5)
