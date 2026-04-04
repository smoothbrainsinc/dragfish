extends Node3D

@export var rng_seed: int = 666
@export var prop_scene: PackedScene
@export var density: float = 0.02   # amount per triangle area
@export var min_scale: float = 0.8
@export var max_scale: float = 1.5

@export var min_depth: float = -100.0
@export var max_depth: float = 0.0

@onready var mesh_instance: MeshInstance3D = $"../L2-sandy"

var rng := RandomNumberGenerator.new()

func _ready():
	if not mesh_instance or not mesh_instance.mesh:
		push_error("Mesh not found")
		return

	rng.seed = rng_seed

	spawn_on_mesh()
	
func spawn_on_mesh():
	var mdt = MeshDataTool.new()
	var err = mdt.create_from_surface(mesh_instance.mesh, 0)

	if err != OK:
		push_error("MeshDataTool failed")
		return

	var face_count = mdt.get_face_count()

	for face in face_count:
		var a = mesh_instance.to_global(mdt.get_vertex(mdt.get_face_vertex(face, 0)))
		var b = mesh_instance.to_global(mdt.get_vertex(mdt.get_face_vertex(face, 1)))
		var c = mesh_instance.to_global(mdt.get_vertex(mdt.get_face_vertex(face, 2)))

		var area = triangle_area(a, b, c)

		# how many objects on this triangle
		var count = int(area * density)

		for i in count:
			var pos = random_point_in_triangle(a, b, c)

			# depth filter
			if pos.y < min_depth or pos.y > max_depth:
				continue

			spawn_prop(pos)
			
func triangle_area(a: Vector3, b: Vector3, c: Vector3) -> float:
	return ((b - a).cross(c - a)).length() * 0.5


func random_point_in_triangle(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var r1 = sqrt(rng.randf())
	var r2 = rng.randf()

	return a * (1.0 - r1) + b * (r1 * (1.0 - r2)) + c * (r1 * r2)
	
func spawn_prop(pos: Vector3):
	if not prop_scene:
		return

	var inst = prop_scene.instantiate()
	inst.position = pos

	inst.rotate_y(rng.randf() * TAU)

	var s = rng.randf_range(min_scale, max_scale)
	inst.scale = Vector3.ONE * s

	add_child(inst)
