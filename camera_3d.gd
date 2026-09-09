extends Camera3D

var speed = 40.0
var mouse_sensitivity = 0.003
var mouse_captured = false

var yaw = 0.0
var pitch = 0.0

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mouse_captured = true
	yaw = rotation.y
	pitch = rotation.x

func _input(event):
	if event is InputEventMouseMotion and mouse_captured:
		yaw -= event.relative.x * mouse_sensitivity
		pitch -= event.relative.y * mouse_sensitivity
		pitch = clamp(pitch, -PI / 2 + 0.01, PI / 2 - 0.01)
		rotation = Vector3(pitch, yaw, 0.0)
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		mouse_captured = false
	if event is InputEventMouseButton and event.pressed and not mouse_captured:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		mouse_captured = true
		yaw = rotation.y
		pitch = rotation.x

func _process(delta):
	var dir = Vector3.ZERO
	if Input.is_key_pressed(KEY_W): dir -= global_transform.basis.z
	if Input.is_key_pressed(KEY_S): dir += global_transform.basis.z
	if Input.is_key_pressed(KEY_A): dir -= global_transform.basis.x
	if Input.is_key_pressed(KEY_D): dir += global_transform.basis.x
	if Input.is_key_pressed(KEY_Q): dir -= global_transform.basis.y
	if Input.is_key_pressed(KEY_E): dir += global_transform.basis.y
	if dir.length_squared() > 0.0:
		global_position += dir.normalized() * speed * delta
