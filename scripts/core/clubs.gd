class_name Clubs
extends RefCounted
## The bag, and turning a swing-meter result into a ball launch.

const ALL := [
	{name = "Driver", speed = 72.0, loft = 11.0, spin = 2700.0},
	{name = "3 Wood", speed = 64.5, loft = 13.0, spin = 3600.0},
	{name = "5 Wood", speed = 61.0, loft = 15.0, spin = 4300.0},
	{name = "3 Iron", speed = 58.5, loft = 16.0, spin = 4600.0},
	{name = "4 Iron", speed = 57.0, loft = 17.5, spin = 4900.0},
	{name = "5 Iron", speed = 55.5, loft = 19.0, spin = 5400.0},
	{name = "6 Iron", speed = 53.0, loft = 21.0, spin = 6200.0},
	{name = "7 Iron", speed = 50.0, loft = 23.5, spin = 7000.0},
	{name = "8 Iron", speed = 47.0, loft = 26.0, spin = 7800.0},
	{name = "9 Iron", speed = 44.0, loft = 29.0, spin = 8500.0},
	{name = "P Wedge", speed = 41.0, loft = 33.0, spin = 9200.0},
	{name = "S Wedge", speed = 35.0, loft = 40.0, spin = 9800.0},
	{name = "Putter", speed = 0.0, loft = 0.0, spin = 0.0},
]
const DRIVER := 0
const SAND_WEDGE := 11
const PUTTER := 12

## Shot set-up chosen before the swing (MicroProse-style):
## tee_height: 0 low, 1 medium, 2 high (only matters for a tee shot);
## ball_position: -1 back in the stance, 0 centre, 1 forward.
const TEE_HEIGHTS := ["Low", "Medium", "High"]
const BALL_POSITIONS := {-1: "Back", 0: "Centre", 1: "Forward"}
## stance: -2 open, -1 semi-open, 0 square, 1 semi-closed, 2 closed.
const STANCES := {-2: "Open", -1: "Semi-open", 0: "Square", 1: "Semi-closed", 2: "Closed"}
const DEFAULT_SETUP := {tee_height = 1, ball_position = 0, stance = 0}

## Sidespin (rpm) and push/pull (radians) per unit of swing-meter error.
const SIDESPIN_PER_ERROR := 9000.0
const PUSH_PER_ERROR := 0.12
const PUTT_PUSH_PER_ERROR := 0.06

static var _carries := PackedFloat32Array()


static func club_name(i: int) -> String:
	return ALL[i].name


## Carry in metres of a perfect full shot from the fairway, on flat ground with no wind.
static func carry(i: int) -> float:
	if _carries.is_empty():
		var flat := FlatCourse.new()
		for j in ALL.size():
			if j == PUTTER:
				_carries.append(0.0)
			else:
				var l := launch_for(j, Vector3.ZERO, 0.0, 1.0, 0.0, Surface.FAIRWAY, 0.0)
				_carries.append(BallPhysics.simulate(l, flat).carry)
	return _carries[i]


## Ball speed multiplier for this club from this lie.
static func lie_power(club: int, lie: int) -> float:
	if lie == Surface.BUNKER and club == SAND_WEDGE:
		return 0.9
	return Surface.LIE_POWER[lie]


## Putter ball speed that rolls `distance` metres on a flat green.
static func putt_speed_for(distance: float) -> float:
	return sqrt(2.0 * Surface.ROLL_DECEL[Surface.GREEN] * distance)


## power: 0..1.1 (above 1 is overswing). accuracy: swing-meter error, positive
## means the downswing click was early (push and slice), negative late (pull and hook).
static func launch_for(club: int, position: Vector3, heading: float, power: float,
		accuracy: float, lie: int, putt_speed: float, setup := DEFAULT_SETUP) -> BallPhysics.Launch:
	var l := BallPhysics.Launch.new()
	l.position = position
	# Overswinging buys distance but magnifies any timing error.
	var err := accuracy * (1.0 + maxf(power - 1.0, 0.0) * 8.0)
	if club == PUTTER:
		l.speed = putt_speed * power
		l.heading = heading - err * PUTT_PUSH_PER_ERROR
		return l
	var c: Dictionary = ALL[club]
	l.speed = float(c.speed) * power * lie_power(club, lie)
	l.elevation = deg_to_rad(float(c.loft))
	l.heading = heading - err * PUSH_PER_ERROR
	# Grass between club and ball kills spin, so shots from the rough fly and run.
	l.backspin = float(c.spin) * (0.5 if lie == Surface.ROUGH else 1.0)
	l.sidespin = err * SIDESPIN_PER_ERROR
	_apply_setup(l, club, lie, setup)
	return l


## Tee height and ball position change how the ball comes off the club;
## setup.lie_quality (a Lie value) for how the ball is sitting.
static func _apply_setup(l: BallPhysics.Launch, club: int, lie: int, setup: Dictionary) -> void:
	var wood := club <= 2
	if setup.has("lie_quality"):
		Lie.apply(l, int(setup.lie_quality))
	if lie == Surface.TEE:
		# A risk-or-control choice. Teed high, a wood is caught on the
		# upswing: a bigger, higher drive (more for the wind to work on) that
		# curves more when it's mistimed. Teed low: shorter, lower, straighter.
		# Irons barely notice.
		var step := clampi(int(setup.get("tee_height", 1)), 0, 2) - 1
		if wood:
			l.elevation += deg_to_rad(step * 2.5)
			l.backspin *= 1.0 - step * 0.12
			l.speed *= 1.0 + step * 0.025
			l.sidespin *= 1.0 + step * 0.3
		else:
			l.elevation += deg_to_rad(step * 0.4)
			l.backspin *= 1.0 - step * 0.04
	# Stance (manual p.69): an open stance swings out-to-in, starting the ball
	# left with fade spin that curves it back right; closed is the reverse,
	# a draw. Short irons, with their backspin, barely curve.
	var stance := clampi(int(setup.get("stance", 0)), -2, 2)
	if stance != 0:
		l.heading -= stance * 0.03
		l.sidespin -= stance * (280.0 + 40.0 * club)
	match clampi(int(setup.get("ball_position", 0)), -1, 1):
		1:
			# Forward in the stance: higher and softer, a little less spin,
			# and a touch more curve on a mistimed swing.
			l.elevation += deg_to_rad(2.5)
			l.backspin *= 0.92
			l.sidespin *= 1.1
		-1:
			# Back in the stance: a low, controlled punch that spins more and
			# goes a touch shorter, under the wind or the branches.
			l.elevation -= deg_to_rad(3.5)
			l.backspin *= 1.06
			l.speed *= 0.985
			l.sidespin *= 0.85
