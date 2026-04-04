# scripts/vehicle/visuals/VehicleVisuals.gd
extends Node

@export var vehicle_controller: VehicleController
@export var tire_meshes: Array[Node3D]  # [fl, fr, rl, rr]
@export var exhaust_flame: GPUParticles3D
@export var tire_smoke: CPUParticles3D

func _ready() -> void:
	if not vehicle_controller:
		vehicle_controller = get_parent() as VehicleController
	assert(vehicle_controller, "VehicleVisuals requires a VehicleController parent")

func _physics_process(delta: float) -> void:
	if not vehicle_controller.initialized:
		return
	_sync_tire_visuals()
	_update_exhaust_flames()
	_update_tire_smoke()

func _sync_tire_visuals() -> void:
	var wheels = vehicle_controller.all_wheels
	for i in range(min(wheels.size(), tire_meshes.size())):
		var wheel = wheels[i]
		var mesh = tire_meshes[i]
		if not mesh:
			continue
		
		# Position: match wheel's local offset + suspension travel
		var local_pos = Vector3(wheel.position.x, -wheel.suspension_travel, wheel.position.z)
		mesh.position = local_pos
		
		# Rotation: rolling based on forward speed
		var circumference = TAU * wheel.wheel_radius
		if circumference > 0.01:
			var rotations_per_sec = vehicle_controller.forward_speed / circumference
			var delta_rot = rotations_per_sec * get_physics_process_delta_time()
			mesh.rotate_x(-delta_rot)

func _update_exhaust_flames() -> void:
	if not exhaust_flame:
		return
	
	var rpm_percentage = vehicle_controller.engine.current_rpm / vehicle_controller.engine.config.redline_rpm
	if rpm_percentage > 0.8:
		exhaust_flame.emitting = true
		exhaust_flame.scale = Vector3(1, 1, 1) * rpm_percentage
	else:
		exhaust_flame.emitting = false

func _update_tire_smoke() -> void:
	if not tire_smoke:
		return
	
	var slip_sum = 0.0
	for w in vehicle_controller.all_wheels:
		slip_sum += abs(w.get_skid_info().x)
	
	if slip_sum > 0.5:  # Adjust threshold as needed
		tire_smoke.emitting = true
		tire_smoke.scale = Vector3(1, 1, 1) * (slip_sum / 2.0)
	else:
		tire_smoke.emitting = false
