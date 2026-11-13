extends Node
## Global helpers: input setup, physics layers, noise events.

const LAYER_WALL := 1
const LAYER_PLAYER := 2
const LAYER_ZOMBIE := 4
const LAYER_ANIMAL := 8
const LAYER_NPC := 16 # hostile survivors
const LAYER_WATER := 32 # lakes & rivers: block walking, not bullets or sight
const LAYER_DOOR := 64 # closed doors: block zombies and animals, not people
const LAYER_EDGE := 128 # the edge of a region: creatures stay in, you can walk on to the next region
const LAYER_GATE := 256 # gates you built: only you get through (bandits and zombies never do)

signal noise_made(pos: Vector2, radius: float)

## 0 = full daylight, 1 = darkest night. Set by main.gd.
var night := 0.0
## "clear", "rain" or "snow". Set by main.gd. Rain / snow: colder, you warm up slower; rain: fish bite
## faster and crops grow faster.
var weather := "clear"
## How much colder this region's air is than home (snowfields are much colder).
var region_cold := 0.0
## True while a full-screen UI (inventory) is open: blocks attacking/moving.
var ui_open := false
## Save file location (tests point this somewhere else).
var save_path := "user://save.json" # the slot being played (see SaveGame.slot_path)
var save_slot := 1 # last slot played (remembered in the settings)
## Save data to load when the game scene starts; empty = new game.
var pending_load := {}

## Set by the player to ask the HUD to open the inventory (searching a container).
var open_inventory := false

## Set when a click was used by a UI button, so it doesn't also fire a gun. Cleared on release.
var click_used := false

## "auto": guns lock onto the nearest enemy by themselves, Space shoots, no mouse needed while walking.
## "mouse": aim with the mouse, click to shoot. T switches; remembered between games.
var aim_mode := "auto"
const SETTINGS_PATH := "user://settings.cfg"

## Sound volumes 0..1 (Master, sound effects, ambience: wind, rain, birds).
var vol_master := 0.8
var vol_sfx := 1.0
var vol_ambience := 0.7
## "windowed", "fullscreen" or "borderless"; the window size when windowed; vsync.
var window_mode := "windowed"
var resolution := Vector2i(1280, 720)
var vsync := true
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]

## Rebindable keys, in the order the settings screen lists them: action -> [name, default keys, physical?]
## Letter keys use the printed key label (any keyboard layout); movement / numbers use the key position.
const KEYS := {
	"move_up": ["Move up", [KEY_W, KEY_UP], true],
	"move_down": ["Move down", [KEY_S, KEY_DOWN], true],
	"move_left": ["Move left", [KEY_A, KEY_LEFT], true],
	"move_right": ["Move right", [KEY_D, KEY_RIGHT], true],
	"sprint": ["Sprint", [KEY_SHIFT], true],
	"sneak": ["Sneak", [KEY_CTRL], true],
	"interact": ["Use / search / pick up", [KEY_Q], false],
	"inventory": ["Inventory", [KEY_E, KEY_TAB, KEY_I], false],
	"craft": ["Crafting", [KEY_K], false],
	"map": ["Map", [KEY_M], false],
	"build": ["Build mode", [KEY_B], false],
	"build_fire": ["Make a campfire", [KEY_C], false],
	"fish": ["Fish", [KEY_F], false],
	"throw": ["Throw a stick", [KEY_G], false],
	"fire": ["Shoot (auto aim)", [KEY_SPACE], true],
	"reload": ["Reload", [KEY_R], false],
	"holster": ["Lower weapon / stop", [KEY_X], false],
	"weapon_primary": ["Main weapon", [KEY_1], true],
	"weapon_secondary": ["Secondary weapon", [KEY_2], true],
	"weapon_melee": ["Melee weapon", [KEY_3], true],
	"aim_mode": ["Switch aim mode", [KEY_T], false],
	"help": ["Show / hide help", [KEY_F1], true],
	"pause": ["Pause / back", [KEY_ESCAPE], true],
	"fullscreen": ["Fullscreen", [KEY_F11], true],
	"quit": ["Quit to menu (paused)", [KEY_BACKSPACE], false],
}


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		aim_mode = String(cfg.get_value("controls", "aim_mode", "auto"))
		save_slot = clampi(int(cfg.get_value("game", "slot", 1)), 1, SaveGame.SLOTS)
		vol_master = clampf(float(cfg.get_value("audio", "master", vol_master)), 0.0, 1.0)
		vol_sfx = clampf(float(cfg.get_value("audio", "sfx", vol_sfx)), 0.0, 1.0)
		vol_ambience = clampf(float(cfg.get_value("audio", "ambience", vol_ambience)), 0.0, 1.0)
		window_mode = String(cfg.get_value("display", "mode", window_mode))
		var r = cfg.get_value("display", "resolution", [resolution.x, resolution.y])
		if r is Array and r.size() == 2:
			resolution = Vector2i(int(r[0]), int(r[1]))
		vsync = bool(cfg.get_value("display", "vsync", vsync))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("controls", "aim_mode", aim_mode)
	cfg.set_value("game", "slot", save_slot)
	cfg.set_value("audio", "master", vol_master)
	cfg.set_value("audio", "sfx", vol_sfx)
	cfg.set_value("audio", "ambience", vol_ambience)
	cfg.set_value("display", "mode", window_mode)
	cfg.set_value("display", "resolution", [resolution.x, resolution.y])
	cfg.set_value("display", "vsync", vsync)
	# Keys: only the ones you changed
	if cfg.has_section("keys"):
		cfg.erase_section("keys")
	for action in KEYS:
		var cur := _key_codes(action)
		if cur != _default_codes(action):
			cfg.set_value("keys", action, cur)
	cfg.save(SETTINGS_PATH)


func _ready() -> void:
	load_settings()
	for action in KEYS:
		_key(action, KEYS[action][1], KEYS[action][2])
	if not InputMap.has_action("attack"):
		InputMap.add_action("attack")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("attack", mb)
	# Saved key changes
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK and cfg.has_section("keys"):
		for action in cfg.get_section_keys("keys"):
			if KEYS.has(action):
				var codes = cfg.get_value("keys", action, [])
				if codes is Array:
					_set_codes(action, codes)
	_setup_audio()
	apply_audio()
	apply_display()


# ---------------------------------------------------------------- keys

## The keys of an action as saved text: "p<physical keycode>" / "k<keycode>".
func _key_codes(action: String) -> Array:
	var out := []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			out.append("p%d" % k.physical_keycode if k.physical_keycode != 0 else "k%d" % k.keycode)
	return out


func _default_codes(action: String) -> Array:
	var out := []
	for k in KEYS[action][1]:
		out.append(("p%d" if KEYS[action][2] else "k%d") % k)
	return out


func _set_codes(action: String, codes: Array) -> void:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			InputMap.action_erase_event(action, ev)
	for c in codes:
		var s := String(c)
		if s.length() < 2:
			continue
		var ev := InputEventKey.new()
		if s[0] == "p":
			ev.physical_keycode = int(s.substr(1))
		else:
			ev.keycode = int(s.substr(1))
		InputMap.action_add_event(action, ev)


## Binds a key to an action (replacing its keys). If another action had that key, it gets this
## action's old key instead (a swap). Returns the name of that other action, or "".
func rebind(action: String, ev: InputEventKey) -> String:
	var code := "p%d" % ev.physical_keycode if KEYS[action][2] else "k%d" % (ev.keycode if ev.keycode != 0 else _from_physical(ev.physical_keycode))
	var old := _key_codes(action)
	var swapped := ""
	for other in KEYS:
		if other == action:
			continue
		for oe in InputMap.action_get_events(other):
			if oe is InputEventKey and _same_key(oe as InputEventKey, ev):
				InputMap.action_erase_event(other, oe)
				if InputMap.action_get_events(other).filter(func(e): return e is InputEventKey).is_empty() and not old.is_empty():
					_set_codes(other, [_convert(String(old[0]), KEYS[other][2])])
				swapped = String(KEYS[other][0])
	_set_codes(action, [code])
	save_settings()
	return swapped


func _same_key(a: InputEventKey, b: InputEventKey) -> bool:
	var ka := a.keycode if a.keycode != 0 else _from_physical(a.physical_keycode)
	var kb := b.keycode if b.keycode != 0 else _from_physical(b.physical_keycode)
	return ka == kb


## A saved key code as a physical / label code.
func _convert(code: String, physical: bool) -> String:
	var n := int(code.substr(1))
	if code[0] == "p" and not physical:
		return "k%d" % _from_physical(n)
	if code[0] == "k" and physical:
		return "p%d" % n # (letters / numbers / F-keys have the same code both ways on a standard layout)
	return code


func reset_keys() -> void:
	for action in KEYS:
		_set_codes(action, _default_codes(action))
	save_settings()


## The key label at a physical key position (the same code on a standard layout, or with no display).
func _from_physical(code: int) -> int:
	if DisplayServer.get_name() == "headless":
		return code
	var k := DisplayServer.keyboard_get_keycode_from_physical(code)
	return k if k != 0 else code


## The name of an action's (first) key, for help text: "Q", "Space", "F1"...
func key(action: String) -> String:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			var code := k.keycode if k.keycode != 0 else _from_physical(k.physical_keycode)
			return OS.get_keycode_string(code)
	return "-"


## All of an action's keys: "E / Tab / I".
func keys_text(action: String) -> String:
	var out := PackedStringArray()
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			out.append(OS.get_keycode_string(k.keycode if k.keycode != 0 else _from_physical(k.physical_keycode)))
	return " / ".join(out) if not out.is_empty() else "(none)"


# ---------------------------------------------------------------- audio / display

func _setup_audio() -> void:
	for bus in ["SFX", "Ambience"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")


func apply_audio() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(vol_master, 0.0001)))
	AudioServer.set_bus_mute(0, vol_master <= 0.001)
	for b in [["SFX", vol_sfx], ["Ambience", vol_ambience]]:
		var i := AudioServer.get_bus_index(b[0])
		if i >= 0:
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(float(b[1]), 0.0001)))
			AudioServer.set_bus_mute(i, float(b[1]) <= 0.001)


## F11: fullscreen on / off (remembered).
func toggle_fullscreen() -> void:
	window_mode = "windowed" if window_mode != "windowed" else "borderless"
	apply_display()
	save_settings()


func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	match window_mode:
		"fullscreen":
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		"borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			var screen := DisplayServer.screen_get_usable_rect()
			var size := Vector2i(mini(resolution.x, screen.size.x), mini(resolution.y, screen.size.y))
			DisplayServer.window_set_size(size)
			DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)


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


## Rain drowns out sound: noise only carries 60% as far.
const RAIN_NOISE := 0.6


func make_noise(pos: Vector2, radius: float) -> void:
	noise_made.emit(pos, radius * (RAIN_NOISE if weather == "rain" else 1.0))


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
	"parka": [_COAT, {"a": "base", "b": "light", "d": "dark"}, false, "3b5a8c"],
	"field_jacket": [_COAT, {"a": "base", "b": "light", "d": "dark"}, false, "5a6438"],
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
	"bed_head", "bed_foot", "table", "sofa", "toilet", "bath", "milcrate", "chest", "garden_bed", "camp_bed",
	"workbench", "stove", "storage_shelf", "weapon_rack", "rain_barrel", "snare", "fish_trap"]
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
		"milcrate":
			# Olive ammo / supply crate with a stencil mark
			_box(img, Rect2i(0, 3, 16, 12), Color("5a6438"))
			img.fill_rect(Rect2i(1, 4, 14, 2), Color("6e7a46"))
			img.fill_rect(Rect2i(2, 8, 12, 1), Color("3e4628"))
			img.fill_rect(Rect2i(6, 10, 4, 2), Color("d8d0a0"))
			img.fill_rect(Rect2i(1, 7, 1, 6), Color("8a8e94"))
			img.fill_rect(Rect2i(14, 7, 1, 6), Color("8a8e94"))
		"chest":
			_box(img, Rect2i(1, 4, 14, 11), wood)
			img.fill_rect(Rect2i(2, 5, 12, 3), wood_l)
			img.fill_rect(Rect2i(2, 8, 12, 1), wood_d)
			img.fill_rect(Rect2i(7, 8, 2, 3), Color("c9a46a"))
			img.fill_rect(Rect2i(3, 5, 1, 9), wood_d)
			img.fill_rect(Rect2i(12, 5, 1, 9), wood_d)
		"garden_bed":
			_box(img, Rect2i(0, 1, 16, 14), Color("8a6440"))
			img.fill_rect(Rect2i(2, 3, 12, 10), Color("4e3626"))
			for x in [4, 8, 12]:
				img.fill_rect(Rect2i(x, 4, 1, 8), Color("3e2a1e"))
		"camp_bed":
			_box(img, Rect2i(1, 0, 14, 16), wood)
			img.fill_rect(Rect2i(2, 1, 12, 14), Color("6a7a5a"))
			_box(img, Rect2i(3, 2, 10, 4), Color("e8e0d0"))
			img.fill_rect(Rect2i(2, 8, 12, 1), Color("54623e"))
		"workbench":
			_box(img, Rect2i(0, 3, 16, 9), wood_l)
			img.fill_rect(Rect2i(1, 4, 14, 1), Color("a07850"))
			img.fill_rect(Rect2i(1, 9, 14, 2), wood)
			img.fill_rect(Rect2i(1, 12, 2, 4), wood_d)
			img.fill_rect(Rect2i(13, 12, 2, 4), wood_d)
			# a saw and a hammer on top
			img.fill_rect(Rect2i(2, 6, 6, 2), Color("b0b4bc"))
			img.fill_rect(Rect2i(8, 6, 2, 2), Color("8a3a2a"))
			img.fill_rect(Rect2i(11, 5, 1, 4), Color("6e4a32"))
			img.fill_rect(Rect2i(10, 5, 3, 1), Color("5a5a64"))
		"stove":
			_box(img, Rect2i(2, 2, 12, 12), Color("3e3e46"))
			img.fill_rect(Rect2i(3, 3, 10, 3), Color("5a5a64"))
			img.fill_rect(Rect2i(10, 0, 3, 3), Color("2a2a30"))
			img.fill_rect(Rect2i(5, 8, 6, 4), Color("1a1016"))
			img.fill_rect(Rect2i(3, 14, 2, 2), Color("2a2a30"))
			img.fill_rect(Rect2i(11, 14, 2, 2), Color("2a2a30"))
		"storage_shelf":
			_box(img, Rect2i(0, 0, 16, 16), wood)
			img.fill_rect(Rect2i(1, 1, 14, 14), wood_d.darkened(0.35))
			img.fill_rect(Rect2i(1, 7, 14, 1), wood_l)
			img.fill_rect(Rect2i(1, 14, 14, 1), wood_l)
		"weapon_rack":
			img.fill_rect(Rect2i(3, 1, 10, 14), wood_d.darkened(0.4))
			_box(img, Rect2i(0, 0, 3, 16), wood)
			_box(img, Rect2i(13, 0, 3, 16), wood)
			for y in [5, 10, 15]:
				img.fill_rect(Rect2i(3, y, 10, 1), wood_l)
		"rain_barrel":
			_box(img, Rect2i(2, 1, 12, 14), Color("5a4a3a"))
			img.fill_rect(Rect2i(3, 2, 10, 4), Color("2a2a30"))
			img.fill_rect(Rect2i(2, 8, 12, 1), Color("8a8e94"))
			img.fill_rect(Rect2i(2, 12, 12, 1), Color("8a8e94"))
			img.fill_rect(Rect2i(5, 9, 1, 3), Color("6e5a46"))
			img.fill_rect(Rect2i(10, 9, 1, 3), Color("6e5a46"))
		"snare":
			img.fill_rect(Rect2i(7, 2, 2, 9), C_OUT)
			img.fill_rect(Rect2i(7, 3, 1, 7), wood_l)
			var rope := Color("c8a868")
			for x in range(4, 12):
				img.set_pixel(x, 10, rope)
				img.set_pixel(x, 14, rope)
			for y in range(10, 15):
				img.set_pixel(4, y, rope)
				img.set_pixel(11, y, rope)
		"fish_trap":
			_box(img, Rect2i(1, 4, 14, 9), Color("8a6a44"))
			for x in [4, 7, 10]:
				img.fill_rect(Rect2i(x, 5, 1, 7), Color("6a4e30"))
			img.fill_rect(Rect2i(2, 8, 12, 1), Color("a8865a"))
			img.fill_rect(Rect2i(12, 6, 2, 5), Color("2a2224"))
	var t := ImageTexture.create_from_image(img)
	_tex_cache[key] = t
	return t


## A wooden wall you built (3/4 view: plank tops and the plank face), 16 x 24.
func built_wall() -> Texture2D:
	if _tex_cache.has("_built_wall"):
		return _tex_cache["_built_wall"]
	var img := Image.create_empty(16, 24, false, Image.FORMAT_RGBA8)
	var face := Color("8a5e3a")
	img.fill_rect(Rect2i(0, 0, 16, 8), Color("5e3e26"))
	for x in [0, 4, 8, 12]:
		img.fill_rect(Rect2i(x, 0, 1, 8), Color("4a3020"))
		img.fill_rect(Rect2i(x + 1, 0, 3, 1), Color("7a5636"))
	img.fill_rect(Rect2i(0, 8, 16, 16), face)
	for x in [0, 4, 8, 12]:
		img.fill_rect(Rect2i(x, 8, 1, 16), Color("5e3e26"))
		img.fill_rect(Rect2i(x + 1, 8, 1, 16), face.lightened(0.15))
	img.fill_rect(Rect2i(0, 12, 16, 1), Color("4a3020"))
	img.fill_rect(Rect2i(0, 20, 16, 1), Color("4a3020"))
	for x in [2, 6, 10, 14]:
		img.set_pixel(x, 13, Color("b0b0b8"))
		img.set_pixel(x, 21, Color("b0b0b8"))
	img.fill_rect(Rect2i(0, 23, 16, 1), Color("1a1016"))
	var t := ImageTexture.create_from_image(img)
	_tex_cache["_built_wall"] = t
	return t


## A crop growing in a garden bed: stage 0 sprout, 1 growing, 2 ripe. 16 x 16.
func crop(kind: String, stage: int) -> Texture2D:
	var key := "_crop_%s_%d" % [kind, stage]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	var leaf := Color("4a9a3a")
	var dark := Color("2e6a2a")
	var h: int = [4, 9, 12][clampi(stage, 0, 2)]
	for x in [4, 8, 12]:
		img.fill_rect(Rect2i(x, 14 - h, 1, h), dark)
		img.fill_rect(Rect2i(x - 1, 14 - h, 3, 2), leaf)
		if stage >= 1:
			img.fill_rect(Rect2i(x - 2, 14 - h / 2, 5, 2), leaf)
		if stage == 2:
			if kind == "tomato":
				img.fill_rect(Rect2i(x - 2, 15 - h, 2, 2), Color("d83a2e"))
				img.fill_rect(Rect2i(x + 1, 12 - h / 2, 2, 2), Color("d83a2e"))
			else:
				img.fill_rect(Rect2i(x - 1, 13, 3, 2), Color("b08a58"))
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
