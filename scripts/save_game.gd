class_name SaveGame
## Automatic saves, one file per slot (3 slots). When the survivor dies the file is kept but marked
## dead, so it can't be continued.

const SLOTS := 3


## Slot 1 keeps the old single-save file name, so existing saves show up in it.
static func slot_path(slot: int) -> String:
	return "user://save.json" if slot == 1 else "user://save_%d.json" % slot


static func read_slot(slot: int) -> Dictionary:
	return _read_file(slot_path(slot))


static func slot_can_continue(slot: int) -> bool:
	var d := read_slot(slot)
	return not d.is_empty() and not d.get("dead", false) and int(d.get("version", 0)) == VERSION


## Play in this slot from now on (saves go there).
static func use_slot(slot: int) -> void:
	Game.save_slot = slot
	Game.save_path = slot_path(slot)
	Game.save_settings()

const VERSION := 8 # bumped when the world/item format changes; older saves cannot be continued


static func path() -> String:
	return Game.save_path


static func exists() -> bool:
	return FileAccess.file_exists(path())


static func read() -> Dictionary:
	return _read_file(path())


static func _read_file(p: String) -> Dictionary:
	if not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {}
	var data = JSON.parse_string(f.get_as_text())
	return data if data is Dictionary else {}


## Writes the save. Safe to run on a worker thread (it only touches `data` and the file).
static func write(data: Dictionary) -> void:
	if data.has("explored_raw"):
		var raw: PackedByteArray = data["explored_raw"]
		data["explored"] = Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE))
		data.erase("explored_raw")
	data["version"] = VERSION
	data["saved_at"] = Time.get_datetime_string_from_system()
	var tmp := path() + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Could not write save: %s" % tmp)
		return
	f.store_string(JSON.stringify(data))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path()))


static func can_continue() -> bool:
	var d := read()
	return not d.is_empty() and not d.get("dead", false) and int(d.get("version", 0)) == VERSION


## JSON turns ints into floats; fix item stacks back up.
static func fix_item(it) -> Variant:
	if it == null:
		return null
	var d: Dictionary = it
	d["count"] = int(d["count"])
	if d.has("mag"):
		d["mag"] = int(d["mag"])
	if d.has("uses"):
		d["uses"] = int(d["uses"])
	if d.has("water"):
		d["water"] = int(d["water"])
	if d.has("cargo"):
		var c := []
		for x in d["cargo"]:
			c.append(fix_item(x))
		d["cargo"] = c
	return d


static func vec(a) -> Vector2:
	return Vector2(a[0], a[1])
