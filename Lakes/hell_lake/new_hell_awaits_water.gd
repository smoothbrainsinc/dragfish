extends Node3D

@onready var water_mat: ShaderMaterial = $WaterMesh.get_surface_override_material(0)
@onready var capture_cam: Camera3D = $SubViewport/TopDownCamera

func _process(_delta):
	water_mat.set_shader_parameter("cam_position", capture_cam.global_position)
	water_mat.set_shader_parameter("orthographic_cam_size", capture_cam.size)
	water_mat.set_shader_parameter("render_texture", $SubViewport.get_texture())
