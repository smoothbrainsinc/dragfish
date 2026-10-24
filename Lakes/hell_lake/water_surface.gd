extends Area3D
class_name WaterSurface
## Water volume. Put this on the water_surface Area3D. Its collision mask must
## include the vehicle's collision layer.
##
## Today: spawns a splash when a fast RigidBody3D (vehicle) enters.
## Buoyancy later: bodies_in_water, get_surface_height(), get_depth() and the
## _process_submerged() hook are the integration points, so nothing here needs
## to change shape when buoyancy is added.

signal body_entered_water(body: RigidBody3D, point: Vector3, speed: float)
signal body_exited_water(body: RigidBody3D)

## Entries slower than this (m/s) make no splash.
@export var min_splash_speed: float = 2.0
## Overall splash size multiplier.
@export var splash_scale: float = 1.0
## Mesh whose global Y is the water level. Defaults to the first MeshInstance3D child.
@export var surface_node: Node3D
## Added to the surface node's Y.
@export var surface_offset: float = 0.0

## Bodies currently overlapping the water. Buoyancy iterates this.
var bodies_in_water: Array[RigidBody3D] = []

var _material: StandardMaterial3D
var _drop_mesh: QuadMesh
var _mist_mesh: QuadMesh


func _ready() -> void:
	if surface_node == null:
		for c in get_children():
			if c is MeshInstance3D:
				surface_node = c
				break
	_build_shared_resources()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _physics_process(delta: float) -> void:
	for body in bodies_in_water:
		if is_instance_valid(body):
			_process_submerged(body, delta)


## Water level at a world position. Flat for now; override or extend for waves.
func get_surface_height(_world_pos: Vector3) -> float:
	var base := surface_node.global_position.y if surface_node else global_position.y
	return base + surface_offset


## How far below the surface a world point is (negative above water).
func get_depth(world_pos: Vector3) -> float:
	return get_surface_height(world_pos) - world_pos.y


## Called every physics frame for each body in the water. Buoyancy and drag go here.
func _process_submerged(_body: RigidBody3D, _delta: float) -> void:
	pass


func _on_body_entered(body: Node3D) -> void:
	var rb := body as RigidBody3D
	if rb == null:
		return
	if not bodies_in_water.has(rb):
		bodies_in_water.append(rb)

	var speed := rb.linear_velocity.length()
	var point := rb.global_position
	point.y = get_surface_height(point)
	body_entered_water.emit(rb, point, speed)
	if speed >= min_splash_speed:
		_spawn_splash(point, speed)


func _on_body_exited(body: Node3D) -> void:
	var rb := body as RigidBody3D
	if rb == null:
		return
	bodies_in_water.erase(rb)
	body_exited_water.emit(rb)


func _spawn_splash(point: Vector3, speed: float) -> void:
	var power := clampf(speed / 30.0, 0.15, 1.5) * splash_scale

	var spray := _make_spray(power)
	var mist := _make_mist(power)
	for p: CPUParticles3D in [spray, mist]:
		get_tree().current_scene.add_child(p)
		p.global_position = point
		p.emitting = true
		get_tree().create_timer(p.lifetime + 0.5).timeout.connect(p.queue_free)


func _make_spray(power: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = false
	p.local_coords = false
	p.amount = int(40.0 + 120.0 * power)
	p.lifetime = 1.4
	p.mesh = _drop_mesh
	p.material_override = _material
	p.direction = Vector3.UP
	p.spread = 40.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 6.0 + 10.0 * power
	p.gravity = Vector3(0.0, -9.8, 0.0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	ramp.colors = PackedColorArray([
		Color(0.9, 0.95, 1.0, 0.9),
		Color(0.9, 0.95, 1.0, 0.7),
		Color(0.9, 0.95, 1.0, 0.0)
	])
	p.color_ramp = ramp
	return p


func _make_mist(power: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.emitting = false
	p.local_coords = false
	p.amount = int(16.0 + 24.0 * power)
	p.lifetime = 2.0
	p.mesh = _mist_mesh
	p.material_override = _material
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.0 + 3.0 * power
	p.gravity = Vector3(0.0, -0.5, 0.0)
	p.damping_min = 0.8
	p.damping_max = 1.5
	p.scale_amount_min = 0.8 * power + 0.4
	p.scale_amount_max = 1.4 * power + 0.6
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 2.5))
	p.scale_amount_curve = grow
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	ramp.colors = PackedColorArray([
		Color(1, 1, 1, 0.0),
		Color(1, 1, 1, 0.45),
		Color(1, 1, 1, 0.0)
	])
	p.color_ramp = ramp
	return p


func _build_shared_resources() -> void:
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_material.billboard_keep_scale = true
	_material.vertex_color_use_as_albedo = true
	_material.albedo_texture = tex
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	_drop_mesh = QuadMesh.new()
	_drop_mesh.size = Vector2(0.15, 0.15)
	_mist_mesh = QuadMesh.new()
	_mist_mesh.size = Vector2(1.5, 1.5)
