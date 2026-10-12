class_name GreenGrid
extends MultiMeshInstance3D
## Animated slope read-out over the green: a grid of dots that drift downhill,
## faster and redder where the green is steeper.

const SPACING := 1.0
const LIFT := 0.03
## Dot travel speed per 1% of slope, in metres per second.
const SPEED_PER_PERCENT := 0.12

var _bases := PackedVector3Array()
## Downhill direction (XZ, unit) and gradient (rise per metre, positive) per dot.
var _downhill := PackedVector2Array()
var _gradient := PackedFloat32Array()
var _phase := PackedFloat32Array()
var _time := 0.0


func build(hole: Hole) -> void:
	var r := hole.green_radius * 1.3 + Hole.FRINGE_WIDTH
	var c := hole.green_centre
	var x := c.x - r
	while x <= c.x + r:
		var z := c.y - r
		while z <= c.y + r:
			var surf := hole.surface_at(x, z)
			if surf == Surface.GREEN or surf == Surface.FRINGE:
				var n := hole.normal_at(x, z)
				var down := Vector2(n.x, n.z) / n.y
				_bases.append(Vector3(x, hole.height_at(x, z) + LIFT, z))
				_gradient.append(down.length())
				_downhill.append(down.normalized() if down.length() > 0.0001 else Vector2.ZERO)
				_phase.append(fposmod(x * 0.37 + z * 0.73, 1.0))
			z += SPACING
		x += SPACING

	var dot := CylinderMesh.new()
	dot.top_radius = 0.06
	dot.bottom_radius = 0.06
	dot.height = 0.004
	dot.radial_segments = 8
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dot.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = dot
	mm.instance_count = _bases.size()
	multimesh = mm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_build_lines(hole, r)
	_update()


## The original's gridlines: a 1 m grid draped over the green, so its rolls
## and tilts show at a glance.
func _build_lines(hole: Hole, r: float) -> void:
	var c := hole.green_centre
	var on_green := func(x: float, z: float) -> bool:
		var s := hole.surface_at(x, z)
		return s == Surface.GREEN or s == Surface.FRINGE
	var mesh := ImmediateMesh.new()
	const STEP := 0.25
	for axis in 2:
		var u := -r
		while u <= r:
			var open := false
			var v := -r
			while v <= r:
				var x: float = c.x + (u if axis == 0 else v)
				var z: float = c.y + (v if axis == 0 else u)
				if on_green.call(x, z):
					if not open:
						mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
						open = true
					mesh.surface_add_vertex(Vector3(x, hole.height_at(x, z) + 0.02, z))
				elif open:
					mesh.surface_end()
					open = false
				v += STEP
			if open:
				mesh.surface_end()
			u += SPACING
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var lines := MeshInstance3D.new()
	lines.mesh = mesh
	lines.material_override = mat
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lines)


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	_update()


func _update() -> void:
	for i in _bases.size():
		var pct := _gradient[i] * 100.0
		var travel := fposmod(_phase[i] + _time * SPEED_PER_PERCENT * pct / SPACING, 1.0)
		var offset := _downhill[i] * travel * SPACING
		var p := _bases[i] + Vector3(offset.x, -_gradient[i] * travel * SPACING, offset.y)
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, p))
		var col := slope_colour(pct)
		col.a = sin(travel * PI) * 0.9
		multimesh.set_instance_color(i, col)


## Flat greens read white-blue, then yellow, orange and red as they steepen.
static func slope_colour(percent: float) -> Color:
	if percent < 1.0:
		return Color(0.75, 0.9, 1.0).lerp(Color(1.0, 1.0, 0.4), percent)
	if percent < 2.5:
		return Color(1.0, 1.0, 0.4).lerp(Color(1.0, 0.55, 0.1), (percent - 1.0) / 1.5)
	return Color(1.0, 0.55, 0.1).lerp(Color(1.0, 0.15, 0.1), clampf((percent - 2.5) / 2.0, 0.0, 1.0))
