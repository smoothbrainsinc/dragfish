extends Control
## Consumes timing_system.gd's all_finished signal:
##   left_results / right_results dicts use timing_system's own keys
##   (vehicle_name, reaction_time, time_60ft, time_330ft, time_660ft,
##   time_1000ft, elapsed_time, speed_mph, speed_kmh, red_light).
## winner is timing_system's get_winner() result mapped to: "left" | "right" | "both_fouled" | "".

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
@onready var results_delay_timer: Timer = $ResultsDelayTimer
@onready var left_blink: AnimationPlayer = $VBoxContainer/LanesRow/LeftPanel/WinnerBlink
@onready var right_blink: AnimationPlayer = $VBoxContainer/LanesRow/RightPanel/WinnerBlink

const WINNER_STYLE := preload("res://scenes/panel_winner.tres")

var _pending_left: Dictionary
var _pending_right: Dictionary
var _pending_winner: String
var _pending_portrait: Texture2D


func _ready() -> void:
	visible = false
	add_to_group("finish_line_ui")
	results_delay_timer.timeout.connect(_reveal_results)


## Connect: timing_system.all_finished.connect(finish_line.show_results)
func show_results(left_results: Dictionary, right_results: Dictionary, winner: String,
		winner_portrait: Texture2D = null) -> void:
	_pending_left = left_results
	_pending_right = right_results
	_pending_winner = winner
	_pending_portrait = winner_portrait
	results_delay_timer.start()


func _reveal_results() -> void:
	visible = true
	left_panel.remove_theme_stylebox_override("panel")
	right_panel.remove_theme_stylebox_override("panel")
	left_panel.modulate = Color(1, 1, 1, 1)
	right_panel.modulate = Color(1, 1, 1, 1)
	left_blink.stop()
	right_blink.stop()

	_fill_lane(_pending_left, left_name, left_reaction, left_60, left_330, left_eighth, left_1000, left_et, left_speed)
	_fill_lane(_pending_right, right_name, right_reaction, right_60, right_330, right_eighth, right_1000, right_et, right_speed)

	match _pending_winner:
		"left":
			left_panel.add_theme_stylebox_override("panel", WINNER_STYLE)
			left_blink.play("blink")
			winner_label.text = "WINNER: %s" % str(_pending_left.get("vehicle_name", ""))
		"right":
			right_panel.add_theme_stylebox_override("panel", WINNER_STYLE)
			right_blink.play("blink")
			winner_label.text = "WINNER: %s" % str(_pending_right.get("vehicle_name", ""))
		"both_fouled":
			winner_label.text = "BOTH DRIVERS FOULED - NO WINNER"
		_:
			winner_label.text = ""

	winner_image.texture = _pending_portrait


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
