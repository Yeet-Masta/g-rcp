extends Node

## Force-feedback orchestrator. Single global owner of the [code]FFBPlugin[/code]
## GDExtension.
##
## Register this script as an Autoload (Project Settings → Autoload) with the
## name [b]FFBManager[/b] (the lookup in car.gd is [code]/root/FFBManager[/code],
## so the name must match exactly).
##
## On boot it tries to bind the first haptic-capable SDL device, re-polls every
## couple of seconds while none is plugged in (hot-plug support), and owns:
##   - one long-running constant-force effect that
##     [code]Car._apply_force_feedback()[/code] drives every physics tick —
##     this is the dominant steering feel;
##   - one periodic sine effect that [code]Car[/code] can pulse for curb /
##     bump hits on top of the constant force.
##
## NOTE on method names: the GDScript-callable names come from the plugin's
## [code]_bind_methods()[/code], NOT from the C++ header. The constant-force
## calls are bound as [code]update_constant_force_effect[/code] /
## [code]play_constant_force_effect[/code] even though the header declares them
## as [code]..._ffb_effect[/code]. The names used here match a known-good test
## script — change them only if you also change the binding.
##
## Every method is safe to call when no device is connected — it just no-ops,
## so car.gd doesn't have to special-case the keyboard-only path.

## Length (ms) we pass when refreshing the constant force. We re-issue the
## effect every physics tick, so this only needs to outlast a frame or two of
## stutter. Keeping it short means the wheel relaxes quickly if updates stop
## (game paused, FFB disabled) instead of holding a stale force.
const CONSTANT_FORCE_LENGTH_MS := 100

## How often we retry device discovery while disconnected (seconds).
const RECONNECT_INTERVAL := 2.0

var plugin: FFBPlugin = null
var connected_device_index := -1
var device_name := ""
var constant_effect_id := -1
var bump_effect_id := -1

var _last_torque := 0.0
var _reconnect_timer := 0.0


func _ready() -> void:
	# Created directly, exactly like the known-good test script.
	plugin = FFBPlugin.new()
	add_child(plugin)
	_try_open_first_haptic()


func _process(delta: float) -> void:
	# Hot-plug: poll every couple of seconds while we have no device.
	if plugin == null or is_open():
		return
	_reconnect_timer += delta
	if _reconnect_timer >= RECONNECT_INTERVAL:
		_reconnect_timer = 0.0
		_try_open_first_haptic()


## True once a device is bound and the constant-force effect has been created.
func is_open() -> bool:
	return plugin != null and connected_device_index >= 0 and constant_effect_id >= 0


## Set the main steering torque. [param torque] is normalised: -1 = full left,
## +1 = full right. The value is clamped, then exponentially smoothed so that
## frame-to-frame jitter from the simulation doesn't make the wheel chatter.
## [param smoothing] is the fraction of the new sample taken per call
## (0 = freeze, 1 = no smoothing).
##
## We update AND (re)play every call — this is the pattern the working test
## script uses. A constant force has no waveform, so replaying it each frame
## produces no click; it just refreshes the effect's life timer.
func apply_steering_torque(torque: float, smoothing: float = 0.4) -> void:
	if not is_open():
		return
	var target := clampf(torque, -1.0, 1.0)
	_last_torque = lerpf(_last_torque, target, clampf(smoothing, 0.0, 1.0))
	plugin.update_constant_force_effect(_last_torque, CONSTANT_FORCE_LENGTH_MS, constant_effect_id)
	plugin.play_constant_force_effect(constant_effect_id, 1)


## Fire a short bump pulse layered on top of the constant force. Use for
## curb hits, jump landings, gear-shift jolts. [param magnitude] is 0..1.
func pulse_bump(magnitude: float, length_ms: int = 100, period_ms: int = 60) -> void:
	if not is_open() or bump_effect_id < 0:
		return
	var m := clampf(absf(magnitude), 0.0, 1.0)
	if m < 0.08:
		return  # below noise floor — would feel like a permanent buzz
	# update_periodic_effect lets us scale the pulse to impact severity. If the
	# binding isn't present under this name, we still fire the pre-baked sine.
	if plugin.has_method("update_periodic_effect"):
		plugin.update_periodic_effect(bump_effect_id, FFBPlugin.WAVE_SINE, period_ms, m, length_ms)
	plugin.run_effect(bump_effect_id, 1)


## Master device gain (0..100). Applies to every effect on the device.
func set_global_gain(gain_0_to_100: int) -> void:
	if plugin == null or connected_device_index < 0:
		return
	plugin.set_gain(clampi(gain_0_to_100, 0, 100))


## Hardware autocenter spring (0..100). Left at 0 by default — sim drivers
## want the game's computed SAT to be the centering force, not a stock spring.
func set_hardware_autocenter(strength_0_to_100: int) -> void:
	if plugin == null or connected_device_index < 0:
		return
	plugin.set_autocenter(clampi(strength_0_to_100, 0, 100))


## Tears down effects and closes the device. Called automatically on quit.
func shutdown() -> void:
	if plugin == null:
		return
	plugin.stop_all_effects()
	if constant_effect_id >= 0:
		plugin.destroy_ffb_effect(constant_effect_id)
		constant_effect_id = -1
	if bump_effect_id >= 0:
		plugin.destroy_ffb_effect(bump_effect_id)
		bump_effect_id = -1
	if connected_device_index >= 0:
		plugin.close_ffb_device()
		connected_device_index = -1
		device_name = ""
	_last_torque = 0.0


func _exit_tree() -> void:
	shutdown()


# Internal

## Enumerate joysticks, pick the first haptic-capable one, and initialise our
## effects on it. Prints the full list so a failed bind is easy to diagnose
## from the console. Returns the opened index, or -1 if nothing was found.
func _try_open_first_haptic() -> int:
	if plugin == null:
		return -1
	var names: PackedStringArray = plugin.get_joystick_names()
	if names.is_empty():
		return -1  # no joysticks at all — stay quiet, _process will retry

	for i in names.size():
		var tag := " [FFB]" if plugin.is_joystick_haptic(i) else ""
		print("FFBManager: joystick %d: %s%s" % [i, names[i], tag])

	for i in names.size():
		if not plugin.is_joystick_haptic(i):
			continue
		if plugin.init_ffb(i) != 0:
			push_warning("FFBManager: init_ffb(%d) failed for \"%s\"." % [i, names[i]])
			continue
		connected_device_index = i
		device_name = names[i]
		# Put the device in a known state: full gain (the game's ffb_strength
		# does the attenuating) and no stock autocenter spring.
		plugin.set_gain(100)
		plugin.set_autocenter(0)
		_init_effects()
		if is_open():
			print("FFBManager: opened \"%s\" — %d effect slots." % [device_name, plugin.get_max_effects()])
			return i
		# Haptic init succeeded but effect creation didn't; close and keep looking.
		plugin.close_ffb_device()
		connected_device_index = -1
		device_name = ""
	push_warning("FFBManager: no usable force-feedback device found.")
	return -1


func _init_effects() -> void:
	# Constant force is the dominant signal; without it there's nothing to drive.
	if not plugin.has_constant_force():
		push_warning("FFBManager: \"%s\" has haptics but no constant-force support." % device_name)
		return
	constant_effect_id = plugin.init_constant_force_effect()
	if constant_effect_id < 0:
		push_warning("FFBManager: failed to create the constant-force effect.")
		return

	# Optional periodic sine for bump pulses. Baked magnitude (0.6) is used as
	# the fallback when update_periodic_effect isn't available.
	if plugin.supports_effect_type(FFBPlugin.WAVE_SINE):
		bump_effect_id = plugin.init_periodic_effect(FFBPlugin.WAVE_SINE, 60, 0.6, 100)
