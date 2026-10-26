extends VehicleBody3D
class_name VehicleController

# ===== Differential =====
@export var diff_lock_strength: float = 4.0    # tune: higher = reacts harder to rpm diff
@export var diff_max_bias: float = 0.35        # max torque shift fraction (0.5 = fully locked)
@export var diff_engage_slip: float = 1.5   # m/s of avg wheelspin before diff logic kicks in

var driven_wheel_left: VehicleWheel3D = null
var driven_wheel_right: VehicleWheel3D = null

## Grip on the driven wheels while a burnout is held. Must be low enough that
## drive force exceeds friction (friction limit = friction_slip * wheel load).
@export var burnout_friction_slip: float = 0.4

## Driven-wheel grip vs tire slip speed: full grip at or below GRIP_FULL_SLIP,
## burnout-level grip at or above GRIP_NONE_SLIP (m/s of tire-vs-ground speed).
const GRIP_FULL_SLIP := 3.0
const GRIP_NONE_SLIP := 12.0

## Player throttle cap before green, so the car can be eased up to the beams.
## Burnouts and launch control are exempt; full throttle returns at green.
@export var creep_throttle: float = 0.2

const BURNOUT_MAX_SPEED := 3.0
const BURNOUT_START_SPEED := 0.5      # brake-pedal burnouts only start from a standstill
const POST_BURNOUT_SPIN_TIME := 2.0   # s, reduced grip after a burnout while the tires spin down       # m/s, burnout ends once the car rolls past this
const REVERSE_ENGAGE_MAX_SPEED := 1.0  # m/s, can only select/leave reverse below this

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
var smoke: TireSmokeModule

# ===== Wheels =====
var steering_wheels: Array[VehicleWheel3D] = []
var driven_wheels: Array[VehicleWheel3D] = []
var all_wheels: Array[VehicleWheel3D] = []

# ===== State =====
var initialized := false
var forward_speed := 0.0
var staged := false          # set by StagingController once in the stage beam
var burnout_active := false
var line_lock := false       # front brakes held, driven wheels free
var _base_friction: Dictionary = {}  # driven wheel -> configured friction_slip
var _spin_window := 0.0              # seconds of post-burnout reduced grip left
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

	# Changed to Log.d
	Log.d(Log.Category.GENERAL, "[VehicleController] Initialized: " + str(name))
	Log.d(Log.Category.GENERAL, "Vehicle forward basis.z = " + str(transform.basis.z))
	Log.d(Log.Category.GENERAL, "Speed sign = " + str(linear_velocity))

func start_vehicle() -> void:
	if not initialized:
		return
	RunLogger.begin_run(self)
	engine.start()
	transmission.start()
	set_physics_process(true)
	

func start_race() -> void:
	if not initialized:
		return
	input.start_race()

func stop_vehicle() -> void:
	RunLogger.end_run()
	_set_burnout(false)
	if smoke:
		smoke.stop()
	set_physics_process(false)
	transmission.stop()
	input.stop()
	engine.stop()
	

# =============================================================
func _physics_process(delta: float) -> void:

	if wheel_sync_grace_timer > 0.0:
		wheel_sync_grace_timer -= delta

	# Gated: Only format the string if PHYSICS logging is enabled
	if Log.enabled[Log.Category.PHYSICS] and Engine.get_physics_frames() % 120 == 0:
		Log.d(Log.Category.PHYSICS, "Gear: %d | Ratio: %.2f | Speed: %.1f mph" % [
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
	var drive_dir := transmission.get_drive_direction()
	# Speed along the driven direction (positive when reversing in reverse)
	var driven_speed := forward_speed * drive_dir

	if line_lock and (staged or input.race_started):
		_set_line_lock(false)
	_update_burnout(throttle, brake_input)
	if is_player and not input.race_started and not burnout_active and not input.launch_control_active:
		throttle = minf(throttle, creep_throttle)

	if driven_speed <= 0.1 and throttle <= 0.0:
		engine.update(0.0, 0.0, driven_speed)
	else:
		engine.update(throttle, current_gear_ratio, driven_speed)

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

	var wheel_radius := _get_driven_wheel_radius()
	var implied_rpm: float = abs(forward_speed) / wheel_radius * (60.0 / TAU) * current_gear_ratio
	var crank_rpm: float = max(engine.current_rpm, implied_rpm)
	var drive_torque: float = engine.config.get_torque_at_rpm(crank_rpm) * throttle
	var drive_force: float = transmission.calculate_wheel_force(drive_torque, wheel_radius) * drive_dir

	# Gated: Only format the string if PHYSICS logging is enabled
	if is_player and Log.enabled[Log.Category.PHYSICS] and Engine.get_physics_frames() % 60 == 0:
		Log.d(Log.Category.PHYSICS, "[Physics] Throttle: %.2f | RPM: %.0f | Gear: %d | Torque: %.0f Nm | Force: %.0f N | Speed: %.1f m/s" % [
			throttle, engine.current_rpm, transmission.get_gear_number(), drive_torque, drive_force, forward_speed
		])

	_apply_drive_force(drive_force)
	_apply_brakes(brake_input)
	_apply_steering(steer)
	
	if Engine.get_physics_frames() % 60 == 0:
		for w in all_wheels:
			print(w.name, " contact: ", w.is_in_contact(), " rpm: ", snappedf(w.get_rpm(), 0.1),
				" y: ", snappedf(w.global_position.y, 0.001),
				" radius: ", w.wheel_radius, " travel: ", w.suspension_travel,
				" rest: ", w.wheel_rest_length, " traction: ", w.use_as_traction)

	tires.update_wheel_slip(all_wheels, forward_speed)
	tires.apply_wheel_friction(all_wheels)
	tires.update_wheelspin(
		all_wheels, forward_speed, engine.current_rpm, current_gear_ratio,
		drive_dir, transmission.get_clutch_position(), throttle, burnout_active
	)
	tires.log_wheel_debug(all_wheels)
	_update_driven_traction(delta)
	
	_update_driven_traction(delta)
	smoke.update_smoke(tires, drive_dir)
	_log_if_stuck(throttle, brake_input)


# =============================================================
# Chute
# =============================================================
func _find_chute() -> void:
	chute = find_child("DragChute", true, false) as DragChute
	if chute:
		# Changed to Log.d
		Log.d(Log.Category.CHUTE, "[VehicleController] Chute found on: " + str(name))
		chute.connect_to_finish_line()
	else:
		# Changed to Log.d
		Log.d(Log.Category.CHUTE, "[VehicleController] No chute on: " + str(name))




# Manual chute control for player
func _input(event) -> void:
	# REMOVED: print("_input called")  <-- This was pure spam
	
	if event is InputEventKey and event.pressed and event.keycode == KEY_C:
		# Changed to Log.d
		Log.d(Log.Category.GENERAL, "[DEBUG] input processing enabled? " + str(is_processing_input()))
		Log.d(Log.Category.CHUTE, "[DEBUG] raw C keypress seen, is_player=" + str(is_player) + " chute=" + str(chute))
		
	if not is_player or not chute:
		return
	if event.is_action_pressed("deploy_chute") or event.is_action_pressed("retract_chute"):
		# Changed to Log.d
		Log.d(Log.Category.CHUTE, "[DEBUG] action matched | is_deployed=" + str(chute.is_deployed))
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

			# Gated: Only format the string if WHEELS logging is enabled
			if Log.enabled[Log.Category.WHEELS]:
				Log.d(Log.Category.WHEELS, "[Clamp] gear " + str(transmission.get_gear_number()) + " max_speed=" + str(max_vehicle_speed) + " forward_speed=" + str(forward_speed) + " -> tapered to " + str(overspeed_ratio))

	if driven_wheel_left and driven_wheel_right:
		_apply_differential_force(force)
	else:
		var per_wheel := force / driven_wheels.size()
		for w in driven_wheels:
			w.engine_force = per_wheel

func _apply_differential_force(total_force: float) -> void:
	var rpm_l := driven_wheel_left.get_rpm()
	var rpm_r := driven_wheel_right.get_rpm()

	var wheel_radius := driven_wheel_left.wheel_radius
	var speed_l := (rpm_l * TAU / 60.0) * wheel_radius
	var speed_r := (rpm_r * TAU / 60.0) * wheel_radius
	var avg_wheel_speed := (speed_l + speed_r) * 0.5
	var wheelspin: float = absf(avg_wheel_speed) - abs(forward_speed)

	# Cornering makes the two wheels differ legitimately - that's not slip.
	# Only bias torque once the wheels are outrunning the chassis.
	if wheelspin < diff_engage_slip:
		var per_wheel := total_force / 2.0
		driven_wheel_left.engine_force = per_wheel
		driven_wheel_right.engine_force = per_wheel
		return

	var rpm_diff := (rpm_l - rpm_r) * transmission.get_drive_direction()
	var bias: float = clamp(rpm_diff * diff_lock_strength * 0.001, -diff_max_bias, diff_max_bias)
	driven_wheel_left.engine_force = total_force * (0.5 - bias)
	driven_wheel_right.engine_force = total_force * (0.5 + bias)

	if Log.enabled[Log.Category.WHEELS] and Engine.get_physics_frames() % 30 == 0:
		Log.d(Log.Category.WHEELS, "[Diff] rpm_l=%.0f rpm_r=%.0f bias=%.2f wheelspin=%.2f" % [rpm_l, rpm_r, bias, wheelspin])
func _apply_brakes(amount: float) -> void:
	for w in all_wheels:
		# Burnout / line lock: driven wheels spin freely. Line lock holds the others.
		var braked := amount
		if burnout_active and w.use_as_traction:
			braked = 0.0
		elif line_lock and not w.use_as_traction:
			braked = 1.0
		w.brake = braked * vehicle_config.brake_force

## Burnout = player holds brake (or line lock) + throttle at a standstill before staging.
## Drops grip on the driven wheels so they break loose and spin.
func _update_burnout(throttle: float, brake_input: float) -> void:
	var slow := absf(forward_speed) < BURNOUT_MAX_SPEED
	# Line lock burnouts start any time you are slow. A brake-pedal burnout must
	# start from a standstill, so braking while creeping to the beams never
	# turns into one.
	var pedal := brake_input > 0.1 and (burnout_active or absf(forward_speed) < BURNOUT_START_SPEED)
	var want := is_player and not staged and not input.race_started \
		and throttle > 0.3 and slow and (line_lock or pedal) \
		and transmission.get_current_total_ratio() > 0.0 \
		and not transmission.is_shifting
	_set_burnout(want)

func _set_burnout(on: bool) -> void:
	if burnout_active and not on:
		_spin_window = POST_BURNOUT_SPIN_TIME
	burnout_active = on


## A spinning tire has no grip: driven-wheel friction follows how fast the tire
## surface is moving relative to the ground, so grip returns only as the tire
## slows down or the car speeds up to meet it.
## Only active during a burnout and for POST_BURNOUT_SPIN_TIME after it. Normal
## launches always run the configured friction, so this can never trap the car.
func _update_driven_traction(delta: float) -> void:
	if input.race_started:
		_spin_window = 0.0
	elif _spin_window > 0.0:
		_spin_window -= delta
	for w in driven_wheels:
		if not _base_friction.has(w):
			_base_friction[w] = w.wheel_friction_slip
		var base: float = _base_friction[w]
		var spun := 0.0
		if burnout_active:
			spun = 1.0
		elif _spin_window > 0.0:
			spun = smoothstep(GRIP_FULL_SLIP, GRIP_NONE_SLIP, tires.get_slip_speed(w))
		w.wheel_friction_slip = lerpf(base, minf(base, burnout_friction_slip), spun)


## Once a second, when full throttle is on but the car is not moving, print what
## is holding it so the cause is visible instead of guessed.
func _log_if_stuck(throttle: float, brake_input: float) -> void:
	if not is_player or Engine.get_physics_frames() % 60 != 0:
		return
	if throttle < 0.5 or absf(forward_speed) > 0.5:
		return
	var parts: Array[String] = []
	for w in driven_wheels:
		parts.append("%s fric=%.2f slip=%.1f skid=%.2f brake=%.0f contact=%s" % [
			w.name, w.wheel_friction_slip, tires.get_slip_speed(w), w.get_skidinfo(), w.brake, w.is_in_contact()])
	print("[Stuck?] thr=%.2f spd=%.2f pedal=%.2f lineLock=%s burnout=%s window=%.1f gear=%d | %s" % [
		throttle, forward_speed, brake_input, line_lock, burnout_active, _spin_window,
		transmission.get_gear_number(), " | ".join(parts)])


func _on_line_lock_requested() -> void:
	if is_player and not staged and not input.race_started:
		_set_line_lock(not line_lock)


func _set_line_lock(on: bool) -> void:
	if on == line_lock:
		return
	line_lock = on
	print("[Vehicle] Line lock %s" % ("ON" if on else "OFF"))

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
			for m in child.get_children():
				if m is Node3D:
					m.transform = Transform3D(Basis.from_scale(Vector3(1, 1, -1)), Vector3.ZERO) * m.transform

	assert(driven_wheels.size() > 0, "No driven wheels!")

	if driven_wheels.size() == 2:
		if driven_wheels[0].position.x > driven_wheels[1].position.x:
			driven_wheel_left = driven_wheels[0]
			driven_wheel_right = driven_wheels[1]
		else:
			driven_wheel_left = driven_wheels[1]
			driven_wheel_right = driven_wheels[0]
	
	# Changed to Log.d
	Log.d(Log.Category.GENERAL, "[VehicleController] Found wheels: %d total, %d driven, %d steering" % [
		all_wheels.size(),
		driven_wheels.size(),
		steering_wheels.size()
	])

func _create_modules() -> void:
	engine = EngineModule.new()
	transmission = TransmissionModule.new()
	tires = TirePhysicsModule.new()
	input = InputModule.new()
	smoke = TireSmokeModule.new()

	add_child(engine)
	add_child(transmission)
	add_child(tires)
	add_child(input)
	add_child(smoke)

func _setup_modules() -> void:
	engine.setup(vehicle_config.engine, _get_driven_wheel_radius())
	transmission.setup(vehicle_config.transmission, vehicle_config.engine)
	tires.setup(vehicle_config.front_tires, vehicle_config.rear_tires)
	tires.register_wheels(all_wheels)
	smoke.setup(self, all_wheels)
	input.setup(is_player, vehicle_config)

	transmission.set_manual_mode(is_player)
	transmission.shift_completed.connect(_on_shift_completed)

	if is_player:
		input.shift_up_requested.connect(_on_shift_up_requested)
		input.shift_down_requested.connect(_on_shift_down_requested)
		input.reverse_requested.connect(_on_reverse_requested)
		input.line_lock_requested.connect(_on_line_lock_requested)

func _on_reverse_requested() -> void:
	if absf(forward_speed) > REVERSE_ENGAGE_MAX_SPEED:
		return
	transmission.set_reverse(not transmission.in_reverse)

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
