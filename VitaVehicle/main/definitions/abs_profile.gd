## A definition for Anti-lock Braking System settings.

class_name ABSProfile extends Resource



## ABS doesn't activate if the vehicle speed is slower than this.
@export var min_speed := 10.0
## How fast the braking pressure changes in units/frame. Unit (0.0 - 1.0).
@export_range(0.0, 1.0, 0.01) var pump_rate := 0.5
## Amount of wheel slip allowed before the system releases the brakes.
@export var slip_threshold := 2500.0
## How many physics ticks the brakes remain "released" once a lock-up is detected.
@export_range(0, 100, 1) var pump_duration := 1
## Slip threshold for sideways sliding (prevent spinning under heavy braking).
@export var lateral_slip_threshold := 500.0
## Pump duration when triggered by sideways slip.
@export_range(0, 100, 1) var lateral_pump_duration := 2
