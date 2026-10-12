class_name Hole
extends RefCounted
## A procedurally generated golf hole. The same number and seed always give
## the same hole, so a whole course can be shared as a single seed.
##
## The course editor can override individual features (see OVERRIDES). Each
## feature draws from its own random stream, so changing one (say, removing
## the water) leaves everything else about the hole as it was.
##
## The tee sits at the origin and the hole plays along +Z, following a
## quadratic curve (the dogleg) to the green. Everything outside `bounds`
## is out of bounds.

const PARS := [4, 4, 3, 5, 4, 4, 3, 4, 5, 4, 3, 4, 5, 4, 4, 3, 4, 5]
const MARGIN := 40.0
const FRINGE_WIDTH := 2.5
const TREE_CELL := 20.0
const POND_BANK := 14.0

## Editable features: key -> [label, min, max, step]. Distances in metres.
const OVERRIDES := {
	par = ["Par", 3, 5, 1],
	length = ["Length", 120.0, 560.0, 5.0],
	bend = ["Dogleg", -90.0, 90.0, 1.0],
	green_offset = ["Green offset", -110.0, 110.0, 1.0],
	fairway_width = ["Fairway width", 20.0, 50.0, 1.0],
	relief = ["Hills", 0.0, 14.0, 0.5],
	green_size = ["Green size", 9.0, 20.0, 0.5],
	water = ["Water", 0, 2, 1],
	bunkers = ["Bunkers", 0, 2, 1],
	trees = ["Trees", 0.0, 2.0, 0.1],
	pin = ["Pin position", 0, 99, 1],
	## A different random layout for the hole (used by Course, not a slider).
	layout = ["Layout", 0, 99999, 1],
}
const WATER_CHOICES := ["Random", "None", "Add a pond"]
const BUNKER_CHOICES := ["Random", "None", "Extra"]

var number: int
var par: int
var length: float
var tee: Vector3
var pin: Vector3
var green_centre: Vector2
var green_radius: float
## In-play area on the XZ plane (x, z).
var bounds: Rect2
## x, z, radius
var bunkers: Array[Vector3] = []
## x, z, radius, water level
var ponds: Array[Vector4] = []
## x, base y, z, canopy radius
var trees: Array[Vector4] = []
var tree_top := 0.0
## A real course's lakes, as shapes (empty for generated holes).
var water_shapes: Array[PackedVector2Array] = []

var _map: MappedLayout
var _bend: float
var _green_x: float
var _fairway_half: float
var _fairway_start: float
var _green_shape: Vector4
var _green_tilt: Vector2
var _tee_h: float
var _green_h: float
var _relief: float
var _overrides := {}
var _noise := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _tree_grid := {}


## overrides may hold "__map": a real hole's mapped shapes (see Course), in
## which case the hole is built from those instead of being generated.
func _init(hole_number: int, seed_value: int, overrides := {}) -> void:
	number = hole_number
	_overrides = overrides
	par = int(overrides.get("par", PARS[(hole_number - 1) % PARS.size()]))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	_noise.seed = seed_value
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.006
	_detail.seed = seed_value + 1
	_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail.frequency = 0.05
	_relief = rng.randf_range(3.0, 9.0)
	if overrides.has("__map"):
		_init_mapped(overrides["__map"], seed_value)
		return

	var bend_max: float
	match par:
		3:
			length = rng.randf_range(135.0, 195.0)
			bend_max = 10.0
		4:
			length = rng.randf_range(320.0, 410.0)
			bend_max = 50.0
		_:
			length = rng.randf_range(440.0, 510.0)
			bend_max = 75.0
	_bend = rng.randf_range(-bend_max, bend_max)
	_green_x = _bend * rng.randf_range(0.2, 1.3)
	_fairway_half = rng.randf_range(14.0, 20.0)
	var fairway_start_roll := rng.randf_range(50.0, 80.0)
	green_radius = rng.randf_range(12.0, 16.0)
	_relief = overrides.get("relief", _relief)
	length = overrides.get("length", length)
	_bend = overrides.get("bend", _bend)
	_green_x = overrides.get("green_offset", _green_x)
	_fairway_half = overrides.get("fairway_width", _fairway_half * 2.0) / 2.0
	green_radius = overrides.get("green_size", green_radius)
	_fairway_start = length - 40.0 if par == 3 else minf(fairway_start_roll, length * 0.3)

	green_centre = Vector2(_green_x, length)
	_green_shape = Vector4(rng.randf_range(0.05, 0.18), rng.randf() * TAU,
			rng.randf_range(0.0, 0.08), rng.randf() * TAU)
	var tilt_angle := rng.randf() * TAU
	_green_tilt = Vector2(cos(tilt_angle), sin(tilt_angle)) * rng.randf_range(0.008, 0.022)
	_tee_h = _natural(0.0, 0.0)
	_green_h = _natural(green_centre.x, green_centre.y)

	var min_x := minf(minf(0.0, _green_x), centre_x(length * 0.5))
	var max_x := maxf(maxf(0.0, _green_x), centre_x(length * 0.5))
	var side := _fairway_half + MARGIN
	bounds = Rect2(min_x - side, -25.0, max_x - min_x + side * 2.0, length + 60.0)

	_place_bunkers(_stream(seed_value, 1))
	_place_ponds(_stream(seed_value, 2))
	_place_pin(_stream(seed_value, 3 + int(overrides.get("pin", 0)) * 1009))
	_place_trees(_stream(seed_value, 4))
	tee = Vector3(0.0, height_at(0.0, 0.0), 0.0)


func _init_mapped(data: Dictionary, seed_value: int) -> void:
	_map = MappedLayout.new(data)
	_overrides = {}
	par = _map.par
	_relief = 1.2  # real courses: gently rolling, not hills
	green_centre = _map.centroid(_map.green)
	green_radius = 0.0
	for p in _map.green:
		green_radius = maxf(green_radius, p.distance_to(green_centre))
	length = green_centre.y
	_green_x = green_centre.x
	_fairway_half = 15.0
	_green_shape = Vector4.ZERO
	var rng := _stream(seed_value, 5)
	var tilt_angle := rng.randf() * TAU
	_green_tilt = Vector2(cos(tilt_angle), sin(tilt_angle)) * rng.randf_range(0.008, 0.018)
	_tee_h = _mapped_base(0.0, 0.0)
	_green_h = _mapped_base(green_centre.x, green_centre.y)
	bounds = _map.bounds
	water_shapes = _map.water
	_place_pin(_stream(seed_value, 3))
	_place_mapped_trees(_stream(seed_value, 4))
	tee = Vector3(0.0, height_at(0.0, 0.0), 0.0)


## True for a hole on a real, mapped course.
func is_mapped() -> bool:
	return _map != null


func overrides() -> Dictionary:
	return _overrides


## The current value of an editable feature, overridden or generated.
func feature(key: String) -> float:
	match key:
		"par":
			return par
		"length":
			return length
		"bend":
			return _bend
		"green_offset":
			return _green_x
		"fairway_width":
			return _fairway_half * 2.0
		"relief":
			return _relief
		"green_size":
			return green_radius
	return _overrides.get(key, 1.0 if key == "trees" else 0.0)


static func _stream(seed_value: int, salt: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_value, salt])
	return r


## X of the hole's centre line at distance z down the hole.
func centre_x(z: float) -> float:
	if _map:
		return _map.centre_x(z)
	var t := clampf(z / length, 0.0, 1.0)
	return 2.0 * t * (1.0 - t) * _bend + t * t * _green_x


func height_at(x: float, z: float) -> float:
	if _map:
		return _mapped_height(x, z)
	var p := Vector2(x, z)
	var h := _natural(x, z)
	h = lerpf(_tee_h, h, smoothstep(5.0, 16.0, p.length()))
	var to_green := p - green_centre
	# Greens: an overall tilt plus long, gentle swales (about 1-2% at most).
	var green_h := _green_h + _green_tilt.dot(to_green) + _noise.get_noise_2d(x * 4.0, z * 4.0) * 0.14
	var flat_r := green_radius * 1.3 + FRINGE_WIDTH
	h = lerpf(green_h, h, smoothstep(flat_r, flat_r + 12.0, to_green.length()))
	for b in bunkers:
		var d := p.distance_to(Vector2(b.x, b.y))
		if d < b.z + 1.5:
			h -= 0.5 * (1.0 - smoothstep(b.z * 0.5, b.z + 1.5, d))
	for pond in ponds:
		var d := p.distance_to(Vector2(pond.x, pond.y))
		if d < pond.z + POND_BANK:
			# Level the banks around the water, then dip to the bed.
			h = lerpf(pond.w + 0.8, h, smoothstep(pond.z + 2.0, pond.z + POND_BANK, d))
			h = lerpf(pond.w - 0.6, h, smoothstep(pond.z - 1.0, pond.z + 3.0, d))
	return h


func _mapped_base(x: float, z: float) -> float:
	return 0.9 + _natural(x, z)


## Real holes: flat-ish ground with greens shaped, bunkers dug in and lakes
## sunk below banks that always stand clear of the water.
func _mapped_height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var h := _mapped_base(x, z)
	h = lerpf(_tee_h, h, smoothstep(5.0, 16.0, p.length()))
	var g := _map.green_amount(x, z)
	if g > 0.0:
		var to_green := p - green_centre
		var green_h := _green_h + _green_tilt.dot(to_green) + _noise.get_noise_2d(x * 4.0, z * 4.0) * 0.1
		h = lerpf(h, green_h, smoothstep(0.1, 0.6, g))
	h -= 0.5 * _map.bunker_amount(x, z)
	h = maxf(h, MappedLayout.WATER_LEVEL + 0.35)
	return lerpf(h, MappedLayout.WATER_LEVEL - 0.6, smoothstep(0.25, 0.75, _map.water_amount(x, z)))


func normal_at(x: float, z: float) -> Vector3:
	const E := 0.3
	return Vector3(height_at(x - E, z) - height_at(x + E, z), 2.0 * E,
			height_at(x, z - E) - height_at(x, z + E)).normalized()


func surface_at(x: float, z: float) -> int:
	if not is_in_bounds(x, z):
		return Surface.OUT
	if _map:
		return _map.surface(x, z)
	var p := Vector2(x, z)
	for pond in ponds:
		if p.distance_to(Vector2(pond.x, pond.y)) < pond.z:
			return Surface.WATER
	for b in bunkers:
		if p.distance_to(Vector2(b.x, b.y)) < b.z:
			return Surface.BUNKER
	var to_green := p - green_centre
	var edge := _green_edge(to_green.angle())
	var dg := to_green.length()
	if dg < edge:
		return Surface.GREEN
	if dg < edge + FRINGE_WIDTH:
		return Surface.FRINGE
	if absf(x) < 5.0 and absf(z) < 4.0:
		return Surface.TEE
	if z > _fairway_start and z < length and lateral_distance(x, z) < fairway_half_width(z):
		return Surface.FAIRWAY
	return Surface.ROUGH


func is_in_bounds(x: float, z: float) -> bool:
	return bounds.has_point(Vector2(x, z))


func trees_near(x: float, z: float) -> Array[Vector4]:
	var found: Array[Vector4] = []
	var cx := floori(x / TREE_CELL)
	var cz := floori(z / TREE_CELL)
	for i in range(cx - 1, cx + 2):
		for j in range(cz - 1, cz + 2):
			var cell = _tree_grid.get(Vector2i(i, j))
			if cell != null:
				found.append_array(cell)
	return found


## Perpendicular distance from the centre line (approximate, cheap).
func lateral_distance(x: float, z: float) -> float:
	if _map:
		return _map.lateral_distance(x, z)
	var t := clampf(z / length, 0.0, 1.0)
	var slope := (2.0 * (1.0 - 2.0 * t) * _bend + 2.0 * t * _green_x) / length
	return absf(x - centre_x(z)) / sqrt(1.0 + slope * slope)


func fairway_half_width(z: float) -> float:
	return _fairway_half * (1.0 + 0.2 * sin(z * 0.025 + _green_shape.y))


## Tee-to-pin distance in metres.
func yardage() -> float:
	return Vector2(pin.x, pin.z).length()


func _natural(x: float, z: float) -> float:
	return _noise.get_noise_2d(x, z) * _relief + _detail.get_noise_2d(x, z) * 0.4


func _green_edge(angle: float) -> float:
	return green_radius * (1.0 + _green_shape.x * sin(2.0 * angle + _green_shape.y)
			+ _green_shape.z * sin(3.0 * angle + _green_shape.w))


func _place_bunkers(rng: RandomNumberGenerator) -> void:
	var choice := int(_overrides.get("bunkers", 0))
	if choice == 1:
		return
	var greenside := rng.randi_range(1, 3) + (2 if choice == 2 else 0)
	for i in greenside:
		# Keep greenside bunkers off the direct line of approach.
		var angle := PI * 1.5 + rng.randf_range(0.6, 2.6) * (1.0 if i % 2 == 0 else -1.0)
		var r := rng.randf_range(3.5, 6.0)
		var at := green_centre + Vector2.from_angle(angle) \
				* (_green_edge(angle) + FRINGE_WIDTH + r + 0.5)
		bunkers.append(Vector3(at.x, at.y, r))
	if par >= 4:
		var z := rng.randf_range(205.0, 245.0)
		if z < length - 70.0:
			var r := rng.randf_range(5.0, 9.0)
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			bunkers.append(Vector3(centre_x(z) + side * (fairway_half_width(z) + r * 0.4), z, r))
			if choice == 2:
				var z2 := z + 25.0
				bunkers.append(Vector3(centre_x(z2) - side * (fairway_half_width(z2) + r * 0.4), z2, r))


func _place_ponds(rng: RandomNumberGenerator) -> void:
	var choice := int(_overrides.get("water", 0))
	var roll := rng.randf()
	if choice == 1 or (choice == 0 and roll > 0.4):
		return
	var r := rng.randf_range(10.0, 16.0)
	var at: Vector2
	if par == 3:
		# In front of the green, with its banks clear of the putting surface.
		var z := length - (green_radius * 1.3 + FRINGE_WIDTH) - r - POND_BANK
		at = Vector2(centre_x(z), z)
	else:
		var z := rng.randf_range(130.0, length - 90.0)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		at = Vector2(centre_x(z) + side * (fairway_half_width(z) + r * 0.5), z)
	ponds.append(Vector4(at.x, at.y, r, _natural(at.x, at.y) - 1.0))


func _place_pin(rng: RandomNumberGenerator) -> void:
	for attempt in 40:
		var offset := Vector2.from_angle(rng.randf() * TAU) * green_radius * rng.randf_range(0.0, 0.55)
		var p := green_centre + offset
		if surface_at(p.x, p.y) == Surface.GREEN and _green_all_round(p, 2.5):
			pin = Vector3(p.x, height_at(p.x, p.y), p.y)
			return
	pin = Vector3(green_centre.x, height_at(green_centre.x, green_centre.y), green_centre.y)


## True when the green surrounds a point by at least margin metres.
func _green_all_round(p: Vector2, margin: float) -> bool:
	for k in 8:
		var q := p + Vector2.from_angle(k * TAU / 8.0) * margin
		if surface_at(q.x, q.y) != Surface.GREEN:
			return false
	return true


func _add_tree(x: float, z: float, r: float) -> void:
	var t := Vector4(x, height_at(x, z), z, r)
	trees.append(t)
	tree_top = maxf(tree_top, t.y + r * 3.0)
	var key := Vector2i(floori(x / TREE_CELL), floori(z / TREE_CELL))
	if not _tree_grid.has(key):
		var cell: Array[Vector4] = []
		_tree_grid[key] = cell
	_tree_grid[key].append(t)


## Real holes: fill the mapped woods with trees, and scatter more through the
## deep rough and beyond the boundary, clear of the hole itself.
func _place_mapped_trees(rng: RandomNumberGenerator) -> void:
	var outer := bounds.grow(60.0)
	for poly in _map.woods:
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in poly:
			lo = lo.min(p)
			hi = hi.max(p)
		lo = lo.max(outer.position)
		hi = hi.min(outer.end)
		var z := lo.y
		while z < hi.y:
			var x := lo.x
			while x < hi.x:
				var p := Vector2(x + rng.randf_range(-3.0, 3.0), z + rng.randf_range(-3.0, 3.0))
				if Geometry2D.is_point_in_polygon(p, poly) and _tree_spot_ok(p, 12.0):
					_add_tree(p.x, p.y, rng.randf_range(2.5, 4.5))
				x += 9.0
			z += 9.0
	var count := int(outer.get_area() / 900.0)
	for i in count:
		var p := Vector2(rng.randf_range(outer.position.x, outer.end.x), rng.randf_range(outer.position.y, outer.end.y))
		var s := surface_at(p.x, p.y)
		if is_in_bounds(p.x, p.y) and (s != Surface.ROUGH or rng.randf() > 0.5):
			continue
		if _tree_spot_ok(p, 30.0):
			_add_tree(p.x, p.y, rng.randf_range(2.5, 5.0))


func _tree_spot_ok(p: Vector2, clear_of_line: float) -> bool:
	if p.length() < 25.0 or p.distance_to(green_centre) < green_radius + 18.0:
		return false
	if _map.water_amount(p.x, p.y) > 0.05 or _map.bunker_amount(p.x, p.y) > 0.05:
		return false
	var s := surface_at(p.x, p.y)
	if s in [Surface.FAIRWAY, Surface.GREEN, Surface.FRINGE, Surface.TEE]:
		return false
	return lateral_distance(p.x, p.y) > clear_of_line


func _place_trees(rng: RandomNumberGenerator) -> void:
	var outer := bounds.grow(60.0)
	var density := float(_overrides.get("trees", 1.0))
	var count := int(outer.get_area() / 900.0 * density)
	var keep_in_play := clampf(0.45 * density, 0.0, 0.9)
	for i in count:
		var x := rng.randf_range(outer.position.x, outer.end.x)
		var z := rng.randf_range(outer.position.y, outer.end.y)
		var p := Vector2(x, z)
		var clear := lateral_distance(x, z) - fairway_half_width(z)
		# Sparse in play, denser beyond the boundary.
		if is_in_bounds(x, z) and (clear < 10.0 or rng.randf() > keep_in_play):
			continue
		if p.length() < 25.0 or p.distance_to(green_centre) < green_radius + 18.0:
			continue
		if surface_at(x, z) in [Surface.WATER, Surface.BUNKER]:
			continue
		var near_pond := false
		for pond in ponds:
			near_pond = near_pond or p.distance_to(Vector2(pond.x, pond.y)) < pond.z + 6.0
		if near_pond:
			continue
		var r := rng.randf_range(2.5, 5.0)
		var t := Vector4(x, height_at(x, z), z, r)
		trees.append(t)
		tree_top = maxf(tree_top, t.y + r * 3.0)
		var key := Vector2i(floori(x / TREE_CELL), floori(z / TREE_CELL))
		if not _tree_grid.has(key):
			var cell: Array[Vector4] = []
			_tree_grid[key] = cell
		_tree_grid[key].append(t)
