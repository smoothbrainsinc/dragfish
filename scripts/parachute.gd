extends Node3D
class_name DragChute

@export var drag_force: float = 80000.0
@export var deploy_time: float = 0.2

var is_deployed: bool = false
var deployment_progress: float = 0.0
var chute_mesh: MeshInstance3D = null

func _ready():
	chute_mesh = $ChuteMesh
	if chute_mesh:
		chute_mesh.visible = false
	set_physics_process(false)

func connect_to_finish_line():
	var finish_line = get_tree().get_first_node_in_group("finish_checkpoint")
	if finish_line:
		print("[Chute] Connected on: ", get_parent().name)
		finish_line.body_entered.connect(_on_finish_line_entered)
	else:
		print("[Chute] MISSED finish line!")


func _on_finish_line_entered(body: Node3D) -> void:
	print("[Chute] body_entered: ", body.name, " parent: ", get_parent().name)
	if body == get_parent():
		deploy()

func _physics_process(delta):
	var vehicle = get_parent() as VehicleBody3D
	if not vehicle:
		return
	if deployment_progress < 1.0:
		deployment_progress = min(1.0, deployment_progress + delta / deploy_time)
		if chute_mesh:
			chute_mesh.visible = true
			chute_mesh.scale = Vector3.ONE * deployment_progress
	var speed_ms = vehicle.linear_velocity.length()
	var speed_factor = min(1.0, speed_ms / 50.0)
	var effective_drag = drag_force * deployment_progress * speed_factor
	vehicle.apply_central_force(-vehicle.linear_velocity.normalized() * effective_drag)
	if chute_mesh and speed_ms > 1.0:
		chute_mesh.rotation_degrees.z = sin(Time.get_ticks_msec() * 0.01) * 10

func deploy():
	if is_deployed:
		return
	is_deployed = true
	deployment_progress = 0.0
	set_physics_process(true)
	print("[Chute] Deployed!")

func retract():
	is_deployed = false
	deployment_progress = 0.0
	set_physics_process(false)
	if chute_mesh:
		chute_mesh.visible = false
	print("[Chute] Retracted")
