class_name Golfer
extends Node3D
## A lifelike golfer at the ball whose swing follows the swing meter: the
## backswing grows with the power being set, the downswing comes down to
## impact as the meter returns, and the finish plays out as the ball is struck.
##
## The body is a MakeHuman character (CC0) and the motion is real: CMU motion
## capture of a golfer's full swing and putt (subject 64), retargeted onto it
## by tools/build_golfer.py. The club is baked onto a "Club" bone; this script
## sizes it for the club in hand and tilts it to that club's lie, so the head
## sits at the ball at address. The cap carries the player's colour.
##
## Local frame: +X points at the target (the golfer's left, for a
## right-hander), +Z from the golfer towards the ball, +Y up.

const MODEL := "res://assets/golfer/golfer.glb"
const MARKERS := "res://assets/golfer/golfer.json"
## The golfer draws on its own render layer, so the game can show it through
## its own view (see golf_game.gd).
const LAYER := 1 << 2
const BALL_RADIUS := 0.021
## How far the club runs up past the Club bone, above the hands.
const BUTT := 0.1
## Club lengths in metres; the full swing was built for the 7 iron.
const LENGTHS := [1.14, 1.09, 1.07, 0.99, 0.98, 0.97, 0.95, 0.94, 0.93, 0.91, 0.9, 0.89, 0.86]
const BUILT_FOR := 0.94
## Seconds of the capture to hold at address, before the takeaway starts.
const ADDRESS_LEAD := 0.3
## The downswing blends out of a short backswing's pose over this much of it.
const BLEND := 0.25
## How much bigger than the captured stroke a full-power putt is.
const PUTT_SCALE := 5.0
## How long either side of impact the club is steered onto the ball.
const FIX_WIDTH := 0.1
## How far moving the ball back or forward in the stance moves it along the
## golfer's feet.
const BALL_SHIFT := 0.08
## Body turn per step of stance, open (-) to closed (+).
const STANCE_TURN := deg_to_rad(4.0)

var _model: Node3D
var _skeleton: Skeleton3D
var _club_bone := -1
var _club: Node3D
var _shaft: MeshInstance3D
var _head: MeshInstance3D
var _grip: MeshInstance3D
var _cap: StandardMaterial3D
var _markers := {}
var _anims := {}
## Bone index → [position track or -1, rotation track or -1], per animation.
var _tracks := {}

var _putter := false
var _stroke := "swing"
var _anim: Animation
var _m := {}
var _club_length := 1.0
## The club's size and lie, relative to the Club bone.
var _club_shape := Basis.IDENTITY
## When this club's head passes the ball, and the turn that puts it exactly
## on the ball then (faded in and out around impact).
var _impact_t := 0.0
var _fix := Quaternion.IDENTITY
var _pivot: Node3D
var _back_t := 0.0
var _back_f := 0.0
var _finish_t := -1.0
var _scale := 1.0
var _address_pose := {}


func _ready() -> void:
	if _model:
		return
	var scene: PackedScene = load(MODEL)
	_model = scene.instantiate()
	add_child(_model)
	_skeleton = _find_skeleton(_model)
	_club_bone = _skeleton.find_bone("Club")
	var player := _find_player(_model)
	for name in ["swing", "putt"]:
		var anim := player.get_animation(name)
		_anims[name] = anim
		_tracks[name] = _bone_tracks(anim)
	player.stop()
	player.active = false
	_markers = JSON.parse_string(FileAccess.get_file_as_string(MARKERS))
	_dress(_model)
	_build_club()


static func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var s := _find_skeleton(c)
		if s:
			return s
	return null


static func _find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var p := _find_player(c)
		if p:
			return p
	return null


func _bone_tracks(anim: Animation) -> Dictionary:
	var out := {}
	for i in anim.get_track_count():
		var path := anim.track_get_path(i)
		var bone := _skeleton.find_bone(path.get_concatenated_subnames())
		if bone < 0:
			continue
		var entry: Array = out.get(bone, [-1, -1])
		match anim.track_get_type(i):
			Animation.TYPE_POSITION_3D:
				entry[0] = i
			Animation.TYPE_ROTATION_3D:
				entry[1] = i
		out[bone] = entry
	return out


## Puts every mesh on the golfer's layer, and gives the cap its own material
## so it can take the player's colour.
func _dress(n: Node) -> void:
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		mi.layers = LAYER
		if "cap" in mi.name.to_lower() and mi.mesh:
			var base := mi.mesh.surface_get_material(0)
			_cap = base.duplicate() if base is StandardMaterial3D else StandardMaterial3D.new()
			mi.set_surface_override_material(0, _cap)
	for c in n.get_children():
		_dress(c)


func _build_club() -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.82, 0.83, 0.86)
	steel.metallic = 0.9
	steel.roughness = 0.3
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.08, 0.08, 0.08)
	black.roughness = 0.8
	var head := StandardMaterial3D.new()
	head.albedo_color = Color(0.25, 0.25, 0.28)
	head.metallic = 0.8
	head.roughness = 0.35
	_club = Node3D.new()
	_model.add_child(_club)
	_pivot = Node3D.new()
	_club.add_child(_pivot)
	_shaft = _part(CylinderMesh.new(), steel)
	_grip = _part(CylinderMesh.new(), black)
	_head = _part(BoxMesh.new(), head)
	var shaft: CylinderMesh = _shaft.mesh
	shaft.top_radius = 0.0065
	shaft.bottom_radius = 0.0045
	shaft.radial_segments = 8
	var grip: CylinderMesh = _grip.mesh
	grip.top_radius = 0.012
	grip.bottom_radius = 0.0095
	grip.height = 0.26
	grip.radial_segments = 8


func _part(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.layers = LAYER
	_pivot.add_child(mi)
	return mi


## Stands the golfer at the ball, aimed along heading, holding the club.
## ball_position: -1 back, 0 centre, 1 forward in the stance.
## colour: the player's colour, worn on the cap.
func address(ball: Vector3, heading: float, club: int, ball_position: int, colour: Color, stance := 0) -> void:
	_ready()
	if _cap:
		_cap.albedo_color = colour
	_putter = club == Clubs.PUTTER
	_stroke = "putt" if _putter else "swing"
	_anim = _anims[_stroke]
	_m = _markers[_stroke]
	var built: float = _m.club_length
	_club_length = built if _putter else built * LENGTHS[club] / BUILT_FOR
	_finish_t = -1.0
	_back_t = 0.0
	_back_f = 0.0
	_scale = 1.0
	_fix = Quaternion.IDENTITY
	_impact_t = _m.impact
	var address_t := maxf(float(_m.start) - ADDRESS_LEAD, 0.0)
	_address_pose = _sample(address_t)
	_apply(_address_pose, address_t)
	_fit_club(0 if _putter else ball_position)
	_aim_at_impact()

	# Stand so the club head is at the ball; the stance turns the body
	# about it.
	var d := Vector3(sin(heading), 0.0, cos(heading))
	var towards_ball := d.cross(Vector3.UP)
	var b := Basis(d, Vector3.UP, towards_ball).rotated(Vector3.UP, -STANCE_TURN * stance)
	transform = Transform3D(b, ball - b * _club_head_local())


## Sizes the club for the one in hand and tilts it, on the swing plane, to
## that club's lie: so its head sits on the ground at address.
func _fit_club(ball_position: int) -> void:
	var bone := _bone_global(_club_bone)
	var x := bone.basis.x
	var y := bone.basis.y
	var drop := BALL_RADIUS - bone.origin.y
	# Head height along the tilted shaft: L(cos t y.y - sin t x.y) = drop.
	var a := _club_length * y.y
	var bb := -_club_length * x.y
	var r := sqrt(a * a + bb * bb)
	var base := atan2(bb, a)
	var off := acos(clampf(drop / r, -1.0, 1.0))
	var tilt := base + off if absf(base + off) < absf(base - off) else base - off
	var lie := Basis(Vector3.BACK, tilt)
	# Ball forward or back in the stance: swing the head along the ground,
	# so the golfer stands that much further back or forward of the ball.
	var reach := Vector2(bone.basis.y.x, bone.basis.y.z).length() * _club_length
	var yaw := Basis.IDENTITY
	if ball_position != 0 and reach > 0.1:
		var turn := BALL_SHIFT * ball_position / reach
		yaw = bone.basis.inverse() * Basis(Vector3.UP, turn) * bone.basis
	var shape := yaw * lie
	# The grip's butt end sits just above the left hand, above the Club bone.
	_shaft.mesh.height = _club_length + BUTT
	_shaft.position = shape * Vector3(0.0, (_club_length - BUTT) * 0.5, 0.0)
	_shaft.basis = shape
	_grip.position = shape * Vector3(0.0, 0.13 - BUTT, 0.0)
	_grip.basis = shape
	var head_size := Vector3(0.075, 0.03, 0.05) if _putter else Vector3(0.08, 0.035, 0.05)
	if not _putter and _club_length > 1.05:
		head_size = Vector3(0.11, 0.06, 0.1)
	_head.mesh.size = head_size
	# The head sits at the end of the shaft, its face square to the target.
	_head.position = shape * Vector3(0.0, _club_length, 0.0)
	_head.basis = shape
	_club_shape = shape
	_pivot.basis = Basis.IDENTITY


## A bone's pose in skeleton space, composed from the local poses (always up
## to date, unlike the skeleton's cached global poses).
func _bone_global(bone: int) -> Transform3D:
	var t := _skeleton.get_bone_pose(bone)
	var parent := _skeleton.get_bone_parent(bone)
	while parent >= 0:
		t = _skeleton.get_bone_pose(parent) * t
		parent = _skeleton.get_bone_parent(parent)
	return t


func _sync_club(t: float) -> void:
	_club.transform = _skeleton.transform * _bone_global(_club_bone)
	var w := exp(-pow((t - _impact_t) / FIX_WIDTH, 2.0)) if t > -INF else 0.0
	_pivot.basis = Basis(Quaternion.IDENTITY.slerp(_fix, w))


## Finds when this club's head passes closest to the ball, and the small turn
## of the club that makes it strike the ball exactly there.
func _aim_at_impact() -> void:
	var ball := _tip()
	var impact: float = _m.impact
	var best := INF
	for i in 97:
		var t := impact - 0.08 + i * 0.16 / 96.0
		_apply(_impact_pose(t), -INF)
		var d := _tip().distance_to(ball)
		if d < best:
			best = d
			_impact_t = t
	_apply(_impact_pose(_impact_t), -INF)
	var bone := _bone_global(_club_bone)
	var want := (bone.affine_inverse() * ball).normalized()
	var have := (_club_shape * Vector3(0.0, _club_length, 0.0)).normalized()
	_fix = Quaternion(have, want)
	_apply(_address_pose, -INF)


func _impact_pose(t: float) -> Dictionary:
	return _scaled(_sample(t), 1.0) if _putter else _sample(t)


## The club head in skeleton space, without the impact turn.
func _tip() -> Vector3:
	return _bone_global(_club_bone) * (_club_shape * Vector3(0.0, _club_length, 0.0))


## Where the club head is, in the golfer's own frame.
func _club_head_local() -> Vector3:
	var bone := _bone_global(_club_bone)
	var tip := bone * (_pivot.basis * (_club_shape * Vector3(0.0, _club_length, 0.0)))
	return _model.transform * (_skeleton.transform * tip)


## Where the club head is now, in the parent's frame (for tests).
func club_head() -> Vector3:
	return transform * _club_head_local()


## Follows the swing meter: call every frame while swinging.
func follow_meter(phase: SwingMeter.Phase, value: float, power: float, delta: float) -> void:
	if _anim == null:
		return
	var start: float = _m.start
	var top: float = _m.top
	var impact := _impact_t
	var pose := {}
	var t := -INF
	match phase:
		SwingMeter.Phase.IDLE:
			if _finish_t < 0.0:
				pose = _address_pose
				t = maxf(start - ADDRESS_LEAD, 0.0)
		SwingMeter.Phase.BACKSWING:
			_back_f = clampf(value, 0.0, 1.0)
			_scale = _stroke_scale(_back_f)
			_back_t = lerpf(start, top, _back_f if not _putter else 1.0)
			t = _back_t
			pose = _sample(_back_t) if not _putter else _scaled(_sample(top), _back_f)
		SwingMeter.Phase.DOWNSWING:
			var u := clampf(1.0 - value / maxf(power, 0.01), 0.0, 1.0)
			if _putter:
				t = lerpf(top, impact, u)
				pose = _scaled(_sample(t), 1.0)
			else:
				var from := impact - (impact - top) * _back_f
				t = lerpf(from, impact, u)
				var down := _sample(t)
				var held := _sample(_back_t)
				pose = _blend(held, down, smoothstep(0.0, BLEND, u)) if _back_f < 1.0 else down
		SwingMeter.Phase.DONE:
			if _finish_t < 0.0:
				_finish_t = 0.0
	if _finish_t >= 0.0:
		_finish_t += delta
		var end: float = _m.end
		var finish: float = _m.finish
		if _putter:
			t = minf(impact + _finish_t, finish)
			pose = _scaled(_sample(t), 1.0)
		else:
			# Short shots finish short.
			var stop := lerpf(impact + (finish - impact) * 0.45, end, smoothstep(0.3, 0.9, _back_f))
			t = minf(impact + _finish_t, stop)
			pose = _sample(t)
	if not pose.is_empty():
		_apply(pose, t)


## Putts: the captured stroke is a short one, so bigger putts swing further.
func _stroke_scale(f: float) -> float:
	return lerpf(1.0, PUTT_SCALE, f) if _putter else 1.0


## Exaggerates a putting pose's movement away from address by the stroke size.
## f: how far through the backstroke (0..1) for a pose on the way back.
func _scaled(pose: Dictionary, f: float) -> Dictionary:
	var k := _scale * f
	var out := {}
	for bone in pose:
		var p: Array = pose[bone]
		var a: Array = _address_pose[bone]
		var ra: Quaternion = a[1]
		var rp: Quaternion = p[1]
		var rot := ra * _pow(ra.inverse() * rp, k)
		var pos: Vector3 = a[0] + (p[0] - a[0]) * k
		out[bone] = [pos, rot]
	return out


static func _pow(q: Quaternion, k: float) -> Quaternion:
	if q.w < 0.0:
		q = -q
	# A bone that doesn't move gives (nearly) no axis: leave it alone.
	var axis := Vector3(q.x, q.y, q.z)
	if axis.length() < 1e-5:
		return Quaternion.IDENTITY
	return Quaternion(axis.normalized(), q.get_angle() * k)


## Every animated bone's [position, rotation] at time t.
func _sample(t: float) -> Dictionary:
	var out := {}
	var tracks: Dictionary = _tracks[_stroke]
	for bone in tracks:
		var tr: Array = tracks[bone]
		var pos := _skeleton.get_bone_rest(bone).origin
		var rot := _skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
		if tr[0] >= 0:
			pos = _anim.position_track_interpolate(tr[0], t)
		if tr[1] >= 0:
			rot = _anim.rotation_track_interpolate(tr[1], t)
		out[bone] = [pos, rot]
	return out


static func _blend(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
	var out := {}
	for bone in a:
		var pa: Array = a[bone]
		var pb: Array = b[bone]
		var ra: Quaternion = pa[1]
		out[bone] = [pa[0].lerp(pb[0], w), ra.slerp(pb[1], w)]
	return out


## Poses the skeleton; t is the capture time it came from, for the club's
## impact turn (-INF for none).
func _apply(pose: Dictionary, t: float) -> void:
	for bone in pose:
		var p: Array = pose[bone]
		_skeleton.set_bone_pose_position(bone, p[0])
		_skeleton.set_bone_pose_rotation(bone, p[1])
	_sync_club(t)
