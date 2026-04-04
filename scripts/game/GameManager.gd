extends Node
## Game Manager - Vehicle discovery and spawning
## IMPORTANT: Vehicle scenes MUST have VehicleController script attached to VehicleBody3D root

const VEHICLE_SCENES_FOLDER = "res://vehicles/"
const VEHICLE_CONFIGS_FOLDER = "res://vehicles/configs/"

# Available vehicles
var available_vehicles: Array[VehicleConfig] = []

# Selected vehicles for race
var player_car_config: VehicleConfig
var npc_car_config: VehicleConfig
var player_lane: String = "right"

# For tuning screen
var selected_vehicle_for_tuning: VehicleConfig
var player_car_data: Dictionary = {}

# Store wheel modifications
var wheel_modifications: Dictionary = {}

# Spawn markers (set by RaceManager or scene)
var left_lane_spawn: Marker3D
var right_lane_spawn: Marker3D

func _ready() -> void:
	print("[GameManager] Initializing...")
	discover_vehicles()

## Discover vehicles by scanning scenes folder
## Uses matching .tres if found, otherwise generates default config
func discover_vehicles() -> void:
	available_vehicles.clear()

	var dir = DirAccess.open(VEHICLE_SCENES_FOLDER)
	if not dir:
		push_error("[GameManager] Cannot open vehicles folder: " + VEHICLE_SCENES_FOLDER)
		return

	print("[GameManager] Scanning for vehicles...")
	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		if file_name.ends_with(".tscn") and not file_name.begins_with("."):
			var vehicle_name = file_name.get_basename()
			var scene_path = VEHICLE_SCENES_FOLDER + file_name
			var specific_tres = VEHICLE_CONFIGS_FOLDER + vehicle_name + ".tres"

			var config: VehicleConfig

			if ResourceLoader.exists(specific_tres):
				config = load(specific_tres) as VehicleConfig
				print("  ✓ %s (custom config, %d HP)" % [vehicle_name, config.get_horsepower()])
			else:
				config = _create_default_config(vehicle_name, scene_path)
				print("  ✓ %s (default config)" % vehicle_name)

			if config and config.is_valid():
				available_vehicles.append(config)
			else:
				push_warning("  ✗ Invalid config for: " + vehicle_name)

		file_name = dir.get_next()

	dir.list_dir_end()

	if available_vehicles.is_empty():
		push_error("[GameManager] No vehicles found in: " + VEHICLE_SCENES_FOLDER)
	else:
		print("[GameManager] Found %d vehicles" % available_vehicles.size())

## Generate a default config for any vehicle without a .tres
func _create_default_config(vehicle_name: String, scene_path: String) -> VehicleConfig:
	var config = VehicleConfig.new()
	config.vehicle_name = vehicle_name
	config.display_name = vehicle_name.replace("_", " ").capitalize()
	config.scene_path = scene_path
	config.mass = 1500.0

	var engine = EngineConfig.new()
	engine.idle_rpm = 1000.0
	engine.redline_rpm = 15000.0
	engine.rev_limiter_rpm = 17500.0
	engine.torque_curve = {
		1000.0: 200.0,
		3000.0: 3500.0,
		5000.0: 4000.0,
		7000.0: 3500.0
	}
	config.engine = engine

	var trans = TransmissionConfig.new()
	trans.gear_ratios.assign([3.50, 2.10, 1.50, 1.00])
	trans.final_drive = 4.10
	config.transmission = trans

	var tires = TireConfig.new()
	tires.compound_name = "Street"
	tires.friction_coefficient = 1.0
	config.front_tires = tires
	config.rear_tires = tires

	return config

## Get list of available vehicles
func get_available_vehicles() -> Array[VehicleConfig]:
	return available_vehicles

## Select vehicles for race
func select_vehicles(player_config: VehicleConfig, npc_config: VehicleConfig) -> bool:
	if not player_config or not player_config.is_valid():
		push_error("[GameManager] Invalid player config!")
		return false

	if not npc_config or not npc_config.is_valid():
		push_error("[GameManager] Invalid NPC config!")
		return false

	player_car_config = player_config
	npc_car_config = npc_config

	print("[GameManager] Selected vehicles:")
	print("  Player: %s" % player_config.display_name)
	print("  NPC: %s" % npc_config.display_name)

	return true

## Set spawn point markers
func set_spawn_markers(left_marker: Marker3D, right_marker: Marker3D) -> void:
	if not left_marker or not right_marker:
		push_error("[GameManager] Invalid spawn markers provided!")
		return

	left_lane_spawn = left_marker
	right_lane_spawn = right_marker
	print("[GameManager] Spawn markers set: left=%s, right=%s" % [
		left_marker.get_path(),
		right_marker.get_path()
	])

## Spawn vehicle body only (NO script attachment here)
## RaceManager handles script attachment after add_child
func spawn_vehicle(config: VehicleConfig, is_player: bool) -> VehicleBody3D:
	if not config or not config.is_valid():
		push_error("[GameManager] Invalid config for spawn!")
		return null

	if not left_lane_spawn or not right_lane_spawn:
		push_error("[GameManager] Spawn markers not set! Call set_spawn_markers() first.")
		return null

	var scene = load(config.scene_path)
	if not scene:
		push_error("[GameManager] Failed to load scene: %s" % config.scene_path)
		return null

	var vehicle_body = scene.instantiate()
	if not vehicle_body:
		push_error("[GameManager] Failed to instantiate scene!")
		return null

	if not vehicle_body is VehicleBody3D:
		push_error("[GameManager] Scene root is not VehicleBody3D! Scene: %s" % config.scene_path)
		vehicle_body.queue_free()
		return null

	var vehicle_lane = player_lane if is_player else ("left" if player_lane == "right" else "right")
	var spawn_marker = left_lane_spawn if vehicle_lane == "left" else right_lane_spawn

	vehicle_body.set_meta("spawn_lane", vehicle_lane)
	vehicle_body.set_meta("spawn_marker", spawn_marker)
	vehicle_body.set_meta("is_player", is_player)
	vehicle_body.set_meta("config", config)

	print("[GameManager] Created vehicle body for %s lane" % vehicle_lane.to_upper())

	return vehicle_body

## Set player lane preference
func set_player_lane(lane: String) -> void:
	if lane in ["left", "right"]:
		player_lane = lane
		print("[GameManager] Player lane: %s" % lane.to_upper())

## Get player lane
func get_player_lane() -> String:
	return player_lane

## Quick select for testing (first two vehicles)
func quick_select_default() -> void:
	if available_vehicles.size() >= 2:
		select_vehicles(available_vehicles[0], available_vehicles[1])
	elif available_vehicles.size() == 1:
		select_vehicles(available_vehicles[0], available_vehicles[0])
	else:
		push_error("[GameManager] No vehicles available for quick select!")

## Debug info
func get_debug_info() -> String:
	return "Vehicles: %d, Selected: %s vs %s" % [
		available_vehicles.size(),
		player_car_config.display_name if player_car_config else "None",
		npc_car_config.display_name if npc_car_config else "None"
	]
