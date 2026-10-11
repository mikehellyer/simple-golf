class_name CourseEditor
extends Control
## Edit a course hole by hole while looking at it from above. Every change is
## stored as an override on top of the generated hole, so "Reset hole" always
## returns to the original.

signal preview_requested(hole: Hole)
signal play_requested(course: Course)
signal closed

const PANEL_WIDTH := 380.0
const REBUILD_DELAY := 0.3

var course: Course
var hole_number := 1
var _hole: Hole
var _name: LineEdit
var _hole_label: Label
var _controls := {}
var _value_labels := {}
var _status: Label
var _rebuild_at := -1.0
var _updating := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.12, 0.06, 0.88)
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_right = PANEL_WIDTH
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)

	var title := Label.new()
	title.text = "Course editor"
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)
	_name = LineEdit.new()
	_name.placeholder_text = "Course name"
	_name.max_length = 40
	_name.text_changed.connect(func(t: String) -> void: course.name = t)
	box.add_child(_name)

	var nav := HBoxContainer.new()
	var prev := Button.new()
	prev.text = "  ◀  "
	prev.pressed.connect(func() -> void: _select_hole(hole_number - 1))
	nav.add_child(prev)
	_hole_label = Label.new()
	_hole_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hole_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hole_label.add_theme_font_size_override("font_size", 18)
	nav.add_child(_hole_label)
	var next := Button.new()
	next.text = "  ▶  "
	next.pressed.connect(func() -> void: _select_hole(hole_number + 1))
	nav.add_child(next)
	box.add_child(nav)

	for key in Hole.OVERRIDES:
		if key == "layout":
			continue
		box.add_child(_feature_row(key))

	var hole_buttons := HBoxContainer.new()
	hole_buttons.add_child(_button("New layout", _new_layout))
	hole_buttons.add_child(_button("Reset hole", _reset_hole))
	box.add_child(hole_buttons)
	box.add_child(HSeparator.new())
	var course_buttons := HBoxContainer.new()
	course_buttons.add_child(_button("Save", _save))
	course_buttons.add_child(_button("Copy code", _copy_code))
	course_buttons.add_child(_button("Play it", func() -> void: play_requested.emit(course)))
	course_buttons.add_child(_button("Back", func() -> void: closed.emit()))
	box.add_child(course_buttons)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = Color(1.0, 0.85, 0.5)
	box.add_child(_status)


func open(c: Course) -> void:
	course = c
	_name.text = c.name
	_status.text = "Changes apply to the hole on the right. Save keeps the course on this computer; Copy code lets you share it."
	visible = true
	_select_hole(1)


func _process(_delta: float) -> void:
	if _rebuild_at > 0.0 and Time.get_ticks_msec() / 1000.0 >= _rebuild_at:
		_rebuild_at = -1.0
		_rebuild()


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(action)
	return b


func _feature_row(key: String) -> Control:
	var spec: Array = Hole.OVERRIDES[key]
	var row := VBoxContainer.new()
	var head := HBoxContainer.new()
	var label := Label.new()
	label.text = spec[0]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(label)
	var value := Label.new()
	value.modulate = Color(1, 1, 1, 0.7)
	head.add_child(value)
	row.add_child(head)
	_value_labels[key] = value
	var control: Control
	match key:
		"par":
			var o := OptionButton.new()
			for p in [3, 4, 5]:
				o.add_item("Par %d" % p)
			o.item_selected.connect(func(i: int) -> void: _changed(key, i + 3))
			control = o
		"water", "bunkers":
			var o := OptionButton.new()
			for choice in (Hole.WATER_CHOICES if key == "water" else Hole.BUNKER_CHOICES):
				o.add_item(choice)
			o.item_selected.connect(func(i: int) -> void: _changed(key, i))
			control = o
		_:
			var s := HSlider.new()
			s.min_value = spec[1]
			s.max_value = spec[2]
			s.step = spec[3]
			s.value_changed.connect(func(v: float) -> void: _changed(key, v))
			control = s
	row.add_child(control)
	_controls[key] = control
	return row


func _select_hole(n: int) -> void:
	hole_number = wrapi(n, 1, Course.MAX_HOLES + 1)
	_rebuild()


func _changed(key: String, value: float) -> void:
	if _updating:
		return
	var o := course.hole_overrides(hole_number).duplicate()
	o[key] = value
	course.set_hole_overrides(hole_number, o)
	_show_value(key, value)
	_rebuild_at = Time.get_ticks_msec() / 1000.0 + REBUILD_DELAY


func _new_layout() -> void:
	var o := course.hole_overrides(hole_number).duplicate()
	o.layout = int(o.get("layout", 0)) + 1
	course.set_hole_overrides(hole_number, o)
	_rebuild()


func _reset_hole() -> void:
	course.set_hole_overrides(hole_number, {})
	_rebuild()


func _rebuild() -> void:
	_hole = course.make_hole(hole_number)
	_updating = true
	for key in _controls:
		var v := _hole.feature(key)
		var c: Control = _controls[key]
		if c is OptionButton:
			c.select(int(v) - 3 if key == "par" else int(v))
		else:
			c.value = v
		_show_value(key, v)
	_updating = false
	_hole_label.text = "Hole %d  ·  Par %d  ·  %d yds" % [hole_number, _hole.par,
			roundi(_hole.yardage() * 1.09361)]
	preview_requested.emit(_hole)


func _show_value(key: String, v: float) -> void:
	var text := ""
	match key:
		"length", "fairway_width", "green_size":
			text = "%d yds" % roundi(v * 1.09361)
		"bend", "green_offset":
			text = "%+d yds" % roundi(v * 1.09361)
		"relief":
			text = "%.1f m" % v
		"trees":
			text = "%d%%" % roundi(v * 100.0)
		"pin":
			text = "#%d" % int(v)
	_value_labels[key].text = text


func _save() -> void:
	if course.name.strip_edges() == "":
		_status.text = "Give the course a name first."
		return
	var err := course.save()
	_status.text = "Saved “%s”." % course.name if err == OK else "Couldn't save (%s)." % error_string(err)


func _copy_code() -> void:
	DisplayServer.clipboard_set(course.to_code())
	_status.text = "Course code copied to the clipboard. Paste it into the menu's course code box to play it."
