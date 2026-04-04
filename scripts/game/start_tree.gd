extends Node3D
## NHRA Christmas Tree - Signal-based, decoupled design

enum TreeType {
	PRO_TREE,    # All ambers at once, 0.4s to green
	FULL_TREE,   # Sequential ambers, 0.5s each
	PRACTICE     # No penalties, for testing
}

@export var tree_type: TreeType = TreeType.PRO_TREE
@export var random_delay: bool = true

# === SIGNALS (What this tree tells the world) ===
signal tree_started              # Tree sequence beginning
signal green_light               # GO!
#signal race_complete             # Race finished
#signal request_red_light(lane: String)  # Someone else wants to trigger red light

# Tree timing constants
const PRO_AMBER_TIME = 0.4
const FULL_AMBER_TIME = 0.5
const FULL_AMBER_INTERVAL = 0.5

# Tree state
var race_active = false
var tree_sequence_running = false

# Light references
var lights = {
	"left": {},
	"right": {}
}
var light_nodes = {}


func _ready():
	add_to_group("start_tree")
	print("[Tree] NHRA Tree System initializing...")
	find_all_lights()
	add_omni_lights()
	turn_all_lights_off()
	print("[Tree] Ready. Type: %s" % TreeType.keys()[tree_type])
	print("[Tree] Press SPACEBAR to start the race")


func _input(event):
	if event.is_action_pressed("ui_accept") and not tree_sequence_running:
		start_tree_sequence()


# ============================================================================
# PUBLIC API (Can be called by other systems, but signals are preferred)
# ============================================================================

func trigger_red_light(lane: String):
	"""Trigger red light for a lane (called by external systems via signal)"""
	set_light(lane, "red", true)
	print("[Tree] %s LANE - RED LIGHT (FOUL START)" % lane.to_upper())


func reset_tree():
	"""Reset tree to initial state"""
	turn_all_lights_off()
	race_active = false
	tree_sequence_running = false
	print("[Tree] Reset complete")


# ============================================================================
# TREE SEQUENCES
# ============================================================================

func start_tree_sequence():
	"""Begin the tree countdown sequence"""
	if tree_sequence_running:
		return
	
	tree_sequence_running = true
	race_active = true
	emit_signal("tree_started")
	print("[Tree] === TREE SEQUENCE STARTING ===")
	
	# Random delay before tree starts
	if random_delay:
		var delay = randf_range(1.0, 3.0)
		print("[Tree] Delay: %.2f seconds" % delay)
		await get_tree().create_timer(delay).timeout
	
	if tree_type == TreeType.PRO_TREE:
		await run_pro_tree()
	else:
		await run_full_tree()


func run_pro_tree():
	"""Pro tree: All ambers at once, 0.4s to green"""
	print("[Tree] PRO TREE")
	
	# All three ambers simultaneously
	set_light("left", "amber3", true)
	set_light("left", "amber2", true)
	set_light("left", "amber1", true)
	set_light("right", "amber3", true)
	set_light("right", "amber2", true)
	set_light("right", "amber1", true)
	print("[Tree] All ambers ON")
	
	await get_tree().create_timer(PRO_AMBER_TIME).timeout
	
	# Turn off ambers
	set_light("left", "amber3", false)
	set_light("left", "amber2", false)
	set_light("left", "amber1", false)
	set_light("right", "amber3", false)
	set_light("right", "amber2", false)
	set_light("right", "amber1", false)
	
	# GREEN LIGHT!
	set_light("left", "green", true)
	set_light("right", "green", true)
	emit_signal("green_light")
	print("[Tree] === GREEN LIGHT - GO! ===")
	
	await get_tree().create_timer(2.0).timeout
	turn_all_lights_off()
	tree_sequence_running = false


func run_full_tree():
	"""Full tree: Sequential ambers, 0.5s each"""
	print("[Tree] FULL TREE (Sportsman)")
	
	# Top amber
	set_light("left", "amber3", true)
	set_light("right", "amber3", true)
	print("[Tree] Top amber ON")
	await get_tree().create_timer(FULL_AMBER_INTERVAL).timeout
	
	# Middle amber
	set_light("left", "amber2", true)
	set_light("right", "amber2", true)
	print("[Tree] Middle amber ON")
	await get_tree().create_timer(FULL_AMBER_INTERVAL).timeout
	
	# Bottom amber
	set_light("left", "amber1", true)
	set_light("right", "amber1", true)
	print("[Tree] Bottom amber ON")
	await get_tree().create_timer(FULL_AMBER_INTERVAL).timeout
	
	# Turn off all ambers
	set_light("left", "amber3", false)
	set_light("left", "amber2", false)
	set_light("left", "amber1", false)
	set_light("right", "amber3", false)
	set_light("right", "amber2", false)
	set_light("right", "amber1", false)
	
	# GREEN LIGHT!
	set_light("left", "green", true)
	set_light("right", "green", true)
	emit_signal("green_light")
	print("[Tree] === GREEN LIGHT - GO! ===")
	
	await get_tree().create_timer(2.0).timeout
	turn_all_lights_off()
	tree_sequence_running = false


# ============================================================================
# LIGHT MANAGEMENT (Internal implementation)
# ============================================================================

func find_all_lights():
	"""Scan tree for light meshes"""
	search_for_lights(self)
	print("[Tree] Found %d light meshes" % (lights["left"].size() + lights["right"].size()))


func search_for_lights(node):
	"""Recursively find light meshes"""
	var node_name = node.name.to_lower()
	
	if node is MeshInstance3D and "empty" not in node_name:
		var lane = ""
		if "left" in node_name:
			lane = "left"
		elif "right" in node_name:
			lane = "right"
		
		if lane != "":
			if "prestage" in node_name:
				lights[lane]["prestage"] = node
			elif "stage" in node_name:
				lights[lane]["stage"] = node
			elif "three" in node_name or "top" in node_name:
				lights[lane]["amber3"] = node
			elif "two" in node_name or "middle" in node_name:
				lights[lane]["amber2"] = node
			elif "one" in node_name or "bottom" in node_name:
				lights[lane]["amber1"] = node
			elif "go" in node_name or "green" in node_name:
				lights[lane]["green"] = node
			elif "foul" in node_name or "red" in node_name:
				lights[lane]["red"] = node
	
	for child in node.get_children():
		search_for_lights(child)


func add_omni_lights():
	"""Add OmniLight3D nodes to Empty markers"""
	search_for_empties(self)


func search_for_empties(node):
	"""Recursively find Empty markers and add lights"""
	if "Empty" in node.name and node is Node3D:
		var omni = OmniLight3D.new()
		omni.omni_range = 2.0
		omni.light_energy = 0
		node.add_child(omni)
		light_nodes[node.name] = omni
	
	for child in node.get_children():
		search_for_empties(child)


func set_light(lane: String, light_name: String, on: bool):
	"""Turn a specific light on/off"""
	if lane not in lights or light_name not in lights[lane]:
		return
	
	var mesh = lights[lane][light_name]
	var mat = mesh.get_active_material(0)
	if mat == null:
		mat = StandardMaterial3D.new()
		mesh.set_surface_override_material(0, mat)
	
	if mat is StandardMaterial3D:
		if on:
			mat.emission_enabled = true
			mat.emission_energy_multiplier = 10.0
			mat.albedo_color = Color.WHITE
			
			# Color based on light type
			if light_name == "green":
				mat.emission = Color(0, 2, 0)
			elif light_name == "red":
				mat.emission = Color(2, 0, 0)
			elif light_name == "prestage" or light_name == "stage":
				mat.emission = Color(2, 2, 0)
			else:
				mat.emission = Color(2, 1.2, 0)
		else:
			mat.emission_enabled = false
			mat.albedo_color = Color(0.2, 0.2, 0.2)
	
	# Update OmniLight if exists
	var empty_pattern = lane + "_" + light_name
	for empty_name in light_nodes.keys():
		if empty_pattern in empty_name.to_lower():
			var omni = light_nodes[empty_name]
			if on:
				omni.light_energy = 3.0
				if light_name == "green":
					omni.light_color = Color(0, 1, 0)
				elif light_name == "red":
					omni.light_color = Color(1, 0, 0)
				elif light_name == "prestage" or light_name == "stage":
					omni.light_color = Color(1, 1, 0)
				else:
					omni.light_color = Color(1, 0.6, 0)
			else:
				omni.light_energy = 0


func turn_all_lights_off():
	"""Turn off all lights"""
	for lane in ["left", "right"]:
		for light_name in lights[lane].keys():
			set_light(lane, light_name, false)
