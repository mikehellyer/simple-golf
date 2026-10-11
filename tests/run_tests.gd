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
