class_name BallPhysics
extends RefCounted
## Deterministic golf-ball flight, bounce and roll. Units are metres and
## seconds, Y is up.
##
## A shot is fully determined by its Launch, the wind and the course, so in
## multiplayer only the launch needs to be shared: every client re-runs the
## same simulation and plays back the resulting path.
##
## The course is duck-typed (see Hole and FlatCourse): height_at, normal_at,
## surface_at, is_in_bounds, trees_near, plus `pin` and `tree_top`.

enum Outcome { REST, HOLED, WATER, OUT_OF_BOUNDS }
## Things that happen during a shot, for sound and commentary.
enum Event { BOUNCE, TREE, CUP_LIP, HOLED, WATER, OUT_OF_BOUNDS }

const DT := 1.0 / 240.0
const SAMPLE_RATE := 60.0
const SAMPLE_EVERY := 4
const GRAVITY := 9.81
const BALL_RADIUS := 0.02134
## 0.5 * air density * cross-section area / ball mass.
const K_AIR := 0.5 * 1.225 * PI * BALL_RADIUS * BALL_RADIUS / 0.04593
const CD_BASE := 0.22
const CD_SPIN := 0.3
const CL_SLOPE := 1.4
const CL_MAX := 0.3
const SPIN_DECAY := 0.04
const RPM_TO_RAD := TAU / 60.0
## A rolling solid sphere feels 5/7 of the slope's pull.
const ROLL_FACTOR := 5.0 / 7.0
const CUP_RADIUS := 0.054
const MAX_CAPTURE_SPEED := 1.6
const MIN_BOUNCE := 0.8
const STOP_SPEED := 0.05
const MAX_TIME := 45.0
## Tree trunk radius and height as fractions of the canopy radius.
const TRUNK_RADIUS := 0.07
const TRUNK_HEIGHT := 1.3


class Launch:
	var position := Vector3.ZERO
	## Ball speed in m/s.
	var speed := 0.0
	## Radians above horizontal. Zero means a putt: the ball starts rolling.
	var elevation := 0.0
	## Radians; 0 plays along +Z, positive turns to the golfer's left (+X).
	var heading := 0.0
	## rpm
	var backspin := 0.0
	## rpm; positive curves right (slice), negative curves left (hook).
	var sidespin := 0.0


class Result:
	## Ball positions sampled at SAMPLE_RATE, for playback.
	var path := PackedVector3Array()
	var outcome := Outcome.REST
	var rest := Vector3.ZERO
	var carry := 0.0
	var apex := 0.0
	## Last on-course ground position before the ball reached a hazard.
	var last_safe := Vector3.ZERO
	## {time, kind: Event, surface, strength (impact speed m/s)}, in time order.
	var events: Array[Dictionary] = []

	func add_event(time: float, kind: Event, surface: int, strength: float) -> void:
		events.append({time = time, kind = kind, surface = surface, strength = strength})


## Mutable ball state shared by the step helpers.
class _Ball:
	var pos: Vector3
	var vel: Vector3
	var spin: Vector3


static func simulate(launch: Launch, course, wind := Vector3.ZERO) -> Result:
	var r := Result.new()
	var start := launch.position
	var dir := Vector3(sin(launch.heading), 0.0, cos(launch.heading))
	var b := _Ball.new()
	b.pos = start
	b.vel = dir * (cos(launch.elevation) * launch.speed) \
			+ Vector3.UP * (sin(launch.elevation) * launch.speed)
	b.spin = dir.cross(Vector3.UP) * (launch.backspin * RPM_TO_RAD) \
			+ Vector3.DOWN * (launch.sidespin * RPM_TO_RAD)
	var pin: Vector3 = course.pin
	var tree_top: float = course.tree_top
	var rolling := launch.elevation <= 0.0
	var landed := rolling
	var outcome := -1
	var lipped := false
	r.apex = start.y
	r.last_safe = start
	r.path.append(b.pos)

	var max_steps := int(MAX_TIME / DT)
	for step in range(1, max_steps + 1):
		var time := step * DT
		if rolling:
			var n: Vector3 = course.normal_at(b.pos.x, b.pos.z)
			var surf: int = course.surface_at(b.pos.x, b.pos.z)
			var h := Vector2(b.vel.x, b.vel.z)
			var speed := h.length()
			var pull := Vector2(n.x, n.z) * (GRAVITY * ROLL_FACTOR)
			var decel: float = Surface.ROLL_DECEL[surf]
			var held := pull.length() <= decel
			if speed < STOP_SPEED and held:
				outcome = Outcome.REST
				break
			var nh := h + pull * DT
			if speed > 0.0:
				nh -= h / speed * (decel * DT)
				# Friction alone must never push the ball backwards.
				if held and nh.dot(h) <= 0.0:
					outcome = Outcome.REST
					break
			b.pos.x += nh.x * DT
			b.pos.z += nh.y * DT
			b.pos.y = course.height_at(b.pos.x, b.pos.z)
			b.vel = Vector3(nh.x, 0.0, nh.y)
			if _hit_trunks(course, b):
				r.add_event(time, Event.TREE, surf, speed)
			var over_cup := _over_cup(b.pos, pin, CUP_RADIUS)
			if over_cup and nh.length() < MAX_CAPTURE_SPEED:
				b.pos = pin
				outcome = Outcome.HOLED
				r.add_event(time, Event.HOLED, Surface.GREEN, nh.length())
				break
			if over_cup and not lipped:
				lipped = true
				r.add_event(time, Event.CUP_LIP, Surface.GREEN, nh.length())
			var hazard := _hazard(course, b.pos)
			if hazard >= 0:
				outcome = hazard
				r.add_event(time, _hazard_event(hazard), surf, speed)
				break
			r.last_safe = b.pos
		else:
			var ground: float = course.height_at(b.pos.x, b.pos.z)
			# Wind is weaker close to the ground.
			var rel := b.vel - wind * clampf((b.pos.y - ground) / 10.0, 0.3, 1.0)
			var air_speed := rel.length()
			var acc := Vector3(0.0, -GRAVITY, 0.0)
			if air_speed > 0.01:
				var w := b.spin.length()
				var s := BALL_RADIUS * w / air_speed
				acc -= rel * (K_AIR * (CD_BASE + CD_SPIN * s) * air_speed)
				if w > 1.0:
					var cl := minf(CL_SLOPE * s, CL_MAX)
					acc += b.spin.cross(rel).normalized() * (K_AIR * cl * air_speed * air_speed)
			b.vel += acc * DT
			b.pos += b.vel * DT
			b.spin *= 1.0 - SPIN_DECAY * DT
			r.apex = maxf(r.apex, b.pos.y)

			if b.pos.y < tree_top:
				var hit_speed := b.vel.length()
				if _hit_canopies(course, b) or _hit_trunks(course, b):
					r.add_event(time, Event.TREE, Surface.ROUGH, hit_speed)

			ground = course.height_at(b.pos.x, b.pos.z)
			if b.pos.y <= ground:
				b.pos.y = ground
				var surf: int = course.surface_at(b.pos.x, b.pos.z)
				var hazard := _hazard(course, b.pos)
				if hazard >= 0:
					outcome = hazard
					r.add_event(time, _hazard_event(hazard), surf, b.vel.length())
					break
				if not landed:
					landed = true
					r.carry = Vector2(b.pos.x - start.x, b.pos.z - start.z).length()
				if _over_cup(b.pos, pin, CUP_RADIUS * 1.5) and Vector2(b.vel.x, b.vel.z).length() < 6.0:
					b.pos = pin
					outcome = Outcome.HOLED
					r.add_event(time, Event.HOLED, surf, b.vel.length())
					break
				var n: Vector3 = course.normal_at(b.pos.x, b.pos.z)
				var vn := b.vel.dot(n)
				if vn < 0.0:
					r.add_event(time, Event.BOUNCE, surf, -vn)
					var e: float = Surface.RESTITUTION[surf]
					var vt := b.vel - n * vn
					var vt_len := vt.length()
					if vt_len > 0.001:
						var vt_dir := vt / vt_len
						var backspin := maxf(b.spin.dot(vt_dir.cross(n)), 0.0)
						var friction: float = Surface.FRICTION[surf]
						var grip: float = Surface.SPIN_GRIP[surf]
						var new_len := vt_len - friction * (1.0 + e) * -vn \
								- backspin * BALL_RADIUS * grip
						# Lots of backspin can pull the ball back a little.
						vt = vt_dir * maxf(new_len, -1.5)
					b.spin *= 0.4
					var bounce := -vn * e
					if bounce < MIN_BOUNCE:
						rolling = true
						b.vel = Vector3(vt.x, 0.0, vt.z)
					else:
						b.vel = vt + n * bounce
				r.last_safe = b.pos

		if step % SAMPLE_EVERY == 0:
			r.path.append(b.pos)

	r.outcome = Outcome.REST if outcome < 0 else outcome
	r.rest = b.pos
	r.path.append(b.pos)
	if not landed:
		r.carry = Vector2(b.pos.x - start.x, b.pos.z - start.z).length()
	return r


## Canopies are spheres of radius t.w centred two radii above the tree's base.
static func _hit_canopies(course, b: _Ball) -> bool:
	var hit := false
	var trees: Array[Vector4] = course.trees_near(b.pos.x, b.pos.z)
	for t in trees:
		var c := Vector3(t.x, t.y + t.w * 2.0, t.z)
		var d := b.pos - c
		if d.length_squared() < t.w * t.w:
			var n := d.normalized()
			var vn := b.vel.dot(n)
			if vn < 0.0:
				b.vel -= n * (vn * 1.3)
			b.vel *= 0.35
			b.spin *= 0.3
			b.pos = c + n * t.w
			hit = true
	return hit


## Trunks are vertical cylinders; the ball rebounds off them fairly hard.
static func _hit_trunks(course, b: _Ball) -> bool:
	var hit := false
	var trees: Array[Vector4] = course.trees_near(b.pos.x, b.pos.z)
	for t in trees:
		if b.pos.y < t.y - 0.5 or b.pos.y > t.y + t.w * TRUNK_HEIGHT:
			continue
		var d := Vector2(b.pos.x - t.x, b.pos.z - t.z)
		var radius := t.w * TRUNK_RADIUS + BALL_RADIUS
		if d.length_squared() < radius * radius:
			var n2 := d.normalized() if d.length() > 0.0001 else Vector2(1.0, 0.0)
			var n := Vector3(n2.x, 0.0, n2.y)
			var vn := b.vel.dot(n)
			if vn < 0.0:
				b.vel -= n * (vn * 1.5)
			b.vel *= 0.7
			b.spin *= 0.5
			b.pos.x = t.x + n2.x * radius
			b.pos.z = t.z + n2.y * radius
			hit = true
	return hit


static func _over_cup(pos: Vector3, pin: Vector3, radius: float) -> bool:
	return Vector2(pos.x - pin.x, pos.z - pin.z).length() < radius


static func _hazard(course, pos: Vector3) -> int:
	if not course.is_in_bounds(pos.x, pos.z):
		return Outcome.OUT_OF_BOUNDS
	if course.surface_at(pos.x, pos.z) == Surface.WATER:
		return Outcome.WATER
	return -1


static func _hazard_event(outcome: int) -> Event:
	return Event.WATER if outcome == Outcome.WATER else Event.OUT_OF_BOUNDS
