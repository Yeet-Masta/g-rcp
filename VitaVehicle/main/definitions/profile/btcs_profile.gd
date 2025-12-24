## A definition for Brake-based Traction Control System settings.

class_name BTCSProfile extends Resource



## Percent of wheelspin allowed before the system reacts.
@export var slip_threshold := 10.0
## How fast the system brakes.
@export var sensitivity := 0.05
