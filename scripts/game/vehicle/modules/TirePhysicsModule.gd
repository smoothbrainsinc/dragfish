extends Node3D
class_name TirePhysicsModule

# --- Tire configs ---
var front_tires_config: TireConfig
var rear_tires_config: TireConfig

# --- Cached values ---
var front_base_friction: float = 1.0
var rear_base_friction: float = 1.0
var optimal_slip_ratio: float = 0.15

# --- Vehicle reference ---
var vehicle: VehicleBody3D


func setup(front_config: TireConfig, rear_config: TireConfig) -> void:
	assert(front_config != null, "Front TireConfig is null")
	assert(rear_config != null, "Rear TireConfig is null")

	front_tires_config = front_config
	rear_tires_config = rear_config

	# Cache effective friction values (includes compound multiplier)
	front_base_friction = front_config.get_effective_friction()
	rear_base_friction = rear_config.get_effective_friction()

	# Use the worse (larger) optimal slip so behavior is stable
	optimal_slip_ratio = max(
		front_config.optimal_slip_ratio,
		rear_config.optimal_slip_ratio
	)

	print("[TirePhysics] Setup:",
		"Front μ=%.2f" % front_base_friction,
		"Rear μ=%.2f" % rear_base_friction,
		"Slip=%.2f" % optimal_slip_ratio
	)


# ---------------------------------------------------------
# Visual wheel rotation only (VehicleWheel3D handles forces)
# ---------------------------------------------------------
func update_wheel_slip(wheels: Array[VehicleWheel3D], forward_speed: float) -> void:
	var delta := get_physics_process_delta_time()
	if delta <= 0.0:
		return

	for w in wheels:
		var circumference := TAU * w.wheel_radius
		if circumference <= 0.0:
			continue

		var rotation_deg := (forward_speed / circumference) * 360.0 * delta
		w.rotation_degrees.x += rotation_deg


# ---------------------------------------------------------
# Optional longitudinal damping (VERY light)
# ---------------------------------------------------------
func apply_wheel_friction(wheels: Array[VehicleWheel3D]) -> void:
	if wheels.is_empty():
		return

	if vehicle == null:
		vehicle = wheels[0].get_parent() as VehicleBody3D
		if vehicle == null:
			return

	# Convert velocity to local space
	var local_vel := vehicle.global_transform.basis.inverse() * vehicle.linear_velocity
	var forward_speed := -local_vel.z

	# Very small rolling resistance (prevents infinite coast)
	var rolling_resistance := 0.015
	var resist_force := -forward_speed * rolling_resistance * vehicle.mass

	var force_vec := vehicle.global_transform.basis.z * resist_force
	vehicle.apply_central_force(force_vec)
