class_name Player
extends CharacterBody2D
## The survivor: movement, needs (health/hunger/thirst), weapons, inventory.

signal died

const RADIUS := 11.0
const WALK_SPEED := 140.0
const SPRINT_SPEED := 195.0
const HAND := Vector2(0, -8)

var world: World
var health := 100.0
var hunger := 100.0
var thirst := 100.0
var bleeding := false
var dead := false
var inv := Inventory.new()
var equipped: Dictionary = {} # an inventory slot dict, or {} for fists
var aim := Vector2.RIGHT
var nearest_loot: LootSpot = null
var message := ""
var message_t := 0.0
var reloading := false
var reload_progress := 0.0

var _attack_cd := 0.0
var _reload_t := 0.0
var _reload_total := 1.0
var _swing_t := 0.0
var _shots: Array = [] # [from_local, to_global] for muzzle tracers
var _shot_t := 0.0
var _hurt_t := 0.0
var _noise_t := 0.0
var _light: PointLight2D
var _sprite: AnimatedSprite2D
var _held: Sprite2D
var _moving := false


func _ready() -> void:
	add_to_group("player")
	collision_layer = Game.LAYER_PLAYER
	collision_mask = Game.LAYER_WALL | Game.LAYER_ZOMBIE
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	var cs := CollisionShape2D.new()
	cs.shape = circle
	add_child(cs)

	var spec := {}
	for d in Game.DIRS:
		spec["idle_" + d] = ["player_idle_" + d, 6, 8.0, true]
		spec["run_" + d] = ["player_run_" + d, 6, 12.0, true]
		spec["punch_" + d] = ["player_punch_" + d, 4, 20.0, false]
	for d in ["side", "side-left"]:
		spec["death_" + d] = ["player_death_" + d, 6, 10.0, false]
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = Game.frames("player", spec)
	_sprite.scale = Vector2(2, 2)
	_sprite.offset = Vector2(0, -7)
	_sprite.play("idle_down")
	add_child(_sprite)
	_held = Sprite2D.new()
	_held.scale = Vector2(2, 2)
	_held.visible = false
	add_child(_held)

	var cam := Camera2D.new()
	cam.zoom = Vector2(1.5, 1.5)
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

	inv.add("food")
	inv.add("water")
	inv.add("bandage")
	say("Find food, water and a weapon. Stay alive.")


func say(text: String) -> void:
	message = text
	message_t = 3.5


func set_night(n: float) -> void:
	if _light:
		_light.energy = n * 0.9


# ---------------------------------------------------------------- weapons

func weapon_id() -> String:
	return "fists" if equipped.is_empty() else String(equipped["id"])


func weapon() -> Dictionary:
	return Items.WEAPONS[weapon_id()]


func equip(item: Dictionary) -> void:
	reloading = false
	if item.is_empty() or is_same(item, equipped):
		equipped = {}
		say("Fists")
	else:
		equipped = item
		say(Items.name_of(item["id"]))


## Hotbar key / right-click in inventory.
func use_slot(i: int) -> void:
	var s = inv.slots[i]
	if s == null:
		if i < Inventory.HOTBAR:
			equip({})
		return
	if Items.is_weapon(s["id"]):
		equip(s)
	elif Items.DEFS[s["id"]]["kind"] == "consumable":
		use_item(s["id"])
	else:
		say(Items.name_of(s["id"]))


# ---------------------------------------------------------------- loop

func _physics_process(delta: float) -> void:
	if dead:
		return
	if not equipped.is_empty() and not inv.contains(equipped):
		equipped = {}
		reloading = false
	_timers(delta)
	_move(delta)
	_needs(delta)
	if not Game.ui_open:
		_actions()
	_find_loot()
	_animate()
	queue_redraw()


func _timers(delta: float) -> void:
	_attack_cd -= delta
	_swing_t -= delta
	_shot_t -= delta
	_hurt_t -= delta
	message_t -= delta
	if reloading:
		_reload_t -= delta
		reload_progress = 1.0 - _reload_t / _reload_total
		if _reload_t <= 0.0:
			reloading = false
			var w := weapon()
			if not w["melee"]:
				var need := int(w["mag"]) - int(equipped["mag"])
				var got := inv.remove(w["ammo"], need)
				equipped["mag"] += got
				say("Reloaded")


func _move(delta: float) -> void:
	var dir := Vector2.ZERO
	if not Game.ui_open:
		dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var sprinting := Input.is_action_pressed("sprint") and dir != Vector2.ZERO
	var speed := SPRINT_SPEED if sprinting else WALK_SPEED
	if health < 30.0:
		speed *= 0.8
	velocity = dir * speed
	move_and_slide()
	_moving = dir != Vector2.ZERO

	if not Game.ui_open:
		var m := get_global_mouse_position() - (global_position + HAND)
		if m.length() > 2.0:
			aim = m.normalized()

	if _moving:
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
	for i in Inventory.HOTBAR:
		if Input.is_action_just_pressed("slot_%d" % (i + 1)):
			use_slot(i)
	if Input.is_action_just_pressed("reload"):
		start_reload()
	if Input.is_action_pressed("attack") and _attack_cd <= 0.0 and not reloading:
		attack()
	if Input.is_action_just_pressed("interact") and nearest_loot:
		say(nearest_loot.search(self))
	if Input.is_action_just_pressed("eat"):
		use_item("food")
	if Input.is_action_just_pressed("drink"):
		use_item("water")
	if Input.is_action_just_pressed("bandage"):
		use_item("bandage")


func attack() -> void:
	if weapon()["melee"]:
		melee()
	else:
		shoot()


func melee() -> void:
	var w := weapon()
	_attack_cd = w["cooldown"]
	_swing_t = 0.22
	var reach: float = w["range"]
	for n in get_tree().get_nodes_in_group("zombies"):
		var z := n as Zombie
		var d := z.global_position - global_position
		if d.length() <= reach + Zombie.RADIUS and absf(aim.angle_to(d)) < deg_to_rad(65.0):
			z.take_damage(w["damage"], d.normalized())
	Game.make_noise(global_position, w["noise"])


func shoot() -> void:
	var w := weapon()
	if int(equipped["mag"]) <= 0:
		_attack_cd = 0.3
		if inv.count_of(w["ammo"]) > 0:
			start_reload()
		else:
			say("Out of ammo")
		return
	equipped["mag"] -= 1
	_attack_cd = w["cooldown"]
	_shots.clear()
	var space := get_world_2d().direct_space_state
	var origin := global_position + HAND
	for i in int(w["pellets"]):
		var dir := aim.rotated(randf_range(-w["spread"], w["spread"]) * (1.0 if w["pellets"] > 1 else 0.5))
		var from := origin + dir * 14.0
		var to := origin + dir * float(w["range"]) * randf_range(0.85, 1.0)
		var q := PhysicsRayQueryParameters2D.create(from, to, Game.LAYER_WALL | Game.LAYER_ZOMBIE, [get_rid()])
		var hit := space.intersect_ray(q)
		var end := to
		if not hit.is_empty():
			end = hit["position"]
			var col: Object = hit["collider"]
			if col is Zombie:
				(col as Zombie).take_damage(w["damage"], dir)
		_shots.append(end)
	_shot_t = 0.07
	Game.make_noise(global_position, w["noise"])


func start_reload() -> void:
	var w := weapon()
	if w["melee"] or reloading or int(equipped["mag"]) >= int(w["mag"]):
		return
	if inv.count_of(w["ammo"]) <= 0:
		say("No ammo")
		return
	reloading = true
	_reload_total = w["reload"]
	_reload_t = _reload_total
	reload_progress = 0.0
	say("Reloading...")


func use_item(item: String) -> void:
	if inv.count_of(item) <= 0:
		say("No %s" % Items.name_of(item).to_lower())
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
	inv.remove(item, 1)


## Drops an inventory slot on the ground as a bag.
func drop_slot(i: int) -> void:
	var s = inv.take(i)
	if s == null:
		return
	if is_same(s, equipped):
		equipped = {}
	var bag := LootSpot.new()
	bag.is_bag = true
	bag.contents = [s]
	bag.position = global_position + Vector2(randf_range(-6, 6), 8)
	get_parent().add_child(bag)
	say("Dropped " + Items.name_of(s["id"]))


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
		_held.visible = false
		_sprite.modulate = Color.WHITE
		_sprite.play("death_side" if aim.x >= 0.0 else "death_side-left")
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


# ---------------------------------------------------------------- visuals

func _animate() -> void:
	var d := Game.dir_name(aim)
	var anim := ("run_" if _moving else "idle_") + d
	if _swing_t > -0.05 and weapon_id() == "fists":
		anim = "punch_" + d
	if _sprite.animation != anim:
		var keep := _sprite.animation.begins_with("run") and anim.begins_with("run")
		var f := _sprite.frame
		_sprite.play(anim)
		if keep:
			_sprite.frame = f
	_sprite.modulate = Color(1, 0.55, 0.55) if _hurt_t > 0.0 else Color.WHITE

	# Held weapon sprite in front of the body.
	var held: String = weapon()["held"]
	_held.visible = held != ""
	if not _held.visible:
		return
	_held.texture = Game.tex(held)
	_held.z_index = -1 if d == "up" else 0
	if weapon()["melee"]:
		# Bat: rest over the shoulder, swing through an arc when attacking.
		var t := clampf(_swing_t / 0.22, 0.0, 1.0)
		var swing := lerpf(1.2, -1.2, 1.0 - t) if _swing_t > 0.0 else -0.9
		var side := 1.0 if aim.x >= 0.0 else -1.0
		_held.flip_h = side < 0.0
		_held.rotation = aim.angle() + PI * 0.5 + swing * side if _swing_t > 0.0 else -0.5 * side
		_held.position = HAND + (aim * 10.0 if _swing_t > 0.0 else Vector2(6 * side, -2))
	else:
		_held.flip_h = false
		_held.flip_v = aim.x < 0.0
		_held.rotation = aim.angle()
		_held.position = HAND + aim * 10.0


func _draw() -> void:
	draw_set_transform(Vector2(0, 1), 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, RADIUS, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO)
	if dead:
		return
	if _swing_t > 0.0:
		var r: float = weapon()["range"] - 6.0
		draw_arc(HAND, r, aim.angle() - 1.0, aim.angle() + 1.0, 12, Color(1, 1, 1, 0.4), 2.0)
	if _shot_t > 0.0:
		var muzzle := HAND + aim * 24.0
		for end in _shots:
			draw_line(muzzle, to_local(end), Color(1, 0.9, 0.5, 0.85), 1.5)
		draw_circle(muzzle, 4.0, Color(1, 0.85, 0.4))
