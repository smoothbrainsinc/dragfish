# VehicleConfig.gd
# res://scripts/game/vehicle/resources/VehicleConfig.gd
#
# Per-car resource. One .tres file per vehicle.
# Stock values come from the class .tres (VehicleClassConfig).
# Player pit changes are saved back into THIS file.
# The class .tres is never touched after you author it.

class_name VehicleConfig
extends Resource

@export_group("Identity")
@export var vehicle_name: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var vehicle_class: VehicleClassConfig  # which class this car belongs to

@export_group("Body")
@export var mass: float = 1000.0
@export var center_of_mass_offset: Vector3 = Vector3.ZERO
@export var drag_coefficient: float = 0.3
@export var frontal_area: float = 2.0
@export var downforce_coefficient: float = 0.0

@export_group("Steering & Brakes")
@export var max_steer_angle: float = 0.4
@export var brake_force: float = 1000.0

@export_group("Wheel Configs")
## Physics values for the front axle. Pit edits land here.
@export var front_wheel_config: WheelConfig
## Physics values for the rear axle. Pit edits land here.
@export var rear_wheel_config: WheelConfig

@export_group("Powertrain")
@export var engine: EngineConfig
@export var transmission: TransmissionConfig
@export var front_tires: TireConfig
@export var rear_tires: TireConfig

@export_group("AI")
@export var ai_reaction_time_min: float = 0.1
@export var ai_reaction_time_max: float = 0.3
@export var ai_shift_strategy: int = 0
@export var ai_consistency: float = 0.05

@export_group("Rules")
## If false, the pit UI locks all spinboxes for this car.
@export var is_tunable: bool = true


## Apply both wheel configs to the wheels on a VehicleBody3D.
## Call this from the vehicle's _ready(). This is the only place
## wheel physics values are written — never rely on .tscn baked values.
func apply_to_vehicle(vehicle: VehicleBody3D) -> void:
	for child in vehicle.get_children():
		if not child is VehicleWheel3D:
			continue
		if child.use_as_steering:
			front_wheel_config.apply_to_wheel(child)
		else:
			rear_wheel_config.apply_to_wheel(child)


## Reset this car's wheel configs back to the class stock values.
## Duplicates so the class stock is never modified.
func reset_to_class_stock() -> void:
	if not vehicle_class:
		push_error("[VehicleConfig] No vehicle_class set on %s — cannot reset." % vehicle_name)
		return
	front_wheel_config = vehicle_class.stock_front_wheel_config.duplicate(true)
	rear_wheel_config  = vehicle_class.stock_rear_wheel_config.duplicate(true)


## Save this config back to its own .tres file.
## This is what SAVE in the pit calls.
func save() -> void:
	if resource_path.is_empty():
		push_error("[VehicleConfig] resource_path is empty — cannot save %s." % vehicle_name)
		return
	var err = ResourceSaver.save(self, resource_path)
	if err != OK:
		push_error("[VehicleConfig] Failed to save %s: error %d" % [vehicle_name, err])
	else:
		print("[VehicleConfig] Saved: %s" % resource_path)
