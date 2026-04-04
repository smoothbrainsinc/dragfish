extends Control

var player_car_index: int = 0
var npc_car_index: int = 1
var npc_none_selected: bool = false

@onready var player_car_label = $GridContainer2/Control/GridContainer/HBoxContainer/PlayerPanel/VBoxContainer/CarName
@onready var player_stats_label = $GridContainer2/Control/GridContainer/HBoxContainer/PlayerPanel/VBoxContainer/Stats
@onready var npc_car_label = $GridContainer2/Control/GridContainer/HBoxContainer/NPCPanel/VBoxContainer/CarName
@onready var npc_stats_label = $GridContainer2/Control/GridContainer/HBoxContainer/NPCPanel/VBoxContainer/Stats
@onready var player_viewport = $GridContainer2/GridContainer/SubViewportContainer/playerViewport
@onready var NPCViewport = $GridContainer2/GridContainer2/SubViewportContainer/NPCViewport

var current_player_car = null
var current_npc_car = null

func _ready():
	print("[Car Selection] Starting...")
	await get_tree().process_frame

	var available_cars = GameManager.get_available_vehicles()

	if available_cars.is_empty():
		push_error("[Car Selection] No vehicles found!")
		return

	if npc_car_index >= available_cars.size():
		npc_car_index = 0

	print("[Car Selection] Found %d vehicles, loading displays..." % available_cars.size())
	update_car_displays()

func _on_vehicle_selected(vehicle_config: VehicleConfig):
	GameManager.selected_vehicle_for_tuning = vehicle_config
	GameManager.player_car_data = {
		"name": vehicle_config.display_name,
		"scene_path": vehicle_config.scene_path,
		"config": vehicle_config
	}
	get_tree().change_scene_to_file("res://scenes/tuning_screen.tscn")

func update_car_displays():
	var available_cars = GameManager.get_available_vehicles()
	if available_cars.is_empty():
		return

	var player_config: VehicleConfig = available_cars[player_car_index]

	player_car_label.text = player_config.display_name
	player_stats_label.text = "Horsepower: %d HP\nMass: %.0f kg" % [
		player_config.get_horsepower(),
		player_config.mass if player_config.mass > 0 else 500.0
	]
	load_player_preview_car(player_config.scene_path)

	# NPC side
	if npc_none_selected:
		npc_car_label.text = "None"
		npc_stats_label.text = "Solo run"
		if current_npc_car and is_instance_valid(current_npc_car):
			current_npc_car.queue_free()
			current_npc_car = null
	else:
		var npc_config: VehicleConfig = available_cars[npc_car_index]
		npc_car_label.text = npc_config.display_name
		npc_stats_label.text = "Horsepower: %d HP\nMass: %.0f kg" % [
			npc_config.get_horsepower(),
			npc_config.mass if npc_config.mass > 0 else 500.0
		]
		load_npc_preview_car(npc_config.scene_path)

func load_player_preview_car(scene_path: String):
	if current_player_car and is_instance_valid(current_player_car):
		current_player_car.queue_free()
		current_player_car = null

	var scene = load(scene_path)
	if not scene:
		push_error("[Car Selection] Failed to load player preview: " + scene_path)
		return

	var vehicle = scene.instantiate()
	_disable_all_physics_and_scripts(vehicle)
	player_viewport.add_child(vehicle)
	vehicle.position = Vector3.ZERO
	vehicle.rotation_degrees = Vector3(0, 30, 0)
	current_player_car = vehicle
	print("[Car Selection] Loaded player preview: %s" % scene_path.get_file())

func load_npc_preview_car(scene_path: String):
	if current_npc_car and is_instance_valid(current_npc_car):
		current_npc_car.queue_free()
		current_npc_car = null

	var scene = load(scene_path)
	if not scene:
		push_error("[Car Selection] Failed to load NPC preview: " + scene_path)
		return

	var vehicle = scene.instantiate()
	_disable_all_physics_and_scripts(vehicle)
	NPCViewport.add_child(vehicle)
	vehicle.position = Vector3.ZERO
	vehicle.rotation_degrees = Vector3(0, 30, 0)
	vehicle.scale = Vector3(0.5, 0.5, 0.5)
	current_npc_car = vehicle
	print("[Car Selection] Loaded NPC preview: %s" % scene_path.get_file())

func _disable_all_physics_and_scripts(node: Node):
	if node is VehicleBody3D:
		node.freeze = true
		node.sleeping = true
		node.set_physics_process(false)
		node.set_process(false)
		print("[Car Selection] Disabled VehicleBody3D physics")
	elif node is RigidBody3D:
		node.freeze = true
		node.sleeping = true
		node.set_physics_process(false)
		node.set_process(false)
	elif node is StaticBody3D:
		node.set_physics_process(false)
		node.set_process(false)

	if node.has_method("set_process"):
		node.set_process(false)
	if node.has_method("set_physics_process"):
		node.set_physics_process(false)

	for child in node.get_children():
		_disable_all_physics_and_scripts(child)

# ── Player nav ─────────────────────────────────────────────
func _on_player_prev_pressed():
	player_car_index = (player_car_index - 1 + GameManager.get_available_vehicles().size()) % GameManager.get_available_vehicles().size()
	update_car_displays()

func _on_player_next_pressed():
	player_car_index = (player_car_index + 1) % GameManager.get_available_vehicles().size()
	update_car_displays()

# ── NPC nav — includes None slot ───────────────────────────
func _on_npc_prev_pressed():
	var vehicle_count: int = GameManager.get_available_vehicles().size()
	if npc_none_selected:
		# None → last car
		npc_none_selected = false
		npc_car_index = vehicle_count - 1
	else:
		npc_car_index -= 1
		if npc_car_index < 0:
			npc_none_selected = true
			npc_car_index = 0
	update_car_displays()

func _on_npc_next_pressed():
	var vehicle_count: int = GameManager.get_available_vehicles().size()
	if npc_none_selected:
		# None → first car
		npc_none_selected = false
		npc_car_index = 0
	else:
		npc_car_index += 1
		if npc_car_index >= vehicle_count:
			npc_none_selected = true
			npc_car_index = 0
	update_car_displays()

# ── Start race ─────────────────────────────────────────────
func _on_start_race_pressed():
	var available = GameManager.get_available_vehicles()

	if available.is_empty():
		push_error("[Car Selection] No vehicles available!")
		return

	GameManager.player_car_config = available[player_car_index]
	GameManager.npc_car_config = null if npc_none_selected else available[npc_car_index]

	print("\n[Car Selection] === RACE STARTING ===")
	print("  Player: %s" % GameManager.player_car_config.display_name)
	print("  NPC: %s" % ("None" if npc_none_selected else GameManager.npc_car_config.display_name))
	print("=====================================\n")

	if current_player_car and is_instance_valid(current_player_car):
		current_player_car.queue_free()
	if current_npc_car and is_instance_valid(current_npc_car):
		current_npc_car.queue_free()

	get_tree().change_scene_to_file("res://scenes/pluto_raceway.tscn")

# ── Other buttons ──────────────────────────────────────────
func _on_pit_button_pressed():
	var available = GameManager.get_available_vehicles()
	GameManager.player_car_config = available[player_car_index]
	GameManager.npc_car_config = null if npc_none_selected else available[npc_car_index]
	get_tree().change_scene_to_file("res://assets/components/pit_area_ui.tscn")

func _on_garage_button_pressed():
	get_tree().change_scene_to_file("res://scenes/vehicle_setup_scene.tscn")

func _exit_tree():
	if current_player_car and is_instance_valid(current_player_car):
		current_player_car.queue_free()
	if current_npc_car and is_instance_valid(current_npc_car):
		current_npc_car.queue_free()
