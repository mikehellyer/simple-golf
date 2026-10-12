class_name MappedLayout
extends RefCounted
## The ground of a real golf hole, built from mapped shapes (see
## tools/import_osm_course.py): which surface is where, and the smooth fields
## that shape the terrain around water, bunkers and the green.
##
## Shapes are rasterised once into a 0.5 m grid of surface types for the
## playing area, so lookups during ball flight stay fast however many
## shapes there are. Coarser 2 m fields, blurred for soft edges, cover the
## wider scenery too, so lakes carry on past the out-of-bounds line.

const STEP := 0.5
const FIELD_STEP := 2.0
const SIDE_MARGIN := 70.0
const SCENERY := 100.0
const WATER_LEVEL := 0.0

var par := 4
var line := PackedVector2Array()
var green := PackedVector2Array()
var water: Array[PackedVector2Array] = []
## Land cut out of the water (e.g. an island green).
var islands: Array[PackedVector2Array] = []
var woods: Array[PackedVector2Array] = []
var bounds := Rect2()

var _origin := Vector2.ZERO
var _w := 0
var _h := 0
var _cells := PackedByteArray()
var _f_origin := Vector2.ZERO
var _fw := 0
var _fh := 0
var _water_field := PackedFloat32Array()
var _bunker_field := PackedFloat32Array()
var _green_field := PackedFloat32Array()


static func _points(flat: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, flat.size() - 1, 2):
		out.append(Vector2(float(flat[i]), float(flat[i + 1])))
	return out


func _init(data: Dictionary) -> void:
	par = int(data.get("par", 4))
	line = _points(data.get("line", []))
	green = _points(data.get("green", []))
	var greens: Array[PackedVector2Array] = [green]
	for g in data.get("greens", []):
		greens.append(_points(g))
	for w in data.get("water", []):
		water.append(_points(w))
	for w in data.get("islands", []):
		islands.append(_points(w))
	for w in data.get("woods", []):
		woods.append(_points(w))

	# The playing area: around the hole's line, behind the tee and past the green.
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in line + green:
		lo = lo.min(p)
		hi = hi.max(p)
	bounds = Rect2(lo.x - SIDE_MARGIN, minf(lo.y, 0.0) - 30.0,
			hi.x - lo.x + SIDE_MARGIN * 2.0, hi.y - minf(lo.y, 0.0) + 65.0)

	_origin = bounds.position
	_w = int(ceil(bounds.size.x / STEP))
	_h = int(ceil(bounds.size.y / STEP))
	_cells.resize(_w * _h)
	_cells.fill(Surface.ROUGH)
	for f in data.get("fairways", []):
		_fill(_points(f), Surface.FAIRWAY)
	for t in data.get("tees", []):
		_fill(_points(t), Surface.TEE)
	# The tee the hole is played from, in case it isn't mapped as a shape.
	_fill(PackedVector2Array([Vector2(-4, -4), Vector2(4, -4), Vector2(4, 4), Vector2(-4, 4)]), Surface.TEE)
	for g in greens:
		for ring in Geometry2D.offset_polygon(g, 2.5):
			_fill(ring, Surface.FRINGE)
	for g in greens:
		_fill(g, Surface.GREEN)
	var bunkers: Array[PackedVector2Array] = []
	for b in data.get("bunkers", []):
		bunkers.append(_points(b))
		_fill(bunkers[-1], Surface.BUNKER)
	# Water over everything, except where an island is cut out of it.
	var wet := PackedByteArray()
	wet.resize(_w * _h)
	var spans: Array[Vector3i] = []
	for w in water:
		for sp in _scan(w, _origin, STEP, _w, _h):
			spans.append(sp)
			for i in range(sp.x, sp.y + 1):
				wet[sp.z * _w + i] = 1
	for isle in islands:
		for sp in _scan(isle, _origin, STEP, _w, _h):
			for i in range(sp.x, sp.y + 1):
				wet[sp.z * _w + i] = 0
	for sp in spans:
		for i in range(sp.x, sp.y + 1):
			if wet[sp.z * _w + i] == 1:
				_cells[sp.z * _w + i] = Surface.WATER

	# Soft-edged fields over the playing area and its scenery.
	var area := bounds.grow(SCENERY)
	_f_origin = area.position
	_fw = int(ceil(area.size.x / FIELD_STEP)) + 1
	_fh = int(ceil(area.size.y / FIELD_STEP)) + 1
	_water_field = _field(water, islands)
	_bunker_field = _field(bunkers)
	var own: Array[PackedVector2Array] = [green]
	_green_field = _field(own)


## Surface type at a point inside the playing area.
func surface(x: float, z: float) -> int:
	var i := int((x - _origin.x) / STEP)
	var j := int((z - _origin.y) / STEP)
	if i < 0 or j < 0 or i >= _w or j >= _h:
		return Surface.OUT
	return _cells[j * _w + i]


## 0 (none) to 1 (fully inside), smoothed over a few metres.
func water_amount(x: float, z: float) -> float:
	return _sample(_water_field, x, z)


func bunker_amount(x: float, z: float) -> float:
	return _sample(_bunker_field, x, z)


func green_amount(x: float, z: float) -> float:
	return _sample(_green_field, x, z)


func centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / maxi(poly.size(), 1)


## X of the hole's line at distance z down the hole (z beyond the ends uses
## the end points).
func centre_x(z: float) -> float:
	if z <= line[0].y:
		return line[0].x
	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		if z <= b.y and b.y > a.y:
			return lerpf(a.x, b.x, (z - a.y) / (b.y - a.y))
	return line[-1].x


func lateral_distance(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := INF
	for i in line.size() - 1:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, line[i], line[i + 1])))
	return best


# --- Rasterising -----------------------------------------------------------

## Scanline fill of a polygon into the surface grid.
func _fill(poly: PackedVector2Array, value: int) -> void:
	for s in _scan(poly, _origin, STEP, _w, _h):
		for i in range(s.x, s.y + 1):
			_cells[s.z * _w + i] = value


func _field(polys: Array[PackedVector2Array], cut_out: Array[PackedVector2Array] = []) -> PackedFloat32Array:
	var mask := PackedFloat32Array()
	mask.resize(_fw * _fh)
	for poly in polys:
		for s in _scan(poly, _f_origin, FIELD_STEP, _fw, _fh):
			for i in range(s.x, s.y + 1):
				mask[s.z * _fw + i] = 1.0
	for poly in cut_out:
		for s in _scan(poly, _f_origin, FIELD_STEP, _fw, _fh):
			for i in range(s.x, s.y + 1):
				mask[s.z * _fw + i] = 0.0
	return _blur(_blur(mask))


## Grid cells inside a polygon, as spans (first column, last column, row).
static func _scan(poly: PackedVector2Array, origin: Vector2, step: float, w: int, h: int) -> Array[Vector3i]:
	var spans: Array[Vector3i] = []
	if poly.size() < 3:
		return spans
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in poly:
		lo = lo.min(p)
		hi = hi.max(p)
	var j0 := maxi(int(floor((lo.y - origin.y) / step)), 0)
	var j1 := mini(int(ceil((hi.y - origin.y) / step)), h - 1)
	for j in range(j0, j1 + 1):
		var y := origin.y + (j + 0.5) * step
		var xs := PackedFloat32Array()
		var n := poly.size()
		for k in n:
			var a := poly[k]
			var b := poly[(k + 1) % n]
			if (a.y > y) != (b.y > y):
				xs.append(a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y))
		xs.sort()
		for k in range(0, xs.size() - 1, 2):
			var i0 := maxi(int(ceil((xs[k] - origin.x) / step - 0.5)), 0)
			var i1 := mini(int(floor((xs[k + 1] - origin.x) / step - 0.5)), w - 1)
			if i1 >= i0:
				spans.append(Vector3i(i0, i1, j))
	return spans


func _blur(src: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(src.size())
	for j in _fh:
		for i in _fw:
			var sum := 0.0
			var count := 0
			for dj in range(-1, 2):
				var jj := j + dj
				if jj < 0 or jj >= _fh:
					continue
				for di in range(-1, 2):
					var ii := i + di
					if ii >= 0 and ii < _fw:
						sum += src[jj * _fw + ii]
						count += 1
			out[j * _fw + i] = sum / count
	return out


func _sample(field: PackedFloat32Array, x: float, z: float) -> float:
	var fx := (x - _f_origin.x) / FIELD_STEP
	var fz := (z - _f_origin.y) / FIELD_STEP
	if fx < 0.0 or fz < 0.0 or fx >= _fw - 1 or fz >= _fh - 1:
		return 0.0
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var k := j * _fw + i
	return lerpf(lerpf(field[k], field[k + 1], tx), lerpf(field[k + _fw], field[k + _fw + 1], tx), tz)
