extends Node
class_name TransmissionModule
## Handles gear shifting, clutch simulation, and power delivery

signal gear_changed(new_gear: int)
signal shift_started
signal shift_completed
signal missed_shift

const MIN_RPM_FOR_SHIFT = 1000.0

var config: TransmissionConfig
var engine_config: EngineConfig

# NOTE: current_gear is 0-indexed internally (0 = 1st gear, 1 = 2nd gear, etc.)
var current_gear: int = 0  # Start in 1st gear (index 0)
var is_shifting: bool = false
var shift_timer: float = 0.0
var clutch_position: float = 1.0  # 1.0 = engaged, 0.0 = disengaged

var is_manual_mode: bool = false
var pending_gear: int = -1
var was_missed_shift: bool = false

func setup(transmission_config: TransmissionConfig, engine_cfg: EngineConfig) -> void:
	if not transmission_config or not engine_cfg:
		push_error("[TransmissionModule] Null configs provided!")
		return
	
	config = transmission_config
	engine_config = engine_cfg
	current_gear = 0  # Start in 1st gear
	print("[TransmissionModule] Setup: %s" % config.get_debug_info())

func _ready() -> void:
	set_physics_process(false)

func start() -> void:
	if not config or not engine_config:
		push_error("[TransmissionModule] Config not set!")
		return
	set_physics_process(true)

func stop() -> void:
	set_physics_process(false)
	
	

func _physics_process(delta: float) -> void:
	# Handle shifting animation
	if is_shifting:
		shift_timer -= delta
		
		# Clutch disengagement during first half of shift
		if shift_timer > config.shift_time * 0.5:
			clutch_position = lerp(clutch_position, 0.0, delta * 5.0)
		else:
			# Clutch engagement during second half
			clutch_position = lerp(clutch_position, 1.0, delta / config.clutch_engagement_time)
		
		# Shift complete
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
	
	# Calculate missed shift chance based on current RPM
	var engine_module = get_parent().get_node_or_null("EngineModule")
	if engine_module:
		var current_rpm = engine_module.current_rpm
		var miss_chance = config.calculate_missed_shift_chance(current_rpm, engine_config, is_upshift)
		
		if randf() < miss_chance:
			was_missed_shift = true
			shift_timer = config.shift_time + config.missed_shift_time_penalty
		else:
			shift_timer = config.shift_time
	else:
		shift_timer = config.shift_time
	
	emit_signal("shift_started")

## Complete the shift
func complete_shift() -> void:
	if was_missed_shift:
		emit_signal("missed_shift")
		var engine_module = get_parent().get_node_or_null("EngineModule")
		if engine_module:
			engine_module.current_rpm = max(
				engine_module.current_rpm - config.missed_shift_rpm_penalty,
				engine_config.idle_rpm
			)
	
	current_gear = pending_gear

	var engine = get_parent().get_node_or_null("EngineModule")
	var ctrl = get_parent()
	if engine and ctrl.has_method("get_forward_speed"):
		var speed = abs(ctrl.get_forward_speed())  # abs() so negative speed doesn't kill it
		var ratio = config.get_total_ratio(current_gear)
		var synced_rpm = engine.calculate_rpm_from_wheel_speed(speed, ratio)
		synced_rpm = max(synced_rpm, engine_config.idle_rpm + 500.0)  # never below idle+500
		engine.current_rpm = synced_rpm
		engine.target_rpm = synced_rpm
		engine.is_rev_limited = false
		
	pending_gear = -1
	is_shifting = false
	clutch_position = 1.0
	
	emit_signal("gear_changed", current_gear + 1)
	emit_signal("shift_completed")


## Auto-shift logic (called by controller when in auto mode)
func update_auto_shift(current_rpm: float) -> void:
	if is_manual_mode:
		return
	if is_shifting or not config.auto_shift_enabled:
		return
	
	var shift_rpm = engine_config.redline_rpm * config.auto_shift_point
	var downshift_rpm = engine_config.redline_rpm * config.auto_downshift_min
	
	# Shift up if over shift point and shift is safe
	if current_rpm >= shift_rpm:
		if config.is_upshift_safe(current_rpm, current_gear, engine_config):
			request_shift_up()
	
	# Shift down if RPM too low (but not if we're near redline in lower gear)
	elif current_rpm < downshift_rpm:
		if current_gear > 0:  # Not in first gear
			# Only downshift if it's safe (won't over-rev)
			if config.is_downshift_safe(current_rpm, current_gear, engine_config):
				request_shift_down()

## Calculate wheel force from engine torque
func calculate_wheel_force(engine_torque: float, wheel_radius: float) -> float:
	if is_shifting or wheel_radius <= 0.0:
		return 0.0
	
	var gear_ratio = config.get_total_ratio(current_gear)
	if gear_ratio == 0.0:
		return 0.0
	
	# Apply gear ratio and clutch
	var wheel_torque = engine_torque * gear_ratio
	wheel_torque *= clutch_position * (1.0 - config.clutch_slip)
	
	


	return wheel_torque / wheel_radius

## Get current gear ratio (0-indexed)
func get_current_gear_ratio() -> float:
	return config.get_total_ratio(current_gear)

## Get current total ratio including final drive
func get_current_total_ratio() -> float:
	return config.get_total_ratio(current_gear)

## Get vehicle speed at current RPM
func get_vehicle_speed(engine_rpm: float, wheel_radius: float) -> float:
	return config.get_vehicle_speed(engine_rpm, current_gear, wheel_radius)

## Check if shift is safe
func is_upshift_safe(current_rpm: float) -> bool:
	return config.is_upshift_safe(current_rpm, current_gear, engine_config)

func is_downshift_safe(current_rpm: float) -> bool:
	return config.is_downshift_safe(current_rpm, current_gear, engine_config)

## Get optimal shift point for current gear
func get_optimal_shift_rpm() -> float:
	return config.get_optimal_shift_rpm(engine_config, current_gear)

## Get clutch engagement (0.0 = disengaged, 1.0 = engaged)
func get_clutch_position() -> float:
	return clutch_position

## Check if clutch is engaged
func is_clutch_engaged() -> bool:
	return clutch_position > 0.9

## Manually set clutch position (for player control)
func set_manual_clutch(position: float) -> void:
	if not is_shifting:
		clutch_position = clamp(position, 0.0, 1.0)

## Reset transmission
func reset() -> void:
	current_gear = 0  # 1st gear (0-indexed)
	is_shifting = false
	shift_timer = 0.0
	clutch_position = 1.0
	pending_gear = -1
	was_missed_shift = false

## Get gear as string (for UI) - converts to 1-based display
func get_gear_string() -> String:
	return str(current_gear + 1)

## Get gear number (1-based for display)
func get_gear_number() -> int:
	return current_gear + 1

## Get gear index (0-based for internal use)
func get_gear_index() -> int:
	return current_gear

## Set manual/auto mode
func set_manual_mode(manual: bool) -> void:
	is_manual_mode = manual

## Calculate what RPM will be after shifting
func get_rpm_after_upshift(current_rpm: float) -> float:
	if current_gear >= config.get_gear_count() - 1:
		return current_rpm
	return config.calculate_rpm_after_upshift(current_rpm, current_gear, current_gear + 1)

func get_rpm_after_downshift(current_rpm: float) -> float:
	if current_gear <= 0:
		return current_rpm
	return config.calculate_rpm_after_downshift(current_rpm, current_gear, current_gear - 1)

## Debug info
func get_debug_info() -> String:
	return "Gear: %d/%d, Ratio: %.2f:1, Clutch: %.0f%%, Shifting: %s" % [
		current_gear + 1,
		config.get_gear_count(),
		get_current_gear_ratio(),
		clutch_position * 100.0,
		"YES" if is_shifting else "NO"
	]
