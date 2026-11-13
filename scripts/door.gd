class_name Door
extends Node2D
## A door that opens by itself when a person (you or a bandit) walks up to it, and closes again once
## nobody is standing in the doorway. Zombies and animals can't open doors: a closed door blocks them
## (and their pathfinding) and blocks their sight - so they only get inside if they're right behind you.

const OPEN_RADIUS := 40.0 # a person this close opens it
const CLEAR_RADIUS := 28.0 # it won't close on something standing in it

var world: World
var cell := Vector2i.ZERO
var metal := false
## The door drawn on the building's front wall (3/4 view), for front doors.
var front: Sprite2D = null
var tex_closed := "door_wood_closed"
var tex_open := "door_wood" # "" = just the dark doorway
var open := false
var across_x := true # in a horizontal wall (you walk through it up / down)
## A gate you built: it opens for you only, and even open it never lets zombies, animals or bandits in
## (your base stays safe).
var gate := false
var _shape: CollisionShape2D
var _t := randf() * 0.1


var _born := 0


func _ready() -> void:
	_born = Time.get_ticks_msec()
	add_to_group("doors")
	position = world.center_of(cell)
	across_x = world._is_wallish(cell + Vector2i(-1, 0)) or world._is_wallish(cell + Vector2i(1, 0))
	var body := StaticBody2D.new()
	body.collision_layer = Game.LAYER_DOOR | (Game.LAYER_GATE if gate else 0)
	body.collision_mask = 0
	_shape = CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(World.T, World.T)
	_shape.shape = rs
	body.add_child(_shape)
	add_child(body)
	_apply(false)


func _physics_process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.1
	var want := _person_near()
	if want != open and (want or not _occupied()):
		_apply(want)


func _person_near() -> bool:
	for n in get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if not p.dead and p.global_position.distance_to(global_position) < OPEN_RADIUS:
			return true
	if gate:
		return false
	for n in get_tree().get_nodes_in_group("survivors"):
		if (n as Node2D).global_position.distance_to(global_position) < OPEN_RADIUS:
			return true
	return false


## Something (a zombie, an animal) is standing in the doorway.
func _occupied() -> bool:
	for g in ["zombies", "animals"]:
		for n in get_tree().get_nodes_in_group(g):
			if (n as Node2D).global_position.distance_to(global_position) < CLEAR_RADIUS:
				return true
	return false


func _apply(o: bool) -> void:
	if o != open and is_inside_tree() and Time.get_ticks_msec() - _born > 500:
		Sfx.at("door_open" if o else "door_close", global_position, -6.0 if not gate else -3.0, 0.1, 0.2)
	open = o
	_shape.set_deferred("disabled", o and not gate)
	world.set_door_open(cell, o, gate)
	if front:
		var tn := tex_open if o else tex_closed
		front.visible = tn != ""
		if tn != "":
			front.texture = Game.tex(tn)
			front.position.y = -front.texture.get_height()
	queue_redraw()


## Seen from above (inside the building): a door panel across the doorway, or swung open against the frame.
func _draw() -> void:
	var T := float(World.T)
	var col := Color("5e646c") if metal else Color("6e4a2e")
	var r: Rect2
	if not open:
		r = Rect2(-T / 2.0, -3, T, 6) if across_x else Rect2(-3, -T / 2.0, 6, T)
	else:
		r = Rect2(-T / 2.0, -T / 2.0, 5, T) if across_x else Rect2(-T / 2.0, -T / 2.0, T, 5)
	draw_rect(r.grow(1), Color("2a1a14"))
	draw_rect(r, col)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 1) if r.size.x > r.size.y else Vector2(1, r.size.y)), col.lightened(0.25))
	if not open:
		draw_rect(Rect2(r.get_center() + (Vector2(T * 0.3, -1) if across_x else Vector2(-1, T * 0.3)), Vector2(2, 2)), Color("c8b070"))
