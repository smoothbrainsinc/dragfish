extends Camera3D

@export var speed := 40.0
@export var mouse_sensitivity := 0.003

var yaw := 0.0
var pitch := 0.0

func _ready() -> void:
	set_active(current)

func set_active(active: bool) -> void:
	set_process(active)
	set_process_input(active)
	if active:
		yaw = rotation.y
		pitch = rotation.x

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sensitivity
		pitch = clamp(pitch - event.relative.y * mouse_sensitivity, -PI / 2 + 0.01, PI / 2 - 0.01)
		rotation = Vector3(pitch, yaw, 0.0)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): dir -= global_transform.basis.z
	if Input.is_key_pressed(KEY_S): dir += global_transform.basis.z
	if Input.is_key_pressed(KEY_A): dir -= global_transform.basis.x
	if Input.is_key_pressed(KEY_D): dir += global_transform.basis.x
	if Input.is_key_pressed(KEY_Q): dir -= global_transform.basis.y
	if Input.is_key_pressed(KEY_E): dir += global_transform.basis.y
	if dir.length_squared() > 0.0:
		global_position += dir.normalized() * speed * delta
