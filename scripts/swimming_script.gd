extends Node3D

@export var swim_speed = 0.5
@export var turn_speed = 1.5
@export var lake_size = 500.0
@export var lake_depth = 50.0
@export var surface_y = 0.0
@export var dive_speed = 0.5
@export var rotate_speed = 1.0

var current_direction = 0.0
var time_to_turn = 0.0
var target_depth = 0.0
var avoid_cooldown = 0.0
var anim_player

@onready var ray = $RayCast3D

func _ready():
	current_direction = randf() * TAU
	time_to_turn = randf_range(2.0, 5.0)
	target_depth = 0.0

func _process(delta):
	avoid_cooldown -= delta

	# Obstacle avoidance — only trigger once per cooldown window
	if ray and ray.is_colliding() and avoid_cooldown <= 0.0:
		current_direction += randf_range(0.8, PI)
		time_to_turn = randf_range(1.0, 3.0)
		target_depth = randf_range(-lake_depth * 0.6, 0.0)
		avoid_cooldown = 1.0

	time_to_turn -= delta

	if time_to_turn <= 0:
		current_direction += randf_range(-1.2, 1.2)
		time_to_turn = randf_range(2.0, 5.0)
		target_depth = randf_range(-lake_depth * 0.6, 0.0)

	# Horizontal movement
	var target = Vector3(sin(current_direction), 0, cos(current_direction))
	var current = -global_transform.basis.z
	var new_dir = current.lerp(target, turn_speed * delta).normalized()

	global_position += new_dir * swim_speed * delta

	# Vertical movement toward target depth
	var target_y = surface_y + target_depth
	global_position.y = move_toward(global_position.y, target_y, dive_speed * delta)

	# Face direction of travel including pitch when diving
	var look_target = global_position + new_dir
	look_target.y = global_position.y + (target_y - global_position.y) * 0.3

	if look_target.distance_to(global_position) > 0.001:
		# FIX: use global_transform consistently throughout
		var target_transform = global_transform.looking_at(look_target, Vector3.UP)
		global_transform.basis = global_transform.basis.orthonormalized().slerp(
			target_transform.basis.orthonormalized(), rotate_speed * delta)

	# Keep within bounds — turn around if hitting a boundary edge
	var hit_boundary = false
	if abs(global_position.x) >= lake_size / 2:
		global_position.x = clamp(global_position.x, -lake_size / 2, lake_size / 2)
		hit_boundary = true
	if abs(global_position.z) >= lake_size / 2:
		global_position.z = clamp(global_position.z, -lake_size / 2, lake_size / 2)
		hit_boundary = true
	if hit_boundary:
		current_direction += PI  # turn around to re-enter bounds
		target_depth = randf_range(-lake_depth * 0.6, 0.0)

	global_position.y = clamp(global_position.y, surface_y - lake_depth, surface_y)
