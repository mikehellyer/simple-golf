class_name Hud
extends CanvasLayer
## On-screen information: hole card, shot info, wind, messages and the swing meter.


class WindArrow:
	extends Control
	## Points the way the wind blows, relative to the player's aim (up = tailwind).
	var direction := Vector2.ZERO

	func _draw() -> void:
		var c := size / 2.0
		draw_circle(c, size.x / 2.0, Color(0, 0, 0, 0.45))
		if direction.length() < 0.01:
			draw_circle(c, 4.0, Color.WHITE)
			return
		var d := direction.normalized() * size.x * 0.38
		var side := Vector2(-d.y, d.x) * 0.45
		draw_line(c - d, c + d * 0.4, Color.WHITE, 3.0)
		draw_colored_polygon(PackedVector2Array([c + d, c + d * 0.3 + side, c + d * 0.3 - side]), Color.WHITE)


var meter: SwingMeter
var scorecard: ScorecardView
var _player_label: Label
var _hole_label: Label
var _shot_label: Label
var _standings_panel: PanelContainer
var _standings: Label
var _wind_label: Label
var _wind: WindArrow
var _message: Label
var _hint: Label
var _update_label: Label


func _ready() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_player_label = _label(24)
	_hole_label = _label(20)
	_shot_label = _label(16)
	box.add_child(_player_label)
	box.add_child(_hole_label)
	box.add_child(_shot_label)

	_wind = WindArrow.new()
	_wind.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_wind.offset_left = -92
	_wind.offset_right = -28
	_wind.offset_top = 16
	_wind.offset_bottom = 80
	add_child(_wind)
	_wind_label = _label(15)
	_wind_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_wind_label.offset_left = -130
	_wind_label.offset_right = -10
	_wind_label.offset_top = 84
	_wind_label.offset_bottom = 108
	_wind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_wind_label)

	_standings_panel = PanelContainer.new()
	_standings_panel.add_theme_stylebox_override("panel", _panel_style())
	_standings_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_standings_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_standings_panel.offset_right = -16
	_standings_panel.offset_top = 116
	_standings = _label(15)
	_standings_panel.add_child(_standings)
	add_child(_standings_panel)

	_message = _label(30)
	_message.set_anchors_preset(Control.PRESET_CENTER)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_message.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_message)

	meter = SwingMeter.new()
	meter.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	meter.offset_left = -280
	meter.offset_right = 280
	meter.offset_top = -110
	meter.offset_bottom = -54
	add_child(meter)

	_hint = _label(14)
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.offset_top = -40
	_hint.offset_bottom = -16
	add_child(_hint)

	scorecard = ScorecardView.new()
	scorecard.set_anchors_preset(Control.PRESET_CENTER)
	scorecard.grow_horizontal = Control.GROW_DIRECTION_BOTH
	scorecard.grow_vertical = Control.GROW_DIRECTION_BOTH
	scorecard.visible = false
	add_child(scorecard)

	_update_label = _label(14)
	_update_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_update_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_update_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_update_label.offset_right = -16
	_update_label.offset_bottom = -16
	_update_label.modulate = Color(1.0, 0.9, 0.4)
	add_child(_update_label)


## The player about to swing; hidden for a single player.
func set_player(text: String, colour: Color) -> void:
	_player_label.visible = text != ""
	_player_label.text = text
	_player_label.label_settings.font_color = colour


func set_standings(lines: PackedStringArray) -> void:
	_standings_panel.visible = not lines.is_empty()
	_standings.text = "\n".join(lines)


func set_hole_info(text: String) -> void:
	_hole_label.text = text


func set_shot_info(text: String) -> void:
	_shot_label.text = text


func set_wind(relative: Vector2, mph: float) -> void:
	_wind.direction = relative
	_wind.queue_redraw()
	_wind_label.text = "Calm" if mph < 0.5 else "Wind %d mph" % roundi(mph)


func show_message(text: String) -> void:
	_message.text = text


func set_hint(text: String) -> void:
	_hint.text = text


func show_update(version: String) -> void:
	_update_label.text = "Simple-Golf %s is available — update it from the clubhouse" % version


func set_meter_visible(on: bool) -> void:
	meter.visible = on


func _label(font_size: int) -> Label:
	var l := Label.new()
	var s := LabelSettings.new()
	s.font_size = font_size
	s.outline_size = 5
	s.outline_color = Color(0, 0, 0, 0.8)
	l.label_settings = s
	return l


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.45)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb
