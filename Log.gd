extends Node

enum Category {
	PHYSICS, SHIFT, CHUTE, WHEELS, GENERAL, LATERAL, ENGINE, SETUP,
	TREE, TIMING, RACE, CAMERA, UI, WORLD, TEST,
}

# Turn any category on (true) or off (false) here. Nothing else to touch.
var enabled: Dictionary = {
	Category.PHYSICS: false,
	Category.SHIFT: false,
	Category.CHUTE: false,
	Category.WHEELS: false,
	Category.GENERAL: false,
	Category.LATERAL: false,   # tire sideways-slip spam, every 0.25s
	Category.ENGINE: false,
	Category.SETUP: false,      # startup / config messages
	Category.TREE: true,
	Category.TIMING: true,
	Category.RACE: true,
	Category.CAMERA: false,
	Category.UI: true,
	Category.WORLD: true,      # fish, weeds, water, fps
	Category.TEST: false,
}


func is_on(category: Category) -> bool:
	return enabled.get(category, false)

# Use instead of print(). Takes any number of things, like print().
func d(category: Category, ...args: Array) -> void:
	if is_on(category):
		print("".join(args.map(str)))
