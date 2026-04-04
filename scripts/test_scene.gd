extends Node3D
## Test scene to verify vehicle spawning and physics
## FIXED: Proper initialization sequence

@onready var camera = $Camera3D
var test_vehicle: VehicleController = null

func _ready():
	print("\n=== VEHICLE SPAWN TEST ===\n")
	
	# Wait one frame for everything to initialize
	await get_tree().process_frame
	
	# Get available vehicles from GameManager
	var available = GameManager.get_available_vehicles()
	
	if available.is_empty():
		push_error("No vehicles available!")
		return
	
	print("Available vehicles:")
	for i in range(available.size()):
		var config: VehicleConfig = available[i]
		print("  [%d] %s - %d HP" % [i, config.display_name, config.get_horsepower()])
	
	# Use the first vehicle
	var config: VehicleConfig = available[0]
	print("\nSpawning: %s" % config.display_name)
	
	# Step 1: Spawn the vehicle (creates the scene instance)
	test_vehicle = GameManager.spawn_vehicle(config, true)
	
	if not test_vehicle:
		push_error("Failed to spawn vehicle!")
		return
	
	# Step 2: Add to scene tree FIRST
	add_child(test_vehicle)
	print("✓ Vehicle added to scene")
	
	# Step 3: Wait for modules to be added to tree
	await get_tree().process_frame
	
	# Step 4: Initialize (this creates and configures modules)
	print("✓ Initializing vehicle...")
	test_vehicle.initialize(config, true)
	
	# Step 5: Position it
	test_vehicle.position = Vector3(0, 2, 0)
	test_vehicle.rotation_degrees = Vector3(0, 0, 0)
	
	# Step 6: Wait for initialization to complete
	await get_tree().process_frame
	
	# Step 7: Start the race (enables physics and input)
	test_vehicle.start_race()
	
	print("\n=== RACE STARTED - Press W to accelerate ===")
	print("Vehicle stats:")
	print("  Mass: %.0f kg" % test_vehicle.mass)
	print("  Gear: %d" % test_vehicle.get_gear())
	print("  RPM: %.0f" % test_vehicle.get_rpm())
	print("  Engine HP: %d" % config.get_horsepower())

func _process(_delta):
	if test_vehicle and is_instance_valid(test_vehicle):
		# Position camera behind vehicle
		var vehicle_pos = test_vehicle.global_position
		var camera_offset = Vector3(0, 3, 8)
		camera.global_position = vehicle_pos + camera_offset
		camera.look_at(vehicle_pos, Vector3.UP)

func _physics_process(_delta):
	if test_vehicle and is_instance_valid(test_vehicle):
		# Debug output every second
		if Engine.get_physics_frames() % 60 == 0:
			print("RPM: %.0f | Gear: %d | Speed: %.1f m/s | Pos: %s" % [
				test_vehicle.get_rpm(),
				test_vehicle.get_gear(),
				test_vehicle.linear_velocity.length(),
				test_vehicle.position
			])

func _input(event):
	# Press ESC to restart
	if event.is_action_pressed("ui_cancel"):
		get_tree().reload_current_scene()
