extends Node
## Race Controller - Coordinates race systems via signals
signal race_complete(winner)

var start_tree: Node3D
var timing_system: Node3D
var race_manager: Node
var finish_line_scene: Control

func _ready():
	print("[RaceController] Initializing coordinator...")
	await get_tree().process_frame
	_find_systems()
	_connect_systems()
	print("[RaceController] All systems connected!")

func _find_systems() -> void:
	start_tree = get_tree().get_first_node_in_group("start_tree")
	timing_system = get_tree().get_first_node_in_group("timing_system")
	race_manager = get_tree().get_first_node_in_group("race_manager")
	finish_line_scene = get_tree().get_first_node_in_group("finish_line_ui")

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

func _connect_systems() -> void:
	if start_tree and timing_system:
		if timing_system.has_method("connect_to_start_tree"):
			timing_system.connect_to_start_tree(start_tree)
			print("  ✓ Connected start tree → timing system")
		elif start_tree.has_signal("green_light"):
			start_tree.green_light.connect(timing_system._on_green_light)
			print("  ✓ Manually connected green_light signal")

	if timing_system and start_tree:
		if timing_system.has_signal("red_light_triggered"):
			timing_system.red_light_triggered.connect(_on_red_light_triggered)
			print("  ✓ Connected timing system → start tree (fouls)")

	if timing_system:
		if timing_system.has_signal("race_finished"):
			timing_system.race_finished.connect(_on_race_finished)
			print("  ✓ Connected timing system → race results")

	if timing_system and finish_line_scene:
		if timing_system.has_signal("all_finished"):
			timing_system.all_finished.connect(finish_line_scene.show_results)
			print("  ✓ Connected timing system → finish line UI")

	if finish_line_scene:
		finish_line_scene.rematch_requested.connect(_on_rematch_requested)
		finish_line_scene.rematch_garage_first_requested.connect(_on_rematch_garage_requested)
		finish_line_scene.new_race_requested.connect(_on_new_race_requested)
		finish_line_scene.end_requested.connect(_on_end_requested)
		finish_line_scene.fish_requested.connect(_on_fish_requested)
		print("  ✓ Connected finish line UI buttons")

func _on_red_light_triggered(lane: int) -> void:
	print("[RaceController] RED LIGHT FOUL: lane %d!" % lane)
	if start_tree and start_tree.has_method("trigger_red_light"):
		start_tree.trigger_red_light(lane)

func _on_race_finished(lane: int, results: Dictionary) -> void:
	print("[RaceController] Lane %d finished!" % lane)
	print("  ET: %.3f" % results.get("elapsed_time", 0.0))
	print("  Speed: %.1f mph" % results.get("speed_mph", 0.0))

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

func start_race() -> void:
	if start_tree and start_tree.has_method("start_sequence"):
		start_tree.start_sequence()
		print("[RaceController] Started race sequence")
	else:
		push_warning("[RaceController] Cannot start race - no start tree!")

func is_race_active() -> bool:
	if timing_system and timing_system.has_method("is_race_active"):
		return timing_system.is_race_active()
	return false
