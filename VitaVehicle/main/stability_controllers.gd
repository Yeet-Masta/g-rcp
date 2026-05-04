## Stateless stability-system controllers.
##
## Originally these all lived as ~250 lines of methods on [Car]. They take no
## state of their own — the per-frame ABS valve state lives on each [Wheel],
## the TCS flash timer lives on the car. The controllers are pure logic that
## reads/writes that state.
##
## Each entry point matches the original [Car] method name so the dispatch
## from [Car._physics_process] is a one-line call:
##
## [codeblock]
## if abs:  StabilityControllers.apply_abs(self, delta)
## if btcs: StabilityControllers.apply_btcs(self, delta)
## if ttcs: StabilityControllers.apply_ttcs(self, delta)
## if esp:  StabilityControllers.apply_esp(self)
## [/codeblock]

class_name StabilityControllers

## Anti-lock braking entry point. Dispatches to either the legacy global
## pump-duration logic or the advanced per-wheel slip-target controller
## depending on [member ABSProfile.use_advanced_controller].
static func apply_abs(car: Car, delta: float) -> void:
	if car.abs == null:
		return
	if car.abs.use_advanced_controller:
		_abs_advanced(car, delta)
	else:
		_abs_legacy(car)


## Legacy controller — kept for backward compatibility. The wheel's
## physics_process sets [member Car.abs_delay] when slip crosses threshold;
## this function just ramps [member Car.brake_allowed] down while the delay
## is active and back up when it expires.
static func _abs_legacy(car: Car) -> void:
	if car.abs_delay > 0:
		car.brake_allowed -= car.abs.pump_rate
	else:
		car.brake_allowed += car.abs.pump_rate
	car.brake_allowed = clamp(car.brake_allowed, 0.0, 1.0)
	car.abs_delay -= 1


## Advanced controller — per-wheel slip-target ABS modelled on the
## x-engineer.org Xcos reference. For each wheel flagged [member Wheel.ContactABS]:
## [br]   1. Compute longitudinal slip ratio [code]s = 1 − (ω·r)/v[/code].
## [br]   2. Form slip error [code]e = target_slip − s[/code], take its sign.
## [br]   3. Pass through first-order hydraulic lag (time constant T).
## [br]   4. Integrate [code]K · valve_state[/code] into [member Wheel.abs_modulation].
## [br][br]
## [member Car.brake_allowed] stays at 1.0 (per-wheel modulation does the
## actual brake shaping); [member Car.abs_delay] is bumped while any wheel
## cycles, so the dash light still works.
static func _abs_advanced(car: Car, delta: float) -> void:
	# In advanced mode the global modulator is unity — per-wheel modulation
	# does the actual brake-pressure shaping. Stacking both would double-
	# modulate the wheel being released.
	car.brake_allowed = 1.0

	var any_active := false
	var profile: ABSProfile = car.abs

	for child in car.get_children():
		if not (child is Wheel):
			continue
		var wheel: Wheel = child

		# Wheels with ContactABS = false are unprotected. Snap them open.
		if not wheel.ContactABS:
			wheel.abs_modulation = 1.0
			wheel.abs_active = false
			wheel.abs_slip_ratio = 0.0
			continue

		# Need ground contact for slip ratio to mean anything.
		if not wheel.is_colliding():
			_relax_modulation(wheel, profile, delta)
			wheel.abs_active = false
			wheel.abs_slip_ratio = 0.0
			continue

		# Longitudinal velocity at the contact patch (local frame).
		var v_long: float = absf(wheel.velocity2.z)

		# Below cutoff speed or driver isn't braking → no intervention.
		if v_long < profile.min_speed or car.brakepedal < 0.05:
			_relax_modulation(wheel, profile, delta)
			wheel.abs_active = false
			# Still publish slip for telemetry, noisy at low v.
			var w_speed_lo: float = absf(wheel.wv * wheel.w_size)
			wheel.abs_slip_ratio = clampf(1.0 - w_speed_lo / maxf(v_long, 0.001), 0.0, 1.0)
			continue

		# Slip ratio (article eq. 10–11)
		var wheel_speed: float = absf(wheel.wv * wheel.w_size)
		var slip: float = clampf(1.0 - wheel_speed / v_long, 0.0, 1.0)
		wheel.abs_slip_ratio = slip

		#Bang-bang command on the slip error
		# error > 0 → slip below target → open valve, build pressure (+1)
		# error < 0 → slip above target → close valve, release pressure (-1)
		var error: float = profile.target_slip - slip
		var cmd: float = signf(error)

		# Lateral-slip override: tyre saturated, force a release.
		var v_lat: float = absf(wheel.velocity2.x)
		if v_lat > profile.lateral_speed_threshold:
			cmd = -1.0

		#First-order hydraulic lag
		# T · d(valve)/dt + valve = cmd → valve += (cmd - valve) * dt/T
		var alpha: float = clampf(delta / maxf(profile.hydraulic_time_constant, 0.001), 0.0, 1.0)
		wheel.abs_valve_state += (cmd - wheel.abs_valve_state) * alpha

		#Integrate into modulation
		wheel.abs_modulation += wheel.abs_valve_state * profile.controller_gain * delta
		wheel.abs_modulation = clampf(wheel.abs_modulation, 0.0, 1.0)

		# Active = noticeably below 1.0. 0.95 hysteresis avoids flicker.
		if wheel.abs_modulation < 0.95:
			wheel.abs_active = true
			any_active = true
		else:
			wheel.abs_active = false

	#Legacy compatibility shims
	# debug.gd checks abs_delay > 0 for the dash light. Bump it while any
	# wheel is cycling so the indicator stays lit; fade naturally otherwise.
	if any_active:
		car.abs_delay = maxf(car.abs_delay, 1.0)
	car.abs_delay = maxf(car.abs_delay - 1.0, 0.0)


## Relax this wheel's modulation back to fully-open when ABS is not engaged.
static func _relax_modulation(wheel: Wheel, profile: ABSProfile, delta: float) -> void:
	wheel.abs_modulation = move_toward(wheel.abs_modulation, 1.0, profile.release_rate * delta)
	wheel.abs_valve_state = move_toward(wheel.abs_valve_state, 0.0, delta / maxf(profile.hydraulic_time_constant, 0.001))

## For each driven wheel that flags [member Wheel.ContactBTCS], measures
## forward wheel-spin against ground speed and applies a per-wheel brake
## pulse to kill the spin. Acts like a brake-locking diff: braking the
## spinning wheel forces torque across the diff to the gripping one. Only
## meaningful while the engine is putting torque down.
static func apply_btcs(car: Car, delta: float) -> void:
	if car.btcs == null:
		return

	var skip: bool = car.brakepedal > 0.05 \
		or not car.is_in_gear() \
		or car.clutchpedal < 0.1 \
		or car.throttle <= 0.0

	if skip:
		car.tcs_flash_timer = maxf(0.0, car.tcs_flash_timer - delta)
		car.tcsflash = car.tcs_flash_timer > 0.0
		return

	var any_intervention := false
	var threshold: float = car.btcs.slip_threshold
	var sensitivity: float = car.btcs.sensitivity

	for w in car.c_pws:
		if not w.ContactBTCS or not w.is_colliding():
			continue
		var slip_excess: float = absf(w.wv * w.w_size) - absf(w.velocity2.z)
		if slip_excess > threshold:
			var brake_amount: float = clampf((slip_excess - threshold) * sensitivity, 0.0, 1.0)
			w.tc_brake = maxf(w.tc_brake, brake_amount)
			any_intervention = true

	# Persistence: keep the flash on for at least 0.2s.
	if any_intervention:
		car.tcs_flash_timer = 0.2
		car.tcsflash = true
	else:
		car.tcs_flash_timer = maxf(0.0, car.tcs_flash_timer - delta)
		car.tcsflash = car.tcs_flash_timer > 0.0

## Inspects wheels flagged [member Wheel.ContactTTCS] and feeds
## [member Car.tcsweight], which the throttle pipeline already uses to scale
## gas pedal → throttle. Higher tcsweight = more throttle reduction.
static func apply_ttcs(car: Car, delta: float) -> void:
	if car.ttcs == null:
		return
	if not car.is_in_gear() or car.clutchpedal < 0.1:
		# tcsweight is reset each frame by drivetrain(); nothing to do.
		return

	var target_weight := 0.0
	var threshold: float = car.ttcs.slip_threshold
	var sensitivity: float = car.ttcs.sensitivity

	for w in car.c_pws:
		if not w.ContactTTCS or not w.is_colliding():
			continue
		var slip_excess: float = absf(w.wv * w.w_size) - absf(w.velocity2.z)
		if slip_excess > threshold:
			target_weight += (slip_excess - threshold) * sensitivity

	# Smoothing: instant cut to save traction, gradual decay back.
	if target_weight > car.tcsweight:
		car.tcsweight = target_weight
	else:
		car.tcsweight = move_toward(car.tcsweight, target_weight, 5.0 * delta)

	if car.tcsweight > 0.01:
		car.tcs_flash_timer = 0.2
		car.tcsflash = true

## Compares actual yaw rate to driver-requested yaw rate (steering input).
## Brakes a single wheel to rotate the car back onto the requested arc:
## [br]   • Oversteer → brake the OUTER FRONT (scrub off rotation)
## [br]   • Understeer → brake the INNER REAR (pivot the rear)
## [br][br]
## Wheels opt in via [member Wheel.ESP_Role] = "front_left" / "front_right" /
## "rear_left" / "rear_right".
static func apply_esp(car: Car) -> void:
	if car.esp == null:
		return

	# ESP needs forward speed to be meaningful; below walking pace, skip.
	var forward_speed: float = car.velocity.z
	if absf(forward_speed) < 2.0:
		car.espflash = false
		return

	# Yaw rate: car's angular velocity in local space, .y is yaw (rad/s).
	var actual_yaw: float = car.rvelocity.y

	# Driver-requested yaw rate: bicycle-model estimate from steering.
	var desired_yaw := 0.0
	if absf(car.final_steer) > 0.001 and car.Steer_Radius > 0.0:
		var turn_radius: float = car.Steer_Radius / absf(car.final_steer)
		desired_yaw = (forward_speed / turn_radius) * signf(car.final_steer)

	var yaw_error: float = actual_yaw - desired_yaw

	# Sign of steer determines inner/outer; fall back to actual yaw if neutral.
	var steer_sign: float = signf(car.final_steer) if absf(car.final_steer) > 0.001 else signf(actual_yaw)
	if steer_sign == 0.0:
		car.espflash = false
		return

	# yaw_error matching steer_sign → oversteer (overshooting).
	# yaw_error opposing steer_sign → understeer (undershooting).
	var oversteer_amount: float = yaw_error * steer_sign
	var intervened := false

	if oversteer_amount > car.esp.yaw_threshold:
		# OUTER FRONT: opposite-sign side of steer.
		var brake_amount: float = clampf((oversteer_amount - car.esp.yaw_threshold) * car.esp.yaw_correction_rate, 0.0, 1.0)
		_esp_brake_role(car, "front", -steer_sign, brake_amount)
		intervened = true
	elif -oversteer_amount > car.esp.stabilization_threshold:
		# INNER REAR: same-sign side as steer.
		var brake_amount: float = clampf((-oversteer_amount - car.esp.stabilization_threshold) * car.esp.correction_rate, 0.0, 1.0)
		_esp_brake_role(car, "rear", steer_sign, brake_amount)
		intervened = true

	car.espflash = intervened


## Apply [param amount] of tc_brake to the wheel whose [member Wheel.ESP_Role]
## matches [param axle] ("front"/"rear") and whose local-x sign matches
## [param side_sign].
static func _esp_brake_role(car: Car, axle: String, side_sign: float, amount: float) -> void:
	if amount <= 0.0:
		return
	for child in car.get_children():
		if not (child is Wheel):
			continue
		var wheel: Wheel = child
		var role: String = String(wheel.ESP_Role)
		if role.is_empty():
			continue
		# Match by substring so "front_left", "FrontLeft", etc. all work.
		if not role.to_lower().contains(axle):
			continue
		# Side from local x position — avoids trusting "left"/"right" naming.
		if signf(wheel.position.x) != signf(side_sign):
			continue
		wheel.tc_brake = maxf(wheel.tc_brake, amount)
