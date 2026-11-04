class_name Zombie
extends CharacterBody2D
## Zombie AI: wanders, investigates noises, chases the player (or a bandit) on sight and follows
## paths around walls.
##
## Types
##   walker  the usual shambler (100 health)
##   runner  very fast (about as fast as you sprint), a bit weaker (80)
##   brute   big, a bit slower, hits 50% harder (300)
##   axe     throws its axe from a distance, then walks over and picks it up again
##           (grab the axe first and it has to fight with its hands) (100)
##   armed   a dead soldier / cop in a vest (armour) that still fires its gun until the magazine
##           is empty; drops the gun when killed (100)
## Every zombie's health, speed and damage vary by up to 10%.

signal died(zombie: Zombie)

enum State { WANDER, INVESTIGATE, CHASE, FETCH }

const RADIUS := 11.0
const THINK_INTERVAL := 0.25
## walk / chase = base speeds, dmg = damage per hit (min, max), armour = points (1 = 10% less damage)
const TYPES := {
	"walker": {"name": "Zombie", "health": 100.0, "walk": 23.0, "chase": 67.0, "dmg": [8.0, 14.0], "cd": 1.1, "reach": 8.0, "knock": 220.0, "armour": 0.0},
	"runner": {"name": "Runner", "health": 80.0, "walk": 30.0, "chase": 114.0, "dmg": [7.0, 12.0], "cd": 0.9, "reach": 8.0, "knock": 260.0, "armour": 0.0},
	"brute": {"name": "Brute", "health": 300.0, "walk": 20.0, "chase": 60.0, "dmg": [12.0, 21.0], "cd": 1.4, "reach": 12.0, "knock": 90.0, "armour": 0.0},
	"axe": {"name": "Axe zombie", "health": 100.0, "walk": 22.0, "chase": 60.0, "dmg": [16.0, 24.0], "cd": 1.3, "reach": 12.0, "knock": 150.0, "armour": 0.0},
	"armed": {"name": "Armed zombie", "health": 100.0, "walk": 22.0, "chase": 58.0, "dmg": [8.0, 14.0], "cd": 1.1, "reach": 8.0, "knock": 200.0, "armour": 3.0},
}
const VARIANCE := 0.1 # each zombie's stats vary by up to 10%
## Armed zombies: [damage min, max, aim time, shots per burst, range]
const ZOMBIE_GUNS := {
	"pistol": [11.0, 16.0, 0.9, 1, 520.0],
	"rifle": [9.0, 13.0, 1.1, 3, 600.0],
}
const THROW_MIN := 90.0
const THROW_MAX := 290.0

var type := "walker"
var world: World
var player: Player
var dead := false
var state := State.WANDER
var health := 70.0
var walk_speed := 40.0
var chase_speed := 110.0
var facing := Vector2.RIGHT
var target := Vector2.ZERO
var path := PackedVector2Array()
## Who it's after: the player or a bandit.
var foe: Node2D = null
## Who hit it last (kills only count for the player when they landed the last hit).
var last_hit_by: Node2D = null
# axe zombie
var has_axe := true
var axe_spot: LootSpot = null
# armed zombie
var gun := ""
var mag := 0

var _t: Dictionary
var max_health := 100.0
var _top := -32.0 # top of the sprite (for the health bar)
var _dmg_mult := 1.0
var _path_i := 0
var _think_t := randf() * THINK_INTERVAL
var _repath_t := 0.0
var _wander_t := randf() * 3.0
var _lose_t := 0.0
var _attack_cd := 0.0
var _flash_t := 0.0
var _knock := Vector2.ZERO
var _sees_foe := false
var _sprite: AnimatedSprite2D
var _held: Sprite2D
var _attack_anim_t := 0.0
var _special_t := 0.0 # throwing / picking up the axe
var _throw_cd := randf_range(0.5, 2.0)
var _aim_t := 0.0
var _burst := 0
var _shots: Array = []
var _shot_t := 0.0
var _tint := Color.WHITE
var _anim_prefix := ""


## Back-compat for older code / tests.
var big: bool:
	get:
		return type == "brute"


func _ready() -> void:
	add_to_group("zombies")
	if not TYPES.has(type):
		type = "walker"
	_t = TYPES[type]
	collision_layer = Game.LAYER_ZOMBIE
	collision_mask = Game.LAYER_WALL | Game.LAYER_PLAYER | Game.LAYER_ZOMBIE | Game.LAYER_NPC | Game.LAYER_WATER | Game.LAYER_DOOR
	add_child(Game.foot_shape(RADIUS + (3.0 if type == "brute" else 0.0), 9.0 if type == "brute" else 7.0))
	health = float(_t["health"]) * _vary()
	max_health = health
	walk_speed = float(_t["walk"]) * _vary()
	chase_speed = float(_t["chase"]) * _vary()
	_dmg_mult = _vary()
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = _make_frames()
	_sprite.scale = Vector2(2, 2)
	match type:
		"runner":
			_sprite.scale = Vector2(1.85, 1.85)
			_tint = Color(1.0, 0.86, 0.78) # paler, flushed skin
		"armed":
			_tint = Color(0.78, 0.86, 0.66) # olive uniform
			if gun == "":
				gun = "pistol" if randf() < 0.6 else "rifle"
				mag = randi_range(3, 8) if gun == "pistol" else randi_range(6, 15)
			_held = Sprite2D.new()
			_held.texture = Items.icon_of(Items.WEAPONS[gun]["held"])
			_held.scale = Vector2.ONE * (2.0 if maxf(_held.texture.get_width(), _held.texture.get_height()) <= 18.0 else 0.85)
			add_child(_held)
	_sprite.play(_anim("idle_down"))
	_sprite.frame = randi() % 4
	add_child(_sprite)
	_fit_offset()
	target = global_position
	facing = Vector2.from_angle(randf() * TAU)


func _make_frames() -> SpriteFrames:
	var key: String = {"walker": "zsmall", "runner": "zsmall", "armed": "zsmall", "brute": "zbig", "axe": "zaxe"}[type]
	var spec := {}
	match key:
		"zsmall", "zbig":
			var b := key == "zbig"
			for d in Game.DIRS:
				spec["idle_" + d] = [key + "_idle_" + d, 6, 6.0, true]
				spec["walk_" + d] = [key + "_walk_" + d, 8 if b else 6, 8.0, true]
				spec["attack_" + d] = [key + "_attack_" + d, 8 if b else 4, 14.0, false]
			for d in ["side", "side-left"]:
				spec["death_" + d] = [key + "_death_" + d, 7 if b else 6, 10.0, false]
		"zaxe":
			# With the axe, and "na_" = after throwing it
			for d in Game.DIRS:
				spec["idle_" + d] = ["zaxe_idle_" + d, 6, 6.0, true]
				spec["walk_" + d] = ["zaxe_walk_" + d, 8, 8.0, true]
				spec["attack_" + d] = ["zaxe_attack_" + d, 7, 14.0, false]
				spec["throw_" + d] = ["zaxe_throw_" + d, 9, 14.0, false]
				spec["na_idle_" + d] = ["zaxe_na_idle_" + d, 6, 6.0, true]
				spec["na_walk_" + d] = ["zaxe_na_walk_" + d, 8, 8.0, true]
				spec["na_attack_" + d] = ["zaxe_na_attack_" + d, 7, 14.0, false]
				spec["take_" + d] = ["zaxe_na_take_" + d, 3, 8.0, false]
			for d in ["side", "side-left"]:
				spec["death_" + d] = ["zaxe_death_" + d, 6, 10.0, false]
				spec["na_death_" + d] = ["zaxe_na_death_" + d, 6, 10.0, false]
	return Game.frames(key, spec)


func _vary() -> float:
	return randf_range(1.0 - VARIANCE, 1.0 + VARIANCE)


## Animation name for this zombie (axe zombies without their axe use the "na_" set).
func _anim(base: String) -> String:
	if type == "axe" and not has_axe and _sprite.sprite_frames.has_animation("na_" + base):
		return "na_" + base
	return base


## Stand on the feet: sheets have different heights, so align the bottom of each frame.
func _fit_offset() -> void:
	var tex := _sprite.sprite_frames.get_frame_texture(_sprite.animation, 0)
	if tex:
		_sprite.offset = Vector2(0, -tex.get_height() / 2.0 + 1.0)
		_top = 2.0 - tex.get_height() * _sprite.scale.y


func _physics_process(delta: float) -> void:
	_attack_cd -= delta
	_attack_anim_t -= delta
	_flash_t -= delta
	_think_t -= delta
	_throw_cd -= delta
	_shot_t -= delta
	if _special_t > 0.0:
		_special_t -= delta
		if _special_t <= 0.0 and state == State.FETCH:
			_pick_up_axe()
	if _think_t <= 0.0:
		_think_t = THINK_INTERVAL
		_think()

	var move_dir := Vector2.ZERO
	var speed := walk_speed
	if _special_t <= 0.0:
		match state:
			State.CHASE:
				speed = chase_speed
				if _sees_foe and _foe_ok():
					move_dir = (foe.global_position - global_position).normalized()
				else:
					move_dir = _follow_path()
			State.INVESTIGATE:
				speed = (walk_speed + chase_speed) * 0.5
				move_dir = _follow_path()
			State.FETCH:
				speed = chase_speed * 0.8
				move_dir = _follow_path()
			State.WANDER:
				move_dir = _follow_path()
	if type == "armed" and _aim_t > 0.0:
		speed *= 0.35 # slows down to aim

	velocity = move_dir * speed + _knock
	_knock = _knock.move_toward(Vector2.ZERO, 900.0 * delta)
	move_and_slide()
	if move_dir != Vector2.ZERO:
		facing = facing.lerp(move_dir, 0.15).normalized()
	if _special_t <= 0.0:
		_try_attack()
		match type:
			"axe":
				_try_throw()
			"armed":
				_try_shoot(delta)
	_animate(move_dir != Vector2.ZERO)
	if _held or _shot_t > -0.1 or health < max_health:
		queue_redraw()


func _animate(moving: bool) -> void:
	var d := Game.dir_name(facing)
	var anim := _anim(("walk_" if moving else "idle_") + d)
	if _special_t > 0.0:
		anim = ("throw_" if state != State.FETCH else "take_") + d
	elif _attack_anim_t > 0.0:
		anim = _anim("attack_" + d)
	if _sprite.animation != anim:
		_sprite.play(anim)
		_fit_offset()
	_sprite.speed_scale = 1.15 if state == State.CHASE and anim.contains("walk") else 0.8
	_sprite.modulate = Color(1, 0.45, 0.45) if _flash_t > 0.0 else _tint
	if _held:
		_held.visible = mag > 0
		var aim := facing
		if _foe_ok():
			aim = (foe.global_position - global_position).normalized()
		_held.flip_v = aim.x < 0.0
		_held.rotation = aim.angle()
		_held.position = Vector2(0, -8) + aim * 10.0
		_held.z_index = -1 if d == "up" else 0


func _foe_ok() -> bool:
	if foe == null or not is_instance_valid(foe):
		return false
	if foe is Player:
		return not (foe as Player).dead
	if foe is Survivor:
		return not (foe as Survivor).dead
	return false


func _think() -> void:
	# Nearest thing it can see: the player or a bandit.
	var sight := lerpf(380.0, 220.0, Game.night)
	var best: Node2D = null
	var best_d := sight
	if player != null and not player.dead:
		var d := global_position.distance_to(player.global_position)
		if d < best_d and world.has_los(global_position, player.global_position):
			best = player
			best_d = d
	for n in get_tree().get_nodes_in_group("survivors"):
		var s := n as Survivor
		var d := global_position.distance_to(s.global_position)
		if d < best_d and world.has_los(global_position, s.global_position):
			best = s
			best_d = d
	_sees_foe = best != null
	if best != null:
		foe = best
		if state == State.FETCH and best_d > 90.0 and _axe_waiting():
			return # keep going for the axe unless the target is right here
		state = State.CHASE
		_lose_t = 5.0
		target = foe.global_position
		return
	if type == "axe" and not has_axe and _axe_waiting() and state != State.FETCH:
		state = State.FETCH
		_set_path(axe_spot.global_position)
		return
	match state:
		State.CHASE:
			if not _foe_ok():
				state = State.WANDER
				return
			_lose_t -= THINK_INTERVAL
			# For a short while after losing sight they still "know" where you are.
			if _lose_t > 2.5:
				target = foe.global_position
			_repath_t -= THINK_INTERVAL
			if _repath_t <= 0.0:
				_repath_t = 0.75
				_set_path(target)
			if _lose_t <= 0.0:
				state = State.WANDER
		State.FETCH:
			if not _axe_waiting():
				state = State.WANDER
			elif global_position.distance_to(axe_spot.global_position) < 18.0:
				_special_t = 0.4 # bend down and take it
			elif _path_i >= path.size():
				_set_path(axe_spot.global_position)
		State.WANDER:
			_wander(THINK_INTERVAL)


func _wander(dt: float) -> void:
	_wander_t -= dt
	if _wander_t <= 0.0:
		_wander_t = randf_range(3.0, 8.0)
		var to := world.random_walkable_near(global_position, 6)
		var b := world.building_at(to)
		if b >= 0 and b != world.building_at(global_position):
			return # don't wander into houses (their doors are shut anyway)
		_set_path(to)


## Zombies can't open doors: if the target is inside a building they're not in, they head for the
## outside of its front door instead (searching for a way in would comb the whole map).
func _set_path(to: Vector2) -> void:
	target = to
	var b := world.building_at(to)
	if b >= 0 and b != world.building_at(global_position) and not world.building_doors[b].is_empty():
		var best := Vector2.INF
		for d in world.building_doors[b]:
			var dc: Vector2i = d
			for off in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
				var n: Vector2i = dc + off
				if world.is_walkable(n) and world.building_at(world.center_of(n)) < 0:
					var p := world.center_of(n)
					if p.distance_to(global_position) < best.distance_to(global_position):
						best = p
		if best != Vector2.INF:
			if global_position.distance_to(best) < 20.0 and world.door_closed[world.idx(world.cell_of(best))] == 0:
				pass # at the (open) door: go on in
			elif not _door_open_for(b):
				to = best
	path = world.find_path(global_position, to, true)
	_path_i = 0


func _door_open_for(b: int) -> bool:
	for d in world.building_doors[b]:
		if world.door_closed[world.idx(d)] == 0:
			return true
	return false


func _follow_path() -> Vector2:
	while _path_i < path.size() and global_position.distance_to(path[_path_i]) < 10.0:
		_path_i += 1
	if _path_i >= path.size():
		if state == State.INVESTIGATE:
			state = State.WANDER
		return Vector2.ZERO
	return (path[_path_i] - global_position).normalized()


func hear(pos: Vector2) -> void:
	if state == State.CHASE or state == State.FETCH:
		return
	state = State.INVESTIGATE
	_set_path(pos)


func _try_attack() -> void:
	if _attack_cd > 0.0 or not _foe_ok():
		return
	var reach: float = _t["reach"]
	if global_position.distance_to(foe.global_position) < RADIUS + Player.RADIUS + reach:
		var unarmed := type == "axe" and not has_axe
		_attack_cd = _t["cd"]
		_attack_anim_t = 0.35 if type != "axe" else 0.5
		facing = (foe.global_position - global_position).normalized()
		var dmg := randf_range(_t["dmg"][0], _t["dmg"][1]) * _dmg_mult
		if unarmed:
			dmg *= 0.55
		hit(foe, dmg, facing, self)


## Deals damage to the player or a bandit.
static func hit(who: Node2D, amount: float, dir: Vector2, from: Node2D) -> void:
	if who is Player:
		(who as Player).take_damage(amount)
	elif who is Survivor:
		(who as Survivor).take_damage(amount, dir, from)
	elif who is Zombie:
		(who as Zombie).take_damage(amount, dir, from)
	elif who is Animal:
		(who as Animal).take_damage(amount, dir, from)


# ---------------------------------------------------------------- axe zombie

func _axe_waiting() -> bool:
	return axe_spot != null and is_instance_valid(axe_spot) and not axe_spot.is_queued_for_deletion() \
		and axe_spot.contents.any(func(it): return it["id"] == "axe")


func _try_throw() -> void:
	if not has_axe or _throw_cd > 0.0 or state != State.CHASE or not _sees_foe or not _foe_ok():
		return
	var d := global_position.distance_to(foe.global_position)
	if d < THROW_MIN or d > THROW_MAX:
		return
	_throw_cd = 999.0
	_special_t = 0.64
	facing = (foe.global_position - global_position).normalized()
	var aim_at := foe.global_position + Vector2(0, -6)
	get_tree().create_timer(0.3, false).timeout.connect(_release_axe.bind(aim_at))


func _release_axe(aim_at: Vector2) -> void:
	if dead or not is_inside_tree():
		return
	has_axe = false
	var axe := ThrownAxe.new()
	axe.world = world
	axe.thrower = self
	axe.position = global_position + Vector2(0, -10)
	var dir := (aim_at - axe.position).normalized().rotated(randf_range(-0.08, 0.08))
	axe.dir = dir
	axe.max_dist = minf(axe.position.distance_to(aim_at) + 70.0, THROW_MAX + 60.0)
	Game.ground(self).add_child(axe)


## Called by the thrown axe when it lands (it becomes an axe lying on the ground).
func axe_landed(spot: LootSpot) -> void:
	axe_spot = spot


func _pick_up_axe() -> void:
	if _axe_waiting() and global_position.distance_to(axe_spot.global_position) < 26.0:
		for i in axe_spot.contents.size():
			if axe_spot.contents[i]["id"] == "axe":
				axe_spot.contents.remove_at(i)
				break
		axe_spot.refresh()
		has_axe = true
		_throw_cd = randf_range(2.0, 4.0)
	axe_spot = null
	state = State.WANDER


# ---------------------------------------------------------------- armed zombie

func _try_shoot(delta: float) -> void:
	if mag <= 0 or state != State.CHASE or not _sees_foe or not _foe_ok():
		_aim_t = 0.0
		return
	var g: Array = ZOMBIE_GUNS[gun]
	var d := global_position.distance_to(foe.global_position)
	if d > float(g[4]) or d < 40.0:
		_aim_t = 0.0
		return
	if _attack_cd > 0.0:
		return
	_aim_t += delta
	if _aim_t < float(g[2]) and _burst == 0:
		return
	_fire(g)
	_burst += 1
	if _burst >= int(g[3]) or mag <= 0:
		_burst = 0
		_aim_t = 0.0
		_attack_cd = randf_range(1.3, 2.2)
	else:
		_attack_cd = 0.14


func _fire(g: Array) -> void:
	mag -= 1
	var origin := global_position + Vector2(0, -8)
	var dir := (foe.global_position + Vector2(0, -8) - origin).normalized().rotated(randf_range(-0.2, 0.2))
	var to := origin + dir * float(g[4])
	var q := PhysicsRayQueryParameters2D.create(origin + dir * 14.0, to, Game.LAYER_WALL | Game.LAYER_PLAYER | Game.LAYER_NPC, [get_rid()])
	var hit_info := get_world_2d().direct_space_state.intersect_ray(q)
	var end := to
	if not hit_info.is_empty():
		end = hit_info["position"]
		var col: Object = hit_info["collider"]
		if col is Player or col is Survivor:
			hit(col as Node2D, randf_range(g[0], g[1]), dir, self)
	_shots = [end]
	_shot_t = 0.07
	Game.make_noise(global_position, 350.0)


func _draw() -> void:
	# Health bar once it's been hurt
	if not dead and health < max_health:
		var w := 26.0
		var y := minf(_top, -30.0) - 6.0
		draw_rect(Rect2(-w / 2.0 - 1, y - 1, w + 2, 5), Color(0.08, 0.04, 0.07, 0.8))
		draw_rect(Rect2(-w / 2.0, y, w * clampf(health / max_health, 0.0, 1.0), 3), Color(0.85, 0.22, 0.18))
	if _shot_t > 0.0 and not _shots.is_empty():
		var aim := (to_local(_shots[0]) - Vector2(0, -8)).normalized()
		var muzzle := Vector2(0, -8) + aim * 22.0
		draw_line(muzzle, to_local(_shots[0]), Color(1, 0.9, 0.5, 0.85), 1.5)
		draw_circle(muzzle, 3.5, Color(1, 0.85, 0.4))


# ---------------------------------------------------------------- damage

func take_damage(amount: float, dir: Vector2, from: Node2D = null) -> void:
	if dead:
		return
	health -= amount * (1.0 - float(_t["armour"]) * 0.1)
	_flash_t = 0.12
	_knock = dir * float(_t["knock"])
	last_hit_by = from if from != null else player
	if from != null and from != self and not (from is Zombie):
		foe = from
	elif foe == null:
		foe = player
	state = State.CHASE
	_special_t = 0.0
	_lose_t = 5.0
	Game.hit_fx(get_parent(), global_position, dir)
	queue_redraw()
	if health <= 0.0:
		_die(dir)


func _die(dir: Vector2) -> void:
	dead = true
	remove_from_group("zombies")
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	z_index = -5
	_sprite.modulate = _tint
	_sprite.speed_scale = 1.0
	_sprite.play(_anim("death_side" if dir.x >= 0.0 else "death_side-left"))
	_fit_offset()
	if _held:
		_held.visible = false
	var blood := Game.make_sprite("blood_%d" % randi_range(1, 5))
	blood.show_behind_parent = true
	blood.position = Vector2(randf_range(-4, 4), 2)
	add_child(blood)
	_drop_loot()
	died.emit(self)
	get_tree().create_timer(45.0).timeout.connect(queue_free)


## Armed zombies drop their gun; axe zombies sometimes their axe.
func _drop_loot() -> void:
	var items := []
	if type == "armed":
		var g := Items.used(Items.make(gun), 15.0, 60.0)
		g["mag"] = clampi(mag, 0, int(Items.WEAPONS[gun]["mag"]))
		items.append(g)
		if randf() < 0.4:
			items.append(Items.make(Items.WEAPONS[gun]["ammo"], randi_range(2, 6)))
		if randf() < 0.3:
			items.append(Items.used(Items.make("vest"), 10.0, 45.0))
	elif type == "axe" and has_axe and randf() < 0.5:
		items.append(Items.used(Items.make("axe"), 20.0, 60.0))
	if items.is_empty():
		return
	var pile := LootSpot.new()
	pile.is_bag = true
	pile.contents = items
	pile.position = global_position + Vector2(randf_range(-6, 6), 6)
	Game.ground(self).call_deferred("add_child", pile)


func to_save() -> Dictionary:
	return {"pos": [position.x, position.y], "type": type, "health": health, "has_axe": has_axe, "gun": gun, "mag": mag}
