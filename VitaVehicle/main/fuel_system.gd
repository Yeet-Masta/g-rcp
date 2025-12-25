## INFO:
## decimeters^3/sec = liters/sec

class_name Fuel extends Resource



## The maximum amount of fuel in [code]liters[/code].
@export var max_fuel := 40.0

## The idle engine consumption in [code]liters/sec[/code].
@export var idle_consumption := 0.0002

## The load engine consumption coefficient. (arbitrary value to help mimic realistic-ish consumption under load)
@export var load_consumption_coefficient := 0.0001

## Deceleration fuel cut-off (DFCO)
## Turn off the fuel injection when decelerating in gear.[br][br]
## [b]Note:[b] Not implemented.
@export var deceleration_fuel_cutoff := false



## Returns fuel consumption in [code]liters/sec[/code].
func get_consumption(engine_torque, rpm) -> float:
	var engine_horsepower := Convert.w_to_hp(Convert.nm_rpm_to_w(engine_torque, rpm))
	var load_consumption := engine_horsepower * load_consumption_coefficient
	var fuel_consumption := idle_consumption + load_consumption
	
	return max(fuel_consumption, 0.0)
