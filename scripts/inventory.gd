class_name Inventory
extends RefCounted
## Slot-based inventory. The first HOTBAR slots are the quick-access bar.

signal changed

const SIZE := 18
const HOTBAR := 6

var slots: Array = [] # each entry: null or {"id": String, "count": int, ["mag": int]}


func _init() -> void:
	slots.resize(SIZE)


## Adds an item stack. Returns how many could NOT fit.
func add_stack(item: Dictionary) -> int:
	var id: String = item["id"]
	var count: int = item["count"]
	var max_stack: int = Items.DEFS[id]["stack"]
	if max_stack > 1:
		for s in slots:
			if s != null and s["id"] == id and s["count"] < max_stack:
				var n := mini(max_stack - int(s["count"]), count)
				s["count"] += n
				count -= n
				if count == 0:
					break
	for i in SIZE:
		if count == 0:
			break
		if slots[i] == null:
			var n := mini(max_stack, count)
			var s := item.duplicate()
			s["count"] = n
			slots[i] = s
			count -= n
	changed.emit()
	return count


func add(id: String, count := 1) -> int:
	return add_stack(Items.make(id, count))


func count_of(id: String) -> int:
	var n := 0
	for s in slots:
		if s != null and s["id"] == id:
			n += int(s["count"])
	return n


## Removes up to `count` of an item (from the back first). Returns how many were removed.
func remove(id: String, count := 1) -> int:
	var removed := 0
	for i in range(SIZE - 1, -1, -1):
		var s = slots[i]
		if s == null or s["id"] != id:
			continue
		var n := mini(int(s["count"]), count - removed)
		s["count"] -= n
		removed += n
		if s["count"] <= 0:
			slots[i] = null
		if removed >= count:
			break
	changed.emit()
	return removed


func contains(item: Dictionary) -> bool:
	for s in slots:
		if s != null and is_same(s, item):
			return true
	return false


## Drag & drop: merge stacks of the same item, otherwise swap.
func move(from: int, to: int) -> void:
	if from == to or slots[from] == null:
		return
	var a: Dictionary = slots[from]
	var b = slots[to]
	if b != null and b["id"] == a["id"] and int(Items.DEFS[a["id"]]["stack"]) > 1:
		var max_stack: int = Items.DEFS[a["id"]]["stack"]
		var n := mini(max_stack - int(b["count"]), int(a["count"]))
		b["count"] += n
		a["count"] -= n
		if a["count"] <= 0:
			slots[from] = null
	else:
		slots[from] = b
		slots[to] = a
	changed.emit()


func take(i: int) -> Variant:
	var s = slots[i]
	slots[i] = null
	changed.emit()
	return s
