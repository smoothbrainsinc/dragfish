extends Resource
class_name TransmissionConfig
## Transmission configuration - gear ratios, shift timing, clutch

@export_group("Gear Ratios")
## Gear ratios (higher = more torque multiplication, lower top speed)
## Format: [1st, 2nd, 3rd, 4th, 5th, 6th...]
@export var gear_ratios: Array[float] = [3.50, 2.10, 1.50, 1.00]
## Final drive ratio (differential)
@export var final_drive: float = 4.10

@export_group("Shift Timing")
## Time to complete a shift (seconds)
@export var shift_time: float = 0.3
## RPM drop per gear shift as percentage (0.0-1.0)
## Example: 0.25 means RPM drops 25% when shifting up
@export_range(0.0, 0.5) var rpm_drop_percentage: float = 0.25

@export_group("Clutch")
@export var has_clutch: bool = true
## Clutch engagement time (seconds)
@export var clutch_engagement_time: float = 0.2
## Slip during engagement (0.0 = no slip, 1.0 = full slip)
@export_range(0.0, 0.5) var clutch_slip: float = 0.1

@export_group("Shift Penalties")
@export var enable_missed_shifts: bool = true
## Chance of missed shift if shifted too early/late (0.0-1.0)
@export_range(0.0, 1.0) var missed_shift_chance: float = 0.1
## RPM penalty for missed shift (subtracted from engine RPM)
@export var missed_shift_rpm_penalty: float = 2000.0
## Time penalty for missed shift (added to shift_time)
@export var missed_shift_time_penalty: float = 0.3

@export_group("Automatic Mode")
@export var auto_shift_enabled: bool = true
## RPM to shift at in auto mode (as percentage of redline)
@export_range(0.7, 1.0) var auto_shift_point: float = 0.92
## Don't downshift above this RPM percentage (prevents ping-ponging)
@export_range(0.3, 0.7) var auto_downshift_min: float = 0.4

## Get total gear ratio for a specific gear (0-indexed)
func get_total_ratio(gear_index: int) -> float:
	if gear_index < 0 or gear_index >= gear_ratios.size():
		return 0.0
	return gear_ratios[gear_index] * final_drive

## Calculate wheel RPM from engine RPM
func get_wheel_rpm(engine_rpm: float, gear_index: int) -> float:
	var ratio = get_total_ratio(gear_index)
	if ratio == 0.0:
		return 0.0
	return engine_rpm / ratio

## Calculate engine RPM from wheel speed
func get_engine_rpm_from_wheel_speed(wheel_speed_ms: float, wheel_radius: float, gear_index: int) -> float:
	if wheel_radius <= 0.0:
		return 0.0
	
	# wheel_speed (m/s) → wheel RPM
	# v = ωr, so ω = v/r (rad/s)
	# RPM = (rad/s) × (60 / 2π)
	var wheel_rpm = (wheel_speed_ms / wheel_radius) * (60.0 / TAU)
	return wheel_rpm * get_total_ratio(gear_index)

## Calculate vehicle speed from engine RPM
func get_vehicle_speed(engine_rpm: float, gear_index: int, wheel_radius: float) -> float:
	var wheel_rpm = get_wheel_rpm(engine_rpm, gear_index)
	# Convert wheel RPM to linear speed
	# v = ωr where ω is in rad/s
	var wheel_angular_velocity = wheel_rpm * TAU / 60.0  # Convert to rad/s
	return wheel_angular_velocity * wheel_radius  # m/s

## Calculate RPM after shifting up
func calculate_rpm_after_upshift(current_rpm: float, from_gear: int, to_gear: int) -> float:
	if from_gear < 0 or to_gear < 0 or from_gear >= gear_ratios.size() or to_gear >= gear_ratios.size():
		return current_rpm
	
	# RPM changes proportionally to gear ratio change
	var old_ratio = get_total_ratio(from_gear)
	var new_ratio = get_total_ratio(to_gear)
	
	if new_ratio == 0.0:
		return current_rpm
	
	return current_rpm * (new_ratio / old_ratio)

## Calculate RPM after shifting down
func calculate_rpm_after_downshift(current_rpm: float, from_gear: int, to_gear: int) -> float:
	return calculate_rpm_after_upshift(current_rpm, from_gear, to_gear)

## Get optimal shift point based on engine config
func get_optimal_shift_rpm(engine_config: EngineConfig, current_gear_index: int) -> float:
	if current_gear_index >= gear_ratios.size() - 1:
		return engine_config.redline_rpm  # Last gear, stay in it
	
	# Find RPM where power in next gear equals power in current gear
	var peak_power_rpm = engine_config.get_peak_power_rpm()
	
	# Calculate what RPM we need to be at NOW so that after shift, we're near peak power
	var rpm_after_shift_at_peak = peak_power_rpm
	var optimal_shift_rpm = rpm_after_shift_at_peak / (get_total_ratio(current_gear_index + 1) / get_total_ratio(current_gear_index))
	
	# Clamp to reasonable range
	return clamp(optimal_shift_rpm, peak_power_rpm * 1.1, engine_config.redline_rpm * 0.95)

## Check if upshift is safe (won't bog down engine)
func is_upshift_safe(current_rpm: float, current_gear_index: int, engine_config: EngineConfig) -> bool:
	if current_gear_index >= gear_ratios.size() - 1:
		return false  # Already in top gear
	
	# Calculate RPM after shift
	var rpm_after = calculate_rpm_after_upshift(current_rpm, current_gear_index, current_gear_index + 1)
	
	# Make sure we won't drop below useful RPM range
	return rpm_after >= engine_config.idle_rpm + 1000.0

## Check if downshift is safe (won't over-rev)
func is_downshift_safe(current_rpm: float, current_gear_index: int, engine_config: EngineConfig) -> bool:
	if current_gear_index <= 0:
		return false  # Already in first gear
	
	# Calculate RPM after shift
	var rpm_after = calculate_rpm_after_downshift(current_rpm, current_gear_index, current_gear_index - 1)
	
	# Make sure we won't exceed rev limiter
	return rpm_after <= engine_config.rev_limiter_rpm

## Calculate chance of missed shift based on timing
func calculate_missed_shift_chance(current_rpm: float, engine_config: EngineConfig, is_upshift: bool) -> float:
	if not enable_missed_shifts:
		return 0.0
	
	var base_chance = missed_shift_chance
	
	if is_upshift:
		# Higher chance if shifting too low in RPM band
		if current_rpm < engine_config.idle_rpm + 1000.0:
			return base_chance * 3.0  # Very bad shift
		elif current_rpm < engine_config.get_peak_power_rpm() * 0.5:
			return base_chance * 2.0  # Bad shift
	else:
		# Downshift - higher chance if it would over-rev
		# (This should be checked with is_downshift_safe first)
		if current_rpm > engine_config.redline_rpm:
			return base_chance * 2.0
	
	return base_chance

## Get number of forward gears
func get_gear_count() -> int:
	return gear_ratios.size()

## Get gear ratio difference between two gears
func get_ratio_difference(from_gear_index: int, to_gear_index: int) -> float:
	var from_ratio = get_total_ratio(from_gear_index)
	var to_ratio = get_total_ratio(to_gear_index)
	if to_ratio == 0.0:
		return 1.0
	return from_ratio / to_ratio

## Debug info
func get_debug_info() -> String:
	return "%d-speed, Final: %.2f:1" % [get_gear_count(), final_drive]
