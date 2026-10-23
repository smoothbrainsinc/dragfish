extends Node3D
class_name TireSmokeModule
## Tire smoke at every contact patch. Emits whenever a wheel loses grip
## (burnouts, launch wheelspin, brake lockup), driven by
## TirePhysicsModule.slip_intensity.

const SMOKE_THRESHOLD := 0.12

var _vehicle: VehicleBody3D
var _emitters: Dictionary = {}  # VehicleWheel3D -> CPUParticles3D
var _material: StandardMaterial3D
var _mesh: QuadMesh


func setup(vehicle: VehicleBody3D, wheels: Array[VehicleWheel3D]) -> void:
	_vehicle = vehicle
	_build_shared_resources()
	for w in wheels:
		var p := _make_emitter()
		add_child(p)
		_emitters[w] = p


## drive_dir: +1 forward, -1 reverse. Smoke is thrown opposite to the
## direction the tire surface is travelling.
func update_smoke(tires: TirePhysicsModule, drive_dir: float) -> void:
	for w: VehicleWheel3D in _emitters:
		var p: CPUParticles3D = _emitters[w]
		var intensity := tires.get_slip_intensity(w)
		var on := intensity > SMOKE_THRESHOLD and w.is_in_contact()

		if on:
			# Contact patch: straight down from the hub by one wheel radius
			p.global_position = w.global_position - _vehicle.global_basis.y * w.wheel_radius
			p.direction = Vector3(0.0, 0.45, -drive_dir)
			p.color = Color(1, 1, 1, clampf(0.35 + intensity * 0.65, 0.0, 1.0))
			p.scale_amount_max = lerpf(1.0, 2.2, intensity)

		if p.emitting != on:
			p.emitting = on


func stop() -> void:
	for p: CPUParticles3D in _emitters.values():
		p.emitting = false


func _build_shared_resources() -> void:
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_material.billboard_keep_scale = true
	_material.vertex_color_use_as_albedo = true
	_material.albedo_texture = tex
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	_mesh = QuadMesh.new()
	_mesh.size = Vector2(1.0, 1.0)


func _make_emitter() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = 48
	p.lifetime = 1.8
	p.local_coords = false
	p.mesh = _mesh
	p.material_override = _material

	p.direction = Vector3(0.0, 0.45, -1.0)  # up and back (vehicle forward is +Z)
	p.spread = 25.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0.0, 0.6, 0.0)
	p.damping_min = 0.6
	p.damping_max = 1.2

	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.4
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 3.0))
	p.scale_amount_curve = grow

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.12, 1.0])
	ramp.colors = PackedColorArray([
		Color(0.9, 0.9, 0.9, 0.0),
		Color(0.9, 0.9, 0.9, 0.55),
		Color(0.65, 0.65, 0.65, 0.0)
	])
	p.color_ramp = ramp
	return p
