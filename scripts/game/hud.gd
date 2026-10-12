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


## How the ball is sitting, as in MicroProse Golf's lie icon.
class LieIcon:
	extends Control
	var surface := Surface.TEE
	var quality := Lie.GOOD

	func _init() -> void:
		custom_minimum_size = Vector2(74, 74)
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.55, 0.75, 0.95))
		var sand := quality in [Lie.SAND_GOOD, Lie.SAND_POOR, Lie.PLUGGED]
		var ground_y := size.y * 0.62
		var ground := Color(0.86, 0.79, 0.58) if sand else Color(0.3, 0.6, 0.22)
		draw_rect(Rect2(0, ground_y, size.x, size.y - ground_y), ground)
		var c := Vector2(size.x * 0.5, ground_y)
		var ball_r := size.x * 0.17
		# How far the ball sits above (+) or below (-) the surface, in radii.
		var sit: float = {Lie.GOOD: 0.9, Lie.FLUFFY: 1.6, Lie.POOR: 0.4, Lie.VERY_POOR: -0.2, Lie.DIVOT: 0.1,
				Lie.SAND_GOOD: 0.8, Lie.SAND_POOR: 0.2, Lie.PLUGGED: -0.55}.get(quality, 0.9)
		if quality == Lie.DIVOT:
			draw_rect(Rect2(c.x - ball_r * 2.2, ground_y, ball_r * 4.4, ball_r * 0.9), Color(0.45, 0.33, 0.2))
		if quality == Lie.PLUGGED:
			draw_arc(c, ball_r * 1.7, PI, TAU, 16, Color(0.7, 0.62, 0.42), 3.0)
		var centre := c - Vector2(0, ball_r * sit)
		if surface == Surface.TEE and quality == Lie.GOOD:
			draw_line(c + Vector2(0, 6), centre + Vector2(0, ball_r), Color(0.95, 0.85, 0.6), 3.0)
		draw_circle(centre, ball_r, Color.WHITE)
		draw_circle(centre + Vector2(-ball_r * 0.3, -ball_r * 0.3), ball_r * 0.25, Color(1, 1, 1, 0.6))
		# Grass blades in front of the ball for rough lies; sand covering a sunk ball.
		var blades: float = {Lie.FLUFFY: 0.9, Lie.POOR: 1.2, Lie.VERY_POOR: 2.0}.get(quality, 0.25 if not sand else 0.0)
		if blades > 0.0:
			for i in 11:
				var x := float(i) / 10.0 * size.x
				var h: float = ball_r * blades * (0.7 + 0.3 * sin(i * 2.3))
				draw_line(Vector2(x, ground_y + 2), Vector2(x + 3, ground_y - h), Color(0.18, 0.45, 0.14), 2.0)
		if sand and sit < 0.5:
			draw_rect(Rect2(0, ground_y, size.x, size.y - ground_y), ground)
		draw_rect(r, Color(1, 1, 1, 0.5), false, 1.5)


signal map_rotate_pressed
signal map_proceed_pressed

var meter: SwingMeter
var map_controls: HBoxContainer
## The bird's-eye window over the cup, shown as a putt comes close.
var cup_view: SubViewportContainer
var _cup_camera: Camera3D
var _lie_icon: LieIcon
var _lie_label: Label
var shot_panel: ShotPanel
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
	var lie_row := HBoxContainer.new()
	lie_row.add_theme_constant_override("separation", 10)
	_lie_icon = LieIcon.new()
	lie_row.add_child(_lie_icon)
	_lie_label = _label(14)
	_lie_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lie_label.custom_minimum_size = Vector2(170, 0)
	_lie_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lie_row.add_child(_lie_label)
	box.add_child(_shot_label)
	box.add_child(lie_row)

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
	meter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(meter)

	shot_panel = ShotPanel.new()
	shot_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	shot_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	shot_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	shot_panel.offset_right = -16
	shot_panel.visible = false
	add_child(shot_panel)

	map_controls = HBoxContainer.new()
	map_controls.add_theme_constant_override("separation", 10)
	map_controls.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	map_controls.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	map_controls.grow_vertical = Control.GROW_DIRECTION_BEGIN
	map_controls.offset_right = -16
	map_controls.offset_bottom = -48
	map_controls.visible = false
	var rotate := Button.new()
	rotate.text = "  ⟳ Rotate  "
	rotate.focus_mode = Control.FOCUS_NONE
	rotate.pressed.connect(func() -> void: map_rotate_pressed.emit())
	map_controls.add_child(rotate)
	var proceed := Button.new()
	proceed.text = "  Proceed ➜  "
	proceed.focus_mode = Control.FOCUS_NONE
	proceed.add_theme_font_size_override("font_size", 22)
	proceed.pressed.connect(func() -> void: map_proceed_pressed.emit())
	map_controls.add_child(proceed)
	add_child(map_controls)

	cup_view = SubViewportContainer.new()
	cup_view.stretch = true
	cup_view.set_anchors_preset(Control.PRESET_CENTER_TOP)
	cup_view.offset_left = -110
	cup_view.offset_right = 110
	cup_view.offset_top = 16
	cup_view.offset_bottom = 236
	cup_view.visible = false
	var sub := SubViewport.new()
	sub.size = Vector2i(220, 220)
	sub.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_cup_camera = Camera3D.new()
	_cup_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cup_camera.size = 3.4
	_cup_camera.cull_mask = 0xFFFFF & ~2
	sub.add_child(_cup_camera)
	cup_view.add_child(sub)
	var frame := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_border_width_all(3)
	sb.border_color = Color(1, 1, 1, 0.8)
	frame.add_theme_stylebox_override("panel", sb)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cup_view.add_child(frame)
	add_child(cup_view)

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


func _process(_delta: float) -> void:
	if shot_panel.visible:
		shot_panel.set_phase(meter.phase)


func set_lie(surface: int, quality: int) -> void:
	_lie_icon.surface = surface
	_lie_icon.quality = quality
	_lie_icon.queue_redraw()
	_lie_label.text = "%s lie\n%s" % [Lie.NAMES[quality], Lie.HINTS[quality]]
	_lie_icon.get_parent().visible = surface != Surface.GREEN


## Shows (or hides) the bird's-eye window looking straight down on the cup.
func show_cup(on: bool, pin := Vector3.ZERO, heading := 0.0) -> void:
	cup_view.visible = on
	if on:
		# Turned so the putt comes up the window from the bottom.
		var b := Basis.looking_at(Vector3.DOWN, Vector3(sin(heading), 0.0, cos(heading)))
		_cup_camera.transform = Transform3D(b, pin + Vector3.UP * 20.0)


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
