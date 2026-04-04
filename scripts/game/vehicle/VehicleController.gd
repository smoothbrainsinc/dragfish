extends VehicleBody3D
class_name VehicleController

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

# ===== Chute =====
var chute: DragChute = null

# =============================================================
func _ready() -> void:
	set_physics_process(false)

func initialize(config: VehicleConfig, player: bool) -> void:
	vehicle_config = config
	is_player = player
	name = config.vehicle_name

	_cache_wheels()
	_create_modules()
	_setup_modules()
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


func _on_finish_line_entered(body: Node3D) -> void:
	if body == self and chute:
		chute.deploy()

# Manual chute control for player
func _input(event) -> void:
	if not is_player or not chute:
		return
	if event.is_action_pressed("deploy_chute"):
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

	var max_wheel_rpm := engine.current_rpm / current_gear_ratio
	var wheel_radius := driven_wheels[0].wheel_radius
	var max_vehicle_speed := (max_wheel_rpm * TAU / 60.0) * wheel_radius

	if abs(forward_speed) > max_vehicle_speed * 1.02:
		for w in driven_wheels:
			w.engine_force = 0.0
		return

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

	if is_player:
		input.shift_up_requested.connect(_on_shift_up_requested)
		input.shift_down_requested.connect(_on_shift_down_requested)

func _on_shift_up_requested() -> void:
	transmission.request_shift_up()

func _on_shift_down_requested() -> void:
	transmission.request_shift_down()

func get_forward_speed() -> float:
	return forward_speed
