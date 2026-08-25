extends Camera3D
class_name FreeCam
## Fly camera: hold right mouse to look, WASD to move, Q/E down/up, Shift fast.

var speed := 6.0
var _looking := false

func _unhandled_input(event: InputEvent) -> void:
	if not current:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_looking = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _looking else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and _looking:
		rotation.y -= event.relative.x * 0.0025
		rotation.x = clampf(rotation.x - event.relative.y * 0.0025, -1.5, 1.5)

func _process(delta: float) -> void:
	if not current:
		return
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		dir -= transform.basis.z
	if Input.is_key_pressed(KEY_S):
		dir += transform.basis.z
	if Input.is_key_pressed(KEY_A):
		dir -= transform.basis.x
	if Input.is_key_pressed(KEY_D):
		dir += transform.basis.x
	if Input.is_key_pressed(KEY_E):
		dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		dir -= Vector3.UP
	if dir.length_squared() > 0.001:
		var sp := speed * (3.5 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
		position += dir.normalized() * sp * delta
