extends Node
## Race Controller - Coordinates race systems via signals
## This is the ONLY script that knows about all race systems
## Acts as a signal hub to keep systems decoupled

signal race_complete(winner: String)

# Race system references (found automatically)
var start_tree: Node3D
var timing_system: Node3D
var race_manager: Node
var finish_line_scene: Control

func _ready():
	print("[RaceController] Initializing coordinator...")
	
	# Wait for scene to load
	await get_tree().process_frame
	
	# Find all systems
	_find_systems()
	
	# Connect systems together
	_connect_systems()
	
	print("[RaceController] All systems connected!")

## Locate race systems in scene tree
func _find_systems() -> void:
	start_tree = get_tree().get_first_node_in_group("start_tree")
	timing_system = get_tree().get_first_node_in_group("timing_system")
	race_manager = get_tree().get_first_node_in_group("race_manager")
	finish_line_scene = get_tree().get_first_node_in_group("finish_line_ui")
	
	# Verify critical systems
	if not start_tree:
		push_error("[RaceController] Start tree not found!")
	else:
		print("  ✓ Start tree: %s" % start_tree.name)
	
	if not timing_system:
		push_error("[RaceController] Timing system not found!")
	else:
		print("  ✓ Timing system: %s" % timing_system.name)
	
	if not race_manager:
		push_warning("[RaceController] Race manager not found (optional)")
	else:
		print("  ✓ Race manager: %s" % race_manager.name)
		
	if not finish_line_scene:
		push_warning("[RaceController] Finish line UI not found (optional)")
	else:
		print("  ✓ Finish line UI: %s" % finish_line_scene.name)

## Wire systems together using signals
func _connect_systems() -> void:
	# === START TREE → TIMING SYSTEM ===
	if start_tree and timing_system:
		if timing_system.has_method("connect_to_start_tree"):
			timing_system.connect_to_start_tree(start_tree)
			print("  ✓ Connected start tree → timing system")
		elif start_tree.has_signal("green_light"):
			start_tree.green_light.connect(timing_system._on_green_light)
			print("  ✓ Manually connected green_light signal")
	
	# === TIMING SYSTEM → START TREE (red lights) ===
	if timing_system and start_tree:
		if timing_system.has_signal("red_light_triggered"):
			timing_system.red_light_triggered.connect(_on_red_light_triggered)
			print("  ✓ Connected timing system → start tree (fouls)")
	
	# === TIMING SYSTEM → RACE CONTROLLER (results) ===
	if timing_system:
		if timing_system.has_signal("race_finished"):
			timing_system.race_finished.connect(_on_race_finished)
			print("  ✓ Connected timing system → race results")
			
	if timing_system and finish_line_scene:
		if timing_system.has_signal("both_finished"):
			timing_system.both_finished.connect(finish_line_scene.show_results)
			print("  ✓ Connected timing system → finish line UI")
			
	if finish_line_scene:
		finish_line_scene.rematch_requested.connect(_on_rematch_requested)
		finish_line_scene.rematch_garage_first_requested.connect(_on_rematch_garage_requested)
		finish_line_scene.new_race_requested.connect(_on_new_race_requested)
		finish_line_scene.end_requested.connect(_on_end_requested)
		finish_line_scene.fish_requested.connect(_on_fish_requested)
		print("  ✓ Connected finish line UI buttons")
	

## Handle red light foul
func _on_red_light_triggered(lane: String) -> void:
	print("[RaceController] RED LIGHT FOUL: %s lane!" % lane.to_upper())
	
	if start_tree and start_tree.has_method("trigger_red_light"):
		start_tree.trigger_red_light(lane)

## Handle race finish for a lane
func _on_race_finished(lane: String, results: Dictionary) -> void:
	print("[RaceController] %s lane finished!" % lane.to_upper())
	print("  ET: %.3f" % results.get("elapsed_time", 0.0))
	print("  Speed: %.1f mph" % results.get("speed_mph", 0.0))
	
	# Check if both lanes finished
	if timing_system and timing_system.has_method("get_winner"):
		var winner = timing_system.get_winner()
		if winner != "none":
			_declare_winner(winner)

## Declare race winner
func _declare_winner(winner: String) -> void:
	print("\n" + "=".repeat(70))
	
	if winner == "both_fouled":
		print("BOTH DRIVERS FOULED - NO WINNER")
	else:
		print("🏁 WINNER: %s LANE 🏁" % winner.to_upper())
	
	print("=".repeat(70) + "\n")
	
	emit_signal("race_complete", winner)

## Public API - Restart race
func restart_race() -> void:
	print("[RaceController] Restarting race...")
	
	if start_tree and start_tree.has_method("reset_tree"):
		start_tree.reset_tree()
	
	if timing_system and timing_system.has_method("reset_timing_data"):
		timing_system.reset_timing_data()
	
	if race_manager and race_manager.has_method("restart_race"):
		race_manager.restart_race()
	
	print("[RaceController] Race restarted")

func _on_rematch_requested() -> void:
	finish_line_scene.visible = false
	restart_race()

func _on_rematch_garage_requested() -> void:
	finish_line_scene.visible = false
	# TODO: send player to pit_area_ui.tscn before restart_race()

func _on_new_race_requested() -> void:
	finish_line_scene.visible = false
	# TODO: send player back to new_car_selection_screen.tscn

func _on_end_requested() -> void:
	get_tree().quit()

func _on_fish_requested() -> void:
	finish_line_scene.visible = false
	# TODO: switch to fishing/lake gameplay mode

## Public API - Start race (for manual control)
func start_race() -> void:
	if start_tree and start_tree.has_method("start_sequence"):
		start_tree.start_sequence()
		print("[RaceController] Started race sequence")
	else:
		push_warning("[RaceController] Cannot start race - no start tree!")

## Check if race is in progress
func is_race_active() -> bool:
	if timing_system and timing_system.has_method("is_race_active"):
		return timing_system.is_race_active()
	return false
