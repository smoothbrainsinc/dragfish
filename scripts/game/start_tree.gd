extends Node3D
## NHRA Christmas Tree - Signal-based, decoupled design

enum TreeType {
	PRO_TREE,    # All ambers at once, 0.4s to green
	FULL_TREE,   # Sequential ambers, 0.5s each
	PRACTICE     # No penalties, for testing
}

@export var tree_type: TreeType = TreeType.PRO_TREE
@export var random_delay: bool = true
@export var emission_energy: float = 12.0
@export var omni_energy: float = 8.0

signal tree_started
signal green_light

const PRO_AMBER_TIME := 0.4
const FULL_AMBER_INTERVAL := 0.5
const GREEN_HOLD_TIME := 2.0

# Node-name fragment -> light key. Order matters: "prestage" before "stage".
const NAME_KEYS := [
	["prestage", "prestage"], ["stage", "stage"],
	["three", "amber3"], ["two", "amber2"], ["one", "amber1"],
	["go", "green"], ["foul", "red"],
]
const AMBER := Color(1.0, 0.6, 0.0)
const YELLOW := Color(1.0, 1.0, 0.0)
const COLORS := {
	"green": Color(0, 1, 0), "red": Color(1, 0, 0),
	"prestage": YELLOW, "stage": YELLOW,
	"amber1": AMBER, "amber2": AMBER, "amber3": AMBER,
}

var race_active := false
var tree_sequence_running := false

# Lane keys (1 = right, 2 = left) match timing_system.gd.
var lights := {1: {}, 2: {}}      # lane -> key -> MeshInstance3D
var materials := {1: {}, 2: {}}   # lane -> key -> StandardMaterial3D
var omnis := {1: {}, 2: {}}       # lane -> key -> OmniLight3D


func _ready() -> void:
	add_to_group("start_tree")
	find_all_lights(self)
	find_all_omnis(self)
	turn_all_lights_off()
	print("[Tree] Ready. Type: %s" % TreeType.keys()[tree_type])


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and not tree_sequence_running:
		start_tree_sequence()


# ============================================================================
# PUBLIC API
# ============================================================================

func trigger_red_light(lane: int) -> void:
	set_light(lane, "red", true)
	print("[Tree] LANE %d - RED LIGHT (FOUL START)" % lane)


func reset_tree() -> void:
	turn_all_lights_off()
	race_active = false
	tree_sequence_running = false


# ============================================================================
# TREE SEQUENCES
# ============================================================================

func start_tree_sequence() -> void:
	if tree_sequence_running:
		return
	tree_sequence_running = true
	race_active = true
	tree_started.emit()

	if random_delay:
		await get_tree().create_timer(randf_range(1.0, 3.0)).timeout

	if tree_type == TreeType.PRO_TREE:
		await run_pro_tree()
	else:
		await run_full_tree()

	await get_tree().create_timer(GREEN_HOLD_TIME).timeout
	turn_all_lights_off()
	tree_sequence_running = false


func run_pro_tree() -> void:
	set_lights(["amber3", "amber2", "amber1"], true)
	await get_tree().create_timer(PRO_AMBER_TIME).timeout
	_go()


func run_full_tree() -> void:
	for amber in ["amber3", "amber2", "amber1"]:
		set_lights([amber], true)
		await get_tree().create_timer(FULL_AMBER_INTERVAL).timeout
	_go()


func _go() -> void:
	set_lights(["amber3", "amber2", "amber1"], false)
	set_lights(["green"], true)
	green_light.emit()


# ============================================================================
# LIGHT MANAGEMENT
# ============================================================================

## Returns [lane, key] for a node name, or [] if it isn't a lane light.
func _parse_name(node_name: String) -> Array:
	var n := node_name.to_lower()
	var lane := 0
	if "right" in n:
		lane = 1
	elif "left" in n:
		lane = 2
	if lane == 0:
		return []
	for pair in NAME_KEYS:
		if pair[0] in n:
			return [lane, pair[1]]
	return []


func find_all_lights(node: Node) -> void:
	if node is MeshInstance3D and node.name.begins_with("lens_"):
		var parsed := _parse_name(node.name)
		if not parsed.is_empty():
			var mesh := node as MeshInstance3D
			var src := mesh.get_active_material(0)
			var mat: StandardMaterial3D = src.duplicate() if src is StandardMaterial3D else StandardMaterial3D.new()
			mesh.set_surface_override_material(0, mat)
			lights[parsed[0]][parsed[1]] = mesh
			materials[parsed[0]][parsed[1]] = mat
	for child in node.get_children():
		find_all_lights(child)


func find_all_omnis(node: Node) -> void:
	if node is OmniLight3D:
		var parsed := _parse_name(node.name)
		if not parsed.is_empty():
			omnis[parsed[0]][parsed[1]] = node
	for child in node.get_children():
		find_all_omnis(child)


func set_lights(keys: Array, on: bool) -> void:
	for lane in lights.keys():
		for key in keys:
			set_light(lane, key, on)


func set_light(lane: int, light_name: String, on: bool) -> void:
	if not materials.has(lane) or not materials[lane].has(light_name):
		return

	var mat: StandardMaterial3D = materials[lane][light_name]
	mat.emission_enabled = on
	if on:
		mat.emission = COLORS[light_name]
		mat.emission_energy_multiplier = emission_energy

	if omnis[lane].has(light_name):
		var omni: OmniLight3D = omnis[lane][light_name]
		omni.light_energy = omni_energy if on else 0.0


func turn_all_lights_off() -> void:
	for lane in lights.keys():
		for key in lights[lane].keys():
			set_light(lane, key, false)
