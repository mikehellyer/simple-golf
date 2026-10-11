extends SceneTree
## End-to-end test of the game's society client against a running server.
## Started by tests/society_test.sh, which runs a throwaway local server.

var _failures := 0
var _passes := 0


func _initialize() -> void:
	_run()


func check(cond: bool, what: String) -> void:
	if cond:
		_passes += 1
	else:
		_failures += 1
		printerr("FAIL: ", what)


func _run() -> void:
	await process_frame  # nodes only join the tree once the main loop runs
	var url := OS.get_environment("SOCIETY_URL")
	var mike := SocietyClient.new()
	var ana := SocietyClient.new()
	root.add_child(mike)
	root.add_child(ana)

	var r := await mike.register(url, "mike", "secret123", "Mike")
	check(r.ok and mike.is_signed_in(), "register signs in (%s)" % r.error)
	r = await ana.register(url, "ana", "secret123", "Ana")
	check(r.ok, "second player registers")
	r = await ana.register(url, "ana", "secret123", "Ana")
	check(not r.ok and r.status == 409 and r.error == "That username is taken.", "duplicate username explained")
	r = await ana.sign_in(url, "ana", "wrong-password")
	check(not r.ok and r.error == "Wrong username or password.", "bad password explained")
	r = await ana.sign_in(url, "ana", "secret123")
	check(r.ok, "sign in")

	var made := await mike.create_society("Friday Four")
	check(made.ok and str(made.data.invite_code).begins_with("SG-"), "create a society")
	var society_id: int = made.data.id
	var joined := await ana.join_society(made.data.invite_code)
	check(joined.ok and joined.data.role == "member", "join by invite code")
	var me := await ana.me()
	check(me.ok and me.data.societies.size() == 1, "member sees their society")

	var course := Course.new("Test course", 4242)
	var t := await mike.create_tournament(society_id, {name = "Saturday Medal", course = course.to_dict(),
			course_code = course.to_code(), holes = 3, scoring = "single",
			starts = Time.get_date_string_from_system(true),
			ends = Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_system()) + 6 * 86400)})
	check(t.ok and t.data.status == "open", "admin creates a tournament (%s)" % t.error)
	var refused := await ana.create_tournament(society_id, {name = "Nope", course = course.to_dict(),
			course_code = course.to_code(), holes = 3, scoring = "single", starts = "2026-01-01", ends = "2026-01-02"})
	check(not refused.ok and refused.status == 403, "members can't create tournaments")

	# Cards built the same way the game builds them.
	var tid: int = t.data.id
	var card := {society_id = society_id, tournament_id = tid, course_name = "Test course",
			course_code = t.data.course_code, pars = [4, 3, 5], strokes = [4, 2, 6], putts = [2, 1, 2],
			fairways = [1, -1, 0], greens = [true, true, false], drives = [235.4, 0.0, 251.0]}
	var sent := await mike.submit_round(card)
	check(sent.ok and sent.data.kind == "tournament", "tournament card accepted")
	var again := await mike.submit_round(card)
	check(not again.ok and again.status == 409, "second card refused in a one-round tournament")
	card.strokes = [5, 3, 5]
	check((await ana.submit_round(card)).ok, "second player's card accepted")
	var practice := card.duplicate()
	practice.tournament_id = null
	check((await ana.submit_round(practice)).ok, "practice card accepted")

	var board := await ana.tournament(tid)
	check(board.ok and board.data.leaderboard.size() == 2 and board.data.leaderboard[0].display_name == "Mike"
			and int(board.data.leaderboard[0].to_par) == 0, "leaderboard ranks the cards")
	var mike_id: int = mike.user.id
	var st := await ana.member_stats(society_id, mike_id)
	check(st.ok and int(st.data.tournament.rounds) == 1 and int(st.data.tournament.birdies) == 1
			and int(st.data.practice.rounds) == 0, "stats keep tournaments and practice apart")
	var list := await ana.rounds(society_id)
	check(list.ok and list.data.rounds.size() == 3, "society scorecards listed")
	var full := await ana.round_card(list.data.rounds[0].id)
	check(full.ok and full.data.strokes.size() == 3, "a saved scorecard can be viewed")

	await mike.sign_out()
	check(not mike.is_signed_in(), "sign out")
	var after := await mike.me()
	check(not after.ok and after.status == 401, "signed-out session no longer works")

	print("\n%d passed, %d failed" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)
