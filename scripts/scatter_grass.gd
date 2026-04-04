@tool
extends EditorScript

const GRASS_SCENE = preload("res://assets/models/fishes/grass.glb")
const GRASS_COUNT = 300
const SPREAD_X = 40.0  # adjust to match your sandy area size
const SPREAD_Z = 40.0

func _run():
	var root = get_scene()
	
	# Find the sandy mesh to get its Y position
	var sandy = _find_node(root, "L2-sandy")
	var base_y = 0.0
	if sandy:
		base_y = sandy.global_position.y
	
	var parent = Node3D.new()
	parent.name = "GrassScatter"
	root.add_child(parent)
	parent.owner = root
	
	for i in range(GRASS_COUNT):
		var instance = GRASS_SCENE.instantiate()
		instance.name = "Grass_%d" % i
		
		# Random position across sandy area
		var rx = randf_range(-SPREAD_X, SPREAD_X)
		var rz = randf_range(-SPREAD_Z, SPREAD_Z)
		
		# Random rotation and slight scale variation
		var ry = randf_range(0, TAU)
		var scale = randf_range(0.8, 1.4)
		
		instance.position = Vector3(rx, base_y, rz)
		instance.rotation.y = ry
		instance.scale = Vector3(scale, scale, scale)
		
		parent.add_child(instance)
		instance.owner = root
	
	print("Done! Placed %d grass instances." % GRASS_COUNT)

func _find_node(node: Node, name: String) -> Node:
	if node.name == name:
		return node
	for child in node.get_children():
		var found = _find_node(child, name)
		if found:
			return found
	return null
