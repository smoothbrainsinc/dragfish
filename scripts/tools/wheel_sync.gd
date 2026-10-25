class_name WheelSync
extends RefCounted
## Keeps the three copies of wheel physics values aligned.
##
##   vehicle .tres  = the truth. The game and the pit read it at race time.
##   vehicle .tscn  = wheel nodes you see in the editor. Ignored at race time.
##
## push: .tres -> .tscn   (editor view matches what the game runs)
## pull: .tscn -> .tres   (take what you dialed in on the nodes)
## Run it through tools/sync_wheels.gd (File > Run in the script editor).

const PROPS := {
	"wheel_roll_influence": "roll_influence",
	"wheel_radius": "radius",
	"wheel_rest_length": "rest_length",
	"wheel_friction_slip": "friction_slip",
	"suspension_travel": "suspension_travel",
	"suspension_stiffness": "suspension_stiffness",
	"suspension_max_force": "suspension_max_force",
	"damping_compression": "damping_compression",
	"damping_relaxation": "damping_relaxation",
}


static func scene_file(cfg: VehicleConfig) -> String:
	var p := cfg.scene_path
	if p.begins_with("uid://"):
		var id := ResourceUID.text_to_id(p)
		return ResourceUID.get_id_path(id) if ResourceUID.has_id(id) else ""
	return p


## Writes the config's wheel values into the wheel nodes of the vehicle scene.
## Edits the .tscn text in place so nothing else in the file changes.
static func push(cfg: VehicleConfig, path: String = "") -> bool:
	var scene := path if not path.is_empty() else scene_file(cfg)
	if scene.is_empty() or not FileAccess.file_exists(scene):
		return false
	if cfg.front_wheel_config == null or cfg.rear_wheel_config == null:
		return false

	var original := FileAccess.get_file_as_string(scene)
	var lines := original.split("\n")
	var out := PackedStringArray()
	var i := 0
	while i < lines.size():
		var line := lines[i]
		out.append(line)
		i += 1
		if not (line.begins_with("[node ") and "type=\"VehicleWheel3D\"" in line):
			continue

		var block := PackedStringArray()
		while i < lines.size() and not lines[i].strip_edges().is_empty() and not lines[i].begins_with("["):
			block.append(lines[i])
			i += 1

		var steering := false
		for b in block:
			if b.strip_edges() == "use_as_steering = true":
				steering = true
		var wc: WheelConfig = cfg.front_wheel_config if steering else cfg.rear_wheel_config

		for wheel_prop in PROPS:
			var value = wc.get(PROPS[wheel_prop])
			var new_line := "%s = %s" % [wheel_prop, var_to_str(value)]
			var found := false
			for k in block.size():
				if block[k].begins_with(wheel_prop + " = "):
					block[k] = new_line
					found = true
					break
			if not found:
				block.append(new_line)
		out.append_array(block)

	var result := "\n".join(out)
	if result == original:
		return true
	var f := FileAccess.open(scene, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(result)
	f.close()
	return true


## Reads wheel values off the vehicle scene's wheel nodes into the config and saves it.
static func pull(cfg: VehicleConfig) -> bool:
	var scene := scene_file(cfg)
	if scene.is_empty():
		return false
	var packed := load(scene) as PackedScene
	if packed == null:
		return false
	var root := packed.instantiate()
	cfg.ensure_local_wheel_configs()
	var did_front := false
	var did_rear := false
	for child in root.get_children():
		if not child is VehicleWheel3D:
			continue
		if child.use_as_steering and not did_front:
			cfg.front_wheel_config.read_from_wheel(child)
			did_front = true
		elif not child.use_as_steering and not did_rear:
			cfg.rear_wheel_config.read_from_wheel(child)
			did_rear = true
	root.free()
	cfg.save()
	return did_front and did_rear
