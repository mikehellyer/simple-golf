class_name SettingsPanel
extends PanelContainer
## Clubhouse "Settings": shadows and anti-aliasing (applied straight away)
## and the renderer (needs a restart).

signal changed(settings: GraphicsSettings)

var settings: GraphicsSettings
var _shadows: OptionButton
var _aa: OptionButton
var _renderer: OptionButton
var _restart: Button
var _note: Label
var _updates: CheckBox
var _map_first: CheckBox
var _pixel: CheckBox
var _pads: Label


func _ready() -> void:
	add_theme_stylebox_override("panel", ClubhouseMenu.panel_style())
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 0)
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	var heading := Label.new()
	heading.text = "Settings"
	heading.add_theme_font_size_override("font_size", 24)
	box.add_child(heading)

	_shadows = _option(GraphicsSettings.SHADOWS)
	box.add_child(_row("Shadows", _shadows))
	_aa = _option(GraphicsSettings.ANTI_ALIASING)
	box.add_child(_row("Anti-aliasing", _aa))
	_renderer = _option(GraphicsSettings.RENDERERS)
	box.add_child(_row("Renderer", _renderer))
	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.modulate = Color(1, 1, 1, 0.7)
	box.add_child(_note)
	_restart = Button.new()
	_restart.text = "Restart now"
	_restart.pressed.connect(func() -> void: settings.restart(get_tree()))
	box.add_child(_restart)

	box.add_child(HSeparator.new())
	_pixel = CheckBox.new()
	_pixel.text = "Classic pixel-art golfer (as in MicroProse Golf)"
	_pixel.toggled.connect(func(_on: bool) -> void: _on_changed())
	box.add_child(_pixel)
	_map_first = CheckBox.new()
	_map_first.text = "Start each shot on the hole map (as in MicroProse Golf)"
	_map_first.toggled.connect(func(_on: bool) -> void: _on_changed())
	box.add_child(_map_first)
	_updates = CheckBox.new()
	_updates.text = "Check for updates when the game starts"
	_updates.toggled.connect(func(_on: bool) -> void: _on_changed())
	box.add_child(_updates)

	box.add_child(HSeparator.new())
	var pad_title := Label.new()
	pad_title.text = "Controller"
	pad_title.add_theme_font_size_override("font_size", 18)
	box.add_child(pad_title)
	_pads = Label.new()
	_pads.modulate = Color(1, 1, 1, 0.75)
	box.add_child(_pads)
	var legend := GridContainer.new()
	legend.columns = 2
	legend.add_theme_constant_override("h_separation", 14)
	for row in PadMap.LEGEND:
		var k := Label.new()
		k.text = row[0]
		k.add_theme_font_size_override("font_size", 13)
		k.add_theme_color_override("font_color", Color(0.95, 0.82, 0.45))
		legend.add_child(k)
		var v := Label.new()
		v.text = row[1]
		v.add_theme_font_size_override("font_size", 13)
		legend.add_child(v)
	box.add_child(legend)
	Input.joy_connection_changed.connect(func(_d: int, _c: bool) -> void: _refresh_pads())

	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.modulate = Color(1, 1, 1, 0.55)
	help.text = "If the game feels slow, turn shadows to Low or Off and anti-aliasing to FXAA. " \
			+ "If you see flickering or other graphics glitches, try the Compatibility (OpenGL) renderer."
	box.add_child(help)

	for o in [_shadows, _aa, _renderer]:
		o.item_selected.connect(func(_i: int) -> void: _on_changed())


func _refresh_pads() -> void:
	var names := PackedStringArray()
	for d in Input.get_connected_joypads():
		names.append(Input.get_joy_name(d))
	_pads.text = "Connected: " + ", ".join(names) if not names.is_empty() \
			else "No controller connected. Plug in a gamepad or joystick at any time."


func open(s: GraphicsSettings) -> void:
	_refresh_pads()
	settings = s
	_shadows.select(s.shadows)
	_aa.select(s.anti_aliasing)
	_renderer.select(s.renderer)
	_updates.set_pressed_no_signal(s.check_updates)
	_map_first.set_pressed_no_signal(s.map_first)
	_pixel.set_pressed_no_signal(s.pixel_golfer)
	_update_note()


func _on_changed() -> void:
	settings.shadows = _shadows.selected
	settings.anti_aliasing = _aa.selected
	settings.renderer = _renderer.selected
	settings.check_updates = _updates.button_pressed
	settings.map_first = _map_first.button_pressed
	settings.pixel_golfer = _pixel.button_pressed
	settings.save()
	_update_note()
	changed.emit(settings)


func _update_note() -> void:
	var restart := settings.needs_restart()
	_restart.visible = restart
	_note.text = "The renderer changes after a restart." if restart else ""


func _option(items: Array) -> OptionButton:
	var o := OptionButton.new()
	for item in items:
		o.add_item(item)
	return o


func _row(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(130, 0)
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row
