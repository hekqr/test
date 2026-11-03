class_name Player
extends CharacterBody2D
## The survivor: movement, needs (hunger/thirst/stamina), weapons, inventory.

signal died

const RADIUS := 11.0
const WALK_SPEED := 140.0
const SPRINT_SPEED := 235.0
const MAG_SIZE := 8
const MELEE_RANGE := 46.0
const MELEE_DAMAGE := 30.0
const PISTOL_DAMAGE := 45.0

var world: World
var health := 100.0
var hunger := 100.0
var thirst := 100.0
var stamina := 100.0
var bleeding := false
var dead := false
var inventory := {"food": 1, "water": 1, "bandage": 1, "ammo": 0}
var has_pistol := false
var weapon := 0 # 0 = knife, 1 = pistol
var mag := 0
var aim := Vector2.RIGHT
var nearest_loot: LootSpot = null
var message := ""
var message_t := 0.0
var reloading := false

var _attack_cd := 0.0
var _reload_t := 0.0
var _swing_t := 0.0
var _shot_t := 0.0
var _shot_end := Vector2.ZERO
var _hurt_t := 0.0
var _noise_t := 0.0
var _light: PointLight2D


func _ready() -> void:
	add_to_group("player")
	collision_layer = Game.LAYER_PLAYER
	collision_mask = Game.LAYER_WALL | Game.LAYER_ZOMBIE
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	var cs := CollisionShape2D.new()
	cs.shape = circle
	add_child(cs)

	var cam := Camera2D.new()
	cam.zoom = Vector2(1.25, 1.25)
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 8.0
	if world:
		cam.limit_left = 0
		cam.limit_top = 0
		cam.limit_right = int(world.size_px().x)
		cam.limit_bottom = int(world.size_px().y)
	add_child(cam)

	var g := Gradient.new()
	g.set_color(0, Color(1, 0.95, 0.8, 1))
	g.set_color(1, Color(1, 0.95, 0.8, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	_light = PointLight2D.new()
	_light.texture = tex
	_light.texture_scale = 2.6
	_light.energy = 0.0
	add_child(_light)

	say("Find food, water and a weapon. Stay alive.")


func say(text: String) -> void:
	message = text
	message_t = 3.5


func set_night(n: float) -> void:
	if _light:
		_light.energy = n * 0.9


func _physics_process(delta: float) -> void:
	if dead:
		return
	_timers(delta)
	_move(delta)
	_needs(delta)
	_actions()
	_find_loot()
	queue_redraw()


func _timers(delta: float) -> void:
	_attack_cd -= delta
	_swing_t -= delta
	_shot_t -= delta
	_hurt_t -= delta
	message_t -= delta
	if reloading:
		_reload_t -= delta
		if _reload_t <= 0.0:
			reloading = false
			var n: int = mini(MAG_SIZE - mag, int(inventory["ammo"]))
			mag += n
			inventory["ammo"] -= n
			say("Reloaded")


func _move(delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var sprinting := Input.is_action_pressed("sprint") and dir != Vector2.ZERO and stamina > 0.5
	var speed := SPRINT_SPEED if sprinting else WALK_SPEED
	if health < 30.0:
		speed *= 0.8
	if sprinting:
		stamina = maxf(stamina - 22.0 * delta, 0.0)
	else:
		stamina = minf(stamina + (14.0 if hunger > 20.0 else 6.0) * delta, 100.0)
	velocity = dir * speed
	move_and_slide()

	var m := get_global_mouse_position() - global_position
	if m.length() > 2.0:
		aim = m.normalized()

	if dir != Vector2.ZERO:
		_noise_t -= delta
		if _noise_t <= 0.0:
			_noise_t = 0.4
			Game.make_noise(global_position, 280.0 if sprinting else 90.0)


func _needs(delta: float) -> void:
	hunger = maxf(hunger - delta * 100.0 / 900.0, 0.0) # full -> empty in 15 min
	thirst = maxf(thirst - delta * 100.0 / 600.0, 0.0) # full -> empty in 10 min
	var dmg := 0.0
	if hunger <= 0.0:
		dmg += 1.0
	if thirst <= 0.0:
		dmg += 1.5
	if bleeding:
		dmg += 1.5
	if dmg > 0.0:
		take_damage(dmg * delta, false)
	elif hunger > 50.0 and thirst > 50.0:
		health = minf(health + 0.4 * delta, 100.0)


func _actions() -> void:
	if Input.is_action_just_pressed("weapon_1"):
		weapon = 0
		reloading = false
		say("Knife")
	if Input.is_action_just_pressed("weapon_2"):
		if has_pistol:
			weapon = 1
			say("Pistol  %d / %d" % [mag, inventory["ammo"]])
		else:
			say("You don't have a pistol yet")
	if Input.is_action_just_pressed("reload"):
		start_reload()
	if Input.is_action_pressed("attack") and _attack_cd <= 0.0 and not reloading:
		if weapon == 0:
			melee()
		else:
			shoot()
	if Input.is_action_just_pressed("interact") and nearest_loot:
		say(nearest_loot.search(self))
	if Input.is_action_just_pressed("eat"):
		use_item("food")
	if Input.is_action_just_pressed("drink"):
		use_item("water")
	if Input.is_action_just_pressed("bandage"):
		use_item("bandage")


func melee() -> void:
	_attack_cd = 0.45
	_swing_t = 0.15
	stamina = maxf(stamina - 6.0, 0.0)
	for n in get_tree().get_nodes_in_group("zombies"):
		var z := n as Zombie
		var d := z.global_position - global_position
		if d.length() <= MELEE_RANGE + Zombie.RADIUS and absf(aim.angle_to(d)) < deg_to_rad(65.0):
			z.take_damage(MELEE_DAMAGE, d.normalized())
	Game.make_noise(global_position, 120.0)


func shoot() -> void:
	if mag <= 0:
		_attack_cd = 0.3
		if int(inventory["ammo"]) > 0:
			start_reload()
		else:
			say("Out of ammo")
		return
	mag -= 1
	_attack_cd = 0.32
	var from := global_position + aim * (RADIUS + 2.0)
	var to := global_position + aim * 750.0
	var q := PhysicsRayQueryParameters2D.create(from, to, Game.LAYER_WALL | Game.LAYER_ZOMBIE, [get_rid()])
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	_shot_end = to
	if not hit.is_empty():
		_shot_end = hit["position"]
		var col: Object = hit["collider"]
		if col is Zombie:
			(col as Zombie).take_damage(PISTOL_DAMAGE, aim)
	_shot_t = 0.06
	Game.make_noise(global_position, 750.0)


func start_reload() -> void:
	if weapon != 1 or reloading or mag >= MAG_SIZE:
		return
	if int(inventory["ammo"]) <= 0:
		say("No ammo")
		return
	reloading = true
	_reload_t = 1.4
	say("Reloading...")


func use_item(item: String) -> void:
	if int(inventory[item]) <= 0:
		say("No %s" % item)
		return
	match item:
		"food":
			if hunger > 95.0:
				say("Not hungry")
				return
			hunger = minf(hunger + 35.0, 100.0)
			say("Ate canned food")
		"water":
			if thirst > 95.0:
				say("Not thirsty")
				return
			thirst = minf(thirst + 40.0, 100.0)
			say("Drank water")
		"bandage":
			if not bleeding and health > 90.0:
				say("No need for a bandage")
				return
			bleeding = false
			health = minf(health + 15.0, 100.0)
			say("Bandaged wounds")
	inventory[item] -= 1


func take_damage(amount: float, can_bleed := true) -> void:
	if dead:
		return
	health -= amount
	if can_bleed:
		_hurt_t = 0.2
		if not bleeding and randf() < 0.3:
			bleeding = true
			say("You are bleeding! Press H to bandage")
	if health <= 0.0:
		health = 0.0
		dead = true
		velocity = Vector2.ZERO
		queue_redraw()
		died.emit()


func _find_loot() -> void:
	nearest_loot = null
	var best := 44.0
	for n in get_tree().get_nodes_in_group("loot"):
		var l := n as LootSpot
		if l.looted:
			continue
		var d := l.global_position.distance_to(global_position)
		if d < best:
			best = d
			nearest_loot = l


func _draw() -> void:
	if dead:
		draw_circle(Vector2.ZERO, RADIUS + 4.0, Color(0.35, 0.05, 0.05, 0.8))
		draw_circle(Vector2.ZERO, RADIUS, Color(0.2, 0.3, 0.45))
		return
	var side := aim.orthogonal()
	draw_circle(Vector2(3, 4), RADIUS, Color(0, 0, 0, 0.3))
	if weapon == 1:
		draw_line(aim * 6.0, aim * 25.0, Color(0.12, 0.12, 0.12), 5.0)
	else:
		draw_line(aim * 6.0 + side * 8.0, aim * 21.0 + side * 8.0, Color(0.78, 0.78, 0.82), 3.0)
	var body := Color(1, 0.45, 0.45) if _hurt_t > 0.0 else Color(0.25, 0.42, 0.68)
	draw_circle(Vector2.ZERO, RADIUS, body)
	draw_circle(aim * 3.0, 6.5, Color(0.86, 0.71, 0.56))
	if _swing_t > 0.0:
		draw_arc(Vector2.ZERO, 40.0, aim.angle() - 1.1, aim.angle() + 1.1, 14, Color(1, 1, 1, 0.55), 3.0)
	if _shot_t > 0.0:
		draw_line(aim * (RADIUS + 14.0), to_local(_shot_end), Color(1, 0.9, 0.5, 0.9), 2.0)
		draw_circle(aim * 27.0, 5.0, Color(1, 0.85, 0.4))
