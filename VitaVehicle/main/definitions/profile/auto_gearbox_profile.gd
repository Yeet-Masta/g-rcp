## A definition for Automatic Gearbox settings.

class_name AutoGearboxProfile extends Resource



## RPM at which the gearbox switches to a higher gear.
@export var upshift_rpm := 6500.0
## RPM range under last upshift that triggers a downshift.
@export var downshift_threshold := 300.0
## How much throttle influences the shifting speed.
@export var throttle_threshold := 0.5
## Minimum threshold for clutch engagement.
@export var engagement_min_rpm := 0.0
## Upper limit where the automatic clutch is fully locked.
@export var engagement_max_rpm := 4000.0
