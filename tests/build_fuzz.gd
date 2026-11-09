extends Node
## Dev tool: builds and takes apart random things around you (walls, gates, chests, beds, stoves...),
## now and then saves and loads, and checks the world stays consistent:
##   - every wall you built is a solid BUILT tile (for people, zombies and sight), and every BUILT tile is a wall
##   - every gate is a door that zombies can't path through; taken-apart pieces leave walkable ground
##   - nothing is lost: what was in a chest drops to the ground when it's taken apart
## godot --headless --path . res://tests/build_fuzz.tscn -- [steps]

var main: Node
var f := 0
var steps := 400
var step := 0
var errors := 0
var center := Vector2i.ZERO
const KINDS := ["wall", "wall", "wall", "gate", "chest", "bed", "garden", "workbench", "stove", "shelf", "rack", "collector", "snare"]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		steps = int(args[0])
	Game.save_path = "user://build_fuzz_%d.json" % OS.get_process_id()
	_load({})


func _load(save: Dictionary) -> void:
	if main:
		main.free()
	Game.pending_load = save
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)


func _err(s: String) -> void:
	errors += 1
	if errors <= 15:
		print("  ERROR at step %d: %s" % [step, s])


func _check() -> void:
	var w: World = main.world
	var walls := {}
	var gates := {}
	for n in get_tree().get_nodes_in_group("structures"):
		var st := n as Structure
		if st.is_queued_for_deletion():
			continue
		if st.kind == "wall":
			walls[st.cell] = true
			if w.get_tile(st.cell) != World.BUILT or not w.astar.is_point_solid(st.cell) or not w.astar_z.is_point_solid(st.cell) or not w.blocks_sight(st.cell):
				_err("wall at %s isn't solid (tile %d)" % [st.cell, w.get_tile(st.cell)])
		elif st.kind == "gate":
			gates[st.cell] = true
			if not w.is_door(st.cell) or not w.astar_z.is_point_solid(st.cell) or w.astar.is_point_solid(st.cell) or not w.gate_cells.has(st.cell):
				_err("gate at %s is wrong (door %s, zombie-solid %s, person-solid %s)" % [st.cell, w.is_door(st.cell), w.astar_z.is_point_solid(st.cell), w.astar.is_point_solid(st.cell)])
	for dy in range(-12, 13):
		for dx in range(-12, 13):
			var c := center + Vector2i(dx, dy)
			if w.get_tile(c) == World.BUILT and not walls.has(c):
				_err("BUILT tile at %s with no wall" % c)
			if w.gate_cells.has(c) and not gates.has(c):
				_err("gate cell at %s with no gate" % c)
			if not walls.has(c) and not gates.has(c) and w.get_tile(c) == World.GROUND and (w.astar.is_point_solid(c) or w.astar_z.is_point_solid(c)):
				_err("empty ground at %s is solid" % c)


func _process(_d: float) -> void:
	f += 1
	if f == 10:
		var w: World = main.world
		center = w.cell_of(main.player.global_position)
		# Clear open ground to build on
		for y in range(40, World.H - 40, 3):
			for x in range(40, World.W - 40, 3):
				var ok := true
				for dy in range(-13, 14):
					for dx in range(-13, 14):
						if w.get_tile(Vector2i(x + dx, y + dy)) != World.GROUND:
							ok = false
							break
					if not ok:
						break
				if ok:
					center = Vector2i(x, y)
					break
			if center != w.cell_of(main.player.global_position):
				break
		main.player.global_position = w.center_of(center + Vector2i(0, 14))
		for z in get_tree().get_nodes_in_group("zombies"):
			z.free()
		main._spawn_t = 1e9
		return
	if f < 11:
		return
	if step >= steps:
		print("BUILD FUZZ DONE: %d steps, %d errors" % [step, errors])
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
		get_tree().quit()
		return
	step += 1
	var w: World = main.world
	var c := center + Vector2i(randi_range(-10, 10), randi_range(-10, 10))
	var st: Structure = main.structure_at(c)
	var r := randf()
	if st != null and r < 0.45:
		# Take it apart (what's stored in it drops on the ground)
		var stored := 0
		if st.chest:
			for it in st.chest.contents:
				stored += int(it["count"])
		var piles_before := _ground_count()
		var p: Player = main.player
		p.global_position = w.center_of(c) + Vector2(0, 40)
		p.dismantle(st)
		p.finish_busy()
		if main.structure_at(c) != null and not main.structure_at(c).is_queued_for_deletion():
			_err("%s at %s wasn't taken apart" % [st.kind, c])
		if _ground_count() < piles_before + stored:
			_err("things stored in a %s were lost when it was taken apart" % st.kind)
		p.global_position = w.center_of(center + Vector2i(0, 14))
	elif st == null and r < 0.85 and w.get_tile(c) == World.GROUND and not w.is_door(c):
		var k: String = KINDS.pick_random()
		var s2: Structure = main.add_structure(k, c)
		if s2.chest and randf() < 0.7:
			s2.chest.contents.append(Items.make(["bandage", "planks", "nails", "ammo_9mm"].pick_random(), randi_range(1, 5)))
	elif r > 0.97:
		# Save and load
		var data: Dictionary = main.to_save()
		SaveGame.write(data)
		_load(SaveGame.read())
		await get_tree().process_frame
	_check()


func _ground_count() -> int:
	var n := 0
	for l in get_tree().get_nodes_in_group("loot"):
		if l.is_bag and not l.is_queued_for_deletion():
			for it in l.contents:
				n += int(it["count"])
	return n
