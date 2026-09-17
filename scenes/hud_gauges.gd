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
	vehicle = await _wait_for_player_vehicle()
	tach.value_max = vehicle.engine.config.redline_rpm

	vehicle.engine.rpm_changed.connect(_on_rpm_changed)
	vehicle.transmission.gear_changed.connect(_on_gear_changed)

	# Prime the gauges/labels with current values instead of waiting for the
	# first signal emission.
	_on_rpm_changed(vehicle.engine.current_rpm)
	_on_gear_changed(vehicle.transmission.get_gear_number())

func _wait_for_player_vehicle() -> VehicleController:
	# race_manager.gd spawns and groups the vehicle asynchronously in its own
	# _ready() (await process_frame, then await spawn_vehicles()), so it
	# doesn't exist yet when this HUD's _ready() first runs. Poll until it
	# does instead of failing once and giving up.
	var v := get_tree().get_first_node_in_group("player_vehicle") as VehicleController
	while v == null:
		await get_tree().process_frame
		v = get_tree().get_first_node_in_group("player_vehicle") as VehicleController
	return v

func _process(_delta: float) -> void:
	if vehicle == null:
		return
	# No speed_changed signal exists on VehicleController — poll it.
	var speed_mph: float = vehicle.get_forward_speed() * MPS_TO_MPH
	speedo.set_value(speed_mph)
	speed_label.text = "%d MPH" % int(speed_mph)

func _on_rpm_changed(rpm: float) -> void:
	tach.set_value(rpm)
	rpm_label.text = "%d RPM" % int(rpm)

func _on_gear_changed(new_gear: int) -> void:
	# TransmissionModule has no reverse/neutral state — new_gear is always
	# 1-indexed positive (1st gear and up).
	gear_label.text = str(new_gear)
