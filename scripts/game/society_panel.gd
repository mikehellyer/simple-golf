class_name SocietyPanel
extends PanelContainer
## The clubhouse's "Online society" tab: sign in to a society server, pick
## or join a society, and use its members' stats, tournaments, practice
## rounds and saved scorecards.

## context: {society_id, society_name, tournament_id (-1 for practice),
## tournament_name, course (Course), course_code, holes, display_name}
signal play_requested(context: Dictionary)

const YARDS := 1.09361
const SECTIONS := ["Members", "Tournaments", "Practice", "Scorecards"]

var client: SocietyClient
var _societies: Array = []
var _society := {}
var _busy := false

var _signin: VBoxContainer
var _server: LineEdit
var _username: LineEdit
var _password: LineEdit
var _display_name: LineEdit
var _home: VBoxContainer
var _picker: OptionButton
var _who: Label
var _code: LineEdit
var _new_name: LineEdit
var _tabs: TabBar
var _pages: Array[Control] = []
var _status: Label

# Members
var _member_list: ItemList
var _member_stats: RichTextLabel
var _admin_row: HBoxContainer
var _invite: Label
# Tournaments
var _t_list: ItemList
var _t_info: RichTextLabel
var _t_play: Button
var _t_delete: Button
var _t_form: VBoxContainer
var _t_name: LineEdit
var _t_holes: OptionButton
var _t_scoring: OptionButton
var _t_course: OptionButton
var _t_code: LineEdit
var _t_start: OptionButton
var _t_days: SpinBox
var _tournaments: Array = []
var _selected_tournament := {}
# Practice
var _p_holes: OptionButton
var _p_course: OptionButton
var _p_code: LineEdit
# Scorecards
var _r_filter: OptionButton
var _r_list: ItemList
var _card_popup: PopupPanel
var _card_view: ScorecardView


func _ready() -> void:
	add_theme_stylebox_override("panel", ClubhouseMenu.panel_style())
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	add_child(outer)
	var heading := Label.new()
	heading.text = "Online society"
	heading.add_theme_font_size_override("font_size", 24)
	outer.add_child(heading)
	_build_signin(outer)
	_build_home(outer)
	_status = Label.new()
	_status.modulate = Color(1.0, 0.85, 0.5)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(_status)
	_card_popup = PopupPanel.new()
	_card_view = ScorecardView.new()
	_card_popup.add_child(_card_view)
	add_child(_card_popup)


## Connects the panel to the server client (done once, at start-up, so a
## finished round can always be uploaded).
func attach(c: SocietyClient) -> void:
	if client == c:
		return
	client = c
	client.signed_in_changed.connect(_refresh_mode)


func open(c: SocietyClient) -> void:
	attach(c)
	_server.text = client.server_url
	_refresh_mode()


func _refresh_mode() -> void:
	_signin.visible = not client.is_signed_in()
	_home.visible = client.is_signed_in()
	if client.is_signed_in():
		_load_me()
	else:
		_status.text = "Sign in to your society server, or create an account on it."


# --- Building the UI -------------------------------------------------------

func _build_signin(parent: Control) -> void:
	_signin = VBoxContainer.new()
	_signin.add_theme_constant_override("separation", 8)
	parent.add_child(_signin)
	_server = _field(_signin, "Server", "e.g. yourname.duckdns.org")
	_username = _field(_signin, "Username", "3-20 letters or digits")
	_password = _field(_signin, "Password", "at least 6 characters")
	_password.secret = true
	_password.text_submitted.connect(func(_t: String) -> void: _sign_in())
	_display_name = _field(_signin, "Name shown", "only needed for a new account")
	_display_name.max_length = 12
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_button("Sign in", _sign_in))
	row.add_child(_button("Create account", _register))
	_signin.add_child(row)
	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.modulate = Color(1, 1, 1, 0.6)
	help.text = "The society is an online club shared with friends: tournaments, practice rounds, " \
			+ "stats and scorecards are kept on the server. Your local club stays on this computer."
	_signin.add_child(help)


func _build_home(parent: Control) -> void:
	_home = VBoxContainer.new()
	_home.add_theme_constant_override("separation", 8)
	_home.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(_home)
	var top := HBoxContainer.new()
	_picker = OptionButton.new()
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker.item_selected.connect(func(i: int) -> void: _load_society(_societies[i].id))
	top.add_child(_picker)
	_who = Label.new()
	_who.modulate = Color(1, 1, 1, 0.7)
	top.add_child(_who)
	top.add_child(_button("Sign out", func() -> void: client.sign_out()))
	_home.add_child(top)
	var join := HBoxContainer.new()
	_code = LineEdit.new()
	_code.placeholder_text = "invite code"
	_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join.add_child(_code)
	join.add_child(_button("Join", _join))
	_new_name = LineEdit.new()
	_new_name.placeholder_text = "new society name"
	_new_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join.add_child(_new_name)
	join.add_child(_button("Create", _create))
	_home.add_child(join)

	_tabs = TabBar.new()
	for s in SECTIONS:
		_tabs.add_tab(s)
	_tabs.tab_changed.connect(_show_section)
	_home.add_child(_tabs)
	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.custom_minimum_size = Vector2(540, 400)
	_home.add_child(stack)
	for build in [_build_members, _build_tournaments, _build_practice, _build_scorecards]:
		var page: Control = build.call()
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stack.add_child(page)
		_pages.append(page)
	_show_section(0)


func _build_members() -> Control:
	var page := VBoxContainer.new()
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(cols)
	_member_list = ItemList.new()
	_member_list.custom_minimum_size = Vector2(170, 0)
	_member_list.item_selected.connect(func(_i: int) -> void: _load_member_stats())
	cols.add_child(_member_list)
	_member_stats = _rich()
	cols.add_child(_member_stats)
	_admin_row = HBoxContainer.new()
	_invite = Label.new()
	_invite.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_admin_row.add_child(_invite)
	_admin_row.add_child(_button("New code", _new_code))
	_admin_row.add_child(_button("Admin ↔ member", _toggle_role))
	_admin_row.add_child(_button("Remove", _remove_member))
	page.add_child(_admin_row)
	return page


func _build_tournaments() -> Control:
	var page := VBoxContainer.new()
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(cols)
	_t_list = ItemList.new()
	_t_list.custom_minimum_size = Vector2(190, 0)
	_t_list.max_text_lines = 2
	_t_list.auto_height = true
	_t_list.item_selected.connect(func(i: int) -> void: _load_tournament(_tournaments[i].id))
	cols.add_child(_t_list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	_t_info = _rich()
	right.add_child(_t_info)
	var buttons := HBoxContainer.new()
	_t_play = _button("Play your round", _play_tournament)
	buttons.add_child(_t_play)
	_t_delete = _button("Delete", _delete_tournament)
	buttons.add_child(_t_delete)
	right.add_child(buttons)

	_t_form = VBoxContainer.new()
	var title := Label.new()
	title.text = "New tournament (admins)"
	_t_form.add_child(title)
	var r1 := HBoxContainer.new()
	_t_name = LineEdit.new()
	_t_name.placeholder_text = "name, e.g. Saturday Medal"
	_t_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r1.add_child(_t_name)
	_t_holes = _holes_option()
	r1.add_child(_t_holes)
	_t_scoring = OptionButton.new()
	_t_scoring.add_item("One round counts")
	_t_scoring.add_item("Best of any rounds")
	r1.add_child(_t_scoring)
	_t_form.add_child(r1)
	var r2 := HBoxContainer.new()
	_t_course = _course_option()
	r2.add_child(_t_course)
	_t_code = LineEdit.new()
	_t_code.placeholder_text = "or course code"
	_t_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r2.add_child(_t_code)
	_t_form.add_child(r2)
	var r3 := HBoxContainer.new()
	_t_start = OptionButton.new()
	for s in ["Starts today", "Starts tomorrow", "Starts next Monday"]:
		_t_start.add_item(s)
	r3.add_child(_t_start)
	var for_label := Label.new()
	for_label.text = "for"
	r3.add_child(for_label)
	_t_days = SpinBox.new()
	_t_days.min_value = 1
	_t_days.max_value = 31
	_t_days.value = 7
	_t_days.suffix = "days"
	r3.add_child(_t_days)
	r3.add_child(_button("Create tournament", _create_tournament))
	_t_form.add_child(r3)
	page.add_child(_t_form)
	return page


func _build_practice() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "Practice rounds are played on your own and saved to the society: they count " \
			+ "towards your practice stats, not tournaments."
	page.add_child(info)
	var row := HBoxContainer.new()
	_p_holes = _holes_option()
	row.add_child(_p_holes)
	_p_course = _course_option()
	row.add_child(_p_course)
	page.add_child(row)
	_p_code = LineEdit.new()
	_p_code.placeholder_text = "or paste a course code"
	page.add_child(_p_code)
	page.add_child(_button("Play a practice round", _play_practice))
	return page


func _build_scorecards() -> Control:
	var page := VBoxContainer.new()
	var row := HBoxContainer.new()
	_r_filter = OptionButton.new()
	_r_filter.add_item("My rounds")
	_r_filter.add_item("Everyone's rounds")
	_r_filter.item_selected.connect(func(_i: int) -> void: _load_rounds())
	row.add_child(_r_filter)
	row.add_child(_button("View scorecard", _view_card))
	page.add_child(row)
	_r_list = ItemList.new()
	_r_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_r_list.item_activated.connect(func(_i: int) -> void: _view_card())
	page.add_child(_r_list)
	return page


func _show_section(i: int) -> void:
	for j in _pages.size():
		_pages[j].visible = j == i
	if _society.is_empty():
		return
	match i:
		3:
			_load_rounds()


# --- Signing in ------------------------------------------------------------

func _sign_in() -> void:
	if _busy:
		return
	_busy = true
	_status.text = "Signing in…"
	var r := await client.sign_in(_server.text, _username.text.strip_edges(), _password.text)
	_busy = false
	_status.text = r.error
	if r.ok:
		_password.text = ""


func _register() -> void:
	if _busy:
		return
	var shown := _display_name.text.strip_edges()
	if shown == "":
		shown = _username.text.strip_edges()
	_busy = true
	_status.text = "Creating your account…"
	var r := await client.register(_server.text, _username.text.strip_edges(), _password.text, shown)
	_busy = false
	_status.text = r.error
	if r.ok:
		_password.text = ""


func _load_me() -> void:
	var r := await client.me()
	if not r.ok:
		_status.text = r.error
		return
	_who.text = client.user.get("display_name", "")
	_societies = r.data.societies
	_picker.clear()
	for s in _societies:
		_picker.add_item("%s%s" % [s.name, "  (admin)" if s.role == "admin" else ""])
	if _societies.is_empty():
		_society = {}
		_status.text = "Join a society with an invite code from a friend, or create your own."
		_clear_pages()
		return
	var keep := 0
	for i in _societies.size():
		if not _society.is_empty() and _societies[i].id == _society.id:
			keep = i
	_picker.select(keep)
	_load_society(_societies[keep].id)
	_retry_pending()


func _join() -> void:
	var r := await client.join_society(_code.text)
	_status.text = r.error if not r.ok else "Welcome to %s!" % r.data.name
	if r.ok:
		_code.text = ""
		_society = r.data
		_load_me()


func _create() -> void:
	var r := await client.create_society(_new_name.text.strip_edges())
	_status.text = r.error if not r.ok else "Created %s. Share the invite code %s with your friends." % [r.data.name, r.data.invite_code]
	if r.ok:
		_new_name.text = ""
		_society = r.data
		_load_me()


# --- Society ---------------------------------------------------------------

func _is_admin() -> bool:
	return _society.get("role", "") == "admin"


func _clear_pages() -> void:
	_member_list.clear()
	_member_stats.text = ""
	_t_list.clear()
	_t_info.text = ""
	_r_list.clear()
	_admin_row.visible = false
	_t_form.visible = false


func _load_society(id: int) -> void:
	var r := await client.society(id)
	if not r.ok:
		_status.text = r.error
		return
	_society = r.data
	_admin_row.visible = _is_admin()
	_t_form.visible = _is_admin()
	_invite.text = "Invite code: %s" % _society.invite_code
	_member_list.clear()
	for m in _society.members:
		var avg = m.scoring_average
		var text := "%s%s  %s" % [m.display_name, " ★" if m.role == "admin" else "",
				"" if avg == null else ("E" if absf(avg) < 0.05 else "%+.1f" % avg)]
		var i := _member_list.add_item(text)
		_member_list.set_item_metadata(i, m)
	if _member_list.item_count > 0:
		_member_list.select(0)
		_load_member_stats()
	_tournaments = _society.tournaments
	_t_list.clear()
	for t in _tournaments:
		var i := _t_list.add_item("%s\n%s · %s" % [t.name, t.status, t.ends if t.status == "open" else t.starts])
		_t_list.set_item_custom_fg_color(i, {"open": Color(0.6, 1.0, 0.6), "upcoming": Color(0.8, 0.85, 1.0)}.get(t.status, Color(0.8, 0.8, 0.8)))
	_t_info.text = "Pick a tournament to see its leaderboard." if not _tournaments.is_empty() \
			else ("No tournaments yet." + (" Set one up below." if _is_admin() else ""))
	_t_play.visible = false
	_t_delete.visible = false
	_selected_tournament = {}
	if _tabs.current_tab == 3:
		_load_rounds()


func _load_member_stats() -> void:
	var items := _member_list.get_selected_items()
	if items.is_empty():
		return
	var m: Dictionary = _member_list.get_item_metadata(items[0])
	var r := await client.member_stats(_society.id, m.id)
	if not r.ok:
		_member_stats.text = r.error
		return
	var t := "[font_size=20][b]%s[/b][/font_size]  [color=#bbbbbb]%s, joined %s[/color]\n\n" % [
			m.display_name, m.role, str(m.joined).left(10)]
	t += "[b]Tournaments[/b]\n" + _stats_text(r.data.tournament) + "\n[b]Practice[/b]\n" + _stats_text(r.data.practice)
	_member_stats.text = t


static func _stats_text(s: Dictionary) -> String:
	if int(s.holes) == 0:
		return "No rounds yet.\n"
	var avg = s.scoring_average
	var t := "Rounds %d · holes %d · average %s per 18\n" % [s.rounds, s.holes,
			"E" if absf(avg) < 0.05 else "%+.1f" % avg]
	t += "Best 18 %s · best 9 %s\n" % [_best(s.best18), _best(s.best9)]
	t += "Fairways %s · greens %s · putts/hole %.2f\n" % [PlayerProfiles.percent(s.fairways, s.fairway_chances),
			PlayerProfiles.percent(s.greens, s.holes), float(s.putts) / s.holes]
	if int(s.drives) > 0:
		t += "Drives: avg %d yds, longest %d yds\n" % [roundi(s.drive_total / s.drives * YARDS), roundi(s.longest_drive * YARDS)]
	t += "Eagles %d · birdies %d · pars %d · bogeys %d · double+ %d\n" % [s.eagles, s.birdies, s.pars, s.bogeys, s.doubles]
	return t


static func _best(b) -> String:
	if b == null:
		return "–"
	return "%d (%s)" % [b.strokes, Scorecard.format_to_par(int(b.strokes) - int(b.par))]


func _selected_member() -> Dictionary:
	var items := _member_list.get_selected_items()
	return {} if items.is_empty() else _member_list.get_item_metadata(items[0])


func _new_code() -> void:
	var r := await client.new_invite(_society.id)
	_status.text = r.error if not r.ok else "New invite code: %s (the old one no longer works)." % r.data.invite_code
	if r.ok:
		_invite.text = "Invite code: %s" % r.data.invite_code


func _toggle_role() -> void:
	var m := _selected_member()
	if m.is_empty():
		return
	var r := await client.set_role(_society.id, m.id, "member" if m.role == "admin" else "admin")
	_status.text = r.error
	_load_society(_society.id)


func _remove_member() -> void:
	var m := _selected_member()
	if m.is_empty():
		return
	var r := await client.remove_member(_society.id, m.id)
	_status.text = r.error if not r.ok else "%s has left the society." % m.display_name
	_load_me()


# --- Tournaments -----------------------------------------------------------

func _load_tournament(id: int) -> void:
	var r := await client.tournament(id)
	if not r.ok:
		_t_info.text = r.error
		return
	var t: Dictionary = r.data
	_selected_tournament = t
	var text := "[font_size=20][b]%s[/b][/font_size]\n" % t.name
	text += "%s · %d holes · %s · %s to %s\n" % [t.course.get("name", "Course"), t.holes,
			"one round counts" if t.scoring == "single" else "best round counts", t.starts, t.ends]
	match t.status:
		"open":
			text += "[color=#88ee88]Open now[/color]"
		"upcoming":
			text += "[color=#aabbff]Opens %s[/color]" % t.starts
		_:
			text += "[color=#bbbbbb]Finished[/color]"
	text += "   ·   you've played %d round%s\n\n" % [t.my_rounds, "" if t.my_rounds == 1 else "s"]
	if t.leaderboard.is_empty():
		text += "No cards in yet."
	else:
		text += "[b]Leaderboard[/b]\n"
		for e in t.leaderboard:
			text += "%d.  %s   %d (%s)%s\n" % [e.position, e.display_name, e.total,
					Scorecard.format_to_par(int(e.to_par)), "" if t.scoring == "single" else "  · %d played" % e.rounds]
	_t_info.text = text
	_t_play.visible = t.can_play
	_t_delete.visible = _is_admin()


func _play_tournament() -> void:
	var t := _selected_tournament
	if t.is_empty() or not t.can_play:
		return
	play_requested.emit(_context(t.id, t.name, Course.from_dict(t.course), t.course_code, int(t.holes)))


func _delete_tournament() -> void:
	if _selected_tournament.is_empty():
		return
	var r := await client.delete_tournament(_selected_tournament.id)
	_status.text = r.error if not r.ok else "Tournament deleted."
	_load_society(_society.id)


func _create_tournament() -> void:
	var course := _chosen_course(_t_course, _t_code)
	if course == null:
		return
	var start := Time.get_unix_time_from_system()
	match _t_start.selected:
		1:
			start += 86400
		2:
			var weekday: int = Time.get_datetime_dict_from_unix_time(int(start)).weekday
			start += 86400 * (((8 - weekday) % 7) if weekday != 1 else 7)
	var starts := Time.get_date_string_from_unix_time(int(start))
	var ends := Time.get_date_string_from_unix_time(int(start + 86400 * (int(_t_days.value) - 1)))
	var details := {name = _t_name.text.strip_edges(), course = course.to_dict(), course_code = course.to_code(),
			holes = SetupMenu.HOLE_OPTIONS[_t_holes.selected], scoring = "single" if _t_scoring.selected == 0 else "best",
			starts = starts, ends = ends}
	var r := await client.create_tournament(_society.id, details)
	_status.text = r.error if not r.ok else "%s is set up: %s to %s." % [r.data.name, starts, ends]
	if r.ok:
		_t_name.text = ""
		_t_code.text = ""
		_load_society(_society.id)


# --- Practice --------------------------------------------------------------

func _play_practice() -> void:
	var course := _chosen_course(_p_course, _p_code)
	if course == null or _society.is_empty():
		return
	play_requested.emit(_context(-1, "", course, course.to_code(), SetupMenu.HOLE_OPTIONS[_p_holes.selected]))


func _context(tournament_id: int, tournament_name: String, course: Course, code: String, holes: int) -> Dictionary:
	return {society_id = int(_society.id), society_name = _society.name, tournament_id = tournament_id,
			tournament_name = tournament_name, course = course, course_code = code, holes = holes,
			display_name = client.user.get("display_name", "Me")}


# --- Scorecards ------------------------------------------------------------

func _load_rounds() -> void:
	if _society.is_empty():
		return
	var mine := _r_filter.selected == 0
	var r := await client.rounds(_society.id, int(client.user.get("id", -1)) if mine else -1)
	_r_list.clear()
	if not r.ok:
		_status.text = r.error
		return
	for x in r.data.rounds:
		var label := "%s  %s  %s, %d holes  %d (%s)  %s" % [str(x.played_at).left(10), x.display_name, x.course_name,
				x.holes, x.total, Scorecard.format_to_par(int(x.total) - int(x.par_total)),
				x.tournament if x.tournament != null else "practice"]
		var i := _r_list.add_item(label)
		_r_list.set_item_metadata(i, x.id)
	if _r_list.item_count == 0:
		_r_list.add_item("No rounds saved yet.")


func _view_card() -> void:
	var items := _r_list.get_selected_items()
	if items.is_empty() or _r_list.get_item_metadata(items[0]) == null:
		return
	var r := await client.round_card(_r_list.get_item_metadata(items[0]))
	if not r.ok:
		_status.text = r.error
		return
	var d: Dictionary = r.data
	var yards := PackedInt32Array()
	yards.resize(d.pars.size())
	var card := Scorecard.new(PackedInt32Array(d.pars), yards, d.display_name)
	for s in d.strokes:
		card.record(int(s))
	var cards: Array[Scorecard] = [card]
	var putts := PackedStringArray()
	for p in d.putts:
		putts.append(str(int(p)))
	var rows: Array[Dictionary] = [{label = "Putts", values = putts}]
	var what: String = d.tournament if d.tournament != null else "Practice"
	_card_view.show_cards(cards, 0, "%s — %s" % [what, d.course_name],
			"%s  ·  %d (%s)" % [str(d.played_at).left(10), d.total, Scorecard.format_to_par(int(d.total) - int(d.par_total))], rows)
	_card_popup.popup_centered()


# --- Uploading finished rounds ---------------------------------------------

## Sends a finished round, keeping it to try again later if that fails.
func submit(card: Dictionary) -> Dictionary:
	var r := await client.submit_round(card)
	if not r.ok and r.status == 0:
		_queue(card)
	return r


func _queue(card: Dictionary) -> void:
	var pending := _pending()
	pending.append(card)
	var f := FileAccess.open("user://society_pending.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(pending))


func _pending() -> Array:
	if not FileAccess.file_exists("user://society_pending.json"):
		return []
	var data = JSON.parse_string(FileAccess.get_file_as_string("user://society_pending.json"))
	return data if typeof(data) == TYPE_ARRAY else []


func _retry_pending() -> void:
	var pending := _pending()
	if pending.is_empty():
		return
	var left := []
	for card in pending:
		var r := await client.submit_round(card)
		if not r.ok and r.status == 0:
			left.append(card)
	DirAccess.remove_absolute("user://society_pending.json")
	for card in left:
		_queue(card)
	var sent := pending.size() - left.size()
	if sent > 0:
		_status.text = "Uploaded %d round%s that couldn't be sent earlier." % [sent, "" if sent == 1 else "s"]


# --- Helpers ---------------------------------------------------------------

func _field(parent: Control, label: String, hint: String) -> LineEdit:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(110, 0)
	row.add_child(l)
	var e := LineEdit.new()
	e.placeholder_text = hint
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(e)
	parent.add_child(row)
	return e


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	return b


func _rich() -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.scroll_active = true
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return r


func _holes_option() -> OptionButton:
	var o := OptionButton.new()
	for n in SetupMenu.HOLE_OPTIONS:
		o.add_item("%d holes" % n)
	return o


func _course_option() -> OptionButton:
	var o := OptionButton.new()
	o.add_item("Random course")
	o.add_item(Course.daily().name)
	for n in Course.list_saved():
		o.add_item(n)
	return o


func _chosen_course(o: OptionButton, code: LineEdit) -> Course:
	if code.text.strip_edges() != "":
		var c := Course.from_code(code.text)
		if c == null:
			_status.text = "That course code isn't valid."
		return c
	match o.selected:
		0:
			return Course.new("Random course", randi())
		1:
			return Course.daily()
	return Course.load_saved(o.get_item_text(o.selected))
