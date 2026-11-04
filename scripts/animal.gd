class_name Animal
extends CharacterBody2D
## Wild animals (rabbit, deer). They wander, and run away from the player and from noise.
## Kill one and skin the carcass with a knife or axe to get raw meat.

signal died(animal: Animal)

const SPECIES := {
	"rabbit": {"health": 15.0, "walk": 30.0, "run": 165.0, "fear": 150.0, "meat": 1, "radius": 7.0, "anim_fps": 8.0},
	"deer": {"health": 80.0, "walk": 35.0, "run": 175.0, "fear": 230.0, "meat": 3, "radius": 12.0, "anim_fps": 7.0},
}

var species := "rabbit"
var world: World
var player: Player
var health := 15.0
var dead := false
var _target := Vector2.ZERO
var _flee_from := Vector2.ZERO
var _flee_t := 0.0
var _think_t := randf() * 0.5
var _wander_t := randf() * 3.0
var _flash_t := 0.0
var _sprite: AnimatedSprite2D


func _ready() -> void:
	add_to_group("animals")
	var s: Dictionary = SPECIES[species]
	health = s["health"]
	collision_layer = Game.LAYER_ANIMAL
	collision_mask = Game.LAYER_WALL
	var circle := CircleShape2D.new()
	circle.radius = s["radius"]
	var cs := CollisionShape2D.new()
	cs.shape = circle
	add_child(cs)
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	sf.add_animation("move")
	sf.set_animation_speed("move", s["anim_fps"])
	sf.add_frame("move", Game.pixel_icon(species + "_1"))
	sf.add_frame("move", Game.pixel_icon(species + "_2"))
	sf.add_animation("idle")
	sf.add_frame("idle", Game.pixel_icon(species + "_1"))
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = sf
	_sprite.scale = Vector2(2, 2)
	_sprite.offset = Vector2(0, -_sprite.sprite_frames.get_frame_texture("idle", 0).get_height() / 2.0 + 2.0)
	_sprite.play("idle")
	add_child(_sprite)
	_target = global_position


func _physics_process(delta: float) -> void:
	_flash_t -= delta
	_flee_t -= delta
	_think_t -= delta
	var s: Dictionary = SPECIES[species]
	if _think_t <= 0.0:
		_think_t = 0.3
		if player and not player.dead:
			var d := global_position.distance_to(player.global_position)
			var fear: float = s["fear"] * (0.55 if Input.is_action_pressed("sprint") == false else 1.0)
			if d < fear:
				scare(player.global_position)
	var speed: float = s["walk"]
	var dir := Vector2.ZERO
	if _flee_t > 0.0:
		speed = s["run"]
		dir = (global_position - _flee_from).normalized()
		# Steer around walls / trees by trying a few angles.
		for a in [0.0, 0.6, -0.6, 1.2, -1.2, 1.8, -1.8]:
			var tdir := dir.rotated(a)
			if world.is_walkable(world.cell_of(global_position + tdir * 24.0)):
				dir = tdir
				break
	else:
		_wander_t -= delta
		if _wander_t <= 0.0:
			_wander_t = randf_range(2.0, 6.0)
			_target = world.random_walkable_near(global_position, 4) if randf() < 0.7 else global_position
		if global_position.distance_to(_target) > 6.0:
			dir = (_target - global_position).normalized()
	velocity = dir * speed
	move_and_slide()
	if dir != Vector2.ZERO:
		_sprite.flip_h = dir.x < 0.0
		if _sprite.animation != "move":
			_sprite.play("move")
		_sprite.speed_scale = 2.0 if _flee_t > 0.0 else 1.0
	elif _sprite.animation != "idle":
		_sprite.play("idle")
	_sprite.modulate = Color(1, 0.5, 0.5) if _flash_t > 0.0 else Color.WHITE


## Run away from a position (player nearby, gunshot, ...).
func scare(from: Vector2) -> void:
	_flee_from = from
	_flee_t = 3.0


func take_damage(amount: float, dir: Vector2) -> void:
	if dead:
		return
	health -= amount
	_flash_t = 0.12
	scare(global_position - dir * 50.0)
	if health <= 0.0:
		dead = true
		died.emit(self)
		queue_free()
