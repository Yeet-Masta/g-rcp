## A definition for Shift Assist settings.

class_name ShiftAssistProfile extends Resource



## Frames to wait during shifting.
@export var shift_delay := 20
## RPM needed to trigger a downshift.
@export var downshift_rpm := 6000.0
## RPM needed to trigger an upshift.
@export var upshift_rpm := 6200.0
## RPM at which the assistant releases the clutch.
@export var clutch_out_rpm := 3000.0
## Delay after a shift before throttle is registered again.
@export var post_shift_delay := 5
