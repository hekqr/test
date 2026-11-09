extends Node
## Dev tool: presses random keys in random situations (inventory / map / pause open, busy, building,
## low health, dead...) and checks the game never ends up in a broken state:
##   - the "a menu is open" flag matches what's actually open
##   - the player isn't stuck inside a wall
##   - the game isn't left paused with no pause menu
## Script errors show in the output.
## godot --headless --path . res://tests/key_fuzz.tscn -- [steps]

var main: Node
var steps := 3000
var step := 0
var f := 0
var issues := {}
var _held := {}
var _recent: Array = []
const ACTIONS := ["move_up", "move_down", "move_left", "move_right", "sprint", "interact", "fish", "build",
	"reload", "holster", "build_fire", "craft", "map", "weapon_primary", "weapon_secondary", "weapon_melee",
	"fire", "aim_mode", "inventory", "help", "pause", "attack"]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		steps = int(args[0])
	Game.save_path = "user://key_fuzz_%d.json" % OS.get_process_id()
	seed(int(Time.get_unix_time_from_system()))
	process_mode = Node.PROCESS_MODE_ALWAYS # keeps pressing keys while the game is paused
	_new_main()


func _new_main() -> void:
	if main:
		get_tree().paused = false
		main.free()
	Game.pending_load = {}
	main = load("res://scenes/main.tscn").instantiate()
	main.process_mode = Node.PROCESS_MODE_PAUSABLE # as if it were the scene (this node always runs)
	add_child(main)
	var p: Player = main.player
	var inv := p.inv
	inv.gear["back"] = Items.make("backpack_large")
	inv.gear["primary"] = Items.make("shotgun")
	inv.gear["secondary"] = Items.make("pistol")
	inv.gear["melee"] = Items.make("axe")
	inv.gear["hands"] = Items.make("fishing_rod")
	for id in ["ammo_12ga", "ammo_9mm", "sticks", "matches", "bandage", "soda", "kit_wall", "kit_chest", "planks", "nails", "rope", "rags"]:
		inv.add(id, randi_range(2, 10))


func _issue(s: String) -> void:
	var k := s.left(18)
	issues[k] = int(issues.get(k, 0)) + 1
	if issues[k] <= 3:
		print("  ISSUE at step %d: %s   (recent keys: %s)" % [step, s, _recent.slice(-6)])


func _process(_d: float) -> void:
	f += 1
	if f < 20:
		return
	if step >= steps:
		_finish()
		return
	if main == null or not is_instance_valid(main) or main.is_queued_for_deletion():
		_new_main()
		return
	var p: Player = main.player
	var hud = main.hud
	# --- invariants (checked every frame)
	var menus: bool = hud.inventory_open or hud.map_open
	if Game.ui_open != menus:
		_issue("ui_open %s but inventory %s / map %s" % [Game.ui_open, hud.inventory_open, hud.map_open])
		Game.ui_open = menus
	var w: World = main.world
	var c := w.cell_of(p.global_position)
	if w.in_bounds(c) and not w.is_walkable(c) and not w.is_door(c) and not w.get_tile(c) in [World.WATER, World.TREE]:
		_issue("player inside a solid tile (%d)" % w.get_tile(c))
	if p.dead and get_tree().paused:
		_issue("paused while dead")
	step += 1
	# --- something happens
	var r := randf()
	if r < 0.05:
		# Change the situation
		match randi() % 7:
			0:
				p.health = randf_range(1.0, 25.0)
			1:
				p.bleeding = true
			2:
				p.hunger = 0.0
			3:
				main.add_zombie(p.global_position + Vector2.from_angle(randf() * TAU) * 120.0, ["walker", "runner", "armed"].pick_random(), "pistol", 4)
			4:
				p.start_busy("Testing..", randf_range(0.2, 2.0), func(): pass)
			5:
				if randf() < 0.3 and not get_tree().paused:
					p.take_damage(1000.0) # dies
			6:
				main.time_of_day = randf()
	# Press or release a random key
	var action: String = ACTIONS.pick_random()
	if p.dead and action in ["interact", "pause", "reload"]:
		action = "inventory" # (Esc / R on the death screen leave this scene, which would end the test run)
	if get_tree().paused and action == "interact":
		action = "pause"
	var ev := InputEventAction.new()
	ev.action = action
	var hold: bool = action.begins_with("move") or action in ["sprint", "fire", "attack"]
	if hold:
		ev.pressed = not _held.get(action, false)
		_held[action] = ev.pressed
	else:
		ev.pressed = true
	Input.parse_input_event(ev)
	_recent.append(action + ("+" if ev.pressed else "-"))
	if not hold:
		var up := InputEventAction.new()
		up.action = action
		up.pressed = false
		Input.parse_input_event(up)
	if p.dead and randf() < 0.02:
		_new_main() # a new survivor
	# Unpause now and then if the bot left the game paused for long (the pause menu is fine)
	if get_tree().paused and randf() < 0.05:
		get_tree().paused = false


func _finish() -> void:
	get_tree().paused = false
	print("KEY FUZZ DONE: %d steps, %d issues" % [step, issues.size()])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
	get_tree().quit()
