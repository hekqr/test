extends Node
## Dev tool: a bot plays the game for a few minutes (walks to loot, searches, fights, eats, crafts,
## builds, sleeps, opens menus, travels to other regions, saves and reloads) and reports problems:
## script errors show in the output; this prints frame spikes, node-count growth and odd states.
## godot --headless --path . res://tests/soak.tscn -- [seconds]

var main: Node
var p: Player
var t := 0.0
var duration := 240.0
var frame := 0
var _last_us := 0
var spikes := 0
var worst := 0.0
var _goal := Vector2.INF
var _path: PackedVector2Array = []
var _repath_t := 0.0
var _act_t := 0.0
var _stuck_t := 0.0
var _last_pos := Vector2.ZERO
var _events := {}
var _nodes0 := 0
var _phase_t := 0.0
var deaths := 0
var travels := 0
var reloads := 0
var issues: Array = []
var _bot_ms := 0.0 # time the bot itself spent (not the game)
var _target: LootSpot = null
var _bad := {} # loot the bot couldn't path to
var _report_t := 0.0
var _frames_since := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		duration = float(args[0])
	Game.save_path = "user://soak_save.json"
	seed(int(Time.get_unix_time_from_system()))
	_start({})


func _start(save: Dictionary) -> void:
	if main:
		main.queue_free()
		await get_tree().process_frame
	Game.pending_load = save
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	p = main.player
	main.world.timing = true # prints slow path searches
	_path = []
	_goal = Vector2.INF
	_last_us = Time.get_ticks_usec()


var _last_event := "-"
var _last_event_t := 0.0


func _note(kind: String) -> void:
	_events[kind] = int(_events.get(kind, 0)) + 1
	_last_event = kind
	_last_event_t = t


func _issue(s: String) -> void:
	if issues.size() < 60 and not issues.has(s):
		issues.append(s)
		print("  ISSUE @%.0fs: %s" % [t, s])


func _process(delta: float) -> void:
	frame += 1
	var now := Time.get_ticks_usec()
	var ms := (now - _last_us) / 1000.0
	_last_us = now
	if frame > 30 and ms > 60.0:
		spikes += 1
		worst = maxf(worst, ms)
		if spikes <= 40 and _last_event != "pause":
			print("  spike %.0f ms at %.1fs (last event: %s at %.1fs)" % [ms, t, _last_event, _last_event_t])
	t += delta
	_frames_since += 1
	_report_t += delta
	if _report_t >= 10.0:
		print("  [%.0fs] fps %.0f  zombies %d  loot %d  nodes %d  region %s  pos %s  busy %.1f  ui %s  paused %s  path %d  goal %s" % [t, _frames_since / _report_t, get_tree().get_nodes_in_group("zombies").size(), get_tree().get_nodes_in_group("loot").size(), get_tree().get_node_count(), main.region if is_instance_valid(main) else "-", Vector2i(p.global_position) if is_instance_valid(p) else Vector2i.ZERO, p.busy_t if is_instance_valid(p) else 0.0, Game.ui_open, get_tree().paused, _path.size(), Vector2i(_goal) if _goal != Vector2.INF else "-"])
		_report_t = 0.0
		_frames_since = 0
	if t >= duration:
		_finish()
		return
	if main == null or not is_instance_valid(main):
		return
	if (p == null or not is_instance_valid(p)) and is_instance_valid(main.player):
		p = main.player
	if p == null or not is_instance_valid(p) or main._travelling:
		return
	if frame == 200:
		_nodes0 = get_tree().get_node_count()
	if t >= duration:
		_finish()
		return
	_check_state()
	if p.dead:
		deaths += 1
		_note("death")
		print("  died at %.0fs (day %d)" % [t, main.day])
		_release()
		_start({})
		return
	_keep_alive()
	_drive(delta)
	_act_t -= delta
	if _act_t <= 0.0:
		_act_t = randf_range(1.5, 4.0)
		_random_action()


## Sanity checks every frame.
func _check_state() -> void:
	if not is_finite(p.global_position.x) or not is_finite(p.global_position.y):
		_issue("player position is not finite")
	var w: World = main.world
	var c := w.cell_of(p.global_position)
	if not w.in_bounds(c):
		_issue("player outside the map at %s" % c)
	elif not w.is_walkable(c) and not w.is_door(c) and w.get_tile(c) != World.WATER:
			_issue("player stuck inside a solid tile %s (tile %d)" % [c, w.get_tile(c)])
	for z in get_tree().get_nodes_in_group("zombies"):
		if not is_finite((z as Node2D).global_position.x):
			_issue("zombie position not finite")
	if p.inv.free_slots() < 0:
		_issue("negative free slots")
	for loc in p.inv.storage_cells():
		var it = p.inv.get_at(loc)
		if it != null and (int(it["count"]) <= 0 or int(it["count"]) > Items.max_stack(it["id"])):
			_issue("bad stack %s x%d" % [it["id"], it["count"]])


## Keep the soak going: top up now and then, but let it get hurt.
func _keep_alive() -> void:
	if p.hunger < 25.0:
		p.hunger = 80.0
	if p.thirst < 25.0:
		p.thirst = 80.0
	if p.health < 20.0 and randf() < 0.002:
		p.health = 70.0
		p.bleeding = false


func _release() -> void:
	for a in ["move_up", "move_down", "move_left", "move_right", "fire", "sprint"]:
		Input.action_release(a)


## Walks along a path to the current goal, shooting / hitting what's near.
func _drive(delta: float) -> void:
	_repath_t -= delta
	if _goal == Vector2.INF or p.global_position.distance_to(_goal) < 30.0 or _repath_t <= 0.0:
		if _goal != Vector2.INF and p.global_position.distance_to(_goal) < 30.0:
			_arrived()
		_pick_goal()
	_stuck_t += delta
	if _stuck_t > 2.0:
		if p.global_position.distance_to(_last_pos) < 8.0 and _path.size() > 0 and not Game.ui_open and p.busy_t <= 0.0:
			_note("stuck")
			if int(_events["stuck"]) <= 8:
				var w: World = main.world
				var c := w.cell_of(p.global_position)
				var rows := PackedStringArray()
				for dy in range(-2, 3):
					var row := ""
					for dx in range(-2, 3):
						var n := c + Vector2i(dx, dy)
						var ch := str(w.get_tile(n))
						if w.is_door(n):
							ch = "D" if w.door_closed[w.idx(n)] == 1 else "d"
						if n == w.cell_of(_path[0]):
							ch = "*"
						row += ("[" + ch + "]") if n == c else (" " + ch + " ")
					rows.append(row)
				print("  STUCK at %s (offset %s) next %s: %s" % [c, (p.global_position - w.center_of(c)).round(), (_path[0] - p.global_position).round(), " / ".join(rows)])
				var nc := w.cell_of(_path[0])
				var col := p.get_last_slide_collision()
				print("     next cell %s tile %d door %s closed %s walkable %s | collider %s at %s" % [nc, w.get_tile(nc), w.is_door(nc), w.door_closed[w.idx(nc)] if w.is_door(nc) else -1, w.is_walkable(nc), col.get_collider() if col else "-", (col.get_position() - p.global_position).round() if col else Vector2.ZERO])
			_goal = Vector2.INF
		_last_pos = p.global_position
		_stuck_t = 0.0
	_release()
	if Game.ui_open or get_tree().paused:
		return
	while _path.size() > 0 and p.global_position.distance_to(_path[0]) < 14.0:
		_path.remove_at(0)
	if _target and is_instance_valid(_target) and p.nearest_loot == _target and p.busy_t <= 0.0:
		_note("interact:" + p.interact_choice())
		p.interact()
		_target = null
		_goal = Vector2.INF
		return
	if _path.size() > 0:
		var d := (_path[0] - p.global_position).normalized()
		if d.x > 0.3:
			Input.action_press("move_right")
		elif d.x < -0.3:
			Input.action_press("move_left")
		if d.y > 0.3:
			Input.action_press("move_down")
		elif d.y < -0.3:
			Input.action_press("move_up")
		if randf() < 0.3:
			Input.action_press("sprint")
	if p.aim_target and p.aim_target.global_position.distance_to(p.global_position) < 260.0:
		Input.action_press("fire")


func _pick_goal() -> void:
	_repath_t = 6.0
	var best: Node2D = null
	var bd := 900.0
	for n in get_tree().get_nodes_in_group("loot"):
		var l := n as LootSpot
		if l.is_store() or (l.opened and l.contents.is_empty() and not l.is_bag) or _bad.has(l.get_instance_id()):
			continue
		var d := l.global_position.distance_to(p.global_position)
		if d < bd and randf() < 0.85:
			bd = d
			best = l
	_target = best as LootSpot
	if best:
		_goal = best.global_position
	else:
		_goal = p.global_position + Vector2.from_angle(randf() * TAU) * randf_range(200.0, 700.0)
	var t0 := Time.get_ticks_usec()
	_path = main.world.find_path(p.global_position, _goal)
	var pms := (Time.get_ticks_usec() - t0) / 1000.0
	if pms > 20.0:
		print("  bot path %.0f ms (%.0f px, %d pts)" % [pms, p.global_position.distance_to(_goal), _path.size()])
	_bot_ms += pms
	if _path.is_empty() or _path[_path.size() - 1].distance_to(_goal) > 60.0:
		if best:
			_bad[best.get_instance_id()] = true
		_goal = Vector2.INF
		_path = []


func _arrived() -> void:
	p._find_loot()
	if p.interact_choice() != "":
		_note("interact:" + p.interact_choice())
		p.interact()


## Something a player does now and then.
func _random_action() -> void:
	if p.busy_t > 0.0:
		return
	var r := randi() % 20
	match r:
		0, 1:
			# Eat / drink / bandage something from the inventory
			for loc in p.inv.storage_cells():
				var it = p.inv.get_at(loc)
				if it == null:
					continue
				var acts: Array = p.actions_for(loc)
				for a in acts:
					if a[1] in ["use", "drink_gourd"]:
						_note("use " + it["id"])
						p.do_action(loc, a[1])
						return
		2:
			_note("inventory")
			main.hud.set_inventory_open(true)
			await get_tree().create_timer(0.5).timeout
			if is_instance_valid(main):
				main.hud.set_inventory_open(false)
		3:
			_note("map")
			main.hud.set_map_open(true)
			await get_tree().create_timer(0.5).timeout
			if is_instance_valid(main):
				main.hud.set_map_open(false)
		4:
			for rc in Crafting.RECIPES:
				if Crafting.missing(rc, p.inv, p.near_bench()) == "":
					_note("craft " + rc["id"])
					p.craft_timed(rc["id"])
					break
		5:
			if p.inv.count_of("sticks") >= 3 and p.inv.count_of("matches") > 0:
				_note("campfire")
				p.build_fire_timed()
		6:
			_note("weapon switch")
			p.switch_weapon(["primary", "secondary", "melee"].pick_random())
		7:
			Game.aim_mode = "mouse" if Game.aim_mode == "auto" else "auto"
		8:
			# Build a base piece
			var kits := ["kit_wall", "kit_chest", "kit_bed", "kit_garden", "kit_workbench", "kit_stove", "kit_snare"]
			var k: String = kits.pick_random()
			p.inv.add(k, 1)
			p.start_placing(k)
			if p.build_problem(p.build_cell()) == "":
				_note("build " + k)
				p.place_kit()
			p.stop_placing()
		9:
			var beds := get_tree().get_nodes_in_group("structures").filter(func(s): return s.kind == "bed")
			if not beds.is_empty() and randf() < 0.4:
				_note("sleep")
				main.sleep()
		10:
			_travel()
		11:
			_reload()
		12:
			_note("pause")
			get_tree().paused = true
			await get_tree().create_timer(0.3, true, false, true).timeout
			get_tree().paused = false
		13:
			_note("weather")
			main._change_weather()
		14:
			# Drop something
			for loc in p.inv.storage_cells():
				if p.inv.get_at(loc) != null and randf() < 0.2:
					_note("drop")
					p.drop(loc)
					break
		15:
			main.time_of_day = randf()
		16, 17:
			_fight()
		18:
			if randf() < 0.5:
				_note("wolves")
				main.spawn_wolf_pack(300.0)
			else:
				_note("bandits")
				main.spawn_survivor_group(300.0, 700.0)
		19:
			# Reload / melee / holster
			_note("reload")
			var ev := InputEventAction.new()
			ev.action = "reload"
			ev.pressed = true
			Input.parse_input_event(ev)
		_:
			pass


## A fight: a gun with ammo (or a melee weapon) and a few zombies of every type close by.
func _fight() -> void:
	_note("fight")
	var guns := ["pistol", "shotgun", "rifle", "hunting_rifle"]
	var g: String = guns.pick_random()
	var slot := Items.equip_of(g)
	p.inv.gear[slot] = Items.make(g)
	p.inv.add(Items.WEAPONS[g]["ammo"], 20)
	p.inv.gear["melee"] = Items.make(["bat", "axe", "knife"].pick_random())
	p.switch_weapon(slot if randf() < 0.8 else "melee")
	for i in randi_range(2, 5):
		var pos: Vector2 = p.global_position + Vector2.from_angle(randf() * TAU) * randf_range(140.0, 300.0)
		if main.world.is_walkable(main.world.cell_of(pos)):
			var type: String = ["walker", "runner", "brute", "axe", "armed"].pick_random()
			main.add_zombie(pos, type, "pistol" if type == "armed" else "", 8)


func _travel() -> void:
	var dir: Vector2i = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN].pick_random()
	_note("travel")
	travels += 1
	main.travel(dir)
	_path = []
	_goal = Vector2.INF


func _reload() -> void:
	_note("save+load")
	reloads += 1
	var data: Dictionary = main.to_save()
	var js := JSON.stringify(data)
	var back = JSON.parse_string(js)
	_release()
	await _start(back)


func _finish() -> void:
	set_process(false)
	_release()
	var nodes := get_tree().get_node_count()
	print("SOAK DONE: %.0fs, %d frames, %d spikes >60ms (worst %.0f ms), deaths %d, travels %d, reloads %d" % [t, frame, spikes, worst, deaths, travels, reloads])
	print("  nodes: %d -> %d" % [_nodes0, nodes])
	print("  zombies %d, loot %d, animals %d, structures %d" % [get_tree().get_nodes_in_group("zombies").size(), get_tree().get_nodes_in_group("loot").size(), get_tree().get_nodes_in_group("animals").size(), get_tree().get_nodes_in_group("structures").size()])
	var keys := _events.keys()
	keys.sort()
	print("  events: " + ", ".join(keys.map(func(k): return "%s %d" % [k, _events[k]])))
	print("  issues: %d" % issues.size())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
	get_tree().quit()
