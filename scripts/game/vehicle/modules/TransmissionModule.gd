extends Node
class_name TransmissionModule
## Handles gear shifting, clutch simulation, and power delivery

signal gear_changed(new_gear: int)  # 1-based gear number (display value)
signal shift_started
signal shift_completed
signal missed_shift

# NOTE: current_gear is 0-indexed internally (0 = 1st gear, 1 = 2nd gear, etc.)
var current_gear: int = 0
var is_shifting: bool = false
var shift_timer: float = 0.0
var clutch_position: float = 1.0  # 1.0 = engaged, 0.0 = disengaged

var is_manual_mode: bool = false
var pending_gear: int = -1
var was_missed_shift: bool = false

var config: TransmissionConfig
var engine_config: EngineConfig

var _engine: Node


func _ready() -> void:
	set_physics_process(false)


func setup(transmission_config: TransmissionConfig, engine_cfg: EngineConfig) -> void:
	if not transmission_config or not engine_cfg:
		push_error("[TransmissionModule] Null configs provided!")
		return

	config = transmission_config
	engine_config = engine_cfg
	current_gear = 0
	print("[TransmissionModule] Setup: %s" % config.get_debug_info())


func start() -> void:
	if not config or not engine_config:
		push_error("[TransmissionModule] Config not set!")
		return
	set_physics_process(true)


func stop() -> void:
	set_physics_process(false)
	_cancel_shift()


func _get_engine() -> Node:
	if not is_instance_valid(_engine):
		_engine = get_parent().get_node_or_null("EngineModule")
	return _engine


func _cancel_shift() -> void:
	is_shifting = false
	was_missed_shift = false
	pending_gear = -1
	shift_timer = 0.0
	clutch_position = 1.0


func _physics_process(delta: float) -> void:
	if not is_shifting:
		return

	shift_timer -= delta

	if shift_timer > config.shift_time * 0.5:
		# First half: disengage (linear, reaches 0.0)
		var disengage_time := maxf(config.shift_time * 0.5, 0.001)
		clutch_position = move_toward(clutch_position, 0.0, delta / disengage_time)
	else:
		# Second half: engage (linear, cannot overshoot)
		var engage_time := maxf(config.clutch_engagement_time, 0.001)
		clutch_position = move_toward(clutch_position, 1.0, delta / engage_time)

	if shift_timer <= 0.0:
		complete_shift()


## Request a gear shift (up or down)
func request_shift_up() -> bool:
	if is_shifting:
		return false
	if current_gear >= config.get_gear_count() - 1:
		return false  # Already in top gear

	pending_gear = current_gear + 1
	start_shift(true)
	return true


func request_shift_down() -> bool:
	if is_shifting:
		return false
	if current_gear <= 0:
		return false  # Already in first gear

	pending_gear = current_gear - 1
	start_shift(false)
	return true


## Start the shift process
func start_shift(is_upshift: bool) -> void:
	is_shifting = true
	was_missed_shift = false
	shift_timer = config.shift_time

	var engine := _get_engine()
	if engine:
		var miss_chance: float = config.calculate_missed_shift_chance(
			engine.current_rpm, engine_config, is_upshift
		)
		if randf() < miss_chance:
			was_missed_shift = true
			shift_timer += config.missed_shift_time_penalty

	shift_started.emit()


## Complete the shift
func complete_shift() -> void:
	if pending_gear >= 0:
		current_gear = pending_gear

	var engine := _get_engine()
	var ctrl := get_parent()

	if engine and ctrl.has_method("get_forward_speed"):
		var speed: float = absf(ctrl.get_forward_speed())
		var ratio: float = config.get_total_ratio(current_gear)
		var synced_rpm: float = engine.calculate_rpm_from_wheel_speed(speed, ratio)
		synced_rpm = maxf(synced_rpm, engine_config.idle_rpm + 500.0)
		engine.current_rpm = synced_rpm
		engine.target_rpm = synced_rpm
		engine.is_rev_limited = false

	# Apply missed-shift penalty AFTER sync, otherwise the sync overwrites it
	if was_missed_shift:
		missed_shift.emit()
		if engine:
			engine.current_rpm = maxf(
				engine.current_rpm - config.missed_shift_rpm_penalty,
				engine_config.idle_rpm
			)

	pending_gear = -1
	is_shifting = false
	was_missed_shift = false
	clutch_position = 1.0

	gear_changed.emit(current_gear + 1)
	shift_completed.emit()


## Auto-shift logic (called by controller when in auto mode)
func update_auto_shift(current_rpm: float) -> void:
	if is_manual_mode or is_shifting or not config.auto_shift_enabled:
		return

	var shift_rpm := engine_config.redline_rpm * config.auto_shift_point
	var downshift_rpm := engine_config.redline_rpm * config.auto_downshift_min

	if current_rpm >= shift_rpm:
		if config.is_upshift_safe(current_rpm, current_gear, engine_config):
			request_shift_up()
	elif current_rpm < downshift_rpm and current_gear > 0:
		if config.is_downshift_safe(current_rpm, current_gear, engine_config):
			request_shift_down()


## Calculate wheel force from engine torque
func calculate_wheel_force(engine_torque: float, wheel_radius: float) -> float:
	if is_shifting or wheel_radius <= 0.0:
		return 0.0

	var gear_ratio := config.get_total_ratio(current_gear)
	if gear_ratio == 0.0:
		return 0.0

	var wheel_torque := engine_torque * gear_ratio
	wheel_torque *= clutch_position * (1.0 - config.clutch_slip)
	return wheel_torque / wheel_radius


## Get current total ratio including final drive
func get_current_total_ratio() -> float:
	return config.get_total_ratio(current_gear)


## Kept for compatibility; same value as get_current_total_ratio()
func get_current_gear_ratio() -> float:
	return get_current_total_ratio()


func get_vehicle_speed(engine_rpm: float, wheel_radius: float) -> float:
	return config.get_vehicle_speed(engine_rpm, current_gear, wheel_radius)


func is_upshift_safe(current_rpm: float) -> bool:
	return config.is_upshift_safe(current_rpm, current_gear, engine_config)


func is_downshift_safe(current_rpm: float) -> bool:
	return config.is_downshift_safe(current_rpm, current_gear, engine_config)


func get_optimal_shift_rpm() -> float:
	return config.get_optimal_shift_rpm(engine_config, current_gear)


func get_clutch_position() -> float:
	return clutch_position


func is_clutch_engaged() -> bool:
	return clutch_position > 0.9


## Manually set clutch position (for player control)
func set_manual_clutch(position: float) -> void:
	if not is_shifting:
		clutch_position = clampf(position, 0.0, 1.0)


func reset() -> void:
	current_gear = 0
	_cancel_shift()


func get_gear_string() -> String:
	return str(current_gear + 1)


func get_gear_number() -> int:
	return current_gear + 1


func get_gear_index() -> int:
	return current_gear


func set_manual_mode(manual: bool) -> void:
	is_manual_mode = manual


func get_rpm_after_upshift(current_rpm: float) -> float:
	if current_gear >= config.get_gear_count() - 1:
		return current_rpm
	return config.calculate_rpm_after_upshift(current_rpm, current_gear, current_gear + 1)


func get_rpm_after_downshift(current_rpm: float) -> float:
	if current_gear <= 0:
		return current_rpm
	return config.calculate_rpm_after_downshift(current_rpm, current_gear, current_gear - 1)


func get_debug_info() -> String:
	return "Gear: %d/%d, Ratio: %.2f:1, Clutch: %.0f%%, Shifting: %s" % [
		current_gear + 1,
		config.get_gear_count(),
		get_current_gear_ratio(),
		clutch_position * 100.0,
		"YES" if is_shifting else "NO"
	]
