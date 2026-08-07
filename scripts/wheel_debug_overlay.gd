extends CanvasLayer

## Corner-wheel debug overlay. Player-only. Reads live off the player_vehicle
## group's VehicleController and its wheelFL/wheelFR/wheelRL/wheelRR children.
## Toggle: Input Map action "toggle_wheel_debug" (bind this in Project Settings,
## separate from the old dashboard's ui_home).
## Expand/collapse: click a corner panel to toggle its own expanded dump.

const CORNER_NAMES := ["FL", "FR", "RL", "RR"]

var player_vehicle: VehicleController = null
var wheels: Dictionary = {}          # corner -> VehicleWheel3D
var panels: Dictionary = {}          # corner -> PanelContainer
var compact_labels: Dictionary = {}  # corner -> Label
var expanded_labels: Dictionary = {} # corner -> Label
var expanded_state: Dictionary = {}  # corner -> bool


func _ready() -> void:
	visible = false

	for corner in CORNER_NAMES:
		var panel := find_child("Panel" + corner, true, false) as PanelContainer
		if panel == null:
			push_warning("[WheelDebugOverlay] Missing Panel%s node in scene." % corner)
			continue
		panels[corner] = panel
		compact_labels[corner] = panel.find_child("CompactLabel", true, false)
		expanded_labels[corner] = panel.find_child("ExpandedLabel", true, false)
		expanded_state[corner] = false
		if expanded_labels[corner]:
			expanded_labels[corner].visible = false
		panel.gui_input.connect(_on_panel_gui_input.bind(corner))


func _process(_delta: float) -> void:
	if not visible:
		return
	if player_vehicle == null or not is_instance_valid(player_vehicle):
		_find_player_vehicle()
		if player_vehicle == null:
			return
	if wheels.is_empty():
		_find_wheels()
	_update_panels()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_wheel_debug"):
		visible = not visible
		if visible and player_vehicle == null:
			_find_player_vehicle()
			_find_wheels()


func _find_player_vehicle() -> void:
	player_vehicle = get_tree().get_first_node_in_group("player_vehicle") as VehicleController


func _find_wheels() -> void:
	if player_vehicle == null:
		return
	for corner in CORNER_NAMES:
		var w := player_vehicle.find_child("wheel" + corner, true, false) as VehicleWheel3D
		if w:
			wheels[corner] = w
		else:
			push_warning("[WheelDebugOverlay] wheel%s not found on player_vehicle." % corner)


func _update_panels() -> void:
	for corner in CORNER_NAMES:
		if not wheels.has(corner):
			continue
		var w: VehicleWheel3D = wheels[corner]

		if compact_labels.get(corner):
			compact_labels[corner].text = _compact_text(w)

		if expanded_state.get(corner, false) and expanded_labels.get(corner):
			expanded_labels[corner].text = _expanded_text(w)


func _compact_text(w: VehicleWheel3D) -> String:
	var grip_pct := w.get_skidinfo() * 100.0
	return "RPM: %.0f\nGrip: %.0f%%\nContact: %s\nForce: %.0f N\nBrake: %.2f" % [
		w.get_rpm(),
		grip_pct,
		"yes" if w.is_in_contact() else "no",
		w.engine_force,
		w.brake,
	]


# These 8 are generic Node/Node3D bookkeeping properties, not wheel tuning
# knobs — every Node has them, so they're excluded by name rather than by
# an unverified inheritance-walk (no Godot binary here to test that against).
const NON_TUNING_PROPERTIES := [
	"unique_name_in_owner",
	"process_mode",
	"process_priority",
	"process_physics_priority",
	"process_thread_group",
	"physics_interpolation_mode",
	"auto_translate_mode",
	"editor_description",
	"rotation_edit_mode",
	"rotation_order",
	"top_level",
	"visible",
	"visibility_parent",
]


func _expanded_text(w: VehicleWheel3D) -> String:
	var lines: Array[String] = []
	for prop in w.get_property_list():
		if prop.usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		if prop.name in NON_TUNING_PROPERTIES:
			continue
		var value = w.get(prop.name)
		lines.append("%s: %s" % [prop.name, value])
	return "\n".join(lines)


func _on_panel_gui_input(event: InputEvent, corner: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		expanded_state[corner] = not expanded_state.get(corner, false)
		if expanded_labels.get(corner):
			expanded_labels[corner].visible = expanded_state[corner]
