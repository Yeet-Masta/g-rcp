# Formulas
# Power (W) = Torque (N.m) * Speed (rpm) / 9.5488
# Horsepower (hp(I)) = Power (W) / 745.70 W
#
# For some reason the guy chose to make it all super difficult by doing this:
# Distance (Scaled unit) * 0.30592 = Distance (meter)
# Distance (Scaled unit) / 3.26882845188 = Distance (meter)
# NOTE:
# For code it will be more readable to have functions that convert, rather than constants.
# Scaled unit refers to the custom scale of the game.

class_name Constants
extends Node


## Distance (Scaled unit) * 0.30592 = Distance (meter)
## Distance (Scaled unit) / 3.26882845188 = Distance (meter)
const UNIT_TO_METER := 0.30592

## Distance (meter) * 3.26882845188 = Distance (Scaled unit)
## Distance (meter) / 0.30592 = Distance (Scaled unit)
const METER_TO_UNIT := 3.26882845188

## Speed (Scaled unit) * 1.10130592 = Speed (KMH)
const UNIT_TO_KMH := 1.10130592

## Torque (lbf*ft) * Speed (rpm) / 5252.0 = Horsepower (hp(I))
const TQFTRPM_TO_HP := 5252.0

## Torque (lbf*ft) * 1.3558179483 = Torque (N.m)
const LBFFT_TO_NM := 1.3558179483

## Magic number
const RISE_FACTOR = 1e-7 # 1.0 / 10000000.0

## Magic number
const REVSPEED_TUNE = 1.475

## The height of the skid marks
const SKIDMARK_HEIGHT = 0.025

## The speed at which camera drag gets unlocked
const CAM_DRAG_UNLOCK_VELOCITY = 5.0
