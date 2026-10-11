class_name Clubhouse
extends Node3D
## The clubhouse lounge, built behind the first tee with a big picture window
## looking down the hole: a fireplace, a trophy cabinet (one cup per round won
## by members), armchairs and the members' board.
##
## Room coordinates: x across (-W/2..W/2), floor at y = 0, z from the back
## wall (-D) to the window (0). The node is placed so the window faces +Z.

const W := 14.0
const D := 10.0
const H := 3.7
const WINDOW_SILL := 0.8
const WINDOW_TOP := 3.1
## Distance from the window wall back to the tee.
const SET_BACK := 26.0

var _fire_light: OmniLight3D
var _board_names: Array[Label3D] = []
var _board_values: Array[Label3D] = []
var _cups := Node3D.new()
var _time := 0.0


## Where the room goes for a hole, and the rectangle (XZ) to keep clear of
## trees: the room itself plus the view down to the tee.
static func clear_area() -> Rect2:
	return Rect2(-W / 2.0 - 6.0, -SET_BACK - D - 6.0, W + 12.0, SET_BACK + D + 6.0)


func build(hole: Hole) -> void:
	# Stand the floor above any ground in the room or between it and the
	# tee, so the view out of the window is clear.
	var floor_y := -INF
	var lowest := INF
	for z in range(int(-SET_BACK - D), 1, 2):
		for x in range(int(-W / 2.0), int(W / 2.0) + 1, 2):
			var h := hole.height_at(x, z)
			floor_y = maxf(floor_y, h)
			if z <= -SET_BACK:
				lowest = minf(lowest, h)
	floor_y += 0.4
	position = Vector3(0.0, floor_y, -SET_BACK)

	var wood := _mat(Color(0.33, 0.2, 0.11), 0.6)
	var dark_wood := _mat(Color(0.2, 0.12, 0.07), 0.5)
	var plaster := _mat(Color(0.86, 0.81, 0.7), 0.9)
	var stone := _mat(Color(0.45, 0.43, 0.4), 1.0)
	var green_cloth := _mat(Color(0.08, 0.25, 0.14), 1.0)
	var leather := _mat(Color(0.35, 0.12, 0.08), 0.45)
	var gold := _mat(Color(0.95, 0.75, 0.25), 0.25)
	gold.metallic = 0.9

	# Shell: foundation, floor, ceiling and beams.
	var plinth := floor_y - lowest + 2.0
	_box(Vector3(W + 0.6, plinth, D + 0.6), Vector3(0, -plinth / 2.0, -D / 2.0), stone)
	_box(Vector3(W, 0.1, D), Vector3(0, -0.05, -D / 2.0), wood)
	_box(Vector3(W, 0.2, D), Vector3(0, H + 0.1, -D / 2.0), plaster)
	for i in 4:
		_box(Vector3(W, 0.25, 0.3), Vector3(0, H - 0.12, -1.5 - i * 2.4), dark_wood)
	_box(Vector3(6.0, 0.02, 4.0), Vector3(0, 0.01, -4.5), green_cloth)

	# Walls with wood panelling below a dado rail.
	_wall(Vector3(W, H, 0.3), Vector3(0, H / 2.0, -D - 0.15), plaster, wood, Vector3(0, 0, 1))
	_wall(Vector3(0.3, H, D), Vector3(-W / 2.0 - 0.15, H / 2.0, -D / 2.0), plaster, wood, Vector3(1, 0, 0))
	_wall(Vector3(0.3, H, D), Vector3(W / 2.0 + 0.15, H / 2.0, -D / 2.0), plaster, wood, Vector3(-1, 0, 0))

	# The picture window.
	_box(Vector3(W, WINDOW_SILL, 0.3), Vector3(0, WINDOW_SILL / 2.0, 0.15), wood)
	_box(Vector3(W, H - WINDOW_TOP, 0.3), Vector3(0, (H + WINDOW_TOP) / 2.0, 0.15), plaster)
	_box(Vector3(W, 0.08, 0.45), Vector3(0, WINDOW_SILL + 0.04, 0.1), dark_wood)
	for i in 8:
		var x := -W / 2.0 + i * (W / 7.0)
		_box(Vector3(0.12, WINDOW_TOP - WINDOW_SILL, 0.2), Vector3(x, (WINDOW_SILL + WINDOW_TOP) / 2.0, 0.15), dark_wood)
	_box(Vector3(W, 0.08, 0.2), Vector3(0, 2.3, 0.15), dark_wood)

	# Fireplace on the left wall.
	var fx := -W / 2.0 + 0.3
	_box(Vector3(0.7, 2.3, 2.6), Vector3(fx, 1.15, -5.0), stone)
	_box(Vector3(0.72, 1.0, 1.3), Vector3(fx + 0.02, 0.55, -5.0), _mat(Color(0.05, 0.04, 0.04), 1.0))
	_box(Vector3(0.9, 0.12, 3.0), Vector3(fx + 0.1, 2.35, -5.0), dark_wood)
	var fire := _mat(Color(1.0, 0.45, 0.1), 1.0)
	fire.emission_enabled = true
	fire.emission = Color(1.0, 0.45, 0.1)
	fire.emission_energy_multiplier = 3.0
	for k in 3:
		_box(Vector3(0.25, 0.25 + k * 0.08, 0.25), Vector3(fx + 0.15, 0.2, -5.35 + k * 0.35), fire)
	_fire_light = OmniLight3D.new()
	_fire_light.light_color = Color(1.0, 0.6, 0.3)
	_fire_light.omni_range = 7.0
	_fire_light.position = Vector3(fx + 1.0, 0.7, -5.0)
	add_child(_fire_light)
	# A painting of a golf hole above the mantel.
	_box(Vector3(0.06, 1.0, 1.6), Vector3(-W / 2.0 + 0.04, 2.95, -5.0), gold)
	_box(Vector3(0.07, 0.85, 1.45), Vector3(-W / 2.0 + 0.05, 2.95, -5.0), _mat(Color(0.35, 0.6, 0.3), 1.0))
	_box(Vector3(0.075, 0.3, 1.45), Vector3(-W / 2.0 + 0.055, 3.25, -5.0), _mat(Color(0.55, 0.7, 0.9), 1.0))

	# Trophy cabinet on the right wall.
	var cx := W / 2.0 - 0.35
	_box(Vector3(0.6, 2.4, 2.8), Vector3(cx, 1.2, -5.0), dark_wood)
	_box(Vector3(0.5, 2.1, 2.5), Vector3(cx - 0.06, 1.25, -5.0), _mat(Color(0.12, 0.08, 0.05), 1.0))
	for i in 3:
		_box(Vector3(0.5, 0.05, 2.5), Vector3(cx - 0.06, 0.45 + i * 0.65, -5.0), wood)
	_cups.position = Vector3(cx - 0.1, 0.0, -5.0)
	add_child(_cups)
	var cabinet_light := OmniLight3D.new()
	cabinet_light.light_color = Color(1.0, 0.9, 0.7)
	cabinet_light.light_energy = 0.6
	cabinet_light.omni_range = 2.0
	cabinet_light.position = Vector3(cx - 0.5, 1.8, -5.0)
	add_child(cabinet_light)

	# Armchairs and a table facing the window.
	for x in [-2.6, 2.6]:
		_armchair(Vector3(x, 0, -4.2), leather)
	var table := CylinderMesh.new()
	table.top_radius = 0.45
	table.bottom_radius = 0.45
	table.height = 0.05
	_mesh(table, Vector3(0, 0.55, -3.8), dark_wood)
	_box(Vector3(0.1, 0.55, 0.1), Vector3(0, 0.27, -3.8), dark_wood)

	# A golf bag by the window.
	var bag := CylinderMesh.new()
	bag.top_radius = 0.17
	bag.bottom_radius = 0.15
	bag.height = 0.9
	_mesh(bag, Vector3(5.8, 0.45, -0.9), _mat(Color(0.55, 0.08, 0.08), 0.6))
	for k in 4:
		var shaft := CylinderMesh.new()
		shaft.top_radius = 0.012
		shaft.bottom_radius = 0.012
		shaft.height = 0.5
		_mesh(shaft, Vector3(5.75 + k * 0.05, 1.1, -0.9 + (k % 2) * 0.06), _mat(Color(0.75, 0.75, 0.78), 0.3))
		_box(Vector3(0.1, 0.06, 0.06), Vector3(5.75 + k * 0.05, 1.37, -0.9 + (k % 2) * 0.06),
				_mat(Color(0.15, 0.15, 0.15), 0.4))

	# The members' board on the back wall.
	_box(Vector3(5.4, 2.4, 0.08), Vector3(0, 2.15, -D + 0.04), gold)
	_box(Vector3(5.2, 2.2, 0.1), Vector3(0, 2.15, -D + 0.05), green_cloth)
	var title := _label("MEMBERS", 64, Color(0.95, 0.8, 0.35))
	title.position = Vector3(0, 3.0, -D + 0.12)
	for i in 8:
		var who := _label("", 40, Color(0.95, 0.92, 0.8))
		who.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		who.position = Vector3(-1.9, 2.6 - i * 0.22, -D + 0.12)
		_board_names.append(who)
		var avg := _label("", 40, Color(0.95, 0.92, 0.8))
		avg.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		avg.position = Vector3(1.9, 2.6 - i * 0.22, -D + 0.12)
		_board_values.append(avg)

	# Warm ceiling lights.
	for x in [-3.5, 3.5]:
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.85, 0.65)
		lamp.light_energy = 1.1
		lamp.omni_range = 9.0
		lamp.position = Vector3(x, H - 0.5, -5.0)
		add_child(lamp)


## Lists members on the board: [[name, scoring average text], ...].
func set_members(rows: Array) -> void:
	for i in _board_names.size():
		_board_names[i].text = str(rows[i][0]) if i < rows.size() else ""
		_board_values[i].text = str(rows[i][1]) if i < rows.size() else ""
	if rows.is_empty():
		_board_names[0].text = "(no members yet)"


## One cup in the cabinet for each round won by a member (up to 18).
func set_trophies(count: int) -> void:
	for c in _cups.get_children():
		c.queue_free()
	var gold := _mat(Color(0.95, 0.75, 0.25), 0.2)
	gold.metallic = 1.0
	var silver := _mat(Color(0.85, 0.86, 0.9), 0.2)
	silver.metallic = 1.0
	# The club championship trophy is always there.
	count = clampi(count + 1, 1, 18)
	for i in count:
		var shelf := i / 6
		var slot := i % 6
		var at := Vector3(0, 0.48 + shelf * 0.65, -1.05 + slot * 0.42)
		var cup := CylinderMesh.new()
		cup.top_radius = 0.09
		cup.bottom_radius = 0.035
		cup.height = 0.2
		var m := MeshInstance3D.new()
		m.mesh = cup
		m.material_override = gold if i % 3 != 2 else silver
		m.position = at + Vector3(0, 0.2, 0)
		_cups.add_child(m)
		var base := BoxMesh.new()
		base.size = Vector3(0.1, 0.08, 0.1)
		var b := MeshInstance3D.new()
		b.mesh = base
		b.material_override = _mat(Color(0.15, 0.1, 0.06), 0.5)
		b.position = at + Vector3(0, 0.06, 0)
		_cups.add_child(b)


## Camera spots (world space): looking out of the window, or at the board.
func view(which: String) -> Array[Vector3]:
	match which:
		# The panel covers the right of the screen, so frame things on the left.
		"members":
			return [to_global(Vector3(-0.8, 1.7, -2.6)), to_global(Vector3(3.2, 2.0, -D))]
	return [to_global(Vector3(5.0, 1.7, -D + 1.0)), to_global(Vector3(0.5, 1.3, 0.0))]


func _process(delta: float) -> void:
	_time += delta
	if _fire_light:
		_fire_light.light_energy = 1.4 + 0.35 * sin(_time * 7.0) * sin(_time * 3.3 + 1.0)


func _wall(size: Vector3, centre: Vector3, upper: Material, lower: Material, inward: Vector3) -> void:
	_box(size, centre, upper)
	var panel := Vector3(size.x if size.x > 1.0 else 0.06, 1.1, size.z if size.z > 1.0 else 0.06)
	_box(panel, Vector3(centre.x, 0.55, centre.z) + inward * 0.17, lower)
	var rail := Vector3(panel.x, 0.06, panel.z + (0.04 if panel.z < 1.0 else 0.0))
	_box(rail, Vector3(centre.x, 1.12, centre.z) + inward * 0.19, lower)


func _armchair(at: Vector3, mat: Material) -> void:
	_box(Vector3(0.9, 0.45, 0.8), at + Vector3(0, 0.22, 0), mat)
	_box(Vector3(0.9, 0.7, 0.2), at + Vector3(0, 0.75, -0.4), mat)
	for side in [-0.5, 0.5]:
		_box(Vector3(0.15, 0.3, 0.8), at + Vector3(side, 0.55, 0), mat)


func _box(size: Vector3, centre: Vector3, mat: Material) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mesh(b, centre, mat)


func _mesh(mesh: Mesh, centre: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = centre
	add_child(mi)
	return mi


func _label(text: String, size: int, colour: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = colour
	l.outline_size = 0
	l.shaded = false
	add_child(l)
	return l


static func _mat(colour: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = roughness
	return m
