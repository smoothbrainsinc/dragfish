class_name Scenario
extends RefCounted
## CPU-side scenario builder: bathymetry, solver bottom texture, visual terrain
## mesh and prop placements. Pure static math, deterministic, no scene access.
##
## Grid convention: domain 30.4 x 30.4 m, 608x608 cells, dx = 0.05 m.
## Corner (i,j) sits at world (i*0.05, j*0.05); row-major index = j*609 + i.
## Cell (i,j) center sits at ((i+0.5)*0.05, (j+0.5)*0.05); bottom_image texel (i,j).

const GRID := 608
const CORNERS := 609
const DX := 0.05
const DOMAIN := 30.4

enum { BEACH, WALL }

# Boulder stamps for the beach (bumps ADDED to the local bed; the ^1.5 falloff
# is C1 at the rim, so adding on the local base keeps the bed seam-free on the
# slope). peak = height above local sand at the stamp center.
const BEACH_STAMPS: Array[Dictionary] = [
	{ "cx": 19.5, "cz": 11.0, "rx": 1.6, "rz": 1.4, "peak": 0.9 },   # hero
	{ "cx": 17.5, "cz": 20.0, "rx": 0.8, "rz": 0.65, "peak": 0.5 },  # cluster
	{ "cx": 18.5, "cz": 21.5, "rx": 0.6, "rz": 0.5, "peak": 0.4 },
	{ "cx": 21.5, "cz": 22.5, "rx": 0.75, "rz": 0.6, "peak": 0.35 },
]

# Measured GLTF bounds (Y above mesh origin), used to sink props correctly.
const HERO_TOP := 1.0772       # coast_rocks_05 max.y (size 4.04 x 1.33 x 3.75)
const NAMAQ_TOP := 0.823       # namaqualand_boulder_02 max.y (2.53 x 0.88 x 1.23)
const SANDROCKS_TOP := 0.431   # sand_rocks_small_01 max.y (4.63 x 0.54 x 3.88)


static func build(kind: int) -> Dictionary:
	var corners := _build_corners(kind)
	var result := {
		"corner_heights": corners,
		"bottom_image": _build_bottom_image(corners),
		"terrain_mesh": _build_terrain_mesh(corners),
		"props": _build_props(kind),
	}
	if kind == WALL:
		result["wall_aabb"] = AABB(Vector3(22.0, -0.6, 0.0), Vector3(8.4, 3.2, 30.4))
	return result


# --- bed elevation -----------------------------------------------------------

static func _beach_base(x: float, z: float) -> float:
	## Beach profile WITHOUT boulder stamps (used for prop placement too).
	var b := -1.2 if x <= 6.0 else -1.2 + (x - 6.0) / 12.0
	return b + 0.05 * sin(z * 0.35 + 1.7) * smoothstep(8.0, 22.0, x)


static func _wall_profile(x: float) -> float:
	if x >= 22.1:
		return 2.5
	if x >= 22.0:
		return lerpf(-0.5, 2.5, (x - 22.0) / 0.1)  # jump over exactly 2 cells
	if x <= 12.0:
		return -1.5
	return -1.5 + (x - 12.0) / 10.0


static func bed_height(kind: int, x: float, z: float) -> float:
	## Analytic bed elevation at an arbitrary world point.
	if kind == WALL:
		return _wall_profile(x)
	var b := _beach_base(x, z)
	for s: Dictionary in BEACH_STAMPS:
		var dx0: float = (x - s.cx) / s.rx
		var dz0: float = (z - s.cz) / s.rz
		var q := 1.0 - dx0 * dx0 - dz0 * dz0
		if q > 0.0:
			b += s.peak * pow(q, 1.5)
	return b


static func _build_corners(kind: int) -> PackedFloat32Array:
	var h := PackedFloat32Array()
	h.resize(CORNERS * CORNERS)
	if kind == WALL:
		# Profile depends on x only: compute one row, replicate.
		var row := PackedFloat32Array()
		row.resize(CORNERS)
		for i in CORNERS:
			row[i] = _wall_profile(float(i) * DX)
		for j in CORNERS:
			var base := j * CORNERS
			for i in CORNERS:
				h[base + i] = row[i]
		return h
	# BEACH: hoist stamp params out of the hot loop.
	var n_stamps := BEACH_STAMPS.size()
	var cxs := PackedFloat32Array()
	var czs := PackedFloat32Array()
	var rxs := PackedFloat32Array()
	var rzs := PackedFloat32Array()
	var pks := PackedFloat32Array()
	for s: Dictionary in BEACH_STAMPS:
		cxs.append(s.cx); czs.append(s.cz); rxs.append(s.rx); rzs.append(s.rz); pks.append(s.peak)
	for j in CORNERS:
		var z := float(j) * DX
		var sz := 0.05 * sin(z * 0.35 + 1.7)
		var base := j * CORNERS
		for i in CORNERS:
			var x := float(i) * DX
			var b := -1.2 if x <= 6.0 else -1.2 + (x - 6.0) / 12.0
			b += sz * smoothstep(8.0, 22.0, x)
			for s in n_stamps:
				var dx0 := (x - cxs[s]) / rxs[s]
				var dz0 := (z - czs[s]) / rzs[s]
				var q := 1.0 - dx0 * dx0 - dz0 * dz0
				if q > 0.0:
					b += pks[s] * pow(q, 1.5)
			h[base + i] = b
	return h


# --- solver bottom texture ---------------------------------------------------

static func _build_bottom_image(corners: PackedFloat32Array) -> Image:
	## 608x608 RGBAF: R = B at cell center, G = B at east face, B = B at north
	## face, A = max of B-center over the 3x3 cell neighborhood.
	var centers := PackedFloat32Array()
	centers.resize(GRID * GRID)
	for j in GRID:
		var c_row := j * CORNERS
		var o_row := j * GRID
		for i in GRID:
			var k := c_row + i
			centers[o_row + i] = (corners[k] + corners[k + 1] + corners[k + CORNERS] + corners[k + CORNERS + 1]) * 0.25
	# Separable 3x3 max (clamped at borders).
	var hmax := PackedFloat32Array()
	hmax.resize(GRID * GRID)
	for j in GRID:
		var row := j * GRID
		for i in GRID:
			var m := centers[row + i]
			if i > 0:
				m = maxf(m, centers[row + i - 1])
			if i < GRID - 1:
				m = maxf(m, centers[row + i + 1])
			hmax[row + i] = m
	var data := PackedFloat32Array()
	data.resize(GRID * GRID * 4)
	for j in GRID:
		var c_row := j * CORNERS
		var o_row := j * GRID
		for i in GRID:
			var k := c_row + i
			var a := hmax[o_row + i]
			if j > 0:
				a = maxf(a, hmax[o_row - GRID + i])
			if j < GRID - 1:
				a = maxf(a, hmax[o_row + GRID + i])
			var p := (o_row + i) * 4
			data[p] = centers[o_row + i]
			data[p + 1] = (corners[k + 1] + corners[k + CORNERS + 1]) * 0.5      # east face
			data[p + 2] = (corners[k + CORNERS] + corners[k + CORNERS + 1]) * 0.5  # north face
			data[p + 3] = a
	return Image.create_from_data(GRID, GRID, false, Image.FORMAT_RGBAF, data.to_byte_array())


# --- visual terrain mesh -----------------------------------------------------

static func _build_terrain_mesh(corners: PackedFloat32Array) -> ArrayMesh:
	## 609x609 vertex grid, indexed triangles, analytic smooth normals from the
	## heightfield, UV1 = world_xz / 30.4, mikktspace tangents.
	var n_verts := CORNERS * CORNERS
	var verts := PackedVector3Array()
	verts.resize(n_verts)
	var normals := PackedVector3Array()
	normals.resize(n_verts)
	var uvs := PackedVector2Array()
	uvs.resize(n_verts)
	var inv_dom := 1.0 / DOMAIN
	for j in CORNERS:
		var z := float(j) * DX
		var row := j * CORNERS
		var jl := maxi(j - 1, 0)
		var jr := mini(j + 1, CORNERS - 1)
		var inv_dz := 1.0 / (float(jr - jl) * DX)
		for i in CORNERS:
			var x := float(i) * DX
			var k := row + i
			var il := maxi(i - 1, 0)
			var ir := mini(i + 1, CORNERS - 1)
			var dbdx := (corners[row + ir] - corners[row + il]) / (float(ir - il) * DX)
			var dbdz := (corners[jr * CORNERS + i] - corners[jl * CORNERS + i]) * inv_dz
			verts[k] = Vector3(x, corners[k], z)
			normals[k] = Vector3(-dbdx, 1.0, -dbdz).normalized()
			uvs[k] = Vector2(x * inv_dom, z * inv_dom)
	var indices := PackedInt32Array()
	indices.resize(GRID * GRID * 6)
	var p := 0
	for j in GRID:
		var a := j * CORNERS
		for i in GRID:
			var v00 := a + i            # (i, j)
			var v10 := v00 + 1          # (i+1, j)
			var v01 := v00 + CORNERS    # (i, j+1)
			var v11 := v01 + 1          # (i+1, j+1)
			# Godot front faces are clockwise; these wind front = +Y.
			indices[p] = v00; indices[p + 1] = v10; indices[p + 2] = v01
			indices[p + 3] = v10; indices[p + 4] = v11; indices[p + 5] = v01
			p += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var tmp := ArrayMesh.new()
	tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# mikktspace tangents (normal-mapped material needs them, and this matches
	# the importer's convention exactly).
	var st := SurfaceTool.new()
	st.create_from(tmp, 0)
	st.generate_tangents()
	return st.commit()


# --- props -------------------------------------------------------------------

static func _prop(path: String, pos: Vector3, uniform_scale: float, rot_y: float) -> Dictionary:
	var basis := Basis.from_euler(Vector3(0.0, rot_y, 0.0)).scaled(Vector3(uniform_scale, uniform_scale, uniform_scale))
	return { "path": path, "transform": Transform3D(basis, pos) }


static func _build_props(kind: int) -> Array[Dictionary]:
	var props: Array[Dictionary] = []
	if kind != BEACH:
		return props
	# Visual shells over the bathymetry stamps: top of mesh = local sand + peak
	# (matches stamp within a few cm), footprint scaled to the stamp radii.
	# Hero: coast_rocks_05 at stamp 0 (peak 0.9). scale 0.82 -> footprint
	# ~3.3 x 3.1 m vs stamp extents 3.2 x 2.8 m; ~0.9 m shows, base buried.
	var s := 0.82
	var y := _beach_base(19.5, 11.0) + 0.9 - HERO_TOP * s
	props.append(_prop("res://assets/models/coast_rocks_05/coast_rocks_05_4k.gltf",
			Vector3(19.5, y, 11.0), s, 0.4))
	# Cluster stamp 1: namaqualand boulder, long axis rotated across the stamp.
	s = 0.65
	y = _beach_base(17.5, 20.0) + 0.5 - NAMAQ_TOP * s
	props.append(_prop("res://assets/models/namaqualand_boulder_02/namaqualand_boulder_02_4k.gltf",
			Vector3(17.5, y, 20.0), s, 1.1))
	# Cluster stamp 2: same boulder, smaller + different heading.
	s = 0.5
	y = _beach_base(18.5, 21.5) + 0.4 - NAMAQ_TOP * s
	props.append(_prop("res://assets/models/namaqualand_boulder_02/namaqualand_boulder_02_4k.gltf",
			Vector3(18.5, y, 21.5), s, 3.9))
	# Cluster stamp 3: flat scatter of small rocks draped on the bump,
	# embedded 3 cm so no floating edges.
	s = 0.55
	y = _beach_base(21.5, 22.5) + 0.35 - SANDROCKS_TOP * s - 0.03
	props.append(_prop("res://assets/models/sand_rocks_small_01/sand_rocks_small_01_4k.gltf",
			Vector3(21.5, y, 22.5), s, 2.2))
	return props
