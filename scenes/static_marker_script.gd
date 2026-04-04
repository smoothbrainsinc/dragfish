extends Node3D

@export_file("*.tscn") var marker_scene_path: String = "/home/lucy/pluto-racing 123125(copy)/northern_pike.tscn"
@export var spawn_center: Vector3 = Vector3(0, 0, 0)
@export var inner_x: float = 240.0
@export var inner_z: float = 230.0
@export var outer_x: float = 500.0
@export var outer_z: float = 440.0
@export var num_markers: int = 36
@export var marker_depth: float = -5.0

func _ready():
	if marker_scene_path == "":
		push_error("[SpawnMarker] No marker scene set!")
		return
	
	var scene = load(marker_scene_path)
	if not scene:
		push_error("[SpawnMarker] Failed to load marker scene: " + marker_scene_path)
		return
	
	for i in range(num_markers):
		var pos = _random_point_in_rect_ring()
		var marker = scene.instantiate()
		marker.position = pos
		add_child(marker)
	
	print("[SpawnMarker] Placed %d markers" % num_markers)

func _random_point_in_rect_ring() -> Vector3:
	while true:
		var x = randf_range(-outer_x, outer_x)
		var z = randf_range(-outer_z, outer_z)
		
		var outside_inner = abs(x) > inner_x or abs(z) > inner_z
		
		if outside_inner:
			return Vector3(
				spawn_center.x + x,
				marker_depth,
				spawn_center.z + z
			)
	return Vector3.ZERO
