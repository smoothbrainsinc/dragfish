extends Node3D
## Attach to a node whose children are exhaust marker Node3Ds

@export var flame_texture: Texture2D = preload("res://textures/T_fire_flipbook4_sm.png")
@export var h_frames: int = 4
@export var v_frames: int = 4
@export var particle_amount: int = 8
@export var flame_scale: float = 0.15
@export var exhaust_direction: Vector3 = Vector3(0, 0, 1) # local space, points OUT of pipe

func _ready():
	for marker in get_children():
		if marker is Node3D:
			add_flame(marker)

func add_flame(marker: Node3D):
	var particles = GPUParticles3D.new()
	particles.amount = particle_amount
	particles.lifetime = 0.4
	particles.local_coords = false

	var process_mat = ParticleProcessMaterial.new()
	process_mat.direction = exhaust_direction
	process_mat.spread = 15.0
	process_mat.initial_velocity_min = 1.5
	process_mat.initial_velocity_max = 3.0
	process_mat.gravity = Vector3.ZERO
	process_mat.scale_min = flame_scale * 0.6
	process_mat.scale_max = flame_scale
	process_mat.color = Color(1.0, 0.6, 0.2)
	particles.process_material = process_mat

	var quad = QuadMesh.new()
	quad.size = Vector2(flame_scale * 4, flame_scale * 4)

	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.particles_anim_h_frames = h_frames
	mat.particles_anim_v_frames = v_frames
	mat.particles_anim_loop = false
	mat.albedo_texture = flame_texture
	quad.material = mat
	particles.draw_pass_1 = quad

	marker.add_child(particles)
