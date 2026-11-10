class_name Survivor
extends CharacterBody2D
## Hostile survivors ("bandits"). Each one carries real gear: clothes, a gun and/or a melee weapon,
## spare ammo and some supplies. They wander around their camp in towns and along roads, attack the
## player on sight, shoot zombies that get close, keep their distance with guns, reload, run away when
## badly hurt, and drop everything they carry when they die.

signal died(s: Survivor)

enum State { WANDER, INVESTIGATE, FIGHT, FLEE }

const RADIUS := 11.0
const HAND := Vector2(0, -8)
const THINK := 0.3
const WALK := 37.0
const RUN := 83.0
const FLEE_SPEED := 96.0
const SIGHT_DAY := 430.0
const SIGHT_NIGHT := 260.0
const ZOMBIE_ALERT := 250.0 # zombies closer than this get shot at
const GUN_DAMAGE := 0.5 # bandits' guns hurt less than yours (they'd be unfair otherwise)
const MELEE_DAMAGE := 0.8
const SPREAD_MULT := 1.35 # and they aim worse

var world: World
var player: Player
var health := 100.0
var dead := false
var state := State.WANDER
## Worn clothing and weapons, by Inventory gear slot (no "hands").
var gear := {}
## Carried supplies (food, meds, spare ammo...).
var items: Array = []
var active := "" # weapon slot in use: "primary" / "secondary" / "melee" / "" (fists)
var home := Vector2.ZERO
var foe: Node2D = null
var facing := Vector2.DOWN
var aim := Vector2.DOWN
var spread := 0.6
var reloading := false
var last_hit_by: Node2D = null

var _think_t := randf() * THINK
var _wander_t := randf() * 4.0
var _lose_t := 0.0
var _last_seen := Vector2.ZERO
var _sees := false
var _repath_t := 0.0
var _path := PackedVector2Array()
var _path_i := 0
var _attack_cd := 0.0
var _reload_t := 0.0
var _swing_t := 0.0
var _flash_t := 0.0
var _knock := Vector2.ZERO
var _strafe := Vector2.ZERO
var _strafe_t := 0.0
var _burst := 0
var _shots: Array = []
var _shot_t := 0.0
var _flee_t := 0.0
var _healed := false
var _moving := false
var _sprite: AnimatedSprite2D
var _held: Sprite2D


func _ready() -> void:
	add_to_group("survivors")
	collision_layer = Game.LAYER_NPC
	collision_mask = Game.LAYER_WALL | Game.LAYER_PLAYER | Game.LAYER_ZOMBIE | Game.LAYER_NPC | Game.LAYER_WATER | Game.LAYER_EDGE | Game.LAYER_GATE
	add_child(Game.foot_shape(RADIUS, 7.0))
	if gear.is_empty():
		_roll_gear()
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = Game.frames("player", Player.sprite_spec())
	_sprite.scale = Vector2(2, 2)
	_sprite.offset = Vector2(0, -7)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/outfit.gdshader")
	_sprite.material = mat
	Player.paint_outfit(mat, gear)
	_sprite.play("idle_down")
	add_child(_sprite)
	_held = Sprite2D.new()
	_held.scale = Vector2(2, 2)
	add_child(_held)
	if home == Vector2.ZERO:
		home = global_position
	_pick_weapon()


# ---------------------------------------------------------------- gear

func _roll_gear() -> void:
	for s in Inventory.GEAR:
		gear[s] = null
	gear["shirt"] = Items.used(Items.make(["tshirt", "flannel"].pick_random()), 30.0, 90.0)
	gear["pants"] = Items.used(Items.make(["jeans", "cargo_pants"].pick_random()), 30.0, 90.0)
	if randf() < 0.55:
		gear["coat"] = Items.used(Items.make(["hoodie", "hoodie", "jacket", "parka", "field_jacket"].pick_random()), 30.0, 90.0)
	if randf() < 0.45:
		gear["head"] = Items.used(Items.make(["cap", "cap", "beanie", "helmet"].pick_random()), 30.0, 90.0)
	if randf() < 0.6:
		gear["boots"] = Items.used(Items.make("boots"), 30.0, 90.0)
	if randf() < 0.14:
		gear["armour"] = Items.used(Items.make(["vest", "scrap_armour"].pick_random()), 25.0, 80.0)
	if randf() < 0.3:
		gear["back"] = Items.used(Items.make(["backpack_small", "sack_backpack", "backpack_large"].pick_random()), 30.0, 90.0)
	var has_gun := randf() < 0.6
	if has_gun:
		var id: String = ["pistol", "pistol", "pistol", "shotgun", "shotgun", "rifle", "hunting_rifle"].pick_random()
		var g := Items.used(Items.make(id), 30.0, 90.0)
		var w: Dictionary = Items.WEAPONS[id]
		g["mag"] = randi_range(int(w["mag"]) / 2, int(w["mag"]))
		gear[Items.equip_of(id)] = g
		_add_ammo(String(w["ammo"]), int(w["mag"]) * randi_range(1, 2)) # 1-2 spare magazines
	if not has_gun or randf() < 0.4:
		var m: String = ["knife", "knife", "bat", "axe", "spear"].pick_random()
		gear["melee"] = Items.used(Items.make(m), 30.0, 90.0)
	items.append_array(Items.roll(Loot.CONTAINERS["floor"]["table"], Vector2i(1, 3), 0.2))
	if randf() < 0.5:
		items.append(Items.make("bandage", randi_range(1, 2)))


func _add_ammo(id: String, n: int) -> void:
	var stack := Items.max_stack(id)
	while n > 0:
		var k := mini(n, stack)
		items.append(Items.make(id, k))
		n -= k


func _ammo_count(id: String) -> int:
	var n := 0
	for it in items:
		if it["id"] == id:
			n += int(it["count"])
	return n


func _take_ammo(id: String, want: int) -> int:
	var got := 0
	for it in items:
		if it["id"] == id and got < want:
			var k := mini(int(it["count"]), want - got)
			it["count"] -= k
			got += k
	items = items.filter(func(it): return int(it["count"]) > 0)
	return got


func weapon_item() -> Variant:
	return gear.get(active) if active != "" else null


func weapon_id() -> String:
	var w = weapon_item()
	return "fists" if w == null else String(w["id"])


func weapon() -> Dictionary:
	return Items.WEAPONS[weapon_id()]


## Best weapon to use right now: a gun with ammo, else the melee weapon, else fists.
func _pick_weapon() -> void:
	active = ""
	for s in ["primary", "secondary"]:
		var g = gear.get(s)
		if g != null and not Items.is_ruined(g) and (int(g["mag"]) > 0 or _ammo_count(Items.WEAPONS[g["id"]]["ammo"]) > 0):
			active = s
			return
	var m = gear.get("melee")
	if m != null and not Items.is_ruined(m):
		active = "melee"


func armour_mult() -> float:
	var p := 0.0
	for s in Inventory.CLOTHING_SLOTS:
		var g = gear.get(s)
		if g != null:
			p += Items.armour_of(g["id"]) * Items.cond_factor(g)
	return 1.0 - minf(p, Inventory.MAX_ARMOUR) * 0.1


# ---------------------------------------------------------------- loop

func _physics_process(delta: float) -> void:
	if dead:
		return
	_attack_cd -= delta
	_swing_t -= delta
	_flash_t -= delta
	_shot_t -= delta
	_strafe_t -= delta
	_think_t -= delta
	if reloading:
		_reload_t -= delta
		if _reload_t <= 0.0:
			_finish_reload()
	if _think_t <= 0.0:
		_think_t = THINK
		_think()

	var move := Vector2.ZERO
	var speed := WALK
	match state:
		State.WANDER:
			move = _follow_path()
		State.INVESTIGATE:
			speed = RUN * 0.8
			move = _follow_path()
		State.FIGHT:
			speed = RUN
			move = _fight_move()
		State.FLEE:
			speed = FLEE_SPEED
			move = _follow_path()
	velocity = move * speed + _knock
	_knock = _knock.move_toward(Vector2.ZERO, 700.0 * delta)
	move_and_slide()
	_moving = move != Vector2.ZERO
	if state == State.FIGHT and _sees and _foe_ok():
		aim = (foe.global_position + Vector2(0, -8) - (global_position + HAND)).normalized()
		facing = aim
		_combat(delta)
	elif _moving:
		facing = facing.lerp(move, 0.2).normalized()
		aim = facing
	_animate()
	queue_redraw()


func _foe_ok() -> bool:
	if foe == null or not is_instance_valid(foe):
		return false
	if foe is Player:
		return not (foe as Player).dead
	if foe is Zombie:
		return not (foe as Zombie).dead
	if foe is Animal:
		return not (foe as Animal).dead
	return false


func _think() -> void:
	if state == State.FLEE:
		_flee_t -= THINK
		if _flee_t <= 0.0 or _path_i >= _path.size():
			_patch_up()
			state = State.WANDER
		return
	# Who's a threat: the player (on sight), zombies that get close.
	var sight := lerpf(SIGHT_DAY, SIGHT_NIGHT, Game.night)
	var best: Node2D = null
	var best_d := INF
	if player != null and not player.dead:
		var d := global_position.distance_to(player.global_position)
		if foe == player:
			d *= 0.8
		if d < sight * player.visibility() and world.has_los(global_position + HAND, player.global_position + Vector2(0, -8)):
			best = player
			best_d = d
	for n in get_tree().get_nodes_in_group("zombies") + get_tree().get_nodes_in_group("wolves"):
		var z := n as Node2D
		var d := global_position.distance_to(z.global_position)
		if d < ZOMBIE_ALERT and d < best_d and world.has_los(global_position + HAND, z.global_position + Vector2(0, -8)):
			best = z
			best_d = d
	_sees = best != null
	if best != null:
		if state != State.FIGHT:
			_strafe_t = 0.0
		foe = best
		state = State.FIGHT
		_lose_t = 6.0
		_last_seen = foe.global_position
		if health < 30.0 and not _healed and randf() < 0.5:
			_run_away()
		return
	match state:
		State.FIGHT:
			_lose_t -= THINK
			if not _foe_ok() or _lose_t <= 0.0:
				state = State.WANDER
				foe = null
				return
			if _lose_t > 4.0:
				_last_seen = foe.global_position
			_repath_t -= THINK
			if _repath_t <= 0.0:
				_repath_t = 1.0
				_set_path(_last_seen)
		State.INVESTIGATE:
			if _path_i >= _path.size():
				state = State.WANDER
		State.WANDER:
			_wander_t -= THINK
			if _wander_t <= 0.0:
				_wander_t = randf_range(4.0, 11.0)
				if randf() < 0.3:
					_path = PackedVector2Array() # stand around for a bit
				else:
					_set_path(world.random_walkable_near(home, 9))
	if not reloading and weapon_item() != null and not weapon()["melee"] and int(weapon_item()["mag"]) < int(weapon()["mag"]) and state != State.FIGHT:
		_start_reload() # top up between fights


func _run_away() -> void:
	state = State.FLEE
	_flee_t = 7.0
	var away := (global_position - foe.global_position).normalized()
	_set_path(world.random_walkable_near(global_position + away * 380.0, 4))


## After running away: bandage up once.
func _patch_up() -> void:
	for it in items:
		if it["id"] in ["bandage", "firstaid"]:
			it["count"] -= 1
			health = minf(health + (35.0 if it["id"] == "firstaid" else 20.0), 100.0)
			_healed = true
			break
	items = items.filter(func(it): return int(it["count"]) > 0)


func hear(pos: Vector2) -> void:
	if state == State.FIGHT or state == State.FLEE:
		return
	state = State.INVESTIGATE
	_set_path(pos)


func _set_path(to: Vector2) -> void:
	_path_i = 0
	# A spot walled in all round (a base with no gate): no way in, so no whole-map path search.
	var pocket := world.small_pocket(world.nearest_walkable(world.cell_of(to)), 900, false)
	if not pocket.is_empty() and not pocket.has(world.nearest_walkable(world.cell_of(global_position))):
		_path = PackedVector2Array()
		return
	_path = world.find_path(global_position, to)


func _follow_path() -> Vector2:
	while _path_i < _path.size() and global_position.distance_to(_path[_path_i]) < 10.0:
		_path_i += 1
	if _path_i >= _path.size():
		return Vector2.ZERO
	return (_path[_path_i] - global_position).normalized()


# ---------------------------------------------------------------- fighting

## Guns: stay at a good range, sidestep now and then, back off while reloading.
## Melee: run straight at the target.
func _fight_move() -> Vector2:
	if not _foe_ok():
		return Vector2.ZERO
	if not _sees:
		return _follow_path()
	var to := foe.global_position - global_position
	var d := to.length()
	var w := weapon()
	if w["melee"]:
		return to.normalized() if d > float(w["range"]) * 0.7 + RADIUS else Vector2.ZERO
	var hi := clampf(float(w["range"]) * 0.35, 150.0, 400.0)
	if foe is Zombie or foe is Animal:
		hi = minf(hi, 200.0)
	var lo := hi * 0.5
	if reloading or d < lo:
		return -to.normalized()
	if d > hi:
		return to.normalized()
	if _strafe_t <= 0.0:
		_strafe_t = randf_range(1.2, 2.8)
		_strafe = Vector2.ZERO if randf() < 0.5 else to.normalized().orthogonal() * (1.0 if randf() < 0.5 else -1.0)
	return _strafe * 0.6


func _combat(delta: float) -> void:
	var w := weapon()
	var d := global_position.distance_to(foe.global_position)
	if w["melee"]:
		if _attack_cd <= 0.0 and d <= float(w["range"]) + RADIUS + 6.0 and world.has_los(global_position, foe.global_position):
			_attack_cd = float(w["cooldown"]) * 1.5
			_swing_t = 0.22
			var dir := (foe.global_position - global_position).normalized()
			var it = weapon_item()
			Zombie.hit(foe, float(w["damage"]) * Items.weapon_factor(it) * MELEE_DAMAGE, dir, self)
			_wear(it, float(w.get("wear", 0.0)))
			Game.make_noise(global_position, w["noise"])
		return
	# Guns: the aim settles while standing, like the player's.
	var smin: float = float(w["spread_min"]) * SPREAD_MULT
	var smax: float = float(w["spread_max"]) * SPREAD_MULT
	var want := smin + (Player.WALK_SPREAD if _moving else 0.0)
	if spread > want:
		spread = maxf(spread - (smax - smin) / (float(w["aim_time"]) * 1.2) * delta, want)
	else:
		spread = minf(spread + 2.0 * delta, want)
	if reloading or _attack_cd > 0.0:
		return
	var g: Dictionary = weapon_item()
	if int(g["mag"]) <= 0:
		_start_reload()
		return
	if d > float(w["range"]) * 0.85:
		return
	if _burst == 0 and spread > lerpf(smin, smax, 0.3) + (Player.WALK_SPREAD if _moving else 0.0):
		return
	_shoot(w, g)


func _shoot(w: Dictionary, g: Dictionary) -> void:
	g["mag"] -= 1
	_wear(g, float(w.get("wear", 0.0)))
	var space := get_world_2d().direct_space_state
	var origin := global_position + HAND
	var shot_dir := aim.rotated(randf_range(-spread, spread))
	_shots.clear()
	for i in int(w["pellets"]):
		var dir := shot_dir.rotated(randf_range(-w["spread"], w["spread"]))
		var to := origin + dir * float(w["range"]) * randf_range(0.85, 1.0)
		var q := PhysicsRayQueryParameters2D.create(origin + dir * 14.0, to, Game.LAYER_WALL | Game.LAYER_PLAYER | Game.LAYER_ZOMBIE | Game.LAYER_ANIMAL | Game.LAYER_NPC | Game.LAYER_GATE, [get_rid()])
		q.hit_from_inside = true
		var hit := space.intersect_ray(q)
		var end := to
		if not hit.is_empty():
			end = hit["position"]
			var col: Object = hit["collider"]
			var dmg := float(w["damage"]) * GUN_DAMAGE
			if col is Player or col is Survivor or col is Zombie or col is Animal:
				Zombie.hit(col as Node2D, dmg, dir, self)
		_shots.append(end)
	_shot_t = 0.07
	spread = minf(spread + float(w["recoil"]) * SPREAD_MULT, float(w["spread_max"]) * SPREAD_MULT + 0.2)
	Game.make_noise(global_position, w["noise"])
	# Rifles fire short bursts, everything else one shot at a time (slower than you).
	if weapon_id() == "rifle":
		_burst += 1
		if _burst >= 3:
			_burst = 0
			_attack_cd = randf_range(0.9, 1.5)
		else:
			_attack_cd = 0.13
	else:
		_attack_cd = maxf(float(w["cooldown"]) * 2.0, 0.6) * randf_range(0.9, 1.3)


func _start_reload() -> void:
	var it = weapon_item()
	if reloading or it == null or weapon()["melee"]:
		return
	if _ammo_count(weapon()["ammo"]) <= 0:
		if int(it["mag"]) <= 0:
			_pick_weapon() # out of ammo: switch to the melee weapon / fists
		return
	reloading = true
	_reload_t = float(weapon()["reload"]) * 1.3


func _finish_reload() -> void:
	reloading = false
	var it = weapon_item()
	if it == null or weapon()["melee"]:
		return
	var w := weapon()
	it["mag"] += _take_ammo(w["ammo"], int(w["mag"]) - int(it["mag"]))


func _wear(it, amount: float) -> void:
	if it == null or not it.has("cond") or amount <= 0.0:
		return
	it["cond"] = maxf(float(it["cond"]) - amount, 0.0)
	if Items.is_ruined(it):
		_pick_weapon()


func take_damage(amount: float, dir := Vector2.ZERO, from: Node2D = null) -> void:
	if dead:
		return
	health -= amount * armour_mult()
	_flash_t = 0.12
	_knock = dir * 120.0
	if from != null:
		last_hit_by = from
	Game.hit_fx(get_parent(), global_position, dir)
	# Fights back (bandits don't turn on each other over a stray bullet)
	if from != null and is_instance_valid(from) and not (from is Survivor) and state != State.FLEE:
		foe = from
		state = State.FIGHT
		_lose_t = 6.0
		_last_seen = from.global_position
		_repath_t = 0.0
	if health <= 0.0:
		_die(dir)
	elif health < 30.0 and not _healed and state == State.FIGHT and _foe_ok() and randf() < 0.35:
		_run_away()


func _die(dir: Vector2) -> void:
	dead = true
	health = 0.0
	remove_from_group("survivors")
	collision_layer = 0
	collision_mask = 0
	z_index = -5
	_held.visible = false
	_sprite.modulate = Color.WHITE
	_sprite.play("death_side" if dir.x >= 0.0 else "death_side-left")
	var blood := Game.make_sprite("blood_%d" % randi_range(1, 5))
	blood.show_behind_parent = true
	blood.position = Vector2(randf_range(-4, 4), 2)
	add_child(blood)
	# Everything they had ends up on the ground: weapon first, then clothes and supplies.
	var drop := []
	for s in ["primary", "secondary", "melee", "armour", "back", "coat", "head", "boots", "pants", "shirt"]:
		if gear.get(s) != null:
			drop.append(gear[s])
			gear[s] = null
	drop.append_array(items)
	items = []
	var pile := LootSpot.new()
	pile.is_bag = true
	pile.contents = drop
	pile.position = global_position + Vector2(0, 6)
	Game.ground(self).call_deferred("add_child", pile)
	died.emit(self)
	queue_redraw()
	get_tree().create_timer(120.0).timeout.connect(queue_free)


# ---------------------------------------------------------------- visuals

func _animate() -> void:
	if dead:
		return
	var d := Game.dir_name(facing)
	var anim := ("run_" if _moving else "idle_") + d
	if _swing_t > -0.05 and weapon_id() == "fists":
		anim = "punch_" + d
	if _sprite.animation != anim:
		_sprite.play(anim)
	_sprite.speed_scale = 0.45 if (_moving and state == State.WANDER) else 0.75
	_sprite.modulate = Color(1, 0.55, 0.55) if _flash_t > 0.0 else Color.WHITE
	var held: String = weapon()["held"]
	_held.visible = held != ""
	if not _held.visible:
		return
	_held.texture = Items.icon_of(held)
	var hm := maxf(_held.texture.get_width(), _held.texture.get_height())
	_held.scale = Vector2.ONE * (2.0 if hm <= 18.0 else 0.85)
	_held.z_index = -1 if d == "up" else 0
	if weapon()["melee"]:
		var side := 1.0 if facing.x >= 0.0 else -1.0
		_held.flip_h = side < 0.0
		_held.flip_v = false
		if _swing_t > 0.0:
			var t := clampf(_swing_t / 0.22, 0.0, 1.0)
			_held.rotation = facing.angle() + PI * 0.5 + lerpf(1.2, -1.2, 1.0 - t) * side
			_held.position = HAND + facing * 10.0
		else:
			_held.rotation = -0.5 * side
			_held.position = HAND + Vector2(6 * side, -2)
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
	# Name tag + health bar so you can tell them apart from you at a glance
	var font := ThemeDB.fallback_font
	var col := Color(1, 0.42, 0.36) if state == State.FIGHT else Color(0.95, 0.75, 0.55)
	draw_string(font, Vector2(-40, -38), "Bandit", HORIZONTAL_ALIGNMENT_CENTER, 80, 10, col)
	if health < 100.0:
		draw_rect(Rect2(-12, -34, 24, 3), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-12, -34, 24 * health / 100.0, 3), Color(0.85, 0.25, 0.2))
	if _shot_t > 0.0:
		var muzzle := HAND + aim * 24.0
		for end in _shots:
			draw_line(muzzle, to_local(end), Color(1, 0.9, 0.5, 0.85), 1.5)
		draw_circle(muzzle, 4.0, Color(1, 0.85, 0.4))
	if _swing_t > 0.0 and weapon()["melee"]:
		draw_arc(HAND, float(weapon()["range"]) - 6.0, facing.angle() - 1.0, facing.angle() + 1.0, 12, Color(1, 1, 1, 0.35), 2.0)


# ---------------------------------------------------------------- saving

func to_save() -> Dictionary:
	return {"pos": [position.x, position.y], "home": [home.x, home.y], "health": health, "gear": gear, "items": items}


static func from_save(d: Dictionary) -> Survivor:
	var s := Survivor.new()
	s.position = SaveGame.vec(d["pos"])
	s.home = SaveGame.vec(d.get("home", d["pos"]))
	s.health = float(d.get("health", 100.0))
	var g: Dictionary = d.get("gear", {})
	for slot in Inventory.GEAR:
		s.gear[slot] = SaveGame.fix_item(g.get(slot))
	for it in d.get("items", []):
		s.items.append(SaveGame.fix_item(it))
	return s
