# vehicle_base.gd  (or whatever your VehicleBody3D script is called)
# res://scripts/game/vehicle/vehicle_base.gd
#
# Snipped to show the critical part: applying config in _ready().
# Your full script goes here — just make sure apply_to_vehicle() is called
# before anything reads wheel values.

extends VehicleBody3D

## Set this in the .tscn inspector, pointing at the car's own VehicleConfig .tres
@export var config: VehicleConfig


func _ready() -> void:
	if not config:
		push_error("[Vehicle] No VehicleConfig set on %s!" % name)
		return

	# Apply mass / CoM from config
	mass = config.mass
	center_of_mass_mode = CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = config.center_of_mass_offset

	# Apply wheel physics — this overwrites anything baked into the .tscn
	config.apply_to_vehicle(self)

	# Everything else your _ready() does goes after this line
