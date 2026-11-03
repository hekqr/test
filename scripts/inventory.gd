class_name Inventory
extends RefCounted
## Gear-slot inventory.
##
## - Gear slots: head, armour, coat, shirt, pants, boots, back, hands, primary, secondary, melee.
## - Clothing and backpacks give storage slots ("cargo"). Each slot holds one item or one stack.
##   A piece of clothing keeps its contents when taken off / dropped.
## - Hands is just one extra slot that can hold anything.
## - "Big" items (weapons, clothing) only fit in a backpack, the Hands slot, or their own gear slot.
## - Stackable items merge into existing stacks automatically.
## - The active weapon (1/2/3) stays in its gear slot; "" = fists.
##
## Locations: {"t": "gear", "s": slot} | {"t": "cargo", "s": owner_slot, "i": index} | {"t": "near", "i": index}

signal changed

const GEAR := ["head", "armour", "coat", "shirt", "pants", "boots", "back", "hands", "primary", "secondary", "melee"]
const STORAGE := ["coat", "shirt", "pants", "armour", "back"] # clothing whose cargo is shown, in order
const WEAPON_SLOTS := ["primary", "secondary", "melee"]

var gear := {}
var active := "" # "", "primary", "secondary" or "melee"
var near: LootSpot = null # container / ground pile next to the player


func _init() -> void:
	for s in GEAR:
		gear[s] = null


# ---------------------------------------------------------------- locations

static func gear_loc(slot: String) -> Dictionary:
	return {"t": "gear", "s": slot}


static func cargo_loc(owner: String, i: int) -> Dictionary:
	return {"t": "cargo", "s": owner, "i": i}


static func near_loc(i: int) -> Dictionary:
	return {"t": "near", "i": i}


func get_at(loc: Dictionary) -> Variant:
	match loc["t"]:
		"gear":
			return gear[loc["s"]]
		"cargo":
			var owner = gear[loc["s"]]
			if owner == null or loc["i"] >= owner["cargo"].size():
				return null
			return owner["cargo"][loc["i"]]
		"near":
			if near == null or loc["i"] >= near.contents.size():
				return null
			return near.contents[loc["i"]]
	return null


func _set_at(loc: Dictionary, item) -> void:
	match loc["t"]:
		"gear":
			gear[loc["s"]] = item
		"cargo":
			gear[loc["s"]]["cargo"][loc["i"]] = item
		"near":
			var i: int = loc["i"]
			if item == null:
				if i < near.contents.size():
					near.contents.remove_at(i)
			elif i < near.contents.size():
				near.contents[i] = item
			else:
				near.contents.append(item)
			near.refresh()


## Every storage cell, in display order.
func storage_cells() -> Array:
	var out := []
	for s in STORAGE:
		var owner = gear[s]
		if owner != null:
			for i in owner["cargo"].size():
				out.append(cargo_loc(s, i))
	return out


func free_slots() -> int:
	var n := 0
	for loc in storage_cells():
		if get_at(loc) == null:
			n += 1
	return n


## "" if the item may go at loc, otherwise the reason it can't.
func can_place(item: Dictionary, loc: Dictionary) -> String:
	var id: String = item["id"]
	match loc["t"]:
		"gear":
			var slot: String = loc["s"]
			if slot != "hands" and Items.equip_of(id) != slot:
				return "That doesn't go there"
		"cargo":
			var owner = gear[loc["s"]]
			if owner == null or loc["i"] >= owner["cargo"].size():
				return "No slot there"
			if is_same(owner, item):
				return "Can't put it inside itself"
			if Items.is_big(id) and loc["s"] != "back":
				return "Too big - only fits in a backpack or hands"
			if Items.equip_of(id) == "back":
				return "Can't put a backpack in a backpack"
		"near":
			if near == null:
				return "Nothing nearby"
	return ""


## Drag & drop: move, merge stacks, or swap. Returns "" or the reason it failed.
func move(from: Dictionary, to: Dictionary) -> String:
	var item = get_at(from)
	if item == null or from == to:
		return ""
	if from["t"] == "near" and to["t"] == "near":
		return ""
	var target = get_at(to)
	var err := can_place(item, to)
	if err != "":
		return err
	var stack := Items.max_stack(item["id"])
	if target != null and target["id"] == item["id"] and stack > 1:
		var n := mini(stack - int(target["count"]), int(item["count"]))
		target["count"] += n
		item["count"] -= n
		if item["count"] <= 0:
			_set_at(from, null)
	elif target == null:
		_set_at(from, null)
		_set_at(to, item)
	else:
		if can_place(target, from) != "":
			return "No room to swap"
		_set_at(to, item)
		_set_at(from, target)
	_after_change()
	return ""


## Right-click: wear / equip the item in its gear slot (swapping out what's there).
func equip(from: Dictionary) -> String:
	var item = get_at(from)
	if item == null:
		return ""
	var slot := Items.equip_of(item["id"])
	if slot == "":
		return "You can't wear that"
	if from["t"] == "gear" and from["s"] == slot:
		return ""
	return move(from, gear_loc(slot))


func take(loc: Dictionary) -> Variant:
	var item = get_at(loc)
	if item != null:
		_set_at(loc, null)
		_after_change()
	return item


func _after_change() -> void:
	if active != "" and gear[active] == null:
		active = ""
	changed.emit()


# ---------------------------------------------------------------- adding / removing

func _holders() -> Array:
	return storage_cells() + [gear_loc("hands")]


## Adds an item to storage (merging stacks first). Returns how many could NOT fit.
func add_stack(item: Dictionary) -> int:
	var id: String = item["id"]
	var count: int = item["count"]
	var max_stack := Items.max_stack(id)
	if max_stack > 1:
		for loc in _holders():
			var s = get_at(loc)
			if s != null and s["id"] == id and int(s["count"]) < max_stack:
				var n := mini(max_stack - int(s["count"]), count)
				s["count"] += n
				count -= n
				if count == 0:
					break
	if count > 0:
		for loc in storage_cells():
			if get_at(loc) == null and can_place(item, loc) == "":
				var s: Dictionary = item.duplicate(true)
				s["count"] = mini(max_stack, count)
				count -= int(s["count"])
				_set_at(loc, s)
				if count == 0:
					break
	_after_change()
	return count


func add(id: String, count := 1) -> int:
	return add_stack(Items.make(id, count))


## Picking up: into its empty gear slot, else storage, else free hands. Returns leftover count.
func pickup(item: Dictionary) -> int:
	var slot := Items.equip_of(item["id"])
	if slot != "" and gear[slot] == null:
		gear[slot] = item.duplicate(true)
		_after_change()
		return 0
	var left := add_stack(item)
	if left > 0 and gear["hands"] == null:
		var h: Dictionary = item.duplicate(true)
		h["count"] = left
		gear["hands"] = h
		left = 0
		_after_change()
	return left


func count_of(id: String) -> int:
	var n := 0
	for loc in _holders():
		var s = get_at(loc)
		if s != null and s["id"] == id:
			n += int(s["count"])
	return n


## Removes up to `count` from storage / hands. Returns how many were removed.
func remove(id: String, count := 1) -> int:
	var removed := 0
	var holders := _holders()
	holders.reverse()
	for loc in holders:
		var s = get_at(loc)
		if s == null or s["id"] != id:
			continue
		var n := mini(int(s["count"]), count - removed)
		s["count"] -= n
		removed += n
		if s["count"] <= 0:
			_set_at(loc, null)
		if removed >= count:
			break
	_after_change()
	return removed


# ---------------------------------------------------------------- weapons / armour

## 1/2/3: select that weapon; selecting the active one again = fists.
func switch_to(slot: String) -> String:
	if active == slot:
		active = ""
		return ""
	if gear[slot] == null:
		return "No %s weapon" % ("main" if slot == "primary" else slot)
	active = slot
	return ""


func weapon_item() -> Variant:
	return gear[active] if active != "" else null


## Total damage protection from worn gear that isn't ruined.
func protection() -> float:
	var p := 0.0
	for s in ["head", "armour", "coat"]:
		var g = gear[s]
		if g != null and float(g.get("cond", 100.0)) > 0.0:
			p += float(Items.DEFS[g["id"]].get("protect", 0.0))
	return p


## Armour pieces lose condition when they absorb a hit.
func wear_armour(amount: float) -> void:
	for s in ["head", "armour"]:
		var g = gear[s]
		if g != null and Items.DEFS[g["id"]].get("protect", 0.0) > 0.0:
			g["cond"] = maxf(float(g["cond"]) - amount, 0.0)


func to_save() -> Dictionary:
	return {"gear": gear, "active": active}


func load_save(d: Dictionary) -> void:
	for s in GEAR:
		gear[s] = SaveGame.fix_item(d["gear"].get(s))
	active = d.get("active", "")
	_after_change()
