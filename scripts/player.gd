class_name Player
extends CharacterBody2D
## The survivor: movement, needs (health/hunger/thirst), weapons, inventory.

signal died

const RADIUS := 11.0
const WALK_SPEED := 84.0
const SPRINT_SPEED := 117.0
const HAND := Vector2(0, -8)

var world: World
var health := 100.0
var hunger := 100.0
var thirst := 100.0
var bleeding := false
var poison_t := 0.0 # seconds of food poisoning left
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
var nearest_fire: Campfire = null
var nearest_tap: WaterSource = null
var nearest_structure: Structure = null # something you built, in reach
var near_tree := Vector2i(-1, -1) # a tree you could chop (with an axe)
var in_base := false # near one of your beds (set by main.gd)
## Building: the kit being placed ("" = not building). The spot is the tile in front of you.
var placing := ""
var near_lake := false # standing at a lake / river bank
var cook_t := 0.0 # cooking in progress (seconds left)
var message := ""
var message_t := 0.0
var reloading := false
var reload_progress := 0.0

var _attack_cd := 0.0
var _reload_t := 0.0
var _reload_total := 1.0
var _swing_t := 0.0
var _shots: Array = [] # [from_local, to_global] for muzzle tracers
var _sprinting := false

# Gun aiming: the gun aims at the nearest zombie by itself; the aim cone (aim_spread, half-angle in
# radians) narrows while you hold still and opens up when you move, shoot or switch targets.
var aim_spread := 0.5
var aim_target: Node2D = null
const WALK_SPREAD := 0.22 # extra cone while walking
const SPRINT_SPREAD := 0.5 # extra cone while sprinting
var _shot_t := 0.0
var _hunger_msg_t := 0.0
# Timed actions: eating, bandaging, searching... take a while (you can only shuffle along meanwhile).
var busy_t := 0.0
var busy_total := 0.0
var busy_label := ""
var _busy_done := Callable()
const T_SEARCH := 1.0
const T_PICKUP := 1.0
const T_EAT := 3.0
const T_DRINK := 3.0
const T_BANDAGE := 5.0
const T_FIRSTAID := 5.0
const T_SKIN := 3.0
const T_CRAFT := 2.0
const T_REPAIR := 3.0
const T_TEAR := 2.0
const T_FIRE := 2.0
const T_BUILD := 2.0
const T_PLANT := 2.0
const T_HARVEST := 2.0
const T_DISMANTLE := 3.0
const T_CHOP := 4.0
## Fishing: a bite takes 3-10 s (faster in the rain), then the fish is hooked or gets away.
const FISH_TIME := Vector2(3.0, 10.0)
const FISH_HOOK := 0.55
const FISH_HOOK_RAIN := 0.7
var _thirst_msg_t := 0.0
var _hurt_t := 0.0
var _noise_t := 0.0
var _sprite: AnimatedSprite2D
var _held: Sprite2D
var _moving := false
var _pack: Node2D # draws the backpack on the character
var _melee_dir := Vector2.RIGHT
var camera: Camera2D
const ZOOM_MIN := 1.0 # see more
const ZOOM_MAX := 3.0 # close up
var _loot_t := 0.0


func _ready() -> void:
	add_to_group("player")
	collision_layer = Game.LAYER_PLAYER
	collision_mask = Game.LAYER_WALL | Game.LAYER_ZOMBIE | Game.LAYER_NPC | Game.LAYER_WATER
	add_child(Game.foot_shape(RADIUS, 7.0))

	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = Game.frames("player", sprite_spec())
	_sprite.scale = Vector2(2, 2)
	_sprite.offset = Vector2(0, -7)
	_sprite.play("idle_down")
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/outfit.gdshader")
	_sprite.material = mat
	add_child(_sprite)
	_pack = Node2D.new()
	_pack.draw.connect(_draw_pack)
	add_child(_pack)
	inv.changed.connect(update_outfit)
	_held = Sprite2D.new()
	_held.scale = Vector2(2, 2)
	_held.visible = false
	add_child(_held)

	var cam := Camera2D.new()
	camera = cam
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
	update_outfit()
	# You start with nothing but the clothes you're wearing.
	say("Find food, water and a weapon. Stay alive.")


## Animations of the survivor sprite (also used by bandits).
static func sprite_spec() -> Dictionary:
	var spec := {}
	for d in Game.DIRS:
		spec["idle_" + d] = ["player_idle_" + d, 6, 8.0, true]
		spec["run_" + d] = ["player_run_" + d, 6, 12.0, true]
		spec["punch_" + d] = ["player_punch_" + d, 4, 20.0, false]
	for d in ["side", "side-left"]:
		spec["death_" + d] = ["player_death_" + d, 6, 10.0, false]
	return spec


func say(text: String) -> void:
	message = text
	message_t = 3.5


func set_night(_n: float) -> void:
	pass # night is a uniform tint (main.gd); no limited light radius


# ---------------------------------------------------------------- weapons

## Selected weapon (1/2/3), or "fists" (also when the selected weapon is broken).
func weapon_id() -> String:
	var w = inv.weapon_item()
	return "fists" if w == null or Items.is_ruined(w) else String(w["id"])


func weapon() -> Dictionary:
	return Items.WEAPONS[weapon_id()]


## The selected gun's item dict (holds "mag"), or {} for melee.
func gun() -> Dictionary:
	return inv.weapon_item() if not weapon()["melee"] else {}


## 1/2/3 and mouse wheel: switch between main gun, secondary and melee.
func switch_weapon(slot: String) -> void:
	reloading = false
	if inv.gear[slot] != null and Items.is_ruined(inv.gear[slot]) and inv.active != slot:
		say("Your %s is broken" % Items.name_of(inv.gear[slot]["id"]).to_lower())
		return
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


## Right-click menu: what can be done with the item at `loc`. [[label, action], ...]
func actions_for(loc: Dictionary) -> Array:
	var it = inv.get_at(loc)
	if it == null:
		return []
	var id: String = it["id"]
	var out := []
	var d := Items.def(id)
	if it.has("water") and loc["t"] != "near":
		out.append(["Drink (%d/%d)" % [it["water"], d["capacity"]], "drink_gourd"])
	if Items.is_usable(id):
		var verb := "Use"
		if Items.kind(id) == "consumable":
			verb = "Drink" if d.get("thirst", 0.0) > d.get("hunger", 0.0) else "Eat"
		out.append([verb, "use"])
	var slot := Items.equip_of(id)
	if slot != "":
		var worn: bool = loc["t"] == "gear" and loc["s"] == slot
		if Items.is_weapon(id):
			if worn:
				out.append(["Lower weapon" if inv.active == slot else "Select", "select"])
			else:
				out.append(["Equip", "equip"])
		elif not worn and not Items.is_ruined(it):
			out.append(["Wear", "equip"])
		if worn:
			out.append(["Take off" if Items.is_clothing(id) else "Put away", "unequip"])
	var fix := Items.repair_kind(id)
	if fix != "" and it.has("cond") and loc["t"] != "near":
		var c := float(it["cond"])
		if c > 0.0 and c < 100.0:
			var kit := "sewing_kit" if fix == "sew" else "toolbox"
			out.append(["Repair (%s)" % Items.name_of(kit).to_lower() if inv.count_of(kit) > 0 else "Repair - needs a " + Items.name_of(kit).to_lower(), "repair"])
	if d.has("builds") and loc["t"] != "near":
		out.append(["Build", "build"])
	if d.has("tear"):
		out.append(["Tear into rags", "tear"])
	if id == "sticks" or id == "matches":
		out.append(["Build campfire", "fire"])
	if loc["t"] == "near":
		out.append(["Take", "take"])
	else:
		out.append(["Drop", "drop"])
	return out


func do_action(loc: Dictionary, action: String) -> void:
	var it = inv.get_at(loc)
	if it == null:
		return
	var id: String = it["id"]
	match action:
		"use":
			_consume_timed(loc, id)
		"equip":
			var err := inv.equip(loc)
			say(err if err != "" else ("Wearing " if Items.is_clothing(id) else "Equipped ") + Items.display_name(it).to_lower())
		"select":
			switch_weapon(loc["s"])
		"unequip":
			var taken = inv.take(loc)
			if inv.pickup_to_storage(taken) > 0:
				inv.put(loc, taken)
				say("No room to put it away")
		"tear":
			start_busy("Tearing..", T_TEAR, func():
				var it2 = inv.get_at(loc)
				if it2 != null and it2["id"] == id:
					tear(loc))
		"repair":
			if Items.is_ruined(it) or float(it.get("cond", 100.0)) >= 100.0 or inv.find("sewing_kit" if Items.repair_kind(id) == "sew" else "toolbox").is_empty():
				repair(loc) # just says why it can't
			else:
				start_busy("Repairing..", T_REPAIR, func():
					var it2 = inv.get_at(loc)
					if it2 != null and it2["id"] == id:
						repair(loc))
		"drink_gourd":
			if int(it.get("water", 0)) <= 0 or thirst > 97.0:
				drink_gourd(loc) # just says why not
			else:
				start_busy("Drinking..", T_DRINK, func():
					var it2 = inv.get_at(loc)
					if it2 != null and it2["id"] == id:
						drink_gourd(loc))
		"fire":
			build_fire_timed()
		"build":
			start_placing(id)
			Game.ui_open = false
			var hud := get_tree().get_first_node_in_group("hud")
			if hud:
				hud.set_inventory_open(false)
		"take":
			var left := inv.pickup(it)
			var taken: Dictionary = inv.take(loc)
			if left > 0:
				taken["count"] = left
				inv.near.contents.append(taken)
				inv.near.refresh()
				say("No free slots")
		"drop":
			drop(loc)


## Starts a timed action. `done` runs when the time is up. Only one at a time.
func start_busy(label: String, secs: float, done: Callable) -> bool:
	if busy_t > 0.0:
		say("Busy: " + busy_label.trim_suffix("..").to_lower())
		return false
	busy_label = label
	busy_total = secs
	busy_t = secs
	_busy_done = done
	reloading = false
	return true


## Completes the current timed action right away (also what the timer calls).
func finish_busy() -> void:
	busy_t = 0.0
	var f := _busy_done
	_busy_done = Callable()
	if f.is_valid() and not dead:
		f.call()


func cancel_busy() -> void:
	if busy_t > 0.0:
		busy_t = 0.0
		_busy_done = Callable()
		say("Stopped")


## Old one-click behaviour, still used for quick right-click without a menu (tests).
## Never drops anything by accident.
func quick_use(loc: Dictionary) -> void:
	var acts := actions_for(loc)
	if not acts.is_empty() and acts[0][1] != "drop":
		do_action(loc, acts[0][1])


## One drink from a water gourd (it stays, empty, when it runs out).
func drink_gourd(loc: Dictionary) -> bool:
	var it = inv.get_at(loc)
	if it == null or int(it.get("water", 0)) <= 0:
		say("The gourd is empty - fill it at a tap, lake or river")
		return false
	if thirst > 97.0:
		say("Not thirsty")
		return false
	thirst = minf(thirst + float(Items.def(it["id"])["thirst"]), 100.0)
	it["water"] = int(it["water"]) - 1
	inv.changed.emit()
	say("Drank from the gourd (%d/%d left)" % [it["water"], Items.def(it["id"])["capacity"]])
	return true


## At a tap or a lake / river: drink your fill, then fill every gourd you carry.
## Taps only have a little water left; lakes and rivers never run dry.
func use_water(tap: WaterSource = null) -> void:
	var units: int = 1000 if tap == null else tap.water
	if units <= 0:
		say("The tap is dry")
		return
	var drank := 0
	while thirst < 90.0 and units > 0:
		thirst = minf(thirst + 40.0, 100.0)
		units -= 1
		drank += 1
	var filled := 0
	var gourds := inv.all_of("gourd")
	for g in gourds:
		var cap := int(Items.def("gourd")["capacity"])
		while int(g["water"]) < cap and units > 0:
			g["water"] = int(g["water"]) + 1
			units -= 1
			filled += 1
	if tap:
		tap.water = units
		tap.queue_redraw()
	inv.changed.emit()
	var parts := PackedStringArray()
	if drank > 0:
		parts.append("You drink your fill" if thirst >= 90.0 else "You drink the last of the water")
	if filled > 0:
		parts.append("filled your gourd%s (+%d)" % ["s" if gourds.size() > 1 else "", filled])
	if parts.is_empty():
		say("Not thirsty" + (" - and your gourds are full" if not gourds.is_empty() else ""))
	else:
		say(", ".join(parts))


## Sewing kit (clothing) or toolbox (weapons, helmets, metal armour): +40% condition per use.
## Ruined things are beyond repair.
func repair(loc: Dictionary) -> bool:
	var it = inv.get_at(loc)
	if it == null or not it.has("cond"):
		return false
	var fix := Items.repair_kind(it["id"])
	if fix == "":
		say("That can't be repaired")
		return false
	if Items.is_ruined(it):
		say("It's ruined - beyond repair")
		return false
	if float(it["cond"]) >= 100.0:
		say("It's in perfect condition")
		return false
	var kit_id := "sewing_kit" if fix == "sew" else "toolbox"
	var kit_loc := inv.find(kit_id)
	if kit_loc.is_empty():
		say("You need a " + Items.name_of(kit_id).to_lower())
		return false
	var kit: Dictionary = inv.get_at(kit_loc)
	it["cond"] = minf(float(it["cond"]) + Items.REPAIR_AMOUNT, 100.0)
	kit["uses"] = int(kit.get("uses", 1)) - 1
	var msg := "Repaired the %s (%d%%)" % [Items.name_of(it["id"]).to_lower(), int(it["cond"])]
	if int(kit["uses"]) <= 0:
		inv.take(kit_loc)
		msg += " - the %s is used up" % Items.name_of(kit_id).to_lower()
	inv.changed.emit()
	say(msg)
	return true


## Weapons wear out with use. Returns true if it just broke.
func _wear_weapon(amount: float) -> bool:
	var it = inv.weapon_item()
	if it == null or not it.has("cond") or amount <= 0.0 or Items.is_ruined(it):
		return false
	it["cond"] = maxf(float(it["cond"]) - amount, 0.0)
	if Items.is_ruined(it):
		reloading = false
		say("Your %s broke!" % Items.name_of(it["id"]).to_lower())
		inv.changed.emit()
		return true
	return false


## Tear a shirt into rags (rags craft into bandages and rope). Anything stored in it drops to the ground.
func tear(loc: Dictionary) -> void:
	var it: Dictionary = inv.take(loc)
	var n: int = Items.def(it["id"])["tear"]
	if Items.is_ruined(it):
		n = maxi(n - 1, 1)
	for x in it.get("cargo", []):
		if x != null:
			drop_item(x)
	var left := inv.pickup(Items.make("rags", n))
	if left > 0:
		drop_item(Items.make("rags", left))
	say("Tore the %s into %d rags" % [Items.name_of(it["id"]).to_lower(), n])


## Crafting menu: make something from a recipe (see crafting.gd).
func craft(recipe_id: String) -> bool:
	var r := Crafting.get_recipe(recipe_id)
	if r.is_empty():
		return false
	var miss := Crafting.missing(r, inv)
	if miss != "":
		say("Missing: " + miss)
		return false
	if recipe_id == "campfire":
		var before := get_tree().get_nodes_in_group("fires").size()
		build_fire()
		return get_tree().get_nodes_in_group("fires").size() > before
	for item in r["needs"]:
		inv.remove(item, int(r["needs"][item]))
	var made := Items.make(r["makes"], int(r["count"]))
	var left := inv.pickup(made)
	if left > 0:
		made["count"] = left
		drop_item(made)
	say("Crafted " + String(r["name"]).to_lower())
	return true


## Eat / drink / bandage from the inventory: takes a few seconds, then the item is used up.
func _consume_timed(loc: Dictionary, id: String) -> void:
	var why := _not_needed(id)
	if why != "":
		say(why)
		return
	var d := Items.def(id)
	var label := "Eating.."
	var secs := T_EAT
	if Items.kind(id) == "medical":
		label = "Bandaging.." if id == "bandage" else "Using first aid kit.."
		secs = T_BANDAGE if id == "bandage" else T_FIRSTAID
	elif d.get("thirst", 0.0) > d.get("hunger", 0.0):
		label = "Drinking.."
		secs = T_DRINK
	start_busy(label, secs, func():
		var it2 = inv.get_at(loc)
		if it2 != null and it2["id"] == id:
			_consume(loc, id)
		elif inv.count_of(id) > 0:
			use_item(id)
		else:
			say("It's gone"))


## "" if using the item would do something, otherwise why not.
func _not_needed(id: String) -> String:
	var d := Items.def(id)
	if Items.kind(id) == "medical":
		var cures: Array = d.get("cures", [])
		if (bleeding and "bleeding" in cures) or (poison_t > 0.0 and "poison" in cures) or (d.get("heal", 0.0) > 0.0 and health < 100.0):
			return ""
		return "You don't need that"
	var h: float = d.get("hunger", 0.0)
	var t: float = d.get("thirst", 0.0)
	if (h <= 0.0 or hunger > 97.0) and (t <= 0.0 or thirst > 97.0):
		return "Not hungry" if h > t else "Not thirsty"
	return ""


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
	_loot_t -= delta
	if _loot_t <= 0.0:
		_loot_t = 0.1 # no need to look for nearby things every frame
		_find_loot()
	_animate()
	queue_redraw()


func _timers(delta: float) -> void:
	if busy_t > 0.0:
		busy_t -= delta
		if busy_t <= 0.0:
			finish_busy()
	if cook_t > 0.0:
		cook_t -= delta
		if cook_t <= 0.0:
			_finish_cooking()
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
	var sprinting := Input.is_action_pressed("sprint") and dir != Vector2.ZERO and busy_t <= 0.0
	_sprinting = sprinting
	var speed := SPRINT_SPEED if sprinting else WALK_SPEED
	if health < 30.0:
		speed *= 0.8
	if busy_t > 0.0:
		speed *= 0.5 # eating / bandaging / searching: you can only shuffle along
	velocity = dir * speed
	move_and_slide()
	_moving = dir != Vector2.ZERO

	if Game.aim_mode == "mouse":
		if not Game.ui_open:
			var m := get_global_mouse_position() - (global_position + HAND)
			if m.length() > 2.0:
				aim = m.normalized()
	elif dir != Vector2.ZERO:
		aim = aim.lerp(dir.normalized(), 0.35).normalized() # auto aim: face where you walk
	_update_aim(delta)

	if _moving:
		_noise_t -= delta
		if _noise_t <= 0.0:
			_noise_t = 0.4
			var quiet := 0.7 if inv.gear["boots"] != null else 1.0
			Game.make_noise(global_position, (280.0 if sprinting else 90.0) * quiet)


func _needs(delta: float) -> void:
	hunger = maxf(hunger - delta * 100.0 / 900.0, 0.0) # full -> empty in 15 min
	thirst = maxf(thirst - delta * 100.0 / 600.0, 0.0) # full -> empty in 10 min
	var tt := target_temp()
	var rate := TEMP_RATE
	if tt > body_temp and Game.weather != "clear" and not indoors():
		rate *= 0.5 # wet / snowed on: you warm up slower
	body_temp = move_toward(body_temp, tt, rate * delta)
	if poison_t > 0.0:
		poison_t -= delta
		thirst = maxf(thirst - delta * 100.0 / 600.0, 0.0) # sick: thirst drains twice as fast
	var dmg := 0.0
	if poison_t > 0.0:
		dmg += 0.25
	if hunger <= 0.0:
		dmg += 1.0
	if thirst <= 0.0:
		dmg += 1.5
	if bleeding:
		dmg += 1.5
	if body_temp < TEMP_FREEZING:
		dmg += 0.5
	_need_messages(delta)
	if dmg > 0.0:
		take_damage(dmg * delta, false)
	elif can_heal():
		health = minf(health + 0.4 * delta, 100.0)


## "I'm hungry" / "I'm thirsty" when they drop below 25% (repeats every minute while it stays low).
func _need_messages(delta: float) -> void:
	_hunger_msg_t -= delta
	_thirst_msg_t -= delta
	if hunger >= 25.0:
		_hunger_msg_t = 0.0
	elif _hunger_msg_t <= 0.0:
		_hunger_msg_t = 60.0
		say("I'm starving!" if hunger <= 0.0 else "I'm hungry")
	if thirst >= 25.0:
		_thirst_msg_t = 0.0
	elif _thirst_msg_t <= 0.0:
		_thirst_msg_t = 60.0
		say("I'm dehydrated!" if thirst <= 0.0 else "I'm thirsty")


func indoors() -> bool:
	return world != null and world.building_at(global_position) >= 0


## Temperature the body is heading towards.
func target_temp() -> float:
	var air := lerpf(TEMP_DAY, TEMP_NIGHT, Game.night)
	if not indoors():
		air -= {"rain": 6.0, "snow": 12.0}.get(Game.weather, 0.0)
	if indoors():
		air += TEMP_INDOORS
	var fire := 0.0
	for f in get_tree().get_nodes_in_group("fires"):
		fire = maxf(fire, (f as Campfire).warmth_at(global_position))
	return clampf(air + inv.warmth() + fire, 0.0, 100.0)


func near_fire() -> bool:
	for f in get_tree().get_nodes_in_group("fires"):
		if (f as Campfire).warmth_at(global_position) > 0.0:
			return true
	return false


## Healing needs: warm enough, hunger & thirst at least 75%, not bleeding.
func can_heal() -> bool:
	return body_temp >= TEMP_WARM and hunger >= 75.0 and thirst >= 75.0 and not bleeding and poison_t <= 0.0


func temp_status() -> String:
	if body_temp < TEMP_FREEZING:
		return "Freezing"
	if body_temp < TEMP_COLD:
		return "Cold"
	if body_temp < TEMP_WARM:
		return "Chilly"
	return "Warm"


## Held actions (attack) are polled every physics frame; everything that happens once per key
## press goes through _unhandled_input so a press can never be missed between physics frames.
func _actions() -> void:
	if Game.click_used and not Input.is_action_pressed("attack"):
		Game.click_used = false
	var w := weapon()
	if w["melee"]:
		_auto_melee()
		return
	var pull := Input.is_action_pressed("fire") or (Game.aim_mode == "mouse" and Input.is_action_pressed("attack") and not Game.click_used)
	if pull and _attack_cd <= 0.0 and not reloading and busy_t <= 0.0:
		shoot()


func _unhandled_input(event: InputEvent) -> void:
	if dead or get_tree().paused or not event.is_pressed() or event.is_echo():
		return
	# Mouse wheel: zoom the camera in / out
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		if not Game.ui_open and camera:
			var z := camera.zoom.x * (1.12 if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12)
			camera.zoom = Vector2.ONE * clampf(z, ZOOM_MIN, ZOOM_MAX)
			get_viewport().set_input_as_handled()
		return
	# These also work with the inventory open. (Eating, drinking and bandaging are done from the inventory.)
	if event.is_action_pressed("aim_mode"):
		Game.aim_mode = "mouse" if Game.aim_mode == "auto" else "auto"
		Game.save_settings()
		say("Auto aim: Space shoots the nearest enemy" if Game.aim_mode == "auto" else "Mouse aim: click to shoot")
	elif event.is_action_pressed("weapon_primary"):
		switch_weapon("primary")
	elif event.is_action_pressed("weapon_secondary"):
		switch_weapon("secondary")
	elif event.is_action_pressed("weapon_melee"):
		switch_weapon("melee")
	elif event.is_action_pressed("reload"):
		start_reload()
	elif event.is_action_pressed("holster") and placing != "":
		stop_placing()
	elif event.is_action_pressed("holster") and busy_t > 0.0:
		cancel_busy()
	elif event.is_action_pressed("holster") and inv.active != "":
		holster()
	elif Game.ui_open:
		return
	elif event.is_action_pressed("interact") and placing != "":
		place_kit()
	elif event.is_action_pressed("build"):
		if placing == "":
			start_placing()
		else:
			next_kit()
	elif event.is_action_pressed("interact"):
		interact()
	elif event.is_action_pressed("build_fire"):
		build_fire_timed()
	elif event.is_action_pressed("fish"):
		go_fishing()
	else:
		return
	get_viewport().set_input_as_handled()


## What E would do right now: "fire", "loot", "water" or "" (closest wins).
func interact_choice() -> String:
	var best := ""
	var best_d := INF
	if nearest_fire:
		best_d = global_position.distance_to(nearest_fire.global_position)
		best = "fire"
	if nearest_loot and global_position.distance_to(nearest_loot.global_position) < best_d:
		best_d = global_position.distance_to(nearest_loot.global_position)
		best = "loot"
	if nearest_structure and global_position.distance_to(nearest_structure.global_position) < best_d:
		best_d = global_position.distance_to(nearest_structure.global_position)
		best = "build"
	var water_d := INF
	if nearest_tap:
		water_d = global_position.distance_to(nearest_tap.global_position)
	elif near_lake:
		water_d = 30.0
	if water_d < best_d:
		best = "water"
		best_d = water_d
	if best == "" and near_tree.x >= 0 and has_axe():
		best = "tree"
	return best


func has_axe() -> bool:
	return inv.count_of("axe") > 0 or (inv.gear["melee"] != null and inv.gear["melee"]["id"] == "axe" and not Items.is_ruined(inv.gear["melee"]))


func action_label() -> String:
	match interact_choice():
		"fire":
			return nearest_fire.label(self)
		"loot":
			return nearest_loot.label()
		"water":
			if nearest_tap:
				return nearest_tap.label()
			return "Drink / fill gourd" if not inv.all_of("gourd").is_empty() else "Drink"
		"build":
			return _structure_label(nearest_structure)
		"tree":
			return "Chop wood"
	return ""


func _structure_label(st: Structure) -> String:
	match st.kind:
		"bed":
			return "Sleep"
		"garden":
			if st.crop == "":
				var seed := _seed_to_plant()
				return "Plant " + Structure.CROPS[seed]["name"].to_lower() if seed != "" else "Garden bed (no seeds)"
			if st.ripe():
				return "Harvest " + Structure.CROPS[st.crop]["name"].to_lower()
			return "%s %d%%" % [Structure.CROPS[st.crop]["name"], int(st.growth * 100.0)]
	return "Dismantle " + st.title().to_lower()


## What you'd plant: tomato seeds first, else a potato.
func _seed_to_plant() -> String:
	if inv.count_of("tomato_seeds") > 0:
		return "tomato"
	if inv.count_of("potato") > 0:
		return "potato"
	return ""


## E / action button: whatever is closest — a fire, water, a carcass, a container or an item on the ground.
func interact() -> void:
	match interact_choice():
		"fire":
			use_fire(nearest_fire)
			return
		"water":
			var tap := nearest_tap
			if tap != null and tap.water <= 0:
				use_water(tap) # "The tap is dry"
			else:
				start_busy("Drinking..", T_DRINK, func(): use_water(tap))
			return
		"build":
			_use_structure(nearest_structure)
			return
		"tree":
			start_busy("Chopping..", T_CHOP, func():
				var left := inv.pickup(Items.make("planks", 2))
				if left > 0:
					drop_item(Items.make("planks", left))
				say("Chopped 2 planks"))
			return
		"":
			return
	var spot := nearest_loot
	if spot.kind == "chest":
		spot.opened = true
		Game.open_inventory = true # your chest's contents show in the nearby list
		return
	if spot.kind == "carcass":
		if not has_blade():
			say("You need a knife or an axe to skin it")
			return
		start_busy("Skinning..", T_SKIN, func():
			if is_instance_valid(spot):
				say(spot.spill(self).replace("Found:", "Skinned:")))
	elif spot.is_bag:
		start_busy("Picking up..", T_PICKUP, func():
			if is_instance_valid(spot) and not spot.is_queued_for_deletion():
				say(spot.search(self)))
	else:
		start_busy("Searching..", T_SEARCH, func():
			if is_instance_valid(spot):
				say(spot.spill(self)))


func has_blade() -> bool:
	if inv.count_of("knife") > 0 or inv.count_of("axe") > 0:
		return true
	var m = inv.gear["melee"]
	return m != null and m["id"] in ["knife", "axe"]


func has_rod() -> bool:
	return inv.count_of("fishing_rod") > 0


## F at a lake or river with a fishing rod: wait for a bite (3-10 s, faster in the rain), then it's
## either hooked (a raw fish lands at your feet) or gets away.
func go_fishing() -> void:
	if not near_lake:
		say("Stand at the edge of a lake or river to fish")
		return
	if not has_rod():
		say("You need a fishing rod (craft one: 2 sticks + rope)")
		return
	var rain := Game.weather == "rain"
	var t := randf_range(FISH_TIME.x, FISH_TIME.y) * (0.6 if rain else 1.0)
	start_busy("Fishing..", t, func():
		if randf() < (FISH_HOOK_RAIN if rain else FISH_HOOK):
			drop_item(Items.make("fish"))
			say("Caught a fish!")
		else:
			say(["Nothing bit", "It got away"].pick_random()))


## Q at something you built: sleep, plant, harvest, or take it apart.
func _use_structure(st: Structure) -> void:
	var main := get_tree().get_first_node_in_group("main")
	match st.kind:
		"bed":
			if main:
				main.sleep()
		"garden":
			if st.crop == "":
				var seed := _seed_to_plant()
				if seed == "":
					say("You need tomato seeds or a potato to plant")
					return
				start_busy("Planting..", T_PLANT, func():
					if st.crop == "" and inv.remove(Structure.CROPS[seed]["seed"], 1) == 1:
						st.plant(seed, main.world_days if main else 0.0)
						say("Planted %s - ready in %.1f days" % [Structure.CROPS[seed]["name"].to_lower(), Structure.CROPS[seed]["days"]]))
			elif st.ripe():
				start_busy("Harvesting..", T_HARVEST, func():
					if st.ripe():
						var items := st.harvest()
						for it in items:
							drop_item(it)
						say("Harvested: " + ", ".join(items.map(func(it): return "%s x%d" % [Items.name_of(it["id"]).to_lower(), it["count"]]))))
			else:
				say("Still growing (%d%%)" % int(st.growth * 100.0))
		_:
			start_busy("Dismantling..", T_DISMANTLE, func():
				if is_instance_valid(st):
					var refund: Dictionary = Structure.KINDS[st.kind]["refund"]
					if st.chest:
						for it in st.chest.contents:
							drop_item(it)
					st.remove()
					for id in refund:
						drop_item(Items.make(id, int(refund[id])))
					say("Took it apart"))


# ---------------------------------------------------------------- building

## Start placing a kit (item menu -> Build, or B for the first kit you carry).
func start_placing(kit := "") -> void:
	if kit == "":
		for k in ["kit_wall", "kit_gate", "kit_chest", "kit_bed", "kit_garden"]:
			if inv.count_of(k) > 0:
				kit = k
				break
	if kit == "" or inv.count_of(kit) <= 0:
		say("No building kits - craft them (K)")
		return
	placing = kit
	say("Building: %s - Q to place, B for the next kit, X to stop" % Items.name_of(kit).to_lower())


## The next kit you carry (B while building).
func next_kit() -> void:
	var kits := ["kit_wall", "kit_gate", "kit_chest", "kit_bed", "kit_garden"]
	var i := kits.find(placing)
	for k in range(1, kits.size() + 1):
		var cand: String = kits[(i + k) % kits.size()]
		if inv.count_of(cand) > 0:
			placing = cand
			say("Building: " + Items.name_of(cand).to_lower())
			return


func stop_placing() -> void:
	if placing != "":
		placing = ""
		say("Stopped building")


## The tile in front of you (the way you face, snapped to up / down / left / right).
func build_cell() -> Vector2i:
	var f := facing
	var d := Vector2(signf(f.x), 0) if absf(f.x) >= absf(f.y) else Vector2(0, signf(f.y))
	return world.cell_of(global_position + d * 34.0 + Vector2(0, -4))


## "" if you can build there, otherwise why not.
func build_problem(cell: Vector2i) -> String:
	if cell.x < 2 or cell.y < 2 or cell.x > World.W - 3 or cell.y > World.H - 3:
		return "Too close to the edge"
	if not world.is_walkable(cell) or world.is_door(cell):
		return "Not there"
	var main := get_tree().get_first_node_in_group("main")
	if main and main.structure_at(cell) != null:
		return "Something's already there"
	var rect := Rect2(Vector2(cell * World.T), Vector2(World.T, World.T)).grow(4)
	for g in ["player", "zombies", "survivors", "animals", "loot"]:
		for n in get_tree().get_nodes_in_group(g):
			if rect.has_point((n as Node2D).global_position):
				return "Something's in the way"
	return ""


func place_kit() -> void:
	if placing == "" or inv.count_of(placing) <= 0:
		stop_placing()
		return
	var cell := build_cell()
	var why := build_problem(cell)
	if why != "":
		say(why)
		return
	var kit := placing
	start_busy("Building..", T_BUILD, func():
		var main := get_tree().get_first_node_in_group("main")
		if main == null or build_problem(cell) != "" or inv.remove(kit, 1) != 1:
			return
		main.add_structure(String(Items.def(kit)["builds"]), cell)
		say("Built " + Items.name_of(kit).to_lower().trim_suffix(" kit"))
		if inv.count_of(kit) <= 0:
			placing = ""
			start_placing() # carry on with another kit if you have one
			if placing == "":
				say("Out of kits"))


## Building a fire takes a moment.
func build_fire_timed() -> void:
	if indoors() or inv.count_of("sticks") < 3 or inv.count_of("matches") < 1:
		build_fire() # just says why not
		return
	start_busy("Building a fire..", T_FIRE, build_fire)


## Crafting from the menu takes a moment.
func craft_timed(recipe_id: String) -> void:
	var r := Crafting.get_recipe(recipe_id)
	if r.is_empty():
		return
	var miss := Crafting.missing(r, inv)
	if miss != "":
		say("Missing: " + miss)
		return
	if recipe_id == "campfire":
		build_fire_timed()
		return
	start_busy("Crafting %s.." % String(r["name"]).to_lower(), T_CRAFT, func(): craft(recipe_id))


## C / right-click sticks: build a campfire (3 sticks + 1 match) at your feet.
func build_fire() -> void:
	if indoors():
		say("You can't build a fire indoors")
		return
	if inv.count_of("sticks") < 3 or inv.count_of("matches") < 1:
		say("A campfire needs 3 sticks and a match")
		return
	var pos := global_position + facing * 26.0
	if not world.is_walkable(world.cell_of(pos)):
		pos = global_position + Vector2(0, 20)
	for f in get_tree().get_nodes_in_group("fires"):
		if (f as Campfire).global_position.distance_to(pos) < 40.0:
			say("There's already a fire here")
			return
	inv.remove("sticks", 3)
	inv.remove("matches", 1)
	var fire := Campfire.new()
	fire.position = pos
	fire.add_sticks(3)
	get_parent().add_child(fire)
	say("You light a campfire")


## Using a fire: cook raw meat, add wood, or relight it.
func use_fire(fire: Campfire) -> void:
	if fire.lit and (inv.count_of("meat") > 0 or inv.count_of("fish") > 0):
		if cook_t <= 0.0:
			cook_t = 3.0
			say("Cooking...")
		return
	if inv.count_of("sticks") <= 0:
		say("You need sticks to keep the fire going")
		return
	if not fire.lit:
		if inv.count_of("matches") <= 0:
			say("You need a match to light it")
			return
		inv.remove("matches", 1)
	inv.remove("sticks", 1)
	fire.add_sticks(1)
	say("The fire burns for %d more seconds" % int(fire.fuel))


func _finish_cooking() -> void:
	if nearest_fire == null or not nearest_fire.lit:
		say("You moved away from the fire")
		return
	var parts := PackedStringArray()
	for raw in ["meat", "fish"]:
		var n := inv.count_of(raw)
		if n <= 0:
			continue
		inv.remove(raw, n)
		var done: String = "cooked_" + String(raw)
		var left := inv.pickup(Items.make(done, n))
		if left > 0:
			drop_item(Items.make(done, left))
		parts.append("%d %s" % [n, raw])
	say("Cooked " + ", ".join(parts))


## Double-click in the inventory: wear / equip / select / use, or take it if it's lying nearby.
func double_click(loc: Dictionary) -> void:
	var it = inv.get_at(loc)
	if it == null:
		return
	if loc["t"] == "near" and Items.equip_of(it["id"]) == "":
		do_action(loc, "take")
	else:
		quick_use(loc)


## Melee fights for you: swing at the nearest zombie / bandit in reach (or an animal).
func _auto_melee() -> void:
	if _attack_cd > 0.0:
		return
	var reach: float = weapon()["range"] + Zombie.RADIUS + 4.0
	var target: Node2D = null
	var best_d := reach
	for n in get_tree().get_nodes_in_group("zombies") + get_tree().get_nodes_in_group("survivors"):
		var t := n as Node2D
		var d := t.global_position.distance_to(global_position)
		if d < best_d and world.has_los(global_position, t.global_position):
			best_d = d
			target = t
	for n in get_tree().get_nodes_in_group("animals"):
		var a := n as Animal
		var d := a.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			target = a
	if target:
		melee((target.global_position - global_position).normalized())


func melee(dir: Vector2) -> void:
	var w := weapon()
	_attack_cd = w["cooldown"]
	_swing_t = 0.22
	_melee_dir = dir
	var reach: float = w["range"]
	var dmg: float = float(w["damage"]) * Items.weapon_factor(inv.weapon_item())
	var hits := 0
	for n in get_tree().get_nodes_in_group("zombies") + get_tree().get_nodes_in_group("survivors"):
		var t := n as Node2D
		var d := t.global_position - global_position
		if d.length() <= reach + Zombie.RADIUS + 4.0 and absf(dir.angle_to(d)) < deg_to_rad(65.0):
			Zombie.hit(t, dmg, d.normalized(), self)
			hits += 1
	for n in get_tree().get_nodes_in_group("animals"):
		var a := n as Animal
		var d := a.global_position - global_position
		if d.length() <= reach + 16.0 and absf(dir.angle_to(d)) < deg_to_rad(65.0):
			a.take_damage(dmg, d.normalized(), self)
			hits += 1
	if hits > 0:
		_wear_weapon(float(w.get("wear", 0.0)))
	Game.make_noise(global_position, w["noise"])


## Picks a target (nearest visible zombie in range, else a nearby animal, else the mouse direction)
## and settles / disturbs the aim cone.
func _update_aim(delta: float) -> void:
	var w := weapon()
	if w["melee"]:
		aim_target = null
		return
	var reach: float = w["range"] * 0.85
	var best: Node2D = null
	var best_d := reach
	for groups in [["zombies", "survivors", "wolves"], ["animals"]]:
		var nodes: Array = []
		for g in groups:
			nodes.append_array(get_tree().get_nodes_in_group(g))
		for n in nodes:
			var t := n as Node2D
			var d := t.global_position.distance_to(global_position)
			# Keep the current target unless something is clearly closer (no flickering).
			if t == aim_target:
				d *= 0.75
			if d < best_d and _clear_shot(t):
				best_d = d
				best = t
		if best != null:
			break # zombies / bandits / wolves first; other animals only when nothing else is around
	if best != aim_target:
		aim_spread = maxf(aim_spread, lerpf(w["spread_min"], w["spread_max"], 0.6))
		aim_target = best
	if aim_target:
		aim = (aim_target.global_position + Vector2(0, -8) - (global_position + HAND)).normalized()
	var smin: float = w["spread_min"]
	var smax: float = w["spread_max"]
	var target_spread := smin
	if _moving:
		target_spread += SPRINT_SPREAD if _sprinting else WALK_SPREAD
	target_spread = minf(target_spread, smax + 0.2)
	if aim_spread > target_spread:
		aim_spread = maxf(aim_spread - (smax - smin) / float(w["aim_time"]) * delta, target_spread)
	else:
		aim_spread = minf(aim_spread + 2.5 * delta, target_spread)


## Only lock onto something a bullet can actually reach (no walls, trees or cars in the way).
func _clear_shot(t: Node2D) -> bool:
	var to := t.global_position + Vector2(0, -8)
	if not world.has_los(global_position + HAND, to):
		return false
	var q := PhysicsRayQueryParameters2D.create(global_position + HAND, to, Game.LAYER_WALL, [get_rid()])
	return get_world_2d().direct_space_state.intersect_ray(q).is_empty()


## How settled the aim is: 0 = wide open, 1 = fully steady.
func aim_steadiness() -> float:
	var w := weapon()
	if w["melee"]:
		return 1.0
	return clampf(1.0 - (aim_spread - w["spread_min"]) / (w["spread_max"] - w["spread_min"]), 0.0, 1.0)


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
	# Worn guns can jam (below 50% condition)
	var cond := float(g.get("cond", 100.0))
	if cond < 50.0 and randf() < (50.0 - cond) / 50.0 * 0.15:
		_attack_cd = 0.9
		say("Jammed! (%d%% condition)" % int(cond))
		return
	g["mag"] -= 1
	_attack_cd = w["cooldown"]
	_shots.clear()
	var space := get_world_2d().direct_space_state
	var origin := global_position + HAND
	# The whole shot goes somewhere inside the aim cone; shotgun pellets spread a bit more around that.
	var shot_dir := aim.rotated(randf_range(-aim_spread, aim_spread))
	for i in int(w["pellets"]):
		var dir := shot_dir.rotated(randf_range(-w["spread"], w["spread"]))
		var from := origin + dir * 14.0
		var to := origin + dir * float(w["range"]) * randf_range(0.85, 1.0)
		var q := PhysicsRayQueryParameters2D.create(from, to, Game.LAYER_WALL | Game.LAYER_ZOMBIE | Game.LAYER_ANIMAL | Game.LAYER_NPC, [get_rid()])
		var hit := space.intersect_ray(q)
		var end := to
		if not hit.is_empty():
			end = hit["position"]
			var col: Object = hit["collider"]
			if col is Zombie or col is Survivor:
				Zombie.hit(col as Node2D, w["damage"], dir, self)
			elif col is Animal:
				(col as Animal).take_damage(w["damage"], dir, self)
		_shots.append(end)
	_shot_t = 0.07
	aim_spread = minf(aim_spread + float(w["recoil"]), float(w["spread_max"]) + 0.2)
	Game.make_noise(global_position, w["noise"])
	_wear_weapon(float(w.get("wear", 0.0)))


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


## Applies a consumable / medical item. Returns false if it wasn't needed.
func _apply_consumable(item: String) -> bool:
	var d := Items.def(item)
	if Items.kind(item) == "medical":
		var cures: Array = d.get("cures", [])
		var needed: bool = (bleeding and "bleeding" in cures) or (poison_t > 0.0 and "poison" in cures) or (d.get("heal", 0.0) > 0.0 and health < 100.0)
		if not needed:
			say("You don't need that")
			return false
		if "bleeding" in cures:
			bleeding = false
		if "poison" in cures:
			poison_t = 0.0
		health = minf(health + d.get("heal", 0.0), 100.0)
		say("Used " + Items.name_of(item).to_lower())
		return true
	var h: float = d.get("hunger", 0.0)
	var t: float = d.get("thirst", 0.0)
	if (h <= 0.0 or hunger > 97.0) and (t <= 0.0 or thirst > 97.0):
		say("Not hungry" if h > t else "Not thirsty")
		return false
	hunger = clampf(hunger + h, 0.0, 100.0)
	thirst = clampf(thirst + t, 0.0, 100.0)
	if randf() < d.get("poison", 0.0):
		poison_t = 90.0
		say("That tasted wrong... you feel sick")
	else:
		say(("Drank " if t > h else "Ate ") + Items.name_of(item).to_lower())
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
			say("I'm bleeding!")
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
	var best := INF
	var best_pile: LootSpot = null
	for n in get_tree().get_nodes_in_group("loot"):
		var l := n as LootSpot
		if l.is_queued_for_deletion():
			continue
		if not l.is_bag and l.kind != "carcass" and l.kind != "chest" and l.opened and l.contents.is_empty():
			continue # already searched
		var d := l.global_position.distance_to(global_position)
		# Closest relative to its reach, so a big car doesn't beat a box right next to you.
		if d < l.reach and d / l.reach < best:
			best = d / l.reach
			nearest_loot = l
		if (l.is_bag or l.kind == "chest") and d < l.reach and (best_pile == null or d < best_pile.global_position.distance_to(global_position)):
			best_pile = l
	# The inventory's nearby list shows what's lying on the ground (searching a container drops its loot there).
	inv.near = best_pile
	nearest_tap = null
	var best_t := 46.0
	for n in get_tree().get_nodes_in_group("taps"):
		var t := n as WaterSource
		var d := t.global_position.distance_to(global_position)
		if d < best_t:
			best_t = d
			nearest_tap = t
	near_lake = world != null and world.water_near(global_position)
	nearest_structure = null
	var best_s := 44.0
	for n in get_tree().get_nodes_in_group("structures"):
		var st := n as Structure
		if st.kind == "chest":
			continue # chests are opened like loot
		var d := st.global_position.distance_to(global_position)
		if d < best_s:
			best_s = d
			nearest_structure = st
	near_tree = Vector2i(-1, -1)
	if world != null:
		var c := world.cell_of(global_position)
		for o in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, -1), Vector2i(-1, -1), Vector2i(0, 0)]:
			if world.get_tile(c + o) == World.TREE:
				near_tree = c + o
				break
	nearest_fire = null
	var best_f := 56.0
	for n in get_tree().get_nodes_in_group("fires"):
		var f := n as Campfire
		var d := f.global_position.distance_to(global_position)
		if d < best_f:
			best_f = d
			nearest_fire = f


# ---------------------------------------------------------------- visuals

const SKIN := Color("e6c2b0")
const HAIR_DARK := Color("452c34")
const HAIR_LIGHT := Color("704f48")


func _cloth_color(slot: String) -> Variant:
	return cloth_color(inv.gear, slot)


static func cloth_color(gear: Dictionary, slot: String) -> Variant:
	var g = gear.get(slot)
	if g == null:
		return null
	return Color(g.get("color", Items.ICON_DEFAULTS.get(g["id"], "7a7a80")))


## Recolours the character to match what's worn: shirt in the middle, coat as the jacket/sleeves,
## head items over the hair. (Pants/boots are too small on the sprite to show.)
func update_outfit() -> void:
	if _sprite == null:
		return
	paint_outfit(_sprite.material as ShaderMaterial, inv.gear)
	if _pack:
		_pack.queue_redraw()


## Sets the outfit shader colours from worn clothing (player and bandits).
static func paint_outfit(mat: ShaderMaterial, gear: Dictionary) -> void:
	var shirt = cloth_color(gear, "shirt")
	var coat = cloth_color(gear, "coat")
	var inner: Color = shirt if shirt != null else (coat if coat != null else SKIN)
	var outer: Color = coat if coat != null else (shirt if shirt != null else SKIN)
	mat.set_shader_parameter("shirt_col", inner)
	mat.set_shader_parameter("coat_col", outer.darkened(0.12) if coat != null else outer)
	mat.set_shader_parameter("coat_hi", outer.lightened(0.25))
	mat.set_shader_parameter("zip_col", Color("9eafad") if coat != null else inner.lightened(0.15))
	var hat = cloth_color(gear, "head")
	mat.set_shader_parameter("hair_dark", hat.darkened(0.2) if hat != null else HAIR_DARK)
	mat.set_shader_parameter("hair_light", hat.lightened(0.1) if hat != null else HAIR_LIGHT)


## Backpack on the character's back (drawn over the body when facing away / sideways).
func _draw_pack() -> void:
	var col = _cloth_color("back")
	if col == null or dead:
		return
	var d := Game.dir_name(facing)
	var c: Color = col
	var r: Rect2
	match d:
		"up":
			r = Rect2(-7, -15, 14, 12)
		"side":
			r = Rect2(-11, -15, 6, 11)
		"side-left":
			r = Rect2(5, -15, 6, 11)
		_:
			return # facing the camera: only the straps would show
	_pack.draw_rect(r.grow(1), Color("1a1016"))
	_pack.draw_rect(r, c)
	_pack.draw_rect(Rect2(r.position.x, r.position.y + r.size.y * 0.45, r.size.x, 2), c.darkened(0.3))

func _animate() -> void:
	facing = _melee_dir if (weapon()["melee"] and _swing_t > -0.15) else aim
	var d := Game.dir_name(facing)
	var anim := ("run_" if _moving else "idle_") + d
	if _swing_t > -0.05 and weapon_id() == "fists":
		anim = "punch_" + d
	if _pack:
		_pack.z_index = 0
		_pack.queue_redraw()
	if _sprite.animation != anim:
		var keep := _sprite.animation.begins_with("run") and anim.begins_with("run")
		var f := _sprite.frame
		_sprite.play(anim)
		if keep:
			_sprite.frame = f
	_sprite.modulate = Color(1, 0.55, 0.55) if _hurt_t > 0.0 else Color.WHITE
	# Slower legs to match the slower walking speed
	_sprite.speed_scale = (0.95 if _sprinting else 0.7) if anim.begins_with("run") else 1.0

	# Held weapon sprite in front of the body.
	var held: String = weapon()["held"]
	_held.visible = held != ""
	if not _held.visible:
		return
	_held.texture = Items.icon_of(held)
	var hm := maxf(_held.texture.get_width(), _held.texture.get_height())
	_held.scale = Vector2.ONE * (2.0 if hm <= 18.0 else 0.85)
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
	if placing != "" and not dead:
		var cell := build_cell()
		var ok := build_problem(cell) == ""
		var r := Rect2(to_local(Vector2(cell * World.T)), Vector2(World.T, World.T))
		draw_rect(r, Color(0.4, 0.95, 0.4, 0.28) if ok else Color(0.95, 0.35, 0.3, 0.28))
		draw_rect(r, Color(0.4, 0.95, 0.4, 0.8) if ok else Color(0.95, 0.35, 0.3, 0.8), false, 2.0)
	draw_set_transform(Vector2(0, 1), 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, RADIUS, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO)
	if dead:
		return
	if _swing_t > 0.0:
		var r: float = weapon()["range"] - 6.0
		draw_arc(HAND, r, _melee_dir.angle() - 1.0, _melee_dir.angle() + 1.0, 12, Color(1, 1, 1, 0.4), 2.0)
	_draw_aim_cone()
	if _shot_t > 0.0:
		var muzzle := HAND + aim * 24.0
		for end in _shots:
			draw_line(muzzle, to_local(end), Color(1, 0.9, 0.5, 0.85), 1.5)
		draw_circle(muzzle, 4.0, Color(1, 0.85, 0.4))


## The aim cone: where the next shot can land. Red = wide, green = steady.
func _draw_aim_cone() -> void:
	var w := weapon()
	if w["melee"] or Game.ui_open:
		return
	var steady := aim_steadiness()
	var col := Color(0.95, 0.35, 0.3).lerp(Color(0.45, 0.95, 0.45), steady)
	var length := 170.0
	if aim_target:
		length = clampf(aim_target.global_position.distance_to(global_position) + 10.0, 40.0, 320.0)
	var start := HAND + aim * 14.0
	var a := aim.rotated(-aim_spread) * length
	var b := aim.rotated(aim_spread) * length
	var fill := col
	fill.a = 0.12
	draw_colored_polygon(PackedVector2Array([start, start + a, start + b]), fill)
	var edge := col
	edge.a = 0.55
	draw_line(start, start + a, edge, 1.0)
	draw_line(start, start + b, edge, 1.0)
	if aim_target:
		var tp := to_local(aim_target.global_position + Vector2(0, -8))
		var r := 10.0 + aim_spread * 20.0
		for k in 4:
			var ang := PI * 0.25 + k * PI * 0.5
			draw_arc(tp, r, ang - 0.35, ang + 0.35, 4, col, 2.0)
