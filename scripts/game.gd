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
