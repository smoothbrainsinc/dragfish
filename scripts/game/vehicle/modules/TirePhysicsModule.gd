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

# --- Wheelspin / break-loose tuning ---
const SPIN_ACCEL := 600.0         # rad/s^2, wheel spin-up once traction is broken
const SPIN_DECAY := 45.0          # rad/s^2, a spun-up tire slowing to ground speed (~1 s from burnout)
const SPIN_CATCHUP := 300.0       # rad/s^2, a tire slower than the ground catching up
const SPIN_LOAD_FACTOR := 0.5     # outside a burnout, ground load holds wheelspin this fraction of engine speed
const SKID_SLIP_THRESHOLD := 0.9  # get_skidinfo() below this = tire has lost grip
const SPIN_SLIP_FULL := 6.0       # m/s tire-vs-ground speed difference = full slip

# --- Per-wheel visual spin state ---
var _spin_omega: Dictionary = {}   # wheel -> visual angular velocity (rad/s, + = forward)
var _spin_extra: Dictionary = {}   # wheel -> accumulated angle beyond pure rolling (rad)
var _mesh_base: Dictionary = {}    # wheel -> Array of [MeshInstance3D, Transform3D, Vector3 pivot]
var slip_intensity: Dictionary = {}  # wheel -> 0..1, read by TireSmokeModule
var _slip_speed: Dictionary = {}   # wheel -> tire surface speed minus ground speed (m/s, abs)



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
func update_wheel_slip(wheels: Array[VehicleWheel3D], _forward_speed: float) -> void:
	var delta := get_physics_process_delta_time()
	if delta <= 0.0:
		return
	for w in wheels:
		var wheel_rpm: float = w.get_rpm()
		var rotation_deg: float = (wheel_rpm / 60.0) * 360.0 * delta
		w.rotation_degrees.x += rotation_deg


# ---------------------------------------------------------
# Wheelspin: VehicleWheel3D only ever rolls at ground speed, so a wheel that
# has lost grip never spins up on its own. Track a separate visual angular
# velocity and rotate the wheel meshes by the difference from rolling.
# ---------------------------------------------------------
func register_wheels(wheels: Array[VehicleWheel3D]) -> void:
	for w in wheels:
		var list: Array = []
		for m in w.get_children():
			if m is MeshInstance3D:
				# Tire geometry is often baked off-center from the node origin, so spin
				# about the geometry's own center (in wheel space), not the node origin.
				var base: Transform3D = m.transform
				list.append([m, base, base * (m as MeshInstance3D).get_aabb().get_center()])
		_mesh_base[w] = list
		_spin_omega[w] = 0.0
		_spin_extra[w] = 0.0
		slip_intensity[w] = 0.0
		_slip_speed[w] = 0.0


func update_wheelspin(
	wheels: Array[VehicleWheel3D],
	forward_speed: float,
	engine_rpm: float,
	gear_ratio: float,
	drive_dir: float,
	clutch: float,
	throttle: float,
	force_spin: bool
) -> void:
	var delta := get_physics_process_delta_time()
	if delta <= 0.0:
		return

	for w in wheels:
		var r := w.wheel_radius
		if r <= 0.0:
			continue

		var roll := forward_speed / r
		var omega: float = _spin_omega.get(w, roll)
		var in_contact := w.is_in_contact()
		var grip := w.get_skidinfo() if in_contact else 1.0

		var driven := w.use_as_traction and gear_ratio > 0.0 and throttle > 0.05 and clutch > 0.1
		var slipping := driven and in_contact and (force_spin or grip < SKID_SLIP_THRESHOLD)

		if slipping:
			var engine_omega := engine_rpm * TAU / 60.0 / gear_ratio * clutch * drive_dir
			# Burnout pins the tire at engine speed; otherwise ground load holds it lower
			var spin_target := engine_omega if force_spin else lerpf(roll, engine_omega, SPIN_LOAD_FACTOR)
			var target := spin_target if absf(spin_target) > absf(roll) else roll
			omega = move_toward(omega, target, SPIN_ACCEL * delta)
		else:
			var rate := SPIN_DECAY if absf(omega) > absf(roll) else SPIN_CATCHUP
			omega = move_toward(omega, roll, rate * delta)

		_slip_speed[w] = absf(omega - roll) * r
		var spin_slip := 0.0
		if in_contact:
			spin_slip = clampf(absf(omega - roll) * r / SPIN_SLIP_FULL, 0.0, 1.0)
		slip_intensity[w] = maxf(1.0 - grip, spin_slip) if in_contact else 0.0

		var extra := fposmod(_spin_extra.get(w, 0.0) - (omega - roll) * delta, TAU)
		_spin_omega[w] = omega
		_spin_extra[w] = extra
		_apply_extra_rotation(w, extra)


func _apply_extra_rotation(w: VehicleWheel3D, extra: float) -> void:
	var rot := Basis(Vector3.RIGHT, extra)
	for entry in _mesh_base.get(w, []):
		var m: MeshInstance3D = entry[0]
		if not is_instance_valid(m):
			continue
		var pivot: Vector3 = entry[2]
		var spin := Transform3D(rot, pivot - rot * pivot)
		m.transform = spin * (entry[1] as Transform3D)


func get_slip_intensity(w: VehicleWheel3D) -> float:
	return slip_intensity.get(w, 0.0)


## Tire surface speed minus ground speed, m/s. Near 0 = rolling, large = spinning.
func get_slip_speed(w: VehicleWheel3D) -> float:
	return _slip_speed.get(w, 0.0)


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
	var forward_speed := local_vel.z

	# Very small rolling resistance (prevents infinite coast)
	var rolling_resistance := 0.015
	var resist_force := -forward_speed * rolling_resistance * vehicle.mass

	var force_vec := vehicle.global_transform.basis.z * resist_force
	vehicle.apply_central_force(force_vec)
