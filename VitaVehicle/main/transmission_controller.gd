## Stateless gearbox controllers.
##
## Each [code]tick(car)[/code] mutates the car's transmission-related state
## (gear/actualgear/clutchpedal/ratio/shift_assist_delay/sassiststep/...) the
## same way the original [code]Car.simulate_*[/code] methods did. The car is
## the source of truth for state; the controllers are pure logic.
##
## Dispatch lives in [method TransmissionController.tick] — it picks one of
## the four implementations based on [member Car.transmission_type].
##
## NOTE on parity: every line here was lifted out of the original
## [code]car.gd[/code] without rewording the math. If you need to tune
## behavior, change it here once instead of finding it inside a 1400-line
## file.

class_name TransmissionController



## Top-level dispatcher. Called from [code]Car.transmission()[/code].
static func tick(car: Car) -> void:
	match car.transmission_type:
		Car.TransmissionType.FULLY_MANUAL:
			ManualGearbox.tick(car)
		Car.TransmissionType.AUTOMATIC:
			AutomaticGearbox.tick(car)
		Car.TransmissionType.CONTINUOUSLY_VARIABLE:
			CVTGearbox.tick(car)
		Car.TransmissionType.SEMI_AUTO:
			SemiAutoGearbox.tick(car)

class ManualGearbox:
	extends RefCounted

	static func tick(car: Car) -> void:
		var controls := ConfigManager.data.controls

		if car.clutch and not car.clutchin:
			car.clutchpedalreal -= controls.off_clutch_rate / car.clock_mult
		else:
			car.clutchpedalreal += controls.on_clutch_rate / car.clock_mult

		car.clutchpedal = 1.0 - car.clutchpedalreal

		if car.gear > 0:
			car.ratio = car.GearRatios[car.gear - 1] * car.final_drive * car.ratio_multi
		elif car.gear == -1:
			car.ratio = car.reverse_ratio * car.final_drive * car.ratio_multi

		match controls.shift_assist_level:
			ControlsConfig.ShiftAssistLevel.NONE:
				_assist_none(car)
			ControlsConfig.ShiftAssistLevel.WEAK:
				_assist_weak(car)
			ControlsConfig.ShiftAssistLevel.FULL:
				_assist_full(car)

		_advance_assist_state(car)
		car.gear = car.actualgear


	static func _assist_none(car: Car) -> void:
		if car.input_upshift:
			car.input_upshift = false
			if car.gear < len(car.GearRatios) and car.gearstress < car.GearGap:
				car.actualgear += 1
		if car.input_downshift:
			car.input_downshift = false
			if car.gear > -1 and car.gearstress < car.GearGap:
				car.actualgear -= 1


	static func _assist_weak(car: Car) -> void:
		if car.rpm < car.shift_assist.clutch_out_rpm:
			var irga_ca := (car.shift_assist.clutch_out_rpm - car.rpm) / (car.shift_assist.clutch_out_rpm - car.IdleRPM)
			car.clutchpedalreal = pow(irga_ca, 2)
		elif not car.gasrestricted and not car.revmatch:
			car.clutchin = false

		if car.input_upshift:
			car.input_upshift = false
			if car.gear < len(car.GearRatios):
				if car.rpm < car.shift_assist.clutch_out_rpm:
					car.actualgear += 1
				elif car.actualgear < 1:
					car.actualgear += 1
					if car.rpm > car.shift_assist.clutch_out_rpm:
						car.clutchin = false
				else:
					if car.shift_assist_delay > 0:
						car.actualgear += 1
					car.shift_assist_delay = int(car.shift_assist.shift_delay / 2.0)
					car.sassiststep = -4
					car.clutchin = true
					car.gasrestricted = true
		elif car.input_downshift:
			car.input_downshift = false
			if car.gear > -1:
				if car.rpm < car.shift_assist.clutch_out_rpm:
					car.actualgear -= 1
				elif car.actualgear == 0 or car.actualgear == 1:
					car.actualgear -= 1
					car.clutchin = false
				else:
					if car.shift_assist_delay > 0:
						car.actualgear -= 1
					car.shift_assist_delay = int(car.shift_assist.shift_delay / 2.0)
					car.sassiststep = -2
					car.clutchin = true
					car.revmatch = true
					car.gasrestricted = false


	static func _assist_full(car: Car) -> void:
		var assistshiftspeed: float = (car.shift_assist.upshift_rpm / car.ratio) * car.drivewheels_size
		var prev_ratio: float = (car.GearRatios[car.gear - 2] * car.final_drive) * car.ratio_multi
		var assistdownshiftspeed: float = (car.shift_assist.downshift_rpm / absf(prev_ratio)) * car.drivewheels_size

		if car.gear == 0:
			if car.gas:
				car.shift_assist_delay -= 1
				if car.shift_assist_delay < 0:
					car.actualgear = 1
			elif car.brake:
				car.shift_assist_delay -= 1
				if car.shift_assist_delay < 0:
					car.actualgear = -1
			else:
				car.shift_assist_delay = 60
		elif car.linear_velocity.length() < 5:
			if (not car.gas and car.gear == 1) or (not car.brake and car.gear == -1):
				car.shift_assist_delay = 60
				car.actualgear = 0

		if car.sassiststep == 0:
			if car.rpm < car.shift_assist.clutch_out_rpm:
				var irga_ca := (car.shift_assist.clutch_out_rpm - car.rpm) / (car.shift_assist.clutch_out_rpm - car.IdleRPM)
				car.clutchpedalreal = pow(irga_ca, 2)
			else:
				car.clutchin = false
			if car.gear != -1:
				if car.gear < len(car.GearRatios) and car.linear_velocity.length() > assistshiftspeed:
					car.shift_assist_delay = int(car.shift_assist.shift_delay / 2.0)
					car.sassiststep = -4
					car.clutchin = true
					car.gasrestricted = true
				if car.gear > 1 and car.linear_velocity.length() < assistdownshiftspeed:
					car.shift_assist_delay = int(car.shift_assist.shift_delay / 2.0)
					car.sassiststep = -2
					car.clutchin = true
					car.gasrestricted = false
					car.revmatch = true


	## Pumps through the multi-step shift state machine: -4 → -3 → 0 (upshift),
	## or -2 → 0 (downshift). Mirrors the original tail-end of simulate_manual.
	static func _advance_assist_state(car: Car) -> void:
		if car.sassiststep == -4 and car.shift_assist_delay < 0:
			car.shift_assist_delay = int(car.shift_assist.shift_delay / 2.0)
			if car.gear < len(car.GearRatios):
				car.actualgear += 1
			car.sassiststep = -3
		elif car.sassiststep == -3 and car.shift_assist_delay < 0:
			if car.rpm > car.shift_assist.clutch_out_rpm:
				car.clutchin = false
			if car.shift_assist_delay < -car.shift_assist.post_shift_delay:
				car.sassiststep = 0
				car.gasrestricted = false
		elif car.sassiststep == -2 and car.shift_assist_delay < 0:
			car.sassiststep = 0
			if car.gear > -1:
				car.actualgear -= 1
			if car.rpm > car.shift_assist.clutch_out_rpm:
				car.clutchin = false
			car.gasrestricted = false
			car.revmatch = false

class AutomaticGearbox:
	extends RefCounted

	static func tick(car: Car) -> void:
		var ag: AutoGearboxProfile = car.auto_gearbox
		car.clutchpedal = (car.rpm - ag.engagement_min_rpm * (car.gaspedal * ag.throttle_threshold + (1.0 - ag.throttle_threshold))) / ag.engagement_max_rpm

		var assist_level: int = ConfigManager.data.controls.shift_assist_level
		if assist_level != ControlsConfig.ShiftAssistLevel.FULL:
			if car.input_upshift:
				car.input_upshift = false
				if car.gear < 1:
					car.actualgear += 1
			if car.input_downshift:
				car.input_downshift = false
				if car.gear > -1:
					car.actualgear -= 1
		else:
			_full_assist_idle_logic(car)

		if car.actualgear == -1:
			car.ratio = car.reverse_ratio * car.final_drive * car.ratio_multi
		else:
			car.ratio = car.GearRatios[car.gear - 1] * car.final_drive * car.ratio_multi

		if car.actualgear > 0:
			_drive_shift_decision(car)
		else:
			car.gear = car.actualgear


	## Auto-shift into D/R from neutral and back to N at low speed (full assist).
	static func _full_assist_idle_logic(car: Car) -> void:
		if car.gear == 0:
			if car.gas:
				car.shift_assist_delay -= 1
				if car.shift_assist_delay < 0:
					car.actualgear = 1
			elif car.brake:
				car.shift_assist_delay -= 1
				if car.shift_assist_delay < 0:
					car.actualgear = -1
			else:
				car.shift_assist_delay = 60
		elif car.linear_velocity.length() < 5:
			if (not car.gas and car.gear == 1) or (not car.brake and car.gear == -1):
				car.shift_assist_delay = 60
				car.actualgear = 0


	## Decide up/down shift while in a forward gear by checking each driven
	## wheel's velocity against an RPM-derived threshold.
	static func _drive_shift_decision(car: Car) -> void:
		var ag: AutoGearboxProfile = car.auto_gearbox
		var lastratio: float = car.GearRatios[car.gear - 2] * car.final_drive * car.ratio_multi
		car.input_upshift = false
		car.input_downshift = false
		var throttle_factor: float = car.gaspedal * ag.throttle_threshold + (1.0 - ag.throttle_threshold)
		for w in car.c_pws:
			var wheel_rate: float = w.wv / car.drivewheels_size
			if wheel_rate > (ag.upshift_rpm * throttle_factor) / car.ratio:
				car.input_upshift = true
			elif wheel_rate < ((ag.upshift_rpm - ag.downshift_threshold) * throttle_factor) / lastratio:
				car.input_downshift = true
		if car.input_upshift:
			car.gear += 1
		elif car.input_downshift:
			car.gear -= 1
		car.gear = clamp(car.gear, 1, len(car.GearRatios))

class CVTGearbox:
	extends RefCounted

	static func tick(car: Car) -> void:
		var ag: AutoGearboxProfile = car.auto_gearbox
		car.clutchpedal = (car.rpm - ag.engagement_min_rpm * (car.gaspedal * ag.throttle_threshold + (1.0 - ag.throttle_threshold))) / ag.engagement_max_rpm

		var assist_level: int = ConfigManager.data.controls.shift_assist_level
		if assist_level != ControlsConfig.ShiftAssistLevel.FULL:
			if car.input_upshift:
				car.input_upshift = false
				if car.gear < 1:
					car.actualgear += 1
			if car.input_downshift:
				car.input_downshift = false
				if car.gear > -1:
					car.actualgear -= 1
		else:
			AutomaticGearbox._full_assist_idle_logic(car)

		car.gear = car.actualgear

		var avg_wv := 0.0
		var n: int = len(car.c_pws)
		if n > 0:
			for w in car.c_pws:
				avg_wv += w.wv / n

		var cvt: CVTProfile = car.cvt
		car.cvtaccel -= (car.cvtaccel - (car.gaspedal * cvt.efficiency_range + (1.0 - cvt.efficiency_range))) * cvt.ratio_step_rate

		var a: float = cvt.lock_timing / ((absf(avg_wv) / 10.0) * car.cvtaccel + 1.0)
		a = max(a, cvt.stability_damping)

		car.ratio = (cvt.rpm_offset * 10000000.0) / (absf(avg_wv) * (car.rpm * a) + 1.0)
		car.ratio = min(car.ratio, cvt.standstill_torque)

class SemiAutoGearbox:
	extends RefCounted

	static func tick(car: Car) -> void:
		var ag: AutoGearboxProfile = car.auto_gearbox
		car.clutchpedal = (car.rpm - ag.engagement_min_rpm * (car.gaspedal * ag.throttle_threshold + (1.0 - ag.throttle_threshold))) / ag.engagement_max_rpm

		if car.gear > 0:
			car.ratio = car.GearRatios[car.gear - 1] * car.final_drive * car.ratio_multi
		elif car.gear == -1:
			car.ratio = car.reverse_ratio * car.final_drive * car.ratio_multi

		var assist_level: int = ConfigManager.data.controls.shift_assist_level
		if assist_level < ControlsConfig.ShiftAssistLevel.FULL:
			if car.input_upshift:
				car.input_upshift = false
				if car.gear < len(car.GearRatios):
					car.actualgear += 1
			if car.input_downshift:
				car.input_downshift = false
				if car.gear > -1:
					car.actualgear -= 1
		else:
			_full_assist(car)

		car.gear = car.actualgear


	static func _full_assist(car: Car) -> void:
		var assistshiftspeed: float = (car.shift_assist.upshift_rpm / car.ratio) * car.drivewheels_size
		var prev_ratio: float = (car.GearRatios[car.gear - 2] * car.final_drive) * car.ratio_multi
		var assistdownshiftspeed: float = (car.shift_assist.downshift_rpm / absf(prev_ratio)) * car.drivewheels_size

		if car.gear == 0:
			if car.gas:
				car.shift_assist_delay -= 1
				if car.shift_assist_delay < 0:
					car.actualgear = 1
			elif car.brake:
				car.shift_assist_delay -= 1
				if car.shift_assist_delay < 0:
					car.actualgear = -1
			else:
				car.shift_assist_delay = 60
		elif car.linear_velocity.length() < 5:
			if (not car.gas and car.gear == 1) or (not car.brake and car.gear == -1):
				car.shift_assist_delay = 60
				car.actualgear = 0

		if car.sassiststep == 0 and car.gear != -1:
			if car.gear < len(car.GearRatios) and car.linear_velocity.length() > assistshiftspeed:
				car.actualgear += 1
			if car.gear > 1 and car.linear_velocity.length() < assistdownshiftspeed:
				car.actualgear -= 1
