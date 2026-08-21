extends Resource
class_name SpawnEntry

## Model to instance (glb/gltf/tres/res)
@export_file("*.glb", "*.gltf", "*.tres", "*.res") var model_path: String

## How many to place
@export var count: int = 100

## Random scale range applied per-instance
@export var min_scale: float = 1.0
@export var max_scale: float = 1.0

## Vertical offset from the sampled surface point
@export var y_offset: float = 0.0

## Optional patch restriction (ignored if patch_radius <= 0)
@export var patch_center: Vector3 = Vector3.ZERO
@export var patch_radius: float = 0.0

## If true, hands the resulting MultiMesh to FishFlock.gd for per-frame movement.
## If false, it's placed once and left static (weeds, rocks, debris, etc).
@export var moves: bool = false

## Only used when moves = true — passed straight to FishFlock.
@export var swim_speed: float = 1.0
@export var separation_weight: float = 1.0
@export var alignment_weight: float = 5.0
@export var cohesion_weight: float = 3.0
@export var perception_radius: float = 15.0
@export var grid_cell_size: float = 8.0
@export var surface_offset: float = 0.0
@export var max_depth_offset: float = -10.0
@export var animation_speed: float = 2.0
@export var tail_wave_amplitude: float = 0.2
