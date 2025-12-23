## INFO:
## decimeters^3/sec = liters/sec


extends Node


@export var car: Car

## The maximum amount of fuel in [code]liters[/code].
@export var max_fuel := 40.0

## The current amount of fuel in [code]liters[/code].
@export var current_fuel := 40.0

## The idle engine consumption in [code]liters/sec[/code].
@export var idle_consumption := 0.0002

## The load engine consumption coefficient. (arbitrary value to help mimic realistic-ish consumption under load)
@export var load_consumption_coefficient := 0.0001

# deceleration fuel cut-off (DFCO)
## Turn off the fuel injection when decelerating in gear.
@export var deceleration_fuel_cutoff := false


## Returns fuel consumption in [code]liters/sec[/code].
func get_fuel_consumption() -> float:
	var engine_horsepower := Convert.w_to_hp(Convert.nm_rpm_to_w(car.engine_torque, car.rpm))
	var load_consumption := engine_horsepower * load_consumption_coefficient
	var fuel_consumption := idle_consumption + load_consumption
	
	if !car.is_ignition_on:
		fuel_consumption = 0.0
	elif car.is_above_idle_rpm() and is_in_gear() and !is_throttle_open():
		fuel_consumption = 0.0
	
	return max(fuel_consumption, 0.0)


func is_in_gear():
	return car.actualgear != 0


func is_throttle_open():
	return car.throttle != 0.0


func _physics_process(delta: float) -> void:
	var fuel_consumption := get_fuel_consumption()
	current_fuel -= fuel_consumption * delta
	
	if current_fuel <= 0.0:
		car.stop_engine()
