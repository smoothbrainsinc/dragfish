extends Node3D
## Scene bootstrap: builds sim, water surface, terrain, cameras, lighting, debug overlay in code.

const TEX := "res://assets/textures"

var sim: SimController
var water_mat: ShaderMaterial
var terrain: MeshInstance3D
var props_root: Node3D
var wall_mesh: MeshInstance3D
var debug_look := false
var _fps_label: Label
var _fps_accum := 0.0
var _fps_ticks := 0
var _last_sim_time := 0.0

func _process(delta: float) -> void:
	_fps_accum += delta
	if _fps_accum >= 0.5 and _fps_label != null:
		var sim_rate := (sim.sim_time - _last_sim_time) / _fps_accum
		_last_sim_time = sim.sim_time
		_fps_label.text = "%d FPS · sim ×%.2f" % [Engine.get_frames_per_second(), sim_rate]
		_fps_accum = 0.0
		_fps_ticks += 1
		if _fps_ticks % 4 == 0 and not OS.get_cmdline_user_args().is_empty():
			print("[fps] %d sim x%.2f" % [Engine.get_frames_per_second(), sim_rate])

func _parse_args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.split("=", true, 1)
		if kv.size() == 2:
			out[kv[0]] = kv[1]
	return out

func _ready() -> void:
	var args := _parse_args()
	sim = SimController.new()
	sim.name = "SimController"
	match String(args.get("scenario", "beach")):
		"wall":
			sim.kind = SimController.Kind.WALL
		"dambreak":
			sim.kind = SimController.Kind.DAM_BREAK
		"ocean":
			sim.kind = SimController.Kind.OCEAN
		_:
			sim.kind = SimController.Kind.BEACH
	# amp/period 0 = use the scenario's own defaults from SimController.CFG
	sim.wave_amp = float(args.get("amp", "0"))
	sim.wave_period = float(args.get("period", "0"))
	debug_look = String(args.get("look", "")) == "debug"
	add_child(sim)
	if args.has("wave") and float(args["wave"]) < 0.5:
		sim.wave_mode = 0.0
	if sim.kind == SimController.Kind.OCEAN and not debug_look:
		# FSR2 temporal upscale: ~35% fewer shaded pixels, visually transparent
		get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
		get_viewport().scaling_3d_scale = 0.77
		get_viewport().use_taa = false # FSR2 is temporal already
	_build_environment()
	_build_water()
	_build_terrain()
	_build_cameras()
	_build_debug_overlay()
	var solo := float(args.get("solo", "0"))
	if solo > 0.0:
		var timer := get_tree().create_timer(solo)
		timer.timeout.connect(sim.trigger_solitary)

func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	if debug_look:
		sky.sky_material = ProceduralSkyMaterial.new()
	else:
		var pano := PanoramaSkyMaterial.new()
		pano.panorama = load("res://assets/hdri/secluded_beach_4k.exr")
		sky.sky_material = pano
		sky.radiance_size = Sky.RADIANCE_SIZE_512
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	if not debug_look:
		env.ssr_enabled = true
		env.ssr_max_steps = 128
		env.ssr_fade_in = 0.15
		env.ssr_fade_out = 2.0
		env.ssao_enabled = true
		env.ssao_radius = 1.0
		env.ssao_intensity = 2.0
		# SSIL contributes nothing visible over open water; ocean skips its ~5 ms
		env.ssil_enabled = sim.kind != SimController.Kind.OCEAN
		env.ssil_radius = 5.0
		env.glow_enabled = true
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
		env.glow_hdr_threshold = 1.2
		env.glow_intensity = 0.4
	var we := WorldEnvironment.new()
	we.name = "WorldEnv"
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	# roughly matched to the secluded_beach HDRI sun (mid elevation, warm)
	sun.rotation_degrees = Vector3(-48.0, 142.0, 0.0)
	sun.light_energy = 1.35
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 1200.0 if sim.kind == SimController.Kind.OCEAN else 70.0
	sun.light_angular_distance = 0.53
	add_child(sun)

func _build_water() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(sim.domain, sim.domain)
	# ocean: 768^2 verts (2.7 m cells) — per-pixel normals carry the detail,
	# the geometry only needs to follow waves 13 m and longer
	var verts: int = mini(sim.n, 768 if sim.kind == SimController.Kind.OCEAN else 1024)
	mesh.subdivide_width = verts - 2
	mesh.subdivide_depth = verts - 2
	water_mat = ShaderMaterial.new()
	if debug_look:
		water_mat.shader = load("res://shaders/debug_surface.gdshader")
		water_mat.set_shader_parameter("tx_state", sim.tex_state)
		water_mat.set_shader_parameter("tx_bottom", sim.tex_bottom)
	else:
		water_mat.shader = load("res://shaders/water.gdshader")
		water_mat.set_shader_parameter("tx_state", sim.tex_state)
		water_mat.set_shader_parameter("tx_bottom", sim.tex_bottom)
		water_mat.set_shader_parameter("tx_derived", sim.tex_derived)
		water_mat.set_shader_parameter("lace_tex", load("res://assets/generated/voronoi_lace.png"))
		water_mat.set_shader_parameter("flow_noise_tex", load("res://assets/generated/flow_noise.png"))
		water_mat.set_shader_parameter("DOMAIN_SIZE", sim.domain)
		water_mat.set_shader_parameter("GRID_RES", float(sim.n))
		if sim.kind == SimController.Kind.OCEAN:
			water_mat.set_shader_parameter("gerstner_amp", 0.85)
			# lace stays FINE (per-pixel pattern, independent of sim cells);
			# only slightly coarser than the beach so drone shots keep texture
			water_mat.set_shader_parameter("lace_scale_coarse", 1.6)
			water_mat.set_shader_parameter("lace_scale_fine", 0.18)
			water_mat.set_shader_parameter("detail_base", 0.55)
			water_mat.set_shader_parameter("foam_breakup", 0.8)
			water_mat.set_shader_parameter("breakup_scale", 7.0)
			water_mat.set_shader_parameter("tuck_h", 0.06)
			# softer foam albedo: at ocean exposure 0.85 blooms into cotton
			water_mat.set_shader_parameter("foam_albedo", Vector3(0.72, 0.72, 0.72))
			# cheap 2-tap detail normals (render-bound at ocean scale)
			water_mat.set_shader_parameter("detail_use_tex", 1.0)
			water_mat.set_shader_parameter("detail_normal_tex", load("res://assets/generated/detail_ripple_normal.png"))
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = mesh
	mi.material_override = water_mat
	mi.position = Vector3(sim.domain * 0.5, 0.0, sim.domain * 0.5)
	# displaced in the vertex shader: give the culler room
	mi.custom_aabb = AABB(Vector3(-sim.domain, -40.0, -sim.domain), Vector3(sim.domain * 2.0, 80.0, sim.domain * 2.0))
	add_child(mi)

func _tex(path: String) -> Texture2D:
	return load(path) as Texture2D

func _build_terrain() -> void:
	for old in [terrain, props_root, wall_mesh]:
		if old != null:
			old.queue_free()
	terrain = null
	props_root = null
	wall_mesh = null
	if sim.kind == SimController.Kind.DAM_BREAK:
		return
	if sim.kind == SimController.Kind.OCEAN:
		_build_ocean_terrain()
		return
	var built := Scenario.build(0 if sim.kind == SimController.Kind.BEACH else 1)
	terrain = MeshInstance3D.new()
	terrain.name = "Terrain"
	terrain.mesh = built["terrain_mesh"]
	if debug_look:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.76, 0.66, 0.5)
		mat.roughness = 0.95
		terrain.material_override = mat
	else:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/sand.gdshader")
		mat.set_shader_parameter("tx_ground", sim.tex_ground)
		mat.set_shader_parameter("tx_state", sim.tex_state)
		mat.set_shader_parameter("caustics_tex", _tex("res://assets/generated/caustics.png"))
		mat.set_shader_parameter("lace_tex", _tex("res://assets/generated/voronoi_lace.png"))
		mat.set_shader_parameter("sand_diff", _tex(TEX + "/coast_sand_01/coast_sand_01_diff_4k.jpg"))
		mat.set_shader_parameter("sand_nor", _tex(TEX + "/coast_sand_01/coast_sand_01_nor_gl_4k.jpg"))
		mat.set_shader_parameter("sand_arm", _tex(TEX + "/coast_sand_01/coast_sand_01_arm_4k.jpg"))
		mat.set_shader_parameter("aerial_diff", _tex(TEX + "/aerial_beach_01/aerial_beach_01_diff_4k.jpg"))
		mat.set_shader_parameter("rocks_diff", _tex(TEX + "/coast_sand_rocks_02/coast_sand_rocks_02_diff_4k.jpg"))
		mat.set_shader_parameter("rocks_nor", _tex(TEX + "/coast_sand_rocks_02/coast_sand_rocks_02_nor_gl_4k.jpg"))
		mat.set_shader_parameter("rocks_arm", _tex(TEX + "/coast_sand_rocks_02/coast_sand_rocks_02_arm_4k.jpg"))
		mat.set_shader_parameter("damp_diff", _tex(TEX + "/damp_sand/damp_sand_diff_4k.jpg"))
		mat.set_shader_parameter("damp_nor", _tex(TEX + "/damp_sand/damp_sand_nor_gl_4k.jpg"))
		mat.set_shader_parameter("damp_arm", _tex(TEX + "/damp_sand/damp_sand_arm_4k.jpg"))
		terrain.material_override = mat
	add_child(terrain)

	if sim.kind == SimController.Kind.BEACH and not debug_look:
		props_root = Node3D.new()
		props_root.name = "Rocks"
		add_child(props_root)
		for prop in built["props"]:
			var scene := load(prop["path"]) as PackedScene
			if scene == null:
				push_warning("prop failed to load: " + str(prop["path"]))
				continue
			var inst := scene.instantiate() as Node3D
			inst.transform = prop["transform"]
			props_root.add_child(inst)

	if sim.kind == SimController.Kind.WALL:
		var aabb: AABB = built["wall_aabb"]
		var box := BoxMesh.new()
		box.size = aabb.size
		wall_mesh = MeshInstance3D.new()
		wall_mesh.name = "QuayWall"
		wall_mesh.mesh = box
		wall_mesh.position = aabb.position + aabb.size * 0.5
		if not debug_look:
			var wmat := ShaderMaterial.new()
			wmat.shader = load("res://shaders/wall.gdshader")
			wmat.set_shader_parameter("tx_ground", sim.tex_ground)
			wmat.set_shader_parameter("blocks_diff", _tex(TEX + "/medieval_blocks_02/medieval_blocks_02_diff_4k.jpg"))
			wmat.set_shader_parameter("blocks_nor", _tex(TEX + "/medieval_blocks_02/medieval_blocks_02_nor_gl_4k.jpg"))
			wmat.set_shader_parameter("blocks_arm", _tex(TEX + "/medieval_blocks_02/medieval_blocks_02_arm_4k.jpg"))
			wmat.set_shader_parameter("moss_diff", _tex(TEX + "/mossy_sandstone/mossy_sandstone_diff_2k.jpg"))
			wmat.set_shader_parameter("moss_nor", _tex(TEX + "/mossy_sandstone/mossy_sandstone_nor_gl_2k.jpg"))
			wmat.set_shader_parameter("moss_arm", _tex(TEX + "/mossy_sandstone/mossy_sandstone_arm_2k.jpg"))
			wall_mesh.material_override = wmat
		add_child(wall_mesh)

func _build_ocean_terrain() -> void:
	# a displaced plane driven by the same bottom texture the solver uses:
	# no CPU mesh build, instant startup, terrain always matches the water
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(sim.domain, sim.domain)
	mesh.subdivide_width = 1022
	mesh.subdivide_depth = 1022
	terrain = MeshInstance3D.new()
	terrain.name = "Terrain"
	terrain.mesh = mesh
	terrain.position = Vector3(sim.domain * 0.5, 0.0, sim.domain * 0.5)
	terrain.custom_aabb = AABB(Vector3(-sim.domain, -60.0, -sim.domain), Vector3(sim.domain * 2.0, 120.0, sim.domain * 2.0))
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/ocean_terrain.gdshader")
	mat.set_shader_parameter("DOMAIN_SIZE", sim.domain)
	mat.set_shader_parameter("GRID_RES", float(sim.n))
	mat.set_shader_parameter("tx_bottom", sim.tex_bottom)
	mat.set_shader_parameter("tx_ground", sim.tex_ground)
	mat.set_shader_parameter("lace_tex", _tex("res://assets/generated/voronoi_lace.png"))
	mat.set_shader_parameter("sand_diff", _tex(TEX + "/coast_sand_01/coast_sand_01_diff_4k.jpg"))
	mat.set_shader_parameter("sand_nor", _tex(TEX + "/coast_sand_01/coast_sand_01_nor_gl_4k.jpg"))
	mat.set_shader_parameter("sand_arm", _tex(TEX + "/coast_sand_01/coast_sand_01_arm_4k.jpg"))
	mat.set_shader_parameter("grass_diff", _tex(TEX + "/aerial_grass_rock/aerial_grass_rock_diff_4k.jpg"))
	mat.set_shader_parameter("grass_nor", _tex(TEX + "/aerial_grass_rock/aerial_grass_rock_nor_gl_4k.jpg"))
	mat.set_shader_parameter("grass_arm", _tex(TEX + "/aerial_grass_rock/aerial_grass_rock_arm_4k.jpg"))
	mat.set_shader_parameter("rocks_diff", _tex(TEX + "/coast_sand_rocks_02/coast_sand_rocks_02_diff_4k.jpg"))
	mat.set_shader_parameter("rocks_nor", _tex(TEX + "/coast_sand_rocks_02/coast_sand_rocks_02_nor_gl_4k.jpg"))
	mat.set_shader_parameter("rocks_arm", _tex(TEX + "/coast_sand_rocks_02/coast_sand_rocks_02_arm_4k.jpg"))
	mat.set_shader_parameter("aerial_diff", _tex(TEX + "/aerial_beach_01/aerial_beach_01_diff_4k.jpg"))
	terrain.material_override = mat
	add_child(terrain)

func _switch_scenario(k: int) -> void:
	if sim.kind == SimController.Kind.OCEAN or SimController.CFG[k]["n"] != sim.n:
		return # grid size is fixed at startup; ocean runs from island.bat
	sim.load_scenario(k)
	_build_terrain()
	var side := get_node_or_null("SideCam") as Camera3D
	if side != null:
		_place_side_cam(side)

func _build_cameras() -> void:
	var half := sim.domain * 0.5
	var ocean := sim.kind == SimController.Kind.OCEAN
	var drone := Camera3D.new()
	drone.name = "DroneCam"
	drone.position = Vector3(half, 1780.0 if ocean else 26.0, half)
	drone.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	drone.fov = 60.0
	drone.far = 4000.0
	drone.add_to_group("shorewaves_cams")
	add_child(drone)
	drone.current = true

	var side := Camera3D.new()
	side.name = "SideCam"
	side.fov = 55.0
	side.add_to_group("shorewaves_cams")
	add_child(side)
	_place_side_cam(side)

	var free := FreeCam.new()
	free.name = "FreeCam"
	free.fov = 60.0
	free.far = 4000.0
	free.add_to_group("shorewaves_cams")
	add_child(free)
	if ocean:
		free.speed = 80.0
		free.look_at_from_position(Vector3(half, 380.0, sim.domain * 0.86), Vector3(700.0, 0.0, 700.0), Vector3.UP)
	else:
		free.look_at_from_position(Vector3(24.0, 3.5, 6.0), Vector3(16.0, 0.0, 15.0), Vector3.UP)

func _place_side_cam(side: Camera3D) -> void:
	var half := sim.domain * 0.5
	side.far = 4000.0
	if sim.kind == SimController.Kind.OCEAN:
		# coast cam: on the west shore of island A (layout mirrored from pass_genbathy.glsl)
		side.look_at_from_position(Vector3(340.0, 14.0, 700.0), Vector3(540.0, 0.0, 700.0), Vector3.UP)
	elif sim.kind == SimController.Kind.WALL:
		# seaward of the quay wall, looking at the impact face
		side.look_at_from_position(Vector3(13.5, 2.4, half), Vector3(22.3, 0.8, half), Vector3.UP)
	else:
		side.look_at_from_position(Vector3(26.0, 1.6, half), Vector3(10.0, 0.0, half), Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				sim.trigger_solitary()
			KEY_1:
				_switch_scenario(SimController.Kind.BEACH)
			KEY_2:
				_switch_scenario(SimController.Kind.WALL)
			KEY_3:
				_switch_scenario(SimController.Kind.DAM_BREAK)
			KEY_F5:
				(get_node("DroneCam") as Camera3D).current = true
			KEY_F6:
				(get_node("SideCam") as Camera3D).current = true
			KEY_F7:
				(get_node("FreeCam") as Camera3D).current = true
			KEY_F3:
				var ov := get_node_or_null("DebugOverlay/StateView")
				if ov != null:
					ov.visible = not ov.visible

func _build_debug_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DebugOverlay"
	var rect := TextureRect.new()
	rect.name = "StateView"
	rect.texture = sim.tex_state
	rect.custom_minimum_size = Vector2(304, 304)
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.position = Vector2(8, 8)
	rect.size = Vector2(304, 304)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/debug_view.gdshader")
	mat.set_shader_parameter("tx_bottom", sim.tex_bottom)
	rect.material = mat
	var dev_run := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shots="):
			dev_run = true
	rect.visible = dev_run # screenshot runs only; F3 toggles
	layer.add_child(rect)

	_fps_label = Label.new()
	_fps_label.name = "Fps"
	_fps_label.text = "-- FPS"
	_fps_label.add_theme_font_size_override("font_size", 15)
	_fps_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	_fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_fps_label.position = Vector2(-170, 8)
	layer.add_child(_fps_label)

	var help := Label.new()
	help.name = "Help"
	help.text = "1/2 beach|wall   SPACE solitary wave   F5 drone  F6 side  F7 free cam (RMB look, WASD, Q/E, Shift)   F3 sim view"
	help.add_theme_font_size_override("font_size", 14)
	help.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help.position = Vector2(10, -30)
	layer.add_child(help)
	add_child(layer)
