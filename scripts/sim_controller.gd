extends Node
class_name SimController
## KP07 shallow-water solver driver. All RenderingDevice work happens on the
## render thread; ping-pong is done by cycling RIDs with pre-built uniform sets.
## Texture2DRD RIDs are repointed on the MAIN thread before the sim callable is pushed.
##
## Grid size, cell size, and timestep are per-scenario (beach/wall run the
## original 608 @ 5 cm; ocean runs 2048 @ 1 m over a 2 x 2 km archipelago).
## The grid size is fixed at startup; runtime scenario switching is only
## allowed between kinds that share it.

const G := 9.81
const THETA := 1.3
const MANNING := 0.03
const K_FOAM := 1.5

enum Kind { DAM_BREAK, BEACH, WALL, OCEAN }

const CFG := {
	Kind.DAM_BREAK: {"n": 608, "dx": 0.05, "dt": 0.002, "sub": 12, "depth0": 1.2, "mode": 0.0, "kappa": 0.01, "amp": 0.0, "period": 5.0, "solo_h": 0.36, "solo_x0": 3.0},
	Kind.BEACH: {"n": 608, "dx": 0.05, "dt": 0.002, "sub": 12, "depth0": 1.2, "mode": 1.0, "kappa": 0.01, "amp": 0.18, "period": 5.0, "solo_h": 0.36, "solo_x0": 3.0},
	Kind.WALL: {"n": 608, "dx": 0.05, "dt": 0.002, "sub": 12, "depth0": 1.5, "mode": 1.0, "kappa": 0.01, "amp": 0.18, "period": 5.0, "solo_h": 0.45, "solo_x0": 3.0},
	Kind.OCEAN: {"n": 2048, "dx": 1.0, "dt": 0.008, "sub": 7, "depth0": 25.0, "mode": 2.0, "kappa": 0.02, "amp": 1.2, "period": 10.0, "solo_h": 7.5, "solo_x0": 150.0},
}

## set by main before add_child; _ready builds this scenario
var kind: int = Kind.BEACH

# resolved from CFG at _ready
var n := 608
var dxv := 0.05
var dtv := 0.002
var max_substeps := 12
var groups := 38
var domain := 30.4
var kappa4 := 1e-8

# --- wavemaker parameters (used when wave_mode > 0) ---
var wave_mode := 0.0
var wave_amp := 0.18
var wave_period := 5.0
var wave_depth0 := 1.2
var wave_ramp := 5.0
var solitary_h := 0.36
var solitary_x0 := 3.0

# --- render-thread-owned GPU resources ---
var _rd: RenderingDevice
var _tex_state_rd: Array[RID] = []
var _tex_bottom_rd := RID()
var _tex_r_rd := RID()
var _tex_derived_rd := RID()
var _tex_ground_rd: Array[RID] = []
var _dbg_buf := RID()
var _shaders := {}
var _pipelines := {}
var _sets := {} # pass name -> Array[RID] indexed by parity (see _init_gpu)

# --- main-thread texture resources for materials ---
var tex_state: Texture2DRD
var tex_bottom: Texture2DRD
var tex_derived: Texture2DRD
var tex_ground: Texture2DRD

# --- latest debug readback (main thread reads) ---
var dbg_volume := 0.0
var dbg_max_h := 0.0
var dbg_max_speed := 0.0
var dbg_wet_cells := 0.0
var dbg_nan_cells := 0.0

var _gpu_ready := false
var _bound := false
var _accum := 0.0
var _parity := 0
var _gparity := 0
var _frame := 0
var _solitary_queued := false
var sim_time := 0.0

func trigger_solitary() -> void:
	_solitary_queued = true

func _apply_cfg() -> void:
	var c: Dictionary = CFG[kind]
	n = c["n"]
	dxv = c["dx"]
	dtv = c["dt"]
	max_substeps = c["sub"]
	groups = (n + 15) / 16
	domain = float(n) * dxv
	kappa4 = pow(c["kappa"], 4.0)
	wave_depth0 = c["depth0"]
	wave_mode = c["mode"]
	if wave_amp <= 0.0:
		wave_amp = c["amp"]
	if wave_period <= 0.0:
		wave_period = c["period"]
	wave_ramp = wave_period
	solitary_h = c["solo_h"]
	solitary_x0 = c["solo_x0"]

func _ready() -> void:
	tex_state = Texture2DRD.new()
	tex_bottom = Texture2DRD.new()
	tex_derived = Texture2DRD.new()
	tex_ground = Texture2DRD.new()
	_apply_cfg()
	var init := _build_initial(kind)
	RenderingServer.call_on_render_thread(_init_gpu.bind(init.get("bottom", PackedByteArray()), init.get("state", PackedByteArray())))

func load_scenario(new_kind: int) -> void:
	if CFG[new_kind]["n"] != n:
		push_warning("SimController: cannot switch to a scenario with a different grid size at runtime")
		return
	kind = new_kind
	wave_amp = 0.0
	wave_period = 0.0
	_apply_cfg()
	sim_time = 0.0
	_accum = 0.0
	var init := _build_initial(kind)
	RenderingServer.call_on_render_thread(_reset_gpu.bind(init.get("bottom", PackedByteArray()), init.get("state", PackedByteArray())))

func _process(delta: float) -> void:
	if not _gpu_ready:
		return
	if not _bound:
		tex_state.texture_rd_rid = _tex_state_rd[_parity]
		tex_bottom.texture_rd_rid = _tex_bottom_rd
		tex_derived.texture_rd_rid = _tex_derived_rd
		tex_ground.texture_rd_rid = _tex_ground_rd[_gparity]
		_bound = true
	_accum += minf(delta, 0.1)
	var steps := clampi(int(_accum / dtv), 0, max_substeps)
	_accum -= float(steps) * dtv
	if steps == 0:
		return
	var final_parity := (_parity + steps) % 2
	var final_gparity := _gparity ^ 1
	tex_state.texture_rd_rid = _tex_state_rd[final_parity]
	tex_ground.texture_rd_rid = _tex_ground_rd[final_gparity]
	var solitary := _solitary_queued
	_solitary_queued = false
	RenderingServer.call_on_render_thread(_run_sim.bind(steps, sim_time, _parity, solitary, _gparity))
	_parity = final_parity
	_gparity = final_gparity
	sim_time += float(steps) * dtv

# ---------------- initial conditions (main thread, CPU) ----------------

func _build_initial(k: int) -> Dictionary:
	if k == Kind.OCEAN:
		return {} # bathymetry and state are generated on the GPU (pass_genbathy/pass_init)
	if k == Kind.DAM_BREAK:
		return _build_dambreak()
	var built := Scenario.build(0 if k == Kind.BEACH else 1)
	var bottom_img: Image = built["bottom_image"]
	var bdata := bottom_img.get_data()
	var bf := bdata.to_float32_array()
	var st := PackedFloat32Array()
	st.resize(n * n * 4)
	for c in n * n:
		var o := c * 4
		st[o] = maxf(bf[o], 0.0) # w = max(B, 0): lake at rest at SWL
		st[o + 1] = 0.0
		st[o + 2] = 0.0
		st[o + 3] = 0.0
	return {"bottom": bdata, "state": st.to_byte_array()}

func _build_dambreak() -> Dictionary:
	# flat bed 1 m below SWL; background h = 0.5 m; 3 m-radius column h = 1.1 m
	var bot := PackedFloat32Array()
	bot.resize(n * n * 4)
	var st := PackedFloat32Array()
	st.resize(n * n * 4)
	var half := domain * 0.5
	for j in n:
		for i in n:
			var o := (j * n + i) * 4
			bot[o + 0] = -1.0
			bot[o + 1] = -1.0
			bot[o + 2] = -1.0
			bot[o + 3] = -1.0
			var x := (float(i) + 0.5) * dxv
			var z := (float(j) + 0.5) * dxv
			var w := -0.5
			if Vector2(x - half, z - half).length() < 3.0:
				w = 0.1
			st[o + 0] = w
			st[o + 1] = 0.0
			st[o + 2] = 0.0
			st[o + 3] = 0.0
	return {"bottom": bot.to_byte_array(), "state": st.to_byte_array()}

# ---------------- render thread ----------------

func _generate_ocean_gpu(cl_owner: bool) -> void:
	# one-shot bathymetry + lake-at-rest init, entirely on the GPU
	var pcb := PackedFloat32Array([dxv, 0.0, 0.0, 0.0]).to_byte_array()
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _pipelines["genbathy"])
	_rd.compute_list_bind_uniform_set(cl, _sets["genbathy"][0], 0)
	_rd.compute_list_set_push_constant(cl, pcb, pcb.size())
	_rd.compute_list_dispatch(cl, groups, groups, 1)
	_rd.compute_list_add_barrier(cl)
	_rd.compute_list_bind_compute_pipeline(cl, _pipelines["init"])
	_rd.compute_list_bind_uniform_set(cl, _sets["init"][0], 0)
	_rd.compute_list_set_push_constant(cl, pcb, pcb.size())
	_rd.compute_list_dispatch(cl, groups, groups, 1)
	_rd.compute_list_add_barrier(cl)
	_rd.compute_list_end()

func _reset_gpu(bottom_data: PackedByteArray, state_data: PackedByteArray) -> void:
	if bottom_data.is_empty():
		_generate_ocean_gpu(true)
	else:
		_rd.texture_update(_tex_bottom_rd, 0, bottom_data)
		_rd.texture_update(_tex_state_rd[0], 0, state_data)
		_rd.texture_update(_tex_state_rd[1], 0, state_data)
	for t in _tex_ground_rd:
		_rd.texture_clear(t, Color(0, 0, 0, 0), 0, 1, 0, 1)
	_rd.texture_clear(_tex_r_rd, Color(0, 0, 0, 0), 0, 1, 0, 1)

func _init_gpu(bottom_data: PackedByteArray, state_data: PackedByteArray) -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		push_error("SimController: no RenderingDevice (headless?)")
		return

	var fmt := RDTextureFormat.new()
	fmt.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	fmt.width = n
	fmt.height = n
	fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		| RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	)
	for i in 2:
		_tex_state_rd.append(_rd.texture_create(fmt, RDTextureView.new(), []))
	_tex_bottom_rd = _rd.texture_create(fmt, RDTextureView.new(), [])
	_tex_r_rd = _rd.texture_create(fmt, RDTextureView.new(), [])
	_rd.texture_clear(_tex_r_rd, Color(0, 0, 0, 0), 0, 1, 0, 1)

	var fmt16 := RDTextureFormat.new()
	fmt16.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	fmt16.width = n
	fmt16.height = n
	fmt16.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	fmt16.usage_bits = fmt.usage_bits
	_tex_derived_rd = _rd.texture_create(fmt16, RDTextureView.new(), [])
	_rd.texture_clear(_tex_derived_rd, Color(0, 0, 0, 0), 0, 1, 0, 1)
	for i in 2:
		var t := _rd.texture_create(fmt16, RDTextureView.new(), [])
		_rd.texture_clear(t, Color(0, 0, 0, 0), 0, 1, 0, 1)
		_tex_ground_rd.append(t)

	var zeros := PackedByteArray()
	zeros.resize(64)
	_dbg_buf = _rd.storage_buffer_create(64, zeros)

	for pass_name in ["step", "boundary", "debug", "solitary", "derived", "ground", "genbathy", "init"]:
		if not _build_pass(pass_name, "res://sim/pass_%s.glsl" % pass_name):
			return

	var step_sets: Array[RID] = []
	var bound_sets: Array[RID] = []
	var debug_sets: Array[RID] = []
	var soli_sets: Array[RID] = []
	for p in 2:
		step_sets.append(_rd.uniform_set_create([
			_img_uniform(0, _tex_state_rd[p]),
			_img_uniform(1, _tex_bottom_rd),
			_img_uniform(2, _tex_r_rd),
			_img_uniform(3, _tex_state_rd[p ^ 1]),
		], _shaders["step"], 0))
		bound_sets.append(_rd.uniform_set_create([
			_img_uniform(0, _tex_state_rd[p]),
			_img_uniform(1, _tex_bottom_rd),
		], _shaders["boundary"], 0))
		var bu := RDUniform.new()
		bu.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		bu.binding = 2
		bu.add_id(_dbg_buf)
		debug_sets.append(_rd.uniform_set_create([
			_img_uniform(0, _tex_state_rd[p]),
			_img_uniform(1, _tex_bottom_rd),
			bu,
		], _shaders["debug"], 0))
		soli_sets.append(_rd.uniform_set_create([
			_img_uniform(0, _tex_state_rd[p]),
			_img_uniform(1, _tex_bottom_rd),
		], _shaders["solitary"], 0))
	_sets["step"] = step_sets
	_sets["boundary"] = bound_sets
	_sets["debug"] = debug_sets
	_sets["solitary"] = soli_sets

	var derived_sets: Array[RID] = []
	for p in 2:
		derived_sets.append(_rd.uniform_set_create([
			_img_uniform(0, _tex_state_rd[p]),
			_img_uniform(1, _tex_bottom_rd),
			_img_uniform(2, _tex_derived_rd),
		], _shaders["derived"], 0))
	_sets["derived"] = derived_sets
	var ground_sets: Array[RID] = []
	for p in 2:
		for gp in 2:
			ground_sets.append(_rd.uniform_set_create([
				_img_uniform(0, _tex_state_rd[p]),
				_img_uniform(1, _tex_bottom_rd),
				_img_uniform(2, _tex_ground_rd[gp]),
				_img_uniform(3, _tex_ground_rd[gp ^ 1]),
				_img_uniform(4, _tex_r_rd),
			], _shaders["ground"], 0))
	_sets["ground"] = ground_sets # index = p * 2 + gp

	_sets["genbathy"] = [_rd.uniform_set_create([
		_img_uniform(0, _tex_bottom_rd),
	], _shaders["genbathy"], 0)] as Array[RID]
	_sets["init"] = [_rd.uniform_set_create([
		_img_uniform(0, _tex_bottom_rd),
		_img_uniform(1, _tex_state_rd[0]),
		_img_uniform(2, _tex_state_rd[1]),
	], _shaders["init"], 0)] as Array[RID]

	if bottom_data.is_empty():
		_generate_ocean_gpu(false)
	else:
		_rd.texture_update(_tex_bottom_rd, 0, bottom_data)
		_rd.texture_update(_tex_state_rd[0], 0, state_data)
		_rd.texture_update(_tex_state_rd[1], 0, state_data)

	_gpu_ready = true
	print("SimController: GPU init ok (%dx%d, dx=%s, DT=%s, kind=%d)" % [n, n, dxv, dtv, kind])

func _img_uniform(binding: int, rid: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = binding
	u.add_id(rid)
	return u

func _build_pass(pass_name: String, path: String) -> bool:
	var sf: RDShaderFile = load(path)
	if sf == null:
		push_error("SimController: missing shader file " + path)
		return false
	var spirv := sf.get_spirv()
	if spirv.compile_error_compute != "":
		push_error("SimController: %s compile error:\n%s" % [path, spirv.compile_error_compute])
		return false
	_shaders[pass_name] = _rd.shader_create_from_spirv(spirv)
	_pipelines[pass_name] = _rd.compute_pipeline_create(_shaders[pass_name])
	return true

func _sim_pc(t: float) -> PackedByteArray:
	return PackedFloat32Array([dtv, dxv, G, THETA, kappa4, MANNING, t, K_FOAM]).to_byte_array()

func _bound_pc(t: float) -> PackedByteArray:
	return PackedFloat32Array([
		t, wave_mode, wave_amp, wave_period, wave_depth0, wave_ramp, dxv, G,
	]).to_byte_array()

func _run_sim(substeps: int, t0: float, parity: int, solitary: bool, gparity: int) -> void:
	var p := parity
	var cl := _rd.compute_list_begin()
	if solitary:
		var d0 := wave_depth0
		var ks := sqrt(3.0 * solitary_h / (4.0 * d0 * d0 * d0))
		var cs := sqrt(G * (solitary_h + d0))
		var scb := PackedFloat32Array([solitary_h, solitary_x0, ks, cs, dxv, 0.0, 0.0, 0.0]).to_byte_array()
		_rd.compute_list_bind_compute_pipeline(cl, _pipelines["solitary"])
		_rd.compute_list_bind_uniform_set(cl, _sets["solitary"][p], 0)
		_rd.compute_list_set_push_constant(cl, scb, scb.size())
		_rd.compute_list_dispatch(cl, groups, groups, 1)
		_rd.compute_list_add_barrier(cl)
	for k in substeps:
		var t := t0 + float(k) * dtv
		var pcb := _sim_pc(t)
		# fused flux+integrate: one dispatch, one barrier per substep
		_rd.compute_list_bind_compute_pipeline(cl, _pipelines["step"])
		_rd.compute_list_bind_uniform_set(cl, _sets["step"][p], 0)
		_rd.compute_list_set_push_constant(cl, pcb, pcb.size())
		_rd.compute_list_dispatch(cl, groups, groups, 1)
		_rd.compute_list_add_barrier(cl)

		var bcb := _bound_pc(t + dtv)
		_rd.compute_list_bind_compute_pipeline(cl, _pipelines["boundary"])
		_rd.compute_list_bind_uniform_set(cl, _sets["boundary"][p ^ 1], 0)
		_rd.compute_list_set_push_constant(cl, bcb, bcb.size())
		_rd.compute_list_dispatch(cl, groups, groups, 1)
		_rd.compute_list_add_barrier(cl)
		p ^= 1

	var t_end := t0 + float(substeps) * dtv
	var dcb := _sim_pc(t_end)
	_rd.compute_list_bind_compute_pipeline(cl, _pipelines["derived"])
	_rd.compute_list_bind_uniform_set(cl, _sets["derived"][p], 0)
	_rd.compute_list_set_push_constant(cl, dcb, dcb.size())
	_rd.compute_list_dispatch(cl, groups, groups, 1)
	_rd.compute_list_add_barrier(cl)

	# ground pass: dt slot carries the frame delta, not the substep DT
	var gcb := PackedFloat32Array([
		float(substeps) * dtv, dxv, G, THETA, kappa4, MANNING, t_end, K_FOAM,
	]).to_byte_array()
	_rd.compute_list_bind_compute_pipeline(cl, _pipelines["ground"])
	_rd.compute_list_bind_uniform_set(cl, _sets["ground"][p * 2 + gparity], 0)
	_rd.compute_list_set_push_constant(cl, gcb, gcb.size())
	_rd.compute_list_dispatch(cl, groups, groups, 1)
	_rd.compute_list_add_barrier(cl)

	_frame += 1
	# the reduction walks every cell in one workgroup: cheap at 608, a few ms
	# at 2048, so it only runs at the print cadence
	if _frame % 30 == 0:
		_rd.compute_list_bind_compute_pipeline(cl, _pipelines["debug"])
		_rd.compute_list_bind_uniform_set(cl, _sets["debug"][p], 0)
		_rd.compute_list_set_push_constant(cl, dcb, dcb.size())
		_rd.compute_list_dispatch(cl, 1, 1, 1)
	_rd.compute_list_end()

	if _frame % 30 == 0:
		_rd.buffer_get_data_async(_dbg_buf, _on_debug_data)

func _on_debug_data(data: PackedByteArray) -> void:
	var f := data.to_float32_array()
	dbg_volume = f[0]
	dbg_max_h = f[1]
	dbg_max_speed = f[2]
	dbg_wet_cells = f[3]
	dbg_nan_cells = f[4]
	print("[sim] t=%.2f vol=%.3f m3 max_h=%.3f max_u=%.2f wet=%d nan=%d" % [
		f[5], f[0], f[1], f[2], int(f[3]), int(f[4]),
	])
