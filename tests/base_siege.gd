extends Node
## Dev tool: a walled base with a gate, you standing inside right by the gate (so it's open), and a crowd
## of zombies, wolves and bandits outside going for you for 40 s. Nothing may get inside, and nothing
## may hurt you through the wall or the gate.
## godot --headless --path . res://tests/base_siege.tscn

var main: Node
var f := 0
var ring_c := Vector2i.ZERO
var gate_c := Vector2i.ZERO
var hp0 := 0.0
var inside_hits := 0
var t := 0.0
const R := 3 # the ring: 7 x 7 tiles


func _ready() -> void:
	Game.save_path = "user://siege_%d.json" % OS.get_process_id()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)


func _open_spot(w: World, r: int) -> Vector2i:
	for y in range(40, World.H - 40, 3):
		for x in range(40, World.W - 40, 3):
			var ok := true
			for dy in range(-r - 3, r + 4):
				for dx in range(-r - 3, r + 4):
					if w.get_tile(Vector2i(x + dx, y + dy)) != World.GROUND:
						ok = false
						break
				if not ok:
					break
			if ok and w.settlement_at(Vector2i(x, y)) < 0:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _inside(c: Vector2i) -> bool:
	return absi(c.x - ring_c.x) < R and absi(c.y - ring_c.y) < R


func _process(delta: float) -> void:
	f += 1
	var w: World = main.world
	var p: Player = main.player
	if f == 10:
		for z in get_tree().get_nodes_in_group("zombies"):
			z.free()
		for s in get_tree().get_nodes_in_group("survivors"):
			s.free()
		main._spawn_t = 1e9
		main._survivor_t = 1e9
		main._animal_t = 1e9
		ring_c = _open_spot(w, R)
		if ring_c.x < 0:
			print("SIEGE: no open spot")
			get_tree().quit()
			return
		gate_c = ring_c + Vector2i(R, 0)
		for dx in range(-R, R + 1):
			for dy in range(-R, R + 1):
				if absi(dx) == R or absi(dy) == R:
					var c := ring_c + Vector2i(dx, dy)
					main.add_structure("gate" if c == gate_c else "wall", c)
		main.add_structure("bed", ring_c + Vector2i(-1, -1))
		p.global_position = w.center_of(gate_c + Vector2i(-1, 0))
		p.health = 100.0
		hp0 = p.health
		# The crowd, just outside the gate and around the walls
		var types := ["walker", "runner", "brute", "axe", "armed", "walker", "runner", "armed", "crawler"]
		for i in types.size():
			var pos := w.center_of(gate_c + Vector2i(2 + i % 3, -3 + i))
			main.add_zombie(pos, types[i], "pistol" if types[i] == "armed" else "", 8)
		for i in 3:
			var wolf: Animal = main.spawn_animal("wolf", 0.0)
			if wolf:
				wolf.global_position = w.center_of(gate_c + Vector2i(4, i * 2 - 2))
				wolf.prey = p
		var bandits: Array = main.spawn_survivor_group(0.0, 900.0)
		for i in bandits.size():
			(bandits[i] as Node2D).global_position = w.center_of(gate_c + Vector2i(5, i * 2 - 2))
		for z in get_tree().get_nodes_in_group("zombies"):
			z.foe = p
			z.state = Zombie.State.CHASE
		print("SIEGE: base at %s, gate %s; %d zombies, %d wolves, %d bandits" % [ring_c, gate_c, get_tree().get_nodes_in_group("zombies").size(), get_tree().get_nodes_in_group("wolves").size(), bandits.size()])
	if f <= 10:
		return
	t += delta
	# Keep the player by the gate, inside, and alive; keep everything hostile.
	p.global_position = w.center_of(gate_c + Vector2i(-1, 0))
	p.velocity = Vector2.ZERO
	if p.health < hp0 - 0.5: # (bleeding ticks don't count)
		inside_hits += 1
		if inside_hits <= 12:
			var near := []
			for g in ["zombies", "animals", "survivors"]:
				for n in get_tree().get_nodes_in_group(g):
					var d := (n as Node2D).global_position.distance_to(p.global_position)
					if d < 70.0:
						near.append("%s %s d=%.0f cell %s" % [g, n.get("type") if g == "zombies" else (n.get("species") if g == "animals" else "bandit"), d, w.cell_of((n as Node2D).global_position) - gate_c])
			print("  hit -%.1f at %.1fs  bleeding %s  near: %s" % [hp0 - p.health, t, p.bleeding, near])
		hp0 = p.health
	p.health = maxf(p.health, 50.0)
	hp0 = p.health
	p.hunger = 100.0
	p.bleeding = false
	p.thirst = 100.0
	for s in get_tree().get_nodes_in_group("survivors"):
		s.foe = p
		s.state = Survivor.State.FIGHT
		s._sees = true
	var gate_open: bool = main.structure_at(gate_c).door.open
	for g in ["zombies", "animals", "survivors"]:
		for n in get_tree().get_nodes_in_group(g):
			if _inside(w.cell_of((n as Node2D).global_position)):
				print("  BREACH: a %s got inside at %.1fs (gate open %s)" % [g, t, gate_open])
				(n as Node2D).queue_free()
	if t >= 40.0:
		print("SIEGE DONE: hit %d times through the wall / gate in 40 s; gate open: %s" % [inside_hits, gate_open])
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
		get_tree().quit()
