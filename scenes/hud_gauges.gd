extends CanvasLayer

## Matches your current scene tree:
## HUD (CanvasLayer, this script)
##  └─ Gauges (Control)
##      ├─ TachContainer (Gauge2D)
##      │   ├─ Face (TextureRect)
##      │   └─ Needle (TextureRect)
##      ├─ SpeedContainer (Gauge2D)     # duplicate of TachContainer
##      │   ├─ Face
##      │   └─ Needle
##      ├─ RPMLabel (Label)
##      ├─ SpeedLabel (Label)
##      └─ GearLabel (Label)

@onready var tach: Gauge2D = $Gauges/TachContainer
@onready var speedo: Gauge2D = $Gauges/SpeedContainer
@onready var rpm_label: Label = $Gauges/RPMLabel
@onready var speed_label: Label = $Gauges/SpeedLabel
@onready var gear_label: Label = $Gauges/GearLabel

const MPS_TO_MPH := 2.23694

var vehicle: VehicleController = null

func _ready() -> void:
	pass  # binding now happens lazily in _process(), so it survives rematches


func _process(_delta: float) -> void:
	# Re-find the vehicle if we don't have one, or the one we had got freed
	# (e.g. race_manager.gd deletes and respawns it on rematch).
	if vehicle == null or not is_instance_valid(vehicle):
		var found := get_tree().get_first_node_in_group("player_vehicle") as VehicleController
		if found == null:
			return
		vehicle = found
		_bind_vehicle(vehicle)

	var speed_mph: float = vehicle.get_forward_speed() * MPS_TO_MPH
	speedo.set_value(speed_mph)
	speed_label.text = "%d MPH" % int(speed_mph)


func _bind_vehicle(v: VehicleController) -> void:
	tach.value_max = v.engine.config.redline_rpm
	v.engine.rpm_changed.connect(_on_rpm_changed)
	v.transmission.gear_changed.connect(_on_gear_changed)

	# Prime the gauges/labels with current values instead of waiting for the
	# first signal emission.
	_on_rpm_changed(v.engine.current_rpm)
	_on_gear_changed(v.transmission.get_gear_number())


func _on_rpm_changed(rpm: float) -> void:
	tach.set_value(rpm)
	rpm_label.text = "%d RPM" % int(rpm)


func _on_gear_changed(new_gear: int) -> void:
	# TransmissionModule has no reverse/neutral state — new_gear is always
	# 1-indexed positive (1st gear and up).
	gear_label.text = str(new_gear)
