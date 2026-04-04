extends Camera3D

var speed = 80.0
var mouse_sensitivity = 0.003
var mouse_captured = false

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mouse_captured = true

func _input(event):
	if event is InputEventMouseMotion and mouse_captured:
		rotate_y(-event.relative.x * mouse_sensitivity)
		rotate_object_local(Vector3.RIGHT, -event.relative.y * mouse_sensitivity)
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		mouse_captured = false

func _process(delta):
	var dir = Vector3.ZERO
	if Input.is_key_pressed(KEY_W): dir -= global_transform.basis.z
	if Input.is_key_pressed(KEY_S): dir += global_transform.basis.z
	if Input.is_key_pressed(KEY_A): dir -= global_transform.basis.x
	if Input.is_key_pressed(KEY_D): dir += global_transform.basis.x
	if Input.is_key_pressed(KEY_Q): dir -= global_transform.basis.y
	if Input.is_key_pressed(KEY_E): dir += global_transform.basis.y
	global_position += dir.normalized() * speed * delta
