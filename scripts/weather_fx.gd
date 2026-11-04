class_name WeatherFX
extends Node2D
## Rain streaks or snowflakes falling across the screen (drawn in screen space, cheap).

var kind := "clear"
var _drops: Array[Vector3] = [] # x, y, speed factor
var _size := Vector2(1280, 720)


func _process(delta: float) -> void:
	if kind == "clear":
		if not _drops.is_empty():
			_drops.clear()
			queue_redraw()
		return
	_size = get_viewport_rect().size
	var want := 220 if kind == "rain" else 160
	while _drops.size() < want:
		_drops.append(Vector3(randf() * _size.x, randf() * _size.y, randf_range(0.7, 1.3)))
	var fall := Vector2(-60.0, 900.0) if kind == "rain" else Vector2(-20.0, 70.0)
	for i in _drops.size():
		var d := _drops[i]
		var sway := sin(Time.get_ticks_msec() / 600.0 + d.x * 0.05) * 18.0 if kind == "snow" else 0.0
		d.x += (fall.x + sway) * d.z * delta
		d.y += fall.y * d.z * delta
		if d.y > _size.y + 10:
			d.y = -10
			d.x = randf() * (_size.x + 100.0)
		if d.x < -20:
			d.x += _size.x + 40
		_drops[i] = d
	queue_redraw()


func _draw() -> void:
	if kind == "rain":
		for d in _drops:
			draw_line(Vector2(d.x, d.y), Vector2(d.x + 2.0, d.y - 14.0 * d.z), Color(0.75, 0.82, 0.95, 0.35), 1.0)
	elif kind == "snow":
		for d in _drops:
			draw_rect(Rect2(d.x, d.y, 2.0 * d.z, 2.0 * d.z), Color(1, 1, 1, 0.75))
