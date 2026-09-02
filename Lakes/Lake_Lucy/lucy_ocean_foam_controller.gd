@tool
extends Node

# Attach to the root of your ocean scene. Expects this node structure
# as children (adjust the NodePaths below to match yours):
#   ocean_mesh          : MeshInstance3D  (your water plane/lake)
#   FoamSubViewport      : SubViewport (foam_calc.gdshader ColorRect inside)
#   HistoryA              : SubViewport (foam_history.gdshader ColorRect inside)
#   HistoryB              : SubViewport (foam_history.gdshader ColorRect inside)
#
# HistoryA and HistoryB's ColorRect materials should have Update Mode set
# to DISABLED — this script drives them manually with UPDATE_ONCE so only
# one buffer renders per frame.

@export var ocean_mesh_path: NodePath
@export var foam_sub_viewport_path: NodePath
@export var history_a_path: NodePath
@export var history_b_path: NodePath

var ocean_mesh: MeshInstance3D
var foam_sub_viewport: SubViewport
var history_a: SubViewport
var history_b: SubViewport

var material_a: ShaderMaterial
var material_b: ShaderMaterial
var ocean_material: ShaderMaterial

var write_a := true

func _ready() -> void:
	ocean_mesh = get_node(ocean_mesh_path)
	foam_sub_viewport = get_node(foam_sub_viewport_path)
	history_a = get_node(history_a_path)
	history_b = get_node(history_b_path)

	material_a = history_a.get_node("ColorRect").material
	material_b = history_b.get_node("ColorRect").material

func _process(delta: float) -> void:
	if not ocean_mesh:
		return

	ocean_material = ocean_mesh.get_surface_override_material(0)
	if not ocean_material:
		return

	material_a.set_shader_parameter("delta", delta)
	material_b.set_shader_parameter("delta", delta)
	material_a.set_shader_parameter("current_foam", foam_sub_viewport.get_texture())
	material_b.set_shader_parameter("current_foam", foam_sub_viewport.get_texture())
	material_a.set_shader_parameter("history_foam", history_b.get_texture())
	material_b.set_shader_parameter("history_foam", history_a.get_texture())

	if write_a:
		history_a.render_target_update_mode = SubViewport.UPDATE_ONCE
		history_b.render_target_update_mode = SubViewport.UPDATE_DISABLED
		ocean_material.set_shader_parameter("foam_map", history_a.get_texture())
	else:
		history_b.render_target_update_mode = SubViewport.UPDATE_ONCE
		history_a.render_target_update_mode = SubViewport.UPDATE_DISABLED
		ocean_material.set_shader_parameter("foam_map", history_b.get_texture())

	write_a = not write_a
