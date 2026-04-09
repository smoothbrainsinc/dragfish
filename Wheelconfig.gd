# WheelConfig.gd
# res://scripts/game/vehicle/resources/WheelConfig.gd
#
# Holds the physics values for one axle (front or rear).
# This is the single source of truth for all wheel physics.
# The .tscn wheel node values are ignored — _ready() always writes from here.

class_name WheelConfig
extends Resource

@export_group("Motion")
@export var engine_force: float = 0.0
@export var brake: float = 0.0
@export var steering: float = 0.0

@export_group("Wheel")
@export var roll_influence: float = 0.1
@export var radius: float = 0.5
@export var rest_length: float = 0.15
@export var friction_slip: float = 10.5

@export_group("Suspension")
@export var suspension_travel: float = 0.2
@export var suspension_stiffness: float = 5.88
@export var suspension_max_force: float = 6000.0

@export_group("Damping")
@export var damping_compression: float = 0.83
@export var damping_relaxation: float = 0.88


## Apply this config to a VehicleWheel3D node.
func apply_to_wheel(wheel: VehicleWheel3D) -> void:
	wheel.engine_force          = engine_force
	wheel.brake                 = brake
	wheel.steering              = steering
	wheel.wheel_roll_influence  = roll_influence
	wheel.wheel_radius          = radius
	wheel.wheel_rest_length     = rest_length
	wheel.wheel_friction_slip   = friction_slip
	wheel.suspension_travel     = suspension_travel
	wheel.suspension_stiffness  = suspension_stiffness
	wheel.suspension_max_force  = suspension_max_force
	wheel.damping_compression   = damping_compression
	wheel.damping_relaxation    = damping_relaxation


## Read current values FROM a wheel INTO this config.
## Used by the pit to snapshot what's on the car before saving.
func read_from_wheel(wheel: VehicleWheel3D) -> void:
	engine_force        = wheel.engine_force
	brake               = wheel.brake
	steering            = wheel.steering
	roll_influence      = wheel.wheel_roll_influence
	radius              = wheel.wheel_radius
	rest_length         = wheel.wheel_rest_length
	friction_slip       = wheel.wheel_friction_slip
	suspension_travel   = wheel.suspension_travel
	suspension_stiffness = wheel.suspension_stiffness
	suspension_max_force = wheel.suspension_max_force
	damping_compression = wheel.damping_compression
	damping_relaxation  = wheel.damping_relaxation
