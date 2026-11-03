class_name Zombie
extends CharacterBody2D
## Zombie AI: wanders, investigates noises, chases the player on sight, follows paths around walls.

signal died(zombie: Zombie)

enum State { WANDER, INVESTIGATE, CHASE }

const RADIUS := 11.0
const THINK_INTERVAL := 0.25

var world: World
var player: Player
var big := false
var dead := false
var state := State.WANDER
var health := 70.0
var damage_min := 8.0
var damage_max := 14.0
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
var _sprite: AnimatedSprite2D
var _attack_anim_t := 0.0


func _ready() -> void:
	add_to_group("zombies")
	collision_layer = Game.LAYER_ZOMBIE
	collision_mask = Game.LAYER_WALL | Game.LAYER_PLAYER | Game.LAYER_ZOMBIE
	var circle := CircleShape2D.new()
	circle.radius = RADIUS + (3.0 if big else 0.0)
	var cs := CollisionShape2D.new()
	cs.shape = circle
	add_child(cs)
	if big:
		health = 180.0
		walk_speed *= 0.8
		chase_speed *= 0.78
		damage_min = 18.0
		damage_max = 26.0
	var key := "zbig" if big else "zsmall"
	var spec := {}
	for d in Game.DIRS:
		spec["idle_" + d] = [key + "_idle_" + d, 6, 6.0, true]
		spec["walk_" + d] = [key + "_walk_" + d, 8 if big else 6, 8.0, true]
		spec["attack_" + d] = [key + "_attack_" + d, 8 if big else 4, 14.0, false]
	for d in ["side", "side-left"]:
		spec["death_" + d] = [key + "_death_" + d, 7 if big else 6, 10.0, false]
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = Game.frames(key, spec)
	_sprite.scale = Vector2(2, 2)
	_sprite.offset = Vector2(0, -11 if big else -7)
	_sprite.play("idle_down")
	_sprite.frame = randi() % 4
	add_child(_sprite)
	target = global_position
	facing = Vector2.from_angle(randf() * TAU)


func _physics_process(delta: float) -> void:
	_attack_cd -= delta
	_attack_anim_t -= delta
	_flash_t -= delta
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
	_try_attack()
	_animate(move_dir != Vector2.ZERO)


func _animate(moving: bool) -> void:
	var d := Game.dir_name(facing)
	var anim := ("walk_" if moving else "idle_") + d
	if _attack_anim_t > 0.0:
		anim = "attack_" + d
	if _sprite.animation != anim:
		_sprite.play(anim)
	_sprite.speed_scale = 1.6 if state == State.CHASE and anim.begins_with("walk") else 1.0
	_sprite.modulate = Color(1, 0.45, 0.45) if _flash_t > 0.0 else Color.WHITE


func _think() -> void:
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
	if global_position.distance_to(player.global_position) < RADIUS + Player.RADIUS + (12.0 if big else 8.0):
		_attack_cd = 1.4 if big else 1.1
		_attack_anim_t = 0.35
		facing = (player.global_position - global_position).normalized()
		player.take_damage(randf_range(damage_min, damage_max))


func take_damage(amount: float, dir: Vector2) -> void:
	if dead:
		return
	health -= amount
	_flash_t = 0.12
	_knock = dir * (90.0 if big else 220.0)
	state = State.CHASE
	_lose_t = 5.0
	if health <= 0.0:
		_die(dir)


func _die(dir: Vector2) -> void:
	dead = true
	remove_from_group("zombies")
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	z_index = -5
	_sprite.modulate = Color.WHITE
	_sprite.speed_scale = 1.0
	_sprite.play("death_side" if dir.x >= 0.0 else "death_side-left")
	var blood := Game.make_sprite("blood_%d" % randi_range(1, 5))
	blood.show_behind_parent = true
	blood.position = Vector2(randf_range(-4, 4), 2)
	add_child(blood)
	died.emit(self)
	get_tree().create_timer(45.0).timeout.connect(queue_free)
