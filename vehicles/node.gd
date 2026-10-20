extends Node

var t := 0.0

func _physics_process(delta: float) -> void:
	t += delta
	if t < 3.0:
		return
	t = -1000000.0
	for w in get_parent().get_children():
		if w is VehicleWheel3D:
			print(w.name, " wheel basis: ", w.basis)
			for m in w.get_children():
				if m is MeshInstance3D:
					print("  ", m.name, " global basis: ", m.global_transform.basis, " det: ", m.global_transform.basis.determinant())
