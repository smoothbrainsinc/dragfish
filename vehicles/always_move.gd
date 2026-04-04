extends VehicleBody3D

@export var move_speed: float = 50.0

func _physics_process(_delta):
	# Just fucking move
	engine_force = move_speed
	
	# Show we're alive
	if Engine.get_frames_drawn() % 60 == 0:
		print("[%s] Speed: %.1f m/s" % [name, linear_velocity.length()])
