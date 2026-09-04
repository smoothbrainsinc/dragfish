extends Node3D
## Attach to a node whose children are exhaust marker Node3Ds

@export var flame_texture: Texture2D
@export var h_frames: int = 5
@export var v_frames: int = 5
@export var flame_scale: float = 0.5
@export var exhaust_direction: Vector3 = Vector3(0, 0, -1)

func _ready():
	print("Found ", get_child_count(), " children")
	for marker in get_children():
		print("Child: ", marker.name, " Type: ", marker.get_class())
		print(marker.name, " forward: ", marker.global_transform.basis.z, " up: ", marker.global_transform.basis.y)
		if marker is Node3D:
			setup_flame(marker)

func setup_flame(marker: Node3D):
	if flame_texture == null:
		push_warning("Flame texture is missing! Assign it in the Inspector.")
		return

	var particles = CPUParticles3D.new()
	particles.name = "ExhaustFlame"
	particles.amount = 16
	particles.lifetime = 0.3
	particles.local_coords = true
	particles.emitting = true
	
	# Simulation properties
	particles.direction = exhaust_direction
	particles.spread = 15.0
	particles.initial_velocity_min = 5.0
	particles.initial_velocity_max = 10.0
	particles.gravity = Vector3.ZERO
	particles.scale_amount_min = flame_scale * 0.5
	particles.scale_amount_max = flame_scale
	particles.color = Color(1.0, 0.7, 0.3)
	
	# Texture and Animation properties (Built directly into CPUParticles3D)
	# Texture and Animation properties (CPUParticles3D draws through a mesh,
	# so the texture + sprite-sheet animation live on the mesh's material)
	var quad_mesh = QuadMesh.new()
	quad_mesh.size = Vector2(flame_scale, flame_scale)

	var flame_material = StandardMaterial3D.new()
	flame_material.albedo_texture = flame_texture
	flame_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_material.particles_anim_h_frames = h_frames
	flame_material.particles_anim_v_frames = v_frames
	flame_material.particles_anim_loop = false

	quad_mesh.material = flame_material
	particles.mesh = quad_mesh

	particles.anim_speed_min = 15.0
	particles.anim_speed_max = 75.0
	particles.anim_offset_min = 0.0
	particles.anim_offset_max = 0.0

	marker.add_child(particles)
