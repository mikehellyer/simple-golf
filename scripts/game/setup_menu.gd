class_name SetupMenu
extends PanelContainer
## "New round" in the clubhouse: the format, the course and who is playing.
## Each player slot is a club member or a computer golfer. The last line-up
## is remembered between sessions.

signal start_requested(mode: int, players: Array, holes: int, course: Course)
signal editor_requested(course: Course)
signal host_requested(player_name: String, profile: String)
signal join_requested(address: String, player_name: String, profile: String)

const SETTINGS_PATH := "user://settings.cfg"
const MAX_PLAYERS := 4
const HOLE_OPTIONS := [18, 9, 3]
const CPU_NAMES := ["Ace", "Birdie", "Chip", "Divot"]

var members: PlayerProfiles
var _mode: OptionButton
var _count: OptionButton
var _holes: OptionButton
var _course: OptionButton
var _code: LineEdit
var _address: LineEdit
var _status: Label
var _info: Label
var _rows: Array[HBoxContainer] = []
var _tags: Array[Label] = []
var _who: Array[OptionButton] = []
## Saved choice per slot: a member id, or "cpu:<kind>".
var _choices: Array[String] = []
var _start: Button


func _ready() -> void:
	add_theme_stylebox_override("panel", ClubhouseMenu.panel_style())
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(500, 0)
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var heading := Label.new()
	heading.text = "Local club — new round"
	heading.add_theme_font_size_override("font_size", 24)
	box.add_child(heading)

	_mode = OptionButton.new()
	for m in Competition.MODE_NAMES:
		_mode.add_item(m)
	_mode.item_selected.connect(func(_i: int) -> void: _refresh())
	box.add_child(_labelled("Game", _mode))
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.modulate = Color(1, 1, 1, 0.75)
	_info.custom_minimum_size = Vector2(0, 46)
	box.add_child(_info)
	_count = OptionButton.new()
	_count.item_selected.connect(func(_i: int) -> void: _refresh_rows())
	box.add_child(_labelled("Players", _count))
	_holes = OptionButton.new()
	for n in HOLE_OPTIONS:
		_holes.add_item("%d holes%s" % [n, " (quick test)" if n == 3 else ""])
	box.add_child(_labelled("Length", _holes))
	var course_row := HBoxContainer.new()
	_course = OptionButton.new()
	_course.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_course.item_selected.connect(func(_i: int) -> void: _code.text = "")
	course_row.add_child(_course)
	var edit := Button.new()
	edit.text = "Edit…"
	edit.pressed.connect(func() -> void:
		var c := selected_course()
		if c and c.is_real():
			_status.text = "Real courses can't be edited, but you can play them as they are."
		elif c:
			editor_requested.emit(c))
	course_row.add_child(edit)
	box.add_child(_labelled("Course", course_row))
	_code = LineEdit.new()
	_code.placeholder_text = "or paste a course code (SG-… / SGX-…)"
	box.add_child(_labelled("", _code))

	for i in MAX_PLAYERS:
		var row := HBoxContainer.new()
		var tag := Label.new()
		tag.custom_minimum_size = Vector2(70, 0)
		tag.add_theme_color_override("font_color", Competition.COLOURS[i])
		row.add_child(tag)
		var who := OptionButton.new()
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(who)
		box.add_child(row)
		_rows.append(row)
		_tags.append(tag)
		_who.append(who)
		_choices.append("")

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_start = Button.new()
	_start.text = "  Tee off  "
	_start.pressed.connect(func() -> void: _begin(false))
	buttons.add_child(_start)
	var watch := Button.new()
	watch.text = "Watch the computer"
	watch.pressed.connect(func() -> void: _begin(true))
	buttons.add_child(watch)
	box.add_child(buttons)

	box.add_child(HSeparator.new())
	var online := HBoxContainer.new()
	online.add_theme_constant_override("separation", 8)
	var online_label := Label.new()
	online_label.text = "Online"
	online_label.custom_minimum_size = Vector2(70, 0)
	online.add_child(online_label)
	var host := Button.new()
	host.text = "Host"
	host.pressed.connect(_on_host)
	online.add_child(host)
	_address = LineEdit.new()
	_address.placeholder_text = "host address"
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address.text_submitted.connect(func(_t: String) -> void: _on_join())
	online.add_child(_address)
	var join := Button.new()
	join.text = "Join"
	join.pressed.connect(_on_join)
	online.add_child(join)
	box.add_child(online)
	_status = Label.new()
	_status.modulate = Color(1.0, 0.75, 0.5)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)

	_load()


func open(profiles: PlayerProfiles, status := "") -> void:
	members = profiles
	_status.text = status
	refresh_courses()
	refresh_players()
	_start.grab_focus()


## Rebuilds each slot's list: club members, then computer golfers.
func refresh_players() -> void:
	for i in MAX_PLAYERS:
		var o := _who[i]
		o.clear()
		for m in members.members:
			o.add_item(m.name)
			o.set_item_metadata(o.item_count - 1, m.id)
		if o.item_count > 0:
			o.add_separator()
		for k in range(1, Competition.KIND_NAMES.size()):
			o.add_item("Computer — %s" % CpuPlayer.SKILL_NAMES[k - 1].to_lower())
			o.set_item_metadata(o.item_count - 1, "cpu:%d" % k)
		var want := _choices[i]
		if want == "":
			# Default: the first members, then computer golfers.
			want = members.members[i].id if i < members.members.size() else "cpu:%d" % Competition.Kind.CPU_MEDIUM
		_select_meta(o, want)
		if not o.item_selected.is_connected(_remember):
			o.item_selected.connect(_remember.bind(i))
	_refresh()


func _remember(_index: int, slot: int) -> void:
	_choices[slot] = str(_who[slot].get_selected_metadata())


func _select_meta(o: OptionButton, meta: String) -> void:
	for j in o.item_count:
		if str(o.get_item_metadata(j)) == meta:
			o.select(j)
			return
	o.select(o.item_count - 2)


## Fills the course list (random, today's, real courses, saved ones).
func refresh_courses(select_name := "") -> void:
	CoursePicker.fill(_course, select_name)


## Selects a course coming back from the editor: by name if it's saved,
## otherwise by its share code.
func use_course(c: Course) -> void:
	if c.name in Course.list_saved():
		_code.text = ""
		refresh_courses(c.name)
	else:
		_code.text = c.to_code()


## The chosen course, or null (with a message) if the pasted code is bad.
func selected_course() -> Course:
	if _code.text.strip_edges() != "":
		var c := Course.from_code(_code.text)
		if c == null:
			_status.text = "That course code isn't valid."
		return c
	return CoursePicker.chosen(_course)


func _labelled(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(70, 0)
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _refresh() -> void:
	var mode := _mode.selected
	_info.text = Competition.MODE_INFO[mode]
	var previous := _player_count()
	_count.clear()
	var counts: Array = Competition.PLAYER_COUNTS[mode]
	for c in counts:
		_count.add_item("%d" % c)
	var keep := counts.find(previous)
	_count.select(keep if keep >= 0 else 0)
	_refresh_rows()


func _refresh_rows() -> void:
	var n := _player_count()
	var teams := Competition.is_team_mode(_mode.selected as Competition.Mode)
	for i in MAX_PLAYERS:
		_rows[i].visible = i < n
		_tags[i].text = ("Team %d" % (i / 2 + 1)) if teams else ("Player %d" % (i + 1))


func _player_count() -> int:
	if _count.item_count == 0:
		return 1
	return _count.get_item_text(_count.selected).to_int()


## The line-up, or an empty list (with a message) if it isn't valid.
func _players(all_cpu: bool) -> Array[Competition.Player]:
	var out: Array[Competition.Player] = []
	var used := {}
	for i in _player_count():
		var meta := str(_who[i].get_selected_metadata())
		if all_cpu:
			meta = "cpu:%d" % (Competition.Kind.CPU_HARD if i % 2 == 0 else Competition.Kind.CPU_MEDIUM)
		if meta.begins_with("cpu:"):
			out.append(Competition.Player.new(CPU_NAMES[i], meta.get_slice(":", 1).to_int() as Competition.Kind,
					Competition.COLOURS[i]))
			continue
		var m := members.find(meta)
		if m.is_empty():
			_status.text = "Choose who is playing in each slot."
			return []
		if used.has(meta):
			_status.text = "%s can only play once in a round." % m.name
			return []
		used[meta] = true
		var p := Competition.Player.new(m.name, Competition.Kind.HUMAN, Competition.COLOURS[i])
		p.profile = m.id
		out.append(p)
	return out


func _begin(all_cpu: bool) -> void:
	var c := selected_course()
	var players := _players(all_cpu)
	if c == null or players.is_empty():
		return
	_save()
	start_requested.emit(_mode.selected, players, _hole_count(), c)


## Online play uses Player 1's slot, which must be a club member.
func _online_member() -> Dictionary:
	var m := members.find(str(_who[0].get_selected_metadata()))
	if m.is_empty():
		_status.text = "To play online, choose yourself (a club member) as Player 1."
	return m


func _on_host() -> void:
	var m := _online_member()
	if m.is_empty():
		return
	_save()
	host_requested.emit(m.name, m.id)


func _on_join() -> void:
	if _address.text.strip_edges() == "":
		_status.text = "Enter the host's address, e.g. 192.168.1.20"
		return
	var m := _online_member()
	if m.is_empty():
		return
	_save()
	_status.text = "Connecting…"
	join_requested.emit(_address.text, m.name, m.id)


func _hole_count() -> int:
	return HOLE_OPTIONS[maxi(_holes.selected, 0)]


func _load() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	_mode.select(cfg.get_value("game", "mode", 0))
	_holes.select(clampi(cfg.get_value("game", "holes_option", 0), 0, HOLE_OPTIONS.size() - 1))
	_address.text = cfg.get_value("online", "address", "")
	_refresh()
	var count: int = cfg.get_value("game", "players", 1)
	var counts: Array = Competition.PLAYER_COUNTS[_mode.selected]
	_count.select(maxi(counts.find(count), 0))
	_refresh_rows()
	for i in MAX_PLAYERS:
		_choices[i] = cfg.get_value("players", "slot%d" % i, "")


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # keep other sections, e.g. graphics
	cfg.set_value("game", "mode", _mode.selected)
	cfg.set_value("game", "players", _player_count())
	cfg.set_value("game", "holes_option", _holes.selected)
	cfg.set_value("online", "address", _address.text)
	for i in MAX_PLAYERS:
		cfg.set_value("players", "slot%d" % i, str(_who[i].get_selected_metadata()))
	cfg.save(SETTINGS_PATH)
