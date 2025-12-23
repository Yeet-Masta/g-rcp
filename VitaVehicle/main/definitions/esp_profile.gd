## A definition for Electronic Stability Program settings.

class_name ESPProfile extends Resource



## Steering slip before ESP is triggered.
@export var stabilization_threshold := 0.5
## How aggressively the system corrects understeer.
@export var correction_rate := 1.5
## Sensitivity to unintended normal rotation.
@export var yaw_threshold := 1.0
## Strength of braking for correcting yaw.
@export var yaw_correction_rate := 3.0
