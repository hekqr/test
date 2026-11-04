extends Node
## Global helpers: input setup, physics layers, noise events.

const LAYER_WALL := 1
const LAYER_PLAYER := 2
const LAYER_ZOMBIE := 4
const LAYER_ANIMAL := 8
const LAYER_NPC := 16 # hostile survivors
const LAYER_WATER := 32 # lakes & rivers: block walking, not bullets or sight
const LAYER_DOOR := 64 # closed doors: block zombies and animals, not people

signal noise_made(pos: Vector2, radius: float)

## 0 = full daylight, 1 = darkest night. Set by main.gd.
var night := 0.0
## True while a full-screen UI (inventory) is open: blocks attacking/moving.
var ui_open := false
## Save file location (tests point this somewhere else).
var save_path := "user://save.json"
## Save data to load when the game scene starts; empty = new game.
var pending_load := {}

## Set by the player to ask the HUD to open the inventory (searching a container).
var open_inventory := false

## Set when a click was used by a UI button, so it doesn't also fire a gun. Cleared on release.
var click_used := false


func _ready() -> void:
	_key("move_up", [KEY_W, KEY_UP])
	_key("move_down", [KEY_S, KEY_DOWN])
	_key("move_left", [KEY_A, KEY_LEFT])
	_key("move_right", [KEY_D, KEY_RIGHT])
	_key("sprint", [KEY_SHIFT])
	# Letter keys use the printed key label (so they work on any keyboard layout);
	# movement and number keys use the physical key position.
	_key("interact", [KEY_E], false)
	_key("reload", [KEY_R], false)
	_key("holster", [KEY_X], false)
	_key("build_fire", [KEY_C], false)
	_key("craft", [KEY_K], false)
	_key("map", [KEY_M], false)
	_key("weapon_primary", [KEY_1])
	_key("weapon_secondary", [KEY_2])
	_key("weapon_melee", [KEY_3])
	for pair in [["weapon_next", MOUSE_BUTTON_WHEEL_DOWN], ["weapon_prev", MOUSE_BUTTON_WHEEL_UP]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
			var wb := InputEventMouseButton.new()
			wb.button_index = pair[1]
			InputMap.action_add_event(pair[0], wb)
	_key("inventory", [KEY_TAB, KEY_I], false)
	_key("help", [KEY_F1])
	_key("pause", [KEY_ESCAPE])
	_key("fullscreen", [KEY_F11])
	_key("quit", [KEY_Q], false)
	if not InputMap.has_action("attack"):
		InputMap.add_action("attack")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("attack", mb)


func _key(action: String, keys: Array, physical := true) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		if physical:
			ev.physical_keycode = k
		else:
			ev.keycode = k
		InputMap.action_add_event(action, ev)


func make_noise(pos: Vector2, radius: float) -> void:
	noise_made.emit(pos, radius)


# ---------------------------------------------------------------- art helpers

const ART := "res://assets/thirdparty/"
const DIRS := ["down", "up", "side", "side-left"]

var _tex_cache := {}
var _frames_cache := {}


func tex(name: String) -> Texture2D:
	if not _tex_cache.has(name):
		_tex_cache[name] = load(ART + name + ".png")
	return _tex_cache[name]


## Builds SpriteFrames from horizontal sprite sheets.
## spec: { anim_name: [file_name, frame_count, fps, loop] }
func frames(key: String, spec: Dictionary) -> SpriteFrames:
	if _frames_cache.has(key):
		return _frames_cache[key]
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for anim in spec:
		var s: Array = spec[anim]
		var t := tex(s[0])
		var n: int = s[1]
		var w := t.get_width() / n
		sf.add_animation(anim)
		sf.set_animation_speed(anim, s[2])
		sf.set_animation_loop(anim, s[3])
		for i in n:
			var at := AtlasTexture.new()
			at.atlas = t
			at.region = Rect2(i * w, 0, w, t.get_height())
			sf.add_frame(anim, at)
	_frames_cache[key] = sf
	return sf


## Picks one of the 4 sprite directions for a facing vector.
func dir_name(v: Vector2) -> String:
	if absf(v.x) >= absf(v.y) * 0.8:
		return "side" if v.x >= 0.0 else "side-left"
	return "down" if v.y >= 0.0 else "up"


## The y-sorted node where things on the ground go (loot piles, thrown axes).
func ground(from: Node) -> Node:
	var e := from.get_tree().get_first_node_in_group("entities")
	return e if e != null else from.get_parent()


## Collision shape around a character's feet (a flat capsule), so they touch walls where their feet are -
## not the old circle that stuck out below the sprite. half_w / half_h in pixels; feet at y = +2.
func foot_shape(half_w: float, half_h: float) -> CollisionShape2D:
	var cap := CapsuleShape2D.new()
	cap.radius = half_h
	cap.height = half_w * 2.0
	var cs := CollisionShape2D.new()
	cs.shape = cap
	cs.rotation = PI * 0.5
	cs.position = Vector2(0, 2.0 - half_h)
	return cs


## Short blood spray where a bullet or blade hits (plays once, then removes itself).
func hit_fx(parent: Node, pos: Vector2, dir: Vector2) -> void:
	if parent == null:
		return
	var key := "hit_blood_%d" % randi_range(1, 2)
	var sf := frames(key, {"hit": [key, 3, 16.0, false]})
	var fx := AnimatedSprite2D.new()
	fx.sprite_frames = sf
	fx.scale = Vector2(2, 2)
	fx.flip_h = dir.x < 0.0
	fx.position = pos + Vector2(0, -10)
	fx.z_index = 5
	parent.add_child(fx)
	fx.play("hit")
	fx.animation_finished.connect(fx.queue_free)


func make_sprite(name: String, scale_px := 2.0) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex(name)
	s.scale = Vector2(scale_px, scale_px)
	return s


## Thirst bar frame: the HP bar frame with the heart swapped for a water drop.
func thirst_bar() -> Texture2D:
	if _tex_cache.has("_thirst_bar"):
		return _tex_cache["_thirst_bar"]
	var img := tex("ui_hp_bar").get_image()
	img.convert(Image.FORMAT_RGBA8)
	var outline := img.get_pixel(12, 4)
	for y in img.get_height():
		for x in 12:
			img.set_pixel(x, y, Color(0, 0, 0, 0))
	for y in range(3, 9):
		img.set_pixel(11, y, outline)
	# 9x11 water drop: o = outline, a = dark blue, b = blue, c = highlight
	var drop := [
		"....o....",
		"...oao...",
		"...oao...",
		"..oaboo..",
		"..obbbo..",
		".oabbbbo.",
		".oabcbbo.",
		"oabbcbbbo",
		"oaabbbbao",
		".oaaaaao.",
		"..ooooo..",
	]
	var cols := {"o": outline, "a": Color("2c4a7a"), "b": Color("4a7fc0"), "c": Color("a8d0f0")}
	for y in drop.size():
		var row: String = drop[y]
		for x in row.length():
			if cols.has(row[x]):
				img.set_pixel(1 + x, y, cols[row[x]])
	var t := ImageTexture.create_from_image(img)
	_tex_cache["_thirst_bar"] = t
	return t


## HP fill recoloured blue for the thirst bar.
func thirst_fill() -> Texture2D:
	if _tex_cache.has("_thirst_fill"):
		return _tex_cache["_thirst_fill"]
	var img := tex("ui_hp_fill").get_image()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var l := c.get_luminance()
			img.set_pixel(x, y, Color(l * 0.45, l * 0.9, l * 1.7, c.a))
	var t := ImageTexture.create_from_image(img)
	_tex_cache["_thirst_fill"] = t
	return t


# ---------------------------------------------------------------- clothing icons
# Original pixel-art icons for clothing (the art packs have none). o = outline.

const _SHIRT := [
	"....oo..oo....",
	"..ooaaooaaoo..",
	".oaaaaaaaaaao.",
	"oaaaaaaaaaaaao",
	"oaaoaaaaaaoaao",
	".oo.oaaaaao.oo",
	"....oaaaaao...",
	"....oaaaaao...",
	"....oaaaaao...",
	"....oaaaaao...",
	"....obbbbbo...",
	".....ooooo....",
]
const _COAT := [
	"....oo..oo....",
	"..ooaaooaaoo..",
	".oaaaaobaaaao.",
	"oaaaaaobaaaaao",
	"oaaoaaobaaoaao",
	"oaaoaaobaaoaao",
	"oaaoaaobaaoaao",
	"oaaoaaobaaoaao",
	"oddoaaobaaoddo",
	".oo.oaobaao.oo",
	"....oaobaao...",
	"....ooooooo...",
]
const _PANTS := [
	"oooooooooooo",
	"obbbbbbbbbbo",
	"oaaaaaaaaaao",
	"oaaaaooaaaao",
	"oaaao..oaaao",
	"oaaao..oaaao",
	"oapao..oapao",
	"oapao..oapao",
	"oaaao..oaaao",
	"oaaao..oaaao",
	"occco..occco",
	"ooooo..ooooo",
]
const _BOOT := [
	".oooo.....",
	".oaao.....",
	".oaao.....",
	".oaao.....",
	".oaao.....",
	".oaaooooo.",
	".oaaaaaaao",
	"obbbbbbbbo",
	"oooooooooo",
]
const _VEST := [
	".ooo....ooo.",
	".oao....oao.",
	"ooaao..oaaoo",
	"oaaaaooaaaao",
	"oaaaaobaaaao",
	"oaccaobaccao",
	"oaccaobaccao",
	"oaaaaobaaaao",
	"oaccaobaccao",
	"oaccaobaccao",
	"oaaaaobaaaao",
	"oooooooooooo",
]
const _HELMET := [
	"....ooooo....",
	"..ooaaaaaoo..",
	".oaabbaaaaao.",
	".oabaaaaaaao.",
	"oaabaaaaaaaao",
	"oaaaaaaaaaaao",
	"occccccccccco",
	"ooooooooooooo",
]
const _PACK := [
	"...oooooo...",
	"..oo....oo..",
	".oooooooooo.",
	"oaaaaaaaaaao",
	"obbbbbbbbbbo",
	"obbbbbbbbbbo",
	"oaaaaddaaaao",
	"oaaaaaaaaaao",
	"oaoccccccoao",
	"oaoccccccoao",
	"oaooooooooao",
	"oaaaaaaaaaao",
	".oooooooooo.",
]

const _CAP := [
	"....oooooo....",
	"...oaaaaaao...",
	"..oabaaaaaao..",
	"..oaaaaaaaao..",
	"..oaaaaaaaaooo",
	"..occcccccccco",
	"..oooooooooooo",
]
const _BEANIE := [
	".....oo.....",
	"....obbo....",
	"...oaaaao...",
	"..oaaaaaao..",
	".oaaaaaaaao.",
	".oaaaaaaaao.",
	"oddddddddddo",
	"odcdcdcdcdco",
	"oddddddddddo",
	"oooooooooooo",
]
const _THERMO := [
	"...ooo...",
	"...oco...",
	"...oco...",
	"...oco...",
	"...oao...",
	"...oao...",
	"..oaaao..",
	".oaaaaao.",
	".oaabaao.",
	".oaaaaao.",
	"..ooooo..",
]

const _SODA := [
	".oooooo.",
	"occcccco",
	"oaaaaaao",
	"oabaaaao",
	"oabaaaao",
	"oawwwwao",
	"oabaaaao",
	"oaaaaaao",
	"occcccco",
	".oooooo.",
]
const _MEAT := [
	"..ooooo....",
	".oaaaaaoo..",
	"oabaaaaaao.",
	"oaaaccaaaao",
	"oaaaaaaaaao",
	".oaaaaaaoww",
	"..oooooowwo",
	".......ooo.",
]

## [rows, palette, checker, default base colour]. Palette values: hex, or a shade of the item's colour:
## "base", "light", "dark", "darker".
const _MATCHES := [
	"ooooooooo",
	"oaaaaaaao",
	"oabbbbbao",
	"oabwwwbao",
	"oabbbbbao",
	"oaaaaaaao",
	"ooooooooo",
]
const _RABBIT_1 := [
	".......o.o..",
	"......oaoao.",
	"......oaoao.",
	"..oooooaaaao",
	".oaaaaaaaeao",
	"oaaaaaaaaaao",
	"obaaaaaaaao.",
	".oaaaaaaao..",
	"..oo.o.oo...",
]
const _RABBIT_2 := [
	"........o.o.",
	".......oaoao",
	"...ooooaaaao",
	".ooaaaaaaeao",
	"obaaaaaaaaao",
	".oaaaaaaaao.",
	"..oo....oo..",
	".o........o.",
	"............",
]
const _DEER_1 := [
	"............o..o..",
	"............oo.oo.",
	".............oooo.",
	"............oaaao.",
	"............oaaeao",
	"...........oaaaaoo",
	"..oooooooooaaaoo..",
	".oaaaaaaaaaaaao...",
	"obaaaaaaaaaaaao...",
	"oaaaaaaaaaaaaao...",
	".oaccaaaaaacao....",
	"..oaoo....oaoo....",
	"..oao.....oao.....",
	"..oao.....oao.....",
	"..oo......oo......",
]
const _DEER_2 := [
	"............o..o..",
	"............oo.oo.",
	".............oooo.",
	"............oaaao.",
	"............oaaeao",
	"...........oaaaaoo",
	"..oooooooooaaaoo..",
	".oaaaaaaaaaaaao...",
	"obaaaaaaaaaaaao...",
	"oaaaaaaaaaaaaao...",
	".oaccaaaaaacao....",
	"..oaoo....oaoo....",
	".oao.......oao....",
	".oao........oao...",
	".oo..........oo...",
]

const _WOLF_1 := [
	"..............o.o....",
	".............oaoao...",
	".............oaaaaoo.",
	"oo..........oaaeaaaao",
	"oco.......ooaaaaaaoo.",
	".oco.oooooccaaaaao...",
	"..ocoaacccccaaaao....",
	"...oaaaaaaaaaaaao....",
	"...oaaaaaaaaaaao.....",
	"....obbbbbbbbbbo.....",
	"....oaoo....oaao.....",
	"....oao.....oao......",
	"....oo......oo.......",
]
const _WOLF_2 := [
	"..............o.o....",
	".............oaoao...",
	".............oaaaaoo.",
	"oo..........oaaeaaaao",
	"oco.......ooaaaaaaoo.",
	".oco.oooooccaaaaao...",
	"..ocoaacccccaaaao....",
	"...oaaaaaaaaaaaao....",
	"...oaaaaaaaaaaao.....",
	"....obbbbbbbbbbo.....",
	"...oaoao....oaoao....",
	"..oao.oao..oao.oao...",
	"..oo...oo..oo...oo...",
]

const ICONS := {
	"matches": [_MATCHES, {"a": "a83838", "b": "e8e0c8", "w": "c84a2a"}, false, "a83838"],
	"cooked_meat": [_MEAT, {"a": "7a4a2a", "b": "a06a3a", "c": "c8a070", "w": "e8e0d0"}, false, "7a4a2a"],
	"rabbit_1": [_RABBIT_1, {"a": "9a8a7a", "b": "e8e4dc", "e": "1a1016"}, false, "9a8a7a"],
	"rabbit_2": [_RABBIT_2, {"a": "9a8a7a", "b": "e8e4dc", "e": "1a1016"}, false, "9a8a7a"],
	"deer_1": [_DEER_1, {"a": "8a6040", "b": "e8e0d0", "c": "b08a60", "e": "1a1016"}, false, "8a6040"],
	"deer_2": [_DEER_2, {"a": "8a6040", "b": "e8e0d0", "c": "b08a60", "e": "1a1016"}, false, "8a6040"],
	"wolf_1": [_WOLF_1, {"a": "6e6a72", "b": "b8b4b0", "c": "4a4650", "e": "e8c040"}, false, "6e6a72"],
	"wolf_2": [_WOLF_2, {"a": "6e6a72", "b": "b8b4b0", "c": "4a4650", "e": "e8c040"}, false, "6e6a72"],
	"tshirt": [_SHIRT, {"a": "base", "b": "dark"}, false, "6b7a4a"],
	"flannel": [_SHIRT, {"a": "base", "b": "dark", "c": "darker"}, true, "8c3b3b"],
	"hoodie": [_COAT, {"a": "base", "b": "light", "d": "dark"}, false, "5a5f6e"],
	"jacket": [_COAT, {"a": "base", "b": "light", "d": "dark"}, false, "6e4a32"],
	"jeans": [_PANTS, {"a": "base", "b": "dark", "c": "light", "p": "base"}, false, "3b5a8c"],
	"cargo_pants": [_PANTS, {"a": "base", "b": "dark", "c": "light", "p": "dark"}, false, "6a6440"],
	"boots": [_BOOT, {"a": "base", "b": "darker"}, false, "5a4030"],
	"vest": [_VEST, {"a": "base", "b": "light", "c": "dark"}, false, "4e5434"],
	"helmet": [_HELMET, {"a": "base", "b": "light", "c": "darker"}, false, "4e5a3a"],
	"backpack_small": [_PACK, {"a": "base", "b": "dark", "c": "dark", "d": "c9a46a"}, false, "5a6a3a"],
	"backpack_large": [_PACK, {"a": "base", "b": "dark", "c": "dark", "d": "c9a46a"}, false, "6a4a30"],
	"cap": [_CAP, {"a": "base", "b": "light", "c": "dark"}, false, "8a3030"],
	"beanie": [_BEANIE, {"a": "base", "b": "d0c8b0", "c": "light", "d": "dark"}, false, "3a4a5a"],
	"thermo": [_THERMO, {"a": "c04040", "b": "f08080", "c": "cfd8e0"}, false, "c04040"],
	"soda": [_SODA, {"a": "base", "b": "light", "c": "b0b0b8", "w": "e8e4dc"}, false, "a83838"],
	"meat": [_MEAT, {"a": "a83a3a", "b": "d06060", "c": "e8c8b8", "w": "e8e0d0"}, false, "a83a3a"],
}


static func shade(base: Color, role: String) -> Color:
	match role:
		"light":
			return base.lightened(0.28)
		"dark":
			return base.darkened(0.3)
		"darker":
			return base.darkened(0.5)
	return base


func pixel_icon(name: String, color := "") -> Texture2D:
	if name.begins_with("furn_") or FURNITURE.has(name):
		return furniture(name.trim_prefix("furn_"))
	if name in Icons.NAMES:
		var hk := "_hi_%s_%s" % [name, color]
		if not _tex_cache.has(hk):
			_tex_cache[hk] = Icons.make(name, color)
		return _tex_cache[hk]
	var key := "_px_%s_%s" % [name, color]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var spec: Array = ICONS[name]
	var rows: Array = spec[0]
	var pal: Dictionary = spec[1]
	var checker: bool = spec[2]
	var base := Color(color if color != "" else spec[3])
	var img := Image.create_empty(rows[0].length(), rows.size(), false, Image.FORMAT_RGBA8)
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var ch := row[x]
			if ch == ".":
				continue
			if ch == "o":
				img.set_pixel(x, y, Color("1a1016"))
				continue
			if checker and ch == "a" and (x + y) % 2 == 0:
				ch = "c"
			var v: String = pal.get(ch, pal["a"])
			img.set_pixel(x, y, shade(base, v) if v in ["base", "light", "dark", "darker"] else Color(v))
	var t := ImageTexture.create_from_image(img)
	_tex_cache[key] = t
	return t


## One frame of a horizontal sprite sheet.
func sheet_frame(name: String, frames: int, idx: int) -> Texture2D:
	var key := "_sheet_%s_%d" % [name, idx]
	if not _tex_cache.has(key):
		var t := tex(name)
		var w := t.get_width() / frames
		var at := AtlasTexture.new()
		at.atlas = t
		at.region = Rect2(idx * w, 0, w, t.get_height())
		_tex_cache[key] = at
	return _tex_cache[key]


# ---------------------------------------------------------------- furniture (drawn, the packs have none)

const FURNITURE := ["counter", "wardrobe", "medcabinet", "desk", "shelf", "shelf_white", "locker",
	"bed_head", "bed_foot", "table", "sofa", "toilet", "bath"]
const C_OUT := Color("1a1016")


func _box(img: Image, r: Rect2i, fill: Color, outline := true) -> void:
	img.fill_rect(r, C_OUT if outline else fill)
	if outline:
		img.fill_rect(r.grow(-1), fill)


func furniture(name: String) -> Texture2D:
	var key := "_furn_" + name
	if _tex_cache.has(key):
		return _tex_cache[key]
	var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	var wood := Color("6e4a32")
	var wood_d := Color("4a3020")
	var wood_l := Color("8a6040")
	match name:
		"counter":
			_box(img, Rect2i(0, 1, 16, 15), Color("cfc6b4"))
			img.fill_rect(Rect2i(1, 9, 14, 6), wood)
			img.fill_rect(Rect2i(7, 9, 1, 6), wood_d)
			img.fill_rect(Rect2i(5, 11, 1, 2), Color("d8d0c0"))
			img.fill_rect(Rect2i(9, 11, 1, 2), Color("d8d0c0"))
			img.fill_rect(Rect2i(3, 3, 4, 3), Color("9aa0a8"))
		"wardrobe":
			_box(img, Rect2i(1, 0, 14, 16), wood)
			img.fill_rect(Rect2i(2, 1, 12, 2), wood_l)
			img.fill_rect(Rect2i(7, 3, 1, 12), wood_d)
			img.fill_rect(Rect2i(5, 8, 1, 2), Color("c9a46a"))
			img.fill_rect(Rect2i(9, 8, 1, 2), Color("c9a46a"))
		"medcabinet":
			_box(img, Rect2i(2, 3, 12, 11), Color("dcdcd8"))
			img.fill_rect(Rect2i(7, 5, 2, 7), Color("b83a3a"))
			img.fill_rect(Rect2i(5, 7, 6, 2), Color("b83a3a"))
		"desk":
			_box(img, Rect2i(0, 2, 16, 12), wood_l)
			img.fill_rect(Rect2i(1, 11, 14, 2), wood)
			img.fill_rect(Rect2i(3, 4, 5, 4), Color("e8e4dc"))
			img.fill_rect(Rect2i(10, 4, 3, 3), Color("3a3a44"))
		"shelf", "shelf_white":
			var frame := Color("7a7a84") if name == "shelf" else Color("d8d8d4")
			_box(img, Rect2i(0, 0, 16, 16), frame)
			var goods := [Color("b84a3a"), Color("c8a838"), Color("3a6aa8"), Color("4a8a4a"), Color("d8d4cc")]
			if name == "shelf_white":
				goods = [Color("e8e4dc"), Color("b83a3a"), Color("e8e4dc"), Color("6a9ac8")]
			for row in 3:
				img.fill_rect(Rect2i(1, 5 + row * 5, 14, 1), frame.darkened(0.35))
				for i in 4:
					img.fill_rect(Rect2i(2 + i * 3, 2 + row * 5, 2, 3), goods[(row * 4 + i) % goods.size()])
		"locker":
			_box(img, Rect2i(1, 0, 14, 16), Color("4a5a6e"))
			img.fill_rect(Rect2i(7, 1, 1, 14), Color("2e3a48"))
			for i in 3:
				img.fill_rect(Rect2i(3, 2 + i * 2, 3, 1), Color("2e3a48"))
				img.fill_rect(Rect2i(9, 2 + i * 2, 3, 1), Color("2e3a48"))
			img.fill_rect(Rect2i(5, 9, 1, 2), Color("b0b8c0"))
			img.fill_rect(Rect2i(9, 9, 1, 2), Color("b0b8c0"))
		"bed_head":
			_box(img, Rect2i(1, 0, 14, 16), wood)
			img.fill_rect(Rect2i(2, 2, 12, 14), Color("e0d8c8"))
			_box(img, Rect2i(3, 3, 10, 6), Color("f0ece4"))
		"bed_foot":
			_box(img, Rect2i(1, 0, 14, 16), wood)
			img.fill_rect(Rect2i(2, 0, 12, 14), Color("5a6a8c"))
			img.fill_rect(Rect2i(2, 0, 12, 2), Color("7a8aac"))
		"table":
			_box(img, Rect2i(1, 2, 14, 12), wood_l)
			img.fill_rect(Rect2i(2, 3, 12, 1), Color("a07850"))
		"sofa":
			_box(img, Rect2i(0, 2, 16, 13), Color("6a4a5a"))
			img.fill_rect(Rect2i(1, 3, 14, 4), Color("5a3a4a"))
			img.fill_rect(Rect2i(7, 7, 1, 7), Color("4a2e3c"))
		"toilet":
			_box(img, Rect2i(4, 1, 8, 4), Color("e8e8e4"))
			_box(img, Rect2i(3, 4, 10, 10), Color("e8e8e4"))
			img.fill_rect(Rect2i(5, 6, 6, 6), Color("b8c8d0"))
		"bath":
			_box(img, Rect2i(0, 1, 16, 14), Color("e8e8e4"))
			img.fill_rect(Rect2i(2, 3, 12, 10), Color("8ab0c8"))
	var t := ImageTexture.create_from_image(img)
	_tex_cache[key] = t
	return t


## Temperature bar frame: the HP bar frame with the heart swapped for a thermometer.
func temp_bar() -> Texture2D:
	if _tex_cache.has("_temp_bar"):
		return _tex_cache["_temp_bar"]
	var img := tex("ui_hp_bar").get_image()
	img.convert(Image.FORMAT_RGBA8)
	var outline := img.get_pixel(12, 4)
	for y in img.get_height():
		for x in 12:
			img.set_pixel(x, y, Color(0, 0, 0, 0))
	for y in range(3, 9):
		img.set_pixel(11, y, outline)
	var icon := pixel_icon("thermo").get_image()
	img.blend_rect(icon, Rect2i(Vector2i.ZERO, icon.get_size()), Vector2i(1, 0))
	var t := ImageTexture.create_from_image(img)
	_tex_cache["_temp_bar"] = t
	return t


## Grey version of the HP fill, tinted per temperature when drawn.
func temp_fill() -> Texture2D:
	if _tex_cache.has("_temp_fill"):
		return _tex_cache["_temp_fill"]
	var img := tex("ui_hp_fill").get_image()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var l := minf(c.get_luminance() * 2.2, 1.0)
			img.set_pixel(x, y, Color(l, l, l, c.a))
	var t := ImageTexture.create_from_image(img)
	_tex_cache["_temp_fill"] = t
	return t


## Two-colour symbol for an empty inventory slot (shirt shape for the shirt slot, etc.)
func slot_symbol(slot: String) -> Texture2D:
	var key := "_slot_" + slot
	if not _tex_cache.has(key):
		_tex_cache[key] = Icons.slot_symbol(slot, Color("4a3e4a"), Color("6e6070"))
	return _tex_cache[key]
