extends Node3D
## Standalone deep-water ocean demo: Gerstner trochoidal waves only, no
## shallow-water solver. Keys 1/2/3 switch sea-state presets; F7-style free
## flight is always active (right mouse to look, WASD, Q/E, Shift).

var ocean_mat: ShaderMaterial
var _fps_label: Label
var _fps_accum := 0.0

const PRESETS := {
	KEY_1: {"name": "calm", "base_wavelength": 55.0, "amplitude": 0.35, "steepness": 0.45, "spread_deg": 22.0, "foam_amount": 0.25},
	KEY_2: {"name": "moderate", "base_wavelength": 90.0, "amplitude": 1.1, "steepness": 0.75, "spread_deg": 28.0, "foam_amount": 1.0},
	KEY_3: {"name": "storm", "base_wavelength": 150.0, "amplitude": 2.6, "steepness": 0.95, "spread_deg": 38.0, "foam_amount": 1.6},
}

func _ready() -> void:
	_build_environment()
	_build_ocean()
	_build_camera()
	_build_ui()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("sea="):
			var wanted := a.split("=")[1]
			for key in PRESETS:
				if PRESETS[key]["name"] == wanted:
					_apply_preset(PRESETS[key])

func _apply_preset(p: Dictionary) -> void:
	for key in p:
		if key != "name":
			ocean_mat.set_shader_parameter(key, p[key])

func _build_environment() -> void:
	var env := Environment.new()
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = load("res://assets/hdri/secluded_beach_4k.exr")
	var sky := Sky.new()
	sky.sky_material = pano
	sky.radiance_size = Sky.RADIANCE_SIZE_512
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 1.2
	env.glow_intensity = 0.4
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, 142.0, 0.0)
	sun.light_energy = 1.35
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = false # nothing casts onto open water
	add_child(sun)

func _build_ocean() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(3000.0, 3000.0)
	mesh.subdivide_width = 798
	mesh.subdivide_depth = 798
	ocean_mat = ShaderMaterial.new()
	ocean_mat.shader = load("res://shaders/gerstner_ocean.gdshader")
	ocean_mat.set_shader_parameter("detail_normal_tex", load("res://assets/generated/detail_ripple_normal.png"))
	ocean_mat.set_shader_parameter("lace_tex", load("res://assets/generated/voronoi_lace.png"))
	var mi := MeshInstance3D.new()
	mi.name = "Ocean"
	mi.mesh = mesh
	mi.material_override = ocean_mat
	mi.custom_aabb = AABB(Vector3(-1500, -20, -1500), Vector3(3000, 40, 3000))
	add_child(mi)

func _build_camera() -> void:
	var cam := FreeCam.new()
	cam.name = "FreeCam"
	cam.fov = 65.0
	cam.far = 6000.0
	cam.speed = 25.0
	add_child(cam)
	# face the open-sea sector of the panorama, not the cove vegetation
	cam.look_at_from_position(Vector3(0.0, 24.0, 0.0), Vector3(-260.0, 2.0, 140.0), Vector3.UP)
	cam.current = true

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	_fps_label = Label.new()
	_fps_label.add_theme_font_size_override("font_size", 15)
	_fps_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	_fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_fps_label.position = Vector2(-120, 8)
	layer.add_child(_fps_label)
	var help := Label.new()
	help.text = "1 calm  2 moderate  3 storm   free cam: RMB look, WASD, Q/E, Shift"
	help.add_theme_font_size_override("font_size", 14)
	help.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help.position = Vector2(10, -30)
	layer.add_child(help)
	add_child(layer)

func _process(delta: float) -> void:
	_fps_accum += delta
	if _fps_accum >= 0.5:
		_fps_label.text = "%d FPS" % Engine.get_frames_per_second()
		_fps_accum = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if PRESETS.has(event.keycode):
			_apply_preset(PRESETS[event.keycode])
