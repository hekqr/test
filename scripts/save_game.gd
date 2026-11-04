class_name SaveGame
## One automatic save file. When the survivor dies the file is kept but marked dead,
## so it can't be continued (a dev "revive" may be added later).

const VERSION := 3 # bumped when the world/item format changes; older saves cannot be continued


static func path() -> String:
	return Game.save_path


static func exists() -> bool:
	return FileAccess.file_exists(path())


static func read() -> Dictionary:
	if not exists():
		return {}
	var f := FileAccess.open(path(), FileAccess.READ)
	if f == null:
		return {}
	var data = JSON.parse_string(f.get_as_text())
	return data if data is Dictionary else {}


static func write(data: Dictionary) -> void:
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
	if d.has("cargo"):
		var c := []
		for x in d["cargo"]:
			c.append(fix_item(x))
		d["cargo"] = c
	return d


static func vec(a) -> Vector2:
	return Vector2(a[0], a[1])
