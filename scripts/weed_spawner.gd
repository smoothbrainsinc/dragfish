@tool
extends Node3D

@export var shore_y_offset: float = 0.25

func _ready():
	# Load grass mesh
	var mesh_scene = load("res://grass.glb").instantiate()
	var mi = mesh_scene.find_child("*", true, false) as MeshInstance3D
	var grass_mesh = mi.mesh
	mesh_scene.free()

	# Get the L2-sandy mesh vertices
	var sandy = get_node("../../L2-sandy") as MeshInstance3D
	var sandy_mesh = sandy.mesh
	var mdt = MeshDataTool.new()
	mdt.create_from_surface(sandy_mesh, 0)

	# Set up multimesh
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = mdt.get_vertex_count()
	mm.mesh = grass_mesh

	for i in mdt.get_vertex_count():
		var pos = sandy.to_global(mdt.get_vertex(i))
		pos.y += shore_y_offset
		var xform = Transform3D()
		xform.origin = pos
		xform = xform.rotated(Vector3.UP, randf() * TAU)
		var s = randf_range(0.8, 1.4)
		xform = xform.scaled(Vector3(s, s, s))
		mm.set_instance_transform(i, xform)

	var mmi = MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
