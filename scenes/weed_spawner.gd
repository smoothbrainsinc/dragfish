extends MeshInstance3D

@export var weed_model_path: String = "res://assets/models/fishes/reeds2.glb"
@export var weed_count: int = 500
@export var y_offset: float = 0.0
@export var min_scale: float = 0.8
@export var max_scale: float = 1.6
@export var patch_center: Vector3 = Vector3.ZERO
@export var patch_radius: float = 100.0
@export var use_patch: bool = false
@export var saved_multimesh: MultiMesh = null

func _ready():
	if saved_multimesh:
		var mmi = MultiMeshInstance3D.new()
		mmi.multimesh = saved_multimesh
		add_child(mmi)
		return
	_build_multimesh()

func _build_multimesh():
	var weed_mesh = _load_mesh(weed_model_path)
	if not weed_mesh:
		push_error("WeedSpawner: could not load mesh at " + weed_model_path)
		return

	var mdt = MeshDataTool.new()
	if mdt.create_from_surface(mesh, 0) != OK:
		push_error("WeedSpawner: MeshDataTool failed")
		return

	var face_count = mdt.get_face_count()

	var valid_tris = []
	var valid_areas = []
	var total_area = 0.0

	for f in face_count:
		var a = mdt.get_vertex(mdt.get_face_vertex(f, 0))
		var b = mdt.get_vertex(mdt.get_face_vertex(f, 1))
		var c = mdt.get_vertex(mdt.get_face_vertex(f, 2))
		if use_patch:
			var center = (a + b + c) / 3.0
			var dist = Vector2(center.x - patch_center.x, center.z - patch_center.z).length()
			if dist > patch_radius:
				continue
		var area = (b - a).cross(c - a).length() * 0.5
		valid_tris.append(f)
		valid_areas.append(area)
		total_area += area

	if valid_tris.is_empty():
		push_error("WeedSpawner: no triangles found in patch area")
		return

	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = weed_mesh
	mm.instance_count = weed_count

	for i in weed_count:
		var tri = _pick_weighted_tri(valid_tris, valid_areas, total_area)
		var a = mdt.get_vertex(mdt.get_face_vertex(tri, 0))
		var b = mdt.get_vertex(mdt.get_face_vertex(tri, 1))
		var c = mdt.get_vertex(mdt.get_face_vertex(tri, 2))
		var r1 = sqrt(randf())
		var r2 = randf()
		var local_pos = a * (1.0 - r1) + b * (r1 * (1.0 - r2)) + c * (r1 * r2)
		local_pos.y += y_offset
		var s = randf_range(min_scale, max_scale)
		var basis = Basis().rotated(Vector3.UP, randf() * TAU)
		basis = basis.scaled(Vector3(s, s, s))
		mm.set_instance_transform(i, Transform3D(basis, local_pos))

	saved_multimesh = mm
	var mmi = MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	print("WeedSpawner: placed %d weeds in %d valid faces" % [weed_count, valid_tris.size()])

func _pick_weighted_tri(tris: Array, areas: Array, total: float) -> int:
	var r = randf() * total
	var cum = 0.0
	for i in areas.size():
		cum += areas[i]
		if r <= cum:
			return tris[i]
	return tris[-1]

func _load_mesh(path: String) -> Mesh:
	var res = load(path)
	if res is Mesh: return res
	if res is PackedScene:
		var inst = res.instantiate()
		var m = _find_mesh(inst)
		inst.free()
		return m
	push_error("WeedSpawner: not a Mesh or PackedScene: " + path)
	return null

func _find_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D and node.mesh: return node.mesh
	for child in node.get_children():
		var m = _find_mesh(child)
		if m: return m
	return null
