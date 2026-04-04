extends Node
class_name EngineModule
## Handles engine simulation - RPM, torque output, rev limiter

signal rpm_changed(rpm: float)
signal rev_limiter_activated

# Constants
const RPM_INERTIA_MULTIPLIER = 10.0
const RPM_FRICTION_MULTIPLIER = 100.0
const MOVEMENT_THRESHOLD = 2.0  # m/s

var config: EngineConfig
var current_rpm: float = 0.0
var target_rpm: float = 0.0
var is_rev_limited: bool = false
var wheel_radius: float = 0.35

func update(throttle: float, gear_ratio: float, vehicle_speed: float) -> void:
	apply_throttle(throttle, gear_ratio, vehicle_speed)

func setup(engine_config: EngineConfig, vehicle_wheel_radius: float = 0.35) -> void:
	config = engine_config
	wheel_radius = vehicle_wheel_radius
	current_rpm = config.idle_rpm
	target_rpm = config.idle_rpm
	print("[EngineModule] Setup: %d HP @ %.0f RPM, Wheel: %.2fm" % [
		config.get_peak_horsepower(),
		config.get_peak_power_rpm(),
		wheel_radius
	])
	print("[EngineModule] Redline: %.0f RPM | Rev Limiter: %.0f RPM" % [
		config.redline_rpm,
		config.rev_limiter_rpm
	])

func _ready() -> void:
	# VehicleController calls _physics_process manually, disable auto
	set_physics_process(false)

func start() -> void:
	if not config:
		push_error("[EngineModule] No config set!")
		return
	# Do NOT enable physics process here - VehicleController drives us manually
	set_physics_process(false)

func stop() -> void:
	set_physics_process(false)

func _physics_process(delta: float) -> void:
	if not config:
		return

	# Apply inertia (smooth RPM changes)
	current_rpm = lerp(current_rpm, target_rpm, config.engine_inertia * delta * RPM_INERTIA_MULTIPLIER)

	# Apply engine friction (RPM naturally drops toward idle)
	if target_rpm < current_rpm:
		var friction_force = config.engine_friction * (current_rpm - config.idle_rpm)
		current_rpm -= friction_force * delta * RPM_FRICTION_MULTIPLIER

	# Never go below idle RPM
	current_rpm = clamp(current_rpm, config.idle_rpm, config.rev_limiter_rpm + 500.0)

	# Rev limiter
	if current_rpm >= config.redline_rpm:
		if not is_rev_limited:
			is_rev_limited = true
			emit_signal("rev_limiter_activated")
			print("[EngineModule] REV LIMITER at %.0f RPM" % current_rpm)

		current_rpm = min(current_rpm, config.redline_rpm)
		target_rpm = config.redline_rpm - 500.0
	else:
		is_rev_limited = false

	emit_signal("rpm_changed", current_rpm)

func set_target_rpm(rpm: float) -> void:
	target_rpm = clamp(rpm, config.idle_rpm, config.rev_limiter_rpm + 500.0)

func get_current_torque() -> float:
	if not config:
		return 0.0
	if current_rpm >= config.redline_rpm:
		return 0.0
	return config.get_torque_at_rpm(current_rpm)

func get_current_power() -> float:
	if not config:
		return 0.0
	if current_rpm >= config.redline_rpm:
		return 0.0
	return config.get_power_at_rpm(current_rpm)

func get_current_horsepower() -> float:
	return get_current_power() / 745.7

func calculate_rpm_from_wheel_speed(wheel_speed: float, gear_ratio: float) -> float:
	var wheel_angular_velocity = wheel_speed / wheel_radius
	var wheel_rpm = wheel_angular_velocity * (60.0 / TAU)
	return wheel_rpm * gear_ratio

func apply_throttle(throttle: float, current_gear_ratio: float, vehicle_speed: float) -> void:
	if is_rev_limited:
		target_rpm = config.redline_rpm - 500.0
		return

	var is_moving = vehicle_speed > MOVEMENT_THRESHOLD

	if current_gear_ratio > 0.0 and is_moving:
		if throttle <= 0.0:
			target_rpm = config.idle_rpm
		else:
			var wheel_rpm = (vehicle_speed / wheel_radius) * (60.0 / TAU)
			var rpm_from_wheels = wheel_rpm * current_gear_ratio
			var headroom = (config.redline_rpm - config.idle_rpm) * throttle * 0.4
			target_rpm = clamp(
				max(rpm_from_wheels + headroom, config.idle_rpm + headroom),
				config.idle_rpm,
				config.redline_rpm - 500.0
			)

	elif current_gear_ratio > 0.0 and not is_moving:
		if throttle > 0.0:
			var rev_range = config.redline_rpm - config.idle_rpm
			target_rpm = clamp(
				config.idle_rpm + rev_range * throttle * 0.85,
				config.idle_rpm,
				config.redline_rpm - 500.0
			)
		else:
			target_rpm = config.idle_rpm

	else:
		if throttle > 0.0:
			var rev_range = config.redline_rpm - config.idle_rpm
			target_rpm = clamp(
				config.idle_rpm + rev_range * throttle * 0.85,
				config.idle_rpm,
				config.redline_rpm - 500.0
			)
		else:
			target_rpm = config.idle_rpm

func get_rpm_percentage() -> float:
	return current_rpm / config.redline_rpm

func reset() -> void:
	current_rpm = config.idle_rpm if config else 1000.0
	target_rpm = current_rpm
	is_rev_limited = false
