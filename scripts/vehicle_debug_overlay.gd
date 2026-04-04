extends Node3D
## ENHANCED PHYSICS DEBUG - Shows traction control, G-forces, and more

@export var enabled := true
@export var show_wheel_forces := true
@export var show_g_forces := true
@export var show_traction_control := true
@export var label_offset := Vector3(3, 4, 0)

var vehicle: VehicleBody3D
var label_3d: Label3D
var wheel_force_arrows: Array[MeshInstance3D] = []
var center_of_mass_marker: MeshInstance3D

# G-force tracking
var previous_velocity := Vector3.ZERO
var current_g_force := Vector3.ZERO

func _ready():
	await get_tree().process_frame
	
	vehicle = get_parent() as VehicleBody3D
	if not vehicle:
		push_error("VehicleDebugOverlay must be child of VehicleBody3D!")
		queue_free()
		return
	
	# Main data label
	label_3d = Label3D.new()
	label_3d.pixel_size = 0.007
	label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label_3d.position = label_offset
	label_3d.modulate = Color.YELLOW
	label_3d.outline_size = 4
	label_3d.outline_modulate = Color.BLACK
	add_child(label_3d)
	
	# Center of mass marker
	center_of_mass_marker = create_sphere(Color.RED, 0.15)
	add_child(center_of_mass_marker)
	
	# Create force arrows for each wheel
	if show_wheel_forces:
		for i in range(vehicle.get_child_count()):
			var wheel = vehicle.get_child(i) as VehicleWheel3D
			if wheel:
				var arrow = create_arrow(Color.CYAN)
				wheel.add_child(arrow)
				wheel_force_arrows.append(arrow)

func _physics_process(delta):
	if not enabled or not is_instance_valid(vehicle):
		return
	
	# Calculate G-forces
	if delta > 0:
		var acceleration = (vehicle.linear_velocity - previous_velocity) / delta
		current_g_force = acceleration / 9.81  # Convert to G's
		previous_velocity = vehicle.linear_velocity

func _process(_delta):
	if not enabled or not is_instance_valid(vehicle):
		return
	
	# Speed calculations
	var speed_kph = vehicle.linear_velocity.length() * 3.6
	var speed_mph = speed_kph * 0.621371
	var actual_velocity = vehicle.linear_velocity
	var actual_angular_vel = vehicle.angular_velocity
	
	# Build main display
	var text = ""
	text += "━━ ACTUAL PHYSICS DATA ━━\n"
	text += "SPEED: %.1f mph (%.1f kph)\n" % [speed_mph, speed_kph]
	text += "VEL: X:%.1f Y:%.1f Z:%.1f\n" % [actual_velocity.x, actual_velocity.y, actual_velocity.z]
	
	# G-Forces (NEW!)
	if show_g_forces:
		var longitudinal_g = current_g_force.z  # Forward/backward
		var lateral_g = current_g_force.x  # Left/right
		text += "G-FORCE: Long:%.2fG Lat:%.2fG\n" % [longitudinal_g, lateral_g]
		
		# Warning for high G's
		if abs(longitudinal_g) > 3.0:
			text += "⚠ HIGH ACCELERATION!\n"
	
	text += "ANG: X:%.2f Y:%.2f Z:%.2f\n" % [actual_angular_vel.x, actual_angular_vel.y, actual_angular_vel.z]
	text += "━━━━━━━━━━━━━━━━━━━━\n"
	
	# Traction Control Status (NEW!)
	if show_traction_control:
		if vehicle.has_method("get") and vehicle.get("traction_control_enabled") != null:
			text += "TRACTION CONTROL:\n"
			var tc_enabled = vehicle.get("traction_control_enabled")
			if tc_enabled:
				text += "  Status: "
				var tc_active = vehicle.get("traction_control_active")
				var is_launch = vehicle.get("is_launching")
				if tc_active:
					text += "⚠ ACTIVE (Cutting Power)\n"
				elif is_launch:
					text += "🚦 LAUNCH CONTROL\n"
				else:
					text += "✓ READY\n"
			else:
				text += "  Status: ❌ OFF\n"
			text += "━━━━━━━━━━━━━━━━━━━━\n"
	
	text += "INPUTS:\n"
	text += "  Engine: %.0fN" % vehicle.engine_force
	
	# Show power reduction (NEW!)
	var vehicle_engine_max = vehicle.get("max_engine_force")
	if vehicle_engine_max != null and vehicle.engine_force < vehicle_engine_max * 0.95:
		var power_percent = (vehicle.engine_force / vehicle_engine_max) * 100
		text += " (%.0f%%)" % power_percent
	
	text += " | Brake: %.0fN\n" % vehicle.brake
	text += "  Steering: %.2f\n" % vehicle.steering
	text += "━━━━━━━━━━━━━━━━━━━━\n"
	
	# Wheel analysis
	var wheel_idx = 0
	var total_grip = 0.0
	var grounded_wheels = 0
	var wheel_data_text = ""
	var max_slip = 0.0
	
	for i in range(vehicle.get_child_count()):
		var wheel = vehicle.get_child(i) as VehicleWheel3D
		if wheel:
			var contact = wheel.is_in_contact()
			var rpm = wheel.get_rpm()
			var skid = wheel.get_skidinfo()
			var slip = 1.0 - skid
			
			wheel_data_text += "W%d" % (wheel_idx + 1)
			
			# Show if wheel is driven
			if wheel.use_as_traction:
				wheel_data_text += "⚡"
			
			wheel_data_text += ": "
			
			if contact:
				grounded_wheels += 1
				total_grip += skid
				
				if slip > max_slip:
					max_slip = slip
				
				var contact_point = wheel.get_contact_point()
				var wheel_pos = wheel.global_position
				var suspension_compression = wheel_pos.distance_to(contact_point)
				
				wheel_data_text += "RPM:%.0f GRIP:%.0f%% " % [rpm, skid * 100]
				
				# Slip warning (NEW!)
				if slip > 0.15:  # More than 15% slip
					wheel_data_text += "⚠SLIP "
				
				wheel_data_text += "SUSP:%.2fm ✓\n" % suspension_compression
				
				# Visual force arrow with better color coding
				if wheel_idx < wheel_force_arrows.size():
					var arrow = wheel_force_arrows[wheel_idx]
					arrow.visible = true
					
					# Scale arrow based on slip
					var slip_amount = slip
					arrow.scale.y = 0.3 + (slip_amount * 3.0)
					
					# Color: Green (good grip) -> Yellow (mild slip) -> Red (bad slip)
					var mat = arrow.material_override as StandardMaterial3D
					if mat:
						var new_color: Color
						if slip < 0.10:
							new_color = Color.GREEN
						elif slip < 0.20:
							new_color = Color.YELLOW
						else:
							new_color = Color.RED
						
						mat.albedo_color = new_color
						mat.emission = new_color
			else:
				wheel_data_text += "AIRBORNE ✗\n"
				if wheel_idx < wheel_force_arrows.size():
					wheel_force_arrows[wheel_idx].visible = false
			
			wheel_idx += 1
	
	text += wheel_data_text
	text += "━━━━━━━━━━━━━━━━━━━━\n"
	
	if grounded_wheels > 0:
		var avg_grip = (total_grip / grounded_wheels) * 100
		text += "AVG GRIP: %.0f%%\n" % avg_grip
		
		# Enhanced warnings (NEW!)
		if avg_grip < 80:
			text += "⚠ WHEEL SLIP DETECTED\n"
		if max_slip > 0.30:
			text += "🔥 EXCESSIVE SLIP - LOSING TRACTION!\n"
		if avg_grip > 95:
			text += "✓ OPTIMAL GRIP\n"
	else:
		text += "⚠ NO GROUND CONTACT\n"
	
	text += "GROUNDED: %d/4 wheels\n" % grounded_wheels
	text += "MASS: %.0fkg\n" % vehicle.mass
	
	# Power-to-weight ratio (NEW!)
	var vehicle_max_force = vehicle.get("max_engine_force")
	if vehicle_max_force != null:
		var power_to_weight = vehicle_max_force / vehicle.mass
		text += "PWR/WT: %.1f N/kg\n" % power_to_weight
	
	# Aerodynamics info (NEW!)
	var drag_cd = vehicle.get("drag_coefficient")
	var downforce_cl = vehicle.get("downforce_coefficient")
	if drag_cd != null:
		text += "AERO: Cd=%.2f" % drag_cd
		if downforce_cl != null:
			text += " Cl=%.2f" % downforce_cl
		text += "\n"
	
	label_3d.text = text
	
	# Update center of mass marker
	if vehicle.center_of_mass:
		center_of_mass_marker.position = vehicle.center_of_mass
		center_of_mass_marker.visible = true
	else:
		center_of_mass_marker.visible = false

func create_arrow(color: Color) -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()
	var shaft = CylinderMesh.new()
	shaft.height = 1.0
	shaft.top_radius = 0.08
	shaft.bottom_radius = 0.08
	
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy = 0.8
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	
	mesh_instance.mesh = shaft
	mesh_instance.material_override = material
	mesh_instance.position = Vector3(0, -0.5, 0)
	
	return mesh_instance

func create_sphere(color: Color, size: float) -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = size
	sphere.height = size * 2
	
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy = 1.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	
	mesh_instance.mesh = sphere
	mesh_instance.material_override = material
	
	return mesh_instance

func toggle_debug():
	enabled = !enabled
	visible = enabled

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_D:
		toggle_debug()
		print("[Debug] Physics Overlay: %s" % ("ON" if enabled else "OFF"))
