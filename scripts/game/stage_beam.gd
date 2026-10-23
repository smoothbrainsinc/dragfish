extends Area3D
class_name StageBeam
## Place on an Area3D across a lane. Fires when that lane's vehicle enters/leaves.
## Set `lane` (1 = right, 2 = left, same numbering as the tree and spawn markers)
## and `kind`. Needs a CollisionShape3D and a collision mask that includes the
## vehicle's layer.

enum Kind { PRESTAGE, STAGE }

signal vehicle_entered(beam: StageBeam, vehicle: VehicleController)
signal vehicle_exited(beam: StageBeam, vehicle: VehicleController)

@export var kind: Kind = Kind.PRESTAGE
@export var lane: int = 1


func _ready() -> void:
	add_to_group("stage_beam")
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _lane_vehicle(body: Node3D) -> VehicleController:
	var v := body as VehicleController
	if v == null or int(v.get_meta("spawn_lane", -1)) != lane:
		return null
	return v


func _on_body_entered(body: Node3D) -> void:
	var v := _lane_vehicle(body)
	if v:
		vehicle_entered.emit(self, v)


func _on_body_exited(body: Node3D) -> void:
	var v := _lane_vehicle(body)
	if v:
		vehicle_exited.emit(self, v)
