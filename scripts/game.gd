extends Node
## Global helpers: input setup, physics layers, noise events.

const LAYER_WALL := 1
const LAYER_PLAYER := 2
const LAYER_ZOMBIE := 4

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
	_key("interact", [KEY_E])
	_key("reload", [KEY_R])
	_key("holster", [KEY_X])
	_key("weapon_primary", [KEY_1])
	_key("weapon_secondary", [KEY_2])
	_key("weapon_melee", [KEY_3])
	for pair in [["weapon_next", MOUSE_BUTTON_WHEEL_DOWN], ["weapon_prev", MOUSE_BUTTON_WHEEL_UP]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
			var wb := InputEventMouseButton.new()
			wb.button_index = pair[1]
			InputMap.action_add_event(pair[0], wb)
	_key("inventory", [KEY_TAB, KEY_I])
	_key("eat", [KEY_F])
	_key("drink", [KEY_G])
	_key("bandage", [KEY_H])
	_key("help", [KEY_F1])
	_key("pause", [KEY_ESCAPE])
	_key("fullscreen", [KEY_F11])
	_key("quit", [KEY_Q])
	if not InputMap.has_action("attack"):
		InputMap.add_action("attack")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("attack", mb)


func _key(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
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

const ICONS := {
	"tshirt": [_SHIRT, {"a": "6b7a4a", "b": "4e5a36"}, false],
	"flannel": [_SHIRT, {"a": "8c3b3b", "b": "5e2a2e", "c": "6a2a2a"}, true],
	"hoodie": [_COAT, {"a": "5a5f6e", "b": "8a8f9e", "d": "3e4250"}, false],
	"jacket": [_COAT, {"a": "6e4a32", "b": "a07050", "d": "4a3020"}, false],
	"jeans": [_PANTS, {"a": "3b5a8c", "b": "2a3e63", "c": "5878a8", "p": "3b5a8c"}, false],
	"cargo_pants": [_PANTS, {"a": "6a6440", "b": "4a4630", "c": "8a8458", "p": "4a4630"}, false],
	"boots": [_BOOT, {"a": "5a4030", "b": "2a1e18"}, false],
	"vest": [_VEST, {"a": "4e5434", "b": "7a8050", "c": "3a3e26"}, false],
	"helmet": [_HELMET, {"a": "4e5a3a", "b": "7a8a5a", "c": "2e3422"}, false],
	"backpack_small": [_PACK, {"a": "5a6a3a", "b": "46542e", "c": "4a5830", "d": "c9a46a"}, false],
	"backpack_large": [_PACK, {"a": "6a4a30", "b": "553a24", "c": "5a3e28", "d": "c9a46a"}, false],
}


func pixel_icon(name: String) -> Texture2D:
	var key := "_px_" + name
	if _tex_cache.has(key):
		return _tex_cache[key]
	var spec: Array = ICONS[name]
	var rows: Array = spec[0]
	var pal: Dictionary = spec[1]
	var checker: bool = spec[2]
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
			img.set_pixel(x, y, Color(pal.get(ch, pal["a"])))
	var t := ImageTexture.create_from_image(img)
	_tex_cache[key] = t
	return t
