class_name LobbyMenu
extends Control
## The online waiting room. The host picks the format and adds computer
## players; everyone sees who has joined. Teams are the first two players
## against the last two.

signal start_requested
signal leave_requested

var _net: NetSession
var _title: Label
var _address: Label
var _players: VBoxContainer
var _mode: OptionButton
var _holes: OptionButton
var _cpu_kind: OptionButton
var _host_controls: Array[Control] = []
var _status: Label
var _start: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.12, 0.06, 0.85)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", sb)
	centre.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 30)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_address = Label.new()
	_address.modulate = Color(1, 1, 1, 0.7)
	_address.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_address.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_address)

	_mode = OptionButton.new()
	for m in Competition.MODE_NAMES:
		_mode.add_item(m)
	_mode.item_selected.connect(func(_i: int) -> void: _push_settings())
	box.add_child(_row("Game", _mode))
	_holes = OptionButton.new()
	_holes.add_item("18 holes")
	_holes.add_item("9 holes")
	_holes.item_selected.connect(func(_i: int) -> void: _push_settings())
	box.add_child(_row("Length", _holes))

	var cpu_row := HBoxContainer.new()
	_cpu_kind = OptionButton.new()
	for k in range(1, Competition.KIND_NAMES.size()):
		_cpu_kind.add_item(Competition.KIND_NAMES[k])
	_cpu_kind.select(1)
	_cpu_kind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cpu_row.add_child(_cpu_kind)
	var add := Button.new()
	add.text = "Add computer"
	add.pressed.connect(_add_cpu)
	cpu_row.add_child(add)
	var remove := Button.new()
	remove.text = "Remove"
	remove.pressed.connect(_remove_cpu)
	cpu_row.add_child(remove)
	box.add_child(_row("Computer", cpu_row))
	_host_controls.assign([_mode, _holes, _cpu_kind, add, remove])

	var heading := Label.new()
	heading.text = "Players"
	box.add_child(heading)
	_players = VBoxContainer.new()
	box.add_child(_players)
	_status = Label.new()
	_status.modulate = Color(1.0, 0.85, 0.5)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 10)
	_start = Button.new()
	_start.text = "  Tee off  "
	_start.pressed.connect(func() -> void: start_requested.emit())
	buttons.add_child(_start)
	var leave := Button.new()
	leave.text = "Leave"
	leave.pressed.connect(func() -> void: leave_requested.emit())
	buttons.add_child(leave)
	box.add_child(buttons)


func open(net: NetSession) -> void:
	if _net != net:
		_net = net
		_net.lobby_changed.connect(_refresh)
	visible = true
	_refresh()


func _row(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(90, 0)
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


## Players can enter any of the host's addresses that are on the LAN.
static func lan_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."):
			out.append(a)
	return out


func _refresh() -> void:
	if not visible or _net == null:
		return
	var host := _net.is_host
	_title.text = "Hosting an online game" if host else "Online game"
	if host:
		var addrs := lan_addresses()
		_address.text = "Others join with  %s  (port %d)" % [
				", ".join(addrs) if not addrs.is_empty() else "this computer's address",
				NetSession.DEFAULT_PORT]
	else:
		_address.text = "Waiting for the host to tee off…"
	for c in _host_controls:
		if c is BaseButton:
			c.disabled = not host
	_mode.select(_net.settings.mode)
	_holes.select(0 if _net.settings.holes == 18 else 1)

	for child in _players.get_children():
		child.queue_free()
	var line_up := _net.line_up()
	var teams := Competition.is_team_mode(_net.settings.mode)
	for i in line_up.size():
		var p := line_up[i]
		var l := Label.new()
		var who: String = Competition.KIND_NAMES[p.kind] if p.is_cpu() \
				else ("host" if p.owner == 1 else "online")
		l.text = "%s%s   ·   %s" % ["Team %d: " % (i / 2 + 1) if teams else "", p.name, who]
		l.add_theme_color_override("font_color", p.colour)
		_players.add_child(l)

	var counts: Array = Competition.PLAYER_COUNTS[_net.settings.mode]
	var ok := line_up.size() in counts
	_start.visible = host
	_start.disabled = not ok
	if ok:
		_status.text = ""
	else:
		_status.text = "%s needs %s players; there are %d." % [
				Competition.MODE_NAMES[_net.settings.mode],
				" or ".join(counts.map(func(c: int) -> String: return str(c))), line_up.size()]


func _push_settings() -> void:
	if _net == null or not _net.is_host:
		return
	var s := _net.settings.duplicate(true)
	s.mode = _mode.selected
	s.holes = 18 if _holes.selected == 0 else 9
	_net.set_settings(s)


func _add_cpu() -> void:
	if _net.members.size() + _net.settings.cpus.size() >= 4:
		return
	var s := _net.settings.duplicate(true)
	s.cpus.append(_cpu_kind.selected + 1)
	_net.set_settings(s)


func _remove_cpu() -> void:
	var s := _net.settings.duplicate(true)
	if not s.cpus.is_empty():
		s.cpus.pop_back()
		_net.set_settings(s)
