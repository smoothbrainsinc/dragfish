extends PanelContainer

const CAR_SELECTION_SCENE := "res://scenes/new_car_selection_screen.tscn"

func _on_choose_vehicle_pressed() -> void:
	get_tree().change_scene_to_file(CAR_SELECTION_SCENE)

func _on_quit_pressed() -> void:
	get_tree().quit()
