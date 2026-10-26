extends Node

class Cap extends Logger:
	var lines: PackedStringArray = []
	var mtx := Mutex.new()
	func _log_message(message: String, error: bool) -> void:
		mtx.lock()
		lines.append(("[ERR] " if error else "") + message.rstrip("\n"))
		mtx.unlock()

var _cap := Cap.new()
var _start_line := 0
var _dir := ""

func _ready() -> void:
	OS.add_logger(_cap)

func begin_run(v: VehicleController) -> void:
	end_run()
	_dir = "user://runs/%s_%s" % [Time.get_datetime_string_from_system().replace(":", "-"), v.name]
	DirAccess.make_dir_recursive_absolute(_dir)
	_cap.mtx.lock()
	_start_line = _cap.lines.size()
	_cap.mtx.unlock()

	var cfg: VehicleConfig = v.vehicle_config
	_copy_with_deps(cfg.resource_path)
	_copy_with_deps(_resolve(cfg.scene_path))

	var state := {"vehicle": str(v.name), "mass": v.mass, "config": {}, "wheels": {}}
	for p in cfg.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			state.config[p.name] = var_to_str(cfg.get(p.name))
	for w in v.all_wheels:
		state.wheels[str(w.name)] = {
			"radius": w.wheel_radius, "rest_length": w.wheel_rest_length,
			"travel": w.suspension_travel, "stiffness": w.suspension_stiffness,
			"max_force": w.suspension_max_force, "friction_slip": w.wheel_friction_slip,
			"roll_influence": w.wheel_roll_influence, "brake": w.brake,
			"damping_compression": w.damping_compression,
			"damping_relaxation": w.damping_relaxation,
			"traction": w.use_as_traction, "steering": w.use_as_steering,
		}
	var f := FileAccess.open(_dir + "/live_state.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(state, "\t"))

func end_run() -> void:
	if _dir == "":
		return
	_cap.mtx.lock()
	var out := _cap.lines.slice(_start_line)
	_cap.mtx.unlock()
	var f := FileAccess.open(_dir + "/output.log", FileAccess.WRITE)
	f.store_string("\n".join(out))
	_dir = ""

func _resolve(path: String) -> String:
	if path.begins_with("uid://"):
		return ResourceUID.get_id_path(ResourceUID.text_to_id(path))
	return path

func _copy_with_deps(path: String) -> void:
	if path == "" or not FileAccess.file_exists(path):
		return
	_copy(path)
	for d in ResourceLoader.get_dependencies(path):
		var p: String = d.split("::")[-1]
		if p.ends_with(".tres") or p.ends_with(".tscn"):
			_copy(p)

func _copy(path: String) -> void:
	var dst := _dir + "/" + path.get_file()
	if FileAccess.file_exists(dst):
		return
	var f := FileAccess.open(dst, FileAccess.WRITE)
	f.store_string(FileAccess.get_file_as_string(path))
