class_name Zombie
extends CharacterBody2D
## Zombie AI: wanders, investigates noises, chases the player on sight, follows paths around walls.

signal died(zombie: Zombie)

enum State { WANDER, INVESTIGATE, CHASE }

const RADIUS := 11.0
const THINK_INTERVAL := 0.25

var world: World
var player: Player
var state := State.WANDER
var health := 70.0
var walk_speed := randf_range(28.0, 48.0)
var chase_speed := randf_range(100.0, 125.0)
var facing := Vector2.RIGHT
var target := Vector2.ZERO
var path := PackedVector2Array()

var _path_i := 0
var _think_t := randf() * THINK_INTERVAL
var _repath_t := 0.0
var _wander_t := randf() * 3.0
var _lose_t := 0.0
var _attack_cd := 0.0
var _flash_t := 0.0
var _knock := Vector2.ZERO
var _sees_player := false
var _skin := Color(0.36, 0.52, 0.30)


func _ready() -> void:
	add_to_group("zombies")
	collision_layer = Game.LAYER_ZOMBIE
	collision_mask = Game.LAYER_WALL | Game.LAYER_PLAYER | Game.LAYER_ZOMBIE
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	var cs := CollisionShape2D.new()
	cs.shape = circle
	add_child(cs)
	_skin = _skin.lerp(Color(0.55, 0.56, 0.42), randf())
	target = global_position
	facing = Vector2.from_angle(randf() * TAU)
	rotation = facing.angle()


func _physics_process(delta: float) -> void:
	_attack_cd -= delta
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			queue_redraw()
	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = THINK_INTERVAL
		_think()

	var move_dir := Vector2.ZERO
	var speed := walk_speed
	match state:
		State.CHASE:
			speed = chase_speed
			if _sees_player:
				move_dir = (player.global_position - global_position).normalized()
			else:
				move_dir = _follow_path()
		State.INVESTIGATE:
			speed = (walk_speed + chase_speed) * 0.5
			move_dir = _follow_path()
		State.WANDER:
			move_dir = _follow_path()

	velocity = move_dir * speed + _knock
	_knock = _knock.move_toward(Vector2.ZERO, 900.0 * delta)
	move_and_slide()
	if move_dir != Vector2.ZERO:
		facing = facing.lerp(move_dir, 0.15).normalized()
		rotation = facing.angle()
	_try_attack()


func _think() -> void:
	queue_redraw()
	if player == null or player.dead:
		_sees_player = false
		if state == State.CHASE:
			state = State.WANDER
		_wander(THINK_INTERVAL)
		return
	var d := global_position.distance_to(player.global_position)
	var sight := lerpf(380.0, 220.0, Game.night)
	_sees_player = d < sight and world.has_los(global_position, player.global_position)
	if _sees_player:
		state = State.CHASE
		_lose_t = 5.0
		target = player.global_position
		return
	match state:
		State.CHASE:
			_lose_t -= THINK_INTERVAL
			# For a short while after losing sight they still "know" where you are.
			if _lose_t > 2.5:
				target = player.global_position
			_repath_t -= THINK_INTERVAL
			if _repath_t <= 0.0:
				_repath_t = 0.75
				_set_path(target)
			if _lose_t <= 0.0:
				state = State.WANDER
		State.WANDER:
			_wander(THINK_INTERVAL)


func _wander(dt: float) -> void:
	_wander_t -= dt
	if _wander_t <= 0.0:
		_wander_t = randf_range(3.0, 8.0)
		_set_path(world.random_walkable_near(global_position, 6))


func _set_path(to: Vector2) -> void:
	target = to
	path = world.find_path(global_position, to)
	_path_i = 0


func _follow_path() -> Vector2:
	while _path_i < path.size() and global_position.distance_to(path[_path_i]) < 10.0:
		_path_i += 1
	if _path_i >= path.size():
		if state == State.INVESTIGATE:
			state = State.WANDER
		return Vector2.ZERO
	return (path[_path_i] - global_position).normalized()


func hear(pos: Vector2) -> void:
	if state == State.CHASE:
		return
	state = State.INVESTIGATE
	_set_path(pos)


func _try_attack() -> void:
	if _attack_cd > 0.0 or player == null or player.dead:
		return
	if global_position.distance_to(player.global_position) < RADIUS + Player.RADIUS + 8.0:
		_attack_cd = 1.1
		player.take_damage(randf_range(8.0, 14.0))


func take_damage(amount: float, dir: Vector2) -> void:
	health -= amount
	_flash_t = 0.12
	_knock = dir * 220.0
	state = State.CHASE
	_lose_t = 5.0
	queue_redraw()
	if health <= 0.0:
		died.emit(self)
		queue_free()


func _draw() -> void:
	# Drawn facing +X; node rotation turns it.
	var c := Color(1, 1, 1) if _flash_t > 0.0 else _skin
	draw_circle(Vector2(3, 4).rotated(-rotation), RADIUS, Color(0, 0, 0, 0.3))
	draw_line(Vector2(2, -8), Vector2(19, -7), c.darkened(0.15), 4.0)
	draw_line(Vector2(2, 8), Vector2(19, 7), c.darkened(0.15), 4.0)
	draw_circle(Vector2.ZERO, RADIUS, c.darkened(0.4))
	draw_circle(Vector2(3, 0), 7.0, c)
	if state == State.CHASE:
		draw_circle(Vector2(7, -3), 1.6, Color(1, 0.15, 0.1))
		draw_circle(Vector2(7, 3), 1.6, Color(1, 0.15, 0.1))
