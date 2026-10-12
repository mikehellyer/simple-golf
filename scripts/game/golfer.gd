class_name Golfer
extends Node3D
## A low-poly golfer at the ball whose swing follows the swing meter: the
## backswing grows with the power being set (overswing shows), the downswing
## comes down to impact as the meter returns, and the finish plays out as the
## ball is struck. Putts are a short pendulum stroke.
##
## Local frame: +X points at the target (the golfer's left, for a
## right-hander), +Z from the golfer towards the ball, +Y up.

const ARM := 0.62
const SPINE_TILT := deg_to_rad(32.0)
const FINISH_TIME := 0.7

var _parts := {}
var _shirt := StandardMaterial3D.new()
var _putter := false
## Swing plane: a vertical-ish plane through the shoulders, containing the
## target line and the direction to the ball.
var _shoulders := Vector3.ZERO
var _ball_local := Vector3.ZERO
var _plane_normal := Vector3.ZERO
var _arm_start := Vector3.ZERO
var _club_length := 1.0
var _sign := 1.0
## Pose: arm swing angle, wrist hinge, body turn (radians).
var _arm := 0.0
var _wrist := 0.0
var _turn := 0.0
var _finish_t := -1.0
var _top := 0.0


func _ready() -> void:
	var skin := _mat(Color(0.93, 0.76, 0.62))
	var trousers := _mat(Color(0.14, 0.16, 0.28))
	var white := _mat(Color(0.95, 0.95, 0.95))
	var steel := _mat(Color(0.8, 0.8, 0.84))
	steel.metallic = 0.8
	steel.roughness = 0.3
	for side in ["l", "r"]:
		_parts["leg_" + side] = _box(trousers)
		_parts["shoe_" + side] = _box(white)
		_parts["arm_" + side] = _box(_shirt)
	_parts["hips"] = _box(trousers)
	_parts["torso"] = _box(_shirt)
	_parts["head"] = _sphere(skin, 0.11)
	_parts["cap"] = _box(white)
	_parts["hands"] = _sphere(white, 0.05)
	_parts["shaft"] = _box(steel)
	_parts["clubhead"] = _box(_mat(Color(0.12, 0.12, 0.14)))
	_shirt.albedo_color = Color(0.85, 0.15, 0.15)


## Stands the golfer at the ball, aimed along heading, holding the club.
## ball_position: -1 back, 0 centre, 1 forward in the stance.
func address(ball: Vector3, heading: float, club: int, ball_position: int, shirt: Color) -> void:
	_shirt.albedo_color = shirt.darkened(0.1) if shirt.v > 0.9 else shirt
	_putter = club == Clubs.PUTTER
	var d := Vector3(sin(heading), 0.0, cos(heading))
	var towards_ball := d.cross(Vector3.UP)
	var b := Basis(d, Vector3.UP, towards_ball)
	# Longer clubs stand further from the ball.
	var reach := 0.45 if _putter else lerpf(0.78, 0.58, float(club) / Clubs.SAND_WEDGE)
	_ball_local = Vector3(ball_position * 0.12, 0.02, reach)
	transform = Transform3D(b, ball - b * _ball_local)

	var spine := Vector3(0.0, cos(SPINE_TILT), sin(SPINE_TILT))
	_shoulders = Vector3(0.0, 0.95, 0.0) + spine * 0.55
	var to_ball := _ball_local - _shoulders
	_plane_normal = Vector3.RIGHT.cross(to_ball).normalized()
	_arm_start = to_ball.normalized()
	_club_length = to_ball.length() - ARM
	# Rotate whichever way first takes the hands away from the target.
	_sign = 1.0
	if _arm_start.rotated(_plane_normal, 0.2).x > _arm_start.x:
		_sign = -1.0
	_arm = 0.0
	_wrist = 0.0
	_turn = 0.0
	_finish_t = -1.0
	_top = 0.0
	_pose()


## Follows the swing meter: call every frame while swinging.
func follow_meter(phase: SwingMeter.Phase, value: float, power: float, delta: float) -> void:
	var full := deg_to_rad(28.0) if _putter else deg_to_rad(200.0)
	match phase:
		SwingMeter.Phase.IDLE:
			if _finish_t < 0.0:
				_arm = 0.0
				_wrist = 0.0
				_turn = 0.0
		SwingMeter.Phase.BACKSWING:
			var f := maxf(value, 0.0)
			_top = full * f
			_set_backswing(f, full)
		SwingMeter.Phase.DOWNSWING:
			# Down from the top to impact as the meter returns to the snap line.
			var u := clampf(1.0 - value / maxf(power, 0.01), 0.0, 1.0)
			var eased := u * u
			_arm = _top * (1.0 - eased)
			_wrist = (0.0 if _putter else deg_to_rad(85.0)) * clampf(1.0 - eased * 1.4, 0.0, 1.0)
			_turn = -0.42 * _arm
		SwingMeter.Phase.DONE:
			if _finish_t < 0.0:
				_finish_t = 0.0
	if _finish_t >= 0.0:
		_finish_t += delta
		var t := clampf(_finish_t / FINISH_TIME, 0.0, 1.0)
		var e := 1.0 - (1.0 - t) * (1.0 - t)
		# Through the ball to a full, balanced finish facing the target.
		# Putts follow through about as far as the backstroke went.
		var finish := maxf(_top, deg_to_rad(6.0)) * 1.1 if _putter else deg_to_rad(235.0)
		_arm = -finish * e
		_wrist = 0.0 if _putter else deg_to_rad(-55.0) * e
		_turn = 0.0 if _putter else deg_to_rad(95.0) * e
	_pose()


func _set_backswing(f: float, full: float) -> void:
	_arm = full * f
	_wrist = 0.0 if _putter else deg_to_rad(85.0) * smoothstep(0.15, 0.7, f)
	_turn = 0.0 if _putter else -0.42 * _arm


# --- Posing ------------------------------------------------------------------

func _pose() -> void:
	var yaw := Basis(Vector3.UP, _turn)
	var hips := Vector3(0.0, 0.95, 0.0)
	var spine := Vector3(0.0, cos(SPINE_TILT), sin(SPINE_TILT))
	var shoulders := hips + yaw * (spine * 0.55)
	var hip_yaw := Basis(Vector3.UP, _turn * 0.5)

	# Legs and feet, a little wider for the long clubs.
	var width := 0.13 if _putter else 0.2
	for side in [-1.0, 1.0]:
		var key := "l" if side > 0.0 else "r"
		var foot := Vector3(side * width, 0.04, 0.0)
		var hip := hips + hip_yaw * Vector3(side * 0.1, 0.0, 0.0)
		_segment(_parts["leg_" + key], hip, foot + Vector3(0, 0.04, 0), 0.13)
		_place_box(_parts["shoe_" + key], foot + Vector3(0, 0, 0.06), Vector3(0.1, 0.07, 0.26), Basis.IDENTITY)
	_place_box(_parts["hips"], hips, Vector3(0.32, 0.18, 0.2), hip_yaw)
	_segment(_parts["torso"], hips + yaw * (spine * 0.08), shoulders, 0.36, 0.2, yaw)
	var head := hips + spine * 0.78
	_place_box(_parts["head"], head, Vector3.ONE, Basis.IDENTITY)
	_place_box(_parts["cap"], head + Vector3(0, 0.08, 0.04), Vector3(0.24, 0.05, 0.28), yaw)

	# Arms and club swing round the plane through the shoulders.
	var a := _arm_start.rotated(_plane_normal, _sign * _arm)
	var hands := _shoulders + a * ARM
	var shaft := a.rotated(_plane_normal, _sign * _wrist)
	var head_pos := hands + shaft * _club_length
	for side in [-1.0, 1.0]:
		var key := "l" if side > 0.0 else "r"
		_segment(_parts["arm_" + key], shoulders + yaw * Vector3(side * 0.18, -0.02, 0.0), hands, 0.08)
	_place_box(_parts["hands"], hands, Vector3.ONE, Basis.IDENTITY)
	_segment(_parts["shaft"], hands, head_pos, 0.018)
	_place_box(_parts["clubhead"], head_pos, Vector3(0.11 if not _putter else 0.12, 0.05, 0.05),
			Basis(Vector3.UP, 0.0))


## Stretches a box between two points (local space).
func _segment(mi: MeshInstance3D, from: Vector3, to: Vector3, thickness: float, depth := -1.0,
		twist := Basis.IDENTITY) -> void:
	var dir := to - from
	var length := dir.length()
	if length < 0.001:
		return
	var y := dir / length
	var x := (twist * Vector3.RIGHT)
	if absf(x.dot(y)) > 0.95:
		x = Vector3.FORWARD
	var z := x.cross(y).normalized()
	x = y.cross(z).normalized()
	mi.transform = Transform3D(Basis(x * thickness, y * length, z * (depth if depth > 0.0 else thickness)),
			(from + to) * 0.5)


func _place_box(mi: MeshInstance3D, at: Vector3, size: Vector3, basis: Basis) -> void:
	mi.transform = Transform3D(basis.scaled(size), at)


func _box(mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	return mi


func _sphere(mat: Material, r: float) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	return mi


static func _mat(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.85
	return m
