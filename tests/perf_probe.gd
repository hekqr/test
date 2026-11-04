extends Node
## Dev tool: measures world generation, autosave, pathfinding and frame-time spikes.
## godot --headless --path . res://tests/perf_probe.tscn

var main: Node
var frame := 0
var worst := 0.0
var worst_phys := 0.0
var t_last := 0


func _ready() -> void:
	Game.save_path = "user://perf_save.json"
	var t0 := Time.get_ticks_msec()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.world.timing = true
	print("startup (generate + spawn): %d ms" % (Time.get_ticks_msec() - t0))
	t_last = Time.get_ticks_usec()


func _process(_delta: float) -> void:
	frame += 1
	var now := Time.get_ticks_usec()
	if frame > 5:
		var ms := (now - t_last) / 1000.0
		worst = maxf(worst, ms)
		if ms > 30.0 and frame > 11:
			print("  spike frame %d: %.1f ms" % [frame, ms])
	t_last = now
	if frame == 10:
		var n := 0
		for g in ["loot", "zombies", "animals", "doors", "taps", "survivors"]:
			print("  %s: %d" % [g, get_tree().get_nodes_in_group(g).size()])
		print("  total nodes: %d" % get_tree().get_node_count())
		var t0 := Time.get_ticks_usec()
		main.save_game()
		print("autosave: %.1f ms (%d KB)" % [(Time.get_ticks_usec() - t0) / 1000.0, FileAccess.get_file_as_bytes(Game.save_path).size() / 1024])
		var t1 := Time.get_ticks_usec()
		var d: Dictionary = main.to_save()
		print("  to_save(): %.1f ms" % ((Time.get_ticks_usec() - t1) / 1000.0))
		var t2 := Time.get_ticks_usec()
		var js := JSON.stringify(d)
		print("  stringify: %.1f ms" % ((Time.get_ticks_usec() - t2) / 1000.0))
		# A zombie outside wants to reach a spot inside a house (door closed)
		var w: World = main.world
		var b: Rect2i = w.buildings[0]
		var inside: Vector2i = w.building_floors[0][0]
		var outside := Vector2i(b.end.x + 3, b.position.y)
		var t3 := Time.get_ticks_usec()
		var path := w.find_path(w.center_of(outside), w.center_of(inside), true)
		print("zombie path into a closed house: %.1f ms (%d points)" % [(Time.get_ticks_usec() - t3) / 1000.0, path.size()])
		var t4 := Time.get_ticks_usec()
		path = w.find_path(w.center_of(outside), w.center_of(inside), false)
		print("person path into a house: %.1f ms" % ((Time.get_ticks_usec() - t4) / 1000.0))
	if frame == 12:
		worst = 0.0
		var t5 := Time.get_ticks_usec()
		main.save_game(true)
		print("background autosave, main-thread part: %.1f ms" % ((Time.get_ticks_usec() - t5) / 1000.0))
	if frame == 1500:
		print("worst frame over ~10 s: %.1f ms" % worst)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
		get_tree().quit()
