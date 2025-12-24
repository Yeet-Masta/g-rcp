## A definition for Throttle-based Traction Control System settings.

class_name TTCSProfile extends Resource



## Percent of wheelspin allowed before the system reacts.
@export var slip_threshold := 5.0
## How fast the system cuts off throttle.
@export var sensitivity := 1.0
