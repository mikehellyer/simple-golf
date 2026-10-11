class_name MembersPanel
extends PanelContainer
## Club members: join, rename, leave, and each member's career statistics.

signal members_changed

const YARDS := 1.09361

var members: PlayerProfiles
var _list: ItemList
var _name_edit: LineEdit
var _stats: RichTextLabel
var _status: Label
var _confirm: ConfirmationDialog


func _ready() -> void:
	add_theme_stylebox_override("panel", ClubhouseMenu.panel_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var heading := Label.new()
	heading.text = "Local club — members & stats"
	heading.add_theme_font_size_override("font_size", 24)
	box.add_child(heading)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(cols)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(180, 0)
	cols.add_child(left)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(_i: int) -> void: _show_stats())
	left.add_child(_list)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Name"
	_name_edit.max_length = 12
	_name_edit.text_submitted.connect(func(_t: String) -> void: _join())
	left.add_child(_name_edit)
	var join := Button.new()
	join.text = "Join the club"
	join.pressed.connect(_join)
	left.add_child(join)
	var row := HBoxContainer.new()
	var rename := Button.new()
	rename.text = "Rename"
	rename.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rename.pressed.connect(_rename)
	row.add_child(rename)
	var remove := Button.new()
	remove.text = "Remove"
	remove.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	remove.pressed.connect(_ask_remove)
	row.add_child(remove)
	left.add_child(row)

	_stats = RichTextLabel.new()
	_stats.bbcode_enabled = true
	_stats.fit_content = false
	_stats.scroll_active = true
	_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stats.custom_minimum_size = Vector2(320, 380)
	cols.add_child(_stats)

	_status = Label.new()
	_status.modulate = Color(1.0, 0.85, 0.5)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)

	_confirm = ConfirmationDialog.new()
	_confirm.confirmed.connect(_remove)
	add_child(_confirm)


func open(profiles: PlayerProfiles, status := "") -> void:
	members = profiles
	_status.text = status
	refresh()
	if members.members.is_empty():
		_name_edit.grab_focus()


func refresh(select_id := "") -> void:
	var previous := _selected_id() if select_id == "" else select_id
	_list.clear()
	for m in members.members:
		var i := _list.add_item(m.name)
		_list.set_item_metadata(i, m.id)
		_list.set_item_custom_fg_color(i, Competition.COLOURS[int(m.colour) % Competition.COLOURS.size()])
		if m.id == previous:
			_list.select(i)
	if not _list.is_anything_selected() and _list.item_count > 0:
		_list.select(0)
	_show_stats()


func _selected_id() -> String:
	if _list == null or not _list.is_anything_selected():
		return ""
	return str(_list.get_item_metadata(_list.get_selected_items()[0]))


func _join() -> void:
	var m := members.add(_name_edit.text)
	if m.is_empty():
		_status.text = "Enter a name that isn't already a member."
		return
	members.save()
	_name_edit.text = ""
	_status.text = "Welcome to the club, %s!" % m.name
	refresh(m.id)
	members_changed.emit()


func _rename() -> void:
	var id := _selected_id()
	if id == "" or not members.rename(id, _name_edit.text):
		_status.text = "Pick a member, type their new name, then press Rename."
		return
	members.save()
	_name_edit.text = ""
	refresh(id)
	members_changed.emit()


func _ask_remove() -> void:
	var m := members.find(_selected_id())
	if m.is_empty():
		return
	_confirm.dialog_text = "Remove %s from the club? Their statistics will be deleted." % m.name
	_confirm.popup_centered()


func _remove() -> void:
	members.remove(_selected_id())
	members.save()
	refresh()
	members_changed.emit()


func _show_stats() -> void:
	var m := members.find(_selected_id())
	if m.is_empty():
		_stats.text = "[font_size=18]Welcome to the clubhouse![/font_size]\n\n" \
				+ "Type your name and press [b]Join the club[/b] to become a member. " \
				+ "Members' rounds are recorded here: scoring average, best rounds, " \
				+ "fairways and greens hit, putting, driving distance and match results."
		return
	var s: Dictionary = m.stats
	var t := "[font_size=22][b]%s[/b][/font_size]   [color=#bbbbbb]member since %s[/color]\n\n" % [m.name, m.joined]
	if int(s.holes) == 0:
		_stats.text = t + "No golf played yet. Pick %s in a round's line-up and their stats will appear here." % m.name
		return
	var avg := PlayerProfiles.scoring_average(s)
	t += "[b]Rounds[/b] %d   ·   [b]Holes[/b] %d   ·   [b]Scoring average[/b] %s per 18\n" % [
			s.rounds, s.holes, "E" if absf(avg) < 0.05 else "%+.1f" % avg]
	t += "[b]Best 18[/b] %s   ·   [b]Best 9[/b] %s\n\n" % [_best(s.best18), _best(s.best9)]
	t += "[b]Fairways hit[/b] %s   ·   [b]Greens in regulation[/b] %s\n" % [
			PlayerProfiles.percent(s.fairways, s.fairway_chances), PlayerProfiles.percent(s.greens, s.holes)]
	t += "[b]Putts per hole[/b] %.2f   ·   [b]Driving[/b] %s\n\n" % [float(s.putts) / s.holes,
			"–" if int(s.drives) == 0 else "avg %d yds, longest %d yds" % [
				roundi(s.drive_total / s.drives * YARDS), roundi(s.longest_drive * YARDS)]]
	t += "[b]Holes in one[/b] %d · [b]Eagles[/b] %d · [b]Birdies[/b] %d · [b]Pars[/b] %d · [b]Bogeys[/b] %d · [b]Double+[/b] %d\n" % [
			s.hole_in_ones, s.eagles, s.birdies, s.pars, s.bogeys, s.doubles]
	t += "[b]Won[/b] %d · [b]Lost[/b] %d · [b]Halved[/b] %d · [b]Skins[/b] %d\n\n" % [s.wins, s.losses, s.halves, s.skins]
	if not m.history.is_empty():
		t += "[b]Recent rounds[/b]\n"
		for r in m.history:
			var to_par := int(r.strokes) - int(r.par)
			var result: String = {"win": "  [color=#7ee07e]won[/color]", "loss": "  [color=#e08a7e]lost[/color]",
					"halved": "  halved"}.get(r.get("result", ""), "")
			t += "%s   %s   %s, %d holes   [b]%d[/b] (%s)%s\n" % [r.date, r.course,
					Competition.MODE_NAMES[int(r.mode)], r.holes, r.strokes,
					Scorecard.format_to_par(to_par), result]
	_stats.text = t


static func _best(b: Dictionary) -> String:
	if b.is_empty():
		return "–"
	return "%d (%s), %s" % [b.strokes, Scorecard.format_to_par(int(b.strokes) - int(b.par)), b.date]
