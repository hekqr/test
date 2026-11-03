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


func _ready() -> void:
	_key("move_up", [KEY_W, KEY_UP])
	_key("move_down", [KEY_S, KEY_DOWN])
	_key("move_left", [KEY_A, KEY_LEFT])
	_key("move_right", [KEY_D, KEY_RIGHT])
	_key("sprint", [KEY_SHIFT])
	_key("interact", [KEY_E])
	_key("reload", [KEY_R])
	_key("holster", [KEY_X])
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
