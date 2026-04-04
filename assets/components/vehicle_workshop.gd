extends Control

@onready var properties_list : VBoxContainer = $MainSplitter/TuningArea/TuningScroll/PropertiesList
@onready var viewport : SubViewport = $MainSplitter/PreviewPanel/CarViewport/CarSubViewport

var wheel_row_scene := preload("res://assets/components/WheelPropertyRow.tscn")
var current_vehicle : VehicleBody3D = null
var wheels : Array[VehicleWheel3D] = []

# ─────────────────────────────────────
# The one and only tuning definition
# ─────────────────────────────────────
const TUNING := [
	["engine_force",         "Engine Force",         0.0,   10000.0,  10.0],
	["brake",                "Brake Force",          0.0,    5000.0,   5.0],
	["steering",             "Steering",            -1.0,      1.0,   0.01],
	["wheel_roll_influence", "Roll Influence",      0.0,      10.0,   0.01],
	["wheel_radius",         "Wheel Radius",        0.2,       2.0,   0.01],
	["wheel_rest_length",    "Rest Length",         0.01,      1.0, 0.001],
	["wheel_friction_slip",  "Friction Slip",       0.1,     500.0,   0.5],
	["suspension_travel",    "Suspension Travel",   0.01,      1.0, 0.001],
	["suspension_stiffness", "Stiffness",           1.0,     500.0,   0.1],
	["suspension_max_force", "Max Force",         1000.0,  50000.0, 100.0],
	["damping_compression",  "Damping Compression",0.1,      10.0,  0.01],
	["damping_relaxation",   "Damping Relaxation",  0.1,      10.0,  0.01],
]

func _ready() -> void:
	_load_current_car()

func _load_current_car() -> void:
	if not GameManager.player_car_data or not GameManager.player_car_data.has("scene_path"):
		push_error("No car selected!")
		return

	var packed : PackedScene = load(GameManager.player_car_data.scene_path)
	current_vehicle = packed.instantiate()
	current_vehicle.freeze = true

	_remove_control_scripts(current_vehicle)

	viewport.add_child(current_vehicle)
	current_vehicle.rotation_degrees.y = 30

	wheels = _find_all_wheels_sorted(current_vehicle)
	print("[Workshop] Found ", wheels.size(), " wheels")

	_build_tuning_ui()

func _build_tuning_ui() -> void:
	for child in properties_list.get_children():
		child.queue_free()

	for def in TUNING:
		var row : WheelPropertyRow = wheel_row_scene.instantiate()

		row.property_name   = def[0]
		row.display_name    = def[1]
		row.min_value       = def[2]
		row.max_value       = def[3]
		row.step            = def[4]
		row.allow_greater   = true
		row.allow_lesser    = true

		properties_list.add_child(row)
		row.setup(wheels)

func _remove_control_scripts(node: Node) -> void:
	if node.script and "control" in node.script.resource_path.get_file().to_lower():
		node.set_script(null)
	for child in node.get_children():
		_remove_control_scripts(child)

func _find_all_wheels_sorted(root: Node) -> Array[VehicleWheel3D]:
	var fl = root.get_node_or_null("wheelFL")
	var fr = root.get_node_or_null("wheelFR")
	var rl = root.get_node_or_null("wheelRL")
	var rr = root.get_node_or_null("wheelRR")
	
	if fl and fr and rl and rr:
		return [fl, fr, rl, rr]
	
	var found: Array[VehicleWheel3D] = []
	if root is VehicleWheel3D:
		found.append(root)
	for child in root.get_children():
		found += _find_all_wheels_sorted(child)
	found.sort_custom(func(a,b): return a.name.naturalnocasecmp_to(b.name) < 0)
	return found

# ─────────────────────────────────────
# Buttons
# ─────────────────────────────────────
func _on_race_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/raceway.tscn")

func _on_select_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/car_selection_screen.tscn")

func _on_reset_pressed() -> void:
	get_tree().reload_current_scene()

func _on_save_to_scene_pressed() -> void:
	if not current_vehicle or not GameManager.player_car_data.has("scene_path"):
		return
	
	var packed := PackedScene.new()
	packed.pack(current_vehicle)
	var path : String = GameManager.player_car_data.scene_path
	var err := ResourceSaver.save(packed, path)
	if err == OK:
		print("[Workshop] PERMANENTLY saved tuning to: ", path)
	else:
		push_error("Failed to save scene: %s (error %d)" % [path, err])
