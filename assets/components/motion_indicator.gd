class_name MotionIndicator
extends VBoxContainer

@onready var title_label: Label = $TitleLabel
@onready var value_label: Label = $ValueLabel

var current_value: float = 0.0

func set_title(text: String) -> void:
	if title_label:
		title_label.text = text

func set_value(value: float) -> void:
	current_value = value
	if value_label:
		value_label.text = str(value)
