extends Resource
class_name VehicleConfig
## Main vehicle configuration resource
## This is the master config that ties together all vehicle systems

@export_group("Identity")
@export var vehicle_name: String = "Generic Vehicle"
@export var display_name: String = "Street Car"
@export_multiline var description: String = ""

@export_group("Scene Reference")
## Path to the vehicle's .tscn file (contains 3D model + VehicleBody3D)
@export_file("*.tscn") var scene_path: String = ""

@export_group("Physical Properties")
## Mass in kilograms - can override scene value if > 0
@export var mass: float = 0.0
## Center of mass offset (affects weight transfer)
@export var center_of_mass_offset: Vector3 = Vector3(0, -0.2, 0)
## Wheel radius in meters (used if not specified in scene)
@export var default_wheel_radius: float = 0.35

@export_group("Drivetrain")
@export var drive_type: DriveType = DriveType.RWD
@export var engine: EngineConfig
@export var transmission: TransmissionConfig

@export_group("Tires")
@export var front_tires: TireConfig
@export var rear_tires: TireConfig

@export_group("Steering & Brakes")
## Maximum steering angle in radians (~0.35 = 20 degrees)
@export_range(0.05, 1.0) var max_steer_angle: float = 0.35
## Brake force multiplier
@export_range(100.0, 5000.0) var brake_force: float = 1200.0

@export_group("Aerodynamics")
## Drag coefficient (0.25-0.4 for cars, 0.6+ for dragsters)
@export_range(0.0, 2.0) var drag_coefficient: float = 0.35
## Frontal area in square meters
@export_range(1.0, 5.0) var frontal_area: float = 2.2
## Downforce coefficient (negative lift)
@export var downforce_coefficient: float = 0.0
## Rolling resistance
@export_range(0.0, 0.1) var rolling_resistance: float = 0.015

@export_group("Suspension")
## Front suspension stiffness (affects weight transfer)
@export_range(0.0, 100.0) var front_suspension_stiffness: float = 50.0
## Rear suspension stiffness
@export_range(0.0, 100.0) var rear_suspension_stiffness: float = 60.0
## Suspension travel in meters
@export_range(0.05, 0.5) var suspension_travel: float = 0.3
## Damping (how quickly suspension settles)
@export_range(0.0, 10.0) var suspension_damping: float = 5.0

@export_group("AI Behavior")
@export var ai_reaction_time_min: float = 0.10
@export var ai_reaction_time_max: float = 0.25
@export var ai_shift_strategy: ShiftStrategy = ShiftStrategy.OPTIMAL
## Random variation in performance (0.0 = perfect, 1.0 = very inconsistent)
@export_range(0.0, 1.0) var ai_consistency: float = 0.05

@export_group("Tuning")
## Allow this car to be tuned by player
@export var is_tunable: bool = true
## Performance category (for matchmaking/restrictions)
@export var category: Category = Category.STREET
## Performance index (calculated from specs)
@export var performance_index: float = 0.0

enum DriveType {
	RWD,  ## Rear wheel drive (most drag cars)
	FWD,  ## Front wheel drive
	AWD   ## All wheel drive
}

enum ShiftStrategy {
	REDLINE,      ## Shift at redline RPM
	OPTIMAL,      ## Shift at optimal power point
	CONSERVATIVE, ## Shift early to protect engine
	AGGRESSIVE    ## Hold gear longer, risk over-rev
}

enum Category {
	STREET,      ## Street legal
	SPORT,       ## Modified street
	PRO_STREET,  ## Heavy modifications
	PRO_STOCK,   ## Professional stock class
	FUNNY_CAR,   ## Funny car class
	TOP_FUEL     ## Top fuel dragster
}

## Validate the configuration
func is_valid() -> bool:
	var errors = []
	
	if scene_path.is_empty():
		errors.append("No scene_path set")
	
	if not engine:
		errors.append("No engine config")
	
	if not transmission:
		errors.append("No transmission config")
	
	if not front_tires or not rear_tires:
		errors.append("Missing tire configs")
	
	if mass < 0.0:
		errors.append("Invalid mass")
	
	if errors.size() > 0:
		push_error("[VehicleConfig] Validation failed for '%s': %s" % [
			vehicle_name,
			", ".join(errors)
		])
		return false
	
	return true

## Get estimated horsepower from engine config
func get_horsepower() -> int:
	if not engine:
		return 0
	return engine.get_peak_horsepower()

## Get peak torque
func get_peak_torque() -> float:
	if not engine:
		return 0.0
	return engine.get_peak_torque()

## Get estimated weight-to-power ratio (kg/hp - lower is better)
func get_power_to_weight_ratio() -> float:
	if mass <= 0.0 or not engine:
		return 0.0
	var hp = get_horsepower()
	return mass / float(hp) if hp > 0 else 0.0

## Get estimated quarter mile time (very rough)
func estimate_quarter_mile_time() -> float:
	if mass <= 0.0 or not engine:
		return 0.0
	
	var weight_lbs = mass * 2.205
	var hp = get_horsepower()
	
	if hp <= 0:
		return 0.0
	
	return 6.290 * pow(weight_lbs / float(hp), 1.0/3.0)

## Calculate performance index (0-1000+ scale)
func calculate_performance_index() -> float:
	if not engine or mass <= 0.0:
		return 0.0
	
	var hp = get_horsepower()
	var weight_kg = mass
	
	var power_index = (hp / weight_kg) * 100.0
	
	var tire_multiplier = 1.0
	if rear_tires:
		tire_multiplier = rear_tires.get_compound_multiplier()
	
	var gear_bonus = 1.0
	if transmission:
		gear_bonus = 1.0 + (transmission.get_gear_count() - 4) * 0.05
	
	performance_index = power_index * tire_multiplier * gear_bonus
	return performance_index

## Get drive type as string
func get_drive_type_string() -> String:
	match drive_type:
		DriveType.RWD:
			return "RWD"
		DriveType.FWD:
			return "FWD"
		DriveType.AWD:
			return "AWD"
	return "UNKNOWN"

## Get category as string
func get_category_string() -> String:
	match category:
		Category.STREET:
			return "Street"
		Category.SPORT:
			return "Sport"
		Category.PRO_STREET:
			return "Pro Street"
		Category.PRO_STOCK:
			return "Pro Stock"
		Category.FUNNY_CAR:
			return "Funny Car"
		Category.TOP_FUEL:
			return "Top Fuel"
	return "UNKNOWN"

## Get comprehensive debug info
func get_debug_info() -> String:
	return "%s (%s) - %d HP, %.0f kg, %s, %s" % [
		display_name,
		get_category_string(),
		get_horsepower(),
		mass,
		get_drive_type_string(),
		transmission.get_debug_info() if transmission else "No Trans"
	]

## Clone this config (for tuning without modifying original)
func duplicate_config() -> VehicleConfig:
	var new_config = self.duplicate(true)
	if engine:
		new_config.engine = engine.duplicate(true)
	if transmission:
		new_config.transmission = transmission.duplicate(true)
	if front_tires:
		new_config.front_tires = front_tires.duplicate(true)
	if rear_tires:
		new_config.rear_tires = rear_tires.duplicate(true)
	return new_config
