class_name Competition
extends RefCounted
## Who is playing, in what format, and how the scores add up.
##
## Everything is organised by *ball*: each ball has its own Scorecard. In most
## formats a ball is one player; in foursomes a ball is a team of two who take
## alternate shots. A *side* is what wins holes: a player, or a team of two in
## fourball (best ball) and foursomes.

enum Mode { STROKE, MATCH, SKINS, FOURBALL, FOURSOMES }
enum Kind { HUMAN, CPU_EASY, CPU_MEDIUM, CPU_HARD }

const MODE_NAMES := ["Stroke play", "Match play", "Skins", "Fourball", "Foursomes"]
const MODE_INFO := [
	"Everyone plays their own ball. Fewest strokes over 18 holes wins.",
	"Head to head. Win holes, not strokes: the match ends when one player is more holes up than there are holes left.",
	"Every hole is worth a skin. The outright lowest score takes it; ties carry the skin over to the next hole.",
	"Two teams of two, each playing their own ball. The better score in each team counts, match play.",
	"Two teams of two sharing one ball and taking alternate shots, match play.",
]
const PLAYER_COUNTS := [[1, 2, 3, 4], [2], [2, 3, 4], [4], [4]]
const KIND_NAMES := ["Human", "CPU (easy)", "CPU (medium)", "CPU (hard)"]
const COLOURS := [Color(1, 1, 1), Color(1.0, 0.85, 0.2), Color(1.0, 0.45, 0.3), Color(0.45, 0.75, 1.0)]


class Player:
	var name: String
	var kind: Kind
	var colour: Color

	func _init(player_name: String, player_kind: Kind, player_colour: Color) -> void:
		name = player_name
		kind = player_kind
		colour = player_colour

	func is_cpu() -> bool:
		return kind != Kind.HUMAN

	func skill() -> CpuPlayer.Skill:
		return maxi(kind - 1, 0) as CpuPlayer.Skill


var mode: Mode
var players: Array[Player] = []
var cards: Array[Scorecard] = []
## Per hole: "AS", "1 UP"... from side 0's point of view (match formats).
var match_row := PackedStringArray()
## Per hole: who won the skin(s), or "–" for a carry-over.
var skins_row := PackedStringArray()
var skins := PackedInt32Array()
var carry := 1
var match_diff := 0
var match_over := false
var _order := PackedInt32Array()


func _init(game_mode: Mode, game_players: Array[Player], pars: PackedInt32Array,
		yards: PackedInt32Array) -> void:
	mode = game_mode
	players = game_players
	for b in ball_count():
		cards.append(Scorecard.new(pars, yards, ball_name(b)))
	skins.resize(side_count())
	match_row.resize(pars.size())
	skins_row.resize(pars.size())


static func is_team_mode(m: Mode) -> bool:
	return m == Mode.FOURBALL or m == Mode.FOURSOMES


func is_match() -> bool:
	return mode in [Mode.MATCH, Mode.FOURBALL, Mode.FOURSOMES]


func ball_count() -> int:
	return 2 if mode == Mode.FOURSOMES else players.size()


func side_count() -> int:
	return 2 if is_team_mode(mode) else players.size()


func side_of_ball(ball: int) -> int:
	if mode == Mode.FOURBALL:
		return ball / 2
	return ball


func side_name(side: int) -> String:
	if is_team_mode(mode):
		return "%s & %s" % [players[side * 2].name, players[side * 2 + 1].name]
	return players[side].name


func ball_name(ball: int) -> String:
	return side_name(ball) if mode == Mode.FOURSOMES else players[ball].name


## Who swings this ball next. Foursomes partners alternate, with the first
## player driving on odd holes and the second on even holes.
func hitter(ball: int, swings_taken: int, hole_number: int) -> Player:
	if mode != Mode.FOURSOMES:
		return players[ball]
	var first := 0 if hole_number % 2 == 1 else 1
	return players[ball * 2 + (first + swings_taken) % 2]


func hole_count() -> int:
	return cards[0].hole_count()


func holes_played() -> int:
	return cards[0].holes_played()


func is_over() -> bool:
	return match_over or holes_played() >= hole_count()


## Teeing order: the lowest score on the previous hole has the honour; ties
## keep their previous order.
func tee_order() -> PackedInt32Array:
	var played := holes_played()
	if played == 0 or _order.is_empty():
		_order = PackedInt32Array(range(ball_count()))
		return _order
	var order := Array(_order)
	var last := played - 1
	order.sort_custom(func(a: int, b: int) -> bool:
		var sa := cards[a].strokes[last]
		var sb := cards[b].strokes[last]
		if sa != sb:
			return sa < sb
		return _order.find(a) < _order.find(b))
	_order = PackedInt32Array(order)
	return _order


## Records a finished hole (strokes per ball) and returns a one-line headline.
func record_hole(strokes: PackedInt32Array) -> String:
	var hole_index := holes_played()
	var par := cards[0].pars[hole_index]
	for b in ball_count():
		cards[b].record(strokes[b])
	var side_scores := PackedInt32Array()
	side_scores.resize(side_count())
	side_scores.fill(999)
	for b in ball_count():
		var s := side_of_ball(b)
		side_scores[s] = mini(side_scores[s], strokes[b])

	if is_match():
		var headline: String
		if side_scores[0] < side_scores[1]:
			match_diff += 1
			headline = "%s win%s the hole" % [side_name(0), _s(0)]
		elif side_scores[1] < side_scores[0]:
			match_diff -= 1
			headline = "%s win%s the hole" % [side_name(1), _s(1)]
		else:
			headline = "Hole halved"
		var remaining := hole_count() - (hole_index + 1)
		match_row[hole_index] = _short_status()
		if absi(match_diff) > remaining:
			match_over = true
		return "%s  ·  %s" % [headline, match_status()]

	if mode == Mode.SKINS:
		var best := 999
		var winners := 0
		var winner := -1
		for s in side_count():
			if side_scores[s] < best:
				best = side_scores[s]
				winners = 1
				winner = s
			elif side_scores[s] == best:
				winners += 1
		if winners == 1:
			var won := carry
			skins[winner] += won
			carry = 1
			skins_row[hole_index] = "%s%s" % [side_name(winner).left(2), "" if won == 1 else "×%d" % won]
			return "%s win%s %d skin%s" % [side_name(winner), _s(winner), won, "" if won == 1 else "s"]
		carry += 1
		skins_row[hole_index] = "–"
		return "Tied — %d skins carry over" % carry

	if ball_count() == 1:
		return "%s — %d on the par %d" % [Scorecard.score_name(strokes[0], par), strokes[0], par]
	var leader := leaders()
	return "Leader%s: %s (%s)" % ["s" if leader.size() > 1 else "",
			", ".join(leader.map(func(b: int) -> String: return ball_name(b))),
			cards[leader[0]].to_par_text()]


## Balls with the lowest score relative to par so far.
func leaders() -> Array[int]:
	var best := 999
	var out: Array[int] = []
	for b in ball_count():
		var tp := cards[b].to_par()
		if tp < best:
			best = tp
			out = [b]
		elif tp == best:
			out.append(b)
	return out


## Match standing, e.g. "Mike 2 UP thru 7", "All square", "Mike 1 UP (dormie)".
func match_status() -> String:
	var played := holes_played()
	if match_diff == 0:
		return "All square" + (" thru %d" % played if played > 0 else "")
	var leader := 0 if match_diff > 0 else 1
	var up := absi(match_diff)
	var remaining := hole_count() - played
	if match_over:
		if remaining > 0:
			return "%s win%s %d & %d" % [side_name(leader), _s(leader), up, remaining]
		return "%s win%s %d UP" % [side_name(leader), _s(leader), up]
	var text := "%s %d UP" % [side_name(leader), up]
	if up == remaining:
		return text + " (dormie)"
	return text + " thru %d" % played


## Lines for the on-screen leaderboard.
func standings() -> PackedStringArray:
	var lines := PackedStringArray()
	if is_match():
		lines.append(match_status())
	elif mode == Mode.SKINS:
		for s in side_count():
			lines.append("%s: %d skin%s" % [side_name(s), skins[s], "" if skins[s] == 1 else "s"])
		if carry > 1:
			lines.append("%d skins riding on this hole" % carry)
	elif ball_count() > 1:
		var order := Array(range(ball_count()))
		order.sort_custom(func(a: int, b: int) -> bool: return cards[a].to_par() < cards[b].to_par())
		for b in order:
			lines.append("%s  %s" % [cards[b].to_par_text(), ball_name(b)])
	return lines


## Summary when the round or match is over.
func result_text() -> String:
	if is_match():
		if match_diff == 0:
			return "Match halved"
		return match_status()
	if mode == Mode.SKINS:
		var best := skins[0]
		var who: Array[String] = []
		for s in side_count():
			if skins[s] > best:
				best = skins[s]
				who = [side_name(s)]
			elif skins[s] == best:
				who.append(side_name(s))
		return "%s win%s with %d skin%s" % [" & ".join(who), "" if who.size() > 1 else "s",
				best, "" if best == 1 else "s"]
	var lead := leaders()
	if ball_count() == 1:
		return "Round complete — %d (%s)" % [cards[0].total(), cards[0].to_par_text()]
	var names := ", ".join(lead.map(func(b: int) -> String: return ball_name(b)))
	return "%s win%s with %d (%s)" % [names, "" if lead.size() > 1 else "s",
			cards[lead[0]].total(), cards[lead[0]].to_par_text()]


func _short_status() -> String:
	if match_diff == 0:
		return "AS"
	return "%d %s" % [absi(match_diff), "UP" if match_diff > 0 else "DN"]


## "wins" for a single player, "win" for a team ("Mike & Ana win").
func _s(side: int) -> String:
	return "" if is_team_mode(mode) else "s"
