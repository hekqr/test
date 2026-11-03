class_name LootSpot
extends Node2D
## A searchable container inside buildings, or a bag of dropped items.

const KINDS := ["loot_box_1", "loot_box_2", "loot_trash_1", "loot_trash_2"]

var looted := false
var is_bag := false
var contents: Array = [] # item stacks
var kind := 0
var _sprite: Sprite2D


func _ready() -> void:
	add_to_group("loot")
	if is_bag:
		if contents.is_empty():
			var r := Items.roll_loot()
			contents = [r[0]] if not r.is_empty() else [Items.make("food")]
	else:
		kind = randi() % KINDS.size()
		if contents.is_empty():
			contents = Items.roll_loot()
	if is_bag:
		# Items on the ground show their own icon.
		_sprite = Sprite2D.new()
		_sprite.texture = Items.icon(contents[0]["id"]) if not contents.is_empty() else Game.tex("loot_box_1")
		_sprite.scale = Vector2(1.5, 1.5)
		_sprite.rotation = randf_range(-0.4, 0.4)
	else:
		_sprite = Game.make_sprite(KINDS[kind])
		_sprite.offset = Vector2(0, -_sprite.texture.get_height() / 2.0 + 3.0)
	add_child(_sprite)


func label() -> String:
	if is_bag and not contents.is_empty():
		var it: Dictionary = contents[0]
		var n := Items.name_of(it["id"])
		if contents.size() > 1:
			n += " +%d" % (contents.size() - 1)
		elif int(it["count"]) > 1:
			n += " x%d" % it["count"]
		return "Pick up " + n
	return "Search"


## Moves everything that fits into the player's inventory.
func search(p: Player) -> String:
	if looted:
		return "Already searched"
	var found := PackedStringArray()
	var left := []
	for it in contents:
		var before: int = it["count"]
		var rest := p.inv.pickup(it)
		var took := before - rest
		if took > 0:
			found.append(Items.name_of(it["id"]) + ("" if took == 1 else " x%d" % took))
		if rest > 0:
			var r: Dictionary = it.duplicate()
			r["count"] = rest
			left.append(r)
	var had_items := not contents.is_empty()
	contents = left
	if contents.is_empty():
		looted = true
		if is_bag:
			queue_free()
	queue_redraw()
	var verb := "Picked up: " if is_bag else "Found: "
	var msg := "Nothing useful here" if not had_items else (verb + ", ".join(found) if not found.is_empty() else "")
	if not left.is_empty():
		msg = (msg + "  -  " if msg != "" else "") + "No room in pockets!"
	return msg


func _draw() -> void:
	draw_set_transform(Vector2(0, 5), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 12.0, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO)
	if _sprite:
		_sprite.modulate = Color(0.45, 0.42, 0.45) if looted else Color.WHITE
	if not looted and not is_bag:
		# small glint so searchable containers stand out
		var t := Time.get_ticks_msec() / 400.0 + position.x
		if fmod(t, 6.0) < 0.6:
			draw_circle(Vector2(6, -16), 2.0, Color(1, 0.95, 0.6, 0.9))


func _process(_delta: float) -> void:
	if not looted:
		queue_redraw()
