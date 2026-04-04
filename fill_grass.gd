@tool
extends EditorScript

func _run():
	var scene = load("res://assets/models/fishes/grass.glb")
	var instance = scene.instantiate()
	var mesh_instance = instance.find_child("grass_iPlants-Agrostis-Pack-01", true, false)
	var mesh = mesh_instance.mesh

	var root = get_scene()
	var mmi = root.find_child("MultiMeshInstance3D", true, false)
	var mm = mmi.multimesh
	mm.mesh = mesh
	mm.instance_count = 5000

	for i in range(5000):
		var t = Transform3D()
		t.origin = Vector3(
			randf_range(-60, 60),
			0.0,
			randf_range(-60, 60)
		)
		t.basis = Basis(Vector3.UP, randf_range(0, TAU))
		mm.set_instance_transform(i, t)

	instance.free()
	print("Done! Grass placed.")
