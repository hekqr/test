class_name Ambience
extends Node
## Background sound: wind (stronger in snow), rain, crickets at night, birds in daylight.
## Quieter indoors. Fades between them as the weather / time of day changes.

var main: Node
var _players := {} # name -> AudioStreamPlayer
var _bird_t := 3.0
const LOOPS := ["amb_wind", "amb_rain", "amb_crickets"]


func _ready() -> void:
	for n in LOOPS:
		var s := Sfx.stream(n)
		if s == null:
			continue
		var w := (s as AudioStreamWAV).duplicate() as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
		var p := AudioStreamPlayer.new()
		p.stream = w
		p.bus = "Ambience"
		p.volume_db = -60.0
		add_child(p)
		p.play(randf() * w.get_length())
		_players[n] = p


## Target loudness (linear 0..1) of each loop right now.
func _targets() -> Dictionary:
	var p: Player = main.player
	var inside := p != null and p.indoors()
	var w: String = main.weather
	var snowy: bool = main.world.biome == "snow" or w == "snow"
	var wind := 0.22 + (0.35 if snowy else 0.0) + (0.1 if w == "rain" else 0.0)
	var rain := 0.75 if w == "rain" else 0.0
	var crickets := 0.0
	if Game.night > 0.55 and w == "clear" and not snowy:
		crickets = 0.45 * clampf((Game.night - 0.55) / 0.3, 0.0, 1.0)
	if inside:
		wind *= 0.35
		rain *= 0.4
		crickets *= 0.3
	return {"amb_wind": wind, "amb_rain": rain, "amb_crickets": crickets}


func _process(delta: float) -> void:
	if main == null or main.player == null:
		return
	var t := _targets()
	for n in _players:
		var p: AudioStreamPlayer = _players[n]
		var cur := db_to_linear(p.volume_db)
		cur = move_toward(cur, float(t.get(n, 0.0)), delta * 0.4)
		p.volume_db = linear_to_db(maxf(cur, 0.0005))
	# Birds now and then on clear days, away from the snow
	_bird_t -= delta
	if _bird_t <= 0.0:
		_bird_t = randf_range(3.0, 10.0)
		var pl: Player = main.player
		if Game.night < 0.3 and main.weather == "clear" and main.world.biome != "snow" and not pl.dead and not pl.indoors():
			Sfx.at("bird_", pl.global_position + Vector2.from_angle(randf() * TAU) * randf_range(150.0, 450.0), -12.0, 0.15)
