class_name ScorecardView
extends PanelContainer
## A traditional two-row (front nine / back nine) scorecard. Under-par scores
## are circled, over-par scores boxed, as on a real card.

const CELL := Vector2(46, 30)

var _grid: GridContainer
var _title: Label
var _footer: Label


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.97, 0.96, 0.9)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(18)
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 12
	add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	_title = _text("", 22, Color(0.1, 0.3, 0.15))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_grid = GridContainer.new()
	_grid.columns = 11
	_grid.add_theme_constant_override("h_separation", 2)
	_grid.add_theme_constant_override("v_separation", 2)
	box.add_child(_grid)
	_footer = _text("", 18, Color(0.15, 0.15, 0.15))
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_footer)


## current_hole is 1-based; it is highlighted as the hole being played.
func show_card(card: Scorecard, current_hole: int, headline := "") -> void:
	_title.text = headline if headline != "" else "Scorecard — %s" % card.player_name
	for child in _grid.get_children():
		child.queue_free()
	_add_nine(card, 0, "Out", current_hole)
	_add_nine(card, 9, "In", current_hole)
	var played := card.holes_played()
	if played == 0:
		_footer.text = "No holes completed yet"
	else:
		_footer.text = "Total %d  ·  %s after %d hole%s" % [card.total(), card.to_par_text(),
				played, "" if played == 1 else "s"]
	visible = true


func _add_nine(card: Scorecard, first: int, total_label: String, current_hole: int) -> void:
	var last := mini(first + 9, card.hole_count())
	var header := Color(0.1, 0.3, 0.15)
	_cell("Hole", header, Color(0.85, 0.9, 0.82), true)
	for i in range(first, last):
		var bg := Color(1.0, 0.92, 0.5) if i + 1 == current_hole else Color(0.85, 0.9, 0.82)
		_cell(str(i + 1), header, bg, true)
	_cell(total_label, header, Color(0.85, 0.9, 0.82), true)

	_cell("Yds", Color(0.35, 0.35, 0.35), Color.TRANSPARENT)
	var yards := 0
	for i in range(first, last):
		yards += card.yards[i]
		_cell(str(card.yards[i]), Color(0.35, 0.35, 0.35), Color.TRANSPARENT)
	_cell(str(yards), Color(0.35, 0.35, 0.35), Color.TRANSPARENT)

	_cell("Par", Color(0.1, 0.1, 0.1), Color.TRANSPARENT)
	for i in range(first, last):
		_cell(str(card.pars[i]), Color(0.1, 0.1, 0.1), Color.TRANSPARENT)
	_cell(str(card.par_total(first, last)), Color(0.1, 0.1, 0.1), Color.TRANSPARENT, true)

	_cell("Score", Color(0.1, 0.1, 0.1), Color.TRANSPARENT)
	for i in range(first, last):
		if i < card.holes_played():
			_score_cell(card.strokes[i], card.pars[i])
		else:
			_cell("", Color.BLACK, Color.TRANSPARENT)
	var played_here := card.holes_played() > first
	_cell(str(card.total(first, last)) if played_here else "", Color(0.1, 0.1, 0.1), Color.TRANSPARENT, true)


func _cell(text: String, fg: Color, bg: Color, bold := false) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = CELL
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", sb)
	var l := _text(text, 17 if bold else 15, fg)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	_grid.add_child(p)
	return p


func _score_cell(score: int, par: int) -> void:
	var diff := score - par
	var p := _cell(str(score), Color(0.1, 0.1, 0.1), Color.TRANSPARENT, true)
	if diff == 0:
		return
	var sb := StyleBoxFlat.new()
	sb.draw_center = diff <= -2 or diff >= 2
	sb.set_border_width_all(2)
	if diff < 0:
		# Circles: red for birdie, gold fill for eagle or better.
		sb.border_color = Color(0.8, 0.1, 0.1)
		sb.bg_color = Color(1.0, 0.85, 0.3)
		sb.set_corner_radius_all(15)
	else:
		# Boxes: single for bogey, filled for double or worse.
		sb.border_color = Color(0.15, 0.3, 0.7)
		sb.bg_color = Color(0.7, 0.8, 1.0)
		sb.set_corner_radius_all(2)
	sb.set_expand_margin_all(-3)
	p.add_theme_stylebox_override("panel", sb)


func _text(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	return l
