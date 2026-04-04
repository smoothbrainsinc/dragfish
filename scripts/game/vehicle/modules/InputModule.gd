extends Node
class_name InputModule
## Handles player and AI input for vehicle control
## Player input uses InputMap actions, AI uses simulated inputs

signal shift_up_requested
signal shift_down_requested
signal launch_control_activated  # For holding at launch RPM

# Required InputMap actions (validate these exist)
const REQUIRED_ACTIONS = [
	"throttle",
	"brake",
	"shift_up",
	"shift_down",
	"clutch"
]

var is_player_controlled: bool = true
var vehicle_config: VehicleConfig  # Reference to get AI parameters

# AI state
var ai_reaction_timer: float = 0.0
var ai_has_reacted: bool = false
var ai_target_reaction_time: float = 0.0
var ai_current_throttle: float = 0.0
var ai_shift_timer: float = 0.0
var ai_throttle_variation: float = 0.0  # Random performance variation

# Race state
var race_started: bool = false
var launch_control_active: bool = false

func setup(player_controlled: bool, config: VehicleConfig = null) -> void:
	is_player_controlled = player_controlled
	vehicle_config = config
	
	if is_player_controlled:
		_validate_input_map()
	else:
		if vehicle_config:
			# Use AI parameters from vehicle config
			ai_target_reaction_time = randf_range(
				vehicle_config.ai_reaction_time_min,
				vehicle_config.ai_reaction_time_max
			)
			# AI consistency affects throttle variation
			ai_throttle_variation = vehicle_config.ai_consistency
		else:
			# Fallback defaults
			ai_target_reaction_time = randf_range(0.10, 0.25)
			ai_throttle_variation = 0.05
		
		print("[InputModule] AI setup: reaction=%.3fs, consistency=%.2f" % [
			ai_target_reaction_time,
			ai_throttle_variation
		])

func _ready() -> void:
	set_physics_process(false)

## Validate required input actions exist
func _validate_input_map() -> void:
	var missing_actions = []
	for action in REQUIRED_ACTIONS:
		if not InputMap.has_action(action):
			missing_actions.append(action)
	
	if missing_actions.size() > 0:
		push_warning("[InputModule] Missing input actions: %s" % ", ".join(missing_actions))

func start_race() -> void:
	race_started = true
	set_physics_process(true)
	print("[InputModule] Race started - %s" % ("Player" if is_player_controlled else "AI"))

func stop() -> void:
	set_physics_process(false)
	reset()

## Get throttle input (0.0 - 1.0)
func get_throttle() -> float:
	if not race_started:
		return 0.0
	
	if is_player_controlled:
		# Check if launch control is active
		if launch_control_active:
			return 1.0  # Full throttle held at launch RPM
		return Input.get_action_strength("throttle")
	else:
		return get_ai_throttle()

## Get brake input (0.0 - 1.0)
func get_brake() -> float:
	var brake = 0.0
	if is_player_controlled:
		brake = Input.get_action_strength("brake") if InputMap.has_action("brake") else 0.0
		# 🅿️ Parking brake (e.g., "e_brake" action bound to 'P')
		if InputMap.has_action("parking_brake") and Input.is_action_pressed("parking_brake"):
			brake = max(brake, 1.0)  # full brake
	else:
		brake = 0.0
	return brake


## Get steering input (-1.0 to 1.0)
## Note: Minimal steering needed for drag racing
func get_steering() -> float:
	if is_player_controlled:
		if InputMap.has_action("steer_left") and InputMap.has_action("steer_right"):
			var left = Input.get_action_strength("steer_left")
			var right = Input.get_action_strength("steer_right")
			return right - left  # Positive = right, negative = left
		return 0.0
	else:
		# AI slight corrections to stay straight
		return randf_range(-0.02, 0.02)

## Check clutch input (for manual transmission)
func is_clutch_pressed() -> bool:
	if not is_player_controlled:
		return false
	if not InputMap.has_action("clutch"):
		return false
	return Input.is_action_pressed("clutch")

## Check for launch control activation (holding brake + throttle)
func check_launch_control() -> bool:
	if not is_player_controlled or not vehicle_config:
		return false
	
	if not vehicle_config.engine or not vehicle_config.engine.has_launch_control:
		return false
	
	var brake_pressed = Input.is_action_pressed("brake") if InputMap.has_action("brake") else false
	var throttle_pressed = Input.get_action_strength("throttle") > 0.5
	
	return brake_pressed and throttle_pressed

func _physics_process(_delta: float) -> void:
	if is_player_controlled:
		# Check for manual shift requests
		if InputMap.has_action("shift_up") and Input.is_action_just_pressed("shift_up"):
			emit_signal("shift_up_requested")
		
		if InputMap.has_action("shift_down") and Input.is_action_just_pressed("shift_down"):
			emit_signal("shift_down_requested")
		
		# Check for launch control
		launch_control_active = check_launch_control()
		if launch_control_active:
			emit_signal("launch_control_activated")

## AI throttle with reaction time and consistency variation
func get_ai_throttle() -> float:
	if not race_started:
		return 0.0
	
	# Reaction time simulation
	if not ai_has_reacted:
		ai_reaction_timer += get_physics_process_delta_time()
		if ai_reaction_timer >= ai_target_reaction_time:
			ai_has_reacted = true
		else:
			return 0.0  # Still reacting...
	
	# Smooth throttle application
	ai_current_throttle = lerp(ai_current_throttle, 1.0, get_physics_process_delta_time() * 5.0)
	
	# Add consistency variation (simulates imperfect throttle control)
	var variation = sin(Time.get_ticks_msec() * 0.001) * ai_throttle_variation
	
	return clamp(ai_current_throttle + variation, 0.0, 1.0)

## AI shifting logic - handles different shift strategies
func update_ai_shifting(
	current_rpm: float, 
	optimal_shift_rpm: float,
	redline_rpm: float,
	current_gear: int,
	max_gear: int,
	transmission: TransmissionModule
) -> void:
	if is_player_controlled or not ai_has_reacted:
		return
	
	if current_gear >= max_gear:
		return  # Already in top gear
	
	ai_shift_timer += get_physics_process_delta_time()
	
	# Minimum time between shifts (prevents double-shifting)
	if ai_shift_timer < 0.15:
		return
	
	# Determine shift point based on strategy
	var shift_rpm = optimal_shift_rpm
	
	if vehicle_config:
		match vehicle_config.ai_shift_strategy:
			VehicleConfig.ShiftStrategy.REDLINE:
				shift_rpm = redline_rpm * 0.98  # Shift just before redline
			
			VehicleConfig.ShiftStrategy.OPTIMAL:
				shift_rpm = optimal_shift_rpm  # Shift at power peak
			
			VehicleConfig.ShiftStrategy.CONSERVATIVE:
				shift_rpm = optimal_shift_rpm * 0.9  # Shift early
			
			VehicleConfig.ShiftStrategy.AGGRESSIVE:
				shift_rpm = redline_rpm * 1.02  # Risk over-rev
	
	# Add consistency variation to shift timing
	var shift_variance = randf_range(-200.0, 200.0) * ai_throttle_variation * 10.0
	shift_rpm += shift_variance
	
	# Execute shift
	if current_rpm >= shift_rpm:
		if transmission.request_shift_up():
			ai_shift_timer = 0.0

## Reset input state (called between races)
func reset() -> void:
	race_started = false
	launch_control_active = false
	ai_reaction_timer = 0.0
	ai_has_reacted = false
	ai_current_throttle = 0.0
	ai_shift_timer = 0.0
	
	# Randomize AI parameters for next race
	if not is_player_controlled and vehicle_config:
		ai_target_reaction_time = randf_range(
			vehicle_config.ai_reaction_time_min,
			vehicle_config.ai_reaction_time_max
		)

## Get input state for debugging
func get_debug_info() -> String:
	if is_player_controlled:
		return "Player: T=%.2f B=%.2f LC=%s" % [
			get_throttle(),
			get_brake(),
			"YES" if launch_control_active else "NO"
		]
	else:
		return "AI: T=%.2f React=%s (%.2fs)" % [
			ai_current_throttle,
			"YES" if ai_has_reacted else "NO",
			ai_reaction_timer
		]
