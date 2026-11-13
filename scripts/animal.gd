class_name Animal
extends CharacterBody2D
## Wild animals.
## - Rabbits and deer wander and run away from the player and from noise.
## - Wolves hunt in packs of 2-3: they chase the player (or a bandit) on sight, bite and back off,
##   call the rest of the pack, and run away when badly hurt. They see further at night.
## Kill one and skin the carcass with a knife or axe for raw meat (and leather from deer and wolves).

signal died(animal: Animal)

const SPECIES := {
	"rabbit": {"health": 15.0, "walk": 18.0, "run": 99.0, "fear": 150.0, "meat": 1, "leather": 0, "radius": 7.0, "anim_fps": 8.0},
	"deer": {"health": 80.0, "walk": 21.0, "run": 105.0, "fear": 230.0, "meat": 3, "leather": 1, "radius": 12.0, "anim_fps": 7.0},
	# Wolves: faster than runners (and than you), bite a bit harder than a walker, fragile
	"wolf": {"health": 40.0, "walk": 29.0, "run": 126.0, "fear": 0.0, "meat": 2, "leather": 1, "radius": 10.0, "anim_fps": 10.0,
		"predator": true, "bite": [9.0, 16.0], "sight": 300.0, "sight_night": 380.0},
}

var species := "rabbit"
var world: World
var player: Player
var health := 15.0
var dead := false
## Wolves: who they're hunting (the player or a bandit), and their pack's home area.
var prey: Node2D = null
var home := Vector2.ZERO
var last_hit_by: Node2D = null
var _target := Vector2.ZERO
var _flee_from := Vector2.ZERO
var _flee_t := 0.0
var _think_t := randf() * 0.5
var _wander_t := randf() * 3.0
var _flash_t := 0.0
var _bite_cd := 0.0
var _lost_t := 0.0
var _sprite: AnimatedSprite2D


func _ready() -> void:
	add_to_group("animals")
	var s: Dictionary = SPECIES[species]
	if is_predator():
		add_to_group("wolves")
	health = s["health"] * randf_range(0.9, 1.1)
	collision_layer = Game.LAYER_ANIMAL
	collision_mask = Game.LAYER_WALL | Game.LAYER_WATER | Game.LAYER_DOOR | Game.LAYER_EDGE
	if is_predator():
		collision_mask |= Game.LAYER_PLAYER | Game.LAYER_NPC
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
	if home == Vector2.ZERO:
		home = global_position


func is_predator() -> bool:
	return SPECIES[species].get("predator", false)


func _physics_process(delta: float) -> void:
	_flash_t -= delta
	_flee_t -= delta
	_think_t -= delta
	_bite_cd -= delta
	var s: Dictionary = SPECIES[species]
	if _think_t <= 0.0:
		_think_t = 0.3
		if is_predator():
			_hunt_think()
		elif player and not player.dead:
			var d := global_position.distance_to(player.global_position)
			var fear: float = s["fear"] * (0.55 if Input.is_action_pressed("sprint") == false else 1.0)
			if d < fear:
				scare(player.global_position)
	var speed: float = s["walk"]
	var dir := Vector2.ZERO
	if _flee_t > 0.0:
		speed = s["run"]
		dir = _steer((global_position - _flee_from).normalized())
	elif _prey_ok():
		speed = s["run"]
		var to := prey.global_position - global_position
		# Circle in, bite, back off a little before the next bite
		if _bite_cd > 0.6:
			dir = _steer(-to.normalized().rotated(0.6))
			speed *= 0.6
		elif to.length() > float(s["radius"]) + Player.RADIUS + 4.0:
			dir = _steer(to.normalized())
		_try_bite()
	else:
		_wander_t -= delta
		if _wander_t <= 0.0:
			_wander_t = randf_range(2.0, 6.0)
			var around := home if is_predator() else global_position
			_target = world.random_walkable_near(around, 5 if is_predator() else 4) if randf() < 0.7 else global_position
		if global_position.distance_to(_target) > 6.0:
			dir = (_target - global_position).normalized()
	velocity = dir * speed
	move_and_slide()
	if dir != Vector2.ZERO:
		_sprite.flip_h = dir.x < 0.0
		if _sprite.animation != "move":
			_sprite.play("move")
		_sprite.speed_scale = 1.4 if speed > float(s["walk"]) * 1.5 else 0.7
	elif _sprite.animation != "idle":
		_sprite.play("idle")
	_sprite.modulate = Color(1, 0.5, 0.5) if _flash_t > 0.0 else Color.WHITE


## Steer around walls / trees / water by trying a few angles.
func _steer(dir: Vector2) -> Vector2:
	for a in [0.0, 0.6, -0.6, 1.2, -1.2, 1.8, -1.8]:
		var tdir := dir.rotated(a)
		if world.is_walkable(world.cell_of(global_position + tdir * 24.0)):
			return tdir
	return dir


## Run away from a position (player nearby, gunshot, ...). Wolves only run when they're losing.
func scare(from: Vector2) -> void:
	if is_predator() and health > SPECIES[species]["health"] * 0.3:
		return
	_flee_from = from
	_flee_t = 3.0 if not is_predator() else 6.0
	prey = null


# ---------------------------------------------------------------- wolves

const FIRE_FEAR := 130.0 # wolves won't go for anyone this close to a lit fire


func _near_fire(pos: Vector2) -> bool:
	for f in get_tree().get_nodes_in_group("fires"):
		var fire := f as Campfire
		if fire.lit and fire.global_position.distance_to(pos) < FIRE_FEAR:
			return true
	return false


## Gives up the hunt and backs off (fire).
func scare_from_fire(from: Vector2) -> void:
	_flee_from = from
	_flee_t = 4.0
	prey = null

func _prey_ok() -> bool:
	if prey == null or not is_instance_valid(prey):
		return false
	if prey is Player:
		return not (prey as Player).dead
	if prey is Survivor:
		return not (prey as Survivor).dead
	return false


func _hunt_think() -> void:
	if _flee_t > 0.0:
		return
	var s: Dictionary = SPECIES[species]
	var sight := lerpf(s["sight"], s["sight_night"], Game.night)
	# Wolves keep away from fire: a lit campfire (or stove) near you sends them off.
	if _prey_ok() and _near_fire(prey.global_position):
		scare_from_fire(prey.global_position)
		return
	if _prey_ok():
		var d := global_position.distance_to(prey.global_position)
		var sees := d < sight * 1.4 and world.has_los(global_position, prey.global_position)
		_lost_t = 0.0 if sees else _lost_t + 0.3
		if _lost_t > 4.0:
			prey = null
		return
	var best: Node2D = null
	var best_d := sight
	var options: Array = get_tree().get_nodes_in_group("survivors")
	if player != null and not player.dead:
		options.append(player)
	for n in options:
		var t := n as Node2D
		var d := global_position.distance_to(t.global_position)
		if t is Player:
			d /= (t as Player).visibility() # sneaking: harder to spot; bleeding: easier
		if _near_fire(t.global_position):
			continue
		if d < best_d and world.has_los(global_position, t.global_position):
			best = t
			best_d = d
	if best:
		_set_prey(best)


## Hunt someone, and call the pack.
func _set_prey(who: Node2D) -> void:
	if prey == null and species == "wolf":
		Sfx.at("wolf_snarl", global_position, -2.0, 0.12, 1.0)
	prey = who
	_lost_t = 0.0
	for n in get_tree().get_nodes_in_group("wolves"):
		var w := n as Animal
		if w != self and not w.dead and w.prey == null and w.global_position.distance_to(global_position) < 320.0:
			w.prey = who
			w._lost_t = 0.0


func _try_bite() -> void:
	if _bite_cd > 0.0 or not _prey_ok():
		return
	var s: Dictionary = SPECIES[species]
	var to := prey.global_position - global_position
	if to.length() < float(s["radius"]) + Player.RADIUS + 9.0 and world.has_los(global_position, prey.global_position):
		_bite_cd = randf_range(1.0, 1.4)
		Sfx.at("wolf_snarl", global_position, -4.0, 0.15, 0.4)
		Zombie.hit(prey, randf_range(s["bite"][0], s["bite"][1]), to.normalized(), self)


func take_damage(amount: float, dir: Vector2, from: Node2D = null) -> void:
	if dead:
		return
	health -= amount
	if from is Player:
		FloatText.spawn(get_parent(), global_position, str(int(round(amount))), Color(1, 0.85, 0.4), 13)
	_flash_t = 0.12
	last_hit_by = from if from != null else player
	Game.hit_fx(get_parent(), global_position, dir)
	if health <= 0.0:
		dead = true
		died.emit(self)
		queue_free()
		return
	if not is_predator():
		scare(global_position - dir * 50.0)
		return
	# Wolves turn on whoever hurt them, unless they're badly hurt
	if health < SPECIES[species]["health"] * 0.3 and randf() < 0.6:
		scare(global_position - dir * 50.0)
	else:
		var who: Node2D = from if from != null else player
		if who != null and (who is Player or who is Survivor):
			_set_prey(who)
