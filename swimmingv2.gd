extends Node3D

@export_group("Movement")
@export var swim_speed: float = 2.0
@export var turn_speed: float = 3.0

@export_group("Lake Bounds")
@export var lake_size: Vector2 = Vector2(500, 500)
@export var lake_depth: float = 50.0
@export var surface_y: float = 0.0
@export var min_depth: float = 5.0

@export_group("Behavior")
@export var wander_time_min: float = 3.0
@export var wander_time_max: float = 8.0
@export var dive_chance: float = 0.3
@export var max_dive_depth: float = 0.8

@export_group("Obstacle Avoidance")
@export var avoidance_ray_length: float = 10.0
@export var avoidance_cooldown: float = 1.0

@onready var avoidance_ray: RayCast3D = $RayCast3D

var current_direction: Vector3 = Vector3.FORWARD
var target_direction: Vector3 = Vector3.FORWARD
var time_until_new_target: float = 0.0
var avoidance_timer: float = 0.0
var target_y: float = 0.0

func _ready():
	_randomize_direction()
	time_until_new_target = randf_range(wander_time_min, wander_time_max)
	target_y = global_position.y
	
	if avoidance_ray:
		avoidance_ray.target_position = Vector3(0, 0, -avoidance_ray_length)
		avoidance_ray.enabled = true

func _process(delta):
	_update_wandering(delta)
	_handle_avoidance(delta)
	_update_vertical_movement(delta)
	_apply_movement(delta)
	_constrain_to_bounds()
	_update_rotation(delta)

func _randomize_direction():
	var angle = randf() * TAU
	current_direction = Vector3(sin(angle), 0, cos(angle)).normalized()
	target_direction = current_direction

func _update_wandering(delta):
	time_until_new_target -= delta
	
	if time_until_new_target <= 0.0:
		var angle_change = randf_range(-PI/2, PI/2)
		var current_angle = atan2(current_direction.x, current_direction.z)
		var new_angle = current_angle + angle_change
		target_direction = Vector3(sin(new_angle), 0, cos(new_angle)).normalized()
		
		if randf() < dive_chance:
			target_y = surface_y - randf_range(min_depth, lake_depth * max_dive_depth)
		else:
			target_y = surface_y - randf_range(min_depth, min_depth + 10.0)
		
		time_until_new_target = randf_range(wander_time_min, wander_time_max)

func _handle_avoidance(delta):
	avoidance_timer -= delta
	
	if avoidance_ray and avoidance_timer <= 0.0:
		avoidance_ray.force_raycast_update()
		
		if avoidance_ray.is_colliding():
			var collision_point = avoidance_ray.get_collision_point()
			var to_obstacle = (collision_point - global_position).normalized()
			
			var avoidance_dir = to_obstacle.orthogonal().normalized()
			if randf() > 0.5:
				avoidance_dir = -avoidance_dir
			
			target_direction = avoidance_dir
			avoidance_timer = avoidance_cooldown
			target_y = global_position.y + randf_range(-10, 10)

func _update_vertical_movement(delta):
	var depth_speed = swim_speed * 0.5
	global_position.y = move_toward(global_position.y, target_y, depth_speed * delta)

func _apply_movement(delta):
	# Clamp delta to prevent the zero-vector freeze bug from your original script
	var t = min(turn_speed * delta, 1.0) 
	current_direction = current_direction.slerp(target_direction, t).normalized()
	
	if current_direction.length_squared() < 0.01:
		current_direction = Vector3.FORWARD
	
	global_position += current_direction * swim_speed * delta

func _constrain_to_bounds():
	var half_size = lake_size / 2.0
	var boundary_margin = 5.0
	
	if abs(global_position.x) > half_size.x - boundary_margin:
		global_position.x = clamp(global_position.x, -half_size.x + boundary_margin, half_size.x - boundary_margin)
		target_direction.x *= -1.0
	if abs(global_position.z) > half_size.y - boundary_margin:
		global_position.z = clamp(global_position.z, -half_size.y + boundary_margin, half_size.y - boundary_margin)
		target_direction.z *= -1.0
	
	global_position.y = clamp(global_position.y, surface_y - lake_depth, surface_y - min_depth)

func _update_rotation(delta):
	if current_direction.length_squared() < 0.01:
		return
	
	var look_ahead = 2.0
	var target_pos = global_position + current_direction * look_ahead
	
	var vertical_diff = target_y - global_position.y
	target_pos.y += vertical_diff * 0.3
	
	var target_basis = Basis.looking_at(target_pos - global_position, Vector3.UP)
	global_transform.basis = global_transform.basis.slerp(target_basis, turn_speed * delta).orthonormalized()
