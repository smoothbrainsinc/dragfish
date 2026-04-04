# scripts/game/VisualEffectsManager.gd
extends Node

@export var fireworks: GPUParticles3D
@export var crowd_cheer_sound: AudioStreamPlayer3D

func _ready() -> void:
	# Listen to global race events
	var race_controller = get_tree().get_first_node_in_group("race_controller")
	if race_controller:
		race_controller.connect("race_complete", _on_race_complete)

func _on_race_complete(_winner: String) -> void:
	# Trigger fireworks
	if fireworks:
		fireworks.emitting = true
		fireworks.restart()
	
	# Play crowd cheer
	if crowd_cheer_sound:
		crowd_cheer_sound.play()
