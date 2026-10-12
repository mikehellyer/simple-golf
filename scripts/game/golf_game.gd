extends Node3D
## Game loop: 1-4 players, on one machine or online, in stroke play, match
## play, skins, fourball or foursomes.
##
## Everything that changes the game goes through the host (offline, this
## machine is its own host): it decides whose turn it is, runs computer
## players, and resolves each shot. A shot is shared as its inputs plus the
## host's result, so every machine replays the swing, simulates the same
## flight locally, then lands the ball exactly where the host says.
##
## Controls: Left/Right aim (Shift for fine), Up/Down club, Space or left
## click to swing, M overhead map, Tab scorecard, G green slope grid,
## N sound on/off, F fullscreen, Esc cancels a swing (twice: leave the round),
## U opens the download page when an update exists.
##
## Command-line options (after `--`): --demo watches a computer fourball;
## --editor opens the course editor; --tab=members opens that clubhouse tab;
## --host / --join=ADDR / --name=NAME / --profile=ID / --autoplay / --auto-start=N /
## --mode=N / --holes=N / --cpus=K,K / --quit-at-end / --net-log are used by
## the automated network test.

enum State { MENU, LOBBY, EDITOR, FLYBY, AIM, SWING, FLIGHT, RESULT, HOLE_DONE, ROUND_DONE }

const YARDS := 1.09361
const FEET := 3.28084
const MPH := 2.23694
const AIM_RATE := 0.5
const FLYBY_TIME := 5.0
const RESULT_TIME := 2.0
const CPU_AIM_TIME := 0.5
const CPU_SWING_TIME := 1.5
const AUTO_ADVANCE_TIME := 4.0
const AIM_SEND_INTERVAL := 0.1
## Host waits this long past the result for slow clients before moving on.
const ACK_TIMEOUT := 12.0
const MAX_STROKES := 12
const MAX_WIND := 9.0
const MAP_LAYER := 2


## One ball in play on the current hole.
class Ball:
	var index := 0
	var pos := Vector3.ZERO
	var lie := Surface.TEE
	var strokes := 0
	## Swings actually taken (penalty strokes excluded), for foursomes turns.
	var swings := 0
	var done := false
	var mesh: MeshInstance3D
	var map_marker: MeshInstance3D


var course: Course
var comp: Competition
var hole: Hole
var club := Clubs.DRIVER
var heading := 0.0
var wind := Vector3.ZERO
var state := State.MENU
var state_time := 0.0

var _hole_total := 18
var _holes: Array[Hole] = []
## The club's members and their stats (saved on this computer).
var members := PlayerProfiles.new()
## Per ball on the current hole: {putts, fairway (-1/0/1), gir, drive}.
var _hole_stats: Array[Dictionary] = []
## Online society: the server connection, the round being played for a
## society (empty for local rounds) and its hole-by-hole log for the card.
var _society: SocietyClient
var _society_round := {}
var _round_log: Array[Dictionary] = []
var _balls: Array[Ball] = []
var _ball: Ball
var _hitter: Competition.Player
var _tee_queue: Array[int] = []
var _cpu_plan: CpuPlayer.Plan
var _rng := RandomNumberGenerator.new()
var _net: NetSession
var _view: CourseView
var _hud: Hud
var _menu: ClubhouseMenu
var _clubhouse: Clubhouse
## Which part of the clubhouse the camera looks at: "play" or "members".
var _clubhouse_view := "play"
var _env: Environment
var _sun: DirectionalLight3D
var _graphics := GraphicsSettings.load_saved()
var _lobby: LobbyMenu
var _editor: CourseEditor
var _sfx: Sfx
var _camera: Camera3D
var _map_camera: Camera3D
var _marker: MeshInstance3D
var _aim_line: MeshInstance3D
var _trail: MeshInstance3D
var _map_pin: MeshInstance3D
var _map_target: MeshInstance3D
var _shot: BallPhysics.Result
var _shot_start := Vector3.ZERO
## The host's verdict on the shot being played: {pos, lie, strokes, done, outcome, msg}.
var _resolution := {}
var _swung_locally := false
## Host: a shot for this turn has been decided and sent; don't decide again.
var _decided := false
## Host: peers that have finished watching the current shot.
var _acks := {}
var _replaying := false
var _pending_swing := Vector2.ZERO
var _event_index := 0
var _playback := 0.0
var _landing_cam := false
var _cam_target := Vector3.ZERO
var _cam_look := Vector3.ZERO
var _look_now := Vector3.ZERO
var _putt_speed := 0.0
var _show_grid := true
var _quit_armed_at := -100.0
var _aim_sent_at := 0.0
var _update_url := ""
var _args := OS.get_cmdline_user_args()
var _demo := "--demo" in _args
var _autoplay := "--autoplay" in _args
var _net_log := "--net-log" in _args


func _ready() -> void:
	# The renderer can only be picked at launch: restart once if the saved
	# choice differs (unless it was given on the command line).
	if _graphics.needs_restart() and DisplayServer.get_name() != "headless" \
			and not "--rendering-method" in OS.get_cmdline_args():
		set_process(false)
		set_process_unhandled_input(false)
		_graphics.restart(get_tree())
		return
	_rng.randomize()
	_build_world()
	_graphics.apply(get_viewport(), _sun)
	_net = NetSession.new()
	_net.name = "Net"
	add_child(_net)
	_net.join_finished.connect(_on_join_finished)
	_net.session_closed.connect(func(reason: String) -> void: _show_menu(reason))
	_net.member_left.connect(_on_member_left)
	_net.lobby_changed.connect(_maybe_auto_start)
	_hud = Hud.new()
	add_child(_hud)
	_hud.meter.swing_finished.connect(_on_meter_finished)
	_hud.meter.clicked.connect(func() -> void: _sfx.play("tick", -6.0))
	_sfx = Sfx.new()
	add_child(_sfx)
	var menu_layer := CanvasLayer.new()
	menu_layer.layer = 2
	add_child(menu_layer)
	_menu = ClubhouseMenu.new()
	_menu.visible = false
	menu_layer.add_child(_menu)
	_menu.setup.start_requested.connect(_on_menu_start)
	_menu.setup.host_requested.connect(_on_host_requested)
	_menu.setup.join_requested.connect(_on_join_requested)
	_menu.quit_requested.connect(func() -> void: get_tree().quit())
	_society = SocietyClient.new()
	add_child(_society)
	_menu.society_panel.attach(_society)
	_menu.view_changed.connect(func(which: String) -> void:
		_clubhouse_view = which
		if which == "society":
			_menu.society_panel.open(_society))
	_menu.society_panel.play_requested.connect(_start_society_round)
	_menu.members_changed.connect(_update_clubhouse_decor)
	_menu.settings_panel.open(_graphics)
	_menu.settings_panel.changed.connect(func(g: GraphicsSettings) -> void: g.apply(get_viewport(), _sun))
	_lobby = LobbyMenu.new()
	_lobby.visible = false
	_lobby.start_requested.connect(_on_lobby_start)
	_lobby.leave_requested.connect(func() -> void:
		_net.leave()
		_show_menu())
	menu_layer.add_child(_lobby)
	_editor = CourseEditor.new()
	_editor.visible = false
	_editor.preview_requested.connect(func(h: Hole) -> void:
		_show_hole(h)
		_setup_map_camera(true))
	_editor.closed.connect(func() -> void: _show_menu())
	_editor.play_requested.connect(func(c: Course) -> void:
		_show_menu()
		_menu.setup.use_course(c))
	_menu.setup.editor_requested.connect(_show_editor)
	menu_layer.add_child(_editor)
	Updater.update_available.connect(_on_update_available)

	if _demo:
		_start_demo()
	elif "--editor" in _args:
		_show_menu()
		_show_editor(Course.new("My course", 42))
	elif "--host" in _args:
		_show_menu()
		_on_host_requested(_arg("name", "Host"), _arg("profile", ""))
	elif _arg("join", "") != "":
		_show_menu()
		_on_join_requested(_arg("join", ""), _arg("name", "Guest"))
	else:
		_show_menu()


## Value of a `--key=value` command-line option.
func _arg(key: String, default: String) -> String:
	for a in _args:
		if a.begins_with("--%s=" % key):
			return a.get_slice("=", 1)
	return default


# --- Menus, lobby and sessions ---------------------------------------------

func _show_menu(status := "") -> void:
	if _net.is_online():
		_net.leave()
	_set_state(State.MENU)
	_hud.visible = false
	_lobby.visible = false
	_editor.visible = false
	_camera.make_current()
	_clear_balls()
	_sfx.set_birds(false)
	_show_hole(Hole.new(1, _rng.randi()), true)
	_menu.open(members, status)
	if _arg("tab", "") != "":
		_menu.show_tab(_arg("tab", ""))
	elif not _society_round.is_empty():
		_menu.show_tab("society")
	_society_round = {}
	# Start inside, looking out of the window.
	var v := _clubhouse.view("play")
	_camera.position = v[0]
	_look_now = v[1]


func _show_lobby() -> void:
	_set_state(State.LOBBY)
	_hud.visible = false
	_menu.visible = false
	_clear_balls()
	if hole == null:
		_show_hole(Hole.new(_rng.randi_range(1, 18), _rng.randi()))
	_lobby.open(_net)
	_maybe_auto_start()


## The members' board and trophy cabinet reflect the club's records.
func _update_clubhouse_decor() -> void:
	if _clubhouse == null:
		return
	var rows := []
	var wins := 0
	var ranked := members.members.duplicate()
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ha: bool = int(a.stats.holes) > 0
		var hb: bool = int(b.stats.holes) > 0
		if ha != hb:
			return ha
		return PlayerProfiles.scoring_average(a.stats) < PlayerProfiles.scoring_average(b.stats))
	for m in ranked:
		wins += int(m.stats.wins)
		var avg := PlayerProfiles.scoring_average(m.stats)
		var text := "new" if int(m.stats.holes) == 0 else ("E" if absf(avg) < 0.05 else "%+.1f" % avg)
		rows.append([m.name, text])
	_clubhouse.set_members(rows)
	_clubhouse.set_trophies(wins)


func _show_editor(c: Course) -> void:
	_set_state(State.EDITOR)
	_menu.visible = false
	_hud.visible = false
	_clear_balls()
	_map_camera.make_current()
	_editor.open(c)


func _start_demo() -> void:
	var players: Array[Competition.Player] = []
	var names := ["Ada", "Bobby", "Cleo", "Dev"]
	for i in 4:
		var kind := Competition.Kind.CPU_HARD if i % 2 == 0 else Competition.Kind.CPU_MEDIUM
		players.append(Competition.Player.new(names[i], kind, Competition.COLOURS[i]))
	_start_round(Competition.Mode.FOURBALL, players, 18, Course.new("Random course", _rng.randi()))


## A practice or tournament round for an online society: one player, stroke
## play; the card is uploaded when the round is finished.
func _start_society_round(context: Dictionary) -> void:
	var me := Competition.Player.new(context.display_name, Competition.Kind.HUMAN, Competition.COLOURS[0])
	var players: Array[Competition.Player] = [me]
	_start_round(Competition.Mode.STROKE, players, context.holes, context.course)
	_society_round = context


func _on_menu_start(mode: int, players: Array, holes: int, c: Course) -> void:
	_society_round = {}
	var typed: Array[Competition.Player] = []
	typed.assign(players)
	_start_round(mode as Competition.Mode, typed, holes, c)


func _on_host_requested(player_name: String, profile := "") -> void:
	var err := _net.host(NetSession.DEFAULT_PORT, player_name)
	if err != OK:
		_menu.open(members, "Could not host on port %d (%s)." % [NetSession.DEFAULT_PORT, error_string(err)])
		return
	_net.my_profile = profile
	var s := _net.settings.duplicate(true)
	s.mode = _arg("mode", "0").to_int()
	s.course = Course.new("Random course", _rng.randi()).to_dict()
	s.holes = _arg("holes", "18").to_int()
	s.cpus = []
	for k in _arg("cpus", "").split(",", false):
		s.cpus.append(k.to_int())
	_net.set_settings(s)
	_show_lobby()


func _on_join_requested(address: String, player_name: String, profile := "") -> void:
	var err := _net.join(address, player_name)
	if err != OK:
		_menu.open(members, "Could not connect to %s (%s)." % [address, error_string(err)])
		return
	_net.my_profile = profile


func _on_join_finished(ok: bool, reason: String) -> void:
	if ok:
		_show_lobby()
	else:
		_show_menu(reason)


func _on_lobby_start() -> void:
	var line_up := _net.line_up()
	if not line_up.size() in Competition.PLAYER_COUNTS[_net.settings.mode]:
		return
	_start_round(_net.settings.mode, line_up, _net.settings.holes,
			Course.from_dict(_net.settings.get("course", {})))


## Automated test: the host tees off once enough players have joined.
func _maybe_auto_start() -> void:
	var want := _arg("auto-start", "0").to_int()
	if want > 0 and _net.is_host and state == State.LOBBY and _net.line_up().size() >= want:
		_on_lobby_start()


func _on_member_left(peer_id: int) -> void:
	if comp == null or state in [State.MENU, State.LOBBY]:
		return
	# The computer takes over anyone who drops out mid-round.
	for i in comp.players.size():
		if comp.players[i].owner == peer_id:
			net_player_dropped.rpc(i)


# --- Network messages ------------------------------------------------------
# All game-changing messages come from the host ("authority"). Offline, the
# same functions are called directly.

func _online() -> bool:
	return _net.is_online()


func _is_authority() -> bool:
	return not _online() or _net.is_host


func _is_local(p: Competition.Player) -> bool:
	return not _online() or p.owner == multiplayer.get_unique_id()


@rpc("authority", "call_local", "reliable")
func net_start_round(mode: int, player_dicts: Array, course_dict: Dictionary, holes: int) -> void:
	var players: Array[Competition.Player] = []
	for d in player_dicts:
		var p := Competition.Player.from_dict(d)
		# The host doesn't know a joining player's member id; they do.
		if _online() and p.owner == multiplayer.get_unique_id() and p.profile == "":
			p.profile = _net.my_profile
		players.append(p)
	course = Course.from_dict(course_dict)
	_hole_total = clampi(holes, 1, Course.MAX_HOLES)
	_holes.clear()
	var pars := PackedInt32Array()
	var yards := PackedInt32Array()
	for n in range(1, _hole_total + 1):
		var h := course.make_hole(n)
		_holes.append(h)
		pars.append(h.par)
		yards.append(roundi(h.yardage() * YARDS))
	comp = Competition.new(mode as Competition.Mode, players, pars, yards)
	_menu.visible = false
	_lobby.visible = false
	_hud.visible = true
	_round_log.clear()
	_start_hole(1)


@rpc("authority", "call_local", "reliable")
func net_start_hole(number: int) -> void:
	_complete_pending_shot()
	_start_hole(number)


@rpc("authority", "call_local", "reliable")
func net_begin_turn(ball_index: int) -> void:
	_complete_pending_shot()
	_hud.show_message("")
	if ball_index < 0:
		_hole_complete()
	else:
		_begin_turn(ball_index)


## A shot has been decided: everyone replays the swing, then the flight.
@rpc("authority", "call_local", "reliable")
func net_play_shot(ball_index: int, shot_club: int, shot_heading: float, power: float,
		accuracy: float, resolution: Dictionary) -> void:
	_ball = _balls[ball_index]
	club = shot_club
	heading = shot_heading
	_resolution = resolution
	_pending_swing = Vector2(power, accuracy)
	_acks.clear()
	_putt_speed = Aim.putt_speed(Aim.flat_distance(_ball.pos, hole.pin))
	_update_aim()
	_update_hud()
	if _swung_locally:
		_swung_locally = false
		_launch()
	else:
		_replaying = true
		_hud.show_message("")
		_set_state(State.SWING)
		_hud.meter.autoplay(power, accuracy)


## A client's swing, sent to the host for approval.
@rpc("any_peer", "call_remote", "reliable")
func net_request_shot(shot_club: int, shot_heading: float, power: float, accuracy: float) -> void:
	if not _net.is_host or _hitter == null or state != State.AIM and state != State.SWING:
		return
	if multiplayer.get_remote_sender_id() != _hitter.owner or _hitter.is_cpu():
		return
	_decide_shot(_ball.index, clampi(shot_club, 0, Clubs.PUTTER), shot_heading,
			clampf(power, 0.0, SwingMeter.MAX_VALUE), clampf(accuracy, SwingMeter.MIN_VALUE, 1.0))


## Live aim from whoever is playing, so everyone can watch them line up.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func net_aim(shot_club: int, shot_heading: float) -> void:
	if _hitter == null or state != State.AIM:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != _hitter.owner:
		return
	club = clampi(shot_club, 0, Clubs.PUTTER)
	heading = shot_heading
	_update_green_grid()
	_update_aim()
	_update_hud()


@rpc("authority", "call_local", "reliable")
func net_round_complete() -> void:
	_complete_pending_shot()
	_round_complete()


## Client to host: I've finished watching the shot.
@rpc("any_peer", "call_remote", "reliable")
func net_shot_done() -> void:
	if _net.is_host:
		_acks[multiplayer.get_remote_sender_id()] = true


## If the host has moved on while this machine is still showing a shot
## (a slow client), finish that shot instantly so no result is lost.
func _complete_pending_shot() -> void:
	if _replaying:
		_replaying = false
		_hud.meter.reset()
		_launch()
	if state == State.FLIGHT:
		_finish_shot()


## Host: everyone has seen the shot land (or we've waited long enough).
func _everyone_caught_up() -> bool:
	if not _online():
		return true
	if state_time > RESULT_TIME + ACK_TIMEOUT:
		return true
	for id in _net.members:
		if id != 1 and not _acks.has(id):
			return false
	return true


@rpc("authority", "call_local", "reliable")
func net_to_lobby() -> void:
	_show_lobby()


@rpc("authority", "call_local", "reliable")
func net_player_dropped(player_index: int) -> void:
	var p := comp.players[player_index]
	p.kind = Competition.Kind.CPU_MEDIUM
	p.owner = 1
	_hud.show_message("%s left — the computer takes over" % p.name)
	if p == _hitter and (state == State.AIM or state == State.SWING) and not _replaying and not _decided:
		_cpu_plan = null
		_swung_locally = false
		_set_state(State.AIM)


# --- Round flow (host) -----------------------------------------------------

func _start_round(mode: Competition.Mode, players: Array[Competition.Player], holes: int, c: Course) -> void:
	var dicts := players.map(func(p: Competition.Player) -> Dictionary: return p.to_dict())
	if _online():
		net_start_round.rpc(mode, dicts, c.to_dict(), holes)
	else:
		net_start_round(mode, dicts, c.to_dict(), holes)


## Host: picks the next ball (honour order on the tee, then farthest from
## the hole) and tells everyone; -1 means the hole is finished.
func _advance_turn() -> void:
	var next := -1
	while next < 0 and not _tee_queue.is_empty():
		var i: int = _tee_queue.pop_front()
		if not _balls[i].done:
			next = i
	if next < 0:
		var far := -1.0
		for b in _balls:
			var d := Aim.flat_distance(b.pos, hole.pin)
			if not b.done and d > far:
				far = d
				next = b.index
	if _online():
		net_begin_turn.rpc(next)
	else:
		net_begin_turn(next)


func _advance_hole() -> void:
	if comp.is_over():
		if _online():
			net_round_complete.rpc()
		else:
			net_round_complete()
	elif _online():
		net_start_hole.rpc(hole.number + 1)
	else:
		net_start_hole(hole.number + 1)


## Host: simulate the shot, settle where the ball ends up, tell everyone.
func _decide_shot(ball_index: int, shot_club: int, shot_heading: float, power: float, accuracy: float) -> void:
	if _decided:
		return
	_decided = true
	var b := _balls[ball_index]
	var launch := Clubs.launch_for(shot_club, b.pos, shot_heading, power, accuracy, b.lie,
			Aim.putt_speed(Aim.flat_distance(b.pos, hole.pin)))
	var result := BallPhysics.simulate(launch, hole, wind)
	var resolution := _resolve(result, b, shot_club)
	if _online():
		net_play_shot.rpc(ball_index, shot_club, shot_heading, power, accuracy, resolution)
	else:
		net_play_shot(ball_index, shot_club, shot_heading, power, accuracy, resolution)


## Where the ball ends up after a shot, with penalties applied.
func _resolve(r: BallPhysics.Result, b: Ball, shot_club: int) -> Dictionary:
	var out := {pos = b.pos, lie = b.lie, strokes = b.strokes + 1, done = false, outcome = r.outcome}
	var msg := ""
	match r.outcome:
		BallPhysics.Outcome.HOLED:
			out.done = true
			out.pos = hole.pin
			msg = "HOLE IN ONE!" if out.strokes == 1 else "In the hole!"
		BallPhysics.Outcome.WATER:
			out.strokes += 1
			out.pos = _drop_point(r, b.pos)
			msg = "Splash!\nOne stroke penalty — ball dropped"
		BallPhysics.Outcome.OUT_OF_BOUNDS:
			out.strokes += 1
			msg = "Out of bounds\nStroke and distance"
		_:
			out.pos = r.rest
			var lie := hole.surface_at(r.rest.x, r.rest.z)
			msg = Surface.NAMES[lie]
			if shot_club != Clubs.PUTTER:
				msg += "\ncarried %d yds" % roundi(r.carry * YARDS)
			elif lie == Surface.GREEN:
				msg = "%d ft to go" % ceili(Aim.flat_distance(r.rest, hole.pin) * FEET)
	out.lie = hole.surface_at(out.pos.x, out.pos.z) if r.outcome != BallPhysics.Outcome.HOLED else Surface.GREEN
	if not out.done and out.strokes >= MAX_STROKES:
		out.done = true
		msg += "\nPicked up"
	out.msg = msg
	return out


# --- Hole and turn flow (everyone) -----------------------------------------

## Shows a hole; with clubhouse = true, the clubhouse stands behind the tee.
func _show_hole(h: Hole, clubhouse := false) -> void:
	if _view:
		_view.queue_free()
	if _clubhouse:
		_clubhouse.queue_free()
		_clubhouse = null
	hole = h
	_view = CourseView.new()
	_view.build(hole, Clubhouse.clear_area() if clubhouse else Rect2())
	add_child(_view)
	_setup_map_camera()
	# Indoors, the lamps and fire light the room rather than the blue sky.
	_env.ambient_light_sky_contribution = 0.25 if clubhouse else 1.0
	if clubhouse:
		_clubhouse = Clubhouse.new()
		_clubhouse.build(hole)
		add_child(_clubhouse)
		_update_clubhouse_decor()


func _start_hole(number: int) -> void:
	_show_hole(_holes[number - 1])
	var rng := RandomNumberGenerator.new()
	rng.seed = course.hole_seed(number) + 99
	var wind_angle := rng.randf() * TAU
	wind = Vector3(sin(wind_angle), 0.0, cos(wind_angle)) * rng.randf_range(0.0, MAX_WIND)
	_sfx.set_birds(true)
	_hud.scorecard.visible = false

	_clear_balls()
	_hole_stats.clear()
	for b in comp.ball_count():
		_balls.append(_make_ball(b))
		_hole_stats.append({putts = 0, fairway = -1, gir = false, drive = 0.0})
	_tee_queue.assign(Array(comp.tee_order()))
	_ball = _balls[_tee_queue[0]]
	_hitter = comp.hitter(_ball.index, 0, hole.number)
	club = Clubs.DRIVER
	heading = Aim.default_heading(hole, _ball.pos, club, _ball.lie)
	_update_hud()
	_set_state(State.FLYBY)
	var intro := "Hole %d\nPar %d  ·  %d yards" % [hole.number, hole.par, roundi(hole.yardage() * YARDS)]
	if course.is_real():
		intro += "\n%s\nCourse layout © OpenStreetMap contributors" % course.name
	_hud.show_message(intro)


func _begin_turn(ball_index: int) -> void:
	_ball = _balls[ball_index]
	_hitter = comp.hitter(_ball.index, _ball.swings, hole.number)
	_cpu_plan = null
	_swung_locally = false
	_replaying = false
	_decided = false
	var dist := Aim.flat_distance(_ball.pos, hole.pin)
	club = Aim.pick_club(dist, _ball.lie)
	_putt_speed = Aim.putt_speed(dist)
	heading = Aim.default_heading(hole, _ball.pos, club, _ball.lie)
	_update_aim()
	_update_hud()
	_set_state(State.AIM)
	if comp.players.size() > 1:
		_hud.show_message("%s to play" % _hitter.name)


func _on_meter_finished(power: float, accuracy: float) -> void:
	if _replaying:
		_replaying = false
		_launch()
		return
	# A swing made on this machine: the host decides it; clients ask the host.
	_swung_locally = true
	if _is_authority():
		_decide_shot(_ball.index, club, heading, power, accuracy)
	else:
		net_request_shot.rpc_id(1, club, heading, power, accuracy)
		_hud.set_hint("Waiting for the host…")


func _launch() -> void:
	_ball.swings += 1
	_shot_start = _ball.pos
	var launch := Clubs.launch_for(club, _ball.pos, heading, _pending_swing.x, _pending_swing.y,
			_ball.lie, _putt_speed)
	_shot = BallPhysics.simulate(launch, hole, wind)
	_play_strike(_pending_swing.x)
	_event_index = 0
	_playback = 0.0
	_landing_cam = false
	_set_state(State.FLIGHT)


func _finish_shot() -> void:
	var r := _resolution
	if _net_log:
		print("SHOT hole=%d ball=%d strokes=%d outcome=%d pos=%.3f,%.3f,%.3f local=%.3f,%.3f,%.3f" % [
				hole.number, _ball.index, r.strokes, r.outcome, r.pos.x, r.pos.y, r.pos.z,
				_shot.rest.x, _shot.rest.y, _shot.rest.z])
	_track_stats(r)
	_ball.pos = r.pos
	_ball.lie = r.lie
	_ball.strokes = r.strokes
	_ball.done = r.done
	_ball.mesh.position = _ball.pos
	_ball.mesh.visible = r.outcome != BallPhysics.Outcome.HOLED
	if _online() and not _net.is_host:
		net_shot_done.rpc_id(1)
	var msg: String = r.msg
	if comp.players.size() > 1:
		msg = "%s: %s" % [_hitter.name, msg]
	_hud.show_message(msg)
	_set_state(State.RESULT)


## Notes putts, fairways, greens in regulation and drives as shots finish.
func _track_stats(r: Dictionary) -> void:
	var st := _hole_stats[_ball.index]
	var holed: bool = r.outcome == BallPhysics.Outcome.HOLED
	if _ball.lie == Surface.GREEN:
		st.putts += 1
	if _ball.swings == 1 and hole.par >= 4:
		st.fairway = 1 if r.lie == Surface.FAIRWAY or holed else 0
		if club <= 2 and r.outcome == BallPhysics.Outcome.REST:
			st.drive = Aim.flat_distance(_shot_start, r.pos)
	if not st.gir and (r.lie == Surface.GREEN or holed) and int(r.strokes) <= hole.par - 2:
		st.gir = true


## Stats count for human club members playing at this machine.
func _records_stats(p: Competition.Player) -> bool:
	return not p.is_cpu() and p.profile != "" and _is_local(p)


func _hole_complete() -> void:
	var strokes := PackedInt32Array()
	var best := 999
	for b in _balls:
		strokes.append(b.strokes)
		best = mini(best, b.strokes)
	var headline := comp.record_hole(strokes)
	# Keep each ball's hole for the society scorecard.
	for b in _balls.size():
		var st := _hole_stats[b]
		_round_log.append({ball = b, par = hole.par, strokes = strokes[b], putts = st.putts,
				fairway = st.fairway, gir = st.gir, drive = st.drive})
	var any := false
	for i in comp.players.size():
		var p := comp.players[i]
		if _records_stats(p):
			var b := comp.ball_of_player(i)
			var st := _hole_stats[b]
			members.record_hole(p.profile, hole.par, strokes[b], st.putts, st.fairway, st.gir, st.drive)
			any = true
	if any:
		members.save()
	if _net_log:
		print("HOLE %d %s" % [hole.number, strokes])
	if best < hole.par or best == 1:
		_sfx.play("applause")
	elif best == hole.par:
		_sfx.play("polite", -4.0)
	_hud.show_message("")
	_hud.set_shot_info("")
	_hud.set_player("", Color.WHITE)
	_hud.set_standings(comp.standings())
	_show_card(headline, hole.number)
	_set_state(State.HOLE_DONE)


func _round_complete() -> void:
	if _net_log:
		print("ROUND %s" % comp.result_text())
	var any := false
	for i in comp.players.size():
		var p := comp.players[i]
		if not _records_stats(p):
			continue
		var card := comp.cards[comp.ball_of_player(i)]
		var played := card.holes_played()
		var entry := {
			date = Time.get_date_string_from_system(), course = course.name, code = course.to_code(),
			mode = comp.mode, holes = played, strokes = card.total(), par = card.par_total(0, played),
			result = comp.result_for(i), skins = comp.skins[comp.side_of_ball(comp.ball_of_player(i))]
					if comp.mode == Competition.Mode.SKINS else 0,
			text = comp.result_text(),
		}
		members.record_round(p.profile, entry)
		any = true
	if any:
		members.save()
	_sfx.play("applause")
	_show_card(comp.result_text(), 0)
	_set_state(State.ROUND_DONE)
	if not _society_round.is_empty():
		_submit_society_card()
	if "--quit-at-end" in _args:
		await get_tree().create_timer(1.0).timeout
		get_tree().quit()


## Uploads the finished society round and says how it went.
func _submit_society_card() -> void:
	var ctx := _society_round
	var card := {society_id = ctx.society_id, tournament_id = null if ctx.tournament_id < 0 else ctx.tournament_id,
			course_name = ctx.course.name, course_code = ctx.course_code,
			pars = [], strokes = [], putts = [], fairways = [], greens = [], drives = []}
	for h in _round_log:
		if h.ball != 0:
			continue
		card.pars.append(h.par)
		card.strokes.append(h.strokes)
		card.putts.append(mini(h.putts, h.strokes))
		card.fairways.append(h.fairway)
		card.greens.append(h.gir)
		card.drives.append(snappedf(h.drive, 0.1))
	var what: String = ctx.tournament_name if ctx.tournament_id >= 0 else "practice round"
	_hud.show_message("Sending your card to %s…" % ctx.society_name)
	var r := await _menu.society_panel.submit(card)
	if r.ok:
		_hud.show_message("Card saved to %s (%s)" % [ctx.society_name, what])
	elif r.status == 0:
		_hud.show_message("Couldn't reach the society server.\nYour card is saved and will be sent next time you open the society.")
	else:
		_hud.show_message("The society didn't accept this card:\n%s" % r.error)


func _show_card(headline: String, current_hole: int) -> void:
	var rows: Array[Dictionary] = []
	if comp.is_match():
		rows.append({label = "Match", values = comp.match_row})
	elif comp.mode == Competition.Mode.SKINS:
		rows.append({label = "Skins", values = comp.skins_row})
	var footer := "  ·  ".join(comp.standings())
	if comp.ball_count() == 1:
		var c := comp.cards[0]
		footer = "Total %d  ·  %s after %d" % [c.total(), c.to_par_text(), c.holes_played()] \
				if c.holes_played() > 0 else "No holes completed yet"
	if comp.is_match():
		footer = "Match row: %s's standing after each hole" % comp.side_name(0)
	if current_hole == 0 or headline == "Scorecard":
		footer += "\n%s  ·  code %s" % [course.name, course.to_code().left(40)]
	_hud.scorecard.show_cards(comp.cards, current_hole, headline, footer, rows)


func _set_state(s: State) -> void:
	state = s
	state_time = 0.0
	var aiming := s == State.AIM or s == State.SWING
	var mine := _human_controls()
	_marker.visible = aiming
	_aim_line.visible = aiming
	_map_target.visible = aiming
	_trail.visible = s == State.FLIGHT or s == State.RESULT
	_hud.set_meter_visible(aiming or s == State.FLIGHT)
	_update_green_grid()
	if s == State.AIM or s == State.FLYBY:
		_hud.scorecard.visible = false
	var host := _is_authority()
	match s:
		State.FLYBY:
			_hud.set_hint("Space: skip fly-by" if host else "")
		State.AIM:
			_hud.meter.reset()
			if mine:
				_hud.set_hint("←/→ aim  ·  ↑/↓ club  ·  Space swing  ·  M map  ·  Tab card  ·  G slopes  ·  N sound")
			elif _hitter.is_cpu():
				_hud.set_hint("%s is thinking…" % _hitter.name)
			else:
				_hud.set_hint("%s is lining up…" % _hitter.name)
		State.SWING:
			_hud.set_hint("Space: set power, then again on the white line" if mine and not _replaying else "")
		State.FLIGHT:
			_hud.set_hint("Space: skip")
		State.RESULT:
			_hud.set_hint("")
		State.HOLE_DONE:
			if host:
				_hud.set_hint("Space: finish" if comp.is_over() else "Space: next hole")
			else:
				_hud.set_hint("Waiting for the host…")
		State.ROUND_DONE:
			if not _online():
				_hud.set_hint("Space: back to the menu")
			else:
				_hud.set_hint("Space: back to the lobby" if host else "Waiting for the host…")


# --- Input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if state in [State.MENU, State.LOBBY, State.EDITOR]:
		return
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
			if state == State.AIM and _human_controls():
				heading = Aim.heading_to(_ball.pos, hole.pin)
				_aim_changed()
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
					_show_card("Scorecard", hole.number)
		KEY_G:
			_show_grid = not _show_grid
			_update_green_grid()
		KEY_N:
			_hud.show_message("Sound off" if _sfx.toggle_mute() else "Sound on")
		KEY_ESCAPE:
			if state == State.SWING and _human_controls() and not _swung_locally and not _replaying:
				_set_state(State.AIM)
			elif Time.get_ticks_msec() / 1000.0 - _quit_armed_at < 2.5:
				_show_menu()
			else:
				_quit_armed_at = Time.get_ticks_msec() / 1000.0
				_hud.show_message("Press Esc again to leave the round")


func _action() -> void:
	match state:
		State.FLYBY:
			if _is_authority():
				_advance_turn()
		State.AIM:
			if _human_controls():
				_hud.show_message("")
				_set_state(State.SWING)
				_hud.meter.click()
		State.SWING:
			if _human_controls() and not _replaying and not _swung_locally:
				_hud.meter.click()
		State.FLIGHT:
			# Skip ahead, keeping only the final sound (cup, splash...).
			_event_index = maxi(_event_index, _shot.events.size() - 1)
			_playback = INF
		State.RESULT:
			if _is_authority():
				state_time = RESULT_TIME
		State.HOLE_DONE:
			if _is_authority():
				_advance_hole()
		State.ROUND_DONE:
			if _demo:
				_start_demo()
			elif not _online():
				_show_menu()
			elif _net.is_host:
				net_to_lobby.rpc()


## A human at this machine is playing the current shot.
func _human_controls() -> bool:
	return _hitter != null and not _hitter.is_cpu() and _is_local(_hitter) and not _autoplay


## The computer at this machine plays the current shot (a computer golfer
## on the host, or a human in --autoplay test mode).
func _cpu_controls() -> bool:
	return _hitter != null and _is_local(_hitter) and (_hitter.is_cpu() or _autoplay)


func _no_humans_here() -> bool:
	if _autoplay:
		return true
	for p in comp.players:
		if not p.is_cpu():
			return false
	return true


func _change_club(step: int) -> void:
	if state != State.AIM or not _human_controls():
		return
	var first := Clubs.DRIVER if _ball.lie == Surface.TEE else Clubs.DRIVER + 1
	club = clampi(club + step, first, Clubs.PUTTER)
	_aim_changed()


## The local player moved their aim or changed club: redraw and tell others.
func _aim_changed() -> void:
	_update_green_grid()
	_update_aim()
	_update_hud()
	var now := Time.get_ticks_msec() / 1000.0
	if _online() and now - _aim_sent_at > AIM_SEND_INTERVAL:
		_aim_sent_at = now
		net_aim.rpc(club, heading)


func _on_update_available(version: String, url: String) -> void:
	_update_url = url
	_hud.show_update(version)


# --- Per-frame -------------------------------------------------------------

func _process(delta: float) -> void:
	state_time += delta
	match state:
		State.MENU, State.LOBBY:
			if _clubhouse:
				# A gentle drift, as if glancing round the room.
				var v := _clubhouse.view(_clubhouse_view if state == State.MENU else "play")
				_cam_target = v[0] + Vector3(sin(state_time * 0.2) * 0.3, 0.0, 0.0)
				_cam_look = v[1] + Vector3(sin(state_time * 0.13) * 0.5, sin(state_time * 0.17) * 0.15, 0.0)
			else:
				var a := state_time * 0.05
				var z := hole.length * 0.6
				var centre := Vector3(hole.centre_x(z), hole.height_at(hole.centre_x(z), z), z)
				_cam_target = centre + Vector3(sin(a) * 160.0, 55.0, cos(a) * 160.0)
				_cam_look = centre
		State.FLYBY:
			_flyby_camera()
			if _is_authority() and (state_time > FLYBY_TIME or (_no_humans_here() and state_time > FLYBY_TIME * 0.5)):
				_advance_turn()
		State.AIM:
			if _human_controls():
				_handle_aim_keys(delta)
			elif _cpu_controls():
				_cpu_turn()
			_aim_camera()
		State.SWING:
			_aim_camera()
		State.FLIGHT:
			_advance_flight(delta)
		State.RESULT:
			if _is_authority() and state_time > RESULT_TIME and _everyone_caught_up():
				_advance_turn()
		State.HOLE_DONE, State.ROUND_DONE:
			var a := state_time * 0.25
			_cam_target = hole.pin + Vector3(sin(a) * 14.0, 5.0, cos(a) * 14.0)
			_cam_look = hole.pin
			if _is_authority() and _no_humans_here() and state_time > AUTO_ADVANCE_TIME:
				_action()
	_move_camera(delta)
	for b in _balls:
		b.mesh.scale = Vector3.ONE * maxf(1.0, _camera.global_position.distance_to(b.mesh.position) / 30.0)
		b.map_marker.position = b.mesh.position
		b.map_marker.visible = b.mesh.visible
	if hole:
		_map_pin.position = hole.pin


## The computer looks over the shot for a moment, settles on a plan, then
## swings on the same meter a human would use.
func _cpu_turn() -> void:
	if _cpu_plan == null:
		if state_time > CPU_AIM_TIME:
			_cpu_plan = CpuPlayer.plan(hole, _ball.pos, _ball.lie, wind, _hitter.skill(), _rng)
			club = _cpu_plan.club
			heading = _cpu_plan.heading
			_aim_sent_at = -1.0
			_aim_changed()
	elif state_time > CPU_SWING_TIME:
		if _hitter.is_cpu():
			# Host-run computer golfer: decide now; everyone replays the swing.
			_decide_shot(_ball.index, club, heading, _cpu_plan.power, _cpu_plan.accuracy)
		else:
			# --autoplay: swing this machine's human player on the meter.
			_hud.show_message("")
			_set_state(State.SWING)
			_hud.meter.autoplay(_cpu_plan.power, _cpu_plan.accuracy)


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
	_aim_changed()


func _advance_flight(delta: float) -> void:
	_playback += delta
	var path := _shot.path
	var f := minf(_playback * BallPhysics.SAMPLE_RATE, float(path.size() - 1))
	var i := int(f)
	if i >= path.size() - 1:
		_ball.mesh.position = path[path.size() - 1]
		_playback = INF
		_play_shot_events()
		_finish_shot()
		return
	_ball.mesh.position = path[i].lerp(path[i + 1], f - i)
	_play_shot_events()
	if club != Clubs.PUTTER:
		var mesh: ImmediateMesh = _trail.mesh
		mesh.clear_surfaces()
		mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for k in i + 1:
			mesh.surface_add_vertex(path[k])
		mesh.surface_add_vertex(_ball.mesh.position)
		mesh.surface_end()
	_flight_camera()


# --- Sound -----------------------------------------------------------------

func _play_strike(power: float) -> void:
	var loud := linear_to_db(clampf(power, 0.25, 1.1))
	if club == Clubs.PUTTER:
		_sfx.play("putt", loud - 4.0)
		return
	_sfx.play("swing", loud - 10.0, randf_range(0.95, 1.05))
	if _ball.lie == Surface.BUNKER:
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


# --- Cameras ---------------------------------------------------------------

func _aim_camera() -> void:
	var dir := _dir(heading)
	if club == Clubs.PUTTER:
		_cam_target = _ball.pos - dir * 3.5 + Vector3.UP * 1.4
		_cam_look = _ball.pos + dir * 6.0
	else:
		_cam_target = _ball.pos - dir * 9.0 + Vector3.UP * 4.5
		_cam_look = _ball.pos + dir * 60.0
	_cam_target.y = maxf(_cam_target.y, hole.height_at(_cam_target.x, _cam_target.z) + 1.0)


func _flight_camera() -> void:
	var p := _ball.mesh.position
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
		# Never put the camera inside a tree: rise above any canopy nearby.
		for t in hole.trees_near(cam.x, cam.z):
			if Vector2(cam.x - t.x, cam.z - t.z).length() < t.w * 1.5:
				cam.y = maxf(cam.y, t.y + t.w * 3.5)
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


func _setup_map_camera(editor := false) -> void:
	var c := hole.bounds.get_center()
	_map_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_map_camera.size = hole.bounds.size.y + 30.0
	# In the editor, slide the view right so the hole sits beside the panel.
	var view := get_viewport().get_visible_rect().size
	_map_camera.h_offset = -_map_camera.size * view.x / view.y * 0.15 if editor else 0.0
	_map_camera.far = 1000.0
	# Looking straight down with +Z towards the top of the screen.
	_map_camera.transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3(0.0, 0.0, 1.0)),
			Vector3(c.x, 400.0, c.y))


# --- Aiming and HUD ----------------------------------------------------------

func _reach() -> float:
	return Aim.reach(club, _ball.lie, Aim.flat_distance(_ball.pos, hole.pin))


func _update_aim() -> void:
	var dir := _dir(heading)
	var reach := _reach()
	var target := _ball.pos + dir * reach
	target.y = hole.height_at(target.x, target.z)
	_marker.position = target + Vector3.UP * 0.1
	_marker.scale = Vector3.ONE * (0.12 if club == Clubs.PUTTER else clampf(reach / 60.0, 0.5, 3.0))
	_map_target.position = target

	var mesh: ImmediateMesh = _aim_line.mesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	const STEPS := 40
	for k in STEPS + 1:
		var p := _ball.pos.lerp(target, float(k) / STEPS)
		p.y = hole.height_at(p.x, p.z) + 0.06
		mesh.surface_add_vertex(p)
	mesh.surface_end()


func _update_hud() -> void:
	if comp.players.size() > 1:
		var who := _hitter.name
		if comp.mode == Competition.Mode.FOURSOMES:
			who += "  (%s)" % comp.ball_name(_ball.index)
		_hud.set_player(who, _hitter.colour)
	else:
		_hud.set_player("", Color.WHITE)
	_hud.set_standings(comp.standings())
	var dist := Aim.flat_distance(_ball.pos, hole.pin)
	_hud.set_hole_info("Hole %d   Par %d   %d yds" % [hole.number, hole.par, roundi(hole.yardage() * YARDS)])
	var lines := PackedStringArray()
	lines.append("Stroke %d   ·   Round %s" % [_ball.strokes + 1, comp.cards[_ball.index].to_par_text()])
	if _ball.lie == Surface.GREEN or dist < 20.0:
		lines.append("To pin: %d ft" % ceili(dist * FEET))
	else:
		lines.append("To pin: %d yds" % roundi(dist * YARDS))
	lines.append("Lie: %s" % Surface.NAMES[_ball.lie])
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
	var mid := (_ball.pos + hole.pin) * 0.5
	var n := hole.normal_at(mid.x, mid.z)
	var downhill := Vector2(n.x, n.z) * 100.0
	var f := Vector2(sin(heading), cos(heading))
	var left := Vector2(cos(heading), -sin(heading))
	var along := downhill.dot(f)
	var across := downhill.dot(left)
	var slope := "Downhill" if along > 0.0 else "Uphill"
	var brk := "left" if across > 0.0 else "right"
	return "Green: %s %.1f%%, breaks %s %.1f%%" % [slope, absf(along), brk, absf(across)]


func _update_green_grid() -> void:
	if _view:
		_view.green_grid.visible = _show_grid and club == Clubs.PUTTER \
				and (state == State.AIM or state == State.SWING)


func _drop_point(r: BallPhysics.Result, start: Vector3) -> Vector3:
	var path := r.path
	for k in range(path.size() - 1, -1, -1):
		var p := path[k]
		if hole.is_in_bounds(p.x, p.z) and hole.surface_at(p.x, p.z) != Surface.WATER:
			var d := p + _flat(start - p).normalized() * 3.0
			if hole.surface_at(d.x, d.z) == Surface.WATER:
				d = p
			d.y = hole.height_at(d.x, d.z)
			return d
	return start


# --- Balls -----------------------------------------------------------------

func _make_ball(index: int) -> Ball:
	var b := Ball.new()
	b.index = index
	b.pos = hole.tee
	var colour := comp.hitter(index, 0, 1).colour
	var sphere := SphereMesh.new()
	sphere.radius = 0.05
	sphere.height = 0.1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.emission_enabled = true
	mat.emission = colour * 0.4
	sphere.material = mat
	b.mesh = MeshInstance3D.new()
	b.mesh.mesh = sphere
	b.mesh.position = b.pos
	add_child(b.mesh)
	b.map_marker = _map_marker(colour)
	return b


func _clear_balls() -> void:
	for b in _balls:
		b.mesh.queue_free()
		b.map_marker.queue_free()
	_balls.clear()
	_ball = null
	_hitter = null


# --- Helpers ---------------------------------------------------------------

static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


static func _dir(h: float) -> Vector3:
	return Vector3(sin(h), 0.0, cos(h))


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
	_env = env
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	_sun = sun
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

	var ring := TorusMesh.new()
	ring.inner_radius = 1.6
	ring.outer_radius = 2.0
	_marker = _overlay(ring, Color(1.0, 0.9, 0.2, 0.9))
	_aim_line = _overlay(ImmediateMesh.new(), Color(1.0, 0.9, 0.2, 0.6))
	_trail = _overlay(ImmediateMesh.new(), Color(1.0, 1.0, 1.0, 0.8))
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
