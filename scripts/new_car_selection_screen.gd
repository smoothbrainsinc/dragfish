extends Control

# Nodes
@onready var tree: Tree = $MarginContainer/VBoxContainer/HBoxContainer2/LeftPanelContainer/VBoxContainer/ScrollContainer/Tree
@onready var search: LineEdit = $MarginContainer/VBoxContainer/HBoxContainer2/LeftPanelContainer/VBoxContainer/LineEdit
@onready var viewport: SubViewport = $MarginContainer/VBoxContainer/HBoxContainer2/RightPanelContainer/VBoxContainer/SubViewportContainer/SubViewport
@onready var car_label: Label = $MarginContainer/VBoxContainer/HBoxContainer2/RightPanelContainer/VBoxContainer/Label
@onready var race_selected_btn: Button = $MarginContainer/VBoxContainer/HBoxContainer/RaceSelected_Button
@onready var race_last_btn: Button = $MarginContainer/VBoxContainer/HBoxContainer/RaceLast_Button

const CONFIGS_PATH = "res://vehicles/configs/"
const RACE_SCENE = "res://scenes/pluto_raceway.tscn"
const PIT_SCENE = "res://assets/components/pit_area_ui.tscn"

# Colors
const COLOR_DEFAULT = Color(1, 1, 1, 1)
const COLOR_PLAYER = Color(0.3, 1.0, 0.3, 1)   # Green
const COLOR_NPC = Color(0.3, 0.3, 1.0, 1)       # Blue
const COLOR_BOTH = Color(1.0, 0.3, 1.0, 1)      # Purple

var all_configs: Array = []
var player_config: VehicleConfig = null
var npc_config: VehicleConfig = null
var current_preview_car: Node = null

func _ready():
	_load_all_configs()
	_populate_tree(all_configs)
	_load_last_car()
	search.text_changed.connect(_on_search_changed)
	# Connect to gui_input to handle left/right click separately
	tree.gui_input.connect(_on_tree_gui_input)

func _load_all_configs() -> void:
	all_configs.clear()
	var dir = DirAccess.open(CONFIGS_PATH)
	if not dir:
		push_error("Cannot open configs folder: " + CONFIGS_PATH)
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var config = load(CONFIGS_PATH + file_name)
			if config is VehicleConfig:
				all_configs.append(config)
		file_name = dir.get_next()
	dir.list_dir_end()

func _populate_tree(configs: Array) -> void:
	tree.clear()
	var root = tree.create_item()

	var classes: Dictionary = {}
	for config in configs:
		var class_name_str = config.vehicle_class.display_name if config.vehicle_class else "Uncategorized"
		if not classes.has(class_name_str):
			classes[class_name_str] = []
		classes[class_name_str].append(config)
	
	for class_name_str in classes:
		var class_item = tree.create_item(root)
		class_item.set_text(0, class_name_str)
		class_item.set_selectable(0, false)
		class_item.set_collapsed(false)
		
		for config in classes[class_name_str]:
			var car_item = tree.create_item(class_item)
			car_item.set_text(0, config.display_name)
			car_item.set_metadata(0, config)
	
	_update_all_colors()

func _update_all_colors() -> void:
	var root = tree.get_root()
	if not root:
		return
	
	for class_item in root.get_children():
		for car_item in class_item.get_children():
			var config = car_item.get_metadata(0)
			if not config:
				continue
			
			if config == player_config and config == npc_config:
				car_item.set_custom_color(0, COLOR_BOTH)
			elif config == player_config:
				car_item.set_custom_color(0, COLOR_PLAYER)
			elif config == npc_config:
				car_item.set_custom_color(0, COLOR_NPC)
			else:
				car_item.set_custom_color(0, COLOR_DEFAULT)

func _on_search_changed(text: String) -> void:
	if text.strip_edges() == "":
		_populate_tree(all_configs)
		return
	var filtered: Array = []
	for config in all_configs:
		if config.display_name.to_lower().contains(text.to_lower()):
			filtered.append(config)
	_populate_tree(filtered)

func _on_tree_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mouse_pos = tree.get_local_mouse_position()
		var item = tree.get_item_at_position(mouse_pos)
		if not item:
			return
		var config = item.get_metadata(0)
		if not config:
			return
		
		if event.button_index == MOUSE_BUTTON_LEFT:
			# Left click = Player
			player_config = config
			_update_all_colors()
			_update_display()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# Right click = NPC
			npc_config = config
			_update_all_colors()
			_update_display()
		# Prevent the event from propagating further
		tree.accept_event()

func _update_display() -> void:
	if player_config:
		if npc_config and npc_config != player_config:
			car_label.text = "Player: %s | NPC: %s" % [
				player_config.display_name,
				npc_config.display_name
			]
		elif npc_config == player_config:
			car_label.text = "Player & NPC: %s" % player_config.display_name
		else:
			car_label.text = "Player: %s" % player_config.display_name
		race_selected_btn.disabled = false
		_load_preview(player_config.scene_path)
	else:
		car_label.text = "Left-click for Player, Right-click for NPC"
		race_selected_btn.disabled = true

func _load_preview(scene_path: String) -> void:
	if current_preview_car and is_instance_valid(current_preview_car):
		current_preview_car.queue_free()
		current_preview_car = null
	
	var scene = load(scene_path)
	if not scene:
		push_error("Failed to load preview: " + scene_path)
		return
	
	var vehicle = scene.instantiate()
	_disable_physics(vehicle)
	viewport.add_child(vehicle)
	vehicle.position = Vector3.ZERO
	vehicle.rotation_degrees = Vector3(0, 30, 0)
	current_preview_car = vehicle

func _disable_physics(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	if node is VehicleBody3D:
		node.freeze = true
	for child in node.get_children():
		_disable_physics(child)

func _load_last_car() -> void:
	if not GameManager.last_raced_config:
		race_last_btn.disabled = true
		return
	player_config = GameManager.last_raced_config
	_update_all_colors()
	_update_display()

func _on_race_selected_pressed() -> void:
	if not player_config:
		return
	GameManager.player_car_config = player_config
	GameManager.npc_car_config = npc_config if npc_config != player_config else null
	GameManager.last_raced_config = player_config
	get_tree().change_scene_to_file(RACE_SCENE)

func _on_race_last_pressed() -> void:
	if not GameManager.last_raced_config:
		return
	GameManager.player_car_config = GameManager.last_raced_config
	GameManager.npc_car_config = null
	get_tree().change_scene_to_file(RACE_SCENE)

func _on_pit_pressed() -> void:
	if player_config:
		GameManager.player_car_config = player_config
		GameManager.npc_car_config = npc_config if npc_config != player_config else null
	get_tree().change_scene_to_file(PIT_SCENE)

func _on_details_pressed() -> void:
	pass

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/start_scene.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()

func _exit_tree() -> void:
	if current_preview_car and is_instance_valid(current_preview_car):
		current_preview_car.queue_free()
