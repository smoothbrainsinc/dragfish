extends Node3D


func _ready():
	await get_tree().process_frame
	for n in get_tree().root.find_children("*", "CollisionShape3D", true, false):
		var s = n.shape
		if s is ConcavePolygonShape3D:
			for v in s.get_faces():
				var w = n.global_transform * v
				if w.y > 5.0:
					Log.d(Log.Category.WORLD, n.get_path(), " | ", s.resource_path, " | ", w)
					break
