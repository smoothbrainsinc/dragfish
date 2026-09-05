extends VehicleBody3D
class_name VehicleController

const WHEEL_SYNC_GRACE_TIME := 0.35  # seconds to suppress the drive-force
									  # desync clamp after a gear shift completes

# ===== Configuration =====
var vehicle_config: VehicleConfig
var is_player: bool

# ===== Subsystems =====
var engine: EngineModule
var transmission: TransmissionModule
var tires: TirePhysicsModule
var input: InputModule

# ===== Wheels =====
var steering_wheels: Array[VehicleWheel3D] = []
var driven_wheels: Array[VehicleWheel3D] = []
var all_wheels: Array[VehicleWheel3D] = []

# ===== State =====
var initialized := false
var forward_speed := 0.0
var wheel_sync_grace_timer := 0.0  # suppresses the drive-force desync clamp right after a shift,
									 # giving the physical wheel time to spin back up to speed

# ===== Chute =====
var chute: DragChute = null

# =============================================================
func _ready() -> void:
	set_physics_process(false)
	set_process_input(true)
	
func initialize(config: VehicleConfig, player: bool) -> void:
	vehicle_config = config
	is_player = player
	name = config.vehicle_name

	_cache_wheels()
	_create_modules()
	_setup_modules()
	config.apply_to_vehicle(self)
	_find_chute()

	mass = config.mass
	center_of_mass_mode = CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = config.center_of_mass_offset

	initialized = true
	set_physics_process(false)

	print("[VehicleController] Initialized:", name)
	print("Vehicle forward basis.z = ", transform.basis.z)
	print("Speed sign = ", linear_velocity)

func start_vehicle() -> void:
	if not initialized:
		return
	engine.start()
	transmission.start()
	set_physics_process(true)
	

func start_race() -> void:
	if not initialized:
		return
	input.start_race()

func stop_vehicle() -> void:
	set_physics_process(false)

# =============================================================
func _physics_process(delta: float) -> void:

	if wheel_sync_grace_timer > 0.0:
		wheel_sync_grace_timer -= delta

	if Engine.get_physics_frames() % 120 == 0:
		print("Gear: %d | Ratio: %.2f | Speed: %.1f mph" % [
			transmission.get_gear_number(),
			transmission.get_current_gear_ratio(),
			forward_speed * 2.23694
		])

	_update_forward_speed()

	var throttle := input.get_throttle()
	var brake_input := input.get_brake()
	var steer := input.get_steering()

	if is_player:
		if input.is_clutch_pressed():
			transmission.set_manual_clutch(0.0)
		else:
			transmission.set_manual_clutch(1.0)

	var current_gear_ratio := transmission.get_current_gear_ratio()

	if forward_speed <= 0.1 and throttle <= 0.0:
		engine.update(0.0, 0.0, forward_speed)
	else:
		engine.update(throttle, current_gear_ratio, forward_speed)

	engine._physics_process(delta)

	if not transmission.is_manual_mode:
		transmission.update_auto_shift(engine.current_rpm)

	if not is_player:
		input.update_ai_shifting(
			engine.current_rpm,
			transmission.get_optimal_shift_rpm(),
			engine.config.redline_rpm,
			transmission.get_gear_index(),
			transmission.config.get_gear_count(),
			transmission
		)

	var drive_torque := engine.get_current_torque()
	var wheel_radius := _get_driven_wheel_radius()
	var drive_force: float = transmission.calculate_wheel_force(drive_torque, wheel_radius)

	if is_player and Engine.get_physics_frames() % 60 == 0:
		print("[Physics] Throttle: %.2f | RPM: %.0f | Gear: %d | Torque: %.0f Nm | Force: %.0f N | Speed: %.1f m/s" % [
			throttle, engine.current_rpm, transmission.get_gear_number(), drive_torque, drive_force, forward_speed
		])

	_apply_drive_force(drive_force)
	_apply_brakes(brake_input)
	_apply_steering(steer)

	tires.update_wheel_slip(all_wheels, forward_speed)
	tires.apply_wheel_friction(all_wheels)


# =============================================================
# Chute
# =============================================================
func _find_chute() -> void:
	chute = find_child("DragChute", true, false) as DragChute
	if chute:
		print("[VehicleController] Chute found on: ", name)
		chute.connect_to_finish_line()
	else:
		print("[VehicleController] No chute on: ", name)




# Manual chute control for player
func _input(event) -> void:
	print("_input called")
	if event is InputEventKey and event.pressed and event.keycode == KEY_C:
		print("[DEBUG] input processing enabled? ", is_processing_input())
		print("[DEBUG] raw C keypress seen, is_player=", is_player, " chute=", chute)
	if not is_player or not chute:
		return
	if event.is_action_pressed("deploy_chute") or event.is_action_pressed("retract_chute"):
		print("[DEBUG] action matched | is_deployed=", chute.is_deployed)
		if not chute.is_deployed:
			chute.deploy()
		else:
			chute.retract()

# =============================================================
# Physics helpers
# =============================================================
func _apply_drive_force(force: float) -> void:
	if driven_wheels.is_empty():
		return
	var current_gear_ratio := transmission.get_current_gear_ratio()
	if current_gear_ratio <= 0.0:
		for w in driven_wheels:
			w.engine_force = 0.0
		return

	# Right after a shift, calculate_wheel_force() returned 0 for the whole
	# shift window, so the physical wheel's own rotation lags actual road
	# speed. Skip the desync check here — force is already being restored,
	# and the wheel needs that force to spin back up. Checking it now would
	# zero the force again and prevent it from ever catching up.
	if wheel_sync_grace_timer <= 0.0:
		var wheel_rpm: float = abs(driven_wheels[0].get_rpm())
		var wheel_radius := driven_wheels[0].wheel_radius
		var max_vehicle_speed := (wheel_rpm * TAU / 60.0) * wheel_radius
		if abs(forward_speed) > max_vehicle_speed * 1.15:
			# Taper toward the wheel-implied max instead of hard-zeroing.
			# A hard zero can never recover on its own: zero force means the
			# wheel can't spin up, so the gap never closes and next frame
			# trips the same clamp again. Scaling the force down still lets
			# the wheel accelerate toward the car's real speed.
			var overspeed_ratio: float = max_vehicle_speed * 1.15 / max(abs(forward_speed), 0.01)
			force *= clamp(overspeed_ratio, 0.15, 1.0)
			print("[Clamp] gear ", transmission.get_gear_number(), " max_speed=", max_vehicle_speed, " forward_speed=", forward_speed, " -> tapered to ", overspeed_ratio)

	var per_wheel := force / driven_wheels.size()
	for w in driven_wheels:
		w.engine_force = per_wheel

func _apply_brakes(amount: float) -> void:
	for w in all_wheels:
		w.brake = amount * vehicle_config.brake_force

func _apply_steering(amount: float) -> void:
	for w in steering_wheels:
		w.steering = amount * vehicle_config.max_steer_angle

func _update_forward_speed() -> void:
	var local_vel := global_transform.basis.inverse() * linear_velocity
	forward_speed = local_vel.z

func _get_driven_wheel_radius() -> float:
	return driven_wheels[0].wheel_radius if not driven_wheels.is_empty() else 0.8125

# =============================================================
# Setup helpers
# =============================================================
func _cache_wheels() -> void:
	for child in get_children():
		if child is VehicleWheel3D:
			all_wheels.append(child)
			if child.use_as_steering:
				steering_wheels.append(child)
			if child.use_as_traction:
				driven_wheels.append(child)

	assert(driven_wheels.size() > 0, "No driven wheels!")
	print("[VehicleController] Found wheels: %d total, %d driven, %d steering" % [
		all_wheels.size(),
		driven_wheels.size(),
		steering_wheels.size()
	])

func _create_modules() -> void:
	engine = EngineModule.new()
	transmission = TransmissionModule.new()
	tires = TirePhysicsModule.new()
	input = InputModule.new()

	add_child(engine)
	add_child(transmission)
	add_child(tires)
	add_child(input)

func _setup_modules() -> void:
	engine.setup(vehicle_config.engine, _get_driven_wheel_radius())
	transmission.setup(vehicle_config.transmission, vehicle_config.engine)
	tires.setup(vehicle_config.front_tires, vehicle_config.rear_tires)
	input.setup(is_player, vehicle_config)

	transmission.set_manual_mode(is_player)
	transmission.shift_completed.connect(_on_shift_completed)

	if is_player:
		input.shift_up_requested.connect(_on_shift_up_requested)
		input.shift_down_requested.connect(_on_shift_down_requested)

func _on_shift_up_requested() -> void:
	transmission.request_shift_up()

func _on_shift_down_requested() -> void:
	transmission.request_shift_down()

func _on_shift_completed() -> void:
	# The physical wheel's own rotation speed lags actual road speed after a
	# force-free shift window (calculate_wheel_force returns 0 while shifting).
	# Give it a moment to spin back up under restored force before the
	# desync clamp in _apply_drive_force starts judging it again.
	wheel_sync_grace_timer = WHEEL_SYNC_GRACE_TIME

func get_forward_speed() -> float:
	return forward_speed
