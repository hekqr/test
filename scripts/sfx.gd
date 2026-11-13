extends Node
## Sound effects (autoload "Sfx"). The sounds are made by tools/make_sfx.py (synthesised, no recordings).
##   Sfx.at("gun_pistol", pos)      a sound somewhere in the world (quieter / panned with distance)
##   Sfx.ui("ui_click")             a flat sound (menus, your own small actions)
## Names ending in _ get a random numbered variant: "hurt_" -> hurt_1 / hurt_2 / hurt_3.

const DIR := "res://assets/sfx/"
const POOL := 28
const HEARING := 1300.0 # px: beyond this you don't hear it

var _cache := {}
var _variants := {}
var _pool: Array[AudioStreamPlayer2D] = []
var _flat: Array[AudioStreamPlayer] = []
var _next := 0
var _next_flat := 0
var _last := {} # name -> time it last started (stops the same sound stacking up)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL:
		var p := AudioStreamPlayer2D.new()
		p.bus = "SFX"
		p.max_distance = HEARING
		p.attenuation = 1.6
		p.panning_strength = 0.6
		add_child(p)
		_pool.append(p)
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_flat.append(p)


func stream(name: String) -> AudioStream:
	if name.ends_with("_"):
		if not _variants.has(name):
			var n := 0
			while ResourceLoader.exists(DIR + name + str(n + 1) + ".wav"):
				n += 1
			_variants[name] = n
		var count: int = _variants[name]
		if count == 0:
			return null
		name = name + str(randi_range(1, count))
	if not _cache.has(name):
		_cache[name] = load(DIR + name + ".wav") if ResourceLoader.exists(DIR + name + ".wav") else null
	return _cache[name]


func _too_soon(name: String, gap: float) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(name, -10.0)) < gap:
		return true
	_last[name] = now
	return false


## A sound at a place in the world. vol_db: louder / quieter than the file; pitch_var: random pitch
## spread so repeats don't sound identical; gap: don't restart the same sound within this many seconds.
func at(name: String, pos: Vector2, vol_db := 0.0, pitch_var := 0.08, gap := 0.03) -> void:
	if _too_soon(name, gap):
		return
	var cam := get_viewport().get_camera_2d()
	if cam and cam.get_screen_center_position().distance_to(pos) > HEARING:
		return
	var s := stream(name)
	if s == null:
		return
	var p := _pool[_next]
	_next = (_next + 1) % POOL
	p.stream = s
	p.global_position = pos
	p.volume_db = vol_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()


## A sound without a place (menus, the inventory, things in your own hands).
func ui(name: String, vol_db := 0.0, pitch_var := 0.04, gap := 0.03) -> void:
	if _too_soon(name, gap):
		return
	var s := stream(name)
	if s == null:
		return
	var p := _flat[_next_flat]
	_next_flat = (_next_flat + 1) % _flat.size()
	p.stream = s
	p.volume_db = vol_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()


## A gunshot for the ammo it fires.
func gun(ammo: String, pos: Vector2, vol_db := 0.0) -> void:
	var n: String = {"ammo_9mm": "gun_pistol", "ammo_12ga": "gun_shotgun", "ammo_556": "gun_rifle", "ammo_308": "gun_hunting"}.get(ammo, "gun_pistol")
	at(n, pos, vol_db, 0.05, 0.0)


## The sound of a timed action, by its label ("Searching..", "Chopping.."...).
func for_action(label: String, pos: Vector2) -> void:
	var l := label.to_lower()
	var n := ""
	var v := -4.0
	if l.begins_with("search") or l.begins_with("skinning") or l.begins_with("harvest") or l.begins_with("planting"):
		n = "rustle"
	elif l.begins_with("chop"):
		n = "chop"
		v = 0.0
	elif l.begins_with("eat"):
		n = "eat"
	elif l.begins_with("drink"):
		n = "drink"
	elif l.begins_with("bandag") or l.begins_with("tearing") or l.begins_with("using first"):
		n = "bandage"
	elif l.begins_with("building a fire"):
		n = "ignite"
	elif l.begins_with("build") or l.begins_with("dismantl") or l.begins_with("repair"):
		n = "hammer"
	if n != "":
		at(n, pos, v, 0.08, 0.2)


## A looping sound for a node (campfire crackle): a positional player that stays on it.
func loop_on(node: Node2D, name: String, vol_db := 0.0, dist := 500.0) -> AudioStreamPlayer2D:
	var s := stream(name)
	if s == null:
		return null
	if s is AudioStreamWAV:
		var w := (s as AudioStreamWAV).duplicate() as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
		s = w
	var p := AudioStreamPlayer2D.new()
	p.stream = s
	p.bus = "SFX"
	p.volume_db = vol_db
	p.max_distance = dist
	p.autoplay = true
	node.add_child(p)
	return p
