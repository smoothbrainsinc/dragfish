# pit_area_ui_controller.gd
# res://scripts/ui/pit_area_ui_controller.gd
#
# Owns the pit UI. Reads from VehicleConfig, writes back to VehicleConfig.
# No JSON. No GameManager wheel_modifications dict. No ambiguity.
# One thing does one thing:
#   - Load  → reads VehicleConfig wheel configs into spinboxes
#   - Edit  → writes spinbox value directly to the live WheelConfig resource AND the wheel node
#   - Save  → calls VehicleConfig.save() which writes the .tres to disk
#   - Reset → calls VehicleConfig.reset_to_class_stock(), reapplies to wheels, reloads spinboxes

extends Node

# ─── node refs ────────────────────────────────────────────────────────────────
@onready var race_button   = $"../PropertyLabels/HBoxContainer/Panel/ColorRect/GridContainer/Start"
@onready var select_button = $"../PropertyLabels/HBoxContainer/Panel/ColorRect/GridContainer/Select"
@onready var reset_button  = $"../PropertyLabels/HBoxContainer/Panel/ColorRect/GridContainer/Reset"
@onready var save_button   = $"../PropertyLabels/HBoxContainer/Panel/ColorRect/GridContainer/Save"

# ─── state ────────────────────────────────────────────────────────────────────
var current_vehicle: VehicleBody3D = null
var wheels: Array[VehicleWheel3D]  = []
var vehicle_config: VehicleConfig  = null   # the single source of truth


# ─── boot ─────────────────────────────────────────────────────────────────────
func _ready() -> void:
	if not GameManager.player_car_config:
		push_error("[PitUI] No vehicle config in GameManager.")
		return
	vehicle_config = ResourceLoader.load(
		GameManager.player_car_config.resource_path,
		"",
		ResourceLoader.CACHE_MODE_IGNORE
	) as VehicleConfig
	_load_vehicle()


# ─── vehicle loading ───────────────────────────────────────────────────────────
func _load_vehicle() -> void:
	var vehicle_scene = load(vehicle_config.scene_path)
	if not vehicle_scene:
		push_error("[PitUI] Failed to load scene: " + vehicle_config.scene_path)
		return

	current_vehicle = vehicle_scene.instantiate()
	current_vehicle.freeze = true
	_disable_scripts(current_vehicle)

	var subviewport = get_parent().get_node_or_null(
		"PropertyLabels/HBoxContainer/Panel/CarImage/SubViewport"
	)
	if subviewport:
		subviewport.add_child(current_vehicle)
		current_vehicle.position = Vector3.ZERO
		current_vehicle.rotation_degrees.y = 30
	else:
		push_error("[PitUI] SubViewport not found.")
		return

	wheels = _find_wheels(current_vehicle)
	if wheels.size() < 4:
		push_error("[PitUI] Need 4 wheels, found: %d" % wheels.size())
		return

	vehicle_config.apply_to_vehicle(current_vehicle)

	var locked = not vehicle_config.is_tunable
	_set_spinboxes_editable(not locked)
	_load_spinboxes()
	_connect_spinboxes()

# ─── spinbox population ────────────────────────────────────────────────────────
## Read current wheel values into the spinboxes.
## Wheels are already set from the config, so just read the nodes.
func _load_spinboxes() -> void:
	var base = $"../PropertyLabels/HBoxContainer/PropertyLabels/ColorRect/3dMotion/MotionSection"

	_set_row(base.get_node("EngineForceContainer"), "engine_force")
	_set_row(base.get_node("BrakeContainer"),       "brake")
	_set_row(base.get_node("SteeringContainer"),    "steering")

	var ws = base.get_node("Wheel/WheelSection")
	_set_row(ws.get_node("RollContainer"),      "wheel_roll_influence")
	_set_row(ws.get_node("RadiusContainer"),    "wheel_radius")
	_set_row(ws.get_node("RestContainer"),      "wheel_rest_length")
	_set_row(ws.get_node("FrictionContainer"),  "wheel_friction_slip")

	var ss = ws.get_node("Suspension/SuspensionSection")
	_set_row(ss.get_node("TravelContainer"),    "suspension_travel")
	_set_row(ss.get_node("StifnessContainer"),  "suspension_stiffness")
	_set_row(ss.get_node("MaxForceContainer"),  "suspension_max_force")

	var ds = ss.get_node("Damping/DampingSection")
	_set_row(ds.get_node("CompressionContainer"), "damping_compression")
	_set_row(ds.get_node("RelaxationContainer"),  "damping_relaxation")


func _set_row(container: HBoxContainer, wheel_property: String) -> void:
	# SpinBox4=FL, SpinBox3=FR, SpinBox=RL, SpinBox2=RR
	var boxes = [
		container.get_node_or_null("SpinBox4"),
		container.get_node_or_null("SpinBox3"),
		container.get_node_or_null("SpinBox"),
		container.get_node_or_null("SpinBox2"),
	]
	for i in range(min(4, wheels.size())):
		if boxes[i]:
			boxes[i].set_value_no_signal(wheels[i].get(wheel_property))


# ─── spinbox signals ───────────────────────────────────────────────────────────
func _connect_spinboxes() -> void:
	var base = $"../PropertyLabels/HBoxContainer/PropertyLabels/ColorRect/3dMotion/MotionSection"

	_connect_row(base.get_node("EngineForceContainer"), "engine_force")
	_connect_row(base.get_node("BrakeContainer"),       "brake")
	_connect_row(base.get_node("SteeringContainer"),    "steering")

	var ws = base.get_node("Wheel/WheelSection")
	_connect_row(ws.get_node("RollContainer"),      "wheel_roll_influence")
	_connect_row(ws.get_node("RadiusContainer"),    "wheel_radius")
	_connect_row(ws.get_node("RestContainer"),      "wheel_rest_length")
	_connect_row(ws.get_node("FrictionContainer"),  "wheel_friction_slip")

	var ss = ws.get_node("Suspension/SuspensionSection")
	_connect_row(ss.get_node("TravelContainer"),    "suspension_travel")
	_connect_row(ss.get_node("StifnessContainer"),  "suspension_stiffness")
	_connect_row(ss.get_node("MaxForceContainer"),  "suspension_max_force")

	var ds = ss.get_node("Damping/DampingSection")
	_connect_row(ds.get_node("CompressionContainer"), "damping_compression")
	_connect_row(ds.get_node("RelaxationContainer"),  "damping_relaxation")


func _connect_row(container: HBoxContainer, wheel_property: String) -> void:
	var boxes = [
		container.get_node_or_null("SpinBox4"),
		container.get_node_or_null("SpinBox3"),
		container.get_node_or_null("SpinBox"),
		container.get_node_or_null("SpinBox2"),
	]
	for i in range(min(4, boxes.size())):
		if boxes[i]:
			boxes[i].value_changed.connect(
				func(val: float): _on_value_changed(i, wheel_property, val)
			)


# ─── live edit ────────────────────────────────────────────────────────────────
## Called every time a spinbox changes.
## Writes to the wheel node (preview) AND the WheelConfig resource.
## The resource is dirty but not saved until the player hits SAVE.
func _on_value_changed(wheel_idx: int, wheel_property: String, value: float) -> void:
	if wheel_idx >= wheels.size():
		return

	# Write to the preview wheel node
	wheels[wheel_idx].set(wheel_property, value)

	# Write to the correct WheelConfig (front = steering wheels, rear = traction wheels)
	# Map wheel_property (VehicleWheel3D name) → WheelConfig property name
	var config_property = _wheel_prop_to_config_prop(wheel_property)
	if config_property.is_empty():
		return

	var cfg = _config_for_wheel(wheel_idx)
	if cfg:
		cfg.set(config_property, value)


## Returns the WheelConfig that owns wheel at index.
func _config_for_wheel(wheel_idx: int) -> WheelConfig:
	if wheel_idx >= wheels.size():
		return null
	return vehicle_config.front_wheel_config if wheels[wheel_idx].use_as_steering \
		else vehicle_config.rear_wheel_config


## VehicleWheel3D property names differ from WheelConfig property names.
## This is the only place that mapping lives.
func _wheel_prop_to_config_prop(wheel_property: String) -> String:
	match wheel_property:
		"engine_force":         return "engine_force"
		"brake":                return "brake"
		"steering":             return "steering"
		"wheel_roll_influence": return "roll_influence"
		"wheel_radius":         return "radius"
		"wheel_rest_length":    return "rest_length"
		"wheel_friction_slip":  return "friction_slip"
		"suspension_travel":    return "suspension_travel"
		"suspension_stiffness": return "suspension_stiffness"
		"suspension_max_force": return "suspension_max_force"
		"damping_compression":  return "damping_compression"
		"damping_relaxation":   return "damping_relaxation"
	push_error("[PitUI] Unknown wheel property: " + wheel_property)
	return ""


# ─── buttons ──────────────────────────────────────────────────────────────────
func _on_save_pressed() -> void:
	if not vehicle_config:
		push_error("[PitUI] No vehicle_config to save.")
		return
	vehicle_config.save()
	print("[PitUI] Saved.")


func _on_reset_pressed() -> void:
	if not vehicle_config:
		return
	vehicle_config.reset_to_class_stock()
	vehicle_config.apply_to_vehicle(current_vehicle)
	_load_spinboxes()
	print("[PitUI] Reset to class stock.")


func _on_race_pressed() -> void:
	# Config is already up to date in memory.
	# Vehicle script will call vehicle_config.apply_to_vehicle() on _ready().
	get_tree().change_scene_to_file("res://scenes/pluto_raceway.tscn")


func _on_select_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/new_car_selection_screen.tscn")


# ─── helpers ──────────────────────────────────────────────────────────────────
func _find_wheels(node: Node) -> Array[VehicleWheel3D]:
	var found: Array[VehicleWheel3D] = []
	if node is VehicleWheel3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_find_wheels(child))
	return found


func _disable_scripts(node: Node) -> void:
	if node.has_method("set_process"):
		node.set_process(false)
		node.set_physics_process(false)
		node.set_process_input(false)
	if node.get_script():
		var path: String = node.get_script().resource_path
		if "control" in path.to_lower() or "input" in path.to_lower():
			node.set_script(null)
	for child in node.get_children():
		_disable_scripts(child)


func _set_spinboxes_editable(editable: bool) -> void:
	# Walk every SpinBox under the pit UI and set editability
	var root = get_parent().get_node_or_null(
		"PropertyLabels/HBoxContainer/PropertyLabels/ColorRect/3dMotion"
	)
	if not root:
		return
	for node in root.find_children("SpinBox*", "SpinBox", true, false):
		(node as SpinBox).editable = editable
