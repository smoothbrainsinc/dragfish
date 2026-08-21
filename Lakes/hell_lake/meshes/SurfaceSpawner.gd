extends Node
class_name SurfaceSpawner

## Point this at the MeshInstance3D whose surface you want to spawn on (the lake, a field, etc).
@export var target_mesh_path: NodePath

## Drag in as many SpawnEntry .tres resources as you want spawned on that mesh's surface.
@export var entries: Array[SpawnEntry] = []

var _target: MeshInstance3D
var _mdt: MeshDataTool
var _valid_tris: Array = []
var _valid_areas: Array = []
var _total_area: float = 0.0
var _surface_y: float = 0.0

func _ready():
	_target = get_node(target_mesh_path) as MeshInstance3D
	if not _target or not _target.mesh:
		push_error("SurfaceSpawner: target_mesh_path not set or has no mesh")
		return
	_sample_surface()
	for entry in entries:
		_spawn_entry(entry)

func _sample_surface():
	_mdt = MeshDataTool.new()
	if _mdt.create_from_surface(_target.mesh, 0) != OK:
		push_error("SurfaceSpawner: MeshDataTool failed")
		return
	var y_sum = 0.0
	var y_count = 0
	for f in _mdt.get_face_count():
		var a = _mdt.get_vertex(_mdt.get_face_vertex(f, 0))
		var b = _mdt.get_vertex(_mdt.get_face_vertex(f, 1))
		var c = _mdt.get_vertex(_mdt.get_face_vertex(f, 2))
		var area = (b - a).cross(c - a).length() * 0.5
		_valid_tris.append(f)
		_valid_areas.append(area)
		_total_area += area
		for v in [a, b, c]:
			y_sum += v.y
			y_count += 1
	if y_count > 0:
		_surface_y = y_sum / y_count

func _random_point(entry: SpawnEntry) -> Vector3:
	var tris = _valid_tris
	var areas = _valid_areas
	var total = _total_area
	if entry.patch_radius > 0.0:
		tris = []
		areas = []
		total = 0.0
		for i in _valid_tris.size():
			var f = _valid_tris[i]
			var pa = _mdt.get_vertex(_mdt.get_face_vertex(f, 0))
			var pb = _mdt.get_vertex(_mdt.get_face_vertex(f, 1))
			var pc = _mdt.get_vertex(_mdt.get_face_vertex(f, 2))
			var center = (pa + pb + pc) / 3.0
			if Vector2(center.x - entry.patch_center.x, center.z - entry.patch_center.z).length() <= entry.patch_radius:
				tris.append(f)
				areas.append(_valid_areas[i])
				total += _valid_areas[i]
	if tris.is_empty():
		return Vector3.ZERO
	var tri = _pick_weighted_tri(tris, areas, total)
	var a = _mdt.get_vertex(_mdt.get_face_vertex(tri, 0))
	var b = _mdt.get_vertex(_mdt.get_face_vertex(tri, 1))
	var c = _mdt.get_vertex(_mdt.get_face_vertex(tri, 2))
	var r1 = sqrt(randf())
	var r2 = randf()
	var pos = a * (1.0 - r1) + b * (r1 * (1.0 - r2)) + c * (r1 * r2)
	pos.y += entry.y_offset
	return pos

func _pick_weighted_tri(tris: Array, areas: Array, total: float) -> int:
	var r = randf() * total
	var cum = 0.0
	for i in areas.size():
		cum += areas[i]
		if r <= cum:
			return tris[i]
	return tris[-1]

func _spawn_entry(entry: SpawnEntry):
	var model = _load_mesh(entry.model_path)
	if not model:
		push_error("SurfaceSpawner: could not load " + entry.model_path)
		return
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = model
	mm.instance_count = entry.count
	mm.use_custom_data = entry.moves  # fish need custom data for shader animation offset
	for i in entry.count:
		var pos = _random_point(entry)
		var s = randf_range(entry.min_scale, entry.max_scale)
		var facing = randf() * TAU
		var xform: Transform3D
		if entry.moves:
			xform = Transform3D(Basis(), pos)  # FishFlock takes over orientation
			mm.set_instance_custom_data(i, Color(randf_range(0, 100), 0, 0, 1))
		else:
			var b = Basis().rotated(Vector3.UP, facing).scaled(Vector3(s, s, s))
			xform = Transform3D(b, pos)
		mm.set_instance_transform(i, xform)

	var mmi = MultiMeshInstance3D.new()
	mmi.multimesh = mm
	_target.add_child(mmi)  # child of the lake, not the spawner — local space matches automatically

	if entry.moves:
		var flock = preload("res://scenes/fish_flock.gd").new()
		flock.setup(mmi, entry, _surface_y)
		_target.add_child(flock)

	print("SurfaceSpawner: placed %d of %s (%s)" % [entry.count, entry.model_path, "moving" if entry.moves else "static"])

func _load_mesh(path: String) -> Mesh:
	var res = load(path)
	if res is Mesh:
		return res
	if res is PackedScene:
		var inst = res.instantiate()
		var m = _find_mesh(inst)
		inst.queue_free()
		return m
	return null

func _find_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D and node.mesh:
		return node.mesh
	for child in node.get_children():
		var m = _find_mesh(child)
		if m:
			return m
	return null
