extends Node3D

@export var seed: int = 666

@export var lake_size: float = 1500.0
@export var chunk_size: float = 10.0

@export var weed_scene: PackedScene
@export var weed_density: float = 0.02   # tweak this

var rng := RandomNumberGenerator.new()

func _ready():
	generate_lake()



func generate_lake():
	var chunks = int(lake_size / chunk_size)

	for cx in range(chunks):
		for cz in range(chunks):
			generate_chunk(cx, cz)

func generate_chunk(cx: int, cz: int):
	rng.seed = hash([seed, cx, cz])

	var origin_x = cx * chunk_size - lake_size / 2.0
	var origin_z = cz * chunk_size - lake_size / 2.0

	var count = int(chunk_size * chunk_size * weed_density)

	for i in count:
		var x = origin_x + rng.randf_range(0, chunk_size)
		var z = origin_z + rng.randf_range(0, chunk_size)

		var pos = Vector3(x, 0, z)

		# 🔴 IMPORTANT: adjust this Y manually if needed
		pos.y = get_water_floor_height(pos)

		spawn_weed(pos)

func spawn_weed(pos: Vector3):
	if not weed_scene:
		return

	var inst = weed_scene.instantiate()
	inst.position = pos

	inst.rotate_y(rng.randf() * TAU)

	var s = rng.randf_range(0.8, 1.5)
	inst.scale = Vector3.ONE * s

	add_child(inst)

func get_water_floor_height(pos: Vector3) -> float:
	var space = get_world_3d().direct_space_state

	var from = pos + Vector3(0, 50, 0)
	var to = pos + Vector3(0, -100, 0)

	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space.intersect_ray(query)

	if result:
		return result.position.y

	return -40.0
