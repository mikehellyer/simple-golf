class_name CourseMaps
extends RefCounted
## Real golf courses bundled with the game, as course files in res://courses/
## made by tools/import_osm_course.py from OpenStreetMap data.

const DIR := "res://courses"

static var _cache := {}


## Ids (file names without .json) of the bundled real courses.
static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".json"):
			out.append(f.get_basename())
	out.sort()
	return out


static func has(id: String) -> bool:
	return id != "" and FileAccess.file_exists("%s/%s.json" % [DIR, id])


static func data(id: String) -> Dictionary:
	if not _cache.has(id):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("%s/%s.json" % [DIR, id])) if has(id) else null
		_cache[id] = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	return _cache[id]


static func name_of(id: String) -> String:
	return str(data(id).get("name", id))


static func attribution(id: String) -> String:
	return str(data(id).get("attribution", ""))


static func hole_count(id: String) -> int:
	return data(id).get("holes", []).size()


## The mapped shapes of hole `number` (1-based), or {} if there's no such hole.
static func hole(id: String, number: int) -> Dictionary:
	for h in data(id).get("holes", []):
		if int(h.get("number", 0)) == number:
			return h
	return {}
