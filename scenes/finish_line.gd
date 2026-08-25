extends Control

## Consumes timing_system.gd's both_finished signal directly:
##   left_results / right_results dicts use timing_system's own keys
##   (vehicle_name, reaction_time, time_60ft, time_330ft, time_660ft,
##   time_1000ft, elapsed_time, speed_mph, speed_kmh, red_light).
## winner is timing_system's own get_winner() result: "left" | "right" | "both_fouled".

signal rematch_requested
signal rematch_garage_first_requested
signal new_race_requested
signal end_requested
signal fish_requested

@onready var left_panel: PanelContainer = $VBoxContainer/LanesRow/LeftPanel
@onready var right_panel: PanelContainer = $VBoxContainer/LanesRow/RightPanel

@onready var left_name: Label = $VBoxContainer/LanesRow/LeftPanel/LeftVBox/LeftNameLabel
@onready var left_reaction: Label = $VBoxContainer/LanesRow/LeftPanel/LeftVBox/LeftReactionLabel
@onready var left_60: Label = $VBoxContainer/LanesRow/LeftPanel/LeftVBox/Left60Label
@onready var left_330: Label = $VBoxContainer/LanesRow/LeftPanel/LeftVBox/Left330Label
@onready var left_eighth: Label = $VBoxContainer/LanesRow/LeftPanel/LeftVBox/LeftEighthLabel
@onready var left_1000: Label = $VBoxContainer/LanesRow/LeftPanel/LeftVBox/Left1000Label
@onready var left_et: Label = $VBoxContainer/LanesRow/LeftPanel/LeftVBox/LeftETLabel
@onready var left_speed: Label = $VBoxContainer/LanesRow/LeftPanel/LeftVBox/LeftSpeedLabel

@onready var right_name: Label = $VBoxContainer/LanesRow/RightPanel/RightVBox/RightNameLabel
@onready var right_reaction: Label = $VBoxContainer/LanesRow/RightPanel/RightVBox/RightReactionLabel
@onready var right_60: Label = $VBoxContainer/LanesRow/RightPanel/RightVBox/Right60Label
@onready var right_330: Label = $VBoxContainer/LanesRow/RightPanel/RightVBox/Right330Label
@onready var right_eighth: Label = $VBoxContainer/LanesRow/RightPanel/RightVBox/RightEighthLabel
@onready var right_1000: Label = $VBoxContainer/LanesRow/RightPanel/RightVBox/Right1000Label
@onready var right_et: Label = $VBoxContainer/LanesRow/RightPanel/RightVBox/RightETLabel
@onready var right_speed: Label = $VBoxContainer/LanesRow/RightPanel/RightVBox/RightSpeedLabel

@onready var winner_image: TextureRect = $VBoxContainer/WinnerRow/WinnerImage
@onready var winner_label: Label = $VBoxContainer/WinnerRow/WinnerLabel

@onready var rematch_button: Button = $VBoxContainer/ButtonsRow/RematchButton
@onready var rematch_garage_button: Button = $VBoxContainer/ButtonsRow/RematchGarageButton
@onready var new_button: Button = $VBoxContainer/ButtonsRow/NewButton
@onready var end_button: Button = $VBoxContainer/ButtonsRow/EndButton
@onready var fish_button: Button = $VBoxContainer/ButtonsRow/FishButton

var _light_tween: Tween


func _ready() -> void:
	visible = false
	add_to_group("finish_line_ui")
	rematch_button.pressed.connect(func(): rematch_requested.emit())
	rematch_garage_button.pressed.connect(func(): rematch_garage_first_requested.emit())
	new_button.pressed.connect(func(): new_race_requested.emit())
	end_button.pressed.connect(func(): end_requested.emit())
	fish_button.pressed.connect(func(): fish_requested.emit())


## Connect directly: timing_system.both_finished.connect(finish_line.show_results)
## Optional portraits: pass winner_portrait if you look one up via VehicleRegistry
## before showing this scene.
func show_results(left_results: Dictionary, right_results: Dictionary, winner: String,
		winner_portrait: Texture2D = null) -> void:
	visible = true
	_reset_panel(left_panel)
	_reset_panel(right_panel)

	_fill_lane(left_results, left_name, left_reaction, left_60, left_330, left_eighth, left_1000, left_et, left_speed)
	_fill_lane(right_results, right_name, right_reaction, right_60, right_330, right_eighth, right_1000, right_et, right_speed)

	match winner:
		"left":
			_light_up(left_panel)
			winner_label.text = "WINNER: %s" % str(left_results.get("vehicle_name", ""))
		"right":
			_light_up(right_panel)
			winner_label.text = "WINNER: %s" % str(right_results.get("vehicle_name", ""))
		"both_fouled":
			winner_label.text = "BOTH DRIVERS FOULED - NO WINNER"
		_:
			winner_label.text = ""

	winner_image.texture = winner_portrait


func _fill_lane(data: Dictionary, name_label: Label, reaction_label: Label, sixty_label: Label,
		three30_label: Label, eighth_label: Label, thousand_label: Label, et_label: Label,
		speed_label: Label) -> void:
	name_label.text = str(data.get("vehicle_name", "--"))

	if data.get("red_light", false):
		reaction_label.text = "FOUL - RED LIGHT"
	else:
		reaction_label.text = _fmt_time(data.get("reaction_time", 0.0))

	sixty_label.text = _fmt_time(data.get("time_60ft", 0.0))
	three30_label.text = _fmt_time(data.get("time_330ft", 0.0))
	eighth_label.text = _fmt_time(data.get("time_660ft", 0.0))
	thousand_label.text = _fmt_time(data.get("time_1000ft", 0.0))
	et_label.text = _fmt_time(data.get("elapsed_time", 0.0))

	var speed_mph: float = data.get("speed_mph", 0.0)
	speed_label.text = "%.2f MPH (%.2f KM/H)" % [speed_mph, data.get("speed_kmh", 0.0)] if speed_mph > 0.0 else "--"


func _fmt_time(value: float) -> String:
	return "%.4f sec" % value if value > 0.0 else "--"


func _reset_panel(panel: PanelContainer) -> void:
	panel.remove_theme_stylebox_override("panel")
	panel.modulate = Color(1, 1, 1, 1)


func _light_up(panel: PanelContainer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.95, 0.4, 1.0)
	style.border_color = Color(1.0, 0.85, 0.0, 1.0)
	style.set_border_width_all(4)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)

	if _light_tween:
		_light_tween.kill()
	_light_tween = create_tween()
	_light_tween.set_loops()
	_light_tween.tween_property(panel, "modulate", Color(1.3, 1.3, 0.8, 1.0), 0.5)
	_light_tween.tween_property(panel, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.5)
