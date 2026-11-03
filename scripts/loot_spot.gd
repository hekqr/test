class_name LootSpot
extends Node2D
## A container inside a building (open it to see its contents), or a pile of items on the ground.
## Containers keep whatever you put in them. Ground piles disappear when empty.

const KINDS := ["loot_box_1", "loot_box_2", "loot_trash_1", "loot_trash_2"]
const NAMES := ["Cardboard box", "Cardboard box", "Trash can", "Trash can"]

var is_bag := false # true = items lying on the ground
var contents: Array = [] # item stacks
var kind := 0
var opened := false # has the player looked inside (containers)
var loaded := false # restored from a save: don't roll new contents
var _sprite: Sprite2D


## Kept for older saves / tests: a container counts as "looted" once it's empty.
var looted: bool:
	get:
		return contents.is_empty() and not is_bag


func _ready() -> void:
	add_to_group("loot")
	if loaded:
		pass
	elif is_bag:
		if contents.is_empty():
			var r := Items.roll_loot()
			contents = [r[0]] if not r.is_empty() else [Items.make("food")]
	else:
		kind = randi() % KINDS.size()
		if contents.is_empty():
			contents = Items.roll_loot()
	if is_bag:
		_sprite = Sprite2D.new()
		_sprite.scale = Vector2(1.5, 1.5)
		_sprite.rotation = randf_range(-0.4, 0.4)
	else:
		_sprite = Game.make_sprite(KINDS[kind])
		_sprite.offset = Vector2(0, -_sprite.texture.get_height() / 2.0 + 3.0)
	add_child(_sprite)
	refresh()


## Call after contents change.
func refresh() -> void:
	if is_bag:
		if contents.is_empty():
			remove_from_group("loot")
			queue_free()
			return
		# Items on the ground show the icon of the first item.
		if _sprite:
			_sprite.texture = Items.icon(contents[0]["id"])
	queue_redraw()


func title() -> String:
	return "Ground" if is_bag else NAMES[kind]


func to_save() -> Dictionary:
	return {"pos": [position.x, position.y], "bag": is_bag, "kind": kind, "opened": opened, "contents": contents}


static func from_save(d: Dictionary) -> LootSpot:
	var l := LootSpot.new()
	l.loaded = true
	l.position = SaveGame.vec(d["pos"])
	l.is_bag = d["bag"]
	l.kind = int(d["kind"])
	l.opened = d.get("opened", d.get("looted", false))
	for it in d["contents"]:
		l.contents.append(SaveGame.fix_item(it))
	return l


func label() -> String:
	if is_bag and not contents.is_empty():
		var it: Dictionary = contents[0]
		var n := Items.name_of(it["id"])
		if contents.size() > 1:
			n += " +%d" % (contents.size() - 1)
		elif int(it["count"]) > 1:
			n += " x%d" % it["count"]
		return "Pick up " + n
	return "Search " + title().to_lower()


## Takes everything that fits (Take all / picking up a ground pile).
func search(p: Player) -> String:
	opened = true
	var found := PackedStringArray()
	var left := []
	for it in contents:
		var before: int = it["count"]
		var rest := p.inv.pickup(it)
		var took := before - rest
		if took > 0:
			found.append(Items.name_of(it["id"]) + ("" if took == 1 else " x%d" % took))
		if rest > 0:
			var r: Dictionary = it.duplicate(true)
			r["count"] = rest
			left.append(r)
	var had_items := not contents.is_empty()
	contents = left
	refresh()
	var verb := "Picked up: " if is_bag else "Took: "
	var msg := "Nothing here" if not had_items else (verb + ", ".join(found) if not found.is_empty() else "")
	if not left.is_empty():
		msg = (msg + "  -  " if msg != "" else "") + "No free slots!"
	return msg


func _draw() -> void:
	draw_set_transform(Vector2(0, 5), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 12.0, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO)
	if _sprite and not is_bag:
		_sprite.modulate = Color(0.45, 0.42, 0.45) if (opened and contents.is_empty()) else Color.WHITE
	if not opened and not is_bag:
		# small glint so unsearched containers stand out
		var t := Time.get_ticks_msec() / 400.0 + position.x
		if fmod(t, 6.0) < 0.6:
			draw_circle(Vector2(6, -16), 2.0, Color(1, 0.95, 0.6, 0.9))


func _process(_delta: float) -> void:
	if not opened:
		queue_redraw()
