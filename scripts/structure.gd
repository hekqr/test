class_name Structure
extends Node2D
## Something you built at your base: a wooden wall, a gate, a chest, a bed or a garden bed.
## - Walls block everything (people, zombies, bullets, sight).
## - Gates open for people and stay shut for zombies (they're doors).
## - Chests store items (Q opens them).
## - Beds: sleep through the night. Near a bed is your base: zombies don't spawn there and see you
##   worse.
## - Garden beds: plant tomato seeds or a potato; harvest when ripe.

const KINDS := {
	"wall": {"name": "Wooden wall", "refund": {"planks": 2, "nails": 2}},
	"gate": {"name": "Wooden gate", "refund": {"planks": 2, "nails": 3, "rope": 1}},
	"chest": {"name": "Chest", "refund": {"planks": 2, "nails": 2}},
	"bed": {"name": "Bed", "refund": {"planks": 2, "rags": 2}},
	"garden": {"name": "Garden bed", "refund": {"planks": 1, "nails": 1}},
}
## Tomatoes: 1.5 days, 3 tomatoes + 2 seeds (3 x 12 hunger / 1.5 days = 24 / day).
## Potatoes: 3 days, 5 potatoes (5 x 18 / 3 = 30 / day): slower, but more food per day. Rain: 1.5x faster.
const CROPS := {
	"tomato": {"name": "Tomatoes", "days": 1.5, "seed": "tomato_seeds", "yield": [["tomato", 3], ["tomato_seeds", 2]]},
	"potato": {"name": "Potatoes", "days": 3.0, "seed": "potato", "yield": [["potato", 5]]},
}
const CHEST_SLOTS := 16

var kind := "wall"
var cell := Vector2i.ZERO
var world: World
var crop := "" # garden: what's planted
var growth := 0.0 # 0..1 (1 = ripe)
var last_day := 0.0 # world_days when growth was last updated
var chest: LootSpot = null
var door: Door = null
var _sprite: Sprite2D
var _crop_sprite: Sprite2D
var _contents: Array = [] # chest contents when loading


func _ready() -> void:
	add_to_group("structures")
	position = world.center_of(cell)
	_sprite = Sprite2D.new()
	_sprite.scale = Vector2(2, 2)
	add_child(_sprite)
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
		"chest":
			_sprite.texture = Game.furniture("chest")
			chest = LootSpot.new()
			chest.kind = "chest"
			chest.loaded = true
			chest.opened = true
			chest.reach = 44.0
			chest.contents = _contents
			chest.position = Vector2.ZERO
			add_child(chest)
			_sprite.visible = false # the chest draws itself
		"bed":
			_sprite.texture = Game.furniture("camp_bed")
		"garden":
			_sprite.texture = Game.furniture("garden_bed")
			_crop_sprite = Sprite2D.new()
			_crop_sprite.scale = Vector2(2, 2)
			_crop_sprite.offset = Vector2(0, -4)
			add_child(_crop_sprite)
			_update_crop_sprite()


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
	remove_from_group("structures")
	queue_free()


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
	return crop != "" and growth >= 1.0


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
		_crop_sprite.texture = Game.crop(crop, 2 if growth >= 1.0 else (1 if growth >= 0.4 else 0))


# ---------------------------------------------------------------- saving

func to_save() -> Dictionary:
	var d := {"kind": kind, "cell": [cell.x, cell.y]}
	if kind == "chest" and chest:
		d["contents"] = chest.contents
	if kind == "garden":
		d["crop"] = crop
		d["growth"] = growth
		d["last_day"] = last_day
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
	return s
