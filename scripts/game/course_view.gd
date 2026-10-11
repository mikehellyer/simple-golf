class_name CourseView
extends Node3D
## Builds the visible 3D scene for a Hole: terrain, water, trees and the flag.
##
## The terrain is a coarse grid with a hole cut out around the green, where a
## finer "green complex" mesh with a sharper texture takes over. The fine
## mesh's border follows the coarse triangles exactly so the seam has no cracks.

const SCENERY := 90.0
const GRID_STEP := 2.0
const TEXEL := 1.0
const PATCH_STEP := 0.5
const PATCH_TEXEL := 0.25

const COLOURS := {
	Surface.TEE: Color(0.36, 0.62, 0.24),
	Surface.FAIRWAY: Color(0.3, 0.55, 0.16),
	Surface.ROUGH: Color(0.15, 0.32, 0.09),
	Surface.FRINGE: Color(0.3, 0.6, 0.22),
	Surface.GREEN: Color(0.45, 0.78, 0.33),
	Surface.BUNKER: Color(0.87, 0.8, 0.6),
	Surface.WATER: Color(0.18, 0.26, 0.22),
	Surface.OUT: Color(0.12, 0.25, 0.08),
}

var hole: Hole
var green_grid: GreenGrid
var _area: Rect2
## Coarse grid cells covered by the green complex.
var _patch_cells: Rect2i


func build(h: Hole) -> void:
	hole = h
	_area = hole.bounds.grow(SCENERY)
	_patch_cells = _green_patch_cells()
	_build_terrain()
	_build_green_complex()
	_build_water()
	_build_trees()
	_build_flag()
	_build_tee_markers()
	green_grid = GreenGrid.new()
	green_grid.build(hole)
	green_grid.visible = false
	add_child(green_grid)


func _green_patch_cells() -> Rect2i:
	var half := hole.green_radius * 1.3 + Hole.FRINGE_WIDTH + 13.0
	var lo := (hole.green_centre - Vector2(half, half) - _area.position) / GRID_STEP
	var hi := (hole.green_centre + Vector2(half, half) - _area.position) / GRID_STEP
	var i0 := floori(lo.x)
	var j0 := floori(lo.y)
	return Rect2i(i0, j0, ceili(hi.x) - i0, ceili(hi.y) - j0)


func _build_terrain() -> void:
	var nx := int(ceil(_area.size.x / GRID_STEP)) + 1
	var nz := int(ceil(_area.size.y / GRID_STEP)) + 1
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	for j in nz:
		var z := _area.position.y + j * GRID_STEP
		for i in nx:
			heights[j * nx + i] = hole.height_at(_area.position.x + i * GRID_STEP, z)
	var mesh := _grid_mesh(_area.position, GRID_STEP, nx, nz, heights, _patch_cells)
	var width := (nx - 1) * GRID_STEP
	var depth := (nz - 1) * GRID_STEP
	var tex := _bake_texture(_area.position, width, depth, TEXEL)
	add_child(_terrain_instance("Terrain", mesh, tex))


func _build_green_complex() -> void:
	var origin := _area.position + Vector2(_patch_cells.position) * GRID_STEP
	var size := Vector2(_patch_cells.size) * GRID_STEP
	var per_cell := int(round(GRID_STEP / PATCH_STEP))
	var nx := _patch_cells.size.x * per_cell + 1
	var nz := _patch_cells.size.y * per_cell + 1
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	for j in nz:
		for i in nx:
			var x := origin.x + i * PATCH_STEP
			var z := origin.y + j * PATCH_STEP
			var h: float
			if i == 0 or i == nx - 1:
				h = _coarse_edge_height(x, z, j % per_cell, per_cell, false)
			elif j == 0 or j == nz - 1:
				h = _coarse_edge_height(x, z, i % per_cell, per_cell, true)
			else:
				h = hole.height_at(x, z)
			heights[j * nx + i] = h
	var mesh := _grid_mesh(origin, PATCH_STEP, nx, nz, heights, Rect2i())
	var tex := _bake_texture(origin, size.x, size.y, PATCH_TEXEL)
	add_child(_terrain_instance("GreenComplex", mesh, tex))


## Height along an edge of the coarse grid: a straight line between the two
## coarse vertices, matching the coarse mesh so the seam is watertight.
func _coarse_edge_height(x: float, z: float, k: int, per_cell: int, along_x: bool) -> float:
	if k == 0:
		return hole.height_at(x, z)
	var t := float(k) / per_cell
	if along_x:
		var x0 := x - t * GRID_STEP
		return lerpf(hole.height_at(x0, z), hole.height_at(x0 + GRID_STEP, z), t)
	var z0 := z - t * GRID_STEP
	return lerpf(hole.height_at(x, z0), hole.height_at(x, z0 + GRID_STEP), t)


func _grid_mesh(origin: Vector2, step: float, nx: int, nz: int,
		heights: PackedFloat32Array, skip: Rect2i) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(nx * nz)
	normals.resize(nx * nz)
	uvs.resize(nx * nz)
	for j in nz:
		for i in nx:
			var k := j * nx + i
			verts[k] = Vector3(origin.x + i * step, heights[k], origin.y + j * step)
			uvs[k] = Vector2(float(i) / (nx - 1), float(j) / (nz - 1))
			var hl := heights[k - 1] if i > 0 else heights[k]
			var hr := heights[k + 1] if i < nx - 1 else heights[k]
			var hd := heights[k - nx] if j > 0 else heights[k]
			var hu := heights[k + nx] if j < nz - 1 else heights[k]
			var span_x := step * (2.0 if i > 0 and i < nx - 1 else 1.0)
			var span_z := step * (2.0 if j > 0 and j < nz - 1 else 1.0)
			normals[k] = Vector3((hl - hr) / span_x, 1.0, (hd - hu) / span_z).normalized()

	var indices := PackedInt32Array()
	for j in nz - 1:
		for i in nx - 1:
			if skip.has_point(Vector2i(i, j)):
				continue
			var a := j * nx + i
			var c := a + nx
			indices.append_array([a, a + 1, c, a + 1, c + 1, c])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _terrain_instance(node_name: String, mesh: ArrayMesh, tex: ImageTexture) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.roughness = 0.95
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	return mi


func _bake_texture(origin: Vector2, width: float, depth: float, texel: float) -> ImageTexture:
	var w := int(width / texel) + 1
	var h := int(depth / texel) + 1
	var data := PackedByteArray()
	data.resize(w * h * 3)
	for j in h:
		var z := origin.y + j * depth / (h - 1)
		for i in w:
			var x := origin.x + i * width / (w - 1)
			var surf := hole.surface_at(x, z)
			var col: Color = COLOURS[surf]
			match surf:
				Surface.FAIRWAY:
					if posmod(floori(z / 9.0), 2) == 0:
						col = col.darkened(0.08)
				Surface.GREEN:
					if posmod(floori(z / 2.0), 2) == 0:
						col = col.darkened(0.06)
				Surface.ROUGH:
					# Lighter first cut just off the fairway.
					var off := hole.lateral_distance(x, z) - hole.fairway_half_width(z)
					if off < 3.0 and z > 40.0 and z < hole.length:
						col = col.lerp(COLOURS[Surface.FAIRWAY], 0.45)
			# Cheap hash speckle so large areas don't look flat.
			var hx := floori(x / texel * 0.5)
			var hz := floori(z / texel * 0.5)
			var speckle := float(((hx * 73856093) ^ (hz * 19349663)) & 255) / 255.0 * 0.06 - 0.03
			var k := (j * w + i) * 3
			data[k] = clampi(int((col.r + speckle) * 255.0), 0, 255)
			data[k + 1] = clampi(int((col.g + speckle) * 255.0), 0, 255)
			data[k + 2] = clampi(int((col.b + speckle) * 255.0), 0, 255)
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGB8, data)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _build_water() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.36, 0.55, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.08
	mat.metallic = 0.3
	for pond in hole.ponds:
		var disc := CylinderMesh.new()
		disc.top_radius = pond.z + 0.8
		disc.bottom_radius = pond.z + 0.8
		disc.height = 0.02
		disc.radial_segments = 48
		var mi := MeshInstance3D.new()
		mi.mesh = disc
		mi.material_override = mat
		mi.position = Vector3(pond.x, pond.w, pond.y)
		add_child(mi)


## Two kinds of tree, picked by a hash of position: broadleaf (a cluster of
## three blobs) and conifer (stacked cones). Physics treats both as a trunk
## plus a sphere, which these shapes fill closely.
func _build_trees() -> void:
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.6
	trunk_mesh.bottom_radius = 1.0
	trunk_mesh.height = 1.0
	trunk_mesh.radial_segments = 7
	trunk_mesh.material = _tree_material(false)

	var blob := SphereMesh.new()
	blob.radius = 1.0
	blob.height = 2.0
	blob.radial_segments = 10
	blob.rings = 6
	blob.material = _tree_material(true)

	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 9
	cone.material = _tree_material(true)

	var broadleaf: Array[Vector4] = []
	var conifers: Array[Vector4] = []
	for t in hole.trees:
		if _hash(t) < 0.3:
			conifers.append(t)
		else:
			broadleaf.append(t)

	var trunks := _multimesh(trunk_mesh, hole.trees.size(), false)
	for i in hole.trees.size():
		var t := hole.trees[i]
		var r := t.w * BallPhysics.TRUNK_RADIUS
		trunks.set_instance_transform(i, Transform3D(
				Basis.from_scale(Vector3(r, t.w * 2.0, r)), Vector3(t.x, t.y + t.w, t.z)))

	var blobs := _multimesh(blob, broadleaf.size() * 3, true)
	for i in broadleaf.size():
		var t := broadleaf[i]
		var r := t.w
		var spin := _hash(t) * TAU
		var tint := _tint(t)
		for k in 3:
			var a := spin + k * TAU / 3.0
			var offset := Vector3(cos(a) * r * 0.35, (k - 1) * r * 0.18, sin(a) * r * 0.35)
			var s := r * (0.72 - k * 0.04)
			blobs.set_instance_transform(i * 3 + k, Transform3D(
					Basis.from_scale(Vector3(s, s * 0.95, s)), Vector3(t.x, t.y + r * 2.0, t.z) + offset))
			blobs.set_instance_color(i * 3 + k, tint.lightened(k * 0.06))

	var cones := _multimesh(cone, conifers.size() * 2, true)
	for i in conifers.size():
		var t := conifers[i]
		var r := t.w
		var tint := _tint(t).lerp(Color(0.1, 0.26, 0.1), 0.5)
		cones.set_instance_transform(i * 2, Transform3D(
				Basis.from_scale(Vector3(r * 0.95, r * 1.6, r * 0.95)), Vector3(t.x, t.y + r * 1.75, t.z)))
		cones.set_instance_transform(i * 2 + 1, Transform3D(
				Basis.from_scale(Vector3(r * 0.7, r * 1.4, r * 0.7)), Vector3(t.x, t.y + r * 2.6, t.z)))
		cones.set_instance_color(i * 2, tint)
		cones.set_instance_color(i * 2 + 1, tint.lightened(0.05))

	for mm in [trunks, blobs, cones]:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)


func _tree_material(foliage: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.roughness = 1.0
	if foliage:
		mat.vertex_color_use_as_albedo = true
	else:
		mat.albedo_color = Color(0.33, 0.23, 0.14)
	return mat


func _multimesh(mesh: Mesh, count: int, colours: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colours
	mm.mesh = mesh
	mm.instance_count = count
	return mm


static func _hash(t: Vector4) -> float:
	return fposmod(sin(t.x * 12.9898 + t.z * 78.233) * 43758.5453, 1.0)


static func _tint(t: Vector4) -> Color:
	var shade := 0.75 + _hash(t + Vector4(1.0, 0.0, 1.0, 0.0)) * 0.5
	return Color(0.17 * shade, 0.38 * shade, 0.14 * shade)


func _build_flag() -> void:
	var pin := hole.pin
	var cup := CylinderMesh.new()
	cup.top_radius = 0.07
	cup.bottom_radius = 0.07
	cup.height = 0.01
	var cup_mat := StandardMaterial3D.new()
	cup_mat.albedo_color = Color(0.05, 0.05, 0.05)
	cup.material = cup_mat
	var cup_mi := MeshInstance3D.new()
	cup_mi.mesh = cup
	cup_mi.position = pin + Vector3(0.0, 0.01, 0.0)
	add_child(cup_mi)

	var pole := CylinderMesh.new()
	pole.top_radius = 0.015
	pole.bottom_radius = 0.015
	pole.height = 2.3
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.95, 0.95, 0.9)
	pole.material = pole_mat
	var pole_mi := MeshInstance3D.new()
	pole_mi.mesh = pole
	pole_mi.position = pin + Vector3(0.0, 1.15, 0.0)
	add_child(pole_mi)

	var flag := BoxMesh.new()
	flag.size = Vector3(0.6, 0.4, 0.01)
	var flag_mat := StandardMaterial3D.new()
	flag_mat.albedo_color = Color(0.9, 0.15, 0.15)
	flag.material = flag_mat
	var flag_mi := MeshInstance3D.new()
	flag_mi.mesh = flag
	flag_mi.position = pin + Vector3(0.3, 2.1, 0.0)
	add_child(flag_mi)


func _build_tee_markers() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.85, 0.2)
	mesh.material = mat
	for x in [-3.5, 3.5]:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = Vector3(x, hole.height_at(x, 1.0) + 0.1, 1.0)
		add_child(mi)
