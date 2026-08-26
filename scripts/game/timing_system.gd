extends Node3D
## Timing System - Signal-based, decoupled design
## No direct dependencies on other systems
## Lane keys are ints, 1 = farthest right. Supports any number of lanes.

# === SIGNALS ===
signal red_light_triggered(lane: int)
signal checkpoint_crossed(lane: int, checkpoint: String, time: float)
signal race_finished(lane: int, results: Dictionary)
signal all_finished(left_results: Dictionary, right_results: Dictionary, winner: String)  # winner: "left"/"right"/"both_fouled"/""
signal center_line_crossed(lane: int)

# Checkpoint references (set in editor or found by name)
@export var start_line: Area3D
@export var checkpoint_60ft: Area3D
@export var checkpoint_330ft: Area3D
@export var checkpoint_660ft: Area3D
@export var checkpoint_1000ft: Area3D
@export var finish_line: Area3D
@export var speed_trap_start: Area3D
@export var center_line: Area3D

# Timing data, keyed by lane number
var active_lanes: Array[int] = []
var timing_data: Dictionary = {}

# Race state
var race_started = false
var tree_started = false
var green_light_time = 0.0

func _ready():
	add_to_group("timing_system")
	await get_tree().process_frame
	_find_checkpoints()
	_connect_checkpoints()
	print("[Timing] Checkpoint-based timing system ready")
	print("[Timing] Waiting for start tree signals...")

# ============================================================================
# SIGNAL CONNECTIONS (Called by RaceController or manually)
# ============================================================================
func connect_to_start_tree(start_tree: Node):
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
	reset_timing_data()
	tree_started = true
	print("[Timing] Armed and ready (foul detection ACTIVE)...")

func _on_green_light():
	race_started = true
	green_light_time = Time.get_ticks_msec() / 1000.0
	print("[Timing] === RACE STARTED - CLOCK RUNNING ===")

# ============================================================================
# CHECKPOINT HANDLERS
# ============================================================================
func _get_lane(body: Node3D) -> int:
	if not body is VehicleBody3D:
		return -1
	var lane: int = body.get_meta("spawn_lane", -1)
	if lane == -1 or not timing_data.has(lane):
		return -1
	return lane

func _on_start_line_crossed(body: Node3D):
	if not tree_started:
		return
	var lane := _get_lane(body)
	if lane == -1:
		return

	var data = timing_data[lane]
	if data["reaction_recorded"]:
		return
	data["reaction_recorded"] = true
	var current_time = Time.get_ticks_msec() / 1000.0

	if not race_started:
		data["red_light"] = true
		data["reaction_time"] = -999.0
		data["vehicle_name"] = get_vehicle_name(body)
		emit_signal("red_light_triggered", lane)
		print("[Timing] Lane %d - ***** FOUL START - RED LIGHT! *****" % lane)
	else:
		data["reaction_time"] = current_time - green_light_time
		data["vehicle_name"] = get_vehicle_name(body)
		if data["reaction_time"] < 0:
			data["red_light"] = true
			emit_signal("red_light_triggered", lane)
			print("[Timing] Lane %d - RED LIGHT! RT: %.4f" % [lane, data["reaction_time"]])
		else:
			print("[Timing] Lane %d - Reaction Time: %.4f" % [lane, data["reaction_time"]])
			emit_signal("checkpoint_crossed", lane, "start", data["reaction_time"])

func _on_60ft_crossed(body: Node3D):
	_handle_checkpoint(body, "crossed_60ft", "time_60ft", "60ft")

func _on_330ft_crossed(body: Node3D):
	_handle_checkpoint(body, "crossed_330ft", "time_330ft", "330ft")

func _on_660ft_crossed(body: Node3D):
	_handle_checkpoint(body, "crossed_660ft", "time_660ft", "660ft")

func _on_1000ft_crossed(body: Node3D):
	_handle_checkpoint(body, "crossed_1000ft", "time_1000ft", "1000ft")

func _handle_checkpoint(body: Node3D, crossed_key: String, time_key: String, label: String) -> void:
	if not race_started:
		return
	var lane := _get_lane(body)
	if lane == -1:
		return
	var data = timing_data[lane]
	if data[crossed_key]:
		return
	data[crossed_key] = true
	var current_time = Time.get_ticks_msec() / 1000.0
	data[time_key] = current_time - green_light_time
	print("[Timing] Lane %d - %s: %.4f" % [lane, label, data[time_key]])
	emit_signal("checkpoint_crossed", lane, label, data[time_key])

func _on_speed_trap_entered(body: Node3D):
	if not race_started:
		return
	var lane := _get_lane(body)
	if lane == -1:
		return
	var data = timing_data[lane]
	if data["crossed_speed_trap"]:
		return
	data["crossed_speed_trap"] = true
	data["speed_trap_entry_time"] = Time.get_ticks_msec() / 1000.0

func _on_finish_line_crossed(body: Node3D):
	if not race_started:
		return
	var lane := _get_lane(body)
	if lane == -1:
		return

	var data = timing_data[lane]
	if data["finished"]:
		return

	data["finished"] = true
	var current_time = Time.get_ticks_msec() / 1000.0
	data["elapsed_time"] = current_time - green_light_time

	if "linear_velocity" in body:
		var velocity = body.linear_velocity
		var speed_ms = velocity.length()
		data["speed_mph"] = speed_ms * 2.23694
		data["speed_kmh"] = speed_ms * 3.6

	if not data["vehicle_name"]:
		data["vehicle_name"] = get_vehicle_name(body)

	print_race_results(lane)
	emit_signal("race_finished", lane, data.duplicate())

	if _all_lanes_finished():
		_finalize_results()

func _all_lanes_finished() -> bool:
	for lane in active_lanes:
		var d = timing_data[lane]
		if not d["finished"] and not d["red_light"]:
			return false
	return true

func _finalize_results():
	var winner = get_winner()

	print("\n" + "=".repeat(70))
	print("=== ALL LANES DONE - RESULTS ===")
	print("=".repeat(70))

	for lane in active_lanes:
		var d = timing_data[lane]
		print("\nLane %d - %s" % [lane, d["vehicle_name"]])
		if d["red_light"]:
			print("  FOUL - RED LIGHT")
			continue
		print("  Reaction Time: %.4f sec" % d["reaction_time"])
		print("  60 ft:         %.4f sec" % d["time_60ft"])
		print("  330 ft:        %.4f sec" % d["time_330ft"])
		print("  1/8 mile:      %.4f sec" % d["time_660ft"])
		print("  1000 ft:       %.4f sec" % d["time_1000ft"])
		print("  ET (1/4 mile): %.4f sec" % d["elapsed_time"])
		print("  Speed:         %.2f MPH (%.2f KM/H)" % [d["speed_mph"], d["speed_kmh"]])

	print("\n" + "=".repeat(70))
	if str(winner) == "all_fouled":
		print("*** ALL DRIVERS FOULED - NO WINNER ***")
	elif str(winner) == "none":
		print("*** NO WINNER ***")
	else:
		print("*** WINNER: LANE %d (%s) ***" % [winner, timing_data[winner]["vehicle_name"]])
	print("=".repeat(70) + "\n")

	
	# Lane 1 = right, lane 2 = left (per GameManager.gd lane assignment)
	var right_results = timing_data.get(1, {})
	var left_results = timing_data.get(2, {})
	var winner_str = "right" if winner == 1 else "left" if winner == 2 else "both_fouled" if winner == "all_fouled" else ""
	emit_signal("all_finished", left_results, right_results, winner_str)

# ============================================================================
# UTILITIES
# ============================================================================
func get_vehicle_name(vehicle: Node) -> String:
	if vehicle.has_method("get_vehicle_name"):
		return vehicle.get_vehicle_name()
	return vehicle.name

func reset_timing_data():
	active_lanes = GameManager.active_lanes.duplicate()
	timing_data.clear()
	for lane in active_lanes:
		timing_data[lane] = _create_timing_data()
	race_started = false
	tree_started = false
	green_light_time = 0.0
	print("[Timing] Data reset for lanes: ", active_lanes)

func _create_timing_data() -> Dictionary:
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
		"vehicle_name": "",
		"dnf": false
	}

## Returns winning lane (int), "all_fouled", or "none" (race not yet decided)
func get_winner():
	var fouled: Array[int] = []
	var finished: Array[int] = []
	for lane in active_lanes:
		var d = timing_data[lane]
		if d["red_light"]:
			fouled.append(lane)
		elif d["finished"]:
			finished.append(lane)

	if fouled.size() == active_lanes.size():
		return "all_fouled"
	if finished.is_empty():
		return "none"

	var best_lane: int = finished[0]
	var best_time: float = timing_data[best_lane]["elapsed_time"]
	for lane in finished:
		if timing_data[lane]["elapsed_time"] < best_time:
			best_time = timing_data[lane]["elapsed_time"]
			best_lane = lane
	return best_lane

func print_race_results(lane: int):
	var data = timing_data[lane]
	print("\n" + "=".repeat(70))
	print("=== LANE %d RESULTS - %s ===" % [lane, data.get("vehicle_name", "Unknown")])
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
	return _search_children(get_tree().root, node_name)

func _search_children(node: Node, target_name: String) -> Node:
	if node.name.to_lower() == target_name.to_lower():
		return node
	for child in node.get_children():
		var result = _search_children(child, target_name)
		if result:
			return result
	return null

func _connect_checkpoints():
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

func _on_center_line_crossed(body: Node3D):
	if not race_started:
		return
	var lane := _get_lane(body)
	if lane == -1:
		return
	var data = timing_data[lane]
	if data["dnf"] or data["finished"]:
		return
	data["dnf"] = true
	if not data["vehicle_name"]:
		data["vehicle_name"] = get_vehicle_name(body)
	print("[Timing] Lane %d - ***** CENTERLINE CROSSED - DNF! *****" % lane)
	emit_signal("center_line_crossed", lane)
