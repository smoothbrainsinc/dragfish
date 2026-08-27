extends Node3D

@onready var core = $FlameCore
@onready var main = $FlameMain
@onready var glow = $FlameGlow

var engine_rpm = 0.0

func _ready():
	# Wait one frame for everything to load
	await get_tree().process_frame
	
	# Check if materials exist before using them
	if core and core.material_override:
		var offset = randf_range(0.0, 10.0)
		core.material_override.set_shader_parameter("time_offset", offset)
	else:
		push_error("FlameCore has no material_override!")
	
	if main and main.material_override:
		var offset = randf_range(0.0, 10.0)
		main.material_override.set_shader_parameter("time_offset", offset + 2.0)
	else:
		push_error("FlameMain has no material_override!")
	
	if glow and glow.material_override:
		var offset = randf_range(0.0, 10.0)
		glow.material_override.set_shader_parameter("time_offset", offset + 5.0)
	else:
		push_error("FlameGlow has no material_override!")

func set_rpm(rpm: float):
	engine_rpm = rpm
	var normalized = clamp(rpm / 8000.0, 0.0, 1.0)
	
	var height = 0.5 + normalized * 3.5
	var width = 0.15 + normalized * 0.4
	var speed = 2.0 + normalized * 6.0
	
	if core and core.material_override:
		core.material_override.set_shader_parameter("flame_height", height * 0.4)
		core.material_override.set_shader_parameter("flame_width", width * 0.5)
		core.material_override.set_shader_parameter("speed", speed * 1.5)
	
	if main and main.material_override:
		main.material_override.set_shader_parameter("flame_height", height)
		main.material_override.set_shader_parameter("flame_width", width)
		main.material_override.set_shader_parameter("speed", speed)
	
	if glow and glow.material_override:
		glow.material_override.set_shader_parameter("flame_height", height * 1.8)
		glow.material_override.set_shader_parameter("flame_width", width * 2.0)
		glow.material_override.set_shader_parameter("speed", speed * 0.7)

func _process(_delta):
	pass
