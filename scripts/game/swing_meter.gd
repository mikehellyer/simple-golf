class_name SwingMeter
extends Control
## The classic three-click swing meter.
##
## Click 1 starts the backswing, click 2 sets power as the marker travels
## right (past 100% is overswing), click 3 sets accuracy as it sweeps back
## through the snap line at 0. Early is a push/slice, late a pull/hook.

signal swing_finished(power: float, accuracy: float)
signal clicked

enum Phase { IDLE, BACKSWING, DOWNSWING, DONE }

const MIN_VALUE := -0.2
const MAX_VALUE := 1.1
const BACKSWING_RATE := 0.85
const DOWNSWING_RATE := 1.4
const SWEET_SPOT := 0.025

var phase := Phase.IDLE
var value := 0.0
var power := 0.0
var accuracy := 0.0
## Text drawn above the bar's 100% mark, e.g. a putt length.
var full_label := "100%"


func _ready() -> void:
	custom_minimum_size = Vector2(560, 56)


func reset() -> void:
	phase = Phase.IDLE
	value = 0.0
	power = 0.0
	accuracy = 0.0
	queue_redraw()


func click() -> void:
	clicked.emit()
	match phase:
		Phase.IDLE:
			reset()
			phase = Phase.BACKSWING
		Phase.BACKSWING:
			power = value
			phase = Phase.DOWNSWING
		Phase.DOWNSWING:
			_finish(value)


func _process(delta: float) -> void:
	match phase:
		Phase.BACKSWING:
			value += BACKSWING_RATE * delta
			if value >= MAX_VALUE:
				value = MAX_VALUE
				power = MAX_VALUE
				phase = Phase.DOWNSWING
		Phase.DOWNSWING:
			value -= DOWNSWING_RATE * delta
			if value <= MIN_VALUE:
				_finish(MIN_VALUE)
		_:
			return
	queue_redraw()


func _finish(at: float) -> void:
	value = at
	accuracy = 0.0 if absf(at) < SWEET_SPOT else at
	phase = Phase.DONE
	queue_redraw()
	swing_finished.emit(power, accuracy)


func _x(v: float) -> float:
	return (v - MIN_VALUE) / (MAX_VALUE - MIN_VALUE) * size.x


func _draw() -> void:
	var top := 22.0
	var bar_h := size.y - top
	draw_rect(Rect2(0, top, size.x, bar_h), Color(0, 0, 0, 0.55))
	# Overswing zone.
	draw_rect(Rect2(_x(1.0), top, _x(MAX_VALUE) - _x(1.0), bar_h), Color(0.75, 0.15, 0.1, 0.7))
	# Power fill.
	var fill_to := power if phase in [Phase.DOWNSWING, Phase.DONE] else value
	if phase != Phase.IDLE and fill_to > 0.0:
		draw_rect(Rect2(_x(0.0), top + 4, _x(fill_to) - _x(0.0), bar_h - 8), Color(0.3, 0.8, 0.35, 0.9))
	# Sweet spot and snap line.
	draw_rect(Rect2(_x(-SWEET_SPOT), top, _x(SWEET_SPOT) - _x(-SWEET_SPOT), bar_h), Color(1, 1, 1, 0.35))
	draw_line(Vector2(_x(0.0), top), Vector2(_x(0.0), size.y), Color.WHITE, 2.0)
	for q in [0.25, 0.5, 0.75, 1.0]:
		draw_line(Vector2(_x(q), top + bar_h * 0.6), Vector2(_x(q), size.y), Color(1, 1, 1, 0.5), 1.0)
	var font := get_theme_default_font()
	draw_string(font, Vector2(_x(1.0) - 60, top - 6), full_label, HORIZONTAL_ALIGNMENT_RIGHT, 60, 14)
	if phase != Phase.IDLE:
		var mx := _x(value)
		draw_colored_polygon(PackedVector2Array([Vector2(mx - 7, top - 2), Vector2(mx + 7, top - 2),
				Vector2(mx, top + 10)]), Color(1.0, 0.9, 0.2))
		draw_line(Vector2(mx, top), Vector2(mx, size.y), Color(1.0, 0.9, 0.2), 2.0)
	if phase == Phase.DONE:
		var text := "Power %d%%" % roundi(power * 100.0)
		if accuracy > 0.0:
			text += "  ·  early (push/slice)"
		elif accuracy < 0.0:
			text += "  ·  late (pull/hook)"
		else:
			text += "  ·  pure"
		draw_string(font, Vector2(0, top - 6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
