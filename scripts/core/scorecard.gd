class_name Scorecard
extends RefCounted
## One player's card for a round: pars and yardages per hole, strokes as played.

var player_name := "Player"
var pars := PackedInt32Array()
var yards := PackedInt32Array()
## Strokes per completed hole, in order.
var strokes := PackedInt32Array()


func _init(hole_pars: PackedInt32Array, hole_yards: PackedInt32Array, name := "Player") -> void:
	pars = hole_pars
	yards = hole_yards
	player_name = name


func hole_count() -> int:
	return pars.size()


func holes_played() -> int:
	return strokes.size()


func is_complete() -> bool:
	return strokes.size() >= pars.size()


func record(hole_strokes: int) -> void:
	strokes.append(hole_strokes)


## Strokes for holes [from, to) that have been played.
func total(from := 0, to := -1) -> int:
	var end := strokes.size() if to < 0 else mini(to, strokes.size())
	var sum := 0
	for i in range(from, end):
		sum += strokes[i]
	return sum


func par_total(from := 0, to := -1) -> int:
	var end := pars.size() if to < 0 else mini(to, pars.size())
	var sum := 0
	for i in range(from, end):
		sum += pars[i]
	return sum


## Score relative to par over the holes played so far.
func to_par() -> int:
	return total() - par_total(0, strokes.size())


func to_par_text() -> String:
	return format_to_par(to_par())


static func format_to_par(diff: int) -> String:
	return "E" if diff == 0 else "%+d" % diff


static func score_name(score: int, par: int) -> String:
	if score == 1:
		return "Hole in one!"
	match score - par:
		-3:
			return "Albatross!"
		-2:
			return "Eagle!"
		-1:
			return "Birdie"
		0:
			return "Par"
		1:
			return "Bogey"
		2:
			return "Double bogey"
		3:
			return "Triple bogey"
	return "%+d" % (score - par)
