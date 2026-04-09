# VehicleClassConfig.gd
# res://scripts/game/vehicle/resources/VehicleClassConfig.gd
#
# One .tres per class (meth_head, tweeker, broke_fuck, etc.)
# Holds the stock wheel configs that ALL cars in this class start from.
# This file is NEVER written to at runtime. It is read-only truth.
# When a player resets in the pit, their VehicleConfig duplicates from here.

class_name VehicleClassConfig
extends Resource

@export var class_name_id: String = ""       # internal id e.g. "meth_head"
@export var display_name: String = ""        # shown in UI e.g. "Meth Head"
@export var description: String = ""

@export_group("Stock Wheel Configs")
## The baseline front wheel physics for every car in this class.
## Duplicate this into VehicleConfig — never write to this directly.
@export var stock_front_wheel_config: WheelConfig
## The baseline rear wheel physics for every car in this class.
@export var stock_rear_wheel_config: WheelConfig

@export_group("Class Rules")
## Which properties the pit UI is allowed to show/edit for this class.
## Empty array = all properties are tunable.
## Populated = only these properties show up in the pit.
@export var tunable_properties: Array[String] = []

## Hard limits per property. Key = property name, Value = Vector2(min, max).
## Pit spinboxes clamp to these. If a property isn't listed, no limit applies.
@export var property_limits: Dictionary = {}
