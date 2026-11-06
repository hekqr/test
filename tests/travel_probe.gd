extends Node
## Dev tool: times travelling between regions (and a save + reload).
var main: Node
var frame := 0

func _ready() -> void:
	Game.save_path = "user://travel_probe.json"
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.world.timing = true

var _last := 0
var _worst := 0.0
var _worst_f := 0

func _process(_d: float) -> void:
	frame += 1
	var now := Time.get_ticks_usec()
	if _last > 0:
		var ms := (now - _last) / 1000.0
		if ms > _worst:
			_worst = ms
			_worst_f = frame
		if ms > 100.0:
			print("   frame %d: %.0f ms (phys frames %d) (region %s)  process %.0f ms, physics %.0f ms" % [frame, ms, Engine.get_physics_frames(), main.region, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
	_last = now
	if frame in [20, 60, 100, 140, 180]:
		var dir: Vector2i = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT][frame / 40 - 0]
		var t0 := Time.get_ticks_msec()
		main.travel(dir)
		print("travel %s -> %s: %d ms   (zombies %d, loot %d, nodes %d)" % [dir, main.region, Time.get_ticks_msec() - t0, get_tree().get_nodes_in_group("zombies").size(), get_tree().get_nodes_in_group("loot").size(), get_tree().get_node_count()])
	if frame == 215:
		var t0 := Time.get_ticks_usec()
		main.save_game(true)
		print("autosave main-thread part after 5 travels: %.1f ms, regions kept %d, save %d KB" % [(Time.get_ticks_usec() - t0) / 1000.0, main.regions_state.size(), FileAccess.get_file_as_bytes(Game.save_path).size() / 1024])
	if frame == 220:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
		get_tree().quit()
