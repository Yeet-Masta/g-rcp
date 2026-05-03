## A definition for Anti-lock Braking System settings.
##
## Two controllers are available, selected by [member use_advanced_controller]:
## [br][br]
## [b]Advanced (default)[/b] — a per-wheel slip-target controller modelled on
## the x-engineer.org Xcos ABS reference. Each wheel computes its longitudinal
## slip ratio [code]s = 1 − (ω·r)/v[/code], a bang-bang law picks the sign of
## the valve command from the slip error [code]target_slip − s[/code], and a
## first-order hydraulic lag (gain [member controller_gain], time constant
## [member hydraulic_time_constant]) smooths the command before it is
## integrated into a 0..1 brake modulation. Below [member min_speed] the
## modulation is released to 1.0 so the wheel can lock to a stop.
## [br][br]
## [b]Legacy[/b] — the original global-modulator pump that fires for a fixed
## [member pump_duration] whenever any wheel exceeds [member slip_threshold].
## Kept for backward compatibility with vehicles tuned against the old curve.

class_name ABSProfile extends Resource


## When true, use the slip-target bang-bang controller with hydraulic lag
## (per-wheel). When false, use the legacy global pump-duration logic.
@export var use_advanced_controller := true

@export_group("Common")
## ABS doesn't activate if the vehicle speed is slower than this. Below this
## speed the wheel is allowed to lock so the car can come to a complete stop.
@export var min_speed := 10.0

@export_group("Advanced controller")
## Target longitudinal slip ratio. The peak of the friction–slip curve sits
## around 0.15–0.25 for most road surfaces, so 0.2 is the standard textbook
## choice and matches the x-engineer.org reference.
@export_range(0.0, 1.0, 0.01) var target_slip := 0.20
## Hydraulic amplification factor (K). Sets how aggressively the modulation
## ramps when the bang-bang valve commits. Higher = snappier, more chatter.
## In 1/s units: gain × delta is the per-frame change in modulation when the
## valve is fully committed. ~10–20 gives realistic 8–15 Hz cycling.
@export_range(0.0, 100.0, 0.1) var controller_gain := 12.0
## Hydraulic time constant (T) in seconds. Smooths the ±1 bang-bang command
## into a continuous valve state, preventing infinite-frequency oscillation.
## Real systems sit around 0.01–0.05 s; smaller = sharper but noisier.
@export_range(0.001, 0.5, 0.001) var hydraulic_time_constant := 0.04
## Rate at which the per-wheel brake modulation relaxes back to 1.0 when ABS
## is not actively intervening (driver off the brake, below cutoff speed,
## or wheel airborne). In modulation-units per second.
@export_range(0.0, 50.0, 0.1) var release_rate := 8.0
## Lateral velocity threshold (in the codebase's local units) above which
## the controller forces a brake release regardless of longitudinal slip.
## Keeps the car from spinning out under heavy combined braking.
@export var lateral_speed_threshold := 6.0

@export_group("Legacy controller")
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
