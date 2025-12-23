extends TextureRect



@export var debug: Debug



func _process(_delta: float) -> void:
	if !debug.car: return
	
	modulate.a = remap(debug.car.fuel.get_fuel_consumption(), 0.0, 0.02, 0.0, 1.0)
