extends Node3D

@export_file("*.glb", "*.gltf", "*.tres", "*.res") var fish_model_path: String = "res://assets/models/fishes/blue_gill2.glb"
@export var number_of_fish: int = 1000
@export var swim_speed: float = 1.0
@export var turn_speed: float = 2.0
@export var separation_weight: float = 1.0
@export var alignment_weight: float = 5.0
@export var cohesion_weight: float = 3.0
@export var perception_radius: float = 15.0
@export var animation_speed: float = 2.0
@export var tail_wave_amplitude: float = 0.2
@export var grid_cell_size: float = 8.0
@export var lake_radius: float = 650.0
@export var spawn_center: Vector3 = Vector3(0, 0, 400)
@export var inner_x: float = 300.0
@export var inner_z: float = 230.0
@export var outer_x: float = 600.0
@export var outer_z: float = 600.0
@export var surface_y: float = 0.0
@export var max_depth: float = -10.0

var multi_mesh_instance: MultiMeshInstance3D
var fish_data: Array = []
var spatial_grid: Dictionary = {}
var grid_pool: Array = []  # reusable PackedInt32Array buckets, avoids per-frame allocation
var pool_index: int = 0

class FishData:
	var position: Vector3
	var velocity: Vector3
	var animation_offset: float
	func _init(pos: Vector3, vel: Vector3, anim_offset: float):
		position = pos
		velocity = vel
		animation_offset = anim_offset

const FISH_SHADER_CODE = """
shader_type spatial;
uniform sampler2D texture_albedo : source_color;
uniform float animation_speed : hint_range(0.1, 10.0) = 2.0;
uniform float tail_wave_amplitude : hint_range(0.0, 1.0) = 0.2;
uniform float tail_wave_frequency : hint_range(0.1, 10.0) = 5.0;
uniform float body_wave_amplitude : hint_range(0.0, 0.5) = 0.1;
varying vec3 world_pos;
void vertex() {
	float time_offset = INSTANCE_CUSTOM.r;
	float time = TIME * animation_speed + time_offset;
	float distance_from_head = max(0.0, VERTEX.x);
	float normalized_distance = clamp(distance_from_head / 0.5, 0.0, 1.0);
	float wave_strength = normalized_distance * normalized_distance;
	float horizontal_wave = sin(time * tail_wave_frequency - normalized_distance * 3.0)
	                       * tail_wave_amplitude * wave_strength;
	float vertical_wave = sin(time * tail_wave_frequency * 0.7 - normalized_distance * 2.0)
	                     * body_wave_amplitude * wave_strength;
	VERTEX.z += horizontal_wave;
	VERTEX.y += vertical_wave * 0.3;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	NORMAL.z += horizontal_wave * 0.5;
	NORMAL = normalize(NORMAL);
}
void fragment() {
	vec4 albedo_tex = texture(texture_albedo, UV);
	ALBEDO = albedo_tex.rgb;
	ALPHA = albedo_tex.a;
}
"""

func _ready():
	print("\n=== FULL FLOCKING FISH SPAWNER ===")
	var fish_mesh = load_fish_mesh()
	if not fish_mesh:
		push_error("Could not load fish mesh!")
		return
	var fish_material = create_shader_material()
	if not fish_material:
		push_error("Could not create material!")
		return
	setup_multimesh(fish_mesh, fish_material)
	spawn_fish()
	print("✓ Spawned ", number_of_fish, " fish")

func _get_cell(pos: Vector3) -> Vector3i:
	return Vector3i(
		int(pos.x / grid_cell_size),
		int(pos.y / grid_cell_size),
		int(pos.z / grid_cell_size)
	)

func _rebuild_grid() -> void:
	spatial_grid.clear()
	pool_index = 0
	for i in fish_data.size():
		var cell = _get_cell(fish_data[i].position)
		if not spatial_grid.has(cell):
			spatial_grid[cell] = _get_pooled_bucket()
		spatial_grid[cell].append(i)

# Reuse PackedInt32Array buckets across frames instead of allocating a new
# Array for every occupied cell every frame (was the main per-frame GC cost).
func _get_pooled_bucket() -> PackedInt32Array:
	if pool_index < grid_pool.size():
		var bucket: PackedInt32Array = grid_pool[pool_index]
		bucket.resize(0)
		pool_index += 1
		return bucket
	var new_bucket := PackedInt32Array()
	grid_pool.append(new_bucket)
	pool_index += 1
	return new_bucket

func _process(delta):
	_rebuild_grid()
	update_fish(delta)
	if fish_data.size() > 0:
		var world_pos = multi_mesh_instance.global_transform * multi_mesh_instance.multimesh.get_instance_transform(0).origin
		print("fish0 local: ", fish_data[0].position, " | fish0 world: ", world_pos)

func update_fish(delta):
	for i in range(fish_data.size()):
		var fish = fish_data[i]
		var steer = calculate_flocking(i)

		var wander = Vector3(
			randf_range(-1, 1),
			randf_range(-0.1, 0.1),
			randf_range(-1, 1)
		).normalized() * 0.5

		var acceleration = Vector3.ZERO
		acceleration += steer.separation * separation_weight
		acceleration += steer.alignment * alignment_weight
		acceleration += steer.cohesion * cohesion_weight
		acceleration += wander

		var desired_velocity = fish.velocity + acceleration * delta
		desired_velocity = desired_velocity.normalized() * swim_speed

		# turn_speed now actually limits how fast heading can change per frame,
		# instead of velocity snapping instantly to the new direction.
		var max_turn = turn_speed * delta
		fish.velocity = fish.velocity.slerp(desired_velocity, clamp(max_turn, 0.0, 1.0))
		if fish.velocity.length() < 0.001:
			fish.velocity = desired_velocity

		fish.position += fish.velocity * delta

		if fish.position.y > surface_y:
			fish.position.y = surface_y
			fish.velocity.y = -abs(fish.velocity.y)
		elif fish.position.y < max_depth:
			fish.position.y = max_depth
			fish.velocity.y = abs(fish.velocity.y)

		# Bug fix: boundary check was against Vector3.ZERO while fish spawn
		# and school around spawn_center — fish near the spawn ring edge were
		# yanked toward world origin instead of staying in the lake.
		var distance_from_center = Vector2(
			fish.position.x - spawn_center.x,
			fish.position.z - spawn_center.z
		).length()
		if distance_from_center > lake_radius:
			var direction_to_center = Vector3(
				spawn_center.x - fish.position.x,
				0,
				spawn_center.z - fish.position.z
			).normalized()
			fish.velocity += direction_to_center * 3.0 * delta

		var fish_transform = Transform3D()
		fish_transform.origin = fish.position
		var target_direction = fish.velocity.normalized()
		if target_direction.length() > 0.1:
			var right = target_direction
			var up = Vector3.UP
			if abs(right.dot(up)) > 0.99:
				up = Vector3.FORWARD
			var forward = up.cross(right).normalized()
			up = right.cross(forward).normalized()
			fish_transform.basis = Basis(-right, up, forward)
		else:
			fish_transform.basis = multi_mesh_instance.multimesh.get_instance_transform(i).basis
		multi_mesh_instance.multimesh.set_instance_transform(i, fish_transform)

# Single neighbor pass computing distance once per pair instead of three
# separate loops (separation/alignment/cohesion) each recomputing it.
func calculate_flocking(index: int) -> Dictionary:
	var fish = fish_data[index]
	var cell = _get_cell(fish.position)

	var sep_sum = Vector3.ZERO
	var sep_total = 0
	var align_sum = Vector3.ZERO
	var align_total = 0
	var coh_sum = Vector3.ZERO
	var coh_total = 0

	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var neighbor_cell = Vector3i(cell.x + dx, cell.y + dy, cell.z + dz)
				if not spatial_grid.has(neighbor_cell):
					continue
				var bucket: PackedInt32Array = spatial_grid[neighbor_cell]
				for other_index in bucket:
					if other_index == index:
						continue
					var other = fish_data[other_index]
					var distance = fish.position.distance_to(other.position)
					if distance >= perception_radius:
						continue

					if distance > 0.0:
						sep_sum += (fish.position - other.position).normalized() / distance
						sep_total += 1

					align_sum += other.velocity
					align_total += 1

					coh_sum += other.position
					coh_total += 1

	var separation = Vector3.ZERO
	if sep_total > 0:
		separation = (sep_sum / sep_total).normalized() * swim_speed
		separation -= fish.velocity
		separation = separation.limit_length(1.0)

	var alignment = Vector3.ZERO
	if align_total > 0:
		alignment = (align_sum / align_total).normalized() * swim_speed
		alignment -= fish.velocity
		alignment = alignment.limit_length(0.5)

	var cohesion = Vector3.ZERO
	if coh_total > 0:
		var center = coh_sum / coh_total
		cohesion = (center - fish.position).normalized() * swim_speed
		cohesion -= fish.velocity
		cohesion = cohesion.limit_length(0.5)

	return {
		"separation": separation,
		"alignment": alignment,
		"cohesion": cohesion
	}

func spawn_fish():
	for i in range(number_of_fish):
		var pos = _random_point_in_rect_ring()
		var vel = Vector3(
			randf_range(-1, 1),
			randf_range(-0.1, 0.1),
			randf_range(-1, 1)
		).normalized() * swim_speed
		var anim_offset = randf_range(0, 100)
		fish_data.append(FishData.new(pos, vel, anim_offset))
		var fish_transform = Transform3D()
		fish_transform.origin = pos
		fish_transform = fish_transform.looking_at(pos + vel, Vector3.UP)
		multi_mesh_instance.multimesh.set_instance_transform(i, fish_transform)
		multi_mesh_instance.multimesh.set_instance_custom_data(i, Color(anim_offset, 0, 0, 1))

func _random_point_in_rect_ring() -> Vector3:
	while true:
		var x = randf_range(-outer_x, outer_x)
		var z = randf_range(-outer_z, outer_z)
		var outside_inner = abs(x) > inner_x or abs(z) > inner_z
		if outside_inner:
			return Vector3(
				spawn_center.x + x,
				randf_range(surface_y - 1.0, max_depth + 1.0),
				spawn_center.z + z
			)
	return Vector3.ZERO

func load_fish_mesh() -> Mesh:
	if fish_model_path == "" or not FileAccess.file_exists(fish_model_path):
		push_error("Fish model not found: ", fish_model_path)
		return null
	var resource = load(fish_model_path)
	if resource is Mesh:
		return resource
	if resource is PackedScene:
		var instance = resource.instantiate()
		var mesh = find_mesh_in_node(instance)
		instance.queue_free()
		return mesh
	return null

func find_mesh_in_node(node: Node) -> Mesh:
	if node is MeshInstance3D and node.mesh:
		return node.mesh
	for child in node.get_children():
		var mesh = find_mesh_in_node(child)
		if mesh:
			return mesh
	return null

func create_shader_material() -> ShaderMaterial:
	var material = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = FISH_SHADER_CODE
	material.shader = shader
	var texture = get_original_texture()
	if texture:
		material.set_shader_parameter("texture_albedo", texture)
	material.set_shader_parameter("animation_speed", animation_speed)
	material.set_shader_parameter("tail_wave_amplitude", tail_wave_amplitude)
	material.set_shader_parameter("tail_wave_frequency", 5.0)
	material.set_shader_parameter("body_wave_amplitude", 0.1)
	return material

func get_original_texture() -> Texture2D:
	if fish_model_path == "" or not FileAccess.file_exists(fish_model_path):
		return null
	var resource = load(fish_model_path)
	if resource is PackedScene:
		var instance = resource.instantiate()
		var texture = find_texture_in_node(instance)
		instance.queue_free()
		return texture
	return null

func find_texture_in_node(node: Node) -> Texture2D:
	if node is MeshInstance3D and node.mesh:
		var mat = node.get_surface_override_material(0)
		if not mat and node.mesh.get_surface_count() > 0:
			mat = node.mesh.surface_get_material(0)
		if mat:
			if mat is StandardMaterial3D and mat.albedo_texture:
				return mat.albedo_texture
			elif mat is ShaderMaterial:
				for param in ["texture_albedo", "albedo_texture", "base_texture"]:
					var tex = mat.get_shader_parameter(param)
					if tex is Texture2D:
						return tex
	for child in node.get_children():
		var texture = find_texture_in_node(child)
		if texture:
			return texture
	return null

func setup_multimesh(mesh: Mesh, material: Material):
	multi_mesh_instance = MultiMeshInstance3D.new()
	add_child(multi_mesh_instance)
	var multi_mesh = MultiMesh.new()
	multi_mesh.mesh = mesh
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.use_custom_data = true
	multi_mesh.instance_count = number_of_fish
	multi_mesh_instance.multimesh = multi_mesh
	multi_mesh_instance.material_override = material
	multi_mesh_instance.custom_aabb = AABB(Vector3(-683, -15, -662), Vector3(1366, 20, 1323))
