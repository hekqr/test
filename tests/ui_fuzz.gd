extends Node
## Dev tool: random clicks, drags, double-clicks and menu choices in the inventory screen. After each
## step, every item must still exist exactly once (in your gear / bags or on the ground near you):
## nothing lost, nothing duplicated. Eating / using things is left out (it uses items up).
## godot --headless --path . res://tests/ui_fuzz.tscn -- [steps]

var main: Node
var f := 0
var steps := 1500
var step := 0
var errors := 0
var _before := {}
var _log: Array = []
const SAFE := ["take", "drop", "equip", "unequip", "select", "build"]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		steps = int(args[0])
	Game.save_path = "user://ui_fuzz_%d.json" % OS.get_process_id()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)


func _totals() -> Dictionary:
	var p: Player = main.player
	var t := {}
	var add := func(it):
		if it == null:
			return
		t[it["id"]] = int(t.get(it["id"], 0)) + int(it["count"])
		if Items.is_weapon(it["id"]) and it.has("mag"):
			var ammo: String = Items.WEAPONS[it["id"]].get("ammo", "")
			if ammo != "":
				t[ammo] = int(t.get(ammo, 0)) + int(it["mag"]) # loaded rounds count as ammo
	for s in p.inv.gear:
		var g = p.inv.gear[s]
		add.call(g)
		if g != null and g.has("cargo"):
			for c in g["cargo"]:
				add.call(c)
				if c != null and c.has("cargo"):
					for c2 in c["cargo"]:
						add.call(c2)
	for n in main.entities.get_children():
		var l := n as LootSpot
		if l == null or l.is_queued_for_deletion() or not l.is_bag and not l.is_store():
			continue
		if l.global_position.distance_to(p.global_position) > 150.0:
			continue
		for it in l.contents:
			add.call(it)
			if it.has("cargo"):
				for c in it["cargo"]:
					add.call(c)
					if c != null and c.has("cargo"):
						for c2 in c["cargo"]:
							add.call(c2)
	return t


func _setup_items() -> void:
	var p: Player = main.player
	var inv := p.inv
	inv.gear["back"] = Items.make("backpack_large")
	inv.gear["coat"] = Items.make("jacket")
	inv.gear["primary"] = Items.make("rifle")
	inv.gear["secondary"] = Items.make("pistol")
	for id in ["ammo_556", "ammo_9mm", "bandage", "rags", "planks", "nails", "matches", "soda", "kit_wall", "scrap_metal"]:
		inv.add(id, randi_range(1, 8))
	# A pile next to you with clothes, bags and weapons in it
	var pile := LootSpot.new()
	pile.is_bag = true
	pile.contents = [Items.make("hoodie"), Items.make("backpack_small"), Items.make("bat"), Items.make("shotgun"), Items.make("ammo_12ga", 7), Items.make("cargo_pants"), Items.make("helmet"), Items.make("water")]
	pile.position = p.global_position + Vector2(10, 0)
	main.entities.add_child(pile)
	p._find_loot()


func _process(_d: float) -> void:
	f += 1
	if f == 20:
		_setup_items()
		main.hud.set_inventory_open(true)
		_before = _totals()
		return
	if f < 21:
		return
	if step >= steps:
		print("UI FUZZ DONE: %d steps, %d errors" % [step, errors])
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
		get_tree().quit()
		return
	step += 1
	var p: Player = main.player
	p.busy_t = 0.0
	p._find_loot()
	main.hud.set_inventory_open(true)
	var vs: Vector2 = main.hud.get_viewport_rect().size
	var r := randf()
	var desc := ""
	if r < 0.45:
		# Drag from a random spot to a random spot
		var a := Vector2(randf() * vs.x, randf() * vs.y)
		var b := Vector2(randf() * vs.x, randf() * vs.y)
		var cells := _item_points()
		if not cells.is_empty() and randf() < 0.85:
			a = cells.pick_random()
		if randf() < 0.6:
			var targets := _all_points()
			if not targets.is_empty():
				b = targets.pick_random()
		desc = "drag %s -> %s" % [a.round(), b.round()]
		_mouse(a, true)
		_mouse(b, false)
	elif r < 0.75:
		# Click an item, choose a safe option from its menu
		var cells := _item_points()
		if cells.is_empty():
			return
		var a: Vector2 = cells.pick_random()
		_mouse(a, true)
		_mouse(a, false)
		var m: Dictionary = main.hud._menu
		if not m.is_empty():
			var opts := []
			for i in m["items"].size():
				if m["items"][i][1] in SAFE:
					opts.append(i)
			if not opts.is_empty():
				var i: int = opts.pick_random()
				desc = "menu %s on %s" % [m["items"][i][1], a.round()]
				p.do_action(m["loc"], m["items"][i][1])
				main.hud._menu = {}
				p.stop_placing()
				main.hud.set_inventory_open(true)
			else:
				main.hud._menu = {}
	elif r < 0.85:
		var cells := _item_points()
		if cells.is_empty():
			return
		var a: Vector2 = cells.pick_random()
		var loc: Dictionary = main.hud.loc_at(a)
		var it = p.inv.get_at(loc)
		if it == null or Items.kind(it["id"]) in ["consumable", "medical"]:
			return # double-click would eat / use it
		desc = "double-click %s (%s)" % [a.round(), it["id"]]
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		ev.double_click = true
		ev.position = a
		main.hud._input(ev)
	else:
		desc = "take all"
		if p.inv.near:
			p.inv.near.search(p)
	var after := _totals()
	if after != _before:
		errors += 1
		if errors <= 10:
			var diff := {}
			for k in _before.keys() + after.keys():
				if int(_before.get(k, 0)) != int(after.get(k, 0)):
					diff[k] = "%d -> %d" % [int(_before.get(k, 0)), int(after.get(k, 0))]
			print("  ITEMS CHANGED at step %d after %s: %s" % [step, desc, diff])
			print("    recent: ", _log.slice(-4))
			if errors <= 2:
				var pp: Player = main.player
				print("      GEAR: ", JSON.stringify(pp.inv.gear).left(1500))
				for n in main.entities.get_children():
					var l2 := n as LootSpot
					if l2 and l2.global_position.distance_to(pp.global_position) < 200.0:
						print("      SPOT %s bag=%s d=%.0f: %s" % [l2.kind, l2.is_bag, l2.global_position.distance_to(pp.global_position), JSON.stringify(l2.contents).left(600)])
			for k in diff:
				for n in main.entities.get_children():
					var l := n as LootSpot
					if l == null or l.global_position.distance_to(main.player.global_position) > 400.0:
						continue
					for it in l.contents:
						if it["id"] == k:
							print("      %s x%d in %s bag=%s in_group=%s queued=%s d=%.0f" % [k, it["count"], l.kind, l.is_bag, l.is_in_group("loot"), l.is_queued_for_deletion(), l.global_position.distance_to(main.player.global_position)])
		_before = after
	_log.append(desc)


func _mouse(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	main.hud._input(ev)


## Centres of every cell with an item in it (gear, storage, the nearby list).
func _item_points() -> Array:
	var out := []
	for pt in _all_points():
		var loc: Dictionary = main.hud.loc_at(pt)
		if not loc.is_empty() and main.player.inv.get_at(loc) != null:
			out.append(pt)
	return out


func _all_points() -> Array:
	var out := []
	var vs: Vector2 = main.hud.get_viewport_rect().size
	for y in range(0, int(vs.y), 12):
		for x in range(0, int(vs.x), 12):
			var pt := Vector2(x, y)
			if not main.hud.loc_at(pt).is_empty():
				out.append(pt)
	return out
