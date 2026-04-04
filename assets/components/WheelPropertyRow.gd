# res://ui/WheelPropertyRow.gd
@tool
class_name WheelPropertyRow
extends HBoxContainer

@export var property_name : String = "engine_force"
@export var display_name : String = "Engine Force"

@export var min_value : float = 0.0
@export var max_value : float = 1000.0
@export var step : float = 0.01
@export var allow_greater : bool = true     # ← fixed
@export var allow_lesser : bool = true      # ← fixed

var wheels : Array[VehicleWheel3D] = []

@onready var spin_fr : SpinBox = $FR
@onready var spin_fl : SpinBox = $FL
@onready var spin_rl : SpinBox = $RL
@onready var spin_rr : SpinBox = $RR

func _ready() -> void:
	$Label.text = display_name
	
	for spin in [spin_fr, spin_fl, spin_rl, spin_rr]:
		spin.min_value = min_value
		spin.max_value = max_value
		spin.step = step
		spin.allow_greater = allow_greater
		spin.allow_lesser = allow_lesser
		spin.rounded = false

func setup(wheel_array: Array[VehicleWheel3D]) -> void:
	wheels = wheel_array
	_refresh_all_values()
	_connect_all_spins()

func _refresh_all_values() -> void:
	if wheels.size() < 4:
		return
	spin_fr.value = wheels[0].get(property_name)
	spin_fl.value = wheels[1].get(property_name)
	spin_rl.value = wheels[2].get(property_name)
	spin_rr.value = wheels[3].get(property_name)

func _connect_all_spins() -> void:
	spin_fr.value_changed.connect(func(v): _set_wheel_value(0, v))
	spin_fl.value_changed.connect(func(v): _set_wheel_value(1, v))
	spin_rl.value_changed.connect(func(v): _set_wheel_value(2, v))
	spin_rr.value_changed.connect(func(v): _set_wheel_value(3, v))

func _set_wheel_value(index: int, value: float) -> void:
	if index >= wheels.size():
		return
	wheels[index].set(property_name, value)
