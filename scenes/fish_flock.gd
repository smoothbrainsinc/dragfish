extends Node3D
class_name FishFlock

var multi_mesh_instance: MultiMeshInstance3D
var fish_data: Array = []
var spatial_grid: Dictionary = {}

var swim_speed: float
var separation_weight: float
var alignment_weight: float
var cohesion_weight: float
var perception_radius: float
var grid_cell_size: float
var surface_y: float
var max_depth_y: float

class FishData:
	var position: Vector3
	var velocity: Vector3
	func _init(pos: Vector3, vel: Vector3):
		position = pos
		velocity = vel

func setup(mmi: MultiMeshInstance3D, entry: SpawnEntry, sampled_surface_y: float):
	multi_mesh_instance = mmi
	swim_speed = entry.swim_speed
	separation_weight = entry.separation_weight
	alignment_weight = entry.alignment_weight
	cohesion_weight = entry.cohesion_weight
	perception_radius = entry.perception_radius
	grid_cell_size = entry.grid_cell_size
	surface_y = sampled_surface_y + entry.surface_offset
	max_depth_y = sampled_surface_y + entry.max_depth_offset

	for i in mmi.multimesh.instance_count:
		var pos = mmi.multimesh.get_instance_transform(i).origin
		var vel = Vector3(randf_range(-1, 1), randf_range(-0.1, 0.1), randf_range(-1, 1)).normalized() * swim_speed
		fish_data.append(FishData.new(pos, vel))

func _process(delta):
	_rebuild_grid()
	_update_fish(delta)

func _get_cell(pos: Vector3) -> Vector3i:
	return Vector3i(int(pos.x / grid_cell_size), int(pos.y / grid_cell_size), int(pos.z / grid_cell_size))

func _rebuild_grid():
	spatial_grid.clear()
	for i in fish_data.size():
		var cell = _get_cell(fish_data[i].position)
		if not spatial_grid.has(cell):
			spatial_grid[cell] = []
		spatial_grid[cell].append(i)

func _get_neighbors(index: int) -> Array:
	var cell = _get_cell(fish_data[index].position)
	var neighbors = []
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var nc = Vector3i(cell.x + dx, cell.y + dy, cell.z + dz)
				if spatial_grid.has(nc):
					for other in spatial_grid[nc]:
						if other != index:
							neighbors.append(other)
	return neighbors

func _update_fish(delta):
	for i in fish_data.size():
		var fish = fish_data[i]
		var neighbors = _get_neighbors(i)

		var separation = _separation(i, neighbors)
		var alignment = _alignment(i, neighbors)
		var cohesion = _cohesion(i, neighbors)
		var wander = Vector3(randf_range(-1, 1), randf_range(-0.1, 0.1), randf_range(-1, 1)).normalized() * 0.5

		var accel = separation * separation_weight + alignment * alignment_weight + cohesion * cohesion_weight + wander
		fish.velocity += accel * delta
		fish.velocity = fish.velocity.normalized() * swim_speed
		fish.position += fish.velocity * delta

		if fish.position.y > surface_y:
			fish.position.y = surface_y
			fish.velocity.y = -abs(fish.velocity.y)
		elif fish.position.y < max_depth_y:
			fish.position.y = max_depth_y
			fish.velocity.y = abs(fish.velocity.y)

		var xform = Transform3D()
		xform.origin = fish.position
		var dir = fish.velocity.normalized()
		if dir.length() > 0.1:
			var up = Vector3.UP if abs(dir.dot(Vector3.UP)) <= 0.99 else Vector3.FORWARD
			var forward = up.cross(dir).normalized()
			up = dir.cross(forward).normalized()
			xform.basis = Basis(-dir, up, forward)
		else:
			xform.basis = multi_mesh_instance.multimesh.get_instance_transform(i).basis
		multi_mesh_instance.multimesh.set_instance_transform(i, xform)

func _separation(index: int, neighbors: Array) -> Vector3:
	var steering = Vector3.ZERO
	var total = 0
	var fish = fish_data[index]
	for oi in neighbors:
		var other = fish_data[oi]
		var d = fish.position.distance_to(other.position)
		if d < perception_radius and d > 0:
			steering += (fish.position - other.position).normalized() / d
			total += 1
	if total > 0:
		steering = (steering / total).normalized() * swim_speed - fish.velocity
		steering = steering.limit_length(1.0)
	return steering

func _alignment(index: int, neighbors: Array) -> Vector3:
	var steering = Vector3.ZERO
	var total = 0
	var fish = fish_data[index]
	for oi in neighbors:
		var other = fish_data[oi]
		if fish.position.distance_to(other.position) < perception_radius:
			steering += other.velocity
			total += 1
	if total > 0:
		steering = (steering / total).normalized() * swim_speed - fish.velocity
		steering = steering.limit_length(0.5)
	return steering

func _cohesion(index: int, neighbors: Array) -> Vector3:
	var steering = Vector3.ZERO
	var total = 0
	var fish = fish_data[index]
	for oi in neighbors:
		var other = fish_data[oi]
		if fish.position.distance_to(other.position) < perception_radius:
			steering += other.position
			total += 1
	if total > 0:
		steering = (steering / total - fish.position).normalized() * swim_speed - fish.velocity
		steering = steering.limit_length(0.5)
	return steering
