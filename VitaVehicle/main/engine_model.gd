## Shared engine torque-curve math.
##
## Lives in a single place so the runtime simulation in [Car.simulate_engine]
## and the dyno graph in [code]draw.gd[/code] can never drift out of sync with
## each other. Both build the same [CurveParams] and feed it to
## [method torque_dyno] / [method torque_runtime].
##
## Pure static math — no nodes, no state. Inputs are explicit parameters so
## a caller can supply either a runtime [Car]'s @exports or a graph script's
## copies of them.
##
## All RPM values are in absolute (non-signed) RPM. Boost is in PSI.

class_name EngineModel

## A bag of all parameters that define a torque curve. Keeping them in one
## struct makes the call sites readable (`EngineModel.torque(p)`) instead of
## a 30-argument function call.
class CurveParams:
	extends RefCounted

	# Normal-state curve
	var build_up_torque := 0.0
	var torque_rise := 0.0
	var rise_rpm := 0.0
	var offset_torque := 0.0
	var float_rate := 0.0
	var decline_rate := 0.0
	var decline_rpm := 0.0
	var decline_sharpness := 1.0

	# VVT-state curve
	var vvt_rpm := INF  # set above the rev range to disable VVT
	var vvt_build_up_torque := 0.0
	var vvt_torque_rise := 0.0
	var vvt_rise_rpm := 0.0
	var vvt_offset_torque := 0.0
	var vvt_float_rate := 0.0
	var vvt_decline_rate := 0.0
	var vvt_decline_rpm := 0.0
	var vvt_decline_sharpness := 1.0

	# Engine internals
	var engine_friction := 18000.0
	var engine_drag := 0.006
	var engine_compression_ratio := 8.0

	# Boost
	var psi := 0.0
	var max_psi := 0.0
	var turbo_amount := 1.0
	var turbo_enabled := false
	var supercharger_enabled := false
	var sc_rpm_influence := 1.0
	var blow_rate := 35.0
	var sc_threshold := 6.0


## Convenience: build a CurveParams from a Car instance. Reads only @export
## properties so it's safe to call from anywhere.
##
## Allocates a new [CurveParams]. The runtime path lives in
## [Car._physics_process] and would allocate once per car per physics tick,
## so use [method params_from_car_into] there with a pre-allocated instance.
static func params_from_car(car: Car) -> CurveParams:
	var p := CurveParams.new()
	params_from_car_into(car, p)
	return p


## Fill an existing [CurveParams] from a [Car]'s @exports. Lets the runtime
## path keep one reusable struct on the car and pay zero allocations per
## physics tick.
static func params_from_car_into(car: Car, p: CurveParams) -> void:
	p.build_up_torque        = car.BuildUpTorque
	p.torque_rise            = car.TorqueRise
	p.rise_rpm               = car.RiseRPM
	p.offset_torque          = car.OffsetTorque
	p.float_rate             = car.FloatRate
	p.decline_rate           = car.DeclineRate
	p.decline_rpm            = car.DeclineRPM
	p.decline_sharpness      = car.DeclineSharpness
	p.vvt_rpm                = car.VVTRPM
	p.vvt_build_up_torque    = car.VVT_BuildUpTorque
	p.vvt_torque_rise        = car.VVT_TorqueRise
	p.vvt_rise_rpm           = car.VVT_RiseRPM
	p.vvt_offset_torque      = car.VVT_OffsetTorque
	p.vvt_float_rate         = car.VVT_FloatRate
	p.vvt_decline_rate       = car.VVT_DeclineRate
	p.vvt_decline_rpm        = car.VVT_DeclineRPM
	p.vvt_decline_sharpness  = car.VVT_DeclineSharpness
	p.engine_friction        = car.EngineFriction
	p.engine_drag            = car.EngineDrag
	p.engine_compression_ratio = car.EngineCompressionRatio
	p.psi                    = car.turbopsi
	p.max_psi                = car.MaxPSI
	p.turbo_amount           = car.TurboAmount
	p.turbo_enabled          = car.TurboEnabled
	p.supercharger_enabled   = car.SuperchargerEnabled
	p.sc_rpm_influence       = car.SCRPMInfluence
	p.blow_rate              = car.BlowRate
	p.sc_threshold           = car.SCThreshold

## Torque produced by the engine at [param rpm] under the given curve.
## Computes its own boost from the parameters (used by the dyno where boost
## isn't being simulated). For the runtime path, prefer [method torque_runtime]
## which takes pre-computed boost and a throttle multiplier.
static func torque_dyno(p: CurveParams, rpm: float) -> float:
	var psi: float = p.psi
	if p.supercharger_enabled:
		var maxpsi: float = psi
		var scrpm: float = rpm * p.sc_rpm_influence
		psi = (scrpm / 10000.0) * p.blow_rate - p.sc_threshold
		psi = clampf(psi, 0.0, maxpsi)
	if not p.supercharger_enabled and not p.turbo_enabled:
		psi = 0.0

	var boost_term: float = (psi * p.turbo_amount) * (p.engine_compression_ratio * 0.609)
	var value := _curve_torque(p, rpm, boost_term, 1.0)

	# Dyno: subtract internal losses so the graph reads net torque.
	value -= rpm / (absf(rpm * rpm) / p.engine_friction + 1.0)
	value -= rpm * p.engine_drag
	return value

## Combustion torque the engine is currently producing, given the already-
## simulated [param turbopsi] and the [param throttle] position. Engine
## friction and drag are NOT subtracted here — the runtime path handles those
## separately because it also needs them for the rpmforce term.
static func torque_runtime(p: CurveParams, rpm: float, turbopsi: float, throttle: float) -> float:
	var boost_term: float = (turbopsi * p.turbo_amount) * (p.engine_compression_ratio * 0.609)
	return _curve_torque(p, rpm, boost_term, throttle)

## Evaluate the rise/decline/float curve at [param rpm]. [param boost_term]
## is the additive boost contribution (already multiplied by compression and
## turbo amount). [param throttle_mult] scales the rpm-dependent body; the
## dyno passes 1.0, the runtime passes the actual throttle position.
static func _curve_torque(p: CurveParams, rpm: float, boost_term: float, throttle_mult: float) -> float:
	var value := 0.0
	if rpm > p.vvt_rpm:
		var f := maxf(rpm - p.vvt_rise_rpm, 0.0)
		value = (rpm * p.vvt_build_up_torque + p.vvt_offset_torque + f * f * (p.vvt_torque_rise * Constants.RISE_FACTOR)) * throttle_mult
		value += boost_term
		var j := maxf(rpm - p.vvt_decline_rpm, 0.0)
		value /= (j * (j * p.vvt_decline_sharpness + (1.0 - p.vvt_decline_sharpness))) * (p.vvt_decline_rate * Constants.RISE_FACTOR) + 1.0
		value /= (rpm * rpm) * (p.vvt_float_rate * Constants.RISE_FACTOR) + 1.0
	else:
		var f := maxf(rpm - p.rise_rpm, 0.0)
		value = (rpm * p.build_up_torque + p.offset_torque + f * f * (p.torque_rise * Constants.RISE_FACTOR)) * throttle_mult
		value += boost_term
		var j := maxf(rpm - p.decline_rpm, 0.0)
		value /= (j * (j * p.decline_sharpness + (1.0 - p.decline_sharpness))) * (p.decline_rate * Constants.RISE_FACTOR) + 1.0
		value /= (rpm * rpm) * (p.float_rate * Constants.RISE_FACTOR) + 1.0
	return value
