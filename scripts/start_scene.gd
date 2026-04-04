extends PanelContainer
## Startup/Main Menu Scene
## Ensures GameManager initializes before going to car selection

@onready var choose_vehicle_btn = $ColorRect/VBoxContainer/HBoxContainer/choose_vehicle
@onready var garage_btn = $ColorRect/VBoxContainer/HBoxContainer/garage
@onready var quit_btn = $ColorRect/VBoxContainer/HBoxContainer/quit

var is_ready = false

func _ready():
	print("\n=== PLUTO RACING - STARTUP ===\n")
	
	# Disable buttons until ready
	choose_vehicle_btn.disabled = true
	garage_btn.disabled = true
	
	# Connect button signals
	choose_vehicle_btn.pressed.connect(_on_choose_vehicle_pressed)
	garage_btn.pressed.connect(_on_garage_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)
	
	# Wait for GameManager to initialize
	await _wait_for_game_manager()
	
	# Enable buttons
	choose_vehicle_btn.disabled = false
	garage_btn.disabled = false
	is_ready = true
	
	print("=== READY TO RACE ===\n")

func _wait_for_game_manager():
	"""Wait for GameManager to discover vehicles"""
	print("[Startup] Waiting for GameManager...")
	
	# Give GameManager time to run its _ready() function
	await get_tree().process_frame
	await get_tree().process_frame
	
	var max_attempts = 10
	var attempt = 0
	
	while attempt < max_attempts:
		var available = GameManager.get_available_vehicles()
		
		if not available.is_empty():
			print("[Startup] ✓ GameManager ready - %d vehicles found" % available.size())
			for vehicle in available:
				print("  - %s (%d HP)" % [vehicle.display_name, vehicle.get_horsepower()])
			return
		
		# Wait a bit longer
		await get_tree().create_timer(0.1).timeout
		attempt += 1
		print("[Startup] Waiting... (attempt %d/%d)" % [attempt, max_attempts])
	
	# If we get here, something went wrong
	push_error("[Startup] GameManager failed to initialize!")
	push_error("[Startup] Check that vehicles exist in res://vehicles/")

func _on_choose_vehicle_pressed():
	if not is_ready:
		return
	
	print("[Startup] Going to car selection...")
	get_tree().change_scene_to_file("res://scenes/car_selection_screen.tscn")

func _on_garage_pressed():
	if not is_ready:
		return
	
	print("[Startup] Going to garage...")
	get_tree().change_scene_to_file("res://scenes/vehicle_setup_scene.tscn")

func _on_quit_pressed():
	print("[Startup] Quitting game...")
	get_tree().quit()
