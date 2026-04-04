extends Node3D
# FISH SPAWNER - Loads mesh directly from imported model files
# Works with .glb, .gltf, or extracted meshes

@export_file("*.glb", "*.gltf", "*.tres", "*.res") var fish_model_path: String = ""
@export var mesh_name_in_model: String = ""  # Leave empty to auto-find first mesh
@export var number_of_fish: int = 1000
@export var spawn_radius: float = 50.0
@export var swim_speed: float = 4.0

var multi_mesh_instance: MultiMeshInstance3D
var time_elapsed: float = 0.0

func _ready():
	print("\n=== FISH SPAWNER (Direct Load) ===")
	
	var fish_mesh: Mesh = null
	
	# Try different methods to get the mesh
	if fish_model_path != "":
		fish_mesh = load_mesh_from_file(fish_model_path)
	else:
		# Try common locations
		print("No model path specified, trying common locations...")
		fish_mesh = try_common_locations()
	
	if not fish_mesh:
		push_error("Could not load fish mesh!")
		push_error("Please set the 'Fish Model Path' in the Inspector")
		push_error("Example: res://models/fishes/blue_gill2.glb")
		return
	
	print("✓ Loaded fish mesh")
	
	# Create material
	var fish_material = create_fish_material()
	if not fish_material:
		push_error("Could not create material!")
		return
	
	print("✓ Created material")
	
	# Create the fish school
	create_fish_school(fish_mesh, fish_material)
	print("✓ Spawned ", number_of_fish, " fish")
	print("=== READY! ===\n")

func try_common_locations() -> Mesh:
	var paths = [
		"res://models/fishes/blue_gill2.glb",
		"res://assets/models/fishes/blue_gill2.glb",
		"res://fishes/blue_gill2.glb",
		"res://blue_gill2.glb",
		"res://models/blue_gill2.glb",
	]
	
	for path in paths:
		print("  Trying: ", path)
		var mesh = load_mesh_from_file(path)
		if mesh:
			return mesh
	
	return null

func load_mesh_from_file(path: String) -> Mesh:
	print("Loading from: ", path)
	
	if not FileAccess.file_exists(path):
		print("  File not found: ", path)
		return null
	
	var resource = load(path)
	if not resource:
		print("  Could not load resource")
		return null
	
	# If it's already a mesh, return it
	if resource is Mesh:
		print("  ✓ Found Mesh resource directly")
		return resource
	
	# If it's a scene (GLB/GLTF imports), search for mesh inside
	if resource is PackedScene:
		print("  Searching inside PackedScene...")
		var scene_instance = resource.instantiate()
		var mesh = find_mesh_in_node(scene_instance)
		scene_instance.queue_free()  # Clean up
		if mesh:
			print("  ✓ Found mesh inside scene")
			return mesh
	
	print("  Could not extract mesh from resource")
	return null

func find_mesh_in_node(node: Node) -> Mesh:
	# Check if this node is a MeshInstance3D
	if node is MeshInstance3D and node.mesh:
		if mesh_name_in_model == "" or node.name.to_lower().contains(mesh_name_in_model.to_lower()):
			print("    Found MeshInstance3D: ", node.name)
			return node.mesh
	
	# Search children
	for child in node.get_children():
		var mesh = find_mesh_in_node(child)
		if mesh:
			return mesh
	
	return null

func create_fish_material() -> ShaderMaterial:
	# Try to load existing material
	var material = load("res://fish_material.tres")
	if material and material is ShaderMaterial:
		print("  Using fish_material.tres")
		return material
	
	# Create new material
	material = ShaderMaterial.new()
	
	var shader = load("res://fish_shader.gdshader")
	if not shader:
		push_error("Could not find fish_shader.gdshader!")
		return null
	
	material.shader = shader
	
	# Set parameters
	material.set_shader_parameter("base_color", Color(0.3, 0.5, 0.8))
	material.set_shader_parameter("animation_speed", 2.0)
	material.set_shader_parameter("tail_wave_amplitude", 0.3)
	material.set_shader_parameter("tail_wave_frequency", 5.0)
	material.set_shader_parameter("body_wave_amplitude", 0.1)
	material.set_shader_parameter("metallic", 0.2)
	material.set_shader_parameter("roughness", 0.4)
	material.set_shader_parameter("specular", 0.5)
	
	print("  Created new material")
	return material

func create_fish_school(mesh: Mesh, material: Material):
	multi_mesh_instance = MultiMeshInstance3D.new()
	add_child(multi_mesh_instance)
	
	var multi_mesh = MultiMesh.new()
	multi_mesh.mesh = mesh
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.use_custom_data = true
	multi_mesh.instance_count = number_of_fish
	
	multi_mesh_instance.multimesh = multi_mesh
	multi_mesh_instance.material_override = material
	
	for i in range(number_of_fish):
		spawn_fish(i)

func spawn_fish(index: int):
	var radius = randf_range(0, spawn_radius)
	var theta = randf() * TAU
	var phi = randf() * PI
	
	var pos = Vector3(
		radius * sin(phi) * cos(theta),
		radius * sin(phi) * sin(theta),
		radius * cos(phi)
	)
	
	var transform = Transform3D()
	transform.origin = pos
	
	var random_forward = Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)).normalized()
	transform = transform.looking_at(pos + random_forward, Vector3.UP)
	
	multi_mesh_instance.multimesh.set_instance_transform(index, transform)
	
	var animation_offset = randf_range(0, 100)
	multi_mesh_instance.multimesh.set_instance_custom_data(index, Color(animation_offset, 0, 0, 1))

func _process(delta):
	if not multi_mesh_instance:
		return
		
	time_elapsed += delta
	
	for i in range(number_of_fish):
		var transform = multi_mesh_instance.multimesh.get_instance_transform(i)
		
		var angle_speed = 0.5
		var vertical_speed = 0.2
		
		transform = transform.rotated(Vector3.UP, angle_speed * delta)
		
		var height_offset = sin(time_elapsed + i * 0.1) * vertical_speed * delta
		transform.origin.y += height_offset
		
		transform.origin += -transform.basis.z * swim_speed * delta
		
		if transform.origin.length() > spawn_radius:
			transform.origin = transform.origin.normalized() * (spawn_radius * 0.9)
		
		multi_mesh_instance.multimesh.set_instance_transform(i, transform)

func _input(event):
	if event.is_action_pressed("ui_accept"):
		if multi_mesh_instance:
			for i in range(number_of_fish):
				spawn_fish(i)
			print("Fish respawned!")
	
	if event.is_action_pressed("ui_page_up"):
		number_of_fish = min(number_of_fish + 500, 20000)
		multi_mesh_instance.multimesh.instance_count = number_of_fish
		for i in range(number_of_fish - 500, number_of_fish):
			spawn_fish(i)
		print("Fish count: ", number_of_fish)
	
	if event.is_action_pressed("ui_page_down"):
		number_of_fish = max(number_of_fish - 500, 100)
		multi_mesh_instance.multimesh.instance_count = number_of_fish
		print("Fish count: ", number_of_fish)
