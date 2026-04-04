extends Node

## Enhanced modular camera controller with multiple camera modes
## Press 1-8 to switch between cameras
## Press F1-F4 to follow different vehicles
## Press RMB to orbit around vehicle during gameplay
## Mouse wheel to zoom in/out
## Press R to reset camera to default behind position

# Camera configuration
@export_group("Camera Settings")
@export var camera_distance := 10.0
@export var camera_height := 5.0
@export var camera_smoothness := 5.0

# Free camera orbit settings
@export_group("Orbit Settings")
@export var orbit_sensitivity := 0.003
@export var zoom_speed := 1.0
@export var min_distance := 3.0
@export var max_distance := 30.0
@export var min_height := 1.0
@export var max_height := 15.0

# Camera management
@export_group("Camera Setup")
@export var target_group_name := "player_vehicle"
@export var cameras: Array[Camera3D] = []

var follow_camera: Camera3D
var target: Node3D
var current_camera_index := 0

# Available vehicles to follow
var available_vehicles := []
var current_vehicle_index := 0

# Orbit mode variables
var orbit_mode := false
var orbit_active := false  # TRUE = orbit locked, FALSE = follow mode
var orbit_angle_h := 0.0  # Horizontal rotation
var orbit_angle_v := 0.0  # Vertical rotation
var current_distance := camera_distance
var current_height := camera_height

# Pan mode variables
var pan_mode := false
var pan_offset := Vector3.ZERO
var pan_sensitivity := 0.01

func _ready():
	# Auto-find the target and all vehicles
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	find_all_vehicles()
	find_target()
	
	# Set up cameras
	setup_cameras()
	
	current_distance = camera_distance
	current_height = camera_height

func find_all_vehicles():
	"""Find all vehicles in the scene"""
	# Look for common vehicle groups or nodes
	var vehicle_groups = ["player_vehicle", "ai_vehicle", "vehicle"]
	
	for group in vehicle_groups:
		var vehicles_in_group = get_tree().get_nodes_in_group(group)
		for vehicle in vehicles_in_group:
			if vehicle is Node3D and not vehicle in available_vehicles:
				available_vehicles.append(vehicle)
	
	# Also check for any RigidBody3D or VehicleBody3D nodes
	if available_vehicles.is_empty():
		var all_nodes = get_tree().root.get_children()
		find_vehicles_recursive(all_nodes)
	
	if available_vehicles.size() > 0:
		print("[Camera] Found %d vehicles to follow" % available_vehicles.size())
		for i in range(available_vehicles.size()):
			print("  [%d] %s" % [i + 1, available_vehicles[i].name])
	else:
		print("[Camera] WARNING: No vehicles found!")

func find_vehicles_recursive(nodes: Array):
	"""Recursively search for vehicle nodes"""
	for node in nodes:
		# Check if it's a vehicle-like node
		if node is RigidBody3D or node is VehicleBody3D or node is CharacterBody3D:
			# Check if it has a name that suggests it's a vehicle
			var node_name = node.name.to_lower()
			if "vehicle" in node_name or "car" in node_name or "sedan" in node_name or "npc" in node_name:
				if not node in available_vehicles:
					available_vehicles.append(node)
		
		# Recurse into children
		if node.get_child_count() > 0:
			find_vehicles_recursive(node.get_children())

func find_target():
	"""Find target by group name"""
	target = get_tree().get_first_node_in_group(target_group_name)
	
	if not target and available_vehicles.size() > 0:
		target = available_vehicles[0]
		current_vehicle_index = 0
	
	if target:
		print("[Camera] Auto-locked onto target: %s" % target.name)
	else:
		print("[Camera] WARNING: No target found in group '%s'!" % target_group_name)

func setup_cameras():
	"""Set up cameras from the exported array"""
	if cameras.is_empty():
		# Auto-detect cameras if none are exported
		for child in get_children():
			if child is Camera3D:
				cameras.append(child)
	
	if cameras.size() > 0:
		follow_camera = cameras[0]
		set_current_camera(0)
		print("[Camera] Found %d cameras" % cameras.size())
	else:
		print("[Camera] WARNING: No cameras found!")

func _physics_process(delta):
	if not follow_camera or not target:
		return
	
	# Only apply special follow logic if this is the follow camera (typically the last one)
	if is_follow_camera_active():
		update_follow_camera(delta)

func is_follow_camera_active() -> bool:
	"""Check if the current camera should use follow behavior"""
	# By default, assume the last camera is the follow camera
	return current_camera_index == cameras.size() - 1

func update_follow_camera(delta):
	"""Update the follow camera position and rotation"""
	# Calculate base target position with pan offset
	var base_target = target.global_position + pan_offset
	
	if orbit_active:
		# ORBIT LOCKED MODE - camera stays at last orbited position
		update_orbit_camera(base_target, delta)
	else:
		# STANDARD FOLLOW MODE - behind vehicle
		update_follow_camera_standard(base_target, delta)

func update_orbit_camera(base_target: Vector3, delta):
	"""Update camera in orbit mode"""
	var target_pos = base_target
	
	# Calculate camera position based on orbit angles
	var offset = Vector3.ZERO
	offset.x = cos(orbit_angle_v) * sin(orbit_angle_h) * current_distance
	offset.z = cos(orbit_angle_v) * cos(orbit_angle_h) * current_distance
	offset.y = sin(orbit_angle_v) * current_distance + current_height
	
	follow_camera.global_position = follow_camera.global_position.lerp(
		target_pos + offset, 
		camera_smoothness * delta
	)
	follow_camera.look_at(target_pos, Vector3.UP)

func update_follow_camera_standard(base_target: Vector3, delta):
	"""Update camera in standard follow mode"""
	var target_pos = base_target - target.global_transform.basis.z * current_distance
	target_pos += Vector3.UP * current_height
	
	follow_camera.global_position = follow_camera.global_position.lerp(
		target_pos, 
		camera_smoothness * delta
	)
	follow_camera.look_at(base_target, Vector3.UP)

func _input(event):
	# Camera switching
	if event is InputEventKey and event.pressed:
		handle_camera_switching(event)
		handle_vehicle_switching(event)
		
		# RESET CAMERA - Press R to reset to behind vehicle
		if event.keycode == KEY_R and is_follow_camera_active():
			reset_camera()
	
	# Only allow orbit/pan on follow camera
	if not is_follow_camera_active():
		return
	
	# Handle mouse input for follow camera
	handle_mouse_input(event)

func handle_camera_switching(event: InputEventKey):
	"""Handle camera switching via number keys 1-8"""
	var key_map = {
		KEY_1: 0, KEY_2: 1, KEY_3: 2, KEY_4: 3,
		KEY_5: 4, KEY_6: 5, KEY_7: 6, KEY_8: 7
	}
	
	if event.keycode in key_map:
		var idx = key_map[event.keycode]
		if idx < cameras.size():
			set_current_camera(idx)

func handle_vehicle_switching(event: InputEventKey):
	"""Handle vehicle switching via F1-F4 keys"""
	if available_vehicles.is_empty():
		return
	
	var vehicle_key_map = {
		KEY_F1: 0, KEY_F2: 1, KEY_F3: 2, KEY_F4: 3
	}
	
	if event.keycode in vehicle_key_map:
		var idx = vehicle_key_map[event.keycode]
		if idx < available_vehicles.size():
			set_target(available_vehicles[idx])
			current_vehicle_index = idx
			reset_camera()  # Reset camera when switching vehicles

func handle_mouse_input(event):
	"""Handle mouse input for the follow camera"""
	if event is InputEventMouseButton:
		handle_mouse_button(event)
	
	# Mouse movement for orbit
	if orbit_mode and event is InputEventMouseMotion:
		handle_orbit_mouse_motion(event)
	
	# Mouse movement for pan
	if pan_mode and event is InputEventMouseMotion:
		handle_pan_mouse_motion(event)

func handle_mouse_button(event: InputEventMouseButton):
	"""Handle mouse button events"""
	match event.button_index:
		MOUSE_BUTTON_RIGHT:
			handle_right_click(event)
		MOUSE_BUTTON_LEFT:
			handle_left_click(event)
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			handle_mouse_wheel(event)

func handle_right_click(event: InputEventMouseButton):
	"""Handle right mouse button for orbit"""
	if event.pressed:
		orbit_mode = true
		orbit_active = true  # Lock orbit position
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		print("[Camera] ORBIT MODE - Move mouse to rotate, release to lock position")
	else:
		orbit_mode = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		print("[Camera] ORBIT LOCKED - Press R to reset behind vehicle")

func handle_left_click(event: InputEventMouseButton):
	"""Handle left mouse button for pan"""
	if event.pressed and Input.is_key_pressed(KEY_SHIFT):
		pan_mode = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		print("[Camera] PAN MODE - Move mouse to pan camera view")
	elif not event.pressed and pan_mode:
		pan_mode = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		print("[Camera] Pan offset: %.1f, %.1f, %.1f" % [pan_offset.x, pan_offset.y, pan_offset.z])

func handle_mouse_wheel(event: InputEventMouseButton):
	"""Handle mouse wheel for zoom"""
	if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		current_distance = clamp(current_distance - zoom_speed, min_distance, max_distance)
		print("[Camera] Zoom: %.1f" % current_distance)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		current_distance = clamp(current_distance + zoom_speed, min_distance, max_distance)
		print("[Camera] Zoom: %.1f" % current_distance)

func handle_orbit_mouse_motion(event: InputEventMouseMotion):
	"""Handle mouse motion for orbit"""
	orbit_angle_h -= event.relative.x * orbit_sensitivity
	orbit_angle_v -= event.relative.y * orbit_sensitivity
	
	# Clamp vertical angle to prevent camera flipping
	orbit_angle_v = clamp(orbit_angle_v, -PI/2 + 0.1, PI/2 - 0.1)

func handle_pan_mouse_motion(event: InputEventMouseMotion):
	"""Handle mouse motion for pan"""
	# Get camera's right and up vectors
	var cam_right = follow_camera.global_transform.basis.x
	var cam_up = follow_camera.global_transform.basis.y
	
	# Pan along camera's local axes
	pan_offset -= cam_right * event.relative.x * pan_sensitivity
	pan_offset += cam_up * event.relative.y * pan_sensitivity

func reset_camera():
	"""Reset camera to default behind-vehicle position"""
	orbit_active = false
	orbit_angle_h = 0.0
	orbit_angle_v = 0.0
	current_distance = camera_distance
	current_height = camera_height
	pan_offset = Vector3.ZERO  # Also reset pan
	print("[Camera] RESET - Back to follow mode")

func set_current_camera(idx: int):
	if idx < 0 or idx >= cameras.size():
		return
	
	# Exit orbit mode when switching cameras
	if orbit_mode:
		orbit_mode = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Reset orbit when switching away from follow camera
	if is_follow_camera_active() and idx != current_camera_index:
		reset_camera()
	
	for i in range(cameras.size()):
		cameras[i].current = (i == idx)
	
	follow_camera = cameras[idx]
	current_camera_index = idx
	print("[Camera] Switched to Camera%d" % (idx + 1))

func set_target(new_target: Node3D):
	"""Set a new target to follow"""
	target = new_target
	print("[Camera] Target changed to: %s" % target.name)

func set_target_by_group(group_name: String):
	"""Set target by group name"""
	target_group_name = group_name
	find_target()

func cycle_target():
	"""Cycle to the next available vehicle"""
	if available_vehicles.size() <= 1:
		return
	
	current_vehicle_index = (current_vehicle_index + 1) % available_vehicles.size()
	set_target(available_vehicles[current_vehicle_index])
	reset_camera()

func add_camera(camera: Camera3D):
	"""Add a camera to the controller"""
	if not camera in cameras:
		cameras.append(camera)
		print("[Camera] Added camera: %s" % camera.name)

func remove_camera(camera: Camera3D):
	"""Remove a camera from the controller"""
	if camera in cameras:
		var idx = cameras.find(camera)
		cameras.erase(camera)
		
		# If we removed the current camera, switch to first available
		if idx == current_camera_index and cameras.size() > 0:
			set_current_camera(0)
		
		print("[Camera] Removed camera: %s" % camera.name)

func _notification(what):
	# Release mouse when exiting game
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
