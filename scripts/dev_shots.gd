extends Node
## Dev/eval autoload: captures screenshots at requested sim times, then quits.
## Inert in normal play (no user args = does nothing).
## Usage:
##   godot --path . -- shots=2,5,8 out=C:/some/dir prefix=iter1

var _times: Array[float] = []
var _out := ""
var _prefix := "shot"
var _cam := ""
var _t := 0.0
var _idx := 0

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"shots":
				for s in kv[1].split(","):
					_times.append(float(s))
				_times.sort()
			"out":
				_out = kv[1]
			"prefix":
				_prefix = kv[1]
			"cam":
				_cam = kv[1]
	set_process(not _times.is_empty() and _out != "")

func _apply_cam() -> void:
	if _cam == "":
		return
	for c in get_tree().get_nodes_in_group("shorewaves_cams"):
		if c.name.to_lower().begins_with(_cam.to_lower()):
			(c as Camera3D).current = true
			_cam = ""
			return

func _process(delta: float) -> void:
	_apply_cam()
	_t += delta
	if _idx < _times.size() and _t >= _times[_idx]:
		var img := get_viewport().get_texture().get_image()
		var path := "%s/%s_t%04.1f.png" % [_out, _prefix, _times[_idx]]
		var err := img.save_png(path)
		if err != OK:
			push_error("DevShots: failed to save %s (err %d)" % [path, err])
		_idx += 1
		if _idx >= _times.size():
			get_tree().quit()
