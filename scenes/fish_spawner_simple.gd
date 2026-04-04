extends Node3D
# FISH SPAWNER - Manual material override version
# Drag your fish MeshInstance3D AND a ShaderMaterial into the Inspector

@export var source_fish_instance: MeshInstance3D  # Drag your fish here
@export var override_material: ShaderMaterial  # Create and drag fish_material.tres here (optional)
@export var number_of_fish: int = 1000
@export var spawn_radius: float = 50.0
@export var swim_speed: float = 4.0

var multi_mesh_instance: MultiMeshInstance3D
var time_elapsed: float = 0.0

func _ready():
	print("\n=== FISH SPAWNER STARTING ===")
	
	if not source_fish_instance:
		push_error("No source fish instance assigned!")
		return
	
	var fish_mesh = source_fish_instance.mesh
	if not fish_mesh:
		push_error("Source fish has no mesh!")
		return
	
	print("✓ Got mesh from: ", source_fish_instance.name)
	
	# Use override material if provided, otherwise try to create one
	var fish_material = override_material
	
	if not fish_material:
		print("⚠ No override material assigned, creating default...")
		fish_material = create_fish_material()
	else:
		print("✓ Using assigned override material")
	
	if not fish_material:
		push_error("Could not get material!")
		return
	
	# Create the fish school
	create_fish_school(fish_mesh, fish_material)
	print("✓ Spawned ", number_of_fish, " fish")
	print("=== READY! ===\n")

func create_fish_material() -> ShaderMaterial:
	# Try to load pre-made material first
	var material = load("res://fish_material.tres")
	if material and material is ShaderMaterial:
		print("  ✓ Loaded fish_material.tres")
		return material
	
	print("  Creating new shader material...")
	material = ShaderMaterial.new()
	
	var shader = load("res://fish_shader.gdshader")
	if not shader:
		push_error("Could not find fish_shader.gdshader!")
		return null
	
	material.shader = shader
	
	# Set nice blue color
	material.set_shader_parameter("base_color", Color(0.3, 0.5, 0.8))
	material.set_shader_parameter("animation_speed", 2.0)
	material.set_shader_parameter("tail_wave_amplitude", 0.3)
	material.set_shader_parameter("tail_wave_frequency", 5.0)
	material.set_shader_parameter("body_wave_amplitude", 0.1)
	material.set_shader_parameter("metallic", 0.2)
	material.set_shader_parameter("roughness", 0.4)
	material.set_shader_parameter("specular", 0.5)
	
	print("  ✓ Created with blue color (0.3, 0.5, 0.8)")
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
