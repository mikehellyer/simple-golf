class_name ShotPanel
extends VBoxContainer
## The MicroProse-style shot controls down the right of the screen: a big
## SWING button (the only place a mouse click swings), tee height and ball
## position, and moving the ball along the tee box.

signal swing_pressed
signal tee_height_pressed
signal ball_position_pressed
signal tee_move_pressed(direction: int)
signal camera_pressed
## The original's green icons: view from behind the hole, gridlines, speed.
signal view180_pressed
signal grid_pressed
signal speed_pressed

const CAMERAS := ["Behind", "TV", "Side", "Green", "Overhead"]


## A button that draws its own little picture above its caption.
class IconButton:
	extends Button
	## "swing", "tee" or "stance"
	var kind := "swing"
	var value := 0
	var caption := ""

	func _init(icon_kind: String, size_px: Vector2) -> void:
		kind = icon_kind
		custom_minimum_size = size_px
		focus_mode = Control.FOCUS_NONE

	func _draw() -> void:
		var c := size / 2.0
		var ink := Color(1, 1, 1, 0.95) if not disabled else Color(1, 1, 1, 0.35)
		var font := get_theme_default_font()
		match kind:
			"swing":
				# A club head swinging through an arc.
				var r := size.x * 0.28
				draw_arc(c + Vector2(0, -6), r, PI * 0.95, PI * 2.05, 24, Color(1, 1, 1, 0.35), 3.0)
				var tip := c + Vector2(0, -6) + Vector2.from_angle(PI * 1.75) * r
				draw_line(c + Vector2(-2, -6 - r * 0.2), tip, ink, 3.0)
				draw_rect(Rect2(tip - Vector2(4, 3), Vector2(12, 7)), ink)
				draw_circle(c + Vector2(r * 0.55, r * 0.35 - 6), 4.0, ink)
			"tee":
				# A tee peg in the ground with the ball sitting at the chosen height.
				var ground := c.y + 8.0
				draw_line(Vector2(c.x - 22, ground), Vector2(c.x + 22, ground), Color(0.5, 0.85, 0.5, 0.8), 2.0)
				var peg_top := ground - 4.0 - value * 6.0
				draw_line(Vector2(c.x, ground + 8.0), Vector2(c.x, peg_top), Color(0.95, 0.85, 0.6), 3.0)
				draw_line(Vector2(c.x - 4, peg_top), Vector2(c.x + 4, peg_top), Color(0.95, 0.85, 0.6), 2.0)
				draw_circle(Vector2(c.x, peg_top - 6.0), 6.0, ink)
			"camera":
				# A film camera on a tripod, with the view number.
				draw_rect(Rect2(c + Vector2(-16, -20), Vector2(26, 16)), ink)
				draw_colored_polygon(PackedVector2Array([c + Vector2(10, -16), c + Vector2(20, -22),
						c + Vector2(20, -2), c + Vector2(10, -8)]), ink)
				for leg in [-10.0, 0.0, 10.0]:
					draw_line(c + Vector2(-3, -4), c + Vector2(leg - 3, 14), ink, 2.0)
				draw_string(get_theme_default_font(), c + Vector2(-13, -7), str(value + 1),
						HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.BLACK)
			"view180":
				# A flag with an eye looking back from behind it.
				draw_line(c + Vector2(-6, 14), c + Vector2(-6, -18), ink, 2.0)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-6, -18), c + Vector2(10, -13),
						c + Vector2(-6, -8)]), Color(0.95, 0.25, 0.2))
				draw_arc(c + Vector2(10, 6), 7.0, PI * 1.15, PI * 1.85, 8, ink, 2.0)
				draw_arc(c + Vector2(10, 2), 7.0, PI * 0.15, PI * 0.85, 8, ink, 2.0)
				draw_circle(c + Vector2(10, 4), 2.5, ink)
			"grid":
				# Gridlines draped over a sloping green.
				for i in 5:
					var t := i / 4.0
					draw_line(c + Vector2(-22 + t * 8, -16 + t * 30), c + Vector2(22 - t * 4, -10 + t * 26), ink, 1.5)
					draw_line(c + Vector2(-22 + t * 44, -16 + t * 6), c + Vector2(-14 + t * 36, 14 + t * 2), ink, 1.5)
			"speed":
				# A ball with speed lines behind it.
				draw_circle(c + Vector2(10, -2), 7.0, ink)
				for k in 3:
					draw_line(c + Vector2(-22, -8 + k * 6), c + Vector2(-2 - k * 3, -8 + k * 6), ink, 2.0)
			"stance":
				# Two feet seen from above, with the ball back, centre or forward
				# (the target is to the left, as for a right-handed golfer).
				var y := c.y - 4.0
				for fx in [-14.0, 14.0]:
					draw_rect(Rect2(Vector2(c.x + fx - 4, y - 10), Vector2(8, 20)), Color(0.75, 0.75, 0.8, 0.9))
				draw_line(Vector2(c.x - 26, y - 18), Vector2(c.x - 34, y - 18), ink, 2.0)
				draw_colored_polygon(PackedVector2Array([Vector2(c.x - 38, y - 18), Vector2(c.x - 32, y - 22),
						Vector2(c.x - 32, y - 14)]), ink)
				draw_circle(Vector2(c.x - value * 9.0, y + 16.0), 5.0, ink)
		if caption != "":
			draw_string(font, Vector2(0, size.y - 8), caption, HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, ink)


var _swing: IconButton
var _tee: IconButton
var _stance: IconButton
var _camera: IconButton
var _green_row: HBoxContainer
var _view180: IconButton
var _grid: IconButton
var _speed: IconButton
var _move: HBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_swing = IconButton.new("swing", Vector2(108, 108))
	_swing.pressed.connect(func() -> void: swing_pressed.emit())
	_style(_swing, Color(0.16, 0.5, 0.22, 0.92), 54)
	add_child(_swing)
	_tee = IconButton.new("tee", Vector2(108, 84))
	_tee.pressed.connect(func() -> void: tee_height_pressed.emit())
	_style(_tee, Color(0.05, 0.1, 0.06, 0.82), 10)
	add_child(_tee)
	_stance = IconButton.new("stance", Vector2(108, 84))
	_stance.pressed.connect(func() -> void: ball_position_pressed.emit())
	_style(_stance, Color(0.05, 0.1, 0.06, 0.82), 10)
	add_child(_stance)
	_camera = IconButton.new("camera", Vector2(108, 72))
	_camera.pressed.connect(func() -> void: camera_pressed.emit())
	_style(_camera, Color(0.05, 0.1, 0.06, 0.82), 10)
	add_child(_camera)
	_green_row = HBoxContainer.new()
	_green_row.add_theme_constant_override("separation", 4)
	_view180 = IconButton.new("view180", Vector2(52, 52))
	_view180.tooltip_text = "View from behind the hole (V)"
	_view180.pressed.connect(func() -> void: view180_pressed.emit())
	_grid = IconButton.new("grid", Vector2(52, 52))
	_grid.tooltip_text = "Gridlines (G)"
	_grid.pressed.connect(func() -> void: grid_pressed.emit())
	_speed = IconButton.new("speed", Vector2(52, 52))
	_speed.tooltip_text = "Check the speed of the green"
	_speed.pressed.connect(func() -> void: speed_pressed.emit())
	for b in [_view180, _grid, _speed]:
		_style(b, Color(0.05, 0.1, 0.06, 0.82), 8)
	_green_row.add_child(_view180)
	_green_row.add_child(_grid)
	add_child(_green_row)
	var speed_row := HBoxContainer.new()
	speed_row.add_child(_speed)
	add_child(speed_row)
	_speed.get_parent().visible = false
	_move = HBoxContainer.new()
	_move.add_theme_constant_override("separation", 4)
	for d in [-1, 1]:
		var b := Button.new()
		b.text = "◀" if d < 0 else "▶"
		b.tooltip_text = "Move the ball along the tee"
		b.custom_minimum_size = Vector2(52, 36)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: tee_move_pressed.emit(d))
		_style(b, Color(0.05, 0.1, 0.06, 0.82), 8)
		_move.add_child(b)
	add_child(_move)


## Shows the controls that apply to this shot.
## near_green: within 30 yards of the green, where the green icons appear.
func show_for(on_tee: bool, putting: bool, tee_height: int, ball_position: int, camera := 1,
		near_green := false) -> void:
	visible = true
	_green_row.visible = near_green
	_speed.get_parent().visible = near_green
	_camera.visible = not putting
	_camera.value = camera
	_camera.caption = "View: %s" % CAMERAS[camera]
	_camera.queue_redraw()
	_tee.visible = on_tee and not putting
	_move.visible = on_tee
	_stance.visible = not putting
	_tee.value = tee_height
	_tee.caption = "Tee: %s" % Clubs.TEE_HEIGHTS[tee_height]
	_stance.value = ball_position
	_stance.caption = "Ball: %s" % Clubs.BALL_POSITIONS[ball_position]
	_tee.queue_redraw()
	_stance.queue_redraw()


## While swinging, the set-up is locked and the SWING button prompts each click.
func set_phase(phase: SwingMeter.Phase) -> void:
	_swing.caption = {SwingMeter.Phase.IDLE: "SWING", SwingMeter.Phase.BACKSWING: "POWER!",
			SwingMeter.Phase.DOWNSWING: "SNAP!", SwingMeter.Phase.DONE: ""}[phase]
	var locked := phase != SwingMeter.Phase.IDLE
	_tee.disabled = locked
	_stance.disabled = locked
	for b in _move.get_children():
		b.disabled = locked
	_swing.disabled = phase == SwingMeter.Phase.DONE
	_swing.queue_redraw()
	_tee.queue_redraw()
	_stance.queue_redraw()


func _style(b: Button, colour: Color, radius: int) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = colour.lightened(0.12) if state == "hover" else (colour.darkened(0.2) if state == "pressed" else colour)
		if state == "disabled":
			sb.bg_color = Color(colour, colour.a * 0.6)
		sb.set_corner_radius_all(radius)
		sb.set_border_width_all(2)
		sb.border_color = Color(1, 1, 1, 0.25)
		b.add_theme_stylebox_override(state, sb)
