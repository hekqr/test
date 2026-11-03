class_name Inventory
extends RefCounted
## Hands + pockets.
## - Hands hold one item, or one stack of a stackable item. They don't use pocket space.
## - Pockets have limited SPACE. Every item (or stack) takes Items.size_of(id) space,
##   so a big item may not fit even when several small ones would.
## - Stackable items (Items.max_stack > 1) merge into existing stacks automatically.

signal changed

const CAPACITY := 12

var hands = null # null or {"id", "count", ["mag"]}
var pockets: Array = [] # list of item stacks


func space_used() -> int:
	var n := 0
	for s in pockets:
		n += Items.size_of(s["id"])
	return n


func space_free() -> int:
	return CAPACITY - space_used()


func fits(id: String) -> bool:
	return Items.size_of(id) <= space_free()


## Adds a stack to the pockets. Returns how many could NOT fit.
func add_stack(item: Dictionary) -> int:
	var id: String = item["id"]
	var count: int = item["count"]
	var max_stack := Items.max_stack(id)
	if max_stack > 1:
		for s in pockets + ([hands] if hands != null else []):
			if s["id"] == id and int(s["count"]) < max_stack:
				var n := mini(max_stack - int(s["count"]), count)
				s["count"] += n
				count -= n
				if count == 0:
					break
	while count > 0 and fits(id):
		var s := item.duplicate()
		s["count"] = mini(max_stack, count)
		count -= int(s["count"])
		pockets.append(s)
	changed.emit()
	return count


func add(id: String, count := 1) -> int:
	return add_stack(Items.make(id, count))


func count_of(id: String) -> int:
	var n := 0
	for s in pockets + ([hands] if hands != null else []):
		if s["id"] == id:
			n += int(s["count"])
	return n


## Removes up to `count` (pockets first, then hands). Returns how many were removed.
func remove(id: String, count := 1) -> int:
	var removed := 0
	for i in range(pockets.size() - 1, -1, -1):
		var s: Dictionary = pockets[i]
		if s["id"] != id:
			continue
		var n := mini(int(s["count"]), count - removed)
		s["count"] -= n
		removed += n
		if s["count"] <= 0:
			pockets.remove_at(i)
		if removed >= count:
			break
	if removed < count and hands != null and hands["id"] == id:
		var n := mini(int(hands["count"]), count - removed)
		hands["count"] -= n
		removed += n
		if hands["count"] <= 0:
			hands = null
	changed.emit()
	return removed


func in_hands(item) -> bool:
	return hands != null and item != null and is_same(hands, item)


## Moves pocket item i into the hands; whatever was in the hands goes back to the pockets.
## Returns "" on success, or a reason it failed.
func to_hands(i: int) -> String:
	var item: Dictionary = pockets[i]
	pockets.remove_at(i)
	if hands != null:
		if space_free() < Items.size_of(hands["id"]):
			pockets.insert(i, item)
			return "No room in pockets for the " + Items.name_of(hands["id"]).to_lower()
		pockets.append(hands)
	hands = item
	changed.emit()
	return ""


## Puts the hands item into the pockets. Returns "" on success, or a reason it failed.
func holster() -> String:
	if hands == null:
		return ""
	if not fits(hands["id"]):
		return "No room in pockets"
	var h: Dictionary = hands
	hands = null
	var left := add_stack(h)
	if left > 0: # only part of a stack fit
		h["count"] = left
		hands = h
	changed.emit()
	return ""


func take_pocket(i: int) -> Dictionary:
	var s: Dictionary = pockets[i]
	pockets.remove_at(i)
	changed.emit()
	return s


func take_hands() -> Variant:
	var s = hands
	hands = null
	changed.emit()
	return s
