extends TextureRect



@export var debug: Debug



func _process(_delta: float) -> void:
	if !debug.car: return
	if !debug.car.fuel: return
	
	# New BSFC-based API takes the car directly.
	var consumption: float = debug.car.fuel.get_consumption(debug.car)
	modulate.a = remap(consumption, 0.0, 0.02, 0.0, 1.0)
