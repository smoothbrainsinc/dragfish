extends Area3D
class_name StageBeam
## Staging zone across the lane(s). Needs a CollisionShape3D with a BoxShape3D,
## thin along its local Z (the travel direction, e.g. 0.1778 m = 7 in).
##
## Front tire edge crosses the near face  = PRESTAGED
## Front tire edge crosses the far face   = STAGED  (put this face on the start line)
##
## No lane setting: a vehicle is checked against the box's width, so one zone can
## span both lanes or you can use one per lane. The travel direction is taken from
## the vehicle, so it works whichever way the box's Z points.

enum State { NONE, PRESTAGED, STAGED }


func _ready() -> void:
	add_to_group("stage_beam")
	monitoring = false
	monitorable = false


func get_state(vehicle: VehicleController) -> State:
	var shape_node := _get_shape_node()
	if shape_node == null:
		return State.NONE
	var box := shape_node.shape as BoxShape3D
	if box == null:
		return State.NONE

	var p := shape_node.global_transform.affine_inverse() * front_point(vehicle)
	var half := box.size * 0.5
	if absf(p.x) > half.x:
		return State.NONE

	var dir := signf(vehicle.global_basis.z.dot(shape_node.global_basis.z))
	if dir == 0.0:
		dir = 1.0
	var along := p.z * dir
	if along < -half.z:
		return State.NONE
	if along < half.z:
		return State.PRESTAGED
	return State.STAGED


## Leading edge of the front tires (vehicle forward is +Z).
static func front_point(vehicle: VehicleController) -> Vector3:
	var sum := Vector3.ZERO
	var radius := 0.0
	for w in vehicle.steering_wheels:
		sum += w.global_position
		radius = maxf(radius, w.wheel_radius)
	var axle := vehicle.global_position
	if not vehicle.steering_wheels.is_empty():
		axle = sum / vehicle.steering_wheels.size()
	return axle + vehicle.global_basis.z.normalized() * radius


func _get_shape_node() -> CollisionShape3D:
	for c in get_children():
		if c is CollisionShape3D:
			return c
	return null
