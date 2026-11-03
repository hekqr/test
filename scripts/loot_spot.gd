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
		kind = 1
	else:
		kind = randi() % KINDS.size()
		if contents.is_empty():
			contents = Items.roll_loot()
	_sprite = Game.make_sprite(KINDS[kind])
	_sprite.offset = Vector2(0, -_sprite.texture.get_height() / 2.0 + 3.0)
	if is_bag:
		_sprite.scale = Vector2(1.5, 1.5)
	add_child(_sprite)


## Moves everything that fits into the player's inventory.
func search(p: Player) -> String:
	if looted:
		return "Already searched"
	var found := PackedStringArray()
	var left := []
	for it in contents:
		var before: int = it["count"]
		var rest := p.inv.add_stack(it)
		if rest > 0 and p.inv.hands == null:
			# Doesn't fit in pockets: take it in hands if they're free.
			var h: Dictionary = it.duplicate()
			h["count"] = rest
			p.inv.hands = h
			rest = 0
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
	var msg := "Nothing useful here" if not had_items else ("Found: " + ", ".join(found) if not found.is_empty() else "")
	if not left.is_empty():
		msg = (msg + "  -  " if msg != "" else "") + "No room in pockets!"
	return msg


func _draw() -> void:
	draw_set_transform(Vector2(0, 5), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 12.0, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO)
	if _sprite:
		_sprite.modulate = Color(0.45, 0.42, 0.45) if looted else Color.WHITE
	if not looted:
		# small glint so searchable containers stand out
		var t := Time.get_ticks_msec() / 400.0 + position.x
		if fmod(t, 6.0) < 0.6:
			draw_circle(Vector2(6, -16), 2.0, Color(1, 0.95, 0.6, 0.9))


func _process(_delta: float) -> void:
	if not looted:
		queue_redraw()
