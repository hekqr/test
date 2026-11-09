extends Node
## Dev tool: wanders between regions (and saves / loads now and then). In every region it builds a few
## things and leaves a marked pile; whenever it comes back, everything left there must still be there.
## godot --headless --path . res://tests/region_fuzz.tscn -- [moves]

var main: Node
var f := 0
var moves := 30
var move := 0
var errors := 0
var expect := {} # region key -> {"structures": {cell: kind}, "piles": {pos: count}}
var _wait := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		moves = int(args[0])
	Game.save_path = "user://region_fuzz_%d.json" % OS.get_process_id()
	_load({})


func _load(save: Dictionary) -> void:
	if main:
		main.free()
	Game.pending_load = save
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)


func _err(s: String) -> void:
	errors += 1
	if errors <= 20:
		print("  ERROR (move %d, region %s): %s" % [move, main.region, s])


func _key() -> String:
	return "%d,%d" % [main.region.x, main.region.y]


func _verify() -> void:
	var k := _key()
	if not expect.has(k):
		return
	var e: Dictionary = expect[k]
	for c in e["structures"]:
		var st: Structure = main.structure_at(c)
		if st == null or st.kind != e["structures"][c]:
			_err("%s at %s is gone" % [e["structures"][c], c])
	for pos in e["piles"]:
		var found := false
		for n in get_tree().get_nodes_in_group("loot"):
			var l := n as LootSpot
			if l.is_bag and l.position.distance_to(pos) < 1.0:
				for it in l.contents:
					if it["id"] == "nails" and int(it["count"]) == int(e["piles"][pos]):
						found = true
		if not found:
			_err("the marked pile at %s is gone" % pos)


func _leave_things() -> void:
	var k := _key()
	if not expect.has(k):
		expect[k] = {"structures": {}, "piles": {}}
	var e: Dictionary = expect[k]
	var w: World = main.world
	var p: Player = main.player
	var base := w.cell_of(p.global_position)
	for i in 3:
		for attempt in 40:
			var c := base + Vector2i(randi_range(-12, 12), randi_range(-12, 12))
			if w.get_tile(c) == World.GROUND and not w.is_door(c) and main.structure_at(c) == null and c.distance_to(base) > 2.0:
				var kind: String = ["wall", "chest", "bed", "garden", "stove", "collector"].pick_random()
				main.add_structure(kind, c)
				e["structures"][c] = kind
				break
	var pile := LootSpot.new()
	pile.is_bag = true
	var n := randi_range(1, 29)
	pile.contents = [Items.make("nails", n)]
	pile.position = p.global_position + Vector2(randf_range(-60, 60), randf_range(-60, 60)).round()
	if w.is_walkable(w.cell_of(pile.position)):
		main.entities.add_child(pile)
		e["piles"][pile.position] = n
	else:
		pile.free()


func _process(_d: float) -> void:
	f += 1
	if f < 15:
		return
	if main._travelling:
		return
	if _wait > 0:
		_wait -= 1
		return
	if move >= moves:
		_verify()
		print("REGION FUZZ DONE: %d moves, %d regions, %d errors" % [move, expect.size(), errors])
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
		get_tree().quit()
		return
	_verify()
	_leave_things()
	move += 1
	if randf() < 0.2:
		SaveGame.write(main.to_save())
		_load(SaveGame.read())
		_wait = 5
		return
	# Stay within a 3 x 3 patch of regions so we keep coming back
	var dirs := []
	for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var nr: Vector2i = main.region + d
		if absi(nr.x) <= 1 and absi(nr.y) <= 1:
			dirs.append(d)
	main.travel(dirs.pick_random())
	_wait = 5
