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
## Steer with an analog stick (gamepad / controller).
## When true, the existing "left" and "right" input actions are read as a
## continuous axis via [code]Input.get_axis[/code] rather than as discrete
## key presses. Bind those actions to a joypad axis in the project Input Map
## (e.g. Joypad Axis 0 negative for "left", positive for "right").
@export var analog_steering := false
## Deadzone applied to analog steering (0.0–1.0). Inputs with magnitude
## below this are treated as zero; above it the remaining range is rescaled
## back to 0..1 so the wheel still reaches full lock.
@export var analog_steering_deadzone := 0.08
## Sensitivity curve exponent for analog steering. 1.0 = linear,
## values >1 give finer control near center, values <1 are more aggressive.
@export var analog_steering_curve := 1.0
@export var steer_amount_decay := 0.015
@export var steering_assistance := 0.0
@export var steering_assistance_angular := 0.0
@export_subgroup("Steering/Keyboard")
@export var keyboard_steer_speed := 0.025
@export var keyboard_return_speed := 0.05
@export var keyboard_compensate_speed := 0.1

@export_subgroup("Pedals")
## Read throttle / brake / handbrake / clutch as analog.
## When true, each pedal value is set directly each frame from the
## corresponding action's strength (0.0–1.0), bypassing on_*_rate /
## off_*_rate ramping. Bind your gamepad triggers (or USB pedal axes) to
## the "gas", "brake", "handbrake", and "clutch" actions in the Input Map.
@export var analog_pedals := false
## Deadzone for analog pedal inputs (0.0–1.0). Trigger / pedal values below
## this are clamped to 0; above it the remaining range is rescaled to 0..1.
@export var analog_pedal_deadzone := 0.0

# if you want to use racing pedals or not because "var have_wheel_throttle := not is_nan(wheel_throttle)" in car.gs doesn't work!?!
@export var pedal_input := true

# smae stupid thing with the clutch!
@export var using_clutch := false

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


# FUTURE: Steering wheel device support

# The flags below are reserved for direct steering-wheel device integration
# (Logitech G29, Thrustmaster T300, Fanatec, etc.). Godot 4 does not yet
# expose a native FFB API, so wiring these up requires either:
#   - a GDExtension that talks to SDL2's haptics layer, or
#   - a platform-specific plugin (Windows DirectInput / Linux evdev).
#
# When you add a wheel plugin, populate Car._read_steering_wheel_axis() and
# Car._apply_force_feedback() — those are the two integration points the
# rest of the codebase already calls.

@export_subgroup("Steering Wheel")
## Use a dedicated steering-wheel device for steering input.
@export var wheel_steering := true

@export_subgroup("Force Feedback")
## Master FFB on/off.
@export var ffb_enabled := true
## Master FFB strength multiplier (0.0–1.0).
@export var ffb_strength := 1.0
## Self-aligning torque scale — derived from front-wheel lateral force.
@export var ffb_self_aligning := 1.0
## Bump / road-feel scale — derived from suspension load deltas frame-to-frame.
@export var ffb_road_feel := 0.5
## Curb / surface-effect scale — fires a bump pulse on large load spikes.
@export var ffb_surface_effects := 0.5
## Exponential smoothing factor for the constant force (0..1). Lower values
## feel heavier and dampen high-frequency noise; higher values feel snappier
## but can chatter. 0.3–0.5 is a good starting range.
@export_range(0.0, 1.0, 0.05) var ffb_smoothing := 0.4
