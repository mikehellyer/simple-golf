class_name SetupMenu
extends Control
## The first screen: pick a format and who is playing. The last line-up is
## remembered between sessions.

signal start_requested(mode: int, players: Array, holes: int)
signal host_requested(player_name: String)
signal join_requested(address: String, player_name: String)
signal quit_requested

const SETTINGS_PATH := "user://settings.cfg"
const MAX_PLAYERS := 4

var _mode: OptionButton
var _count: OptionButton
var _holes: OptionButton
var _address: LineEdit
var _status: Label
var _info: Label
var _rows: Array[HBoxContainer] = []
var _tags: Array[Label] = []
var _names: Array[LineEdit] = []
var _kinds: Array[OptionButton] = []
var _start: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.12, 0.06, 0.82)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", sb)
	centre.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Simple-Golf"
	title.add_theme_font_size_override("font_size", 46)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := Label.new()
	sub.text = "v%s  ·  a modern MicroProse Golf" % Updater.current_version()
	sub.modulate = Color(1, 1, 1, 0.6)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

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
	_holes.add_item("18 holes")
	_holes.add_item("9 holes")
	box.add_child(_labelled("Length", _holes))

	for i in MAX_PLAYERS:
		var row := HBoxContainer.new()
		var tag := Label.new()
		tag.custom_minimum_size = Vector2(70, 0)
		tag.add_theme_color_override("font_color", Competition.COLOURS[i])
		row.add_child(tag)
		var name_edit := LineEdit.new()
		name_edit.max_length = 12
		name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_edit.text_submitted.connect(func(_t: String) -> void: _on_start())
		row.add_child(name_edit)
		var kind := OptionButton.new()
		for k in Competition.KIND_NAMES:
			kind.add_item(k)
		kind.custom_minimum_size = Vector2(150, 0)
		row.add_child(kind)
		box.add_child(row)
		_rows.append(row)
		_tags.append(tag)
		_names.append(name_edit)
		_kinds.append(kind)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_start = Button.new()
	_start.text = "  Tee off  "
	_start.pressed.connect(_on_start)
	buttons.add_child(_start)
	var watch := Button.new()
	watch.text = "Watch the computer"
	watch.pressed.connect(_on_watch)
	buttons.add_child(watch)
	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func() -> void: quit_requested.emit())
	buttons.add_child(quit)
	box.add_child(buttons)

	box.add_child(HSeparator.new())
	var online := HBoxContainer.new()
	online.add_theme_constant_override("separation", 8)
	var online_label := Label.new()
	online_label.text = "Online"
	online_label.custom_minimum_size = Vector2(70, 0)
	online.add_child(online_label)
	var host := Button.new()
	host.text = "Host a game"
	host.pressed.connect(func() -> void:
		_save()
		host_requested.emit(_first_name()))
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
	_refresh()


func open(status := "") -> void:
	visible = true
	_status.text = status
	_start.grab_focus()


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


func _players(all_cpu: bool) -> Array[Competition.Player]:
	var out: Array[Competition.Player] = []
	for i in _player_count():
		var player_name := _names[i].text.strip_edges()
		if player_name == "":
			player_name = "Player %d" % (i + 1)
		var kind := _kinds[i].selected as Competition.Kind
		if all_cpu:
			kind = Competition.Kind.CPU_HARD if i % 2 == 0 else Competition.Kind.CPU_MEDIUM
		out.append(Competition.Player.new(player_name, kind, Competition.COLOURS[i]))
	return out


func _on_start() -> void:
	_save()
	visible = false
	start_requested.emit(_mode.selected, _players(false), _hole_count())


func _on_watch() -> void:
	_save()
	visible = false
	start_requested.emit(_mode.selected, _players(true), _hole_count())


func _on_join() -> void:
	if _address.text.strip_edges() == "":
		_status.text = "Enter the host's address, e.g. 192.168.1.20"
		return
	_save()
	_status.text = "Connecting…"
	join_requested.emit(_address.text, _first_name())


func _first_name() -> String:
	var n := _names[0].text.strip_edges()
	return n if n != "" else "Player 1"


func _hole_count() -> int:
	return 18 if _holes.selected == 0 else 9


func _load() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	_mode.select(cfg.get_value("game", "mode", 0))
	_holes.select(cfg.get_value("game", "holes_option", 0))
	_address.text = cfg.get_value("online", "address", "")
	_refresh()
	var count: int = cfg.get_value("game", "players", 1)
	var counts: Array = Competition.PLAYER_COUNTS[_mode.selected]
	_count.select(maxi(counts.find(count), 0))
	for i in MAX_PLAYERS:
		_names[i].text = cfg.get_value("players", "name%d" % i, "Player %d" % (i + 1))
		var default_kind := Competition.Kind.HUMAN if i == 0 else Competition.Kind.CPU_MEDIUM
		_kinds[i].select(cfg.get_value("players", "kind%d" % i, default_kind))


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "mode", _mode.selected)
	cfg.set_value("game", "players", _player_count())
	cfg.set_value("game", "holes_option", _holes.selected)
	cfg.set_value("online", "address", _address.text)
	for i in MAX_PLAYERS:
		cfg.set_value("players", "name%d" % i, _names[i].text)
		cfg.set_value("players", "kind%d" % i, _kinds[i].selected)
	cfg.save(SETTINGS_PATH)
