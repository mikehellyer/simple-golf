class_name CpuPlayer
extends RefCounted
## Computer golfer. Because the ball physics is deterministic, the computer
## can "imagine" candidate shots by simulating them, pick the best, and then
## make human-like mistakes on the swing meter according to its skill.

enum Skill { EASY, MEDIUM, HARD }

const SKILL_NAMES := ["Easy", "Medium", "Hard"]
## Standard deviation of swing-meter power and timing errors per skill.
const POWER_SD := [0.07, 0.045, 0.025]
const TIMING_SD := [0.055, 0.035, 0.022]
## Misjudging the line (radians) and the pace (fraction of power) on putts.
const READ_SD := [0.03, 0.02, 0.013]
const PACE_SD := [0.08, 0.05, 0.03]
## Extra cost for finishing on these surfaces, in metres of distance.
const LIE_COST := {Surface.ROUGH: 8.0, Surface.BUNKER: 15.0, Surface.FRINGE: 1.0}


class Plan:
	var club := 0
	var heading := 0.0
	var power := 1.0
	var accuracy := 0.0


static func plan(hole: Hole, from: Vector3, lie: int, wind: Vector3, skill: Skill,
		rng: RandomNumberGenerator, quality := -1) -> Plan:
	var p := Plan.new()
	var setup := {} if quality < 0 else {lie_quality = quality}
	var dist := Aim.flat_distance(from, hole.pin)
	p.club = Aim.pick_club(dist, lie)
	var putt_speed := Aim.putt_speed(dist)
	var target := Aim.target(hole, from, p.club, lie)
	var reach := Aim.reach(p.club, lie, dist)
	var putting := p.club == Clubs.PUTTER

	var base := Aim.heading_to(from, target)
	var step := 0.012 if putting else 0.02
	var powers: Array[float] = []
	if putting:
		powers = [0.78, 0.84, 0.89, 0.94, 1.0]
	elif reach > dist:
		# Distance isn't proportional to power (a chip's carry grows roughly
		# with its square), so find the power that gets there by simulating.
		var want := Aim.flat_distance(from, target)
		var lo := 0.03
		var hi := 1.0
		for i in 7:
			var mid := (lo + hi) * 0.5
			var trial := BallPhysics.simulate(Clubs.launch_for(p.club, from, base, mid, 0.0, lie, putt_speed, setup), hole, wind)
			if Aim.flat_distance(from, trial.rest) < want:
				lo = mid
			else:
				hi = mid
		var est := (lo + hi) * 0.5
		for f in [0.94, 0.97, 1.0, 1.03, 1.06]:
			powers.append(clampf(est * f, 0.03, 1.0))
	else:
		powers = [1.0]

	var power: float = powers[powers.size() / 2]
	var heading := _best_heading(hole, from, lie, wind, p.club, base, step, power, putt_speed, target, setup)
	var best_cost := INF
	for pw in powers:
		var c := _cost(hole, from, lie, wind, p.club, heading, pw, putt_speed, target, setup)
		if c < best_cost:
			best_cost = c
			power = pw
	heading = _best_heading(hole, from, lie, wind, p.club, heading, step * 0.5, power, putt_speed, target, setup)

	# Now play like a person: misread putts a little, and mistime the meter.
	p.heading = heading
	if putting:
		p.heading += rng.randfn(0.0, READ_SD[skill])
		p.power = clampf(power * (1.0 + rng.randfn(0.0, PACE_SD[skill])), 0.05, 1.1)
		p.accuracy = rng.randfn(0.0, TIMING_SD[skill] * 0.5)
	else:
		p.power = clampf(power + rng.randfn(0.0, POWER_SD[skill]), 0.05, 1.1)
		p.accuracy = rng.randfn(0.0, TIMING_SD[skill])
	return p


static func _best_heading(hole: Hole, from: Vector3, lie: int, wind: Vector3, club: int,
		centre: float, step: float, power: float, putt_speed: float, target: Vector3, setup := {}) -> float:
	var best := centre
	var best_cost := INF
	for k in range(-4, 5):
		var h := centre + k * step
		var c := _cost(hole, from, lie, wind, club, h, power, putt_speed, target, setup)
		if c < best_cost:
			best_cost = c
			best = h
	return best


static func _cost(hole: Hole, from: Vector3, lie: int, wind: Vector3, club: int,
		heading: float, power: float, putt_speed: float, target: Vector3, setup := {}) -> float:
	var launch := Clubs.launch_for(club, from, heading, power, 0.0, lie, putt_speed, setup)
	var r := BallPhysics.simulate(launch, hole, wind)
	match r.outcome:
		BallPhysics.Outcome.HOLED:
			return 0.0
		BallPhysics.Outcome.WATER, BallPhysics.Outcome.OUT_OF_BOUNDS:
			return 1.0e6
	var cost := Aim.flat_distance(r.rest, target)
	cost += LIE_COST.get(hole.surface_at(r.rest.x, r.rest.z), 0.0)
	return cost
