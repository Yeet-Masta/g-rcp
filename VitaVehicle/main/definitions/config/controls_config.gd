## A definition for controls settings.

class_name ControlsConfig extends Resource



enum ShiftAssistLevel {
	NONE, ## Fully physical gearbox. If the car is manual, controls are manual, if it's automatic, it'll drive like automatic.
	WEAK, ## Helps with the clutch when shifting gears. Avoids stalling.
	FULL, ## Shifts gears for you.
}



@export_group("Car Controls")
@export_subgroup("Gearbox")
@export var shift_assist_level := ShiftAssistLevel.NONE

@export_subgroup("Steering")
@export var steering_sensitivity := 1.0
## Steer with the mouse.
@export var mouse_steering := false
## Steer with the accelerometer, if your device has one.
@export var accelerometer_steering := false
@export var steer_amount_decay := 0.015
@export var steering_assistance := 0.0
@export var steering_assistance_angular := 0.0
@export_subgroup("Steering/Keyboard")
@export var keyboard_steer_speed := 0.025
@export var keyboard_return_speed := 0.05
@export var keyboard_compensate_speed := 0.1

@export_subgroup("Pedals/Throttle")
@export var max_throttle := 1.0
@export var on_throttle_rate := 0.2
@export var off_throttle_rate := 0.2

@export_subgroup("Pedals/Brake")
@export var max_brake := 1.0
@export var on_brake_rate := 0.05
@export var off_brake_rate := 0.1

@export_subgroup("Pedals/Handbrake")
@export var max_handbrake := 1.0
@export var on_handbrake_rate := 0.2
@export var off_handbrake_rate := 0.2

@export_subgroup("Pedals/Clutch")
@export var max_clutch := 1.0
@export var on_clutch_rate := 0.2
@export var off_clutch_rate := 0.2
