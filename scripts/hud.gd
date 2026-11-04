class_name Hud
extends Control
## On-screen UI: stat bars, weapon slots, ammo, action button, inventory screen,
## messages, help, pause and death screens.
##
## Inventory screen: NEARBY (list of items in the container / on the ground) | INVENTORY (gear slots).
## Every gear slot is a big two-colour symbol with fixed room next to it for the most storage that
## kind of clothing can give, so nothing moves when you put something on.

const UI_SCALE := 3.0
const SLOT_SCALE := 3.5 # big gear slot (19x20 px cell -> 66x70)
const CARGO_SCALE := 2.5 # storage cell (-> 47x50)
const CARGO_STEP := 52.0
const CARGO_PER_ROW := 5
const ROW_H := 46.0
## Gear slot positions inside the inventory panel
const GEAR_POS := {
	"head": Vector2(24, 76), "shirt": Vector2(124, 76), "boots": Vector2(224, 76), "hands": Vector2(324, 76),
	"coat": Vector2(24, 186), "armour": Vector2(24, 280), "pants": Vector2(24, 374), "back": Vector2(24, 468),
	"primary": Vector2(540, 190), "secondary": Vector2(540, 290), "melee": Vector2(540, 390),
}
const GEAR_NAMES := {
	"head": "HEAD", "armour": "ARMOUR", "back": "BACK", "coat": "COAT", "shirt": "SHIRT",
	"pants": "PANTS", "boots": "BOOTS", "hands": "HANDS", "primary": "1 MAIN GUN",
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

const NEAR_RECT := Rect2(16, 64, 372, 592)
const INV_RECT := Rect2(400, 64, 864, 592)

var main: Node
var show_help := true
var inventory_open := false
var _font: Font
var _mouse := Vector2.ZERO
var _btn_down := false
var _drag := {} # location being dragged
var _menu := {} # right-click menu: {"loc", "pos", "items": [[label, action], ...]}
var _near_scroll := 0


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

func slot_rect(slot: String) -> Rect2:
	return Rect2(INV_RECT.position + GEAR_POS[slot], Game.tex("ui_cell").get_size() * SLOT_SCALE)


## Storage cell i of the clothing in `owner` slot (fixed position, whether or not it's worn).
func cargo_cell(owner: String, i: int) -> Rect2:
	var sr := slot_rect(owner)
	var y0 := sr.position.y + 10.0
	return Rect2(Vector2(sr.end.x + 14 + (i % CARGO_PER_ROW) * CARGO_STEP, y0 + (i / CARGO_PER_ROW) * CARGO_STEP),
		Game.tex("ui_cell").get_size() * CARGO_SCALE)


## Whole area of a storage slot block (symbol + its storage), for dropping onto.
func block_rect(owner: String) -> Rect2:
	var sr := slot_rect(owner)
	var r := Rect2(sr.position - Vector2(6, 26), Vector2(sr.size.x + 26 + CARGO_PER_ROW * CARGO_STEP, sr.size.y + 34))
	if owner == "back":
		r = r.grow_individual(0, 0, 0, 30)
	return r


func near_row(i: int) -> Rect2:
	return Rect2(NEAR_RECT.position + Vector2(10, 50 + i * ROW_H), Vector2(NEAR_RECT.size.x - 20, ROW_H - 4))


func near_visible_rows() -> int:
	return int((NEAR_RECT.size.y - 50 - 70) / ROW_H)


func take_all_rect() -> Rect2:
	var sz := Game.tex("ui_button").get_size() * 2.0
	return Rect2(Vector2(NEAR_RECT.get_center().x - sz.x / 2.0, NEAR_RECT.end.y - sz.y - 12), sz)


func _has_action(p: Player) -> bool:
	return p.nearest_loot != null or p.nearest_fire != null


func _action_label(p: Player) -> String:
	if p.cook_t > 0.0:
		return "Cooking... %ds" % int(ceil(p.cook_t))
	var fire_d := p.global_position.distance_to(p.nearest_fire.global_position) if p.nearest_fire else INF
	var loot_d := p.global_position.distance_to(p.nearest_loot.global_position) if p.nearest_loot else INF
	return p.nearest_fire.label(p) if fire_d <= loot_d else p.nearest_loot.label()


func action_rect() -> Rect2:
	var vs := get_viewport_rect().size
	var sz := Game.tex("ui_button").get_size() * UI_SCALE
	return Rect2(Vector2((vs.x - sz.x) / 2.0, vs.y - 190), sz)


## Inventory location under the mouse, or {}.
func loc_at(pos: Vector2) -> Dictionary:
	var inv: Inventory = main.player.inv
	for s in Inventory.GEAR:
		if slot_rect(s).has_point(pos):
			return Inventory.gear_loc(s)
	for s in Inventory.STORAGE:
		var g = inv.gear[s]
		if g == null:
			continue
		for i in g["cargo"].size():
			if cargo_cell(s, i).has_point(pos):
				return Inventory.cargo_loc(s, i)
	if inv.near:
		for r in near_visible_rows():
			var i := r + _near_scroll
			if i < inv.near.contents.size() and near_row(r).has_point(pos):
				return Inventory.near_loc(i)
	return {}


# ---------------------------------------------------------------- input

func set_inventory_open(open: bool) -> void:
	inventory_open = open
	Game.ui_open = open
	_drag = {}
	_menu = {}
	Input.set_default_cursor_shape(Input.CURSOR_ARROW if open else Input.CURSOR_CROSS)


func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	var p: Player = main.player
	if not inventory_open:
		# Action button (search / pick up)
		if mb.button_index == MOUSE_BUTTON_LEFT and _has_action(p) and not p.dead and action_rect().has_point(mb.position):
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
	# Scroll the nearby list
	if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and NEAR_RECT.has_point(mb.position):
		var n: int = inv.near.contents.size() if inv.near else 0
		_near_scroll = clampi(_near_scroll + (1 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1), 0, maxi(n - near_visible_rows(), 0))
		get_viewport().set_input_as_handled()
		return
	# Right-click menu open: a left click picks an option (or closes the menu).
	if not _menu.is_empty() and mb.pressed:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var i := _menu_index(mb.position)
			if i >= 0:
				p.do_action(_menu["loc"], _menu["items"][i][1])
		_menu = {}
		get_viewport().set_input_as_handled()
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed and mb.double_click and not loc.is_empty():
			# Double-click: wear / equip / use / take
			_drag = {}
			p.double_click(loc)
		elif mb.pressed:
			if inv.near and not inv.near.contents.is_empty() and take_all_rect().has_point(mb.position):
				p.say(inv.near.search(p))
			elif not loc.is_empty() and inv.get_at(loc) != null:
				_drag = loc
		elif not _drag.is_empty():
			_drop_drag(p, mb.position, loc)
			_drag = {}
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and not loc.is_empty():
		var acts := p.actions_for(loc)
		if not acts.is_empty():
			_menu = {"loc": loc, "pos": mb.position, "items": acts}
	get_viewport().set_input_as_handled()


const MENU_W := 190.0
const MENU_ROW := 26.0


func _menu_rect() -> Rect2:
	var vs := get_viewport_rect().size
	var h: float = _menu["items"].size() * MENU_ROW + 8
	var pos: Vector2 = _menu["pos"]
	pos.x = minf(pos.x, vs.x - MENU_W - 4)
	pos.y = minf(pos.y, vs.y - h - 4)
	return Rect2(pos, Vector2(MENU_W, h))


func _menu_index(pos: Vector2) -> int:
	var r := _menu_rect()
	if not r.has_point(pos):
		return -1
	var i := int((pos.y - r.position.y - 4) / MENU_ROW)
	return i if i >= 0 and i < _menu["items"].size() else -1


func _drop_drag(p: Player, pos: Vector2, loc: Dictionary) -> void:
	var inv := p.inv
	if loc.is_empty():
		if NEAR_RECT.has_point(pos):
			if _drag["t"] == "near":
				return
			if inv.near:
				loc = Inventory.near_loc(inv.near.contents.size())
			else:
				p.drop(_drag) # starts a new pile on the ground
				return
		elif INV_RECT.has_point(pos):
			# Dropped on a slot block but not on a cell: wear it there, or use its first free cell.
			var item = inv.get_at(_drag)
			for s in Inventory.STORAGE:
				if block_rect(s).has_point(pos):
					if Items.equip_of(item["id"]) == s:
						loc = Inventory.gear_loc(s)
					elif inv.gear[s] != null:
						for i in inv.gear[s]["cargo"].size():
							if inv.get_at(Inventory.cargo_loc(s, i)) == null:
								loc = Inventory.cargo_loc(s, i)
								break
			if loc.is_empty():
				return
		else:
			p.drop(_drag) # outside every panel: drop on the ground
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
func _stat_bar(pos: Vector2, frame: Texture2D, fill: Texture2D, fill_at: Vector2, value: float, low: bool, tint := Color.WHITE) -> void:
	var v := clampf(value / 100.0, 0.0, 1.0)
	var fsz := fill.get_size()
	var src := Rect2(Vector2.ZERO, Vector2(ceilf(fsz.x * v), fsz.y))
	var blink := low and fmod(Time.get_ticks_msec() / 250.0, 2.0) < 1.0
	var mod := tint * (1.4 if blink else 1.0)
	mod.a = 1.0
	if src.size.x > 0:
		draw_texture_rect_region(fill, Rect2(pos + fill_at * UI_SCALE, src.size * UI_SCALE), src, mod)
	_tex(frame, pos, UI_SCALE)


## Draws a texture centred in `box`, as big as fits. Small pack icons use whole-number scales,
## the larger drawn icons half steps, so pixels stay crisp.
func _fit_icon(t: Texture2D, box: Rect2, modulate := Color.WHITE, fill := 0.8) -> void:
	var sz := t.get_size()
	var k := minf(box.size.x * fill / sz.x, box.size.y * fill / sz.y)
	k = maxf(1.0, snappedf(k - 0.24, 0.5) if maxf(sz.x, sz.y) >= 24 else floorf(k))
	_tex(t, box.get_center() - sz * k / 2.0, k, modulate)


func _item_icon(item: Dictionary, cell: Rect2, _scale_px := 0.0, modulate := Color.WHITE) -> void:
	_fit_icon(Items.item_icon(item), cell, modulate)
	if int(item["count"]) > 1:
		_text(cell.end - Vector2(6, 6), str(item["count"]), 14, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 0)
	elif item.has("mag"):
		_text(cell.end - Vector2(6, 6), str(item["mag"]), 12, Color(1, 0.9, 0.6), HORIZONTAL_ALIGNMENT_RIGHT, 0)


func _cell(r: Rect2, scale_px: float, chosen := false) -> void:
	_tex(Game.tex("ui_cell_chosen" if chosen else "ui_cell"), r.position, scale_px)


## Draws the item at loc into a cell (skipping it while it's being dragged).
func _cell_item(inv: Inventory, loc: Dictionary, r: Rect2, chosen := false, scale_px := CARGO_SCALE) -> void:
	_cell(r, scale_px, chosen)
	var it = inv.get_at(loc)
	if it == null:
		return
	if r.has_point(_mouse) and _drag.is_empty():
		draw_rect(r.grow(-8), Color(1, 1, 1, 0.08))
	if not _drag.is_empty() and _drag == loc:
		return
	_item_icon(it, r, 0.0, Color(0.55, 0.45, 0.45) if Items.is_ruined(it) else Color.WHITE)


func _cond_text(it: Dictionary) -> String:
	if Items.is_ruined(it):
		return "RUINED"
	return "%d%%" % int(round(float(it.get("cond", 100.0))))


func _cond_color(it: Dictionary) -> Color:
	var c := float(it.get("cond", 100.0))
	if c <= 0.0:
		return Color(1, 0.4, 0.35)
	return C_DIM if c > 30.0 else Color(1, 0.75, 0.4)


## Bar tint: blue when freezing -> orange when warm.
func _temp_color(t: float) -> Color:
	if t < Player.TEMP_FREEZING:
		return Color("4a7fc0")
	if t < Player.TEMP_COLD:
		return Color("6fa8d8")
	if t < Player.TEMP_WARM:
		return Color("b8c8c8")
	return Color("e09048")


# ---------------------------------------------------------------- draw

func _draw() -> void:
	if main == null or main.player == null:
		return
	var p: Player = main.player
	var vs := get_viewport_rect().size
	var st := int(main.survived)

	# Stat bars (bottom-left)
	var bx := 18.0
	var by := vs.y - 192.0
	_stat_bar(Vector2(bx, by), Game.tex("ui_hp_bar"), Game.tex("ui_hp_fill"), Vector2(11, 4), p.health, p.health < 25.0)
	_stat_bar(Vector2(bx + 9, by + 44), Game.tex("ui_hunger_bar"), Game.tex("ui_hunger_fill"), Vector2(11, 6), p.hunger, p.hunger < 20.0)
	_stat_bar(Vector2(bx, by + 92), Game.thirst_bar(), Game.thirst_fill(), Vector2(11, 4), p.thirst, p.thirst < 20.0)
	var tcol := _temp_color(p.body_temp)
	_stat_bar(Vector2(bx, by + 136), Game.temp_bar(), Game.temp_fill(), Vector2(11, 4), p.body_temp, p.body_temp < Player.TEMP_FREEZING, tcol)
	var status := p.temp_status()
	var trend := p.target_temp() - p.body_temp
	var arrow := " ^" if trend > 1.0 else (" v" if trend < -1.0 else "")
	_text(Vector2(bx + 176, by + 162), status + arrow, 14, tcol.lightened(0.3) if status != "Warm" else C_DIM)
	if p.indoors():
		_text(Vector2(bx + 176, by + 146), "indoors", 11, C_DIM)
	elif p.near_fire():
		_text(Vector2(bx + 176, by + 146), "near fire", 11, Color(1, 0.75, 0.4))
	if not p.can_heal() and p.health < 100.0 and not p.dead and not p.bleeding:
		_text(Vector2(bx + 176, by + 26), "not healing", 11, C_DIM)
	if p.bleeding:
		_tex(Game.tex("blood_2"), Vector2(bx + 176, by + 4), 3.0)
		_text(Vector2(bx + 210, by + 26), "Bleeding [H]", 15, Color(1, 0.4, 0.4))
	if p.poison_t > 0.0:
		_text(Vector2(bx + 186, by + 70), "Sick (%ds)" % int(ceil(p.poison_t)), 15, Color(0.7, 0.9, 0.4))

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
		if n > 10:
			# Big magazines: one bullet icon + count
			start = wx - 160.0
			_tex(full, Vector2(start, wy - 58), 2.0)
			_text(Vector2(start + 20, wy - 40), "%d / %d" % [mag, n], 18, Color.WHITE)
		else:
			for i in n:
				_tex(full if i < mag else empty, Vector2(start + i * step, wy - 58), 2.0)
		_text(Vector2(wx, wy - 32), "+%d" % p.inv.count_of(w["ammo"]), 18, Color(0.95, 0.85, 0.6), HORIZONTAL_ALIGNMENT_RIGHT, 0)
		if p.reloading:
			var rr := Rect2(Vector2(start, wy - 16), Vector2(minf(n, 10) * step, 6))
			draw_rect(rr.grow(2), C_EDGE)
			draw_rect(Rect2(rr.position, Vector2(rr.size.x * p.reload_progress, rr.size.y)), Color(0.9, 0.8, 0.5))

	# Clock / stats (top-right)
	_text(Vector2(vs.x - 20, 32), "Day %d  %s" % [main.day, main.clock_text()], 20, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 0)
	_text(Vector2(vs.x - 20, 54), "Survived %d:%02d   Kills %d" % [st / 60, st % 60, main.kills], 14, Color(0.85, 0.85, 0.85), HORIZONTAL_ALIGNMENT_RIGHT, 0)

	# Action button: appears automatically near containers / items / fires / carcasses
	if _has_action(p) and not p.dead and not inventory_open:
		var ar := action_rect()
		var pressed := _btn_down and ar.has_point(_mouse)
		_tex(Game.tex("ui_button_pressed" if pressed else "ui_button"), ar.position + Vector2(0, 6 if pressed else 0), UI_SCALE)
		var label := _action_label(p)
		_text(Vector2(ar.position.x, ar.position.y + (44 if pressed else 38)), label, 16, C_EDGE, HORIZONTAL_ALIGNMENT_CENTER, ar.size.x)
		_text(Vector2(ar.end.x + 8, ar.position.y + 38), "[E]", 14, C_DIM)

	# Help
	if show_help and not inventory_open:
		var lines := [
			"WASD move   Shift sprint   Melee is automatic   Click to shoot",
			"E / button: search, pick up, skin, cook   R reload   X lower weapon   C campfire",
			"1 / 2 / 3 or wheel: main / secondary / melee   Tab inventory",
			"F eat   G drink   H bandage / first aid   Esc pause   F1 hide help",
		]
		draw_rect(Rect2(14, 14, 660, 104), Color(0.08, 0.04, 0.07, 0.6))
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

	# ---- NEARBY: list of what's in the container / on the ground here
	_panel(NEAR_RECT)
	var near_title := inv.near.title().to_upper() if inv.near else "GROUND"
	_text(NEAR_RECT.position + Vector2(14, 32), near_title, 20, C_TEXT)
	var near_items: Array = inv.near.contents if inv.near else []
	_near_scroll = clampi(_near_scroll, 0, maxi(near_items.size() - near_visible_rows(), 0))
	if near_items.is_empty():
		_text(Vector2(NEAR_RECT.position.x, NEAR_RECT.position.y + 120), "Nothing here", 15, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, NEAR_RECT.size.x)
		_text(Vector2(NEAR_RECT.position.x, NEAR_RECT.position.y + 144), "Drag items here to drop them", 13, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, NEAR_RECT.size.x)
	for r in near_visible_rows():
		var i := r + _near_scroll
		if i >= near_items.size():
			break
		var it: Dictionary = near_items[i]
		var row := near_row(r)
		var loc := Inventory.near_loc(i)
		var dragging: bool = not _drag.is_empty() and _drag == loc
		draw_rect(row, C_EDGE)
		draw_rect(row.grow(-2), C_LIGHT if (row.has_point(_mouse) and _drag.is_empty()) else C_CARD)
		if dragging:
			continue
		_fit_icon(Items.item_icon(it), Rect2(row.position + Vector2(4, 1), Vector2(40, 40)), Color(0.6, 0.5, 0.5) if Items.is_ruined(it) else Color.WHITE, 0.9)
		_text(row.position + Vector2(52, 18), Items.display_name(it), 15, C_TEXT)
		_text(row.position + Vector2(52, 36), _info(it), 12, C_DIM)
	if near_items.size() > near_visible_rows():
		_text(Vector2(NEAR_RECT.end.x - 14, NEAR_RECT.position.y + 32), "%d-%d of %d" % [_near_scroll + 1, mini(_near_scroll + near_visible_rows(), near_items.size()), near_items.size()], 12, C_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 0)
	if not near_items.is_empty():
		var tr := take_all_rect()
		_tex(Game.tex("ui_button"), tr.position, 2.0)
		_text(Vector2(tr.position.x, tr.position.y + 27), "Take all", 15, C_EDGE, HORIZONTAL_ALIGNMENT_CENTER, tr.size.x)

	# ---- INVENTORY: gear slots, each with fixed room for its storage
	_panel(INV_RECT)
	_text(INV_RECT.position + Vector2(14, 32), "INVENTORY", 20, C_TEXT)
	for s in Inventory.GEAR:
		var sr := slot_rect(s)
		var g = inv.gear[s]
		var title: String = GEAR_NAMES[s]
		if g != null and s in Inventory.STORAGE:
			title += "  -  " + Items.display_name(g) + "  " + _cond_text(g)
		_text(sr.position + Vector2(0, -8), title, 12, C_DIM)
		_cell(sr, SLOT_SCALE, inv.active == s)
		if g == null:
			_fit_icon(Game.slot_symbol(s), sr, Color.WHITE, 0.75)
		elif not (not _drag.is_empty() and _drag == Inventory.gear_loc(s)):
			_item_icon(g, sr, 0.0, Color(0.55, 0.45, 0.45) if Items.is_ruined(g) else Color.WHITE)
			if sr.has_point(_mouse) and _drag.is_empty():
				draw_rect(sr.grow(-8), Color(1, 1, 1, 0.08))
		if g != null and g.has("cond") and not s in Inventory.STORAGE:
			_text(Vector2(sr.position.x, sr.end.y + 13), _cond_text(g), 11, _cond_color(g), HORIZONTAL_ALIGNMENT_CENTER, sr.size.x)
		# storage cells of this clothing
		if s in Inventory.STORAGE and g != null:
			for i in g["cargo"].size():
				_cell_item(inv, Inventory.cargo_loc(s, i), cargo_cell(s, i))
		# weapon info
		if s in Inventory.WEAPON_SLOTS and g != null:
			var w: Dictionary = Items.WEAPONS[g["id"]]
			_text(Vector2(sr.end.x + 14, sr.position.y + 28), Items.name_of(g["id"]), 15, C_TEXT)
			var sub: String = "Selected" if inv.active == s else "Press " + SLOT_KEYS[s]
			if not w["melee"]:
				sub = "%d / %d loaded   +%d   %s" % [g["mag"], w["mag"], inv.count_of(w["ammo"]), sub]
			_text(Vector2(sr.end.x + 14, sr.position.y + 48), sub, 12, C_DIM)

	# Stats
	var stx := INV_RECT.position.x + 540
	var sty := INV_RECT.position.y + 512
	var ap := inv.armour_points()
	_text(Vector2(stx, sty), "Armour %.1f   (-%d%% damage)" % [ap, int(round(ap * 10))], 14, C_DIM)
	_text(Vector2(stx, sty + 22), "Warmth +%d   -   %s" % [int(round(inv.warmth())), p.temp_status()], 14, C_DIM)
	_text(Vector2(stx, sty + 44), "%d free storage slots" % inv.free_slots(), 14, C_DIM)

	_text(Vector2(0, vs.y - 30), "Drag to move   -   Double-click: equip / wear / use   -   Right-click for more   -   Drag outside to drop   -   Tab to close", 14, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, vs.x)

	# Right-click menu
	if not _menu.is_empty():
		var mr := _menu_rect()
		draw_rect(mr, C_EDGE)
		draw_rect(mr.grow(-2), C_CARD)
		var hi := _menu_index(_mouse)
		for i in _menu["items"].size():
			var row := Rect2(mr.position + Vector2(4, 4 + i * MENU_ROW), Vector2(MENU_W - 8, MENU_ROW))
			if i == hi:
				draw_rect(row, C_LIGHT)
			_text(row.position + Vector2(8, 18), _menu["items"][i][0], 15, C_TEXT)
		return

	# Tooltip / dragged item
	if _drag.is_empty():
		var hover := loc_at(_mouse)
		var tip_item = inv.get_at(hover) if not hover.is_empty() and hover["t"] != "near" else null
		if tip_item != null:
			var d: Dictionary = tip_item
			var tip := Items.display_name(d) + "   " + _info(d)
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
			_item_icon(dragged, Rect2(_mouse - Vector2(30, 30), Vector2(60, 60)))


## Short info line for an item: count, rounds, condition, storage, food value...
func _info(it: Dictionary) -> String:
	var id: String = it["id"]
	var d := Items.def(id)
	var parts := PackedStringArray()
	if Items.max_stack(id) > 1:
		parts.append("x%d (max %d)" % [it["count"], Items.max_stack(id)])
	if it.has("mag"):
		parts.append("%d / %d loaded" % [it["mag"], Items.WEAPONS[id]["mag"]])
	if Items.is_weapon(id) and not it.has("mag"):
		parts.append("melee, %d damage" % int(Items.WEAPONS[id]["damage"]))
	if Items.kind(id) == "ammo":
		for w in Items.WEAPONS:
			if Items.WEAPONS[w].get("ammo", "") == id:
				parts.append("for " + Items.name_of(w).to_lower())
	if Items.is_clothing(id):
		parts.append(_cond_text(it))
		if Items.cargo_of(id) > 0:
			parts.append("%d slots" % Items.cargo_of(id))
		var f := Items.cond_factor(it)
		parts.append("warmth %d" % int(round(Items.warmth_of(id) * f)))
		if Items.armour_of(id) > 0.0:
			parts.append("armour %.1f" % (Items.armour_of(id) * f))
	if d.has("hunger") and d["hunger"] > 0:
		parts.append("hunger +%d" % int(d["hunger"]))
	if d.has("thirst") and d["thirst"] > 0:
		parts.append("thirst +%d" % int(d["thirst"]))
	if d.get("poison", 0.0) > 0.0:
		parts.append("may make you sick")
	if d.has("cures"):
		parts.append("cures " + ", ".join(PackedStringArray(d["cures"])))
	return ", ".join(parts)
