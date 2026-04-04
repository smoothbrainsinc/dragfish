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
		var gear_text = "1"
		var gear_index = vehicle.transmission.get_gear_index()  # ← Inside transmission module
		if gear_index > 0:
			gear_text = str(gear_index + 1)
		gear_label.text = "GEAR: %s" % gear_text
	
	# --- Speed ---
	if show_speed:
		var speed_mph = vehicle.forward_speed * 2.23694  # ← Use forward_speed property
		speed_label.text = "SPEED: %.1f mph" % speed_mph
