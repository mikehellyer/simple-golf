class_name Aim
extends RefCounted
## Shot set-up shared by human players and the computer: which club to take,
## how far it goes from this lie, and where to aim.


static func pick_club(dist: float, lie: int) -> int:
	if lie == Surface.GREEN or (lie == Surface.FRINGE and dist < 20.0):
		return Clubs.PUTTER
	if lie == Surface.BUNKER and dist < 70.0:
		return Clubs.SAND_WEDGE
	var first := Clubs.DRIVER if lie == Surface.TEE else Clubs.DRIVER + 1
	for i in range(Clubs.SAND_WEDGE, first - 1, -1):
		if Clubs.carry(i) * Clubs.lie_power(i, lie) >= dist * 0.97:
			return i
	return first


## Full-power carry from this lie; for the putter, the distance to the pin.
static func reach(club: int, lie: int, dist: float) -> float:
	if club == Clubs.PUTTER:
		return dist
	return Clubs.carry(club) * Clubs.lie_power(club, lie)


## Putter speed at 100% power: enough to roll 25% past the hole on the flat.
static func putt_speed(dist: float) -> float:
	return Clubs.putt_speed_for(maxf(dist * 1.25, 2.0))


## The pin if it is in range, otherwise the point on the centre line we can
## just reach (a lay-up).
static func target(hole: Hole, from: Vector3, club: int, lie: int) -> Vector3:
	var dist := flat_distance(from, hole.pin)
	var r := reach(club, lie, dist)
	if club == Clubs.PUTTER or r >= dist * 0.95:
		return hole.pin
	var best_z := hole.pin.z
	var best := INF
	var z := from.z
	while z < hole.pin.z:
		var err := absf(flat_distance(Vector3(hole.centre_x(z), 0.0, z), from) - r)
		if err < best:
			best = err
			best_z = z
		z += 2.0
	var x := hole.centre_x(best_z)
	return Vector3(x, hole.height_at(x, best_z), best_z)


static func default_heading(hole: Hole, from: Vector3, club: int, lie: int) -> float:
	return heading_to(from, target(hole, from, club, lie))


static func heading_to(from: Vector3, to: Vector3) -> float:
	return atan2(to.x - from.x, to.z - from.z)


static func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
