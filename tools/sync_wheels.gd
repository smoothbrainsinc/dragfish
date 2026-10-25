@tool
extends EditorScript
## Open this file in the script editor and use File > Run (Ctrl+Shift+X).
## "push": vehicle .tres -> wheel nodes in the vehicle .tscn  (default)
## "pull": wheel nodes in the vehicle .tscn -> vehicle .tres
## Close the vehicle scene tab first, or accept the "reload from disk" prompt.

const MODE := "push"


func _run() -> void:
	for f in DirAccess.get_files_at("res://vehicles/configs"):
		if not f.ends_with(".tres"):
			continue
		var cfg := load("res://vehicles/configs/" + f) as VehicleConfig
		if cfg == null:
			continue
		var ok := WheelSync.push(cfg) if MODE == "push" else WheelSync.pull(cfg)
		print("[WheelSync] %s %s: %s" % [MODE, f, "ok" if ok else "skipped"])
