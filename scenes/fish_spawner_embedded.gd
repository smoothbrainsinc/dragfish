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
				var neighbor_cell = Vector3i(cell.x + dx, cell.y + dy, cell.z + dz)
				if spatial_grid.has(neighbor_cell):
					for other_index in spatial_grid[neighbor_cell]:
						if other_index != index:
							neighbors.append(other_index)
	return neighbors

func _process(delta):
	_rebuild_grid()
	update_fish(delta)

func update_fish(delta):
	for i in range(fish_data.size()):
		var fish = fish_data[i]
		var neighbors = _get_neighbors(i)
		
		var separation = calculate_separation(i, neighbors)
		var alignment = calculate_alignment(i, neighbors)
		var cohesion = calculate_cohesion(i, neighbors)
		
		var wander = Vector3(
			randf_range(-1, 1),
			randf_range(-0.1, 0.1),
			randf_range(-1, 1)
		).normalized() * 0.5
		
		var acceleration = Vector3.ZERO
		acceleration += separation * separation_weight
		acceleration += alignment * alignment_weight
		acceleration += cohesion * cohesion_weight
		acceleration += wander
		
		fish.velocity += acceleration * delta
		fish.velocity = fish.velocity.normalized() * swim_speed
		fish.position += fish.velocity * delta
		
		if fish.position.y > surface_y:
			fish.position.y = surface_y
			fish.velocity.y = -abs(fish.velocity.y)
		elif fish.position.y < max_depth:
			fish.position.y = max_depth
			fish.velocity.y = abs(fish.velocity.y)
		
		var lake_center = Vector3.ZERO
		var distance_from_center = Vector2(
			fish.position.x - lake_center.x,
			fish.position.z - lake_center.z
		).length()
		if distance_from_center > lake_radius:
			var direction_to_center = Vector3(
				lake_center.x - fish.position.x,
				0,
				lake_center.z - fish.position.z
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

func calculate_separation(index: int, neighbors: Array) -> Vector3:
	var steering = Vector3.ZERO
	var total = 0
	var fish = fish_data[index]
	for other_index in neighbors:
		var other = fish_data[other_index]
		var distance = fish.position.distance_to(other.position)
		if distance < perception_radius and distance > 0:
			var diff = (fish.position - other.position).normalized() / distance
			steering += diff
			total += 1
	if total > 0:
		steering /= total
		steering = steering.normalized() * swim_speed
		steering -= fish.velocity
		steering = steering.limit_length(1.0)
	return steering

func calculate_alignment(index: int, neighbors: Array) -> Vector3:
	var steering = Vector3.ZERO
	var total = 0
	var fish = fish_data[index]
	for other_index in neighbors:
		var other = fish_data[other_index]
		var distance = fish.position.distance_to(other.position)
		if distance < perception_radius:
			steering += other.velocity
			total += 1
	if total > 0:
		steering /= total
		steering = steering.normalized() * swim_speed
		steering -= fish.velocity
		steering = steering.limit_length(0.5)
	return steering

func calculate_cohesion(index: int, neighbors: Array) -> Vector3:
	var steering = Vector3.ZERO
	var total = 0
	var fish = fish_data[index]
	for other_index in neighbors:
		var other = fish_data[other_index]
		var distance = fish.position.distance_to(other.position)
		if distance < perception_radius:
			steering += other.position
			total += 1
	if total > 0:
		steering /= total
		steering -= fish.position
		steering = steering.normalized() * swim_speed
		steering -= fish.velocity
		steering = steering.limit_length(0.5)
	return steering

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
	multi_mesh_instance.custom_aabb = AABB(Vector3(-2000, -50, -2000), Vector3(4000, 100, 4000))
