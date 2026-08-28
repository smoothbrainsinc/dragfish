extends Node3D
## Attach to a node whose children are exhaust marker Node3Ds

@export var flame_texture: Texture2D = preload("res://assets/sprites/LeLu's Noise Pack/T_fire_flipbook4_sm.png")
@export var h_frames: int = 5
@export var v_frames: int = 5
@export var particle_amount: int = 16
@export var flame_scale: float = 0.08
@export var exhaust_direction: Vector3 = Vector3(0, 0, 1) # local space, points OUT of pipe

func _ready():
	for marker in get_children():
		if marker is Node3D:
			add_flame(marker)

func add_flame(marker: Node3D):
	var particles = GPUParticles3D.new()
	particles.amount = 16
	particles.lifetime = 0.25
	particles.local_coords = true   # locks trail behavior to marker instead of world

	var process_mat = ParticleProcessMaterial.new()
	process_mat.direction = exhaust_direction
	process_mat.spread = 8.0
	process_mat.initial_velocity_min = 4.0
	process_mat.initial_velocity_max = 7.0
	process_mat.gravity = Vector3.ZERO
	process_mat.scale_min = flame_scale * 0.4
	process_mat.scale_max = flame_scale
	process_mat.color = Color(1.2, 1.0, 0.8)
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
	mat.albedo_color = Color(1.2, 1.0, 0.8)
	quad.material = mat
	particles.draw_pass_1 = quad

	marker.add_child(particles)
