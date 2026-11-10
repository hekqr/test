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
var _drag := {} # location pressed on (becomes a drag once the mouse moves)
var _press_pos := Vector2.ZERO
const DRAG_START := 6.0 # pixels the mouse must move before a press turns into a drag
var _menu := {} # right-click menu: {"loc", "pos", "items": [[label, action], ...]}
var _near_scroll := 0
var left_tab := "near" # "near" or "craft"
var _craft_scroll := 0
var map_open := false
var travel_text := "" # "Travelling to ..." while the next region is built
var _map_tex: ImageTexture # terrain: paper, forests, water (1 px = 2x2 tiles)
var _fog_img: Image
var _fog_tex: ImageTexture # unexplored areas (1 px = 4x4 tiles)
var _map_zoom := 2.5 # 1 = whole map
var _map_center := Vector2.ZERO # in tiles
var _map_dragging := false
var _map_drag_last := Vector2.ZERO
const MAP_ZOOM_MAX := 8.0
const MAP_PAPER := Color("e6dec3")
const MAP_INK := Color("2e2620")


func _ready() -> void:
	add_to_group("hud")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func _process(_delta: float) -> void:
	if main and main.survived > 30.0 and show_help and not get_tree().paused:
		show_help = false
	if Game.open_inventory:
		Game.open_inventory = false
		set_inventory_open(true)
	_mouse = get_viewport().get_mouse_position() - (inv_ofs() if inventory_open else Vector2.ZERO)
	# Auto aim needs no mouse while walking around: hide the cursor (it comes back in menus)
	var hide: bool = Game.aim_mode == "auto" and not Game.ui_open and not get_tree().paused and main != null and main.player != null and not main.player.dead
	var want := Input.MOUSE_MODE_HIDDEN if hide else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != want:
		Input.mouse_mode = want
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


func tab_rect(i: int) -> Rect2:
	return Rect2(NEAR_RECT.position + Vector2(10 + i * 150, 10), Vector2(140, 30))


func craft_row(i: int) -> Rect2:
	return Rect2(NEAR_RECT.position + Vector2(10, 50 + i * 58), Vector2(NEAR_RECT.size.x - 20, 54))


func craft_visible_rows() -> int:
	return int((NEAR_RECT.size.y - 50 - 48) / 58)


func near_visible_rows() -> int:
	return int((NEAR_RECT.size.y - 50 - 70) / ROW_H)


func take_all_rect() -> Rect2:
	var sz := Game.tex("ui_button").get_size() * 2.0
	return Rect2(Vector2(NEAR_RECT.get_center().x - sz.x / 2.0, NEAR_RECT.end.y - sz.y - 12), sz)


func _has_action(p: Player) -> bool:
	return p.placing != "" or p.interact_choice() != ""


func _action_label(p: Player) -> String:
	if p.cook_t > 0.0:
		return "Cooking... %ds" % int(ceil(p.cook_t))
	return p.action_label()


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
	if inv.near and left_tab == "near":
		for r in near_visible_rows():
			var i := r + _near_scroll
			if i < inv.near.contents.size() and near_row(r).has_point(pos):
				return Inventory.near_loc(i)
	return {}


# ---------------------------------------------------------------- input

func set_map_open(open: bool) -> void:
	if open and inventory_open:
		set_inventory_open(false)
	map_open = open
	Game.ui_open = inventory_open or map_open
	if open:
		_refresh_map()


## Builds the terrain picture once (forests as smooth green areas, lakes and rivers) and the fog of
## unexplored areas each time the map opens. Settlements and roads are drawn on top as icons and lines.
func prepare_map() -> void:
	if _map_tex != null:
		return
	var w: World = main.world
	var R := World.W / 2
	var trees := Image.create_empty(R, R, false, Image.FORMAT_L8)
	var water := PackedByteArray()
	water.resize(R * R)
	for y in World.H:
		for x in World.W:
			var t := w.tiles[y * World.W + x]
			var i := (y >> 1) * R + (x >> 1)
			if t == World.TREE:
				trees.set_pixel(x >> 1, y >> 1, Color(1, 1, 1))
			elif t == World.WATER:
				water[i] = 1
	# Smooth forest density: average down, scale back up
	var dens := trees.duplicate() as Image
	dens.shrink_x2()
	dens.shrink_x2()
	dens.shrink_x2()
	dens.resize(R, R, Image.INTERPOLATE_CUBIC)
	var img := Image.create_empty(R, R, false, Image.FORMAT_RGBA8)
	var forest := Color("b3c493")
	var forest_edge := Color("97ab78")
	var lake := Color("9ec4d8")
	var shore := Color("6e9ab5")
	for y in R:
		for x in R:
			var i := y * R + x
			var c := MAP_PAPER
			if (x * 7 + y * 13) % 11 == 0:
				c = MAP_PAPER.darkened(0.035) # paper grain
			var d := dens.get_pixel(x, y).r
			if d > 0.2:
				c = forest
			elif d > 0.16:
				c = forest_edge
			if water[i] == 1:
				var edge := false
				for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = Vector2i(x, y) + o
					if n.x >= 0 and n.y >= 0 and n.x < R and n.y < R and water[n.y * R + n.x] == 0:
						edge = true
				c = shore if edge else lake
			img.set_pixel(x, y, c)
	_map_tex = ImageTexture.create_from_image(img)
	var F := World.W / 4
	_fog_img = Image.create_empty(F, F, false, Image.FORMAT_RGBA8)
	_fog_tex = ImageTexture.create_from_image(_fog_img)


func _refresh_map() -> void:
	prepare_map()
	var has_map: bool = main.player.inv.count_of("map") > 0
	var fog := Color("d3c7a4")
	var F := World.W / 4
	var seen_c: PackedByteArray = main.explored_coarse
	for y in F:
		for x in F:
			var seen: bool = has_map or seen_c[y * F + x] == 1
			_fog_img.set_pixel(x, y, Color(0, 0, 0, 0) if seen else (fog.darkened(0.03) if (x * 7 + y * 3) % 5 == 0 else fog))
	_fog_tex.update(_fog_img)
	_map_center = main.player.global_position / World.T
	_map_zoom = clampf(_map_zoom, 1.0, MAP_ZOOM_MAX)


## Map screen layout: the map square and the legend beside it.
func _map_rect(vs: Vector2) -> Rect2:
	var size := floorf(minf(vs.y - 100.0, vs.x - 360.0))
	return Rect2(Vector2(floorf((vs.x - size) / 2.0) - 90.0, 56), Vector2(size, size))


## Pixels per tile at the current zoom, and the top-left tile shown.
func _map_view(r: Rect2) -> Array:
	var ppt := r.size.x / World.W * _map_zoom
	var view := r.size / ppt
	_map_center = _map_center.clamp(view / 2.0, Vector2(World.W, World.H) - view / 2.0)
	return [ppt, _map_center - view / 2.0, view]


func _map_input(event: InputEvent) -> bool:
	var vs := get_viewport_rect().size
	var r := _map_rect(vs)
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and r.has_point(mb.position):
			# zoom around the point under the mouse
			var v := _map_view(r)
			var tile: Vector2 = v[1] + (mb.position - r.position) / float(v[0])
			_map_zoom = clampf(_map_zoom * (1.25 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8), 1.0, MAP_ZOOM_MAX)
			var v2 := _map_view(r)
			_map_center += tile - (v2[1] + (mb.position - r.position) / float(v2[0]))
			return true
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_map_dragging = mb.pressed and r.has_point(mb.position)
			_map_drag_last = mb.position
			return true
	elif event is InputEventMouseMotion and _map_dragging:
		var mm := event as InputEventMouseMotion
		var v := _map_view(r)
		_map_center -= (mm.position - _map_drag_last) / float(v[0])
		_map_drag_last = mm.position
		return true
	return false


func set_inventory_open(open: bool) -> void:
	if open and map_open:
		map_open = false # one screen at a time
	inventory_open = open
	Game.ui_open = inventory_open or map_open
	_drag = {}
	_menu = {}
	Input.set_default_cursor_shape(Input.CURSOR_ARROW if open else Input.CURSOR_CROSS)


func _input(event: InputEvent) -> void:
	if map_open:
		if _map_input(event):
			get_viewport().set_input_as_handled()
		return
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
				if p.placing != "":
					p.place_kit()
				else:
					p.interact()
			get_viewport().set_input_as_handled()
		return

	mb = mb.duplicate() as InputEventMouseButton
	mb.position -= inv_ofs() # inventory layout space (it's centred on big screens)
	var inv := p.inv
	var loc := loc_at(mb.position)
	# Scroll the nearby list
	if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and NEAR_RECT.has_point(mb.position) and left_tab == "craft":
		_craft_scroll = clampi(_craft_scroll + (1 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1), 0, maxi(Crafting.RECIPES.size() - craft_visible_rows(), 0))
		get_viewport().set_input_as_handled()
		return
	if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and NEAR_RECT.has_point(mb.position):
		var n: int = inv.near.contents.size() if inv.near else 0
		_near_scroll = clampi(_near_scroll + (1 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1), 0, maxi(n - near_visible_rows(), 0))
		get_viewport().set_input_as_handled()
		return
	# Double-click an item: its main action (equip / wear / use / take) - also while its menu is open.
	if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and mb.double_click and not loc.is_empty() and inv.get_at(loc) != null:
		_menu = {}
		_drag = {}
		p.double_click(loc)
		get_viewport().set_input_as_handled()
		return
	# Item menu open: a left click picks an option (or closes the menu).
	if not _menu.is_empty() and mb.pressed:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var i := _menu_index(mb.position)
			if i >= 0:
				p.do_action(_menu["loc"], _menu["items"][i][1])
		_menu = {}
		get_viewport().set_input_as_handled()
		return
	# Tabs on the left panel: NEARBY / CRAFTING
	if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		for i in 2:
			if tab_rect(i).has_point(mb.position):
				left_tab = ["near", "craft"][i]
				get_viewport().set_input_as_handled()
				return
		if left_tab == "craft":
			for k in craft_visible_rows():
				if craft_row(k).has_point(mb.position) and k + _craft_scroll < Crafting.RECIPES.size():
					p.craft_timed(Crafting.RECIPES[k + _craft_scroll]["id"])
					get_viewport().set_input_as_handled()
					return
	if left_tab == "craft" and NEAR_RECT.has_point(mb.position) and _drag.is_empty():
		get_viewport().set_input_as_handled()
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			if inv.near and not inv.near.contents.is_empty() and take_all_rect().has_point(mb.position):
				p.say(inv.near.search(p))
			elif not loc.is_empty() and inv.get_at(loc) != null:
				_drag = loc
				_press_pos = mb.position
		elif not _drag.is_empty():
			if mb.position.distance_to(_press_pos) > DRAG_START:
				_drop_drag(p, mb.position, loc)
			else:
				open_menu(p, _drag, mb.position) # a click: show what you can do with it
			_drag = {}
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and not loc.is_empty():
		open_menu(p, loc, mb.position)
	get_viewport().set_input_as_handled()


const MENU_W := 190.0
const MENU_ROW := 26.0


## The item's action menu (Eat / Drink / Use / Wear / Repair / Drop ...), if there's anything to do with it.
func open_menu(p: Player, loc: Dictionary, at: Vector2) -> void:
	var acts := p.actions_for(loc)
	if not acts.is_empty():
		_menu = {"loc": loc, "pos": at + Vector2(8, 8), "items": acts}


func _menu_rect() -> Rect2:
	var vs := get_viewport_rect().size - inv_ofs() * 2.0
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
	elif get_tree().paused and not p.dead and (event.is_action_pressed("interact") or event.is_action_pressed("quit")):
		main.quit_to_menu() # pause menu: Q (or Backspace) saves and quits to the menu
	elif event.is_action_pressed("inventory") and not p.dead and not get_tree().paused:
		if not inventory_open:
			left_tab = "near"
		set_inventory_open(not inventory_open)
	elif event.is_action_pressed("interact") and inventory_open:
		set_inventory_open(false) # Q opened a chest: Q closes it again
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map") and not p.dead and not get_tree().paused:
		set_map_open(not map_open)
	elif event.is_action_pressed("pause") and map_open:
		set_map_open(false)
	elif event.is_action_pressed("craft") and not p.dead and not get_tree().paused:
		if inventory_open and left_tab == "craft":
			set_inventory_open(false)
		else:
			left_tab = "craft"
			set_inventory_open(true)
	elif event.is_action_pressed("pause") and inventory_open:
		set_inventory_open(false)
	elif event.is_action_pressed("pause") and not p.dead:
		get_tree().paused = not get_tree().paused
	elif p.dead and event.is_action_pressed("pause"):
		main.quit_to_menu()


const LOW_HP := 30.0


## Below 30% health the screen keeps a red tint (stronger the lower you are), slowly pulsing.
func _draw_low_hp(vs: Vector2, hp: float) -> void:
	var k := clampf(1.0 - hp / LOW_HP, 0.0, 1.0)
	var pulse := 0.85 + 0.15 * sin(Time.get_ticks_msec() / 1000.0 * 3.0)
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.75, 0.0, 0.0, (0.16 + 0.14 * k) * pulse))
	var steps := 12
	var edge := 160.0
	for i in steps:
		var a := (0.1 + 0.1 * k) * pulse * (1.0 - float(i) / steps)
		var w := edge / steps
		var o := i * w
		draw_rect(Rect2(0, o, vs.x, w), Color(0.5, 0.0, 0.0, a))
		draw_rect(Rect2(0, vs.y - o - w, vs.x, w), Color(0.5, 0.0, 0.0, a))
		draw_rect(Rect2(o, 0, w, vs.y), Color(0.5, 0.0, 0.0, a))
		draw_rect(Rect2(vs.x - o - w, 0, w, vs.y), Color(0.5, 0.0, 0.0, a))


## Red flash when you get hit: a light red tint plus darker red edges.
func _draw_hit_flash(vs: Vector2, f: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.8, 0.05, 0.05, 0.16 * f))
	var steps := 8
	var edge := 70.0
	for i in steps:
		var a := 0.08 * f * (1.0 - float(i) / steps)
		var w := edge / steps
		var o := i * w
		draw_rect(Rect2(0, o, vs.x, w), Color(0.7, 0.0, 0.0, a))
		draw_rect(Rect2(0, vs.y - o - w, vs.x, w), Color(0.7, 0.0, 0.0, a))
		draw_rect(Rect2(o, 0, w, vs.y), Color(0.7, 0.0, 0.0, a))
		draw_rect(Rect2(vs.x - o - w, 0, w, vs.y), Color(0.7, 0.0, 0.0, a))


# ---------------------------------------------------------------- drawing helpers

func _text(pos: Vector2, s: String, size_px := 16, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, shadow := true) -> void:
	if align == HORIZONTAL_ALIGNMENT_RIGHT and width <= 0.0:
		pos.x -= _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		align = HORIZONTAL_ALIGNMENT_LEFT
		width = -1.0
	if shadow:
		draw_string(_font, pos + Vector2(2, 2), s, align, width, size_px, Color(0.08, 0.04, 0.07, 0.85))
	draw_string(_font, pos, s, align, width, size_px, col)


## True once a pressed item has been moved far enough to count as dragging.
func _dragging() -> bool:
	return not _drag.is_empty() and _mouse.distance_to(_press_pos) > DRAG_START


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
	elif item.has("water"):
		_text(cell.end - Vector2(6, 6), "%d/%d" % [item["water"], Items.def(item["id"])["capacity"]], 12, Color(0.6, 0.85, 1.0), HORIZONTAL_ALIGNMENT_RIGHT, 0)
	elif item.has("uses"):
		_text(cell.end - Vector2(6, 6), str(item["uses"]), 12, Color(0.7, 0.9, 1.0), HORIZONTAL_ALIGNMENT_RIGHT, 0)


func _cell(r: Rect2, scale_px: float, chosen := false) -> void:
	_tex(Game.tex("ui_cell_chosen" if chosen else "ui_cell"), r.position, scale_px)


## Draws the item at loc into a cell (skipping it while it's being dragged).
func _cell_item(inv: Inventory, loc: Dictionary, r: Rect2, chosen := false, scale_px := CARGO_SCALE) -> void:
	_cell(r, scale_px, chosen)
	var it = inv.get_at(loc)
	if it == null:
		return
	if r.has_point(_mouse) and not _dragging():
		draw_rect(r.grow(-8), Color(1, 1, 1, 0.08))
	if _dragging() and _drag == loc:
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
	if travel_text != "":
		var vs0 := get_viewport_rect().size
		draw_rect(Rect2(Vector2.ZERO, vs0), Color("1a1016"))
		draw_string(_font, Vector2(0, vs0.y / 2.0), travel_text, HORIZONTAL_ALIGNMENT_CENTER, vs0.x, 28, Color("e8dcc0"))
		return
	if main == null or main.player == null:
		return
	var p: Player = main.player
	var vs := get_viewport_rect().size
	var st := int(main.survived)
	if p.health < LOW_HP and not p.dead:
		_draw_low_hp(vs, p.health)
	if p.hit_flash > 0.0:
		_draw_hit_flash(vs, p.hit_flash)

	if not inventory_open and not map_open and not p.dead: # (the panels cover them)
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
			_text(Vector2(bx + 210, by + 26), "Bleeding", 15, Color(1, 0.4, 0.4))
		if p.poison_t > 0.0:
			_text(Vector2(bx + 186, by + 70), "Sick (%ds)" % int(ceil(p.poison_t)), 15, Color(0.7, 0.9, 0.4))

	# Timed action (eating, bandaging, searching...): a progress bar
	if p.busy_t > 0.0 and not p.dead:
		var bw := 260.0
		var by2 := vs.y - 222.0 if not inventory_open else 70.0
		var bx2 := (vs.x - bw) / 2.0
		var frac := 1.0 - p.busy_t / maxf(p.busy_total, 0.01)
		_text(Vector2(0, by2 - 8), "%s %.1fs" % [p.busy_label.trim_suffix(".."), p.busy_t], 16, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		draw_rect(Rect2(bx2 - 2, by2 - 2, bw + 4, 14), C_EDGE)
		draw_rect(Rect2(bx2, by2, bw * frac, 10), Color("e0c070"))

	# Weapon slots 1 / 2 / 3 (bottom-centre)
	var cs := Game.tex("ui_cell").get_size() * UI_SCALE
	var hx := vs.x / 2.0 - cs.x * 1.5 - 8
	var hy := vs.y - cs.y - 12.0
	var hide_slots := inventory_open or map_open or p.dead
	if not hide_slots:
		var aim_txt := "AUTO AIM  -  Space: shoot  -  T: mouse aim" if Game.aim_mode == "auto" else "MOUSE AIM  -  click: shoot  -  T: auto aim"
		_text(Vector2(0, hy - 8), aim_txt, 12, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	for i in (0 if hide_slots else 3):
		var slot: String = Inventory.WEAPON_SLOTS[i]
		var r := Rect2(Vector2(hx + i * (cs.x + 8), hy), cs)
		var it = p.inv.gear[slot]
		var active := p.inv.active == slot
		_cell(r, UI_SCALE, active)
		if it != null:
			_item_icon(it, r, 2.0, Color.WHITE if active else Color(1, 1, 1, 0.55))
		_text(r.position + Vector2(7, 17), SLOT_KEYS[slot], 12, C_DIM)
	if not hide_slots:
		_text(Vector2(hx + 3 * (cs.x + 8) + 6, hy + 36), "%d free slots" % p.inv.free_slots(), 13, C_DIM)

	if not inventory_open and not map_open and not p.dead:
		# Weapon + ammo (bottom-right)
		var w := p.weapon()
		var wx := vs.x - 24.0
		var wy := vs.y - 40.0
		_text(Vector2(wx, wy), w["name"], 20, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 0)
		_text(Vector2(wx, wy + 20), Items.damage_text(p.weapon_id()), 12, Color(1, 0.75, 0.6), HORIZONTAL_ALIGNMENT_RIGHT, 0)
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
	_text(Vector2(vs.x - 20, 74), main.region_name, 14, Color(0.95, 0.85, 0.6), HORIZONTAL_ALIGNMENT_RIGHT, 0)
	_text(Vector2(vs.x - 20, 94), {"clear": "Clear", "rain": "Rain", "snow": "Snow"}.get(main.weather, ""), 14, Color(0.75, 0.85, 0.95), HORIZONTAL_ALIGNMENT_RIGHT, 0)

	# Action button: appears automatically near containers / items / fires / carcasses
	if _has_action(p) and not p.dead and not inventory_open and p.busy_t <= 0.0:
		var ar := action_rect()
		var pressed := _btn_down and ar.has_point(_mouse)
		_tex(Game.tex("ui_button_pressed" if pressed else "ui_button"), ar.position + Vector2(0, 6 if pressed else 0), UI_SCALE)
		var label := _action_label(p)
		# The button art has a dark shadow strip at the bottom: centre the text on the light face above it.
		var face_mid := ar.position.y + (6.0 if pressed else 0.0) + 8.5 * UI_SCALE
		var baseline := face_mid + (_font.get_ascent(16) - _font.get_descent(16)) / 2.0
		_text(Vector2(ar.position.x, roundf(baseline)), label, 16, C_EDGE, HORIZONTAL_ALIGNMENT_CENTER, ar.size.x, false)
		_text(Vector2(ar.end.x + 8, ar.position.y + 38), "[Q]", 14, C_DIM)

	# Help
	if show_help and not inventory_open and not map_open and not p.dead:
		var lines := [
			"WASD move   Shift sprint   Ctrl sneak   Melee is automatic   Space shoot (aims for you - stand still to steady)",
			"Q search, pick up, skin, cook, drink, open, sleep, use   F fish   B build (Q on built = take apart)   C campfire   G throw stick",
			"1 / 2 / 3: main / secondary / melee   R reload   X lower weapon / stop   T aim mode   Mouse wheel: zoom   K crafting   M map",
			"E inventory: click an item to eat, drink, bandage, wear, build...   Esc pause   F1 hide help",
		]
		draw_rect(Rect2(14, 14, 660, 104), Color(0.08, 0.04, 0.07, 0.6))
		for i in lines.size():
			_text(Vector2(24, 38 + i * 22), lines[i], 15)
	elif not inventory_open:
		_text(Vector2(20, 28), "F1 help", 13, Color(0.8, 0.8, 0.8))

	if inventory_open:
		_draw_inventory(p, vs)
	if map_open:
		_draw_map(p, vs)

	# Sneaking: are you hidden, or has something noticed you?
	if p.sneaking and not p.dead and not inventory_open and not map_open:
		var seen: bool = main.player_noticed()
		_text(Vector2(0, vs.y - 268.0), "SPOTTED" if seen else "HIDDEN", 13, Color(1, 0.5, 0.4) if seen else Color(0.6, 1.0, 0.6), HORIZONTAL_ALIGNMENT_CENTER, vs.x)

	# Message
	if p.message_t > 0.0:
		var my := vs.y - 245.0
		if inventory_open:
			my = inv_ofs().y + 52.0
		elif map_open:
			my = 26.0 # above the map, not across it
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


## The inventory screen is laid out for 1280 x 720; on taller / wider screens it sits in the middle.
func inv_ofs() -> Vector2:
	var vs := get_viewport_rect().size
	return Vector2(maxf(floorf((vs.x - 1280.0) / 2.0), 0.0), maxf(floorf((vs.y - 720.0) / 2.0), 0.0))


func _draw_inventory(p: Player, vs: Vector2) -> void:
	var inv := p.inv
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.05, 0.02, 0.05, 0.65))
	var ofs := inv_ofs()
	draw_set_transform(ofs)
	vs -= ofs * 2.0

	# ---- Left panel: NEARBY (list of what's here) or CRAFTING
	_panel(NEAR_RECT)
	var near_title := inv.near.title().to_upper() if inv.near else "GROUND"
	for i in 2:
		var tr2 := tab_rect(i)
		var on := (i == 0 and left_tab == "near") or (i == 1 and left_tab == "craft")
		draw_rect(tr2, C_EDGE)
		draw_rect(tr2.grow(-2), C_LIGHT if on else C_CARD)
		_text(Vector2(tr2.position.x, tr2.position.y + 21), [near_title, "CRAFTING [K]"][i], 14 if on else 13, C_TEXT if on else C_DIM, HORIZONTAL_ALIGNMENT_CENTER, tr2.size.x)
	if left_tab == "craft":
		_draw_crafting(p)
	else:
		_draw_nearby(p, inv)

	_draw_gear(p, inv, vs)


func _draw_crafting(p: Player) -> void:
	var bench := p.near_bench()
	_craft_scroll = clampi(_craft_scroll, 0, maxi(Crafting.RECIPES.size() - craft_visible_rows(), 0))
	for k in craft_visible_rows():
		var i := k + _craft_scroll
		if i >= Crafting.RECIPES.size():
			break
		var r: Dictionary = Crafting.RECIPES[i]
		var row := craft_row(k)
		var miss := Crafting.missing(r, p.inv, bench)
		var ok := miss == ""
		draw_rect(row, C_EDGE)
		draw_rect(row.grow(-2), (C_LIGHT if row.has_point(_mouse) else C_CARD) if ok else C_FILL)
		var icon: Texture2D = Items.icon(r["makes"]) if r["makes"] != "" else Items.icon("sticks")
		_fit_icon(icon, Rect2(row.position + Vector2(4, 6), Vector2(42, 42)), Color.WHITE if ok else Color(1, 1, 1, 0.5), 0.9)
		_text(row.position + Vector2(54, 20), String(r["name"]), 15, C_TEXT if ok else C_DIM)
		var parts := PackedStringArray()
		for item in r["needs"]:
			parts.append("%d/%d %s" % [mini(p.inv.count_of(item), int(r["needs"][item])), int(r["needs"][item]), Items.name_of(item).to_lower()])
		if not r["tools"].is_empty():
			parts.append("tool: " + " / ".join(PackedStringArray(r["tools"])))
		var bench_tag: bool = r.get("station", "") == "workbench"
		var need := ", ".join(parts)
		var nfs := 12
		while nfs > 9 and _font.get_string_size(need, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs).x > row.size.x - 62:
			nfs -= 1 # long lists: a smaller font rather than running off the panel
		_text(row.position + Vector2(54, 38), need, nfs, Color(0.6, 0.9, 0.55) if ok else Color(0.95, 0.6, 0.5))
		if bench_tag:
			var name_w := _font.get_string_size(String(r["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			_text(row.position + Vector2(60 + name_w, 20), "(workbench)", 11, Color(0.6, 0.9, 0.55) if bench else C_DIM)
		if ok:
			_text(Vector2(row.end.x - 10, row.position.y + 20), "Click to craft", 11, C_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 0)
	var more := Crafting.RECIPES.size() - craft_visible_rows()
	_text(Vector2(NEAR_RECT.position.x, NEAR_RECT.end.y - 40), "Recipes %d-%d of %d - scroll for more" % [_craft_scroll + 1, mini(_craft_scroll + craft_visible_rows(), Crafting.RECIPES.size()), Crafting.RECIPES.size()] if more > 0 else "Tear shirts into rags (click a shirt)", 12, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, NEAR_RECT.size.x)
	_text(Vector2(NEAR_RECT.position.x, NEAR_RECT.end.y - 22), "At a workbench: more kits" if not bench else "At your workbench", 12, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, NEAR_RECT.size.x)


func _draw_nearby(p: Player, inv: Inventory) -> void:
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
		var dragging: bool = _dragging() and _drag == loc
		draw_rect(row, C_EDGE)
		draw_rect(row.grow(-2), C_LIGHT if (row.has_point(_mouse) and not _dragging()) else C_CARD)
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


func _draw_gear(p: Player, inv: Inventory, vs: Vector2) -> void:
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
		elif not (_dragging() and _drag == Inventory.gear_loc(s)):
			_item_icon(g, sr, 0.0, Color(0.55, 0.45, 0.45) if Items.is_ruined(g) else Color.WHITE)
			if sr.has_point(_mouse) and not _dragging():
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
			_text(Vector2(sr.end.x + 14, sr.position.y + 20), Items.name_of(g["id"]), 15, C_TEXT)
			_text(Vector2(sr.end.x + 14, sr.position.y + 60), Items.damage_text(g["id"]), 12, Color(1, 0.75, 0.6))
			var sub: String = "Selected" if inv.active == s else "Press " + SLOT_KEYS[s]
			if not w["melee"]:
				sub = "%d / %d loaded   +%d   %s" % [g["mag"], w["mag"], inv.count_of(w["ammo"]), sub]
			_text(Vector2(sr.end.x + 14, sr.position.y + 40), sub, 12, C_DIM)

	# Stats
	var stx := INV_RECT.position.x + 540
	var sty := INV_RECT.position.y + 512
	var ap := inv.armour_points()
	_text(Vector2(stx, sty), "Armour %.1f   (-%d%% damage)" % [ap, int(round(ap * 10))], 14, C_DIM)
	_text(Vector2(stx, sty + 22), "Warmth +%d   -   %s" % [int(round(inv.warmth())), p.temp_status()], 14, C_DIM)
	_text(Vector2(stx, sty + 44), "%d free storage slots" % inv.free_slots(), 14, C_DIM)

	_text(Vector2(0, vs.y - 30), "Click an item: what you can do with it   -   Double-click: equip / wear / use   -   Drag to move, outside to drop   -   E to close", 14, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, vs.x)

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
		draw_set_transform(Vector2.ZERO)
		return

	# Tooltip / dragged item
	if not _dragging():
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
	draw_set_transform(Vector2.ZERO)


## Short info line for an item: count, rounds, condition, storage, food value...
func _info(it: Dictionary) -> String:
	var id: String = it["id"]
	var d := Items.def(id)
	var parts := PackedStringArray()
	if Items.max_stack(id) > 1:
		parts.append("x%d (max %d)" % [it["count"], Items.max_stack(id)])
	if it.has("mag"):
		parts.append("%d / %d loaded" % [it["mag"], Items.WEAPONS[id]["mag"]])
	if Items.is_weapon(id):
		parts.append(("melee, " if Items.WEAPONS[id]["melee"] else "") + Items.damage_text(id))
		if it.has("cond"):
			parts.append(_cond_text(it) + (" (broken)" if Items.is_ruined(it) else ""))
	if it.has("uses"):
		parts.append("%d uses left" % int(it["uses"]))
		parts.append("repairs clothing" if d.get("fixes", "") == "sew" else "repairs weapons, helmets, metal armour")
	if id == "scrap_metal":
		parts.append("for improvised armour")
	if id == "leather":
		parts.append("2 = sack, 1 = water gourd")
	if it.has("water"):
		parts.append("water %d / %d - refill at taps, lakes and rivers" % [it["water"], d["capacity"]])
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


func _draw_map(p: Player, vs: Vector2) -> void:
	var w: World = main.world
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.05, 0.02, 0.05, 0.75))
	var r := _map_rect(vs)
	var v := _map_view(r)
	var ppt: float = v[0]
	var origin: Vector2 = v[1]
	var view: Vector2 = v[2]
	var has_map: bool = p.inv.count_of("map") > 0
	var to_screen := func(tile: Vector2) -> Vector2: return r.position + (tile - origin) * ppt
	# Terrain
	draw_texture_rect_region(_map_tex, r, Rect2(origin / 2.0, view / 2.0))
	# Grid: a square every 32 tiles
	var g := 32
	for k in range(0, World.W + 1, g):
		var sx: float = r.position.x + (k - origin.x) * ppt
		if sx > r.position.x and sx < r.end.x:
			draw_line(Vector2(sx, r.position.y), Vector2(sx, r.end.y), Color(0.45, 0.38, 0.28, 0.25), 1.0)
		var sy: float = r.position.y + (k - origin.y) * ppt
		if sy > r.position.y and sy < r.end.y:
			draw_line(Vector2(r.position.x, sy), Vector2(r.end.x, sy), Color(0.45, 0.38, 0.28, 0.25), 1.0)
	# Roads: highways as wide amber lines, settlement streets as thin dark ones
	var lo := origin
	var hi := origin + view
	for pass_i in 2:
		for seg in w.segments:
			var hw: bool = seg["kind"] == "highway"
			var a: Vector2
			var b: Vector2
			var mid := float(seg["at"]) + 1.5
			if seg["vertical"]:
				if mid < lo.x or mid > hi.x:
					continue
				a = Vector2(mid, maxf(float(seg["from"]), lo.y))
				b = Vector2(mid, minf(float(seg["to"]), hi.y))
				if a.y >= b.y:
					continue
			else:
				if mid < lo.y or mid > hi.y:
					continue
				a = Vector2(maxf(float(seg["from"]), lo.x), mid)
				b = Vector2(minf(float(seg["to"]), hi.x), mid)
				if a.x >= b.x:
					continue
			var width := maxf(2.0, 2.4 * ppt) if hw else maxf(1.5, 1.6 * ppt)
			if pass_i == 0:
				draw_line(to_screen.call(a), to_screen.call(b), Color("6e5038") if hw else Color(0, 0, 0, 0), width + 2.0)
			else:
				draw_line(to_screen.call(a), to_screen.call(b), Color("e0ad62") if hw else Color("5d544b"), width)
	# Unexplored areas
	draw_texture_rect_region(_fog_tex, r, Rect2(origin / 4.0, view / 4.0))
	# Settlements: an icon (more blocks = bigger place) and the name. Bigger places get their names placed
	# first; a name goes right, left, above or below its icon, wherever it doesn't cover another one.
	var order := range(w.settlements.size())
	var rank := {"city": 0, "town": 1, "military": 2, "village": 3, "hamlet": 4}
	order.sort_custom(func(a, b): return rank.get(w.settlements[a]["type"], 5) < rank.get(w.settlements[b]["type"], 5))
	var taken := [] # [rect, owner]: owner = settlement index (its icon / name), -1 for road labels
	var labels := []
	for i in order:
		var st: Dictionary = w.settlements[i]
		var c: Vector2i = st["center"]
		var known: bool = has_map or main.explored[w.idx(c)] == 1
		if not known:
			continue
		var pos: Vector2 = to_screen.call(Vector2(c) + Vector2(0.5, 0.5))
		if not r.grow(-4).has_point(pos):
			continue
		taken.append([Rect2(pos - Vector2(8, 8), Vector2(16, 16)), i])
		labels.append([i, pos])
	# Roads out of the region: arrows to the neighbouring regions (labelled first: they have the least room)
	for side in ["N", "S", "W", "E"]:
		var ep: Vector2i = w.edge_exit(side)
		var spos: Vector2 = to_screen.call(Vector2(ep) + Vector2(0.5, 0.5))
		var out: Vector2 = {"N": Vector2.UP, "S": Vector2.DOWN, "W": Vector2.LEFT, "E": Vector2.RIGHT}[side]
		spos = spos.clamp(r.position + Vector2(18, 18), r.end - Vector2(18, 18))
		if not r.grow(-2).has_point(to_screen.call(Vector2(ep))) and _map_zoom > 1.01:
			continue
		var nb: String = World.region_name(main.world_seed, main.region + Vector2i(out))
		var tip := spos + out * 8.0
		draw_colored_polygon(PackedVector2Array([tip, spos - out * 4.0 + out.orthogonal() * 7.0, spos - out * 4.0 - out.orthogonal() * 7.0]), Color("6e5038"))
		var lbl := "to " + nb
		var lw := _font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		# Inside the map from the arrow; for side arrows try below / above it too, away from place names.
		var cands: Array = [spos - out * 16.0 + Vector2(-lw / 2.0, 4)]
		if out.x != 0.0:
			cands = [spos + Vector2(-lw - 14.0 if out.x > 0 else 14.0, 4), spos + Vector2(-lw / 2.0 - out.x * (lw / 2.0 + 6), 22), spos + Vector2(-lw / 2.0 - out.x * (lw / 2.0 + 6), -12)]
		else:
			cands = [spos - out * 18.0 + Vector2(-lw / 2.0, 4), spos + Vector2(12, 4 - out.y * 4.0), spos + Vector2(-lw - 12, 4 - out.y * 4.0)]
		var lp: Vector2 = cands[0]
		for cnd in cands:
			var c2: Vector2 = cnd
			c2.x = clampf(c2.x, r.position.x + 4, r.end.x - lw - 4)
			var lr := Rect2(c2 - Vector2(0, 10), Vector2(lw, 12))
			if not taken.any(func(t): return (t[0] as Rect2).intersects(lr)):
				lp = c2
				break
		lp.x = clampf(lp.x, r.position.x + 4, r.end.x - lw - 4)
		taken.append([Rect2(lp - Vector2(0, 10), Vector2(lw, 12)), -1])
		draw_string(_font, lp, lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("6e5038"))
	for lab in labels:
		var st: Dictionary = w.settlements[lab[0]]
		var pos: Vector2 = lab[1]
		_settlement_icon(pos, String(st["type"]))
		var fs: int = {"city": 20, "town": 17, "village": 15, "hamlet": 13, "military": 14}.get(st["type"], 13)
		var label := String(st["name"])
		if st["type"] == "city":
			label = label.to_upper()
		var sz := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var spots := [pos + Vector2(14, -sz.y * 0.5), pos + Vector2(-14 - sz.x, -sz.y * 0.5),
			pos + Vector2(-sz.x * 0.5, -12 - sz.y), pos + Vector2(-sz.x * 0.5, 12)]
		var best: Vector2 = spots[0]
		var found := false
		for sp in spots:
			var lr := Rect2(sp, sz).grow(1)
			if not r.grow(-2).encloses(lr):
				continue
			var hit := false
			for t in taken:
				if t[1] != lab[0] and (t[0] as Rect2).intersects(lr):
					hit = true
					break
			if not hit:
				best = sp
				found = true
				break
		if not found and st["type"] == "hamlet":
			continue # no room: small places just show their icon
		taken.append([Rect2(best, sz), lab[0]])
		var tp := best + Vector2(0, sz.y * 0.78)
		for o in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
			draw_string(_font, tp + o, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(MAP_PAPER, 0.9))
		draw_string(_font, tp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, MAP_INK)
	# You are here
	var me: Vector2 = to_screen.call(p.global_position / World.T)
	if r.has_point(me):
		var f := p.facing.normalized()
		var tri := PackedVector2Array([me + f * 10.0, me + f.rotated(2.5) * 8.0, me + f.rotated(-2.5) * 8.0])
		draw_colored_polygon(tri, Color("c23a30"))
		draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), MAP_INK, 1.5)
	# Paper margin and frame (also hides anything that spilled over the edge)
	var m := 12.0
	var paper := MAP_PAPER.darkened(0.04)
	draw_rect(Rect2(r.position - Vector2(m, m), Vector2(r.size.x + 2 * m, m)), paper)
	draw_rect(Rect2(Vector2(r.position.x - m, r.end.y), Vector2(r.size.x + 2 * m, m)), paper)
	draw_rect(Rect2(r.position - Vector2(m, 0), Vector2(m, r.size.y)), paper)
	draw_rect(Rect2(Vector2(r.end.x, r.position.y), Vector2(m, r.size.y)), paper)
	draw_rect(r.grow(m), Color("5a4630"), false, 3.0)
	draw_rect(r, Color(0.35, 0.28, 0.2, 0.6), false, 1.0)
	# Grid labels in the margin: letters across, numbers down
	for k in range(0, World.W / g):
		var cx: float = r.position.x + (k * g + g * 0.5 - origin.x) * ppt
		if cx > r.position.x + 4 and cx < r.end.x - 4:
			draw_string(_font, Vector2(cx - 4, r.position.y - 2), char(65 + k), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("6e5a44"))
		var cy: float = r.position.y + (k * g + g * 0.5 - origin.y) * ppt
		if cy > r.position.y + 4 and cy < r.end.y - 4:
			draw_string(_font, Vector2(r.position.x - m + 1, cy + 4), str(k + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("6e5a44"))
	# Legend
	var lx := r.end.x + 30.0
	var ly := r.position.y + 4.0
	draw_rect(Rect2(lx - 10, ly - 4, 190, 356), Color(0.12, 0.08, 0.1, 0.85))
	_text(Vector2(lx, ly + 18), main.region_name.to_upper(), 16, C_TEXT)
	var rows := [["city", "City"], ["town", "Town"], ["village", "Village"], ["hamlet", "Hamlet"], ["military", "Military camp"]]
	for i in rows.size():
		var y := ly + 46 + i * 26
		draw_rect(Rect2(lx - 2, y - 12, 26, 22), MAP_PAPER)
		_settlement_icon(Vector2(lx + 11, y - 1), rows[i][0])
		_text(Vector2(lx + 34, y + 5), rows[i][1], 14, C_TEXT)
	var y2 := ly + 46 + 5 * 26
	draw_line(Vector2(lx, y2), Vector2(lx + 24, y2), Color("6e5038"), 5.0)
	draw_line(Vector2(lx, y2), Vector2(lx + 24, y2), Color("e0ad62"), 3.0)
	_text(Vector2(lx + 34, y2 + 5), "Road", 14, C_TEXT)
	draw_line(Vector2(lx, y2 + 24), Vector2(lx + 24, y2 + 24), Color("5d544b"), 2.0)
	_text(Vector2(lx + 34, y2 + 29), "Street", 14, C_TEXT)
	draw_rect(Rect2(lx, y2 + 40, 24, 14), Color("b3c493"))
	_text(Vector2(lx + 34, y2 + 53), "Forest", 14, C_TEXT)
	draw_rect(Rect2(lx, y2 + 64, 24, 14), Color("9ec4d8"))
	_text(Vector2(lx + 34, y2 + 77), "Water", 14, C_TEXT)
	draw_colored_polygon(PackedVector2Array([Vector2(lx + 20, y2 + 95), Vector2(lx + 4, y2 + 89), Vector2(lx + 4, y2 + 101)]), Color("c23a30"))
	_text(Vector2(lx + 34, y2 + 101), "You", 14, C_TEXT)
	# Compass
	var cp := Vector2(lx + 85, y2 + 160)
	draw_circle(cp, 26, MAP_PAPER)
	draw_arc(cp, 26, 0, TAU, 24, Color("5a4630"), 2.0)
	draw_colored_polygon(PackedVector2Array([cp + Vector2(0, -22), cp + Vector2(6, 0), cp + Vector2(-6, 0)]), Color("c23a30"))
	draw_colored_polygon(PackedVector2Array([cp + Vector2(0, 22), cp + Vector2(6, 0), cp + Vector2(-6, 0)]), Color("5a4630"))
	_text(cp + Vector2(-5, -30), "N", 14, C_TEXT)
	_text(Vector2(0, r.end.y + 34), "Scroll to zoom  -  drag to move  -  M / Esc to close", 14, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	if not has_map:
		_text(Vector2(0, r.end.y + 54), "Only places you've been are drawn. A Road map (cars, shops, garages, police) shows everything.", 13, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, vs.x)


## Settlement symbol: blocks of buildings - 4 for the city, 3 for a town, 2 for a village, 1 for a hamlet.
func _settlement_icon(pos: Vector2, kind: String) -> void:
	if kind == "military":
		# Olive square with a star
		draw_rect(Rect2(pos - Vector2(7, 7), Vector2(14, 14)).grow(1), MAP_PAPER)
		draw_rect(Rect2(pos - Vector2(7, 7), Vector2(14, 14)), Color("4e5a30"))
		var star := PackedVector2Array()
		for k in 10:
			var a := -PI / 2.0 + k * PI / 5.0
			star.append(pos + Vector2.from_angle(a) * (5.5 if k % 2 == 0 else 2.3))
		draw_colored_polygon(star, Color("e8dcb0"))
		return
	var n: int = {"city": 4, "town": 3, "village": 2, "hamlet": 1}.get(kind, 1)
	var sz := 6.0 if kind != "hamlet" else 5.0
	var cells := [Vector2(-1, -1), Vector2(0, -1), Vector2(-1, 0), Vector2(0, 0)]
	if n == 3:
		cells = [Vector2(-1, -1), Vector2(0, -1), Vector2(-0.5, 0)]
	elif n == 2:
		cells = [Vector2(-1, -0.5), Vector2(0, -0.5)]
	elif n == 1:
		cells = [Vector2(-0.5, -0.5)]
	if kind == "city":
		draw_circle(pos, 12.0, Color(0.75, 0.25, 0.2, 0.25))
	for c in cells:
		var rr := Rect2(pos + c * (sz + 1.5), Vector2(sz, sz))
		draw_rect(rr.grow(1), MAP_PAPER)
		draw_rect(rr, MAP_INK)

