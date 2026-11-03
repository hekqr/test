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
var body_temp := 60.0 # 0 freezing .. 100 hot
var dead := false

# Temperature (kept simple): body temp drifts toward outside air + indoors bonus + clothing warmth.
const TEMP_DAY := 35.0
const TEMP_NIGHT := 10.0
const TEMP_INDOORS := 25.0
const TEMP_RATE := 0.3 # per second
const TEMP_WARM := 50.0 # needed to heal
const TEMP_COLD := 30.0
const TEMP_FREEZING := 15.0 # loses health below this
var inv := Inventory.new()
var aim := Vector2.RIGHT # mouse aim (guns)
var facing := Vector2.RIGHT # where the body looks (aim, or the melee target)
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
var _sprite: AnimatedSprite2D
var _held: Sprite2D
var _moving := false
var _melee_dir := Vector2.RIGHT


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


	inv.pickup(Items.make("tshirt"))
	inv.pickup(Items.make("jeans"))
	inv.add("food")
	inv.add("water")
	inv.add("bandage")
	say("Find food, water and a weapon. Stay alive.")


func say(text: String) -> void:
	message = text
	message_t = 3.5


func set_night(_n: float) -> void:
	pass # night is a uniform tint (main.gd); no limited light radius


# ---------------------------------------------------------------- weapons

## Selected weapon (1/2/3), or "fists".
func weapon_id() -> String:
	var w = inv.weapon_item()
	return "fists" if w == null else String(w["id"])


func weapon() -> Dictionary:
	return Items.WEAPONS[weapon_id()]


## The selected gun's item dict (holds "mag"), or {} for melee.
func gun() -> Dictionary:
	return inv.weapon_item() if not weapon()["melee"] else {}


## 1/2/3 and mouse wheel: switch between main gun, secondary and melee.
func switch_weapon(slot: String) -> void:
	reloading = false
	var err := inv.switch_to(slot)
	say(err if err != "" else weapon()["name"])


func cycle_weapon(step: int) -> void:
	var order := Inventory.WEAPON_SLOTS
	var cur := order.find(inv.active)
	for k in range(1, 4):
		var slot: String = order[posmod(cur + step * k, 3)]
		if inv.gear[slot] != null and slot != inv.active:
			switch_weapon(slot)
			return


## X: lower weapon (fists).
func holster() -> void:
	reloading = false
	inv.active = ""
	say("Fists")


## Inventory right-click: consumables are used, clothing / weapons are worn / equipped,
## items nearby are picked up.
func quick_use(loc: Dictionary) -> void:
	var it = inv.get_at(loc)
	if it == null:
		return
	var id: String = it["id"]
	if Items.kind(id) == "consumable":
		_consume(loc, id)
	elif Items.equip_of(id) != "" and not (loc["t"] == "gear" and loc["s"] == Items.equip_of(id)):
		var err := inv.equip(loc)
		say(err if err != "" else ("Wearing " if Items.is_clothing(id) else "Equipped ") + Items.name_of(id).to_lower())
	elif loc["t"] == "near":
		var left := inv.pickup(it)
		var taken: Dictionary = inv.take(loc)
		if left > 0:
			taken["count"] = left
			inv.near.contents.append(taken)
			inv.near.refresh()
			say("No free slots")
	elif loc["t"] == "gear" and loc["s"] in Inventory.WEAPON_SLOTS:
		switch_weapon(loc["s"])


func _consume(loc: Dictionary, id: String) -> void:
	if not _apply_consumable(id):
		return
	var it: Dictionary = inv.get_at(loc)
	it["count"] -= 1
	if it["count"] <= 0:
		inv.take(loc)


# ---------------------------------------------------------------- loop

func _physics_process(delta: float) -> void:
	if dead:
		return
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
				var g := gun()
				var need := int(w["mag"]) - int(g["mag"])
				var got := inv.remove(w["ammo"], need)
				g["mag"] += got
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
			var quiet := 0.7 if inv.gear["boots"] != null else 1.0
			Game.make_noise(global_position, (280.0 if sprinting else 90.0) * quiet)


func _needs(delta: float) -> void:
	hunger = maxf(hunger - delta * 100.0 / 900.0, 0.0) # full -> empty in 15 min
	thirst = maxf(thirst - delta * 100.0 / 600.0, 0.0) # full -> empty in 10 min
	body_temp = move_toward(body_temp, target_temp(), TEMP_RATE * delta)
	var dmg := 0.0
	if hunger <= 0.0:
		dmg += 1.0
	if thirst <= 0.0:
		dmg += 1.5
	if bleeding:
		dmg += 1.5
	if body_temp < TEMP_FREEZING:
		dmg += 0.5
	if dmg > 0.0:
		take_damage(dmg * delta, false)
	elif can_heal():
		health = minf(health + 0.4 * delta, 100.0)


func indoors() -> bool:
	return world != null and world.building_at(global_position) >= 0


## Temperature the body is heading towards.
func target_temp() -> float:
	var air := lerpf(TEMP_DAY, TEMP_NIGHT, Game.night)
	if indoors():
		air += TEMP_INDOORS
	return clampf(air + inv.warmth(), 0.0, 100.0)


## Healing needs: warm enough, hunger & thirst at least 75%, not bleeding.
func can_heal() -> bool:
	return body_temp >= TEMP_WARM and hunger >= 75.0 and thirst >= 75.0 and not bleeding


func temp_status() -> String:
	if body_temp < TEMP_FREEZING:
		return "Freezing"
	if body_temp < TEMP_COLD:
		return "Cold"
	if body_temp < TEMP_WARM:
		return "Chilly"
	return "Warm"


func _actions() -> void:
	if Input.is_action_just_pressed("reload"):
		start_reload()
	if Input.is_action_just_pressed("holster") and inv.active != "":
		holster()
	if Input.is_action_just_pressed("weapon_primary"):
		switch_weapon("primary")
	if Input.is_action_just_pressed("weapon_secondary"):
		switch_weapon("secondary")
	if Input.is_action_just_pressed("weapon_melee"):
		switch_weapon("melee")
	if Input.is_action_just_pressed("weapon_next"):
		cycle_weapon(1)
	if Input.is_action_just_pressed("weapon_prev"):
		cycle_weapon(-1)
	if Game.click_used and not Input.is_action_pressed("attack"):
		Game.click_used = false
	var w := weapon()
	if w["melee"]:
		_auto_melee()
	elif Input.is_action_pressed("attack") and not Game.click_used and _attack_cd <= 0.0 and not reloading:
		shoot()
	if Input.is_action_just_pressed("interact"):
		interact()
	if Input.is_action_just_pressed("eat"):
		use_item("food")
	if Input.is_action_just_pressed("drink"):
		use_item("water")
	if Input.is_action_just_pressed("bandage"):
		use_item("bandage")


## E / action button: search the nearby container or pick up the nearby item.
func interact() -> void:
	if nearest_loot == null:
		return
	if nearest_loot.is_bag:
		say(nearest_loot.search(self))
	else:
		nearest_loot.opened = true
		Game.open_inventory = true


## Melee fights for you: swing at the nearest zombie in reach.
func _auto_melee() -> void:
	if _attack_cd > 0.0:
		return
	var reach: float = weapon()["range"] + Zombie.RADIUS + 4.0
	var best: Zombie = null
	var best_d := reach
	for n in get_tree().get_nodes_in_group("zombies"):
		var z := n as Zombie
		var d := z.global_position.distance_to(global_position)
		if d < best_d and world.has_los(global_position, z.global_position):
			best_d = d
			best = z
	if best:
		melee((best.global_position - global_position).normalized())


func melee(dir: Vector2) -> void:
	var w := weapon()
	_attack_cd = w["cooldown"]
	_swing_t = 0.22
	_melee_dir = dir
	var reach: float = w["range"]
	for n in get_tree().get_nodes_in_group("zombies"):
		var z := n as Zombie
		var d := z.global_position - global_position
		if d.length() <= reach + Zombie.RADIUS + 4.0 and absf(dir.angle_to(d)) < deg_to_rad(65.0):
			z.take_damage(w["damage"], d.normalized())
	Game.make_noise(global_position, w["noise"])


func shoot() -> void:
	var w := weapon()
	var g := gun()
	if int(g["mag"]) <= 0:
		_attack_cd = 0.3
		if inv.count_of(w["ammo"]) > 0:
			start_reload()
		else:
			say("Out of ammo")
		return
	g["mag"] -= 1
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
	if w["melee"] or reloading or int(gun()["mag"]) >= int(w["mag"]):
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
	if _apply_consumable(item):
		inv.remove(item, 1)


## Applies a consumable's effect. Returns false if it wasn't needed.
func _apply_consumable(item: String) -> bool:
	match item:
		"food":
			if hunger > 95.0:
				say("Not hungry")
				return false
			hunger = minf(hunger + 35.0, 100.0)
			say("Ate canned food")
		"water":
			if thirst > 95.0:
				say("Not thirsty")
				return false
			thirst = minf(thirst + 40.0, 100.0)
			say("Drank water")
		"bandage":
			if not bleeding and health > 90.0:
				say("No need for a bandage")
				return false
			bleeding = false
			health = minf(health + 15.0, 100.0)
			say("Bandaged wounds")
	return true


## Drops an item on the ground at the player's feet (joins a pile that's right here).
func drop_item(item) -> void:
	if item == null:
		return
	reloading = false
	var pile: LootSpot = null
	for n in get_tree().get_nodes_in_group("loot"):
		var l := n as LootSpot
		if l.is_bag and l.global_position.distance_to(global_position) < 30.0:
			pile = l
			break
	if pile == null:
		pile = LootSpot.new()
		pile.is_bag = true
		pile.contents = [item]
		pile.position = global_position + Vector2(randf_range(-6, 6), 8)
		get_parent().add_child(pile)
	else:
		pile.contents.append(item)
		pile.refresh()
	say("Dropped " + Items.name_of(item["id"]).to_lower())


## Drops whatever is at an inventory location.
func drop(loc: Dictionary) -> void:
	if loc["t"] == "near":
		return
	drop_item(inv.take(loc))


func take_damage(amount: float, can_bleed := true) -> void:
	if dead:
		return
	if can_bleed:
		# Armour points reduce the hit (1 point = 10%); worn clothes wear down.
		var raw := amount
		amount *= inv.damage_taken_mult()
		var ruined := inv.wear_from_hit(raw)
		if not ruined.is_empty():
			say(", ".join(ruined) + (" is" if ruined.size() == 1 else " are") + " ruined!")
	health -= amount
	if can_bleed:
		_hurt_t = 0.2
		var covered := inv.gear["coat"] != null or inv.gear["armour"] != null
		if not bleeding and randf() < (0.18 if covered else 0.3):
			bleeding = true
			say("You are bleeding! Press H to bandage")
	if health <= 0.0:
		health = 0.0
		dead = true
		velocity = Vector2.ZERO
		_held.visible = false
		_sprite.modulate = Color.WHITE
		_sprite.play("death_side" if facing.x >= 0.0 else "death_side-left")
		queue_redraw()
		died.emit()


func _find_loot() -> void:
	nearest_loot = null
	var best := 44.0
	for n in get_tree().get_nodes_in_group("loot"):
		var l := n as LootSpot
		if l.is_queued_for_deletion():
			continue
		var d := l.global_position.distance_to(global_position)
		if d < best:
			best = d
			nearest_loot = l
	inv.near = nearest_loot


# ---------------------------------------------------------------- visuals

func _animate() -> void:
	facing = _melee_dir if (weapon()["melee"] and _swing_t > -0.15) else aim
	var d := Game.dir_name(facing)
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
		var side := 1.0 if facing.x >= 0.0 else -1.0
		_held.flip_h = side < 0.0
		_held.rotation = facing.angle() + PI * 0.5 + swing * side if _swing_t > 0.0 else -0.5 * side
		_held.position = HAND + (facing * 10.0 if _swing_t > 0.0 else Vector2(6 * side, -2))
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
		draw_arc(HAND, r, _melee_dir.angle() - 1.0, _melee_dir.angle() + 1.0, 12, Color(1, 1, 1, 0.4), 2.0)
	if _shot_t > 0.0:
		var muzzle := HAND + aim * 24.0
		for end in _shots:
			draw_line(muzzle, to_local(end), Color(1, 0.9, 0.5, 0.85), 1.5)
		draw_circle(muzzle, 4.0, Color(1, 0.85, 0.4))
