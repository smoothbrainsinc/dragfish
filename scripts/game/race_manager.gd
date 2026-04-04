extends Node
## Race Manager - Spawns and manages race vehicles

var player_vehicle: VehicleController = null
var npc_vehicle: VehicleController = null
var start_tree_node: Node

func _ready():
	add_to_group("race_manager")
	await get_tree().process_frame
	var left_marker = $left_lane_spawn
	var right_marker = $right_lane_spawn
	if not left_marker or not right_marker:
		push_error("[RaceManager] Spawn markers not found in scene!")
		return
	GameManager.set_spawn_markers(left_marker, right_marker)
	if not GameManager.player_car_config:
		push_error("[RaceManager] No player vehicle selected!")
		return
	print("[RaceManager] Starting race:")
	print("  Player: %s" % GameManager.player_car_config.display_name)
	print("  NPC: %s" % (GameManager.npc_car_config.display_name if GameManager.npc_car_config else "None"))
	await spawn_vehicles()
	var hud = get_tree().root.find_child("VehicleHUD", true, false)
	if hud and player_vehicle:
		hud.set_vehicle(player_vehicle)
	# Connect to green light
	start_tree_node = get_tree().get_first_node_in_group("start_tree")
	if start_tree_node and start_tree_node.has_signal("green_light"):
		start_tree_node.green_light.connect(_on_green_light)
		print("[RaceManager] Connected to green light signal")
	else:
		push_warning("[RaceManager] Could not connect to green light!")

func _on_green_light() -> void:
	print("[RaceManager] GREEN - Starting vehicles!")
	if player_vehicle:
		player_vehicle.start_race()
	if npc_vehicle:
		npc_vehicle.start_race()

func spawn_vehicles() -> void:
	var root = get_tree().current_scene

	# === SPAWN PLAYER ===
	print("\n[RaceManager] Spawning player vehicle...")
	var player_body = GameManager.spawn_vehicle(GameManager.player_car_config, true)

	if not player_body:
		push_error("[RaceManager] Failed to spawn player!")
		return

	root.add_child(player_body)

	var player_spawn_marker = player_body.get_meta("spawn_marker") as Marker3D
	var player_lane = player_body.get_meta("spawn_lane")

	player_body.global_transform = player_spawn_marker.global_transform
	player_body.set_script(preload("res://scripts/game/vehicle/VehicleController.gd"))

	await get_tree().process_frame

	player_vehicle = player_body as VehicleController

	if not player_vehicle:
		push_error("[RaceManager] Failed to cast player to VehicleController!")
		return

	player_vehicle.add_to_group(player_lane + "_vehicle")
	player_vehicle.add_to_group("player_vehicle")
	player_vehicle.initialize(GameManager.player_car_config, true)
	player_vehicle.start_vehicle()

	print("  ✓ Player ready: %s at %s" % [
		GameManager.player_car_config.vehicle_name,
		player_spawn_marker.global_position
	])

	# === SPAWN NPC (optional) ===
	if GameManager.npc_car_config != null:
		print("\n[RaceManager] Spawning NPC vehicle...")
		var npc_body = GameManager.spawn_vehicle(GameManager.npc_car_config, false)

		if not npc_body:
			push_error("[RaceManager] Failed to spawn NPC!")
			return

		root.add_child(npc_body)

		var npc_spawn_marker = npc_body.get_meta("spawn_marker") as Marker3D
		var npc_lane = npc_body.get_meta("spawn_lane")

		npc_body.global_transform = npc_spawn_marker.global_transform
		npc_body.set_script(preload("res://scripts/game/vehicle/VehicleController.gd"))

		await get_tree().process_frame

		npc_vehicle = npc_body as VehicleController

		if not npc_vehicle:
			push_error("[RaceManager] Failed to cast NPC to VehicleController!")
			return

		npc_vehicle.add_to_group(npc_lane + "_vehicle")
		npc_vehicle.add_to_group("npc_vehicle")
		npc_vehicle.initialize(GameManager.npc_car_config, false)
		npc_vehicle.start_vehicle()

		print("  ✓ NPC ready: %s at %s" % [
			GameManager.npc_car_config.vehicle_name,
			npc_spawn_marker.global_position
		])

		print("\n[RaceManager] === BOTH VEHICLES READY ===\n")
	else:
		print("\n[RaceManager] === SOLO RUN - NO NPC ===\n")

func restart_race() -> void:
	print("[RaceManager] Restarting race...")

	_cleanup_vehicle(player_vehicle)
	_cleanup_vehicle(npc_vehicle)

	player_vehicle = null
	npc_vehicle = null

	await get_tree().process_frame

	spawn_vehicles()

func _cleanup_vehicle(vehicle: VehicleController) -> void:
	if vehicle and is_instance_valid(vehicle):
		vehicle.stop_vehicle()
		vehicle.queue_free()

func get_player_vehicle() -> VehicleController:
	return player_vehicle

func get_npc_vehicle() -> VehicleController:
	return npc_vehicle

func are_vehicles_ready() -> bool:
	var player_ok: bool = player_vehicle != null and player_vehicle.is_initialized
	var npc_ok: bool = npc_vehicle == null or (is_instance_valid(npc_vehicle) and npc_vehicle.is_initialized)
	return player_ok and npc_ok
