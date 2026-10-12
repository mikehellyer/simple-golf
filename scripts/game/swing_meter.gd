class_name SwingMeter
extends Control
## The classic three-click swing meter, drawn either as MicroProse Golf's
## circular "swingometer" around the golfer (full shots) or as a straight
## bar (putts).
##
## Click 1 starts the backswing, click 2 sets power, click 3 sets accuracy as
## the downswing sweeps back through the snap point at 0. Early is a
## push/slice, late a pull/hook.
##
## On the ring (seen from behind the golfer): a lead-in runs from 3 o'clock
## to 6 o'clock, then the backswing climbs clockwise past 9 o'clock to the
## check mark at 12 o'clock (full power) and on towards 1 o'clock
## (overswing). The downswing comes back down the inner ring to the white
## sweet spot at 6 o'clock, which shrinks the harder you swing.

signal swing_finished(power: float, accuracy: float)
signal clicked

enum Phase { IDLE, BACKSWING, DOWNSWING, DONE }
enum Style { RING, BAR }

const MIN_VALUE := -0.2
const MAX_VALUE := 1.1
const BACKSWING_RATE := 0.85
const DOWNSWING_RATE := 1.4
## Half-width of the sweet spot at full power; easier on soft shots, much
## harder when overswinging.
const SWEET_SPOT := 0.025
const BAR_SIZE := Vector2(560, 34)
const LEAD_IN_TIME := 0.25

var phase := Phase.IDLE
var value := 0.0
var power := 0.0
var accuracy := 0.0
var style := Style.RING
## Where the ring is drawn (screen position of the golfer) and its radius.
var ring_centre := Vector2.ZERO
var ring_radius := 150.0
## Text drawn by the full-power mark, e.g. a putt length.
var full_label := "100%"
## When set, the meter clicks itself at these values (computer players).
var _auto := false
var _auto_power := 0.0
var _auto_accuracy := 0.0
var _lead_in := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func reset() -> void:
	_auto = false
	phase = Phase.IDLE
	value = 0.0
	power = 0.0
	accuracy = 0.0
	_lead_in = 0.0
	queue_redraw()


## Plays a whole swing on its own, stopping at the given power and accuracy.
func autoplay(target_power: float, target_accuracy: float) -> void:
	click()
	_auto = true
	_auto_power = clampf(target_power, 0.02, MAX_VALUE)
	_auto_accuracy = clampf(target_accuracy, MIN_VALUE, _auto_power - 0.01)


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


## How close to the snap point counts as a pure strike, at a given power.
static func sweet_spot(at_power: float) -> float:
	var soft := lerpf(1.6, 1.0, clampf(at_power, 0.0, 1.0))
	return SWEET_SPOT * soft / (1.0 + maxf(at_power - 1.0, 0.0) * 8.0)


func _process(delta: float) -> void:
	match phase:
		Phase.BACKSWING:
			_lead_in = minf(_lead_in + delta / LEAD_IN_TIME, 1.0)
			value += BACKSWING_RATE * delta
			if _auto and value >= _auto_power:
				value = _auto_power
				click()
			elif value >= MAX_VALUE:
				value = MAX_VALUE
				power = MAX_VALUE
				phase = Phase.DOWNSWING
		Phase.DOWNSWING:
			value -= DOWNSWING_RATE * delta
			if _auto and value <= _auto_accuracy:
				_finish(_auto_accuracy)
			elif value <= MIN_VALUE:
				_finish(MIN_VALUE)
		_:
			return
	queue_redraw()


func _finish(at: float) -> void:
	value = at
	accuracy = 0.0 if absf(at) < sweet_spot(power) else at
	phase = Phase.DONE
	queue_redraw()
	swing_finished.emit(power, accuracy)


func _draw() -> void:
	if style == Style.RING:
		_draw_ring()
	else:
		_draw_bar()


# --- The circular swingometer -----------------------------------------------

## Screen angle for a meter value: 6 o'clock is 0, 12 o'clock is full power,
## 1 o'clock is maximum overswing (angles run clockwise on screen).
static func _angle(v: float) -> float:
	if v <= 1.0:
		return PI * 0.5 + v * PI
	return PI * 1.5 + (v - 1.0) / (MAX_VALUE - 1.0) * (PI / 6.0)


func _point(r: float, a: float) -> Vector2:
	return ring_centre + Vector2(cos(a), sin(a)) * r


func _draw_ring() -> void:
	var outer := ring_radius
	var inner := ring_radius - 12.0
	var dim := Color(1, 1, 1, 0.55)
	# Dotted backswing track, from the lead-in at 3 o'clock round to 1 o'clock.
	var a := 0.0
	while a < _angle(MAX_VALUE):
		draw_circle(_point(outer, a), 1.6, dim)
		a += 0.06
	# Overswing: 12 to 1 o'clock.
	draw_arc(ring_centre, outer, _angle(1.0), _angle(MAX_VALUE), 12, Color(0.9, 0.2, 0.15, 0.85), 4.0)
	# Inner downswing track.
	draw_arc(ring_centre, inner, _angle(MIN_VALUE), _angle(1.0), 48, Color(0, 0, 0, 0.35), 3.0)
	# Check marks at 6 and 12 o'clock.
	for v in [0.0, 1.0]:
		var ang := _angle(v)
		draw_line(_point(outer + 8.0, ang), _point(inner - 8.0, ang), Color.WHITE, 2.0)
	# Sweet spot, sized for the power being set.
	var p := power if phase in [Phase.DOWNSWING, Phase.DONE] else maxf(value, 0.0)
	var s := sweet_spot(p if phase != Phase.IDLE else 1.0)
	draw_arc(ring_centre, inner, _angle(-s), _angle(s), 8, Color(1, 1, 1, 0.95), 7.0)
	if phase == Phase.IDLE:
		_ring_label(outer)
		return
	# The lead-in and the power line (white), then the downswing (red).
	draw_arc(ring_centre, outer, 0.0, PI * 0.5 * _lead_in, 12, Color.WHITE, 4.0)
	var top := power if phase in [Phase.DOWNSWING, Phase.DONE] else value
	if top > 0.0:
		draw_arc(ring_centre, outer, _angle(0.0), _angle(top), 48, Color.WHITE, 4.0)
	if phase in [Phase.DOWNSWING, Phase.DONE] and value < top:
		draw_arc(ring_centre, inner, _angle(value), _angle(top), 48, Color(0.95, 0.15, 0.15), 5.0)
	var marker := _point(inner if phase != Phase.BACKSWING else outer, _angle(value))
	draw_circle(marker, 6.0, Color(1.0, 0.9, 0.2))
	_ring_label(outer)


func _ring_label(outer: float) -> void:
	var font := get_theme_default_font()
	var top := _point(outer + 26.0, _angle(1.0))
	draw_string(font, top - Vector2(60, 0), full_label, HORIZONTAL_ALIGNMENT_CENTER, 120, 14)
	if phase == Phase.DONE:
		draw_string(font, _point(outer + 30.0, _angle(0.0)) - Vector2(150, -10), _result_text(),
				HORIZONTAL_ALIGNMENT_CENTER, 300, 15)


# --- The straight bar (putts) -----------------------------------------------

func _bar_rect() -> Rect2:
	return Rect2(Vector2((size.x - BAR_SIZE.x) * 0.5, size.y - 76.0 - BAR_SIZE.y), BAR_SIZE)


func _x(r: Rect2, v: float) -> float:
	return r.position.x + (v - MIN_VALUE) / (MAX_VALUE - MIN_VALUE) * r.size.x


func _draw_bar() -> void:
	var r := _bar_rect()
	var y0 := r.position.y
	var y1 := r.end.y
	draw_rect(r, Color(0, 0, 0, 0.55))
	draw_rect(Rect2(_x(r, 1.0), y0, _x(r, MAX_VALUE) - _x(r, 1.0), r.size.y), Color(0.75, 0.15, 0.1, 0.7))
	var fill_to := power if phase in [Phase.DOWNSWING, Phase.DONE] else value
	if phase != Phase.IDLE and fill_to > 0.0:
		draw_rect(Rect2(_x(r, 0.0), y0 + 4, _x(r, fill_to) - _x(r, 0.0), r.size.y - 8), Color(0.3, 0.8, 0.35, 0.9))
	var s := sweet_spot(power if phase in [Phase.DOWNSWING, Phase.DONE] else maxf(value, 0.0))
	draw_rect(Rect2(_x(r, -s), y0, _x(r, s) - _x(r, -s), r.size.y), Color(1, 1, 1, 0.35))
	draw_line(Vector2(_x(r, 0.0), y0), Vector2(_x(r, 0.0), y1), Color.WHITE, 2.0)
	for q in [0.25, 0.5, 0.75, 1.0]:
		draw_line(Vector2(_x(r, q), y0 + r.size.y * 0.6), Vector2(_x(r, q), y1), Color(1, 1, 1, 0.5), 1.0)
	var font := get_theme_default_font()
	draw_string(font, Vector2(_x(r, 1.0) - 60, y0 - 6), full_label, HORIZONTAL_ALIGNMENT_RIGHT, 60, 14)
	if phase != Phase.IDLE:
		var mx := _x(r, value)
		draw_colored_polygon(PackedVector2Array([Vector2(mx - 7, y0 - 2), Vector2(mx + 7, y0 - 2),
				Vector2(mx, y0 + 10)]), Color(1.0, 0.9, 0.2))
		draw_line(Vector2(mx, y0), Vector2(mx, y1), Color(1.0, 0.9, 0.2), 2.0)
	if phase == Phase.DONE:
		draw_string(font, Vector2(r.position.x, y0 - 6), _result_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14)


func _result_text() -> String:
	var text := "Power %d%%" % roundi(power * 100.0)
	if accuracy > 0.0:
		text += "  ·  early (push/slice)"
	elif accuracy < 0.0:
		text += "  ·  late (pull/hook)"
	else:
		text += "  ·  pure"
	return text
