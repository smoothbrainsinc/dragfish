extends MeshInstance3D

const WATER_Y     : float   = -5.0
const MAX_DEPTH   : float   = 150.0
const LAKE_ORIGIN : Vector2 = Vector2(-750.0, -750.0)
const LAKE_SIZE   : Vector2 = Vector2(1500.0, 1500.0)
const MAP_RES     : int     = 256

@onready var _mat : ShaderMaterial = get_surface_override_material(0)

func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	_bake_depth_map()

func _bake_depth_map() -> void:
	var space := get_world_3d().direct_space_state
	var img   := Image.create(MAP_RES, MAP_RES, false, Image.FORMAT_RF)
	var ray_length := MAX_DEPTH + abs(WATER_Y) + 10.0

	for y in MAP_RES:
		for x in MAP_RES:
			var world_x := LAKE_ORIGIN.x + (float(x) / MAP_RES) * LAKE_SIZE.x
			var world_z := LAKE_ORIGIN.y + (float(y) / MAP_RES) * LAKE_SIZE.y
			var from    := Vector3(world_x, WATER_Y + 5.0, world_z)
			var to      := Vector3(world_x, WATER_Y - ray_length, world_z)

			var query := PhysicsRayQueryParameters3D.create(from, to)
			query.collide_with_areas = false
			var result := space.intersect_ray(query)

			var depth_value := 0.0
			if result:
				var hit_y      : float = result.position.y
				var water_depth : float = WATER_Y - hit_y
				depth_value = clamp(water_depth / MAX_DEPTH, 0.0, 1.0)

			img.set_pixel(x, y, Color(depth_value, 0.0, 0.0, 1.0))

	var tex := ImageTexture.create_from_image(img)
	_mat.set_shader_parameter("lake_depth_map",  tex)
	_mat.set_shader_parameter("water_surface_y", WATER_Y)
	_mat.set_shader_parameter("max_depth",       MAX_DEPTH)
	_mat.set_shader_parameter("lake_origin",     LAKE_ORIGIN)
	_mat.set_shader_parameter("lake_size",       LAKE_SIZE)
	print("[WaterDepth] Raycast depth map baked: ", MAP_RES, "x", MAP_RES)
