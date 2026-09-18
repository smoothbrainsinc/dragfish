extends Node

# Categories for logging. Add more here as your project grows.
enum Category { PHYSICS, SHIFT, CHUTE, WHEELS, GENERAL }

# Toggle these on/off to control what prints to the console.
# true = prints, false = silent
var enabled: Dictionary = {
	Category.PHYSICS: false,
	Category.SHIFT: false,
	Category.CHUTE: false,
	Category.WHEELS: false,
	Category.GENERAL: true, # Keep general on for now
}

# The main logging function. Call this instead of print().
func d(category: Category, msg: String) -> void:
	if enabled.get(category, false):
		print(msg)
