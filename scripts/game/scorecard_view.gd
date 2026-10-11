class_name ScorecardView
extends PanelContainer
## A traditional two-row (front nine / back nine) scorecard with one score row
## per ball, plus optional rows such as the match standing or skins won.
## Under-par scores are circled, over-par scores boxed, as on a real card.

const CELL := Vector2(46, 26)
const NAME_WIDTH := 112.0

var _grid: GridContainer
var _title: Label
var _footer: Label


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.97, 0.96, 0.9)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(16)
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 12
	add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	_title = _text("", 21, Color(0.1, 0.3, 0.15))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_grid = GridContainer.new()
	_grid.columns = 11
	_grid.add_theme_constant_override("h_separation", 2)
	_grid.add_theme_constant_override("v_separation", 2)
	box.add_child(_grid)
	_footer = _text("", 17, Color(0.15, 0.15, 0.15))
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_footer)


## current_hole is 1-based and highlighted; 0 highlights nothing.
## extra_rows: [{label: String, values: PackedStringArray (one per hole)}]
func show_cards(cards: Array[Scorecard], current_hole: int, headline: String,
		footer: String, extra_rows: Array[Dictionary] = []) -> void:
	_title.text = headline
	_footer.text = footer
	# One column per hole in a row (up to nine), plus the name and total.
	_grid.columns = mini(cards[0].hole_count(), 9) + 2
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_add_nine(cards, 0, "Out", current_hole, extra_rows)
	if cards[0].hole_count() > 9:
		_add_nine(cards, 9, "In", current_hole, extra_rows)
	visible = true


func _add_nine(cards: Array[Scorecard], first: int, total_label: String, current_hole: int,
		extra_rows: Array[Dictionary]) -> void:
	var card := cards[0]
	var last := mini(first + 9, card.hole_count())
	var header := Color(0.1, 0.3, 0.15)
	var head_bg := Color(0.85, 0.9, 0.82)
	_cell("Hole", header, head_bg, true, NAME_WIDTH)
	for i in range(first, last):
		_cell(str(i + 1), header, Color(1.0, 0.92, 0.5) if i + 1 == current_hole else head_bg, true)
	_cell(total_label, header, head_bg, true)

	var grey := Color(0.35, 0.35, 0.35)
	_cell("Yards", grey, Color.TRANSPARENT, false, NAME_WIDTH)
	var yards := 0
	for i in range(first, last):
		yards += card.yards[i]
		_cell(str(card.yards[i]) if card.yards[i] > 0 else "", grey, Color.TRANSPARENT)
	_cell(str(yards) if yards > 0 else "", grey, Color.TRANSPARENT)

	_cell("Par", Color.BLACK, Color.TRANSPARENT, false, NAME_WIDTH)
	for i in range(first, last):
		_cell(str(card.pars[i]), Color.BLACK, Color.TRANSPARENT)
	_cell(str(card.par_total(first, last)), Color.BLACK, Color.TRANSPARENT, true)

	for c in cards:
		_cell(c.player_name, Color(0.1, 0.1, 0.1), Color.TRANSPARENT, true, NAME_WIDTH)
		for i in range(first, last):
			if i < c.holes_played():
				_score_cell(c.strokes[i], c.pars[i])
			else:
				_cell("", Color.BLACK, Color.TRANSPARENT)
		var played_here := c.holes_played() > first
		_cell(str(c.total(first, last)) if played_here else "", Color(0.1, 0.1, 0.1), Color.TRANSPARENT, true)

	for row in extra_rows:
		var values: PackedStringArray = row.values
		_cell(row.label, Color(0.45, 0.15, 0.1), Color.TRANSPARENT, true, NAME_WIDTH)
		for i in range(first, last):
			_cell(values[i] if i < values.size() else "", Color(0.45, 0.15, 0.1), Color.TRANSPARENT)
		_cell("", Color.BLACK, Color.TRANSPARENT)


func _cell(text: String, fg: Color, bg: Color, bold := false, width := CELL.x) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(width, CELL.y)
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", sb)
	var l := _text(text, 16 if bold else 14, fg)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
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
		sb.set_corner_radius_all(13)
	else:
		# Boxes: single for bogey, filled for double or worse.
		sb.border_color = Color(0.15, 0.3, 0.7)
		sb.bg_color = Color(0.7, 0.8, 1.0)
		sb.set_corner_radius_all(2)
	sb.set_expand_margin_all(-2)
	p.add_theme_stylebox_override("panel", sb)


func _text(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	return l
