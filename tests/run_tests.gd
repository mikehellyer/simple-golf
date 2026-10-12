extends SceneTree
## Headless test runner. After importing the project once
## (godot --headless --import), run:
##   godot --headless --script res://tests/run_tests.gd

const UpdaterScript := preload("res://scripts/core/updater.gd")
const YARDS := 1.09361

var _failures := 0
var _passes := 0


func _init() -> void:
	test_club_carries()
	test_wind()
	test_curve()
	test_determinism()
	test_putting()
	test_hazards()
	test_hole_generation()
	test_full_holes_playable()
	test_version_compare()
	test_shot_events()
	test_tree_trunks()
	test_scorecard()
	test_stroke_play()
	test_match_play()
	test_skins()
	test_team_formats()
	test_cpu_golfer()
	test_hole_overrides()
	test_course_codes()
	test_profiles()
	test_society_addresses()
	test_real_course()
	print("\n%d passed, %d failed" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)


func check(cond: bool, what: String) -> void:
	if cond:
		_passes += 1
	else:
		_failures += 1
		printerr("FAIL: ", what)


func _full(club: int, course = null, wind := Vector3.ZERO, accuracy := 0.0) -> BallPhysics.Result:
	var l := Clubs.launch_for(club, Vector3.ZERO, 0.0, 1.0, accuracy, Surface.FAIRWAY, 0.0)
	return BallPhysics.simulate(l, course if course else FlatCourse.new(), wind)


func test_club_carries() -> void:
	var driver := Clubs.carry(Clubs.DRIVER) * YARDS
	var seven := Clubs.carry(7) * YARDS
	var wedge := Clubs.carry(Clubs.SAND_WEDGE) * YARDS
	check(driver > 225.0 and driver < 265.0, "driver carry %d yds" % driver)
	check(seven > 135.0 and seven < 165.0, "7 iron carry %d yds" % seven)
	check(wedge > 65.0 and wedge < 95.0, "sand wedge carry %d yds" % wedge)
	for i in range(1, Clubs.PUTTER):
		check(Clubs.carry(i) < Clubs.carry(i - 1), "%s shorter than %s" % [Clubs.club_name(i), Clubs.club_name(i - 1)])


func test_wind() -> void:
	var still := _full(7).carry
	check(_full(7, null, Vector3(0, 0, -6)).carry < still - 5.0, "headwind shortens the carry")
	check(_full(7, null, Vector3(0, 0, 6)).carry > still + 3.0, "tailwind lengthens the carry")
	check(_full(7, null, Vector3(6, 0, 0)).rest.x > 2.0, "crosswind from the right blows the ball left (+X)")


func test_curve() -> void:
	# Heading 0 plays along +Z, so the golfer's right is -X.
	check(_full(5, null, Vector3.ZERO, 0.1).rest.x < -5.0, "early click slices right")
	check(_full(5, null, Vector3.ZERO, -0.1).rest.x > 5.0, "late click hooks left")
	check(absf(_full(5).rest.x) < 0.01, "pure strike flies straight")


func test_determinism() -> void:
	var hole := Hole.new(4, 1234)
	var l := Clubs.launch_for(Clubs.DRIVER, hole.tee, 0.05, 1.02, 0.04, Surface.TEE, 0.0)
	var a := BallPhysics.simulate(l, hole, Vector3(2, 0, -1))
	var b := BallPhysics.simulate(l, hole, Vector3(2, 0, -1))
	check(a.rest == b.rest and a.path.size() == b.path.size(), "same launch gives the same shot")


func test_putting() -> void:
	var green := FlatCourse.new()
	green.surface = Surface.GREEN
	var l := BallPhysics.Launch.new()
	l.speed = 1.83  # stimpmeter release speed
	var roll := BallPhysics.simulate(l, green).rest.z
	check(roll > 2.8 and roll < 3.3, "stimp 10 roll is about 3 m (got %.2f)" % roll)

	green.pin = Vector3(0, 0, 6)
	l.speed = Clubs.putt_speed_for(6.3)
	check(BallPhysics.simulate(l, green).outcome == BallPhysics.Outcome.HOLED, "firm straight putt drops")
	l.speed = Clubs.putt_speed_for(12.0)
	check(BallPhysics.simulate(l, green).outcome == BallPhysics.Outcome.REST, "putt hit far too hard lips out")


func test_hazards() -> void:
	var lake := FlatCourse.new()
	lake.surface = Surface.WATER
	check(_full(9, lake).outcome == BallPhysics.Outcome.WATER, "ball landing on water is a water hazard")


func test_hole_generation() -> void:
	for n in range(1, 19):
		var hole := Hole.new(n, 1000 + n)
		check(hole.surface_at(hole.pin.x, hole.pin.z) == Surface.GREEN, "hole %d pin is on the green" % n)
		check(hole.surface_at(0.0, 0.0) == Surface.TEE, "hole %d tee is a tee" % n)
		check(hole.is_in_bounds(hole.pin.x, hole.pin.z), "hole %d pin is in bounds" % n)
		var yards := hole.yardage() * YARDS
		var ranges := {3: [130, 230], 4: [330, 470], 5: [460, 590]}
		check(yards > ranges[hole.par][0] and yards < ranges[hole.par][1],
				"hole %d par %d is %d yds" % [n, hole.par, yards])
	# Greens must stay puttable: no spot steeper than 5%.
	var steepest := 0.0
	for n in range(1, 19):
		var h := Hole.new(n, 5000 + n)
		for i in range(-20, 21):
			for j in range(-20, 21):
				var x := h.green_centre.x + i
				var z := h.green_centre.y + j
				if h.surface_at(x, z) == Surface.GREEN:
					var nn := h.normal_at(x, z)
					steepest = maxf(steepest, Vector2(nn.x, nn.z).length() / nn.y)
	check(steepest < 0.05, "greens are no steeper than 5%% (got %.1f%%)" % (steepest * 100.0))
	var a := Hole.new(7, 42)
	var b := Hole.new(7, 42)
	check(a.pin == b.pin and a.trees.size() == b.trees.size(), "same seed gives the same hole")


## A robot plays every hole with perfect strikes at the pin; it should finish
## each one without the simulation hanging or wandering off.
func test_full_holes_playable() -> void:
	var start := Time.get_ticks_msec()
	for n in range(1, 19):
		var hole := Hole.new(n, 77 + n)
		var pos := hole.tee
		var lie := Surface.TEE
		var shots := 0
		var holed := false
		while shots < 15 and not holed:
			shots += 1
			var d := hole.pin - pos
			var dist := Vector2(d.x, d.z).length()
			var heading := atan2(d.x, d.z)
			var club := Clubs.PUTTER
			var power := 1.0
			if lie != Surface.GREEN:
				club = Clubs.SAND_WEDGE
				for i in range(Clubs.SAND_WEDGE, 0, -1):
					if Clubs.carry(i) * Clubs.lie_power(i, lie) >= dist:
						club = i
						break
				if club == Clubs.SAND_WEDGE:
					power = clampf(dist / Clubs.carry(club) / Clubs.lie_power(club, lie), 0.15, 1.0)
				if lie != Surface.TEE and club == Clubs.DRIVER:
					club = 1
			var putt := Clubs.putt_speed_for(dist + 0.3)
			var r := BallPhysics.simulate(Clubs.launch_for(club, pos, heading, power, 0.0, lie, putt), hole)
			match r.outcome:
				BallPhysics.Outcome.HOLED:
					holed = true
				BallPhysics.Outcome.REST:
					pos = r.rest
					lie = hole.surface_at(pos.x, pos.z)
				_:
					# Penalty: replay from the last safe spot.
					shots += 1
					pos = r.last_safe
					lie = hole.surface_at(pos.x, pos.z)
		check(holed, "robot finishes hole %d (par %d) in %d shots" % [n, hole.par, shots])
	print("robot round took %d ms" % (Time.get_ticks_msec() - start))


func test_version_compare() -> void:
	check(UpdaterScript.is_newer("v0.2.0", "0.1.9"), "0.2.0 is newer than 0.1.9")
	check(UpdaterScript.is_newer("1.2.10", "1.2.9"), "1.2.10 is newer than 1.2.9")
	check(not UpdaterScript.is_newer("0.1.0", "0.1.0"), "equal versions are not newer")
	check(not UpdaterScript.is_newer("0.1", "0.1.1"), "0.1 is older than 0.1.1")
	var names := PackedStringArray(["simple-golf-0.3.0-linux-x86_64.tar.gz", "Simple-Golf-0.3.0-macOS.dmg",
			"Simple-Golf-0.3.0-Windows-portable.zip", "Simple-Golf-0.3.0-Windows-Setup.exe",
			"simple-golf_0.3.0_amd64.deb"])
	check(UpdaterScript.pick_installer(names, "Linux") == "simple-golf_0.3.0_amd64.deb", "Linux updates with the .deb")
	check(UpdaterScript.pick_installer(names, "macOS") == "Simple-Golf-0.3.0-macOS.dmg", "macOS updates with the .dmg")
	check(UpdaterScript.pick_installer(names, "Windows") == "Simple-Golf-0.3.0-Windows-Setup.exe",
			"Windows updates with the installer, not the portable zip")


func test_shot_events() -> void:
	var r := _full(7)
	check(r.events.size() >= 1 and r.events[0].kind == BallPhysics.Event.BOUNCE, "landing makes a bounce event")
	var times_ok := true
	for i in range(1, r.events.size()):
		times_ok = times_ok and r.events[i].time >= r.events[i - 1].time
	check(times_ok, "events are in time order")
	var green := FlatCourse.new()
	green.surface = Surface.GREEN
	green.pin = Vector3(0, 0, 4)
	var l := BallPhysics.Launch.new()
	l.speed = Clubs.putt_speed_for(4.2)
	var holed := BallPhysics.simulate(l, green)
	check(holed.events.back().kind == BallPhysics.Event.HOLED, "holed putt ends with a holed event")


class TreeCourse:
	extends FlatCourse
	var tree := Vector4(0.0, 0.0, 30.0, 4.0)

	func _init() -> void:
		tree_top = 12.0

	func trees_near(_x: float, _z: float) -> Array[Vector4]:
		return [tree]


func test_tree_trunks() -> void:
	# A putt rolled straight at a trunk bounces back off it.
	var course := TreeCourse.new()
	var l := BallPhysics.Launch.new()
	l.speed = 9.0
	var r := BallPhysics.simulate(l, course)
	check(r.rest.z < 30.0, "rolling ball stops short of the trunk (z=%.1f)" % r.rest.z)
	var hit := false
	for e in r.events:
		hit = hit or e.kind == BallPhysics.Event.TREE
	check(hit, "trunk hit is reported")
	# A low punch shot into the canopy is knocked down.
	var punch := Clubs.launch_for(5, Vector3.ZERO, 0.0, 1.0, 0.0, Surface.FAIRWAY, 0.0)
	check(BallPhysics.simulate(punch, course).rest.z < Clubs.carry(5) * 0.6, "canopy stops a shot through the tree")


func test_scorecard() -> void:
	var card := Scorecard.new(PackedInt32Array([4, 3, 5, 4, 4, 3, 4, 5, 4, 4, 3, 5, 4, 4, 3, 4, 5, 4]),
			PackedInt32Array([400, 160, 520, 380, 390, 150, 410, 500, 420, 400, 170, 510, 360, 400, 180, 390, 530, 410]))
	check(card.to_par_text() == "E", "empty card is level par")
	for s in [3, 3, 6, 4]:
		card.record(s)
	check(card.total() == 16 and card.to_par() == 0, "16 strokes through 4 holes is level")
	card.record(6)
	check(card.to_par_text() == "+2", "double bogey on the 5th makes it +2")
	check(card.total(0, 9) == 22 and card.total(9, 18) == 0, "out and in totals")
	check(card.par_total(0, 9) == 36 and card.par_total() == 72, "par 36 out, 72 total")
	check(Scorecard.score_name(2, 4) == "Eagle!" and Scorecard.score_name(1, 3) == "Hole in one!", "score names")


func _players(n: int) -> Array[Competition.Player]:
	var out: Array[Competition.Player] = []
	for i in n:
		out.append(Competition.Player.new("P%d" % (i + 1), Competition.Kind.HUMAN, Color.WHITE))
	return out


func _comp(mode: Competition.Mode, n: int, holes := 18) -> Competition:
	var pars := PackedInt32Array()
	var yards := PackedInt32Array()
	for i in holes:
		pars.append(4)
		yards.append(400)
	return Competition.new(mode, _players(n), pars, yards)


func test_stroke_play() -> void:
	var c := _comp(Competition.Mode.STROKE, 3)
	check(c.tee_order() == PackedInt32Array([0, 1, 2]), "first tee goes in player order")
	c.record_hole(PackedInt32Array([5, 3, 4]))
	check(c.tee_order() == PackedInt32Array([1, 2, 0]), "lowest score has the honour")
	c.record_hole(PackedInt32Array([4, 4, 4]))
	check(c.tee_order() == PackedInt32Array([1, 2, 0]), "ties keep the previous order")
	check(c.leaders() == [1], "P2 leads at -1")
	check(c.standings()[0] == "-1  P2", "leaderboard is sorted (%s)" % c.standings()[0])
	check(not c.is_over(), "round not over after 2 holes")


func test_match_play() -> void:
	var c := _comp(Competition.Mode.MATCH, 2)
	c.record_hole(PackedInt32Array([3, 4]))
	check(c.match_status() == "P1 1 UP thru 1", "P1 1 up (%s)" % c.match_status())
	c.record_hole(PackedInt32Array([4, 4]))
	check(c.match_row[1] == "1 UP", "halved hole keeps the standing")
	for i in 14:
		c.record_hole(PackedInt32Array([4, 4]))
	c.record_hole(PackedInt32Array([3, 4]))
	# 2 up with 1 to play: match over, 2 & 1.
	check(c.is_over() and c.match_status() == "P1 wins 2 & 1", "match ends early (%s)" % c.match_status())
	var d := _comp(Competition.Mode.MATCH, 2, 2)
	d.record_hole(PackedInt32Array([4, 3]))
	check(d.match_status() == "P2 1 UP (dormie)", "dormie (%s)" % d.match_status())
	d.record_hole(PackedInt32Array([3, 4]))
	check(d.is_over() and d.result_text() == "Match halved", "all square after the last hole is halved")


func test_skins() -> void:
	var c := _comp(Competition.Mode.SKINS, 3)
	c.record_hole(PackedInt32Array([4, 4, 5]))
	c.record_hole(PackedInt32Array([4, 4, 4]))
	check(c.carry == 3 and c.skins_row[0] == "–", "tied holes carry the skin over")
	var h := c.record_hole(PackedInt32Array([5, 3, 4]))
	check(c.skins[1] == 3 and c.carry == 1, "outright win takes the pot (%s)" % h)
	check(c.result_text() == "P2 wins with 3 skins", c.result_text())


func test_team_formats() -> void:
	var fb := _comp(Competition.Mode.FOURBALL, 4)
	check(fb.ball_count() == 4 and fb.side_count() == 2, "fourball: 4 balls, 2 sides")
	# Team 1's best is 3 (P2), team 2's best is 4.
	fb.record_hole(PackedInt32Array([6, 3, 4, 5]))
	check(fb.match_diff == 1 and fb.match_status().begins_with("P1 & P2 1 UP"), fb.match_status())
	var fs := _comp(Competition.Mode.FOURSOMES, 4)
	check(fs.ball_count() == 2 and fs.cards[1].player_name == "P3 & P4", "foursomes: one ball per team")
	check(fs.hitter(0, 0, 1).name == "P1" and fs.hitter(0, 1, 1).name == "P2"
			and fs.hitter(0, 2, 1).name == "P1", "partners alternate shots")
	check(fs.hitter(1, 0, 2).name == "P4", "second partner drives on even holes")


## The hard computer golfer should play a few holes respectably.
func test_cpu_golfer() -> void:
	var start := Time.get_ticks_msec()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var over_par := 0
	for n in range(1, 7):
		var hole := Hole.new(n, 900 + n)
		var pos := hole.tee
		var lie := Surface.TEE
		var shots := 0
		var holed := false
		while shots < 12 and not holed:
			shots += 1
			var p := CpuPlayer.plan(hole, pos, lie, Vector3(3, 0, 1), CpuPlayer.Skill.HARD, rng)
			var putt := Aim.putt_speed(Aim.flat_distance(pos, hole.pin))
			var r := BallPhysics.simulate(Clubs.launch_for(p.club, pos, p.heading, p.power,
					p.accuracy, lie, putt), hole, Vector3(3, 0, 1))
			match r.outcome:
				BallPhysics.Outcome.HOLED:
					holed = true
				BallPhysics.Outcome.REST:
					pos = r.rest
					lie = hole.surface_at(pos.x, pos.z)
				_:
					shots += 1
					pos = r.last_safe
					lie = hole.surface_at(pos.x, pos.z)
		over_par += shots - hole.par
	check(over_par >= -8 and over_par <= 9, "hard CPU scores like a good golfer over 6 holes (got %+d)" % over_par)
	print("cpu 6 holes %+d in %d ms" % [over_par, Time.get_ticks_msec() - start])


func test_hole_overrides() -> void:
	var plain := Hole.new(5, 321)
	var dry := Hole.new(5, 321, {water = 1})
	check(dry.ponds.is_empty(), "water: none removes ponds")
	check(dry.pin == plain.pin or plain.ponds.size() > 0 and dry.length == plain.length,
			"removing water leaves the layout alone")
	check(dry.bunkers == plain.bunkers, "removing water leaves the bunkers alone")
	var wet := Hole.new(5, 321, {water = 2})
	check(wet.ponds.size() == 1, "water: add always makes a pond")
	var long := Hole.new(5, 321, {length = 480.0, par = 5})
	check(long.par == 5 and absf(long.length - 480.0) < 0.01, "par and length overrides")
	check(long.surface_at(long.pin.x, long.pin.z) == Surface.GREEN, "overridden hole still has its pin on the green")
	check(Hole.new(5, 321, {bunkers = 1}).bunkers.is_empty(), "bunkers: none")
	check(Hole.new(5, 321, {bunkers = 2}).bunkers.size() > plain.bunkers.size(), "bunkers: extra")
	check(Hole.new(5, 321, {trees = 0.0}).trees.is_empty(), "trees: 0 clears the trees")
	check(Hole.new(5, 321, {pin = 7}).pin != plain.pin, "new pin position")
	check(is_equal_approx(Hole.new(5, 321, {relief = 4.5}).feature("relief"), 4.5), "feature() reports overrides")


func test_course_codes() -> void:
	var c := Course.new("Test", 123456789)
	var plain := Course.from_code(c.to_code())
	check(c.to_code().begins_with("SG-") and plain != null and plain.base_seed == 123456789,
			"plain course code round-trips (%s)" % c.to_code())
	c.set_hole_overrides(3, {water = 2, length = 200.0})
	var code := c.to_code()
	var back := Course.from_code(code)
	check(code.begins_with("SGX-") and back != null and back.name == "Test"
			and back.hole_overrides(3).water == 2.0, "edited course code round-trips")
	check(back.make_hole(3).ponds.size() == 1 and back.make_hole(4).pin == c.make_hole(4).pin,
			"decoded course builds the same holes")
	check(Course.from_code("nonsense") == null and Course.from_code("SGX-!!!") == null, "bad codes rejected")
	var hostile := Course.from_dict({seed = 5, edits = {"2": {length = 99999.0, evil = 1}, "40": {par = 3}}})
	check(hostile.hole_overrides(2).length == 560.0 and not hostile.hole_overrides(2).has("evil")
			and hostile.edits.size() == 1, "untrusted courses are clamped and cleaned")
	var day := {year = 2026, month = 10, day = 11}
	check(Course.daily(day).base_seed == Course.daily(day).base_seed
			and Course.daily(day).base_seed != Course.daily({year = 2026, month = 10, day = 12}).base_seed,
			"course of the day is stable for a date and changes daily")
	var other := Course.new("Layout", 99)
	other.set_hole_overrides(1, {layout = 3})
	check(other.make_hole(1).pin != Course.new("Layout", 99).make_hole(1).pin, "new layout changes the hole")


func test_profiles() -> void:
	var file := "user://test_members.json"
	DirAccess.remove_absolute(file)
	var club := PlayerProfiles.new(file)
	var mike := club.add("Mike")
	check(not mike.is_empty() and club.add("mike").is_empty(), "member names are unique")
	club.add("Ana")
	check(club.rename(mike.id, "Michael") and not club.rename(mike.id, "Ana"), "rename, but not onto another member")
	club.record_hole(mike.id, 4, 3, 1, 1, true, 240.0)
	club.record_hole(mike.id, 3, 1, 0, -1, true, 0.0)
	club.record_hole(mike.id, 5, 7, 3, 0, false, 210.0)
	club.record_round(mike.id, {date = "2026-10-11", course = "Test", code = "SG-1", mode = 0,
			holes = 9, strokes = 40, par = 36, result = "win", skins = 0, text = "40 (+4)"})
	check(club.save() == OK, "members save")
	var again := PlayerProfiles.new(file)
	var m := again.find(mike.id)
	var st: Dictionary = m.stats
	check(m.name == "Michael" and again.members.size() == 2, "members reload")
	check(int(st.holes) == 3 and int(st.birdies) == 1 and int(st.hole_in_ones) == 1
			and int(st.doubles) == 1, "hole scores are counted (%s)" % st)
	check(int(st.fairways) == 1 and int(st.fairway_chances) == 2 and int(st.greens) == 2
			and int(st.putts) == 4, "fairways, greens and putts")
	check(is_equal_approx(st.longest_drive, 240.0) and int(st.drives) == 2, "drives")
	check(int(st.rounds) == 1 and int(st.wins) == 1 and int(st.best9.strokes) == 40
			and m.history.size() == 1, "round history, wins and best 9")
	check(is_equal_approx(PlayerProfiles.scoring_average(st), -6.0), "scoring average per 18 (11 on par 12 over 3 holes)")
	again.remove(mike.id)
	check(again.find(mike.id).is_empty(), "members can leave")
	DirAccess.remove_absolute(file)


func test_society_addresses() -> void:
	check(SocietyClient.normalise_url("golfpi.tail1234.ts.net") == "https://golfpi.tail1234.ts.net",
			"Tailscale names use https")
	check(SocietyClient.normalise_url("golfpi.tail1234.ts.net:8443/") == "https://golfpi.tail1234.ts.net:8443",
			"Funnel's spare port is kept")
	check(SocietyClient.normalise_url("192.168.1.20:8000") == "http://192.168.1.20:8000",
			"home network addresses use http")
	check(SocietyClient.normalise_url("https://fridayfour.duckdns.org") == "https://fridayfour.duckdns.org",
			"full addresses are left alone")


func test_real_course() -> void:
	var id := "ponte-vedra-stadium"
	check(id in CourseMaps.ids() and CourseMaps.hole_count(id) == 18, "Ponte Vedra Stadium is bundled with 18 holes")
	var c := Course.real(id, 99)
	var back := Course.from_code(c.to_code())
	check(c.to_code().begins_with("SGC-") and back != null and back.map == id and back.base_seed == 99,
			"real course codes round-trip (%s)" % c.to_code())
	check(Course.from_dict(c.to_dict()).map == id, "real courses survive the trip to the society server")
	var start := Time.get_ticks_msec()
	var par := 0
	var island_water := 0
	for n in range(1, 19):
		var h := c.make_hole(n)
		par += h.par
		check(h.is_mapped(), "hole %d is built from the map" % n)
		check(h.surface_at(h.pin.x, h.pin.z) == Surface.GREEN, "hole %d pin is on its green" % n)
		check(h.surface_at(0.0, 0.0) == Surface.TEE, "hole %d tees off from a tee" % n)
		check(h.pin.z > 100.0 and absf(h.pin.x) < 40.0, "hole %d plays up the screen (pin %s)" % [n, h.pin])
		if n == 17:
			# The island green: water all the way between tee and green.
			for k in range(10, 90):
				var p := Vector3.ZERO.lerp(h.pin, k / 100.0)
				if h.surface_at(p.x, p.z) == Surface.WATER:
					island_water += 1
	check(par == 72, "the Stadium Course is par 72 (got %d)" % par)
	check(island_water > 40, "17 is an island green: water across most of the carry (%d of 80)" % island_water)
	print("built 18 real holes in %d ms" % (Time.get_ticks_msec() - start))

	# Hard computer golfers should get round the real course in a sensible score.
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var over := 0
	start = Time.get_ticks_msec()
	for n in range(1, 19):
		var hole := c.make_hole(n)
		var pos := hole.tee
		var lie := Surface.TEE
		var shots := 0
		var holed := false
		while shots < 12 and not holed:
			shots += 1
			var p := CpuPlayer.plan(hole, pos, lie, Vector3.ZERO, CpuPlayer.Skill.HARD, rng)
			var r := BallPhysics.simulate(Clubs.launch_for(p.club, pos, p.heading, p.power, p.accuracy, lie,
					Aim.putt_speed(Aim.flat_distance(pos, hole.pin))), hole)
			match r.outcome:
				BallPhysics.Outcome.HOLED:
					holed = true
				BallPhysics.Outcome.REST:
					pos = r.rest
					lie = hole.surface_at(pos.x, pos.z)
				_:
					shots += 1
					pos = r.last_safe
					lie = hole.surface_at(pos.x, pos.z)
		check(holed, "hard CPU finishes real hole %d" % n)
		over += shots - hole.par
	check(over < 25, "hard CPU plays the real course in a sensible score (%+d)" % over)
	print("hard CPU round at Ponte Vedra Stadium: %+d in %d ms" % [over, Time.get_ticks_msec() - start])
