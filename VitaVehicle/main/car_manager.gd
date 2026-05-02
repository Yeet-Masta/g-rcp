## Tracks all spawned cars and which one is currently driver-controlled.
##
## Add this as an autoload named [code]CarManager[/code] (Project Settings →
## Autoload, point at [code]res://path/to/car_manager.gd[/code]).
##
## Existing scripts that call [code]get_tree().get_first_node_in_group("car")[/code]
## still work — they'll just get whichever car is first. UI scripts that should
## follow the active car (debug overlay, camera, swappers) can call
## [method get_active] instead.

extends Node



signal active_car_changed(new_car)
signal car_registered(car)
signal car_unregistered(car)



var _active_car: Node = null
var _cars: Array = []  # Untyped because Car class_name lives in car.gd; this autoload must not depend on it.



# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

## Register a car with the manager. Called automatically in Car._ready when
## the helper is wired up. Safe to call multiple times.
func register(car: Node) -> void:
	if car == null or _cars.has(car):
		return
	_cars.append(car)
	car.tree_exiting.connect(_on_car_exiting.bind(car))
	car_registered.emit(car)
	
	# First car spawned becomes active by default.
	if _active_car == null:
		set_active(car)
	else:
		# If there is already an active car, make sure the new car is NOT controlled
		if "Controlled" in car:
			car.Controlled = false


## Unregister and (optionally) free a car.
func unregister(car: Node) -> void:
	if car == null:
		return
	_cars.erase(car)
	car_unregistered.emit(car)
	if _active_car == car:
		_active_car = null
		# Fall back to any remaining car.
		if not _cars.is_empty():
			set_active(_cars[0])
		else:
			active_car_changed.emit(null)


# ---------------------------------------------------------------------------
# Active car
# ---------------------------------------------------------------------------

func get_active() -> Node:
	# Self-heal if the active car was freed externally.
	if _active_car != null and not is_instance_valid(_active_car):
		_active_car = null
	return _active_car


func set_active(car: Node) -> void:
	if car == _active_car:
		return
	if not _cars.has(car):
		register(car)
		return
	
	# Park the previously-active car: zero out driver inputs and apply a
	# light brake so it coasts to a stop instead of running off on its own.
	if _active_car != null and is_instance_valid(_active_car):
		_park_car(_active_car)
	
	_active_car = car
	# Push Controlled flags so only the active car reads input.
	for c in _cars:
		if not is_instance_valid(c):
			continue
		if "Controlled" in c:
			c.Controlled = (c == car)
	active_car_changed.emit(car)

## Releases driver inputs on a car and applies a gentle braking pressure so
## it comes to a smooth stop after the player swaps away from it.
func _park_car(car: Node) -> void:
	# Stop reading input first — Car.controls() overwrites pedals every
	# physics tick when Controlled is true, so we'd be fighting it otherwise.
	if "Controlled" in car:
		car.Controlled = false
	
	# Release throttle, clutch, handbrake, and steering.
	if "gaspedal" in car:
		car.gaspedal = 0.0
	if "throttle" in car:
		car.throttle = 0.0
	if "handbrakepull" in car:
		car.handbrakepull = 0.0
	if "steer_target" in car:
		car.steer_target = 0.0
	if "final_steer" in car:
		car.final_steer = 0.0
	
	# Light brake so it rolls to a stop. 25% of max brake.
	if "brakepedal" in car:
		car.brakepedal = 0.25
	
	# Also zero the raw control flags so any input-system fallbacks don't
	# re-apply gas/brake on the next physics tick.
	if "gas" in car:
		car.gas = false
	if "brake" in car:
		car.brake = false
	if "handbrake" in car:
		car.handbrake = false

## Cycle control to the next spawned car. Convenient for keybinds.
func cycle_active(direction: int = 1) -> void:
	if _cars.is_empty():
		return
	# Compact the list of valid instances first.
	_cars = _cars.filter(func(c): return is_instance_valid(c))
	if _cars.is_empty():
		_active_car = null
		active_car_changed.emit(null)
		return
	var idx := _cars.find(_active_car)
	if idx < 0:
		set_active(_cars[0])
		return
	var next := (idx + direction) % _cars.size()
	if next < 0:
		next += _cars.size()
	set_active(_cars[next])


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

func get_all_cars() -> Array:
	_cars = _cars.filter(func(c): return is_instance_valid(c))
	return _cars.duplicate()


func has_active() -> bool:
	return get_active() != null


func count() -> int:
	_cars = _cars.filter(func(c): return is_instance_valid(c))
	return _cars.size()


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _on_car_exiting(car: Node) -> void:
	# tree_exiting fires before queue_free completes, so the instance is still
	# valid here. Clean up our refs.
	unregister(car)
