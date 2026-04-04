extends Resource
class_name EngineConfig
## Engine configuration - torque curves, RPM limits, characteristics

@export_group("RPM Range")
@export var idle_rpm: float = 1000.0
@export var redline_rpm: float = 7000.0
@export var rev_limiter_rpm: float = 7500.0  ## Hard cut (engine damage above this)

@export_group("Torque Curve")
## Torque curve as RPM:Torque pairs (in Newton-meters)
## The engine will interpolate between these points
@export var torque_curve: Dictionary = {
	1000.0: 200.0,
	2000.0: 300.0,
	3000.0: 400.0,
	4500.0: 500.0,  # Peak torque
	6000.0: 480.0,
	7000.0: 420.0,
	7500.0: 350.0
}

@export_group("Characteristics")
@export var engine_inertia: float = 0.3  ## How quickly engine revs up/down
@export var engine_friction: float = 0.05  ## Internal resistance
@export var rev_limiter_enabled: bool = true

@export_group("Launch Control")
@export var has_launch_control: bool = false
@export var launch_control_rpm: float = 3500.0  ## Target RPM for launch

## Get torque at specific RPM (interpolated from curve)
func get_torque_at_rpm(rpm: float) -> float:
	if torque_curve.is_empty():
		push_error("[EngineConfig] Torque curve is empty!")
		return 0.0
	
	# Rev limiter: no torque at or above redline
	if rpm >= redline_rpm:
		return 0.0
	
	# Clamp RPM to valid range
	rpm = clamp(rpm, idle_rpm, redline_rpm)
	
	# Get sorted RPM points
	var rpm_points = torque_curve.keys()
	rpm_points.sort()
	
	# Find the two points to interpolate between
	for i in range(rpm_points.size() - 1):
		if rpm >= rpm_points[i] and rpm <= rpm_points[i + 1]:
			var lower_rpm = rpm_points[i]
			var upper_rpm = rpm_points[i + 1]
			var lower_torque = torque_curve[lower_rpm]
			var upper_torque = torque_curve[upper_rpm]
			var t = (rpm - lower_rpm) / (upper_rpm - lower_rpm)
			return lerp(lower_torque, upper_torque, t)
	
	# If we're past all points, return the last one
	return torque_curve[rpm_points[-1]]
## Get power (in watts) at specific RPM
## Power = Torque × Angular Velocity
## P (watts) = T (Nm) × (RPM × 2π / 60)
func get_power_at_rpm(rpm: float) -> float:
	var torque = get_torque_at_rpm(rpm)
	var angular_velocity = rpm * TAU / 60.0  # Convert RPM to rad/s
	return torque * angular_velocity

## Get horsepower at specific RPM
func get_horsepower_at_rpm(rpm: float) -> float:
	var watts = get_power_at_rpm(rpm)
	return watts / 745.7  # Convert watts to HP

## Find the RPM where peak power occurs
func get_peak_power_rpm() -> float:
	var rpm_points = torque_curve.keys()
	rpm_points.sort()
	
	var peak_power = 0.0
	var peak_rpm = idle_rpm
	
	# Sample at torque curve points and intermediate values
	var sample_step = 50  # More granular than 100
	for rpm in range(int(idle_rpm), int(redline_rpm) + 1, sample_step):
		var power = get_power_at_rpm(rpm)
		if power > peak_power:
			peak_power = power
			peak_rpm = rpm
	
	return peak_rpm

## Get peak horsepower
func get_peak_horsepower() -> int:
	var peak_rpm = get_peak_power_rpm()
	return int(get_horsepower_at_rpm(peak_rpm))

## Find peak torque RPM
func get_peak_torque_rpm() -> float:
	var peak_torque = 0.0
	var peak_rpm = idle_rpm
	
	for rpm in torque_curve.keys():
		var torque = torque_curve[rpm]
		if torque > peak_torque:
			peak_torque = torque
			peak_rpm = rpm
	
	return peak_rpm

## Get peak torque value
func get_peak_torque() -> float:
	var peak_rpm = get_peak_torque_rpm()
	return torque_curve[peak_rpm]

## Check if RPM is in safe range
func is_rpm_safe(rpm: float) -> bool:
	return rpm <= redline_rpm

## Check if RPM should trigger rev limiter
func should_cut_ignition(rpm: float) -> bool:
	if not rev_limiter_enabled:
		return false
	return rpm >= rev_limiter_rpm
