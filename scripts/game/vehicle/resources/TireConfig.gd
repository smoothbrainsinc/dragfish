extends Resource
class_name TireConfig
## Tire configuration - grip, slip, compound characteristics

@export_group("Compound")
@export var compound_name: String = "Street Radial"
@export var compound_type: CompoundType = CompoundType.STREET

@export_group("Grip Properties")
## Base friction coefficient (higher = more grip)
@export_range(0.5, 2.0) var friction_coefficient: float = 1.0
## Lateral grip (cornering) - not used much in drag racing
@export_range(0.5, 2.0) var lateral_friction: float = 0.9

@export_group("Slip Characteristics")
## Optimal slip ratio for maximum grip (typically 10-20%)
@export_range(0.0, 0.5) var optimal_slip_ratio: float = 0.15
## Slip threshold where tire breaks loose
@export_range(0.0, 1.0) var slip_threshold: float = 0.25
## How quickly friction drops after optimal slip (0.0-1.0)
@export_range(0.0, 1.0) var friction_falloff: float = 0.3

@export_group("Temperature (Future)")
## Operating temperature range (not fully implemented yet)
@export var optimal_temp_min: float = 80.0  # Celsius
@export var optimal_temp_max: float = 100.0
@export var heat_rate: float = 0.5  ## How quickly tire heats up

@export_group("Wear (Future)")
@export var wear_rate: float = 0.1  ## How quickly tire wears

enum CompoundType {
	STREET,        ## Street tire - good all-around
	SPORT,         ## Sport tire - better grip, less durable
	DRAG_RADIAL,   ## Drag radial - designed for straight line
	DRAG_SLICK,    ## Slick - maximum grip, no tread
	BIAS_PLY       ## Bias ply - old school drag tire
}

## Get effective friction based on slip ratio
## Uses a simplified Pacejka-style curve (peak then falloff)
func get_friction_at_slip(slip_ratio: float) -> float:
	# Slip ratio = (wheel_speed - ground_speed) / ground_speed
	# At optimal slip, we get maximum friction
	# Beyond that, friction drops (tire spinning)
	
	var abs_slip = abs(slip_ratio)
	var base_friction = get_effective_friction()
	
	if abs_slip <= optimal_slip_ratio:
		# Before optimal slip - smooth curve to peak
		# Use sine curve for more realistic ramp-up
		var t = abs_slip / optimal_slip_ratio
		var ramp = sin(t * PI * 0.5)  # Smooth 0 to 1 curve
		return base_friction * ramp
	else:
		# Past optimal slip - friction drops off
		var excess = abs_slip - optimal_slip_ratio
		
		# Exponential decay feels more realistic than linear
		var decay = exp(-friction_falloff * excess * 5.0)
		
		# Clamp to minimum 20% friction (never goes to zero or negative)
		var min_friction = base_friction * 0.2
		return max(base_friction * decay, min_friction)

## Check if tire is slipping (losing traction)
func is_slipping(slip_ratio: float) -> bool:
	return abs(slip_ratio) > slip_threshold

## Check if tire is at optimal slip (maximum grip)
func is_optimal_slip(slip_ratio: float) -> bool:
	var abs_slip = abs(slip_ratio)
	var tolerance = optimal_slip_ratio * 0.2  # Within 20% of optimal
	return abs(abs_slip - optimal_slip_ratio) < tolerance

## Get grip multiplier based on compound type
func get_compound_multiplier() -> float:
	match compound_type:
		CompoundType.STREET:
			return 1.0
		CompoundType.SPORT:
			return 1.2
		CompoundType.DRAG_RADIAL:
			return 1.5
		CompoundType.DRAG_SLICK:
			return 2.0
		CompoundType.BIAS_PLY:
			return 1.8
	return 1.0

## Get effective friction coefficient (with compound multiplier)
func get_effective_friction() -> float:
	return friction_coefficient * get_compound_multiplier()

## Get maximum possible grip force for this tire
func get_max_grip_force(normal_force: float) -> float:
	return get_effective_friction() * normal_force

## Debug info for tire state
func get_debug_info() -> String:
	return "%s (μ=%.2f, slip=%.0f%%)" % [
		compound_name,
		get_effective_friction(),
		optimal_slip_ratio * 100.0
	]
