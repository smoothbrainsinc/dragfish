extends CanvasLayer

## Vehicle Dashboard - Godot-built UI (no script-generated nodes)

@export var show_detailed := false  # Toggle in Inspector

# We'll still keep these exports but they might not work
@export var speed_label: Label
@export var rpm_label: Label
@export var traction_label: Label
@export var detailed_panel: PanelContainer
@export var gforce_label: Label
@export var inputs_label: Label
@export var wheel1_label: Label
@export var wheel2_label: Label
@export var wheel3_label: Label
@export var wheel4_label: Label

# Vehicle reference
var vehicle: VehicleBody3D
var previous_velocity := Vector3.ZERO
var current_g := Vector3.ZERO

# Collect wheel labels
var wheel_labels = []

func _ready():
	# Get parent vehicle
	vehicle = get_parent() as VehicleBody3D
	if not vehicle:
		push_error("VehicleDashboard must be child of VehicleBody3D!")
		queue_free()
		return

	
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	if not vehicle.get_meta("is_player", false):
		hide()
		set_process(false)
		set_physics_process(false)
		return

	# Wait one frame for the scene to fully load  <-- this await is now after the group check
	find_ui_elements()
	
	# Collect wheel labels
	wheel_labels = [wheel1_label, wheel2_label, wheel3_label, wheel4_label]
	
	# Verify we found everything
	var all_found = true
	for i in range(wheel_labels.size()):
		if not wheel_labels[i]:
			print("WARNING: Wheel label ", i+1, " not found!")
			all_found = false
	
	if all_found:
		print("[Dashboard] All UI elements found successfully!")
	
	# Set initial visibility
	if detailed_panel:
		detailed_panel.visible = show_detailed
	
	print("[Dashboard] UI ready for: %s" % vehicle.name)

func find_ui_elements():
	# Find all labels and panels by their names in the scene
	speed_label = find_child("SpeedLabel", true, false)
	rpm_label = find_child("RPMLabel", true, false)
	traction_label = find_child("TractionLabel", true, false)
	detailed_panel = find_child("DetailedPanel", true, false)
	gforce_label = find_child("GForceLabel", true, false)
	inputs_label = find_child("InputsLabel", true, false)
	wheel1_label = find_child("Wheel1Label", true, false)
	wheel2_label = find_child("Wheel2Label", true, false)
	wheel3_label = find_child("Wheel3Label", true, false)
	wheel4_label = find_child("Wheel4Label", true, false)
	

func _input(event):
	# Toggle detailed view with F3
	if event.is_action_pressed("ui_home"):
		show_detailed = not show_detailed
		if detailed_panel:
			detailed_panel.visible = show_detailed

func _physics_process(delta: float):
	if not vehicle:
		return
		
	# Calculate G-forces
	if delta > 0.001:
		var accel = (vehicle.linear_velocity - previous_velocity) / delta
		current_g = accel / 9.81
		previous_velocity = vehicle.linear_velocity

func _process(_delta: float):
	if not vehicle:
		return
		
	update_basic_stats()
	
	if show_detailed:
		
		update_detailed_stats()

func update_basic_stats():
	if not speed_label or not rpm_label or not traction_label:
		# Try to find them again if they're missing
		find_ui_elements()
		if not speed_label or not rpm_label or not traction_label:
			return
	
	# Speed
	var speed_kph = vehicle.linear_velocity.length() * 3.6
	var speed_mph = speed_kph * 0.621371
	speed_label.text = "Speed: %.1f mph" % speed_mph
	
	# RPM (approximate from wheel speed)
	var wheels = get_wheels()
	if wheels.size() > 0:
		var avg_rpm = 0.0
		for wheel in wheels:
			avg_rpm += abs(wheel.get_rpm())
		avg_rpm /= wheels.size()
		rpm_label.text = "RPM: %.0f" % avg_rpm
	
	# Traction (simplified)
	var any_spinning = false
	for wheel in wheels:
		if abs(wheel.get_rpm()) > 100 and vehicle.linear_velocity.length() < 5:
			any_spinning = true
			break
	
	if any_spinning:
		traction_label.text = "TC: ACTIVE"
		traction_label.add_theme_color_override("font_color", Color.RED)
	else:
		traction_label.text = "TC: Ready"
		traction_label.add_theme_color_override("font_color", Color.GREEN)

func update_detailed_stats():
	if not gforce_label or not inputs_label:
		print("Missing gforce or inputs label")
		return
	
	
	# G-Forces
	var forward = -vehicle.global_transform.basis.z.normalized()
	var right = vehicle.global_transform.basis.x.normalized()
	var long_g = current_g.dot(forward)
	var lat_g = current_g.dot(right)
	
	gforce_label.text = "G-Force: Lng %.2f | Lat %.2f" % [long_g, lat_g]
	
	# Refresh wheel labels array every time to ensure we have them
	var current_wheel_labels = [wheel1_label, wheel2_label, wheel3_label, wheel4_label]
	
	
	# Get wheels
	var wheels = get_wheels()
	
	
	# Update each wheel label
	for i in range(min(wheels.size(), current_wheel_labels.size())):
		var label = current_wheel_labels[i]
		if not label:
			print("Wheel label ", i, " is null")
			continue
		
		var wheel = wheels[i]
		var rpm = wheel.get_rpm()
	
		
		if wheel.is_in_contact():
			var skid = wheel.get_skidinfo()
			var grip = skid * 100
			label.text = "W%d: %.0f RPM | %.0f%% grip" % [i+1, abs(rpm), grip]
			
			if grip > 80:
				label.add_theme_color_override("font_color", Color.ORANGE)
			elif grip > 50:
				label.add_theme_color_override("font_color", Color.YELLOW)
			else:
				label.add_theme_color_override("font_color", Color.GREEN)
		else:
			label.text = "W%d: AIRBORNE" % (i+1)
			label.add_theme_color_override("font_color", Color.RED)
	
	# Inputs
	var throttle_pct = Input.get_action_strength("throttle") * 100.0
	inputs_label.text = "Throttle: %.0f%% | Brake: %.0f N" % [throttle_pct, vehicle.brake]

func get_wheels() -> Array:
	var wheels = []
	if not vehicle:
		print("No vehicle in get_wheels!")
		return wheels
		
	for child in vehicle.get_children():
		if child is VehicleWheel3D:
			wheels.append(child)
	
	return wheels
	
