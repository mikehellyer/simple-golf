extends Node3D
## Game loop: one player, 18 procedurally generated holes.
##
## Controls: Left/Right aim (Shift for fine), Up/Down club, Space or left
## click to swing, M overhead map, R re-aim at the pin, Tab scorecard,
## G green slope grid, N sound on/off, F fullscreen, Esc cancels a swing,
## U opens the download page when an update exists.
## Run with `-- --demo` for an attract mode where the computer plays.

enum State { FLYBY, AIM, SWING, FLIGHT, RESULT, HOLE_DONE, ROUND_DONE }

const YARDS := 1.09361
const FEET := 3.28084
const MPH := 2.23694
const AIM_RATE := 0.5
const FLYBY_TIME := 5.0
const RESULT_TIME := 2.0
const MAX_STROKES := 12
const MAX_WIND := 9.0
const MAP_LAYER := 2
const HOLES_PER_ROUND := 18

var round_seed := 0
var hole: Hole
var card: Scorecard
var strokes := 0
var ball_pos := Vector3.ZERO
var lie := Surface.TEE
var club := Clubs.DRIVER
var heading := 0.0
var wind := Vector3.ZERO
var state := State.FLYBY
var state_time := 0.0

var _holes: Array[Hole] = []
var _view: CourseView
var _sfx: Sfx
var _event_index := 0
var _show_grid := true
var _hud: Hud
var _camera: Camera3D
var _map_camera: Camera3D
var _ball: MeshInstance3D
var _marker: MeshInstance3D
var _aim_line: MeshInstance3D
var _trail: MeshInstance3D
var _map_ball: MeshInstance3D
var _map_pin: MeshInstance3D
var _map_target: MeshInstance3D
var _shot: BallPhysics.Result
var _shot_start := Vector3.ZERO
var _playback := 0.0
var _landing_cam := false
var _cam_target := Vector3.ZERO
var _cam_look := Vector3.ZERO
var _look_now := Vector3.ZERO
var _putt_speed := 0.0
var _holed := false
var _update_url := ""
var _demo := "--demo" in OS.get_cmdline_user_args()


func _ready() -> void:
	_build_world()
	_hud = Hud.new()
	add_child(_hud)
	_hud.meter.swing_finished.connect(_on_swing_finished)
	_hud.meter.clicked.connect(func() -> void: _sfx.play("tick", -6.0))
	_sfx = Sfx.new()
	add_child(_sfx)
	Updater.update_available.connect(_on_update_available)
	randomize()
	_start_round(randi())


# --- Round and hole flow ---------------------------------------------------

func _start_round(seed_value: int) -> void:
	round_seed = seed_value
	_holes.clear()
	var pars := PackedInt32Array()
	var yards := PackedInt32Array()
	for n in range(1, HOLES_PER_ROUND + 1):
		var h := Hole.new(n, _hole_seed(n))
		_holes.append(h)
		pars.append(h.par)
		yards.append(roundi(h.yardage() * YARDS))
	card = Scorecard.new(pars, yards)
	_start_hole(1)


func _hole_seed(number: int) -> int:
	return round_seed * 31 + number * 7919


func _start_hole(number: int) -> void:
	if _view:
		_view.queue_free()
	hole = _holes[number - 1]
	_view = CourseView.new()
	_view.build(hole)
	add_child(_view)

	var rng := RandomNumberGenerator.new()
	rng.seed = _hole_seed(number) + 99
	var wind_angle := rng.randf() * TAU
	wind = Vector3(sin(wind_angle), 0.0, cos(wind_angle)) * rng.randf_range(0.0, MAX_WIND)

	strokes = 0
	_holed = false
	ball_pos = hole.tee
	lie = Surface.TEE
	_sfx.set_ambience(wind.length())
	_hud.scorecard.visible = false
	_setup_map_camera()
	_prepare_shot()
	_set_state(State.FLYBY)
	_hud.show_message("Hole %d\nPar %d  ·  %d yards" % [hole.number, hole.par, roundi(hole.yardage() * YARDS)])


func _prepare_shot() -> void:
	var dist := _flat(hole.pin - ball_pos).length()
	club = _pick_club(dist)
	_putt_speed = Clubs.putt_speed_for(maxf(dist * 1.25, 2.0))
	heading = _default_heading()
	_ball.position = ball_pos
	_update_aim()
	_update_hud()


func _on_swing_finished(power: float, accuracy: float) -> void:
	strokes += 1
	_shot_start = ball_pos
	var launch := Clubs.launch_for(club, ball_pos, heading, power, accuracy, lie, _putt_speed)
	_shot = BallPhysics.simulate(launch, hole, wind)
	_play_strike(power)
	_event_index = 0
	_playback = 0.0
	_landing_cam = false
	_set_state(State.FLIGHT)


func _play_strike(power: float) -> void:
	var loud := linear_to_db(clampf(power, 0.25, 1.1))
	if club == Clubs.PUTTER:
		_sfx.play("putt", loud - 4.0)
		return
	_sfx.play("swing", loud - 10.0, randf_range(0.95, 1.05))
	if lie == Surface.BUNKER:
		_sfx.play("bunker", loud)
	_sfx.play("hit_wood" if club <= 2 else "hit_iron", loud - 4.0, randf_range(0.97, 1.03))


func _play_shot_events() -> void:
	while _event_index < _shot.events.size() and _shot.events[_event_index].time <= _playback:
		var e: Dictionary = _shot.events[_event_index]
		_event_index += 1
		var loud := linear_to_db(clampf(e.strength / 15.0, 0.12, 1.0))
		match e.kind:
			BallPhysics.Event.BOUNCE:
				match e.surface:
					Surface.GREEN, Surface.FRINGE:
						_sfx.play("bounce_green", loud)
					Surface.BUNKER:
						_sfx.play("bunker", loud)
					_:
						_sfx.play("bounce_grass", loud)
			BallPhysics.Event.TREE:
				_sfx.play("tree", loud + 3.0)
			BallPhysics.Event.CUP_LIP:
				_sfx.play("lip", -4.0)
			BallPhysics.Event.HOLED:
				_sfx.play("cup")
			BallPhysics.Event.WATER:
				_sfx.play("splash")


func _finish_shot() -> void:
	var msg := ""
	match _shot.outcome:
		BallPhysics.Outcome.HOLED:
			_holed = true
			ball_pos = hole.pin
			msg = "HOLE IN ONE!" if strokes == 1 else "In the hole!"
		BallPhysics.Outcome.WATER:
			strokes += 1
			ball_pos = _drop_point()
			lie = hole.surface_at(ball_pos.x, ball_pos.z)
			msg = "Splash!\nOne stroke penalty — ball dropped"
		BallPhysics.Outcome.OUT_OF_BOUNDS:
			strokes += 1
			ball_pos = _shot_start
			msg = "Out of bounds\nStroke and distance"
		_:
			ball_pos = _shot.rest
			lie = hole.surface_at(ball_pos.x, ball_pos.z)
			msg = Surface.NAMES[lie]
			if club != Clubs.PUTTER:
				msg += "\ncarried %d yds" % roundi(_shot.carry * YARDS)
			elif lie == Surface.GREEN:
				msg = "%d ft to go" % ceili(_flat(hole.pin - ball_pos).length() * FEET)
	if not _holed and strokes >= MAX_STROKES:
		_holed = true
		msg += "\nPicked up"
	_ball.position = ball_pos
	_hud.show_message(msg)
	_set_state(State.RESULT)


func _after_result() -> void:
	if _holed:
		card.record(strokes)
		var diff := strokes - hole.par
		if diff < 0 or strokes == 1:
			_sfx.play("applause")
		elif diff == 0:
			_sfx.play("polite", -4.0)
		_hud.show_message("")
		_hud.set_shot_info("Holed in %d   ·   Round %s" % [strokes, card.to_par_text()])
		_hud.scorecard.show_card(card, hole.number, "%s — %d on the par %d %s" % [
				Scorecard.score_name(strokes, hole.par), strokes, hole.par, _ordinal(hole.number)])
		_set_state(State.HOLE_DONE)
	else:
		_hud.show_message("")
		_prepare_shot()
		_set_state(State.AIM)


func _next_hole() -> void:
	if hole.number < HOLES_PER_ROUND:
		_start_hole(hole.number + 1)
		return
	_hud.scorecard.show_card(card, 0, "Round complete — %d (%s)" % [card.total(), card.to_par_text()])
	_set_state(State.ROUND_DONE)


func _set_state(s: State) -> void:
	state = s
	state_time = 0.0
	var aiming := s == State.AIM or s == State.SWING
	_marker.visible = aiming
	_aim_line.visible = aiming
	_map_target.visible = aiming
	_trail.visible = s == State.FLIGHT or s == State.RESULT
	_hud.set_meter_visible(aiming or s == State.FLIGHT)
	_update_green_grid()
	if s == State.AIM or s == State.FLYBY:
		_hud.scorecard.visible = false
	match s:
		State.FLYBY:
			_hud.set_hint("Space: skip fly-by")
		State.AIM:
			_hud.meter.reset()
			_hud.set_hint("←/→ aim  ·  ↑/↓ club  ·  Space swing  ·  M map  ·  Tab card  ·  G slopes  ·  N sound")
		State.SWING:
			_hud.set_hint("Space: set power, then again on the white line")
		State.FLIGHT:
			_hud.set_hint("Space: skip")
		State.RESULT:
			_hud.set_hint("")
		State.HOLE_DONE:
			_hud.set_hint("Space: next hole" if hole.number < HOLES_PER_ROUND else "Space: finish round")
		State.ROUND_DONE:
			_hud.set_hint("Space: new round")


# --- Input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_action()
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			_action()
		KEY_UP:
			_change_club(-1)
		KEY_DOWN:
			_change_club(1)
		KEY_M:
			if _map_camera.current:
				_camera.make_current()
			else:
				_map_camera.make_current()
		KEY_R:
			if state == State.AIM:
				heading = _heading_to(hole.pin)
				_update_aim()
				_update_hud()
		KEY_F:
			var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full
					else DisplayServer.WINDOW_MODE_FULLSCREEN)
		KEY_U:
			if _update_url != "":
				OS.shell_open(_update_url)
		KEY_TAB:
			if state != State.HOLE_DONE and state != State.ROUND_DONE:
				if _hud.scorecard.visible:
					_hud.scorecard.visible = false
				else:
					_hud.scorecard.show_card(card, hole.number)
		KEY_G:
			_show_grid = not _show_grid
			_update_green_grid()
		KEY_N:
			_hud.show_message("Sound off" if _sfx.toggle_mute() else "Sound on")
		KEY_ESCAPE:
			if state == State.SWING:
				_set_state(State.AIM)


func _action() -> void:
	match state:
		State.FLYBY:
			_set_state(State.AIM)
			_hud.show_message("")
		State.AIM:
			_set_state(State.SWING)
			_hud.meter.click()
		State.SWING:
			_hud.meter.click()
		State.FLIGHT:
			# Skip ahead, keeping only the final sound (cup, splash...).
			_event_index = maxi(_event_index, _shot.events.size() - 1)
			_playback = INF
		State.RESULT:
			state_time = RESULT_TIME
		State.HOLE_DONE:
			_next_hole()
		State.ROUND_DONE:
			_start_round(randi())


func _change_club(step: int) -> void:
	if state != State.AIM:
		return
	var first := Clubs.DRIVER if lie == Surface.TEE else Clubs.DRIVER + 1
	club = clampi(club + step, first, Clubs.PUTTER)
	_update_green_grid()
	_update_aim()
	_update_hud()


func _on_update_available(version: String, url: String) -> void:
	_update_url = url
	_hud.show_update(version)


# --- Per-frame -------------------------------------------------------------

func _process(delta: float) -> void:
	state_time += delta
	match state:
		State.FLYBY:
			_flyby_camera()
			if state_time > FLYBY_TIME:
				_set_state(State.AIM)
				_hud.show_message("")
		State.AIM:
			_handle_aim_keys(delta)
			_aim_camera()
		State.SWING:
			_aim_camera()
		State.FLIGHT:
			_advance_flight(delta)
		State.RESULT:
			if state_time > RESULT_TIME:
				_after_result()
		State.HOLE_DONE, State.ROUND_DONE:
			var a := state_time * 0.25
			_cam_target = hole.pin + Vector3(sin(a) * 14.0, 5.0, cos(a) * 14.0)
			_cam_look = hole.pin
	if _demo:
		_demo_play()
	_move_camera(delta)
	_ball.scale = Vector3.ONE * maxf(1.0, _camera.global_position.distance_to(_ball.position) / 30.0)
	_map_ball.position = _ball.position
	_map_pin.position = hole.pin


## Attract mode: a decent golfer who aims at the target and mistimes a little.
func _demo_play() -> void:
	match state:
		State.FLYBY:
			if state_time > 2.5:
				_action()
		State.AIM:
			if state_time > 1.2:
				var dist := _flat(hole.pin - ball_pos).length()
				var power := 1.0
				if club == Clubs.PUTTER:
					power = 0.8
				elif dist < _reach():
					power = clampf(dist / _reach(), 0.2, 1.0)
				_set_state(State.SWING)
				_on_swing_finished(power, randf_range(-0.04, 0.04))
		State.HOLE_DONE, State.ROUND_DONE:
			if state_time > 3.0:
				_action()


func _handle_aim_keys(delta: float) -> void:
	var turn := 0.0
	if Input.is_key_pressed(KEY_LEFT):
		turn += 1.0
	if Input.is_key_pressed(KEY_RIGHT):
		turn -= 1.0
	if turn == 0.0:
		return
	var rate := AIM_RATE
	if club == Clubs.PUTTER:
		rate *= 0.2
	if Input.is_key_pressed(KEY_SHIFT):
		rate *= 0.25
	heading += turn * rate * delta
	_update_aim()
	_update_hud()


func _advance_flight(delta: float) -> void:
	_playback += delta
	var path := _shot.path
	var f := minf(_playback * BallPhysics.SAMPLE_RATE, float(path.size() - 1))
	var i := int(f)
	if i >= path.size() - 1:
		_ball.position = path[path.size() - 1]
		_playback = INF
		_play_shot_events()
		_finish_shot()
		return
	_ball.position = path[i].lerp(path[i + 1], f - i)
	_play_shot_events()
	if club != Clubs.PUTTER:
		var mesh: ImmediateMesh = _trail.mesh
		mesh.clear_surfaces()
		mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for k in i + 1:
			mesh.surface_add_vertex(path[k])
		mesh.surface_add_vertex(_ball.position)
		mesh.surface_end()
	_flight_camera()


# --- Cameras ---------------------------------------------------------------

func _aim_camera() -> void:
	var dir := _dir(heading)
	if club == Clubs.PUTTER:
		_cam_target = ball_pos - dir * 3.5 + Vector3.UP * 1.4
		_cam_look = ball_pos + dir * 6.0
	else:
		_cam_target = ball_pos - dir * 9.0 + Vector3.UP * 4.5
		_cam_look = ball_pos + dir * 60.0
	_cam_target.y = maxf(_cam_target.y, hole.height_at(_cam_target.x, _cam_target.z) + 1.0)


func _flight_camera() -> void:
	var p := _ball.position
	_cam_look = p
	if club == Clubs.PUTTER or _shot.carry < 45.0:
		var dir := _flat(p - _shot_start).normalized() if _flat(p - _shot_start).length() > 0.5 else _dir(heading)
		_cam_target = p - dir * 5.0 + Vector3.UP * 2.0
		_cam_target.y = maxf(_cam_target.y, hole.height_at(_cam_target.x, _cam_target.z) + 1.0)
		return
	# Watch the ball rise from behind the golfer, then cut to a camera near
	# where it comes down, like a TV broadcast.
	if _playback > 1.4 and not _landing_cam:
		_landing_cam = true
		var land := _shot.rest
		var back := _flat(_shot_start - land).normalized()
		var side := back.cross(Vector3.UP)
		var cam := land + back * 30.0 + side * 22.0
		cam.y = maxf(land.y, hole.height_at(cam.x, cam.z)) + 9.0
		_camera.position = cam
		_cam_target = cam


func _flyby_camera() -> void:
	var u := clampf(state_time / FLYBY_TIME, 0.0, 1.0)
	var e := u * u * (3.0 - 2.0 * u)
	var z := lerpf(-30.0, hole.length - 45.0, e)
	var x := hole.centre_x(z)
	var pos := Vector3(x, hole.height_at(x, z) + 22.0 + 18.0 * sin(e * PI), z)
	var zl := minf(z + 80.0, hole.pin.z)
	var xl := hole.centre_x(zl) if zl < hole.pin.z else hole.pin.x
	_cam_target = pos
	_cam_look = Vector3(xl, hole.height_at(xl, zl), zl)
	_camera.position = pos
	_look_now = _cam_look


func _move_camera(delta: float) -> void:
	_camera.position = _camera.position.lerp(_cam_target, 1.0 - exp(-4.0 * delta))
	_look_now = _look_now.lerp(_cam_look, 1.0 - exp(-10.0 * delta))
	var to_look := _look_now - _camera.position
	if to_look.length() > 0.01 and absf(to_look.normalized().y) < 0.999:
		_camera.look_at(_look_now)


func _setup_map_camera() -> void:
	var c := hole.bounds.get_center()
	_map_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_map_camera.size = hole.bounds.size.y + 30.0
	_map_camera.far = 1000.0
	# Looking straight down with +Z towards the top of the screen.
	_map_camera.transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3(0.0, 0.0, 1.0)),
			Vector3(c.x, 400.0, c.y))


# --- Aiming and club choice -------------------------------------------------

func _pick_club(dist: float) -> int:
	if lie == Surface.GREEN or (lie == Surface.FRINGE and dist < 20.0):
		return Clubs.PUTTER
	if lie == Surface.BUNKER and dist < 70.0:
		return Clubs.SAND_WEDGE
	var first := Clubs.DRIVER if lie == Surface.TEE else Clubs.DRIVER + 1
	for i in range(Clubs.SAND_WEDGE, first - 1, -1):
		if Clubs.carry(i) * Clubs.lie_power(i, lie) >= dist * 0.97:
			return i
	return first


func _reach() -> float:
	if club == Clubs.PUTTER:
		return _flat(hole.pin - ball_pos).length()
	return Clubs.carry(club) * Clubs.lie_power(club, lie)


func _default_heading() -> float:
	var reach := _reach()
	if club == Clubs.PUTTER or reach >= _flat(hole.pin - ball_pos).length() * 0.95:
		return _heading_to(hole.pin)
	# Laying up: aim at the point on the centre line we can just reach.
	var best_z := hole.pin.z
	var best := INF
	var z := ball_pos.z
	while z < hole.pin.z:
		var err := absf(_flat(Vector3(hole.centre_x(z), 0.0, z) - ball_pos).length() - reach)
		if err < best:
			best = err
			best_z = z
		z += 2.0
	return _heading_to(Vector3(hole.centre_x(best_z), 0.0, best_z))


func _update_aim() -> void:
	var dir := _dir(heading)
	var reach := _reach()
	var target := ball_pos + dir * reach
	target.y = hole.height_at(target.x, target.z)
	_marker.position = target + Vector3.UP * 0.1
	_marker.scale = Vector3.ONE * (0.12 if club == Clubs.PUTTER else clampf(reach / 60.0, 0.5, 3.0))
	_map_target.position = target

	var mesh: ImmediateMesh = _aim_line.mesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	const STEPS := 40
	for k in STEPS + 1:
		var p := ball_pos.lerp(target, float(k) / STEPS)
		p.y = hole.height_at(p.x, p.z) + 0.06
		mesh.surface_add_vertex(p)
	mesh.surface_end()


func _update_hud() -> void:
	var dist := _flat(hole.pin - ball_pos).length()
	_hud.set_hole_info("Hole %d   Par %d   %d yds" % [hole.number, hole.par, roundi(hole.yardage() * YARDS)])
	var lines := PackedStringArray()
	lines.append("Stroke %d   ·   Round %s" % [strokes + 1, card.to_par_text()])
	if lie == Surface.GREEN or dist < 20.0:
		lines.append("To pin: %d ft" % ceili(dist * FEET))
	else:
		lines.append("To pin: %d yds" % roundi(dist * YARDS))
	lines.append("Lie: %s" % Surface.NAMES[lie])
	if club == Clubs.PUTTER:
		var full := _putt_speed * _putt_speed / (2.0 * Surface.ROLL_DECEL[Surface.GREEN])
		lines.append("Club: Putter  (100%% ≈ %d ft)" % roundi(full * FEET))
		lines.append(_green_read())
		_hud.meter.full_label = "%d ft" % roundi(full * FEET)
	else:
		lines.append("Club: %s  (carry %d yds)" % [Clubs.club_name(club), roundi(_reach() * YARDS)])
		_hud.meter.full_label = "100%"
	_hud.set_shot_info("\n".join(lines))

	var f := _dir(heading)
	var left := Vector3(cos(heading), 0.0, -sin(heading))
	_hud.set_wind(Vector2(-wind.dot(left), -wind.dot(f)), wind.length() * MPH)


func _green_read() -> String:
	var mid := (ball_pos + hole.pin) * 0.5
	var n := hole.normal_at(mid.x, mid.z)
	var downhill := Vector2(n.x, n.z) * 100.0
	var f := Vector2(sin(heading), cos(heading))
	var left := Vector2(cos(heading), -sin(heading))
	var along := downhill.dot(f)
	var across := downhill.dot(left)
	var slope := "Downhill" if along > 0.0 else "Uphill"
	var brk := "left" if across > 0.0 else "right"
	return "Green: %s %.1f%%, breaks %s %.1f%%" % [slope, absf(along), brk, absf(across)]


func _drop_point() -> Vector3:
	var path := _shot.path
	for k in range(path.size() - 1, -1, -1):
		var p := path[k]
		if hole.is_in_bounds(p.x, p.z) and hole.surface_at(p.x, p.z) != Surface.WATER:
			var d := p + _flat(_shot_start - p).normalized() * 3.0
			if hole.surface_at(d.x, d.z) == Surface.WATER:
				d = p
			d.y = hole.height_at(d.x, d.z)
			return d
	return _shot_start


# --- Scoring ---------------------------------------------------------------

func _update_green_grid() -> void:
	if _view:
		_view.green_grid.visible = _show_grid and club == Clubs.PUTTER \
				and (state == State.AIM or state == State.SWING)


static func _ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1:
				suffix = "st"
			2:
				suffix = "nd"
			3:
				suffix = "rd"
	return "%d%s" % [n, suffix]


# --- Helpers ---------------------------------------------------------------

static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


static func _dir(h: float) -> Vector3:
	return Vector3(sin(h), 0.0, cos(h))


func _heading_to(p: Vector3) -> float:
	var d := p - ball_pos
	return atan2(d.x, d.z)


func _build_world() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.5, 0.85)
	sky_mat.sky_horizon_color = Color(0.72, 0.82, 0.92)
	sky_mat.ground_horizon_color = Color(0.6, 0.68, 0.6)
	sky_mat.ground_bottom_color = Color(0.2, 0.3, 0.2)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_density = 0.0004
	env.fog_light_color = Color(0.74, 0.82, 0.9)
	env.fog_sky_affect = 0.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 300.0
	add_child(sun)

	_camera = Camera3D.new()
	_camera.fov = 60.0
	_camera.far = 3000.0
	_camera.cull_mask = 0xFFFFF & ~(1 << (MAP_LAYER - 1))
	add_child(_camera)
	_camera.make_current()
	_map_camera = Camera3D.new()
	var map_env: Environment = env.duplicate()
	map_env.fog_enabled = false
	_map_camera.environment = map_env
	add_child(_map_camera)

	var ball_mesh := SphereMesh.new()
	ball_mesh.radius = 0.05
	ball_mesh.height = 0.1
	var ball_mat := StandardMaterial3D.new()
	ball_mat.albedo_color = Color.WHITE
	ball_mat.emission_enabled = true
	ball_mat.emission = Color(0.4, 0.4, 0.4)
	ball_mesh.material = ball_mat
	_ball = MeshInstance3D.new()
	_ball.mesh = ball_mesh
	add_child(_ball)

	var ring := TorusMesh.new()
	ring.inner_radius = 1.6
	ring.outer_radius = 2.0
	_marker = _overlay(ring, Color(1.0, 0.9, 0.2, 0.9))
	_aim_line = _overlay(ImmediateMesh.new(), Color(1.0, 0.9, 0.2, 0.6))
	_trail = _overlay(ImmediateMesh.new(), Color(1.0, 1.0, 1.0, 0.8))

	_map_ball = _map_marker(Color.WHITE)
	_map_pin = _map_marker(Color(0.95, 0.2, 0.2))
	_map_target = _map_marker(Color(1.0, 0.9, 0.2))


func _overlay(mesh: Mesh, colour: Color) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = colour
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _map_marker(colour: Color) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = 3.0
	s.height = 6.0
	var mi := _overlay(s, colour)
	mi.layers = 1 << (MAP_LAYER - 1)
	return mi
