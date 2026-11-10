extends Node
## Dev tool: builds a base the way a player does, with key presses and clicks only:
## chop a tree with an axe (Q), craft kits in the crafting list (K + click), place them (B, then Q),
## open the chest (Q), sleep in the bed (Q). Prints what worked.
## godot --headless --path . res://tests/base_playthrough.tscn

var main: Node
var f := 0
var step := 0
var wait := 0
var fails := 0
var planks0 := 0
var built := []
const KITS := ["kit_wall", "kit_gate", "kit_chest", "kit_bed", "kit_garden", "kit_workbench"]
var kit_i := 0


func _ready() -> void:
	Game.save_path = "user://base_play_%d.json" % OS.get_process_id()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)


func _press(action: String) -> void:
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		Input.parse_input_event(ev)


func _click(pos: Vector2, wheel := 0) -> void:
	pos += main.hud.inv_ofs()
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT if wheel == 0 else MOUSE_BUTTON_WHEEL_DOWN
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		get_viewport().push_input(ev, true)


func _ok(cond: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		fails += 1


func _process(_d: float) -> void:
	f += 1
	if f < 20:
		return
	if wait > 0:
		wait -= 1
		return
	var p: Player = main.player
	var w: World = main.world
	if p.busy_t > 0.0:
		return # chopping / building: wait like a player would
	match step:
		0:
			for z in get_tree().get_nodes_in_group("zombies"):
				z.free()
			main._spawn_t = 1e9
			main._animal_t = 1e9
			main._survivor_t = 1e9
			# What a player would have found by now: an axe, nails, rope, rags and a backpack
			p.inv.gear["back"] = Items.make("backpack_large")
			p.inv.gear["melee"] = Items.make("axe")
			p.inv.add("nails", 30)
			p.inv.add("rope", 2)
			p.inv.add("rags", 4)
			# Walk up to a tree with open ground around it
			var spot := Vector2.INF
			for y in range(30, World.H - 30, 2):
				for x in range(30, World.W - 30, 2):
					var c := Vector2i(x, y)
					if spot == Vector2.INF and w.get_tile(c) == World.TREE and w.get_tile(c + Vector2i(0, 1)) == World.GROUND:
						var open := true
						for dy in range(2, 8):
							for dx in range(-4, 5):
								if w.get_tile(c + Vector2i(dx, dy)) != World.GROUND:
									open = false
						if open and w.settlement_at(c) < 0:
							spot = w.center_of(c + Vector2i(0, 1))
			p.global_position = spot
			planks0 = p.inv.count_of("planks")
			wait = 40 # (what is near you is looked up every 0.1 s)
			step = 1
		1:
			_ok(p.action_label() == "Chop wood", "next to a tree with an axe the button says: %s" % p.action_label())
			_press("interact")
			wait = 3
			step = 2
		2:
			# (the 4 s of chopping passed)
			if p.inv.count_of("planks") + _ground("planks") < planks0 + 24:
				_press("interact") # keep chopping: 2 planks each time
				wait = 3
				return
			_ok(true, "chopped %d planks with Q" % (p.inv.count_of("planks") + _ground("planks") - planks0))
			if _ground("planks") > 0:
				_press("interact") # pick up what didn't fit
			# Step away from the tree onto the open ground
			p.global_position += Vector2(0, 96)
			wait = 40 # (what is near you is looked up every 0.1 s)
			step = 3
		3:
			_press("craft")
			wait = 3
			step = 4
		4:
			_ok(main.hud.inventory_open and main.hud.left_tab == "craft", "K opens the crafting list")
			step = 5
		5:
			if kit_i >= KITS.size():
				_press("craft")
				wait = 3
				step = 6
				return
			# Scroll the list to the recipe and click it
			var idx := -1
			for i in Crafting.RECIPES.size():
				if Crafting.RECIPES[i]["makes"] == KITS[kit_i]:
					idx = i
			var guard := 0
			while idx - main.hud._craft_scroll >= main.hud.craft_visible_rows() and guard < 30:
				_click(main.hud.NEAR_RECT.get_center(), 1)
				guard += 1
			var before := p.inv.count_of(KITS[kit_i])
			_click(main.hud.craft_row(idx - main.hud._craft_scroll).get_center())
			_ok(p.inv.count_of(KITS[kit_i]) == before + 1, "crafted %s by clicking it (%s)" % [Items.name_of(KITS[kit_i]).to_lower(), p.message])
			kit_i += 1
		6:
			_ok(not main.hud.inventory_open, "K closes it again")
			kit_i = 0
			step = 7
		7:
			if kit_i >= KITS.size():
				step = 9
				return
			if p.placing == "":
				_press("build")
				wait = 2
				return
			if p.placing != KITS[kit_i]:
				_press("build") # B again: next kit
				wait = 2
				return
			# Face a free tile and press Q
			for d in [Vector2.DOWN, Vector2.RIGHT, Vector2.LEFT, Vector2.UP]:
				p.facing = d
				if p.build_problem(p.build_cell()) == "":
					break
			if p.build_problem(p.build_cell()) != "":
				p.global_position += Vector2(64, 0)
				wait = 2
				return
			built.append([KITS[kit_i], p.build_cell()])
			_press("interact")
			wait = 3
			step = 8
		8:
			var last: Array = built[built.size() - 1]
			var st: Structure = main.structure_at(last[1])
			_ok(st != null and st.kind == String(Items.def(last[0])["builds"]), "B then Q built the %s" % Items.name_of(last[0]).to_lower().trim_suffix(" kit"))
			kit_i += 1
			step = 7
		9:
			_press("holster") # X: stop building
			wait = 3
			step = 10
		10:
			_ok(p.placing == "", "X leaves building mode")
			_ok(main.in_base(p.global_position), "with a bed down, this is your base")
			# Q at the chest
			for b in built:
				if b[0] == "kit_chest":
					p.global_position = w.center_of(b[1]) + Vector2(0, 30)
			wait = 40 # (what is near you is looked up every 0.1 s)
			step = 11
		11:
			_ok(p.action_label() == "Open chest", "at the chest the button says: %s" % p.action_label())
			_press("interact")
			wait = 4
			step = 12
		12:
			_ok(main.hud.inventory_open and p.inv.near != null and p.inv.near.kind == "chest", "Q opens the chest")
			_press("interact")
			for b in built:
				if b[0] == "kit_bed":
					p.global_position = w.center_of(b[1]) + Vector2(0, 30)
			main.time_of_day = 22.0 / 24.0
			p.hunger = 100.0
			p.thirst = 100.0
			wait = 40 # (what is near you is looked up every 0.1 s)
			step = 13
		13:
			_ok(p.action_label() == "Sleep", "at the bed the button says: %s" % p.action_label())
			_press("interact")
			wait = 4
			step = 14
		14:
			_ok(absf(main.time_of_day * 24.0 - 7.0) < 0.2, "Q at the bed: slept until %s" % main.clock_text())
			# Take the workbench apart again: B, face it, Q
			for b in built:
				if b[0] == "kit_workbench":
					p.global_position = w.center_of(b[1]) + Vector2(0, 32)
					p.facing = Vector2.UP
			_press("build")
			wait = 4
			step = 15
		15:
			p.facing = Vector2.UP
			_ok(p.action_label().begins_with("Take apart"), "in building mode, facing the workbench: %s" % p.action_label())
			_press("interact")
			wait = 3
			step = 16
		16:
			var gone := true
			for b in built:
				if b[0] == "kit_workbench" and main.structure_at(b[1]) != null:
					gone = false
			_ok(gone and _ground("planks") >= 3, "B then Q took it apart (planks back on the ground)")
			print("BASE PLAYTHROUGH DONE: %d problems" % fails)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
			get_tree().quit()


func _ground(id: String) -> int:
	var n := 0
	for l in get_tree().get_nodes_in_group("loot"):
		if l.is_bag and l.global_position.distance_to(main.player.global_position) < 80.0:
			for it in l.contents:
				if it["id"] == id:
					n += int(it["count"])
	return n
