extends Node

@onready var tree: Node3D = $start_tree

const BUTTON_MAP := {
	"preStageButton": "prestage",
	"StageButton": "stage",
	"ThreeButton": "amber3",
	"TwoButton": "amber2",
	"OneButton": "amber1",
	"GoButton": "green",
	"FoulButton": "red",
}

var _state := {}

func _ready():
	_wire_container($HBoxContainer/LeftVBoxContainer, 2)
	_wire_container($HBoxContainer/RightVBoxContainer2, 1)

func _wire_container(container: Node, lane: int) -> void:
	for child in container.get_children():
		if child is Button and BUTTON_MAP.has(child.name):
			var light_name: String = BUTTON_MAP[child.name]
			_state[[lane, light_name]] = false
			child.pressed.connect(_on_button_pressed.bind(lane, light_name))

func _on_button_pressed(lane: int, light_name: String) -> void:
	var key = [lane, light_name]
	var new_state: bool = not _state.get(key, false)
	_state[key] = new_state
	tree.set_light(lane, light_name, new_state)
	print("[Test] Lane %d - %s -> %s" % [lane, light_name, new_state])
