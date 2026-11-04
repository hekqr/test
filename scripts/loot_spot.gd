class_name LootSpot
extends Node2D
## Something you can search: furniture (fridge, wardrobe, locker...), a car, a garbage bin,
## or a pile of items on the ground. Containers keep whatever you put in them.
## Ground piles disappear when empty.

var kind := "box" # key in Loot.CONTAINERS, or "pile" for items on the ground
var is_bag := false # true = items lying on the ground
var contents: Array = [] # item stacks
var opened := false # has the player looked inside
var loaded := false # restored from a save: don't roll new contents
var tex_name := "" # sprite override (cars, bins)
var flip := false
var reach := 44.0 # how close the player must be
var animal := "" # for carcasses: "rabbit" / "deer"
var _sprite: Sprite2D


## A container counts as "looted" once it's empty.
var looted: bool:
	get:
		return contents.is_empty() and not is_bag


func _ready() -> void:
	add_to_group("loot")
	if is_bag:
		kind = "pile"
	if not loaded:
		if is_bag:
			if contents.is_empty():
				contents = Loot.roll("floor")
				if contents.is_empty():
					contents = [Items.make("food")]
		elif contents.is_empty():
			contents = Loot.roll(kind)
	_sprite = Sprite2D.new()
	if kind == "carcass":
		# A dead animal lying on its side
		_sprite.texture = Game.pixel_icon(animal + "_1")
		_sprite.scale = Vector2(2, 2)
		_sprite.rotation = PI * 0.5 * (-1.0 if flip else 1.0)
		_sprite.modulate = Color(0.85, 0.7, 0.7)
	elif is_bag:
		_sprite.scale = Vector2(1.5, 1.5)
		_sprite.rotation = randf_range(-0.4, 0.4)
	else:
		var spec := tex_name if tex_name != "" else String(Loot.CONTAINERS[kind]["sprite"])
		if spec != "":
			_sprite.texture = Items.icon_of(spec if spec.begins_with("px:") else spec)
			_sprite.scale = Vector2(2, 2)
			_sprite.flip_h = flip
			# Stand on the bottom of the tile.
			_sprite.offset = Vector2(0, 7.5 - _sprite.texture.get_height() / 2.0)
	add_child(_sprite)
	refresh()


## Call after contents change.
func refresh() -> void:
	if kind == "carcass" and contents.is_empty():
		remove_from_group("loot")
		queue_free()
		return
	if is_bag:
		if contents.is_empty():
			remove_from_group("loot")
			queue_free()
			return
		# Items on the ground show the icon of the first item.
		if _sprite:
			_sprite.texture = Items.item_icon(contents[0])
			# Same size on the ground whether it's a small pack icon or a bigger drawn one
			var m := maxf(_sprite.texture.get_width(), _sprite.texture.get_height())
			_sprite.scale = Vector2.ONE * clampf(22.0 / m, 0.6, 1.5)
	queue_redraw()


func title() -> String:
	return "Ground" if is_bag else Loot.title(kind)


func to_save() -> Dictionary:
	return {"pos": [position.x, position.y], "bag": is_bag, "kind": kind, "opened": opened,
		"contents": contents, "tex": tex_name, "flip": flip, "reach": reach, "animal": animal}


static func from_save(d: Dictionary) -> LootSpot:
	var l := LootSpot.new()
	l.loaded = true
	l.position = SaveGame.vec(d["pos"])
	l.is_bag = d["bag"]
	l.kind = String(d["kind"])
	l.opened = d.get("opened", false)
	l.tex_name = d.get("tex", "")
	l.flip = d.get("flip", false)
	l.reach = d.get("reach", 44.0)
	l.animal = d.get("animal", "")
	for it in d["contents"]:
		l.contents.append(SaveGame.fix_item(it))
	return l


func label() -> String:
	if kind == "carcass":
		return "Skin " + animal
	if is_bag and not contents.is_empty():
		var it: Dictionary = contents[0]
		var n := Items.display_name(it)
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
			found.append(Items.display_name(it) + ("" if took == 1 else " x%d" % took))
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
	if kind == "carcass":
		draw_set_transform(Vector2(0, 4), 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, 16.0 if animal == "deer" else 9.0, Color(0.45, 0.05, 0.08, 0.7))
		draw_set_transform(Vector2.ZERO)
		return
	if is_bag:
		draw_set_transform(Vector2(0, 5), 0.0, Vector2(1.0, 0.4))
		draw_circle(Vector2.ZERO, 10.0, Color(0, 0, 0, 0.3))
		draw_set_transform(Vector2.ZERO)
		return
	if _sprite and _sprite.texture:
		_sprite.modulate = Color(0.6, 0.56, 0.6) if (opened and contents.is_empty()) else Color.WHITE
	if not opened:
		# small glint so unsearched containers stand out
		var t := Time.get_ticks_msec() / 400.0 + position.x
		if fmod(t, 6.0) < 0.6:
			draw_circle(Vector2(6, -16), 2.0, Color(1, 0.95, 0.6, 0.9))


func _process(_delta: float) -> void:
	if not opened:
		queue_redraw()
