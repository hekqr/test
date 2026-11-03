extends Node
## Global helpers: input setup, physics layers, noise events.

const LAYER_WALL := 1
const LAYER_PLAYER := 2
const LAYER_ZOMBIE := 4

signal noise_made(pos: Vector2, radius: float)

## 0 = full daylight, 1 = darkest night. Set by main.gd.
var night := 0.0


func _ready() -> void:
	_key("move_up", [KEY_W, KEY_UP])
	_key("move_down", [KEY_S, KEY_DOWN])
	_key("move_left", [KEY_A, KEY_LEFT])
	_key("move_right", [KEY_D, KEY_RIGHT])
	_key("sprint", [KEY_SHIFT])
	_key("interact", [KEY_E])
	_key("reload", [KEY_R])
	_key("weapon_1", [KEY_1])
	_key("weapon_2", [KEY_2])
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
