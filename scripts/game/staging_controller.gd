extends Node
class_name StagingController
## Polls StageBeam zones each frame, drives the pre-stage / stage lights, and
## starts the tree once every active lane has held STAGED. NPC lanes count as
## staged immediately (no NPC driver yet). If the scene has no StageBeam nodes
## this does nothing and the tree still starts from the SPACE debug key.

signal all_staged

## Seconds every lane must hold the stage beam before the tree starts.
@export var stage_hold_time: float = 1.0

var tree: Node
var _beams: Array[StageBeam] = []
var _vehicles: Dictionary = {}    # lane -> VehicleController
var _auto_lanes: Array[int] = []  # lanes held staged without a driver
var _state: Dictionary = {}       # lane -> StageBeam.State
var _hold := 0.0
var _rollout_ref: Dictionary = {}   # lane -> front point when the tree started
var _rollout_dir: Dictionary = {}   # lane -> travel direction when the tree started
var _rolled_out: Array[int] = []

## NHRA rollout: 1 ft of front-tire travel after staging counts as leaving the beam.
const ROLLOUT_DISTANCE := 0.3048
var _fired := false
var _active := false


func setup(start_tree: Node, player: VehicleController, npc: VehicleController) -> void:
	tree = start_tree
	for b in get_tree().get_nodes_in_group("stage_beam"):
		if b is StageBeam:
			_beams.append(b)
	if tree == null or _beams.is_empty():
		push_warning("[Staging] No start tree or StageBeam nodes found - staging disabled")
		return

	for v in [player, npc]:
		if v == null:
			continue
		var lane := int(v.get_meta("spawn_lane", -1))
		_vehicles[lane] = v
		_state[lane] = StageBeam.State.NONE
		_set_lights(lane, StageBeam.State.NONE)
		v.staged = false

	# NPC has no driver yet: hold it staged
	if npc:
		var npc_lane := int(npc.get_meta("spawn_lane", -1))
		_auto_lanes.append(npc_lane)
		_state[npc_lane] = StageBeam.State.STAGED
		_set_lights(npc_lane, StageBeam.State.STAGED)
		npc.staged = true

	_active = true
	print("[Staging] Ready: lanes %s" % [_vehicles.keys()])


func _process(delta: float) -> void:
	if not _active:
		return
	if _fired:
		_check_rollout()
		return

	for lane in _vehicles:
		if lane in _auto_lanes:
			continue
		var vehicle: VehicleController = _vehicles[lane]
		var best := StageBeam.State.NONE
		for beam in _beams:
			best = maxi(best, beam.get_state(vehicle)) as StageBeam.State
		if best != _state[lane]:
			_state[lane] = best
			vehicle.staged = best == StageBeam.State.STAGED
			_set_lights(lane, best)

	if _all_staged():
		_hold += delta
		if _hold >= stage_hold_time:
			_fired = true
			_capture_rollout_reference()
			all_staged.emit()
			print("[Staging] All lanes staged - starting tree")
			tree.start_tree_sequence()
	else:
		_hold = 0.0


func _capture_rollout_reference() -> void:
	for lane in _vehicles:
		if lane in _auto_lanes:
			continue
		var v: VehicleController = _vehicles[lane]
		_rollout_ref[lane] = StageBeam.front_point(v)
		_rollout_dir[lane] = v.global_basis.z.normalized()


## Red light if this happens before green, reaction time after. The timing
## system ignores repeat calls for a lane.
func _check_rollout() -> void:
	var timing := get_tree().get_first_node_in_group("timing_system")
	if timing == null:
		return
	for lane in _rollout_ref:
		if lane in _rolled_out:
			continue
		var v: VehicleController = _vehicles[lane]
		var ref: Vector3 = _rollout_ref[lane]
		var dir: Vector3 = _rollout_dir[lane]
		var moved: float = (StageBeam.front_point(v) - ref).dot(dir)
		if moved >= ROLLOUT_DISTANCE:
			_rolled_out.append(lane)
			timing.on_rollout(v)


func _all_staged() -> bool:
	for lane in _state:
		if _state[lane] != StageBeam.State.STAGED:
			return false
	return not _state.is_empty()


func _set_lights(lane: int, state: StageBeam.State) -> void:
	tree.set_light(lane, "prestage", state >= StageBeam.State.PRESTAGED)
	tree.set_light(lane, "stage", state == StageBeam.State.STAGED)
