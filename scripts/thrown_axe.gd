class_name ThrownAxe
extends Node2D
## An axe thrown by an axe zombie. Spins through the air, hurts the player / a bandit it hits,
## and lands as an axe lying on the ground - the zombie comes back for it, unless you take it first.

const SPEED := 380.0
const HIT_RADIUS := 16.0

var world: World
var thrower: Zombie
var dir := Vector2.RIGHT
var max_dist := 300.0
var _flown := 0.0
var _sprite: AnimatedSprite2D


func _ready() -> void:
	var d := Game.dir_name(dir)
	var sheet := "axe_thrown_vertical" if d in ["up", "down"] else "axe_thrown_" + d
	var sf := Game.frames(sheet, {"spin": [sheet, 9, 22.0, true]})
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = sf
	_sprite.scale = Vector2(2, 2)
	_sprite.play("spin")
	add_child(_sprite)
	z_index = 2


func _physics_process(delta: float) -> void:
	var step := dir * SPEED * delta
	var next := global_position + step
	# Hits a wall, window, tree or furniture: drops right in front of it.
	if not world.is_walkable(world.cell_of(next + Vector2(0, 10))):
		_land()
		return
	global_position = next
	_flown += step.length()
	for n in get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("survivors"):
		var t := n as Node2D
		if t.global_position.distance_to(global_position + Vector2(0, 8)) < HIT_RADIUS:
			if (t is Player and not (t as Player).dead) or (t is Survivor and not (t as Survivor).dead):
				Zombie.hit(t, randf_range(22.0, 30.0), dir, thrower if is_instance_valid(thrower) else null)
				_land()
				return
	if _flown >= max_dist:
		_land()


func _land() -> void:
	set_physics_process(false)
	var spot := LootSpot.new()
	spot.is_bag = true
	spot.contents = [Items.used(Items.make("axe"), 25.0, 60.0)]
	spot.position = global_position + Vector2(0, 10)
	get_parent().add_child(spot)
	if is_instance_valid(thrower) and not thrower.dead:
		thrower.axe_landed(spot)
	queue_free()
