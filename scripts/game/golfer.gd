class_name Golfer
extends Node3D
## A golfer at the ball whose swing follows the swing meter: the backswing
## grows with the power being set (overswing shows), the downswing comes down
## to impact as the meter returns, and the finish plays out as the ball is
## struck. Putts are a short pendulum stroke.
##
## Dressed like MicroProse Golf's golfer: a red long-sleeved jumper with a
## white collar, dark navy trousers, white shoes, a white glove and a cap.
## The cap carries the player's colour so players can tell whose turn it is
## (player 1's is white, exactly as in the original).
##
## Built from rounded parts (capsules and spheres) with real joints: arms
## bend at the elbows (solved each frame so both hands stay on the grip),
## legs flex at the knees, and the body turns through the swing.
##
## Local frame: +X points at the target (the golfer's left, for a
## right-hander), +Z from the golfer towards the ball, +Y up.

const UPPER_ARM := 0.3
const FOREARM := 0.29
const THIGH := 0.46
const SHIN := 0.45
const HIP_HEIGHT := 0.93
const SPINE := 0.52
const SPINE_TILT := deg_to_rad(30.0)
const FINISH_TIME := 0.7
## Distance from the middle of the shoulders to the hands along the swing.
const ARM := 0.56

var _parts := {}
## The classic red jumper, and the cap in the player's colour.
const JUMPER := Color(0.78, 0.1, 0.1)
var _shirt := StandardMaterial3D.new()
var _cap := StandardMaterial3D.new()
var _putter := false
var _shoulders := Vector3.ZERO
var _ball_local := Vector3.ZERO
var _plane_normal := Vector3.ZERO
var _arm_start := Vector3.ZERO
var _club_length := 1.0
var _sign := 1.0
var _arm := 0.0
var _wrist := 0.0
var _turn := 0.0
var _finish_t := -1.0
var _top := 0.0
## -2 open .. 2 closed: moves a foot back from the line, as the stance does.
var _stance := 0


func _ready() -> void:
	var skin := _mat(Color(0.93, 0.72, 0.58))
	var trousers := _mat(Color(0.13, 0.12, 0.32))
	var shoes := _mat(Color(0.97, 0.97, 0.97))
	var glove := _mat(Color(0.98, 0.98, 0.98))
	var collar := _mat(Color(0.97, 0.97, 0.97))
	var cap := _cap
	cap.roughness = 0.85
	cap.albedo_color = Color(0.96, 0.96, 0.96)
	var hair := _mat(Color(0.32, 0.22, 0.13))
	var steel := _mat(Color(0.82, 0.82, 0.86))
	steel.metallic = 0.85
	steel.roughness = 0.25
	var grip := _mat(Color(0.1, 0.1, 0.1))
	for side in ["l", "r"]:
		# Slacks: full in the thigh, tapering to the ankle.
		_parts["thigh_" + side] = _capsule(trousers, 0.095)
		_parts["shin_" + side] = _capsule(trousers, 0.075)
		_parts["shoe_" + side] = _capsule(shoes, 0.058)
		# Long sleeves: the jumper runs down to the wrist.
		_parts["upper_arm_" + side] = _capsule(_shirt, 0.068)
		_parts["forearm_" + side] = _capsule(_shirt, 0.055)
		_parts["wrist_" + side] = _sphere(skin, 0.035)
	_parts["pelvis"] = _capsule(trousers, 0.16)
	_parts["torso"] = _capsule(_shirt, 0.19)
	_parts["chest"] = _capsule(_shirt, 0.085)
	_parts["neck"] = _capsule(skin, 0.05)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.045
	ring.outer_radius = 0.075
	_parts["collar"] = MeshInstance3D.new()
	_parts["collar"].mesh = ring
	_parts["collar"].material_override = collar
	add_child(_parts["collar"])
	_parts["head"] = _sphere(skin, 0.105)
	_parts["hair"] = _sphere(hair, 0.1)
	_parts["cap"] = _sphere(cap, 0.11)
	_parts["brim"] = _box(cap)
	_parts["hands"] = _sphere(glove, 0.05)
	_parts["grip"] = _capsule(grip, 0.016)
	_parts["shaft"] = _capsule(steel, 0.009)
	_parts["clubhead"] = _box(_mat(Color(0.14, 0.14, 0.16)))
	_shirt.albedo_color = JUMPER
	_shirt.roughness = 0.95


## Stands the golfer at the ball, aimed along heading, holding the club.
## ball_position: -1 back, 0 centre, 1 forward in the stance.
## colour: the player's colour, worn on the cap.
func address(ball: Vector3, heading: float, club: int, ball_position: int, colour: Color, stance := 0) -> void:
	_stance = stance
	_cap.albedo_color = colour.darkened(0.04) if colour.v > 0.9 else colour
	_putter = club == Clubs.PUTTER
	var d := Vector3(sin(heading), 0.0, cos(heading))
	var towards_ball := d.cross(Vector3.UP)
	var b := Basis(d, Vector3.UP, towards_ball)
	# Longer clubs stand further from the ball.
	var reach := 0.45 if _putter else lerpf(0.78, 0.58, float(club) / Clubs.SAND_WEDGE)
	_ball_local = Vector3(ball_position * 0.12, 0.02, reach)
	transform = Transform3D(b, ball - b * _ball_local)

	var spine := Vector3(0.0, cos(SPINE_TILT), sin(SPINE_TILT))
	_shoulders = Vector3(0.0, HIP_HEIGHT, 0.0) + spine * SPINE
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
			_arm = full * f
			_wrist = 0.0 if _putter else deg_to_rad(85.0) * smoothstep(0.15, 0.7, f)
			_turn = 0.0 if _putter else -0.42 * _arm
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
		# Putts follow through about as far as the backstroke went.
		var finish := maxf(_top, deg_to_rad(6.0)) * 1.1 if _putter else deg_to_rad(235.0)
		_arm = -finish * e
		_wrist = 0.0 if _putter else deg_to_rad(-55.0) * e
		_turn = 0.0 if _putter else deg_to_rad(95.0) * e
	_pose()


# --- Posing ------------------------------------------------------------------

func _pose() -> void:
	var yaw := Basis(Vector3.UP, _turn)
	var hip_yaw := Basis(Vector3.UP, _turn * 0.45)
	var hips := Vector3(0.0, HIP_HEIGHT, 0.0)
	var spine := Vector3(0.0, cos(SPINE_TILT), sin(SPINE_TILT))
	var chest := hips + yaw * (spine * SPINE)
	var neck_top := hips + spine * (SPINE + 0.13)

	# Legs: hips to feet with the knees flexed forward towards the ball.
	var width := 0.13 if _putter else 0.19
	for side in [-1.0, 1.0]:
		var key := "l" if side > 0.0 else "r"
		var hip := hips + hip_yaw * Vector3(side * 0.1, -0.05, 0.0)
		var ankle := Vector3(side * width, 0.09, 0.02)
		# Open: the front (left) foot drops back; closed: the back foot does.
		if (side > 0.0 and _stance < 0) or (side < 0.0 and _stance > 0):
			ankle.z -= absi(_stance) * 0.07
		# On the follow-through the trail knee (right) turns in towards the target.
		var pole := Vector3(0.0, 0.0, 1.0)
		if side < 0.0 and _turn > 0.0:
			pole = pole.lerp(Vector3(1.0, 0.0, 0.6), clampf(_turn / 1.6, 0.0, 1.0))
		var knee := _ik(hip, ankle, THIGH, SHIN, pole)
		_limb(_parts["thigh_" + key], hip, knee)
		_limb(_parts["shin_" + key], knee, ankle)
		_limb(_parts["shoe_" + key], ankle + Vector3(0, -0.04, -0.05), ankle + Vector3(side * 0.02, -0.04, 0.16))

	# Body: pelvis across the hips, torso and chest up the tilted spine.
	_limb(_parts["pelvis"], hips + hip_yaw * Vector3(-0.11, 0, 0), hips + hip_yaw * Vector3(0.11, 0, 0))
	_limb(_parts["torso"], hips + spine * 0.05, hips + yaw * (spine * (SPINE * 0.8)), 1.2)
	var l_shoulder := chest + yaw * Vector3(0.17, -0.04, 0.0)
	var r_shoulder := chest + yaw * Vector3(-0.17, -0.04, 0.0)
	# Shoulders: a slim bar tucked into the top of the torso.
	_limb(_parts["chest"], r_shoulder.lerp(l_shoulder, 0.08), l_shoulder.lerp(r_shoulder, 0.08))
	_limb(_parts["neck"], chest, neck_top)
	# The white collar of the shirt under the jumper, round the base of the neck.
	var up := (neck_top - chest).normalized()
	var neck_base := chest.lerp(neck_top, 0.3)
	_parts["collar"].transform = Transform3D(Basis(Quaternion(Vector3.UP, up)), neck_base)
	var head := neck_top + spine * 0.1 + Vector3(0, 0.04, 0)
	_place(_parts["head"], head)
	_place(_parts["hair"], head + Vector3(0, -0.01, -0.03))
	# The cap: a flattened crown and a brim towards the ball (eyes on the ball).
	_parts["cap"].transform = Transform3D(Basis.from_scale(Vector3(1.0, 0.55, 1.0)), head + Vector3(0, 0.05, 0))
	_parts["brim"].transform = Transform3D(Basis(Vector3.RIGHT, -0.35).scaled(Vector3(0.18, 0.015, 0.13)),
			head + Vector3(0, 0.05, 0.12))

	# Arms and club swing round the plane through the shoulders.
	var a := _arm_start.rotated(_plane_normal, _sign * _arm)
	var hands := _shoulders + a * ARM
	var shaft := a.rotated(_plane_normal, _sign * _wrist)
	var head_pos := hands + shaft * _club_length
	for side in [-1.0, 1.0]:
		var key := "l" if side > 0.0 else "r"
		var shoulder := l_shoulder if side > 0.0 else r_shoulder
		# Elbows point down and slightly out from the body.
		var elbow := _ik(shoulder, hands, UPPER_ARM, FOREARM, Vector3(side * 0.6, -1.0, 0.2))
		_limb(_parts["upper_arm_" + key], shoulder, elbow)
		# Sleeve to just short of the glove, with a little skin at the wrist.
		var wrist := elbow.lerp(hands, 0.86)
		_limb(_parts["forearm_" + key], elbow, wrist)
		_place(_parts["wrist_" + key], wrist.lerp(hands, 0.5))
	_place(_parts["hands"], hands)
	_limb(_parts["grip"], hands - shaft * 0.04, hands + shaft * 0.16)
	_limb(_parts["shaft"], hands, head_pos)
	_parts["clubhead"].transform = Transform3D(Basis.from_scale(Vector3(0.11 if not _putter else 0.12, 0.05, 0.05)), head_pos)


## Two-bone joint: where the elbow or knee goes for a limb from `root` to
## `end` with the given segment lengths, bending towards `pole`.
static func _ik(root: Vector3, end: Vector3, a: float, b: float, pole: Vector3) -> Vector3:
	var d := end - root
	var dist := clampf(d.length(), 0.001, a + b - 0.001)
	var dir := d.normalized()
	# Distance along root→end to the joint, and how far it sits off that line.
	var x := (a * a - b * b + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(a * a - x * x, 0.0))
	var bend := pole - dir * pole.dot(dir)
	if bend.length() < 0.001:
		bend = dir.cross(Vector3.UP)
	return root + dir * x + bend.normalized() * h


## Stretches a capsule part between two points (local space).
func _limb(mi: MeshInstance3D, from: Vector3, to: Vector3, girth := 1.0) -> void:
	var dir := to - from
	var length := dir.length()
	if length < 0.001:
		return
	var y := dir / length
	var x := Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var z := x.cross(y).normalized()
	x = y.cross(z).normalized()
	var r: float = mi.get_meta("radius")
	# The capsule mesh is radius r and height 2r; stretch its length only.
	var stretch := (length + 2.0 * r) / (2.0 * r)
	mi.transform = Transform3D(Basis(x * girth, y * stretch, z), (from + to) * 0.5)


func _place(mi: MeshInstance3D, at: Vector3) -> void:
	mi.transform = Transform3D(Basis.IDENTITY, at)


func _capsule(mat: Material, r: float) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	mesh.radial_segments = 12
	mesh.rings = 4
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.set_meta("radius", r)
	add_child(mi)
	return mi


func _sphere(mat: Material, r: float) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	return mi


func _box(mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	return mi


static func _mat(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.8
	return m
