## A definition for CVT settings.

class_name CVTProfile extends Resource



## Maps throttle position to engine efficiency for "optimal" RPM.
@export var efficiency_range := 0.75
## How quickly the pulleys change the ratio.
@export var ratio_step_rate := 0.025
## A multiplier for how high the RPM "floats" during acceleration.
@export var rpm_offset := 0.9
## Torque at 0 km/h.
@export var standstill_torque := 500.0
## Delay factor until the variator "settles" on a specific engine speed.
@export var lock_timing := 2.0
## Prevents the CVT from jittering between ratios.
@export var stability_damping := 0.2
