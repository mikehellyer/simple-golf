class_name Course
extends RefCounted
## A course: a name, a seed, a number of holes and any per-hole edits made in
## the course editor. Courses can be shared as a short text code: plain seeds
## as "SG-" plus the seed in base 36, edited courses as "SGX-" plus compressed
## JSON. Saved courses live in user://courses/.

const SAVE_DIR := "user://courses"
const MAX_HOLES := 18

var name := "Random course"
var base_seed := 0
## Hole number (1-based, as a string for JSON) -> overrides Dictionary.
var edits := {}


func _init(course_name := "Random course", seed_value := 0) -> void:
	name = course_name
	base_seed = seed_value


## The same course for everyone in the world on a given day.
static func daily(date := Time.get_date_dict_from_system(true)) -> Course:
	var key := "%04d-%02d-%02d" % [date.year, date.month, date.day]
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return Course.new("Course of the day (%d %s)" % [date.day, months[date.month - 1]],
			hash("simple-golf-" + key) & 0x7FFFFFFF)


func hole_seed(number: int) -> int:
	return base_seed * 31 + number * 7919


func hole_overrides(number: int) -> Dictionary:
	return edits.get(str(number), {})


func set_hole_overrides(number: int, overrides: Dictionary) -> void:
	if overrides.is_empty():
		edits.erase(str(number))
	else:
		edits[str(number)] = overrides


func make_hole(number: int) -> Hole:
	var overrides := hole_overrides(number)
	var layout := int(overrides.get("layout", 0))
	return Hole.new(number, hole_seed(number) + layout * 104729, overrides)


func to_dict() -> Dictionary:
	return {name = name, seed = base_seed, edits = edits}


static func from_dict(d: Dictionary) -> Course:
	var c := Course.new(str(d.get("name", "Course")), int(d.get("seed", 0)))
	var e = d.get("edits", {})
	if typeof(e) == TYPE_DICTIONARY:
		for k in e:
			if typeof(e[k]) == TYPE_DICTIONARY and str(k).to_int() >= 1 and str(k).to_int() <= MAX_HOLES:
				c.edits[str(k)] = _clean(e[k])
	return c


## Keeps only known override keys, clamped to their allowed ranges, so a
## course code from anywhere can't produce a broken hole.
static func _clean(overrides: Dictionary) -> Dictionary:
	var out := {}
	for key in overrides:
		if Hole.OVERRIDES.has(key) and typeof(overrides[key]) in [TYPE_INT, TYPE_FLOAT]:
			var spec: Array = Hole.OVERRIDES[key]
			out[key] = clampf(float(overrides[key]), spec[1], spec[2])
	return out


# --- Share codes -----------------------------------------------------------

func to_code() -> String:
	if edits.is_empty():
		return "SG-" + _to_base36(base_seed)
	var json := JSON.stringify(to_dict()).to_utf8_buffer()
	var packed := json.compress(FileAccess.COMPRESSION_DEFLATE)
	var header := PackedByteArray()
	header.resize(4)
	header.encode_u32(0, json.size())
	return "SGX-" + Marshalls.raw_to_base64(header + packed)


## Returns null if the code isn't valid.
static func from_code(code: String) -> Course:
	code = code.strip_edges().replace(" ", "")
	if code.to_upper().begins_with("SG-"):
		var s := _from_base36(code.substr(3))
		return Course.new("Course %s" % code.substr(3).to_upper(), s) if s >= 0 else null
	if code.begins_with("SGX-"):
		var raw := Marshalls.base64_to_raw(code.substr(4))
		if raw.size() < 5:
			return null
		var size := raw.decode_u32(0)
		if size > 1 << 20:
			return null
		var json := raw.slice(4).decompress(size, FileAccess.COMPRESSION_DEFLATE)
		var data = JSON.parse_string(json.get_string_from_utf8())
		return from_dict(data) if typeof(data) == TYPE_DICTIONARY else null
	return null


static func _to_base36(n: int) -> String:
	const DIGITS := "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	if n == 0:
		return "0"
	var out := ""
	while n > 0:
		out = DIGITS[n % 36] + out
		n /= 36
	return out


static func _from_base36(s: String) -> int:
	const DIGITS := "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	s = s.to_upper()
	if s.is_empty() or s.length() > 12:
		return -1
	var n := 0
	for ch in s:
		var d := DIGITS.find(ch)
		if d < 0:
			return -1
		n = n * 36 + d
	return n


# --- Saving ----------------------------------------------------------------

func save() -> Error:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var f := FileAccess.open("%s/%s.json" % [SAVE_DIR, _file_name(name)], FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict(), "\t"))
	return OK


static func load_saved(course_name: String) -> Course:
	var f := FileAccess.open("%s/%s.json" % [SAVE_DIR, _file_name(course_name)], FileAccess.READ)
	if f == null:
		return null
	var data = JSON.parse_string(f.get_as_text())
	return from_dict(data) if typeof(data) == TYPE_DICTIONARY else null


static func delete_saved(course_name: String) -> void:
	DirAccess.remove_absolute("%s/%s.json" % [SAVE_DIR, _file_name(course_name)])


static func list_saved() -> PackedStringArray:
	var names := PackedStringArray()
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return names
	for file in dir.get_files():
		if file.ends_with(".json"):
			var c := load_saved(file.get_basename())
			if c:
				names.append(c.name)
	names.sort()
	return names


static func _file_name(course_name: String) -> String:
	return course_name.strip_edges().validate_filename().to_lower().replace(" ", "-")
