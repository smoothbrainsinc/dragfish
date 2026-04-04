extends Node3D
## Timing System - Signal-based, decoupled design
## No direct dependencies on other systems

# === SIGNALS (What the timing system tells the world) ===
signal red_light_triggered(lane: String)    # Foul start detected
signal checkpoint_crossed(lane: String, checkpoint: String, time: float)
signal race_finished(lane: String, results: Dictionary)
signal both_finished(left_results: Dictionary, right_results: Dictionary, winner: String)

# Checkpoint references (set in editor or found by name)
@export var start_line: Area3D
@export var checkpoint_60ft: Area3D
@export var checkpoint_330ft: Area3D
@export var checkpoint_660ft: Area3D
@export var checkpoint_1000ft: Area3D
@export var finish_line: Area3D
@export var speed_trap_start: Area3D

# Lane detection (X position threshold)
const LANE_CENTER_THRESHOLD = -34.5

# Timing data
var timing_data = {
	"left": _create_timing_data(),
	"right": _create_timing_data()
}

# Race state
var race_started = false
var tree_started = false
var green_light_time = 0.0


func _ready():
	add_to_group("timing_system")
	
	# Wait for scene to load
	await get_tree().process_frame
	
	# Auto-find checkpoints
	_find_checkpoints()
	
	# Connect checkpoint signals
	_connect_checkpoints()
	
	print("[Timing] Checkpoint-based timing system ready")
	print("[Timing] Waiting for start tree signals...")


# ============================================================================
# SIGNAL CONNECTIONS (Called by RaceController or manually)
# ============================================================================

func connect_to_start_tree(start_tree: Node):
	"""Connect to start tree signals"""
	if start_tree.has_signal("tree_started"):
		start_tree.tree_started.connect(_on_tree_started)
		print("[Timing] Connected to tree_started signal")
	
	if start_tree.has_signal("green_light"):
		start_tree.green_light.connect(_on_green_light)
		print("[Timing] Connected to green_light signal")


# ============================================================================
# SIGNAL HANDLERS
# ============================================================================

func _on_tree_started():
	"""Called when tree sequence begins"""
	reset_timing_data()
	tree_started = true
	print("[Timing] Armed and ready (foul detection ACTIVE)...")


func _on_green_light():
	"""Called when green light turns on"""
	race_started = true
	green_light_time = Time.get_ticks_msec() / 1000.0
	print("[Timing] === RACE STARTED - CLOCK RUNNING ===")


# ============================================================================
# CHECKPOINT HANDLERS
# ============================================================================

func _on_start_line_crossed(body: Node3D):
	"""Vehicle crossed start line - check for foul or record reaction"""
	if not tree_started or not body is VehicleBody3D:
		return
	
	var lane = get_lane_from_position(body.global_position.x)
	if lane == "unknown":
		return
	
	var data = timing_data[lane]
	if data["reaction_recorded"]:
		return
	
	data["reaction_recorded"] = true
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# Check for foul start
	if not race_started:
		# RED LIGHT - crossed before green
		data["red_light"] = true
		data["reaction_time"] = -999.0
		data["vehicle_name"] = get_vehicle_name(body)
		
		# Emit signal instead of calling start_tree directly
		emit_signal("red_light_triggered", lane)
		
		print("[Timing] %s - ***** FOUL START - RED LIGHT! *****" % lane.to_upper())
	else:
		# Normal start
		data["reaction_time"] = current_time - green_light_time
		data["vehicle_name"] = get_vehicle_name(body)
		
		if data["reaction_time"] < 0:
			# Shouldn't happen, but failsafe
			data["red_light"] = true
			emit_signal("red_light_triggered", lane)
			print("[Timing] %s - RED LIGHT! RT: %.4f" % [lane.to_upper(), data["reaction_time"]])
		else:
			print("[Timing] %s - Reaction Time: %.4f" % [lane.to_upper(), data["reaction_time"]])
			emit_signal("checkpoint_crossed", lane, "start", data["reaction_time"])


func _on_60ft_crossed(body: Node3D):
	"""60 foot checkpoint"""
	if not race_started or not body is VehicleBody3D:
		return
	
	var lane = get_lane_from_position(body.global_position.x)
	if lane == "unknown":
		return
	
	var data = timing_data[lane]
	if data["crossed_60ft"]:
		return
	
	data["crossed_60ft"] = true
	var current_time = Time.get_ticks_msec() / 1000.0
	data["time_60ft"] = current_time - green_light_time
	
	print("[Timing] %s - 60ft: %.4f" % [lane.to_upper(), data["time_60ft"]])
	emit_signal("checkpoint_crossed", lane, "60ft", data["time_60ft"])


func _on_330ft_crossed(body: Node3D):
	"""330 foot checkpoint"""
	if not race_started or not body is VehicleBody3D:
		return
	
	var lane = get_lane_from_position(body.global_position.x)
	if lane == "unknown":
		return
	
	var data = timing_data[lane]
	if data["crossed_330ft"]:
		return
	
	data["crossed_330ft"] = true
	var current_time = Time.get_ticks_msec() / 1000.0
	data["time_330ft"] = current_time - green_light_time
	
	print("[Timing] %s - 330ft: %.4f" % [lane.to_upper(), data["time_330ft"]])
	emit_signal("checkpoint_crossed", lane, "330ft", data["time_330ft"])


func _on_660ft_crossed(body: Node3D):
	"""660 foot checkpoint (1/8 mile)"""
	if not race_started or not body is VehicleBody3D:
		return
	
	var lane = get_lane_from_position(body.global_position.x)
	if lane == "unknown":
		return
	
	var data = timing_data[lane]
	if data["crossed_660ft"]:
		return
	
	data["crossed_660ft"] = true
	var current_time = Time.get_ticks_msec() / 1000.0
	data["time_660ft"] = current_time - green_light_time
	
	print("[Timing] %s - 1/8 mile: %.4f" % [lane.to_upper(), data["time_660ft"]])
	emit_signal("checkpoint_crossed", lane, "660ft", data["time_660ft"])


func _on_1000ft_crossed(body: Node3D):
	"""1000 foot checkpoint"""
	if not race_started or not body is VehicleBody3D:
		return
	
	var lane = get_lane_from_position(body.global_position.x)
	if lane == "unknown":
		return
	
	var data = timing_data[lane]
	if data["crossed_1000ft"]:
		return
	
	data["crossed_1000ft"] = true
	var current_time = Time.get_ticks_msec() / 1000.0
	data["time_1000ft"] = current_time - green_light_time
	
	print("[Timing] %s - 1000ft: %.4f" % [lane.to_upper(), data["time_1000ft"]])
	emit_signal("checkpoint_crossed", lane, "1000ft", data["time_1000ft"])


func _on_speed_trap_entered(body: Node3D):
	"""Speed trap entry"""
	if not race_started or not body is VehicleBody3D:
		return
	
	var lane = get_lane_from_position(body.global_position.x)
	if lane == "unknown":
		return
	
	var data = timing_data[lane]
	if data["crossed_speed_trap"]:
		return
	
	data["crossed_speed_trap"] = true
	data["speed_trap_entry_time"] = Time.get_ticks_msec() / 1000.0


func _on_finish_line_crossed(body: Node3D):
	"""Finish line - race complete for this lane"""
	if not race_started or not body is VehicleBody3D:
		return
	
	var lane = get_lane_from_position(body.global_position.x)
	if lane == "unknown":
		return
	
	var data = timing_data[lane]
	if data["finished"]:
		return
	
	data["finished"] = true
	var current_time = Time.get_ticks_msec() / 1000.0
	data["elapsed_time"] = current_time - green_light_time
	
	# Calculate speed from vehicle velocity
	if body.has_method("get") and "linear_velocity" in body:
		var velocity = body.linear_velocity
		var speed_ms = velocity.length()
		data["speed_mph"] = speed_ms * 2.23694
		data["speed_kmh"] = speed_ms * 3.6
	
	if not data["vehicle_name"]:
		data["vehicle_name"] = get_vehicle_name(body)
	
	# Print full results immediately for this lane
	print_race_results(lane)
	
	# Emit signal for this lane
	emit_signal("race_finished", lane, data.duplicate())
	
	# Check if both lanes finished - print comparison
	if timing_data["left"]["finished"] and timing_data["right"]["finished"]:
		_print_winner_comparison()


func _print_winner_comparison():
	"""Print winner comparison after BOTH vehicles finish"""
	var winner = get_winner()
	
	print("\n" + "=".repeat(70))
	print("=== BOTH VEHICLES FINISHED - HEAD-TO-HEAD COMPARISON ===")
	print("=".repeat(70))
	
	var left = timing_data["left"]
	var right = timing_data["right"]
	
	print("\n%-20s | %-15s | %-15s" % ["", "LEFT LANE", "RIGHT LANE"])
	print("=".repeat(70))
	print("%-20s | %-15s | %-15s" % ["Vehicle", left["vehicle_name"], right["vehicle_name"]])
	
	if not left["red_light"] and not right["red_light"]:
		print("%-20s | %.4f sec      | %.4f sec" % ["Reaction Time", left["reaction_time"], right["reaction_time"]])
	
	print("%-20s | %.4f sec      | %.4f sec" % ["60 ft", left["time_60ft"], right["time_60ft"]])
	print("%-20s | %.4f sec      | %.4f sec" % ["330 ft", left["time_330ft"], right["time_330ft"]])
	print("%-20s | %.4f sec      | %.4f sec" % ["1/8 mile", left["time_660ft"], right["time_660ft"]])
	print("%-20s | %.4f sec      | %.4f sec" % ["1000 ft", left["time_1000ft"], right["time_1000ft"]])
	print("%-20s | %.4f sec      | %.4f sec" % ["ET (1/4 mile)", left["elapsed_time"], right["elapsed_time"]])
	print("%-20s | %.2f MPH       | %.2f MPH" % ["Speed", left["speed_mph"], right["speed_mph"]])
	
	print("\n" + "=".repeat(70))
	if winner == "both_fouled":
		print("*** BOTH DRIVERS FOULED - NO WINNER ***")
	elif winner == "left":
		var margin = right["elapsed_time"] - left["elapsed_time"]
		print("*** WINNER: LEFT LANE (%s) by %.4f seconds ***" % [left["vehicle_name"], margin])
	elif winner == "right":
		var margin = left["elapsed_time"] - right["elapsed_time"]
		print("*** WINNER: RIGHT LANE (%s) by %.4f seconds ***" % [right["vehicle_name"], margin])
	print("=".repeat(70) + "\n")
	
	# Emit combined results signal
	emit_signal("both_finished", left.duplicate(), right.duplicate(), winner)


# ============================================================================
# UTILITIES
# ============================================================================

func get_lane_from_position(x_pos: float) -> String:
	"""Determine lane from X position - FIXED!"""
	if x_pos < LANE_CENTER_THRESHOLD:
		return "right"  # Negative X = LEFT lane
	elif x_pos > LANE_CENTER_THRESHOLD:
		return "left"  # Positive X = RIGHT lane
	else:
		return "unknown"


func get_vehicle_name(vehicle: Node) -> String:
	"""Get display name of vehicle"""
	if vehicle.has_method("get_vehicle_name"):
		return vehicle.get_vehicle_name()
	return vehicle.name


func reset_timing_data():
	"""Reset all timing data"""
	race_started = false
	tree_started = false
	green_light_time = 0.0
	timing_data["left"] = _create_timing_data()
	timing_data["right"] = _create_timing_data()
	print("[Timing] Data reset")


func _create_timing_data() -> Dictionary:
	"""Create fresh timing data structure"""
	return {
		"reaction_time": 0.0,
		"elapsed_time": 0.0,
		"time_60ft": 0.0,
		"time_330ft": 0.0,
		"time_660ft": 0.0,
		"time_1000ft": 0.0,
		"speed_mph": 0.0,
		"speed_kmh": 0.0,
		"crossed_60ft": false,
		"crossed_330ft": false,
		"crossed_660ft": false,
		"crossed_1000ft": false,
		"crossed_speed_trap": false,
		"finished": false,
		"red_light": false,
		"reaction_recorded": false,
		"speed_trap_entry_time": 0.0,
		"vehicle_name": ""
	}


func get_winner() -> String:
	"""Determine race winner"""
	var left_data = timing_data["left"]
	var right_data = timing_data["right"]
	
	# Check for red lights first
	if left_data["red_light"] and not right_data["red_light"]:
		return "right"
	elif right_data["red_light"] and not left_data["red_light"]:
		return "left"
	elif left_data["red_light"] and right_data["red_light"]:
		return "both_fouled"
	
	# Both finished - compare times
	if left_data["finished"] and right_data["finished"]:
		return "left" if left_data["elapsed_time"] < right_data["elapsed_time"] else "right"
	elif left_data["finished"]:
		return "left"
	elif right_data["finished"]:
		return "right"
	
	return "none"


func print_race_results(lane: String):
	"""Print detailed results for a lane"""
	var data = timing_data[lane]
	
	print("\n" + "=".repeat(70))
	print("=== %s LANE RESULTS - %s ===" % [lane.to_upper(), data.get("vehicle_name", "Unknown")])
	print("=".repeat(70))
	
	if data["red_light"]:
		print("***** FOUL START - RED LIGHT *****")
	
	if data["reaction_time"] > 0 and data["reaction_time"] != -999.0:
		print("Reaction Time: %.4f sec" % data["reaction_time"])
	
	if data["time_60ft"] > 0:
		print("60 ft:         %.4f sec" % data["time_60ft"])
	if data["time_330ft"] > 0:
		print("330 ft:        %.4f sec" % data["time_330ft"])
	if data["time_660ft"] > 0:
		print("1/8 mile:      %.4f sec" % data["time_660ft"])
	if data["time_1000ft"] > 0:
		print("1000 ft:       %.4f sec" % data["time_1000ft"])
	
	if data["elapsed_time"] > 0:
		print("ET (1/4 mile): %.4f sec" % data["elapsed_time"])
	
	if data["speed_mph"] > 0:
		print("Speed:         %.2f MPH (%.2f KM/H)" % [data["speed_mph"], data["speed_kmh"]])
	
	print("=".repeat(70))


# ============================================================================
# CHECKPOINT DISCOVERY & CONNECTION
# ============================================================================

func _find_checkpoints():
	"""Auto-find checkpoint Area3D nodes"""
	if not start_line:
		start_line = get_tree().get_first_node_in_group("start_checkpoint")
		if not start_line:
			start_line = find_node_by_name("start")
	
	if not checkpoint_60ft:
		checkpoint_60ft = get_tree().get_first_node_in_group("60ft_checkpoint")
		if not checkpoint_60ft:
			checkpoint_60ft = find_node_by_name("60_feet")
	
	if not checkpoint_330ft:
		checkpoint_330ft = get_tree().get_first_node_in_group("330ft_checkpoint")
		if not checkpoint_330ft:
			checkpoint_330ft = find_node_by_name("330_feet")
	
	if not checkpoint_660ft:
		checkpoint_660ft = get_tree().get_first_node_in_group("660ft_checkpoint")
		if not checkpoint_660ft:
			checkpoint_660ft = find_node_by_name("660_feet")
	
	if not checkpoint_1000ft:
		checkpoint_1000ft = get_tree().get_first_node_in_group("1000ft_checkpoint")
		if not checkpoint_1000ft:
			checkpoint_1000ft = find_node_by_name("1000_feet")
	
	if not speed_trap_start:
		speed_trap_start = get_tree().get_first_node_in_group("speed_trap_checkpoint")
		if not speed_trap_start:
			speed_trap_start = find_node_by_name("speed_trap")
	
	if not finish_line:
		finish_line = get_tree().get_first_node_in_group("finish_checkpoint")
		if not finish_line:
			finish_line = find_node_by_name("finish_line")


func find_node_by_name(node_name: String) -> Node:
	"""Recursively search for node by name"""
	return _search_children(get_tree().root, node_name)


func _search_children(node: Node, target_name: String) -> Node:
	"""Recursive search helper"""
	if node.name.to_lower() == target_name.to_lower():
		return node
	for child in node.get_children():
		var result = _search_children(child, target_name)
		if result:
			return result
	return null


func _connect_checkpoints():
	"""Connect body_entered signals for all checkpoints"""
	var connected_count = 0
	
	if start_line:
		start_line.body_entered.connect(_on_start_line_crossed)
		print("[Timing] Connected: start_line")
		connected_count += 1
	
	if checkpoint_60ft:
		checkpoint_60ft.body_entered.connect(_on_60ft_crossed)
		print("[Timing] Connected: 60ft checkpoint")
		connected_count += 1
	
	if checkpoint_330ft:
		checkpoint_330ft.body_entered.connect(_on_330ft_crossed)
		print("[Timing] Connected: 330ft checkpoint")
		connected_count += 1
	
	if checkpoint_660ft:
		checkpoint_660ft.body_entered.connect(_on_660ft_crossed)
		print("[Timing] Connected: 660ft checkpoint")
		connected_count += 1
	
	if checkpoint_1000ft:
		checkpoint_1000ft.body_entered.connect(_on_1000ft_crossed)
		print("[Timing] Connected: 1000ft checkpoint")
		connected_count += 1
	
	if speed_trap_start:
		speed_trap_start.body_entered.connect(_on_speed_trap_entered)
		print("[Timing] Connected: speed trap")
		connected_count += 1
	
	if finish_line:
		finish_line.body_entered.connect(_on_finish_line_crossed)
		print("[Timing] Connected: finish line")
		connected_count += 1
	
	print("[Timing] Total checkpoints connected: %d/7" % connected_count)
	print("Start position: ", start_line.global_position)
	print("Finish position:", finish_line.global_position)
