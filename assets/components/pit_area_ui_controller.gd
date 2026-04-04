extends Node

@onready var preview = get_parent().get_node_or_null("PropertyLabels/HBoxContainer/Panel/CarImage/SubViewport")
@onready var race_button = $"../PropertyLabels/HBoxContainer/Panel/ColorRect/GridContainer/Start"
@onready var select_button = $"../PropertyLabels/HBoxContainer/Panel/ColorRect/GridContainer/Select"
@onready var reset_button = $"../PropertyLabels/HBoxContainer/Panel/ColorRect/GridContainer/Reset"
@onready var save_button = $"../PropertyLabels/HBoxContainer/Panel/ColorRect/GridContainer/Save"

var current_vehicle: VehicleBody3D = null
var wheels: Array[VehicleWheel3D] = []
var original_values: Dictionary = {}
var current_modifications: Dictionary = {}

func _ready():
	# Connect buttons
	race_button.pressed.connect(_on_race_pressed)
	select_button.pressed.connect(_on_select_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	save_button.pressed.connect(_on_save_pressed)
	
	# Load vehicle
	if GameManager.player_car_data and not GameManager.player_car_data.is_empty():
		load_selected_vehicle()
	else:
		push_error("No vehicle data in GameManager! Make sure car_selection_screen sets player_car_data.")

func load_selected_vehicle():
	# Check if we have player_car_data
	if not GameManager.player_car_data or GameManager.player_car_data.is_empty():
		push_error("No vehicle data in GameManager!")
		return
	
	var scene_path = GameManager.player_car_data.get("scene_path", "")
	if scene_path.is_empty():
		push_error("No scene path in player_car_data!")
		return
	
	var vehicle_scene = load(scene_path)
	
	if not vehicle_scene:
		push_error("Failed to load: " + scene_path)
		return
	
	current_vehicle = vehicle_scene.instantiate()
	
	if current_vehicle is VehicleBody3D:
		current_vehicle.freeze = true
	
	disable_scripts(current_vehicle)
	
	# Add to CarImage SubViewport
	var subviewport = get_parent().get_node_or_null("PropertyLabels/HBoxContainer/Panel/CarImage/SubViewport")
	if subviewport:
		subviewport.add_child(current_vehicle)
		current_vehicle.position = Vector3.ZERO
		current_vehicle.rotation_degrees.y = 30
		print("Vehicle added to SubViewport")
	else:
		push_error("SubViewport not found in CarImage!")
		return
	
	wheels = find_wheels(current_vehicle)
	
	if wheels.size() >= 4:
		save_original_values()
		load_saved_modifications()
		load_values_to_ui()
		connect_spinbox_signals()
		print("Loaded: " + scene_path + " with " + str(wheels.size()) + " wheels")
	else:
		push_error("Need 4 wheels! Found: " + str(wheels.size()))

func disable_scripts(node: Node):
	if node.has_method("set_process"):
		node.set_process(false)
		node.set_physics_process(false)
		node.set_process_input(false)
	
	if node.get_script():
		var path = node.get_script().resource_path
		if "control" in path.to_lower() or "input" in path.to_lower():
			node.set_script(null)
	
	for child in node.get_children():
		disable_scripts(child)

func find_wheels(node: Node) -> Array[VehicleWheel3D]:
	var found: Array[VehicleWheel3D] = []
	if node is VehicleWheel3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(find_wheels(child))
	return found

func save_original_values():
	for i in range(wheels.size()):
		var w = wheels[i]
		original_values[i] = {
			"engine_force": w.engine_force,
			"brake": w.brake,
			"steering": w.steering,
			"wheel_roll_influence": w.wheel_roll_influence,
			"wheel_radius": w.wheel_radius,
			"wheel_rest_length": w.wheel_rest_length,
			"wheel_friction_slip": w.wheel_friction_slip,
			"suspension_travel": w.suspension_travel,
			"suspension_stiffness": w.suspension_stiffness,
			"suspension_max_force": w.suspension_max_force,
			"damping_compression": w.damping_compression,
			"damping_relaxation": w.damping_relaxation
		}

func load_saved_modifications():
	"""Load previously saved modifications from file or GameManager"""
	if not GameManager.player_car_data.has("name"):
		print("No vehicle name available")
		current_modifications = {}
		return
	
	var vehicle_name = GameManager.player_car_data["name"]
	
	# First check if modifications exist in GameManager (for immediate use)
	if GameManager.has("wheel_modifications") and GameManager.wheel_modifications.has(vehicle_name):
		current_modifications = GameManager.wheel_modifications[vehicle_name]
		
		# Apply saved modifications to wheels
		for wheel_idx_str in current_modifications:
			var wheel_idx = int(wheel_idx_str)
			if wheel_idx < wheels.size():
				for property in current_modifications[wheel_idx_str]:
					wheels[wheel_idx].set(property, current_modifications[wheel_idx_str][property])
		
		print("Loaded modifications from GameManager for " + vehicle_name)
		return
	
	# If not in GameManager, try loading from file
	var save_path = "user://wheel_mods_%s.json" % vehicle_name
	
	if FileAccess.file_exists(save_path):
		var file = FileAccess.open(save_path, FileAccess.READ)
		if file:
			var json = JSON.new()
			var parse_result = json.parse(file.get_as_text())
			file.close()
			
			if parse_result == OK and json.data is Dictionary:
				current_modifications = json.data
				
				# Apply saved modifications to wheels
				for wheel_idx_str in current_modifications:
					var wheel_idx = int(wheel_idx_str)
					if wheel_idx < wheels.size():
						for property in current_modifications[wheel_idx_str]:
							wheels[wheel_idx].set(property, current_modifications[wheel_idx_str][property])
				
				print("Loaded saved modifications from file for " + vehicle_name)
				return
	
	# No saved mods, start fresh
	current_modifications = {}
	print("No saved modifications found for " + vehicle_name)

func load_values_to_ui():
	var base = $"../PropertyLabels/HBoxContainer/PropertyLabels/ColorRect/3dMotion/MotionSection"
	
	# Engine Force row
	set_spinbox_row(base.get_node("EngineForceContainer"), "engine_force")
	# Brake row
	set_spinbox_row(base.get_node("BrakeContainer"), "brake")
	# Steering row
	set_spinbox_row(base.get_node("SteeringContainer"), "steering")
	
	# Wheel section
	var wheel_section = base.get_node("Wheel/WheelSection")
	set_spinbox_row(wheel_section.get_node("RollContainer"), "wheel_roll_influence")
	set_spinbox_row(wheel_section.get_node("RadiusContainer"), "wheel_radius")
	set_spinbox_row(wheel_section.get_node("RestContainer"), "wheel_rest_length")
	set_spinbox_row(wheel_section.get_node("FrictionContainer"), "wheel_friction_slip")
	
	# Suspension section
	var susp = wheel_section.get_node("Suspension/SuspensionSection")
	set_spinbox_row(susp.get_node("TravelContainer"), "suspension_travel")
	set_spinbox_row(susp.get_node("StifnessContainer"), "suspension_stiffness")
	set_spinbox_row(susp.get_node("MaxForceContainer"), "suspension_max_force")
	
	# Damping section
	var damp = susp.get_node("Damping/DampingSection")
	set_spinbox_row(damp.get_node("CompressionContainer"), "damping_compression")
	set_spinbox_row(damp.get_node("RelaxationContainer"), "damping_relaxation")

func set_spinbox_row(container: HBoxContainer, property: String):
	var boxes = [
		container.get_node_or_null("SpinBox4"),  # FL
		container.get_node_or_null("SpinBox3"),  # FR
		container.get_node_or_null("SpinBox"),   # RL
		container.get_node_or_null("SpinBox2")   # RR
	]
	
	for i in range(min(4, wheels.size())):
		if boxes[i]:
			boxes[i].set_value_no_signal(wheels[i].get(property))

func connect_spinbox_signals():
	var base = $"../PropertyLabels/HBoxContainer/PropertyLabels/ColorRect/3dMotion/MotionSection"
	
	connect_row(base.get_node("EngineForceContainer"), "engine_force")
	connect_row(base.get_node("BrakeContainer"), "brake")
	connect_row(base.get_node("SteeringContainer"), "steering")
	
	var wheel_section = base.get_node("Wheel/WheelSection")
	connect_row(wheel_section.get_node("RollContainer"), "wheel_roll_influence")
	connect_row(wheel_section.get_node("RadiusContainer"), "wheel_radius")
	connect_row(wheel_section.get_node("RestContainer"), "wheel_rest_length")
	connect_row(wheel_section.get_node("FrictionContainer"), "wheel_friction_slip")
	
	var susp = wheel_section.get_node("Suspension/SuspensionSection")
	connect_row(susp.get_node("TravelContainer"), "suspension_travel")
	connect_row(susp.get_node("StifnessContainer"), "suspension_stiffness")
	connect_row(susp.get_node("MaxForceContainer"), "suspension_max_force")
	
	var damp = susp.get_node("Damping/DampingSection")
	connect_row(damp.get_node("CompressionContainer"), "damping_compression")
	connect_row(damp.get_node("RelaxationContainer"), "damping_relaxation")

func connect_row(container: HBoxContainer, property: String):
	var boxes = [
		container.get_node_or_null("SpinBox4"),
		container.get_node_or_null("SpinBox3"),
		container.get_node_or_null("SpinBox"),
		container.get_node_or_null("SpinBox2")
	]
	
	for i in range(min(4, boxes.size())):
		if boxes[i]:
			boxes[i].value_changed.connect(func(val): on_value_changed(i, property, val))

func on_value_changed(wheel_idx: int, property: String, value: float):
	if wheel_idx < wheels.size():
		wheels[wheel_idx].set(property, value)
		
		# Track modification
		if not current_modifications.has(str(wheel_idx)):
			current_modifications[str(wheel_idx)] = {}
		current_modifications[str(wheel_idx)][property] = value
		
		print("Wheel %d: %s = %.2f" % [wheel_idx, property, value])

func _on_save_pressed():
	"""Save current modifications to file and GameManager"""
	if not GameManager.player_car_data.has("name"):
		push_error("No vehicle name in player_car_data!")
		return
	
	var vehicle_name = GameManager.player_car_data["name"]
	
	# Save to file for persistence across sessions
	var save_path = "user://wheel_mods_%s.json" % vehicle_name
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(current_modifications, "\t"))
		file.close()
		print("✓ Saved modifications to: " + save_path)
	else:
		push_error("Failed to save modifications!")
	
	# Also save to GameManager for immediate use in race
	if not "wheel_modifications" in GameManager:
		GameManager.wheel_modifications = {}
	GameManager.wheel_modifications[vehicle_name] = current_modifications.duplicate()
	
	print("✓ Modifications ready for racing!")

func _on_reset_pressed():
	for i in range(wheels.size()):
		if original_values.has(i):
			for prop in original_values[i]:
				wheels[i].set(prop, original_values[i][prop])
	
	# Clear current modifications
	current_modifications = {}
	
	load_values_to_ui()
	print("Reset to original values")

func _on_race_pressed():
	# Ensure modifications are saved to GameManager before racing
	if GameManager.player_car_data.has("name"):
		var vehicle_name = GameManager.player_car_data["name"]
		if not "wheel_modifications" in GameManager:
			GameManager.wheel_modifications = {}
		GameManager.wheel_modifications[vehicle_name] = current_modifications.duplicate()
	
	get_tree().change_scene_to_file("res://scenes/raceway.tscn")

func _on_select_pressed():
	get_tree().change_scene_to_file("res://scenes/car_selection_screen.tscn")
