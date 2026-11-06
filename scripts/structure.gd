class_name Structure
extends Node2D
## Something you built at your base.
## - Walls block everything (people, zombies, bullets, sight). Gates open for people, not zombies.
## - Chests, shelves and weapon racks store items (Q opens them). Racks only take weapons and ammo.
## - Beds: sleep through the night. Near a bed is your base: zombies don't spawn there and see you
##   worse.
## - Garden beds: plant tomato seeds or a potato; harvest when ripe.
## - Workbench: Q opens crafting; the bigger kits (stove, shelves, rack, rain collector) are made at
##   one, and you can repair things there with scrap metal / rags instead of a repair kit.
## - Stove: a fire that never goes out (warmth + cooking, indoors too).
## - Rain collector: fills up while it rains (half as fast in snow); drink or fill gourds from it.
## - Snare (on grass): catches a rabbit now and then. Fish trap (in water by the shore): catches fish.

const KINDS := {
	"wall": {"name": "Wooden wall", "refund": {"planks": 2, "nails": 2}},
	"gate": {"name": "Wooden gate", "refund": {"planks": 2, "nails": 3, "rope": 1}},
	"chest": {"name": "Chest", "refund": {"planks": 2, "nails": 2}},
	"bed": {"name": "Bed", "refund": {"planks": 2, "rags": 2}},
	"garden": {"name": "Garden bed", "refund": {"planks": 1, "nails": 1}},
	"workbench": {"name": "Workbench", "refund": {"planks": 3, "nails": 3}},
	"stove": {"name": "Stove", "refund": {"scrap_metal": 2, "nails": 2}},
	"shelf": {"name": "Shelves", "refund": {"planks": 2, "nails": 2}},
	"rack": {"name": "Weapon rack", "refund": {"planks": 2, "nails": 1}},
	"collector": {"name": "Rain collector", "refund": {"planks": 2, "nails": 2}},
	"snare": {"name": "Snare", "refund": {"rope": 1}},
	"fishtrap": {"name": "Fish trap", "refund": {"sticks": 2, "rope": 1}},
}
## Storage you build -> its LootSpot kind.
const STORAGE := {"chest": "chest", "shelf": "store_shelf", "rack": "store_rack"}
## Tomatoes: 1.5 days, 3 tomatoes + 2 seeds (3 x 12 hunger / 1.5 days = 24 / day).
## Potatoes: 3 days, 5 potatoes (5 x 18 / 3 = 30 / day): slower, but more food per day. Rain: 1.5x faster.
const CROPS := {
	"tomato": {"name": "Tomatoes", "days": 1.5, "seed": "tomato_seeds", "yield": [["tomato", 3], ["tomato_seeds", 2]]},
	"potato": {"name": "Potatoes", "days": 3.0, "seed": "potato", "yield": [["potato", 5]]},
}
const CHEST_SLOTS := 16
const COLLECTOR_CAP := 10 # drinks / gourd fills
const RAIN_PER_HOUR := 2.0 # water a rain collector gathers per in-game hour of rain (snow: half)
const AWAY_RAIN := 0.3 # share of the time it rains, for time that passed while you slept / were away
const SNARE_PER_DAY := 1.0 # rabbits a snare catches per day (on average)
const TRAP_PER_DAY := 1.5 # fish a fish trap catches per day (on average; rain 1.5x)
const TRAP_CAP := 3

var kind := "wall"
var cell := Vector2i.ZERO
var world: World
var crop := "" # garden: what's planted
var growth := 0.0 # 0..1 (1 = ripe)
var last_day := 0.0 # world_days when it was last updated
var water := 0.0 # rain collector
var caught := 0 # snare (0 / 1) or fish trap (0..TRAP_CAP)
var progress := 0.0 # snare / fish trap: towards the next catch
var chest: LootSpot = null # chest / shelves / weapon rack storage
var door: Door = null
var fire: Campfire = null # stove
var _sprite: Sprite2D
var _crop_sprite: Sprite2D
var _overlay: Node2D
var _contents: Array = [] # storage contents when loading


func _ready() -> void:
	add_to_group("structures")
	position = world.center_of(cell)
	_sprite = Sprite2D.new()
	_sprite.scale = Vector2(2, 2)
	add_child(_sprite)
	if STORAGE.has(kind):
		chest = LootSpot.new()
		chest.kind = STORAGE[kind]
		chest.loaded = true
		chest.opened = true
		chest.reach = 44.0
		chest.contents = _contents
		chest.position = Vector2.ZERO
		add_child(chest)
		_sprite.visible = false # it draws itself
		return
	match kind:
		"wall":
			world.add_built(cell)
			_sprite.texture = Game.built_wall()
			_sprite.offset = Vector2(0, -4) # stands on its tile, 3/4 view
		"gate":
			door = Door.new()
			door.world = world
			door.cell = cell
			door.metal = false
			door.tex_closed = ""
			door.tex_open = ""
			world.add_gate(cell, door)
			_sprite.visible = false
		"bed":
			_sprite.texture = Game.furniture("camp_bed")
		"garden":
			_sprite.texture = Game.furniture("garden_bed")
			_crop_sprite = Sprite2D.new()
			_crop_sprite.scale = Vector2(2, 2)
			_crop_sprite.offset = Vector2(0, -4)
			add_child(_crop_sprite)
			_update_crop_sprite()
		"workbench":
			_sprite.texture = Game.furniture("workbench")
		"stove":
			_sprite.texture = Game.furniture("stove")
			fire = Campfire.new()
			fire.permanent = true
			add_child(fire)
		"collector", "snare", "fishtrap":
			_sprite.texture = Game.furniture({"collector": "rain_barrel", "snare": "snare", "fishtrap": "fish_trap"}[kind])
			_overlay = Node2D.new()
			_overlay.draw.connect(_draw_overlay)
			add_child(_overlay)


func title() -> String:
	return KINDS[kind]["name"]


## Removes it from the world (dismantling). Materials are handed back by the caller.
func remove() -> void:
	match kind:
		"wall":
			world.remove_built(cell)
		"gate":
			world.remove_gate(cell)
			if door:
				door.queue_free()
	if fire:
		fire.remove_from_group("fires")
	if chest:
		chest.remove_from_group("loot")
	remove_from_group("structures")
	queue_free()


## Moves it on to `now` (in world days): crops grow, rain collectors fill, snares and traps catch.
## Long gaps (you slept, or were in another region) use the usual share of rainy weather.
func tick(now: float, weather: String) -> void:
	var d := maxf(now - last_day, 0.0)
	if kind == "garden":
		grow(now, weather == "rain" and d < 0.05)
		return
	last_day = now
	if d <= 0.0:
		return
	var away := d >= 0.05
	var wet := AWAY_RAIN if away else (1.0 if weather == "rain" else (0.5 if weather == "snow" else 0.0))
	match kind:
		"collector":
			water = minf(water + d * 24.0 * RAIN_PER_HOUR * wet, COLLECTOR_CAP)
		"snare":
			if caught == 0:
				progress += d * SNARE_PER_DAY * randf_range(0.5, 1.5)
				if progress >= 1.0:
					caught = 1
					progress = 0.0
		"fishtrap":
			progress += d * TRAP_PER_DAY * (1.0 + 0.5 * (AWAY_RAIN if away else (1.0 if weather == "rain" else 0.0))) * randf_range(0.5, 1.5)
			while progress >= 1.0 and caught < TRAP_CAP:
				caught += 1
				progress -= 1.0
			if caught >= TRAP_CAP:
				progress = 0.0
	if _overlay:
		_overlay.queue_redraw()


## What's caught in a snare / fish trap (empties it).
func take_catch() -> Array:
	var out := []
	if caught > 0:
		out.append(Items.make("meat" if kind == "snare" else "fish", caught))
	caught = 0
	progress = 0.0
	if _overlay:
		_overlay.queue_redraw()
	return out


func water_units() -> int:
	return int(water + 0.001)


func _draw_overlay() -> void:
	match kind:
		"collector":
			# Water level in the open barrel
			var f := water / float(COLLECTOR_CAP)
			if f > 0.0:
				_overlay.draw_rect(Rect2(-8, -12, 16, 6), Color(0.25, 0.45, 0.6, 0.35 + 0.5 * f))
				_overlay.draw_rect(Rect2(-8, -12 + 6.0 * (1.0 - f), 16, 6.0 * f), Color("6aa8d8"))
		"snare":
			if caught > 0:
				var t := Game.pixel_icon("rabbit_1")
				_overlay.draw_set_transform(Vector2(0, -2), PI * 0.5, Vector2(1.6, 1.6))
				_overlay.draw_texture(t, -t.get_size() / 2.0, Color(0.85, 0.75, 0.75))
				_overlay.draw_set_transform(Vector2.ZERO)
		"fishtrap":
			for i in caught:
				var p := Vector2(-6 + i * 6, -1 + (i % 2) * 4)
				_overlay.draw_circle(p, 2.5, Color("1a1016"))
				_overlay.draw_circle(p, 1.7, Color("9ab8c8"))


# ---------------------------------------------------------------- crops

func plant(what: String, now: float) -> void:
	crop = what
	growth = 0.0
	last_day = now
	_update_crop_sprite()


## Moves the crop on to `now` (in world days). Rain makes it grow 1.5x as fast.
func grow(now: float, rain: bool) -> void:
	if crop == "":
		last_day = now
		return
	var d := maxf(now - last_day, 0.0)
	last_day = now
	growth = minf(growth + d / float(CROPS[crop]["days"]) * (1.5 if rain else 1.0), 1.0)
	_update_crop_sprite()


func ripe() -> bool:
	return crop != "" and growth >= 0.999 # (float sums like 2/3 + 1/3 can land a hair under 1)


## The harvest: what the plant gives. Clears the bed.
func harvest() -> Array:
	var out := []
	for y in CROPS[crop]["yield"]:
		out.append(Items.make(y[0], int(y[1])))
	crop = ""
	growth = 0.0
	_update_crop_sprite()
	return out


func _update_crop_sprite() -> void:
	if _crop_sprite == null:
		return
	_crop_sprite.visible = crop != ""
	if crop != "":
		_crop_sprite.texture = Game.crop(crop, 2 if ripe() else (1 if growth >= 0.4 else 0))


# ---------------------------------------------------------------- saving

func to_save() -> Dictionary:
	var d := {"kind": kind, "cell": [cell.x, cell.y]}
	if chest:
		d["contents"] = chest.contents
	if kind == "garden":
		d["crop"] = crop
		d["growth"] = growth
	if kind in ["garden", "collector", "snare", "fishtrap"]:
		d["last_day"] = last_day
	if kind == "collector":
		d["water"] = snappedf(water, 0.01)
	if kind in ["snare", "fishtrap"]:
		d["caught"] = caught
		d["progress"] = snappedf(progress, 0.001)
	return d


static func from_save(d: Dictionary, w: World) -> Structure:
	var s := Structure.new()
	s.world = w
	s.kind = String(d["kind"])
	s.cell = Vector2i(int(d["cell"][0]), int(d["cell"][1]))
	for it in d.get("contents", []):
		s._contents.append(SaveGame.fix_item(it))
	s.crop = String(d.get("crop", ""))
	s.growth = float(d.get("growth", 0.0))
	s.last_day = float(d.get("last_day", 0.0))
	s.water = float(d.get("water", 0.0))
	s.caught = int(d.get("caught", 0))
	s.progress = float(d.get("progress", 0.0))
	return s
