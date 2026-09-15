@tool
extends Control
class_name Gauge2D

## Face texture goes on a TextureRect sibling/child (static, no script needed).
## Needle is a separate TextureRect/Sprite2D whose pivot_offset is set in the
## editor to sit exactly on the needle's pin (its rotation point).

@export var needle_path: NodePath = "Needle"
@export var value_min: float = 0.0
@export var value_max: float = 8000.0
@export var needle_angle_min_deg: float = -120.0
@export var needle_angle_max_deg: float = 120.0
@export var smoothing: float = 8.0  # higher = snappier, lower = laggier needle

## Editor-only calibration knob. Drag this in the Inspector while NOT running
## the scene to see the needle move live and line it up against the ticks.
## Has no effect at runtime (set_value() drives it instead).
@export_range(0.0, 8000.0, 1.0) var test_value: float = 0.0:
	set(v):
		test_value = v
		if Engine.is_editor_hint():
			_apply_rotation(v)

var _target_value: float = 0.0
var _current_value: float = 0.0
var _needle: Control

func _ready() -> void:
	_needle = get_node(needle_path)

func set_value(v: float) -> void:
	_target_value = clamp(v, value_min, value_max)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return  # editor preview is driven by test_value's setter instead
	_current_value = lerp(_current_value, _target_value, 1.0 - exp(-smoothing * delta))
	_apply_rotation(_current_value)

func _apply_rotation(v: float) -> void:
	if _needle == null:
		_needle = get_node_or_null(needle_path)
		if _needle == null:
			return
	var t: float = inverse_lerp(value_min, value_max, v)
	_needle.rotation_degrees = lerp(needle_angle_min_deg, needle_angle_max_deg, t)

func get_current_value() -> float:
	return _current_value
