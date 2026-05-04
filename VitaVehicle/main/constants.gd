# Formulas
# Power (W) = Torque (N.m) * Speed (rpm) / 9.5488
# Horsepower (hp(I)) = Power (W) / 745.70 W
#
# Distance (Scaled unit) * 0.30592 = Distance (meter)
# Distance (Scaled unit) / 3.26882845188 = Distance (meter)
# NOTE:
# Scaled unit refers to the custom scale of the game.
# These units are not replacable by the units in the Godot Short addon.

## Project-wide constants. Not a Node — it never had any reason to be one;
## it has no instance state, no _ready, no _process. Const-only "namespace"
## classes idiomatically just extend [Object] (or omit `extends` and inherit
## RefCounted by default), so [code]Constants.UNIT_TO_METER[/code] keeps
## working for every existing call site without polluting the scene tree.

class_name Constants


## Distance (Scaled unit) * 0.30592 = Distance (meter)
## Distance (Scaled unit) / 3.26882845188 = Distance (meter)
const UNIT_TO_METER := 0.30592

## Distance (meter) * 3.26882845188 = Distance (Scaled unit)
## Distance (meter) / 0.30592 = Distance (Scaled unit)
const METER_TO_UNIT := 3.26882845188

## Speed (Scaled unit) * 1.10130592 = Speed (KMH)
const UNIT_TO_KMH := 1.10130592

## Magic number used in the engine torque curves. = 1.0 / 10000000.0.
const RISE_FACTOR = 1e-7

## Magic number used to normalize the rev-speed parameter against the
## historical default tuning of 1.475.
const REVSPEED_TUNE = 1.475

## The height of the skid marks above the ground.
const SKIDMARK_HEIGHT = 0.025

## The speed at which camera drag gets unlocked.
const CAM_DRAG_UNLOCK_VELOCITY = 5.0
