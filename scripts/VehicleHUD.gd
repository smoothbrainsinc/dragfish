extends Control
class_name VehicleHUD

@export var show_rpm := true
@export var show_gear := true
@export var show_speed := true

# UI Labels
@onready var rpm_label: Label = $VBoxContainer/RPMLabel
@onready var gear_label: Label = $VBoxContainer/GearLabel
@onready var speed_label: Label = $VBoxContainer/SpeedLabel

var vehicle: VehicleController = null

func set_vehicle(v: VehicleController) -> void:
	vehicle = v

func _process(_delta: float) -> void:
	if vehicle == null:
		return
	
	# --- RPM ---
	if show_rpm:
		var rpm = vehicle.engine.current_rpm  # ← Inside engine module
		rpm_label.text = "RPM: %d" % rpm
	
	# --- Gear ---
	if show_gear:
		gear_label.text = "GEAR: %s" % vehicle.transmission.get_gear_string()
	
	# --- Speed ---
	if show_speed:
		var speed_mph = vehicle.forward_speed * 2.23694  # ← Use forward_speed property
		speed_label.text = "SPEED: %.1f mph" % speed_mph
