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

	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.modulate = Color(1, 1, 1, 0.55)
	help.text = "If the game feels slow, turn shadows to Low or Off and anti-aliasing to FXAA. " \
			+ "If you see flickering or other graphics glitches, try the Compatibility (OpenGL) renderer."
	box.add_child(help)

	for o in [_shadows, _aa, _renderer]:
		o.item_selected.connect(func(_i: int) -> void: _on_changed())


func open(s: GraphicsSettings) -> void:
	settings = s
	_shadows.select(s.shadows)
	_aa.select(s.anti_aliasing)
	_renderer.select(s.renderer)
	_update_note()


func _on_changed() -> void:
	settings.shadows = _shadows.selected
	settings.anti_aliasing = _aa.selected
	settings.renderer = _renderer.selected
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
