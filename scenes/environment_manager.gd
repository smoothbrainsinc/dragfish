# scripts/game/EnvironmentManager.gd
extends Node

@export var spectator_group: Node3D
@export var track_lights: Array[Light3D]

func _ready() -> void:
	# Listen to race events
	var race_controller = get_tree().get_first_node_in_group("race_controller")
	if race_controller:
		race_controller.connect("race_complete", _on_race_complete)

func _on_race_complete(_winner: String) -> void:
	# Animate spectators
	if spectator_group:
		for child in spectator_group.get_children():
			if child is AnimationPlayer:
				child.play("cheer")

func _update_track_lights() -> void:
	# Dynamic lighting based on time of day
	pass
