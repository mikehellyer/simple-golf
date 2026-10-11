class_name PlayerProfiles
extends RefCounted
## The club's members and their career statistics, saved on this computer.
##
## Stats are added hole by hole (so an abandoned round still counts the holes
## played) and a round summary is added to the member's history when a round
## finishes.

const DEFAULT_PATH := "user://members.json"
const HISTORY_LENGTH := 20

var path: String
## Each member: {id, name, colour, joined, stats, history}.
var members: Array[Dictionary] = []


func _init(file_path := DEFAULT_PATH) -> void:
	path = file_path
	load_file()


static func empty_stats() -> Dictionary:
	return {
		rounds = 0, holes = 0, strokes = 0, par = 0,
		hole_in_ones = 0, eagles = 0, birdies = 0, pars = 0, bogeys = 0, doubles = 0,
		fairways = 0, fairway_chances = 0, greens = 0, putts = 0,
		drives = 0, drive_total = 0.0, longest_drive = 0.0,
		best18 = {}, best9 = {},
		wins = 0, losses = 0, halves = 0, skins = 0,
	}


func find(id: String) -> Dictionary:
	for m in members:
		if m.id == id:
			return m
	return {}


func find_by_name(member_name: String) -> Dictionary:
	for m in members:
		if m.name.to_lower() == member_name.strip_edges().to_lower():
			return m
	return {}


## Adds a member and returns them; names must be unique (case-insensitive).
func add(member_name: String) -> Dictionary:
	member_name = member_name.strip_edges().left(12)
	if member_name == "" or not find_by_name(member_name).is_empty():
		return {}
	var m := {
		id = "%d-%d" % [Time.get_unix_time_from_system(), randi() % 100000],
		name = member_name,
		colour = members.size() % Competition.COLOURS.size(),
		joined = Time.get_date_string_from_system(),
		stats = empty_stats(),
		history = [],
	}
	members.append(m)
	return m


func rename(id: String, new_name: String) -> bool:
	new_name = new_name.strip_edges().left(12)
	var other := find_by_name(new_name)
	var m := find(id)
	if m.is_empty() or new_name == "" or (not other.is_empty() and other.id != id):
		return false
	m.name = new_name
	return true


func remove(id: String) -> void:
	for i in members.size():
		if members[i].id == id:
			members.remove_at(i)
			return


## fairway: 1 hit, 0 missed, -1 no chance (par 3). drive: metres, 0 if none.
func record_hole(id: String, par: int, strokes: int, putts: int, fairway: int, gir: bool, drive: float) -> void:
	var m := find(id)
	if m.is_empty():
		return
	var s: Dictionary = m.stats
	s.holes += 1
	s.strokes += strokes
	s.par += par
	s.putts += putts
	if strokes == 1:
		s.hole_in_ones += 1
	var diff := strokes - par
	if diff <= -2:
		s.eagles += 1
	elif diff == -1:
		s.birdies += 1
	elif diff == 0:
		s.pars += 1
	elif diff == 1:
		s.bogeys += 1
	else:
		s.doubles += 1
	if fairway >= 0:
		s.fairway_chances += 1
		s.fairways += fairway
	if gir:
		s.greens += 1
	if drive > 0.0:
		s.drives += 1
		s.drive_total += drive
		s.longest_drive = maxf(s.longest_drive, drive)


## entry: {date, course, code, mode, holes, strokes, par, result ("win",
## "loss", "halved" or ""), skins, text}.
func record_round(id: String, entry: Dictionary) -> void:
	var m := find(id)
	if m.is_empty():
		return
	var s: Dictionary = m.stats
	s.rounds += 1
	match entry.get("result", ""):
		"win":
			s.wins += 1
		"loss":
			s.losses += 1
		"halved":
			s.halves += 1
	s.skins += int(entry.get("skins", 0))
	var key := "best18" if entry.holes == 18 else ("best9" if entry.holes == 9 else "")
	if key != "":
		var best: Dictionary = s[key]
		var to_par: int = entry.strokes - entry.par
		if best.is_empty() or to_par < int(best.strokes) - int(best.par):
			s[key] = {strokes = entry.strokes, par = entry.par, course = entry.course, date = entry.date}
	m.history.push_front(entry)
	if m.history.size() > HISTORY_LENGTH:
		m.history.resize(HISTORY_LENGTH)


func load_file() -> void:
	members.clear()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("members")) != TYPE_ARRAY:
		return
	for m in data.members:
		if typeof(m) == TYPE_DICTIONARY and m.has("id") and m.has("name"):
			var stats := empty_stats()
			stats.merge(m.get("stats", {}), true)
			m.stats = stats
			if typeof(m.get("history")) != TYPE_ARRAY:
				m.history = []
			members.append(m)


func save() -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify({members = members}, "\t"))
	return OK


# --- Derived figures for display -------------------------------------------

## Average score relative to par over 18 holes, e.g. +7.5.
static func scoring_average(s: Dictionary) -> float:
	return 0.0 if s.holes == 0 else float(s.strokes - s.par) / s.holes * 18.0


static func percent(part: float, whole: float) -> String:
	return "–" if whole <= 0.0 else "%d%%" % roundi(part / whole * 100.0)
