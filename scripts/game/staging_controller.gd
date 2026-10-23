extends Node
class_name StagingController
## Drives pre-stage / stage lights from StageBeam areas and starts the tree
## once every active lane is staged. NPC lanes count as staged immediately
## (no NPC driver yet). If the scene has no StageBeam nodes this does nothing
## and the tree still starts from the SPACE debug key.

signal all_staged

## Seconds every lane must hold the stage beam before the tree starts.
@export var stage_hold_time: float = 1.0

var tree: Node
var _vehicles: Dictionary = {}   # lane -> VehicleController
var _prestaged: Dictionary = {}  # lane -> bool
var _staged: Dictionary = {}     # lane -> bool
var _hold := 0.0
var _fired := false
var _active := false


func setup(start_tree: Node, player: VehicleController, npc: VehicleController) -> void:
	tree = start_tree
	var beams := get_tree().get_nodes_in_group("stage_beam")
	if tree == null or beams.is_empty():
		push_warning("[Staging] No start tree or StageBeam nodes found - staging disabled")
		return

	for v in [player, npc]:
		if v == null:
			continue
		var lane := int(v.get_meta("spawn_lane", -1))
		_vehicles[lane] = v
		_prestaged[lane] = false
		_staged[lane] = false
		_set_lights(lane, false, false)
		v.staged = false

	for b in beams:
		var beam := b as StageBeam
		if beam == null or not _vehicles.has(beam.lane):
			continue
		beam.vehicle_entered.connect(_on_beam_entered)
		beam.vehicle_exited.connect(_on_beam_exited)

	# NPC has no driver yet: hold it staged
	if npc:
		var npc_lane := int(npc.get_meta("spawn_lane", -1))
		_prestaged[npc_lane] = true
		_staged[npc_lane] = true
		_set_lights(npc_lane, true, true)
		npc.staged = true

	_active = true
	print("[Staging] Ready: lanes %s" % [_vehicles.keys()])


func _process(delta: float) -> void:
	if not _active or _fired:
		return
	if _all_staged():
		_hold += delta
		if _hold >= stage_hold_time:
			_fired = true
			all_staged.emit()
			print("[Staging] All lanes staged - starting tree")
			tree.start_tree_sequence()
	else:
		_hold = 0.0


func _all_staged() -> bool:
	for lane in _staged:
		if not _staged[lane]:
			return false
	return not _staged.is_empty()


func _on_beam_entered(beam: StageBeam, vehicle: VehicleController) -> void:
	if _fired:
		return
	match beam.kind:
		StageBeam.Kind.PRESTAGE:
			_prestaged[beam.lane] = true
		StageBeam.Kind.STAGE:
			_prestaged[beam.lane] = true
			_staged[beam.lane] = true
			vehicle.staged = true
	_set_lights(beam.lane, _prestaged[beam.lane], _staged[beam.lane])


func _on_beam_exited(beam: StageBeam, vehicle: VehicleController) -> void:
	if _fired:
		return
	match beam.kind:
		StageBeam.Kind.PRESTAGE:
			_prestaged[beam.lane] = false
		StageBeam.Kind.STAGE:
			_staged[beam.lane] = false
			vehicle.staged = false
	_set_lights(beam.lane, _prestaged[beam.lane], _staged[beam.lane])


func _set_lights(lane: int, prestage: bool, stage: bool) -> void:
	tree.set_light(lane, "prestage", prestage)
	tree.set_light(lane, "stage", stage)
