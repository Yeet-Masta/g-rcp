## The car: a [RigidBody3D] that orchestrates the engine, drivetrain,
## transmission, stability assists, fuel system, and aero.
##
## This file used to be ~1450 lines doing all of the above inline. It has
## been slimmed to be an [b]orchestrator[/b]: each subsystem now lives in its
## own helper class ([EngineModel], [TransmissionController],
## [StabilityControllers], [Fuel]) and Car holds the @export configuration +
## per-frame state, dispatching to those helpers.
##
## All public state, public methods, and @export properties are unchanged —
## the scene file does not need to be edited.

class_name Car extends RigidBody3D

signal debug_lamp_changed

enum TransmissionType {FULLY_MANUAL, AUTOMATIC, CONTINUOUSLY_VARIABLE, SEMI_AUTO}

@export_group("Profiles")
@export var fuel: Fuel

@export_subgroup("Gearbox")
@export var shift_assist: ShiftAssistProfile
@export var auto_gearbox: AutoGearboxProfile
@export var cvt: CVTProfile

@export_subgroup("Stability")
## Anti-lock Braking System.
@warning_ignore("shadowed_global_identifier")
@export var abs: ABSProfile
## Electronic Stability Program.
@export var esp: ESPProfile
## Brake-based Traction Control System.
@export var btcs: BTCSProfile
## Throttle-based Traction Control System
@export var ttcs: TTCSProfile

@export_group("Other")
@export var Debug_Mode := false
@export var LooseSteering := false # simulate rack and pinion steering physics (EXPERIMENTAL)
@export var Controlled := true

@export_group("Chassis")
@export_custom(PROPERTY_HINT_NONE, "suffix:kg") var Weight := 900.0:
	set(value):
		Weight = value
		# Body mass is derived from Weight at a 1:10 scale (the game's unit
		# system is one-tenth of metric, see Constants.UNIT_TO_METER). Update
		# the RigidBody mass eagerly so _physics_process doesn't have to do it
		# every tick.
		mass = value / 10.0

@export_group("Body")
@export var LiftAngle := 0.1
@export var DragCoefficient := 0.25
@export var Downforce := 0.0

@export_group("Steering")
@export var AckermannPoint := -3.8
@export var Steer_Radius := 13.0

@export_group("Drivetrain")
@export var Powered_Wheels: Array[String] = ["fl","fr"]

@export var final_drive := 4.250
@export var GearRatios: Array[float] = [ 3.250, 1.894, 1.259, 0.937, 0.771 ]
@export var reverse_ratio := 3.153
@export var ratio_multi := 9.5
@export var StressFactor := 1.0
@export var GearGap := 60.0
@export var DSWeight := 150.0

@export var transmission_type := TransmissionType.FULLY_MANUAL

@export_group("Differentials")
@export var Locking := 0.1
@export var CoastLocking := 0.0
@export var Preload := 0.0
@export var Centre_Locking := 0.5
@export var Centre_CoastLocking := 0.5
@export var Centre_Preload := 0.0

@export_group("Engine")
@export var RevSpeed := 2.0
@export var EngineFriction := 18000.0
@export var EngineDrag := 0.006
@export var ThrottleResponse := 0.5
@export var DeadRPM := 200.0

@export_group("ECU")
@export var RPMLimit := 7000.0
@export var LimiterDelay := 4
@export var IdleRPM := 800.0
@export var ThrottleLimit := 0.0
@export var ThrottleIdle := 0.25
@export var VVTRPM := 4500.0

@export_group("Torque normal state")
@export var BuildUpTorque := 0.0035
@export var TorqueRise := 30.0
@export var RiseRPM := 1000.0
@export var OffsetTorque := 110.0
@export var FloatRate := 0.1
@export var DeclineRate := 1.5
@export var DeclineRPM := 3500.0
@export var DeclineSharpness := 1.0

@export_group("Torque variable valve timing")
@export var VVT_BuildUpTorque := 0.0
@export var VVT_TorqueRise := 60.0
@export var VVT_RiseRPM := 1000.0
@export var VVT_OffsetTorque := 70.0
@export var VVT_FloatRate := 0.1
@export var VVT_DeclineRate := 2.0
@export var VVT_DeclineRPM := 5000.0
@export var VVT_DeclineSharpness := 1.0

@export_group("Clutch")
@export var ClutchStable := 0.5
@export var GearRatioRatioThreshold := 200.0
@export var ThresholdStable := 0.01
@export var ClutchGrip := 176.125
@export var ClutchFloatReduction := 27.0
@export var ClutchWobble := 2.5*0
@export var ClutchElasticity := 0.2*0
@export var WobbleRate := 0.0

@export_group("Forced inductions")
@export var MaxPSI := 9.0
@export var EngineCompressionRatio := 8.0
@export_subgroup("Turbo")
@export_custom(PROPERTY_HINT_GROUP_ENABLE, "Turbo") var TurboEnabled := false
@export var TurboAmount := 1
@export var TurboSize := 8.0
@export var Compressor := 0.3
@export var SpoolThreshold := 0.1
@export var BlowoffRate := 0.14
@export var TurboEfficiency := 0.075
@export var TurboVacuum := 1.0
@export_subgroup("Supercharger")
@export_custom(PROPERTY_HINT_GROUP_ENABLE, "Supercharger") var SuperchargerEnabled := false
@export var SCRPMInfluence := 1.0
@export var BlowRate := 35.0
@export var SCThreshold := 6.0

## Current RPM.
var rpm := 0.0
var rpmspeed := 0.0
var resistancerpm := 0.0
var resistancedv := 0.0
## Current transmission gear.
var gear := 0
var limiter_delay := 0
var actualgear := 0
var gearstress := 0.0
## Actual engine throttle.
var throttle := 0.0:
	set(value): throttle = clamp(value, 0.0, 1.0)
var cvtaccel := 0.0
var shift_assist_delay := 0
## Shift assist step.
var sassiststep := 0
var clutchin := false
var gasrestricted := false
var revmatch := false
## Throttle input.
var gaspedal := 0.0:
	set(value): gaspedal = clamp(value, 0.0, ConfigManager.data.controls.max_throttle)
var brakepedal := 0.0:
	set(value): brakepedal = clamp(value, 0.0, ConfigManager.data.controls.max_brake)
var clutchpedal := 0.0:
	set(value): clutchpedal = clamp(value, 0.0, 1.0)
var clutchpedalreal := 0.0:
	set(value): clutchpedalreal = clamp(value, 0.0, ConfigManager.data.controls.max_clutch)
## Final steering target after assists and decay.
var final_steer := 0.0:
	set(value): final_steer = clamp(value, -1.0, 1.0)
## Raw steering target from key/mouse/accel input.
var steer_target := 0.0:
	set(value): steer_target = clamp(value, -1.0, 1.0)
var abs_delay := 0.0
var tcsweight := 0.0
var tcsflash := false
var espflash := false
var tcs_flash_timer: float = 0.0
## Current gear ratio (gear * final_drive).
var ratio := 0.0
var brake_allowed := 1.0
## Real engine torque.
var engine_torque := 0.0
## Does the engine inject and ignite fuel?
var is_ignition_on := true
## The amount of vaccuum.
var stall_resistance := 0.0

## Final brake pressure.
var brakeline := 0.0
var handbrakepull := 0.0:
	set(value): handbrakepull = clamp(value, 0.0, ConfigManager.data.controls.max_handbrake)
var dsweight := 0.0
var dsweightrun := 0.0
var diffspeed := 0.0
var diffspeedun := 0.0
var locked := 0.0
var c_locked := 0.0
var wv_difference := 0.0
var rpmforce := 0.0
var whinepitch := 0.0
var turbopsi := 0.0
var scrpm := 0.0
var boosting := 0.0
var rpmcs := 0.0
var rpmcsm := 0.0
var currentstable := 0.0
var steering_geometry := [0.0, 0.0]
var resistance := 0.0
var wob := 0.0
var ds_weight := 0.0
var steer_torque := 0.0
var steer_velocity := 0.0
var drivewheels_size := 1.0

var steering_angles := []
var max_steering_angle := 0.0
var assistance_factor := 0.0

var pastvelocity := Vector3(0, 0, 0)
var gforce := Vector3(0, 0, 0)
var clock_mult := 1.0
var dist := 0.0
var stress := 0.0

# Control flags
var input_upshift := false
var input_downshift := false
var gas := false
var brake := false
var handbrake := false
var clutch := false
## Powered wheel nodes.
var c_pws := []

var velocity := Vector3(0, 0, 0)
var rvelocity := Vector3(0, 0, 0)

# Debug draw
var front_wheels: Array[Wheel] = []
var rear_wheels: Array[Wheel] = []
var front_load := 0.0
var total := 0.0
var weight_dist := [0.0, 0.0]

var debug_lamp := false:
	set(value): debug_lamp = value; debug_lamp_changed.emit()

## The current amount of fuel in [code]liters[/code].
@onready var current_fuel := fuel.max_fuel


# Cached references / scratch space

## Reusable engine torque-curve params. Filled in [method simulate_engine]
## via [code]EngineModel.params_from_car_into[/code] so the runtime never
## allocates a new struct per physics tick.
var _engine_params: EngineModel.CurveParams = EngineModel.CurveParams.new()

## Optional drag-centre node. Cached on _ready; null when the scene doesn't
## include a [code]DRAG_CENTRE[/code] child.
var _drag_centre: Node3D = null

## Cached autoload lookup so we don't crawl the scene root every time a
## script asks who's driving.
var _car_manager: Node = null

## All [Wheel] children — populated once in [method _ready]. Used by stability
## controllers and debug draw to avoid iterating [code]get_children()[/code]
## and type-checking each entry every frame. The powered-wheel subset stays in
## [code]c_pws[/code].
var _all_wheels: Array[Wheel] = []

# Cached front/rear wheel splits for debug draw. Built once in _ready against
# the wheel placement convention (+z is front).
var _front_wheels_cache: Array[Wheel] = []
var _rear_wheels_cache: Array[Wheel] = []

# Latched shift inputs — populated in _input() so a key press that lands
# between physics ticks isn't lost. Cleared by the gearbox controller when
# consumed.
var _pending_upshift := false
var _pending_downshift := false

# Lifecycle

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug_mode"):
		Debug_Mode = !Debug_Mode
	if event.is_action_pressed("ignition"):
		toggle_ignition()
	# Latch shift requests here rather than polling Input.is_action_just_pressed
	# from _physics_process. The physics tick may fall outside the engine frame
	# where the press was first detected, in which case is_action_just_pressed
	# returns false and the shift is silently dropped. Latching guarantees the
	# request survives until the gearbox consumes it.
	if Controlled:
		var mouse: bool = ConfigManager.data.controls.mouse_steering
		var suffix := "_mouse" if mouse else ""
		if event.is_action_pressed("shiftup" + suffix):
			_pending_upshift = true
		if event.is_action_pressed("shiftdown" + suffix):
			_pending_downshift = true


func _ready():
	# Make sure mass reflects Weight even when Weight was assigned in the
	# editor before our setter existed (setters don't run on default value
	# assignment from saved scenes in all Godot versions).
	mass = Weight / 10.0

	# Multi-car: register with the manager (if the autoload is configured).
	# Resolved by-name to avoid a compile dependency on the autoload.
	_car_manager = _find_car_manager()
	if _car_manager != null:
		_car_manager.call("register", self)
	# Auto-start spark engines (you turn the key); diesels auto-start only
	# if already cranking above their auto-ignition threshold.
	var should_start := true
	if fuel != null and "ignition_type" in fuel:
		# Compare by value (1 = COMPRESSION) so older Fuel resources without
		# the field don't blow up.
		if fuel.ignition_type == 1:
			should_start = fuel.should_compression_autostart(rpm)
	if should_start:
		start_engine()
	for i in Powered_Wheels:
		c_pws.append(get_node(i))

	# Cache the wheel set and the front/rear split. The convention is
	# "+z is front" — same as draw_debug used to compute live every frame.
	for child in get_children():
		if child is Wheel:
			_all_wheels.append(child)
			if child.position.z > 0:
				_front_wheels_cache.append(child)
			else:
				_rear_wheels_cache.append(child)

	# Cache the optional aero centre node.
	if has_node("DRAG_CENTRE"):
		_drag_centre = $DRAG_CENTRE


func _find_car_manager() -> Node:
	if get_tree() == null:
		return null
	var root := get_tree().root
	if root.has_node("CarManager"):
		return root.get_node("CarManager")
	return null


func _process(_delta):
	if Debug_Mode:
		draw_debug()


func _physics_process(delta):
	# Reduce steering sensitivity as max-angle grows. This loop runs once per
	# frame after wheels populate steering_angles in their physics_process.
	if len(steering_angles) > 0:
		max_steering_angle = 0.0
		for a in steering_angles:
			max_steering_angle = maxf(max_steering_angle, a)
		assistance_factor = 90.0 / max_steering_angle
	steering_angles = []

	# World → local frame velocity vectors (used by steering, ESP, fuel).
	var basis_t := global_transform.basis.orthonormalized().transposed()
	velocity = basis_t * linear_velocity
	rvelocity = basis_t * angular_velocity

	# mass is now maintained by the Weight setter; no per-frame recompute.
	_apply_aero()

	# G-force telemetry.
	gforce = (linear_velocity - pastvelocity) * ((Constants.UNIT_TO_METER / Physics.EARTH_GRAVITY) / delta)
	pastvelocity = linear_velocity
	gforce = basis_t * gforce

	controls()
	ratio = 10.0
	shift_assist_delay -= 1
	transmission()

	# Steering geometry update for the wheels' raycast retargeting.
	var steer_reduction := pow(max_steering_angle / 90.0, 2) * 0.5
	var steeroutput = final_steer * (abs(final_steer) * steer_reduction + (1.0 - steer_reduction))
	if absf(steeroutput) > 0.0:
		steering_geometry = [-Steer_Radius / steeroutput, AckermannPoint]

	# Stability assists. Each handles its own null guard against the profile.
	StabilityControllers.apply_abs(self, delta)
	StabilityControllers.apply_btcs(self, delta)
	StabilityControllers.apply_ttcs(self, delta)
	StabilityControllers.apply_esp(self)

	brakeline = max(brakepedal * brake_allowed, 0.0)

	# Throttle response. While the rev limiter is firing, decay throttle to 0.
	if not is_redline_limiter_on():
		throttle -= (throttle - (gaspedal / (tcsweight * clutchpedal + 1.0))) * (ThrottleResponse / clock_mult)
	else:
		throttle -= throttle * (ThrottleResponse / clock_mult)

	apply_redline_limiter()
	apply_idle_throttle_compensation()
	simulate_turbo()
	simulate_engine()
	drivetrain()
	simulate_fuel()

	# Force-feedback dispatch happens last so the wheels' .directional_force
	# (set by their _physics_process this frame) is fresh when we read it.
	_apply_force_feedback()


# Public API (kept for external callers — debug.gd, car_manager.gd, etc.)

func toggle_ignition():
	if is_ignition_on: stop_engine()
	else: start_engine()


func start_engine():
	rpm = max(rpm, IdleRPM)
	is_ignition_on = true


func stop_engine():
	is_ignition_on = false


func is_above_idle_rpm() -> bool: return rpm > IdleRPM
func is_vvt_active() -> bool:     return rpm > VVTRPM
func is_redline_limiter_on() -> bool: return limiter_delay > 0
func is_in_gear() -> bool:        return actualgear != 0
func is_throttle_open() -> bool:  return throttle > 0.0


## Asks [code]CarManager[/code] (if present) to hand control to this car.
func make_active() -> void:
	if _car_manager != null:
		_car_manager.call("set_active", self)
	else:
		Controlled = true


# Engine

func apply_redline_limiter():
	if rpm > RPMLimit and throttle > ThrottleLimit:
		throttle = ThrottleLimit
		limiter_delay = LimiterDelay
	limiter_delay -= 1


func apply_idle_throttle_compensation():
	# The farther below idle RPM we drift, the more throttle we force. Keeps
	# the engine from stalling under heavy load without a curve resource.
	if rpm < IdleRPM:
		throttle = clamp(throttle, ThrottleIdle + ((IdleRPM - rpm) / IdleRPM), 1.0)


func simulate_turbo():
	if TurboEnabled:
		var thr: float = (throttle - SpoolThreshold) / (1 - SpoolThreshold)
		if boosting > thr:
			boosting = thr
		else:
			boosting -= (boosting - thr) * TurboEfficiency
		turbopsi += (boosting * rpm) / ((TurboSize / Compressor) * 60.9)
		turbopsi -= turbopsi * BlowoffRate
		turbopsi = clamp(turbopsi, -TurboVacuum, MaxPSI)
	elif SuperchargerEnabled:
		scrpm = rpm * SCRPMInfluence
		turbopsi = clamp((scrpm / 10000.0) * BlowRate - SCThreshold, 0.0, MaxPSI)
	else:
		turbopsi = 0.0


func simulate_engine():
	# Diesel: if the engine is off but the wheels are turning the crank fast
	# enough (clutch engaged in gear, push-start, etc.), it self-ignites.
	if not is_ignition_on and fuel != null and "ignition_type" in fuel:
		if fuel.ignition_type == 1 and fuel.should_compression_autostart(rpm) and current_fuel > 0.0:
			start_engine()

	var torque := 0.0
	if not is_ignition_on:
		throttle = 0.0
		turbopsi = 0.0
	else:
		# Combustion torque from the shared engine model. Note: the dyno
		# graph in draw.gd computes the same curve via the same model.
		# Reuses our pre-allocated CurveParams to avoid per-frame heap churn.
		EngineModel.params_from_car_into(self, _engine_params)
		torque = EngineModel.torque_runtime(_engine_params, rpm, turbopsi, throttle)

	rpmforce = rpm / (absf(rpm * rpm) / (EngineFriction / clock_mult) + 1.0)
	if rpm < DeadRPM:
		stop_engine()
		torque = 0.0
		rpmforce /= 5.0
		stall_resistance = 1.0 - rpm / DeadRPM
	else:
		stall_resistance = 0.0

	rpmforce += rpm * (EngineDrag / clock_mult)
	rpmforce -= torque / clock_mult
	rpm -= rpmforce * RevSpeed
	engine_torque = torque


# Drivetrain & clutch

func drivetrain():
	# Clutch elasticity / wobble model.
	rpmcsm -= (rpmcs - resistance)
	rpmcs += rpmcsm * ClutchElasticity
	rpmcs -= rpmcs * (1.0 - clutchpedal)
	wob = ClutchWobble * clutchpedal * ratio * WobbleRate
	rpmcs -= (rpmcs - resistance) * (1.0 / (wob + 1.0))

	var rpm_change: float = ((rpmcs * 1.0) / clock_mult) * (RevSpeed / Constants.REVSPEED_TUNE)
	rpm += -rpm_change if gear < 0 else rpm_change

	gearstress = (absf(resistance) * StressFactor) * clutchpedal
	var stabled := ratio * 0.9 + 0.1
	ds_weight = DSWeight / stabled
	whinepitch = absf(rpm / ratio) * 1.5

	# Per-axle locking from torque direction.
	if resistance > 0.0:
		locked = absf(resistance / ds_weight) * (CoastLocking / 100.0) + Preload
	else:
		locked = absf(resistance / ds_weight) * (Locking / 100.0) + Preload
	locked = clamp(locked, 0.0, 1.0)

	# Centre-diff locking from front/rear wheel-velocity difference.
	if wv_difference > 0.0:
		c_locked = absf(wv_difference) * (Centre_CoastLocking / 10.0) + Centre_Preload
	else:
		c_locked = absf(wv_difference) * (Centre_Locking / 10.0) + Centre_Preload
	if len(c_pws) < 4:
		c_locked = 0.0
	c_locked = clamp(c_locked, 0.0, 1.0)

	var maxd = VitaVehicleSimulation.fastest_wheel(c_pws)
	var floatreduction := 0.0
	if dsweightrun > 0.0:
		floatreduction = ClutchFloatReduction / dsweightrun

	var stabling: float = max(-(GearRatioRatioThreshold - ratio * drivewheels_size) * ThresholdStable, 0.0)
	currentstable = (ClutchStable + stabling) * (RevSpeed / Constants.REVSPEED_TUNE)

	var what := rpm
	if dsweightrun > 0.0:
		what = rpm - (((rpmforce * floatreduction) * currentstable) / (ds_weight / dsweightrun))

	if gear < 0.0:
		dist = maxd.wv + what / ratio
	else:
		dist = maxd.wv - what / ratio
	dist *= pow(clutchpedal, 2)
	if gear == 0:
		dist = 0.0

	# Distribute torque to driven wheels.
	wv_difference = 0.0
	drivewheels_size = 0.0
	for i in c_pws:
		drivewheels_size += i.w_size / len(c_pws)
		i.c_p = i.W_PowerBias
		wv_difference += ((i.wv - what / ratio) / len(c_pws)) * pow(clutchpedal, 2)
		if gear < 0:
			i.dist = dist * (1 - c_locked) + (i.wv + what / ratio) * c_locked
		elif gear > 0:
			i.dist = dist * (1 - c_locked) + (i.wv - what / ratio) * c_locked
		else:
			i.dist = 0.0

	# Reset accumulators consumed by wheels this frame.
	resistance = 0.0
	dsweightrun = dsweight
	dsweight = 0.0
	tcsweight = 0.0
	stress = 0.0


# Transmission — dispatched to TransmissionController

func transmission():
	if Controlled:
		var mouse: bool = ConfigManager.data.controls.mouse_steering
		clutch = (Input.is_action_pressed("clutch") and not mouse) or (Input.is_action_pressed("clutch_mouse") and mouse)
		if ConfigManager.data.controls.shift_assist_level != ControlsConfig.ShiftAssistLevel.NONE:
			clutch = (Input.is_action_pressed("handbrake") and not mouse) or (Input.is_action_pressed("handbrake_mouse") and mouse)
		clutch = !clutch

	TransmissionController.tick(self)


# Fuel

func simulate_fuel():
	if not fuel: return
	current_fuel -= fuel.get_consumption(self) * get_physics_process_delta_time()
	if current_fuel <= 0.0:
		current_fuel = 0.0
		stop_engine()


# Aero

func _apply_aero():
	var basis_n := global_transform.basis.orthonormalized()
	var veloc := basis_n.transposed() * linear_velocity

	# Pitch torque from forward speed × LiftAngle.
	apply_torque_impulse(basis_n * Vector3((-veloc.length() * 0.3) * LiftAngle, 0, 0))

	# Aero coefficient. TODO: promote to an @export so cars can tune it.
	const AERO_COEFF := 0.15
	# Velocity components, scaled. Names reflect what they actually hold —
	# the previous code aliased them (vx/vy/vz) in a way that didn't match
	# the components they referenced.
	var v_lat: float = veloc.x * AERO_COEFF
	var v_long: float = veloc.z * AERO_COEFF
	var v_vert: float = veloc.y * AERO_COEFF
	var v_mag: float = veloc.length() * AERO_COEFF

	# Force composition:
	#   • X: lateral drag (sideslip)
	#   • Y: downforce (proportional to total speed) + vertical drag
	#   • Z: longitudinal drag from forward motion
	var force := basis_n * Vector3(
		-v_lat * DragCoefficient,
		-v_mag * Downforce - v_vert * DragCoefficient,
		-v_long * DragCoefficient
	)
	if _drag_centre != null:
		apply_impulse(force, basis_n * _drag_centre.position)
	else:
		apply_central_impulse(force)


# Controls (input → pedals/steering)

func controls():
	# Read raw inputs first, then dispatch to physical-vs-virtual steering
	# and to the per-frame pedal smoothing in control_car().
	var mouse: bool = ConfigManager.data.controls.mouse_steering
	var suffix := "_mouse" if mouse else ""
	gas            = Input.is_action_pressed("gas" + suffix)
	brake          = Input.is_action_pressed("brake" + suffix)
	# Shift requests are latched from _input() so a press between physics
	# ticks isn't lost. Consume them once and clear.
	input_upshift  = _pending_upshift
	input_downshift = _pending_downshift
	_pending_upshift = false
	_pending_downshift = false
	handbrake      = Input.is_action_pressed("handbrake" + suffix)

	steer_velocity += 0.01 * Input.get_axis("left", "right")

	if LooseSteering:
		simulate_physical_steering()

	if Controlled:
		control_car()


func simulate_physical_steering():
	final_steer += steer_velocity
	if absf(final_steer) > 1.0:
		steer_velocity *= -0.5

	for i in [$fl, $fr]:
		steer_velocity += (i.directional_force.x * 0.00125) * i.Caster
		steer_velocity -= (i.stress * 0.0025) * (atan2(absf(i.wv), 1.0) * i.angle)
		steer_velocity += final_steer * (i.directional_force.z * 0.0005) * i.Caster
		if i.position.x > 0:
			steer_velocity += i.directional_force.z * 0.0001
		else:
			steer_velocity -= i.directional_force.z * 0.0001
		steer_velocity /= i.stress / (pow(i.slip_percpre, 2) * 100.0 + 1.0) + 1.0


func control_car():
	var c: ControlsConfig = ConfigManager.data.controls
	var left := Input.is_action_pressed("left")
	var right := Input.is_action_pressed("right")

	# Pedals
	if c.analog_pedals:
		# Analog branch: trigger / USB pedal strength IS the pedal position.
		# We still honor full shift-assist's gas↔brake swap when in reverse,
		# and the gasrestricted / revmatch flags from the shift state machine.
		var t_in := _analog_pedal_strength("gas", c.analog_pedal_deadzone)
		var b_in := _analog_pedal_strength("brake", c.analog_pedal_deadzone)
		var hb_in := _analog_pedal_strength("handbrake", c.analog_pedal_deadzone)

		if c.shift_assist_level == ControlsConfig.ShiftAssistLevel.FULL:
			# In reverse, the driver presses "brake" to go and "gas" to stop.
			var go_throttle: float = b_in if gear == -1 else t_in
			var press_brake: float = t_in if gear == -1 else b_in
			if gasrestricted: go_throttle = 0.0
			if revmatch:      go_throttle = max(go_throttle, 0.5)
			gaspedal = go_throttle * c.max_throttle
			brakepedal = press_brake * c.max_brake
		else:
			if c.shift_assist_level == ControlsConfig.ShiftAssistLevel.NONE:
				gasrestricted = false
				clutchin = false
				revmatch = false
			var t: float = 0.0 if (gasrestricted and not revmatch) else t_in
			gaspedal = t * c.max_throttle
			brakepedal = b_in * c.max_brake

		handbrakepull = hb_in * c.max_handbrake
	else:
		# Discrete branch (keyboard / button): existing rate-based ramps.
		if c.shift_assist_level == ControlsConfig.ShiftAssistLevel.FULL:
			var go_forward: bool = (gas and not gasrestricted and gear != -1) or (brake and gear == -1) or revmatch
			gaspedal += (c.on_throttle_rate / clock_mult) if go_forward else -(c.off_throttle_rate / clock_mult)

			var press_brake: bool = (brake and gear != -1) or (gas and gear == -1)
			brakepedal += (c.on_brake_rate / clock_mult) if press_brake else -(c.off_brake_rate / clock_mult)
		else:
			if c.shift_assist_level == ControlsConfig.ShiftAssistLevel.NONE:
				gasrestricted = false
				clutchin = false
				revmatch = false
			gaspedal += (c.on_throttle_rate / clock_mult) if (gas and not gasrestricted) or revmatch else -(c.off_throttle_rate / clock_mult)
			brakepedal += (c.on_brake_rate / clock_mult) if brake else -(c.off_brake_rate / clock_mult)

		handbrakepull += (c.on_handbrake_rate / clock_mult) if handbrake else -(c.off_handbrake_rate / clock_mult)

	# Steering
	# Sideways slip influences how much the assist eases off.
	var siding := absf(velocity.x)
	if (velocity.x > 0 and steer_target > 0) or (velocity.x < 0 and steer_target < 0):
		siding = 0.0
	var going: float = max(velocity.z / (siding + 1.0), 0.0)

	if LooseSteering:
		return

	# Priority order:
	#   1. Dedicated steering wheel device (future, via plugin)
	#   2. Mouse
	#   3. Accelerometer
	#   4. Analog stick / gamepad
	#   5. Keyboard ramp+snap-back
	# Each branch sets steer_target; the assist block below is shared.
	var wheel_axis := _read_steering_wheel_axis()
	if c.wheel_steering and not is_nan(wheel_axis):
		_steer_to_target(wheel_axis * c.steering_sensitivity)
	elif c.mouse_steering:
		var mouseposx := 0.0
		if get_viewport().size.x > 0.0:
			mouseposx = get_viewport().get_mouse_position().x / get_viewport().size.x
		_steer_to_target((mouseposx - 0.5) * 2.0 * c.steering_sensitivity)
	elif c.accelerometer_steering:
		_steer_to_target((Input.get_accelerometer().x / 10.0) * c.steering_sensitivity)
	elif c.analog_steering:
		# Get_axis returns analog (-1..1) when "left"/"right" are bound to a
		# joypad axis in the Input Map. For binary keyboard binds it returns
		# -1, 0, or +1 so the deadzone/curve below are no-ops in that case.
		var raw := Input.get_axis("left", "right")
		var mag := absf(raw)
		if mag < c.analog_steering_deadzone:
			raw = 0.0
		else:
			mag = (mag - c.analog_steering_deadzone) / (1.0 - c.analog_steering_deadzone)
			mag = pow(mag, c.analog_steering_curve)
			raw = signf(raw) * mag
		steer_target = clamp(raw * c.steering_sensitivity, -1.0, 1.0)
	else:
		# Keyboard: ramp toward direction, snap-back to zero when neutral.
		if right:
			steer_target += c.keyboard_steer_speed if steer_target > 0 else c.keyboard_compensate_speed
		elif left:
			steer_target -= c.keyboard_steer_speed if steer_target < 0 else c.keyboard_compensate_speed
		else:
			if steer_target > c.keyboard_return_speed:
				steer_target -= c.keyboard_return_speed
			elif steer_target < -c.keyboard_return_speed:
				steer_target += c.keyboard_return_speed
			else:
				steer_target = 0.0

	#Steering assist (decay & counter-steer)
	if assistance_factor > 0.0:
		var maxsteer: float = 1.0 / (going * (c.steer_amount_decay / assistance_factor) + 1.0)
		var assist_commence: float = min(linear_velocity.length() / 10.0, 1.0)
		final_steer = (steer_target * maxsteer) \
			- (velocity.normalized().x * assist_commence) * (c.steering_assistance * assistance_factor) \
			+ rvelocity.y * (c.steering_assistance_angular * assistance_factor)
	else:
		final_steer = steer_target


## Mouse and accelerometer share an "amplify-near-extremes" curve.
func _steer_to_target(raw: float) -> void:
	steer_target = raw
	var s: float = min(absf(steer_target) * 1.0 + 0.5, 1.0)
	steer_target *= s


## Read an analog action's strength, apply a deadzone, and rescale the
## remaining range back to 0..1 so the pedal can still hit max travel.
func _analog_pedal_strength(action: String, deadzone: float) -> float:
	var v := Input.get_action_strength(action)
	if v < deadzone:
		return 0.0
	return (v - deadzone) / (1.0 - deadzone)


# Steering wheel & FFB hooks (future)

# These two methods are the integration points for a future steering-wheel /
# force-feedback plugin. They are intentionally no-ops by default so the
# game runs identically without any plugin installed. Replace the bodies
# (or override in a subclass) when wiring up an SDL2-FFB GDExtension or a
# platform-specific haptics plugin.

## Read the raw axis (-1..1) of an attached steering wheel device.
##
## Default: returns NAN, meaning "no wheel connected — fall back to other
## input methods". When a plugin is in place, return a value in [-1, 1] mapped
## from the wheel's physical angle:
## [codeblock]
## var c := ConfigManager.data.controls
## if not c.wheel_steering: return NAN
## # Option A — wheel exposed as a normal joypad (Godot's built-in path):
## return Input.get_joy_axis(c.wheel_device_id, JOY_AXIS_LEFT_X)
## # Option B — direct SDL2 / DirectInput plugin:
## #   var deg := SDL2FFB.get_wheel_position_degrees(c.wheel_device_id)
## #   return clamp(deg / (c.wheel_rotation_degrees * 0.5), -1.0, 1.0)
## [/codeblock]
func _read_steering_wheel_axis() -> float:
	return NAN


## Compute and dispatch force-feedback effects to the wheel device.
##
## Called once per physics tick at the end of [code]_physics_process[/code],
## after the wheels have updated their forces. The four signals you typically
## sum into a single FFB constant-force torque are:
##
##   1. Self-aligning torque ← front wheels' lateral force,
##                             [code]$fl/$fr.directional_force.x[/code], scaled
##                             by Caster. This is the dominant feel.
##   2. Tyre load            ← front wheels' [code].directional_force.y[/code];
##                             multiply SAT by load so unweighted wheels go
##                             light (kerb-hop, jumps).
##   3. Bump / road feel     ← per-wheel suspension compression delta
##                             frame-to-frame (see [Wheel]).
##   4. Curb / surface FX    ← transient buzz on
##                             [GroundSurfaceVariables] type changes.
##
## Reference implementation:
## [codeblock]
## var c := ConfigManager.data.controls
## if not c.ffb_enabled: return
## var sat := 0.0
## for w in [$fl, $fr]:
##     sat += w.directional_force.x * w.Caster
## var torque := sat * c.ffb_self_aligning \
##             + bump_signal * c.ffb_road_feel \
##             + curb_signal * c.ffb_surface_effects
## SDL2FFB.set_constant_force(c.wheel_device_id, torque * c.ffb_strength)
## [/codeblock]
func _apply_force_feedback() -> void:
	pass


# Misc

func bullet_fix():
	# Moves all children so the [code]DRAG_CENTRE[/code] sits at the origin.
	# Disabled by default — was being called from _ready and rearranged the
	# node positions on every spawn.
	var offset = $DRAG_CENTRE.position
	AckermannPoint -= offset.z
	for i in get_children():
		i.position -= offset


func draw_debug():
	# Uses the cached front/rear splits built in _ready instead of re-scanning
	# children every frame.
	front_load = 0.0
	total = 0.0
	for f in _front_wheels_cache:
		front_load += f.directional_force.y
		total += f.directional_force.y
	for r in _rear_wheels_cache:
		front_load -= r.directional_force.y
		total += r.directional_force.y

	if total > 0:
		weight_dist[0] = remap(front_load / total, -1.0, 1.0, 0.0, 1.0)
		weight_dist[1] = 1.0 - weight_dist[0]

	# Keep the public arrays in sync for any external code that reads them.
	front_wheels = _front_wheels_cache
	rear_wheels = _rear_wheels_cache
