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
	vehicle = get_tree().get_first_node_in_group("player_vehicle") as VehicleController
	if vehicle == null:
		push_warning("HUD: no node in group 'player_vehicle' found")
		return

	# EngineModule and TransmissionModule are created in VehicleController's
	# _ready-time setup, so by the time the HUD's _ready runs, vehicle.engine
	# and vehicle.transmission should already exist — but if your HUD scene
	# can instantiate before the vehicle spawns, connect these lazily instead
	# (e.g. from race_manager once player_vehicle is assigned).
	vehicle.engine.rpm_changed.connect(_on_rpm_changed)
	vehicle.transmission.gear_changed.connect(_on_gear_changed)

	# Prime the gauges/labels with current values instead of waiting for the
	# first signal emission.
	_on_rpm_changed(vehicle.engine.current_rpm)
	_on_gear_changed(vehicle.transmission.get_gear_number())

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
