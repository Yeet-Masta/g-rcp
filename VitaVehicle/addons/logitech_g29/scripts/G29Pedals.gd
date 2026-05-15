## A custom node for handling pedal input from a Fanatec CSL Elite Pedals set
## (also works with CSL Elite Pedals V2 / LC and CSL Pedals).
##
## [FanatecPedals] processes raw joypad axis values from the throttle, brake,
## and clutch pedals and converts them into normalized, easy-to-use values
## (0.0 to 1.0). It also features a built-in mapping system allowing players
## to rebind their pedals at runtime.
## [br][br]
## When connected to a CSL Elite Wheel Base via RJ12, the pedals share the
## same joypad device as the wheel — there is only one device ID to worry
## about. When using the pedals as a standalone USB device (CSL Elite Pedals
## V2 supports this directly; older CSL Elite require the ClubSport USB
## Adapter), they appear as their own joypad and you can target them
## explicitly via [member device_id].
## [br][br]
## [b]Important note on default axes:[/b] The exact axis IDs Godot reports
## for Fanatec pedals depends on driver version, firmware, and how they're
## connected. The defaults below match the most common Windows / SDL2
## arrangement when the pedals are connected through a CSL Elite Wheel Base.
## If they look wrong, enable [member debug_print] and use
## [method start_mapping_pedal] to rebind at runtime, or just adjust the
## axis values in the inspector.
## [br][br]
## [b]Example Usage:[/b]
## [codeblock]
## func _ready():
##     $FanatecPedals.throttle_changed.connect(_on_throttle_pressed)
##
## func _on_throttle_pressed(value: float):
##     # value is 0.0 (resting) to 1.0 (floored)
##     car_acceleration = max_acceleration * value
## [/codeblock]
@icon("res://addons/logitech_g29/icons/G29 Pedal.svg")
class_name FanatecPedals
extends Node

# --- NORMALIZED SIGNALS (0.0 to 1.0) ---

## Emitted when the throttle pedal is pressed or released.
## The [param value] ranges from [code]0.0[/code] (unpressed) to [code]1.0[/code] (fully pressed).
signal throttle_changed(value: float)

## Emitted when the brake pedal is pressed or released.
## The [param value] ranges from [code]0.0[/code] (unpressed) to [code]1.0[/code] (fully pressed).
## Note: The CSL Elite V2 brake is a load cell, so this value reflects pressure rather than travel.
signal brake_changed(value: float)

## Emitted when the clutch pedal is pressed or released.
## The [param value] ranges from [code]0.0[/code] (unpressed) to [code]1.0[/code] (fully pressed).
signal clutch_changed(value: float)

# --- RAW SIGNALS (-1.0 to 1.0) ---

## Emitted when the raw throttle axis changes. The [param value] typically ranges from [code]-1.0[/code] to [code]1.0[/code].
signal throttle_raw_changed(value: float)

## Emitted when the raw brake axis changes. The [param value] typically ranges from [code]-1.0[/code] to [code]1.0[/code].
signal brake_raw_changed(value: float)

## Emitted when the raw clutch axis changes. The [param value] typically ranges from [code]-1.0[/code] to [code]1.0[/code].
signal clutch_raw_changed(value: float)

# --- MAPPING SIGNALS ---

## Emitted after [method start_mapping_pedal] successfully detects a physical pedal press and binds it.
## [param pedal_name] will be the string passed to the mapping function, and [param axis_index] is the newly assigned joypad axis.
signal mapping_complete(pedal_name: String, axis_index: int)


@export_group("Device Settings")

## If [code]true[/code], the node will prioritize connecting to a joypad whose
## name contains "Fanatec", "CSL", or "ClubSport".
@export var prefer_fanatec: bool = true

## The internal joypad ID assigned by Godot. Read-only during gameplay.
## When pedals are connected through a Fanatec wheel base, this will be the
## same as the wheel's device_id.
@export var device_id: int = -1


@export_group("Hardware Axes Mapping")

## The joypad axis mapped to the throttle. Can be reassigned at runtime using
## [method start_mapping_pedal]. Default ([constant JOY_AXIS_TRIGGER_RIGHT],
## axis 5) matches the most common Windows mapping for the CSL Elite Pedals
## connected via the wheel base.
@export var throttle_axis: JoyAxis = JOY_AXIS_LEFT_Y

## The joypad axis mapped to the brake. Default ([constant JOY_AXIS_TRIGGER_LEFT],
## axis 4) matches the most common Windows mapping. The CSL Elite V2 load cell
## still reports its pressure value through this same axis.
@export var brake_axis: JoyAxis = JOY_AXIS_TRIGGER_LEFT

## The joypad axis mapped to the clutch. Default ([constant JOY_AXIS_RIGHT_Y],
## axis 3) matches the most common Windows mapping for the CSL Elite Pedals.
@export var clutch_axis: JoyAxis = JOY_AXIS_RIGHT_Y


@export_group("Pedal Inversion")

## Reverses the normalized output for the throttle. Fanatec pedals connected
## through the wheel base typically report the resting state as -1.0 and full
## press as +1.0, so the standard normalization gives the correct 0..1 result
## without inverting. Toggle if your throttle reads backwards.
@export var invert_throttle: bool = true

## Reverses the normalized output for the brake. The CSL Elite V2 load cell
## also typically reads -1.0 at rest and +1.0 at maximum pressure.
@export var invert_brake: bool = true

## Reverses the normalized output for the clutch.
@export var invert_clutch: bool = true


@export_group("Debug")

## If [code]true[/code], prints normalized pedal outputs and mapping success alerts to the console.
@export var debug_print: bool = true

## The minimum change required (on a 0.0 to 1.0 scale) before a new debug
## message is printed. Set to [code]0.01[/code] to see 1% micro-movements,
## or [code]0.1[/code] for 10% steps to reduce console spam.
@export var debug_pedal_threshold: float = 0.01

# Internal State Tracking
var _last_throttle: float = 0.0
var _last_brake: float = 0.0
var _last_clutch: float = 0.0

var _last_raw_throttle: float = 0.0
var _last_raw_brake: float = 0.0
var _last_raw_clutch: float = 0.0

# Used to prevent debug console spam based on the threshold
var _last_printed_throttle: float = 0.0
var _last_printed_brake: float = 0.0
var _last_printed_clutch: float = 0.0

# Mapping State
var _is_mapping: bool = false
var _pedal_being_mapped: String = ""

func _ready() -> void:
	if device_id == -1: device_id = _pick_device()
	if device_id == -1:
		# Don't fully stop processing — listen for hot-plug so the pedals
		# can come online if the user connects them after the scene loads.
		set_process(false)
	elif debug_print:
		print("FanatecPedals: Connected to device ", device_id, " (", Input.get_joy_name(device_id), ")")

	# Watch for connect / disconnect so the getters return 0.0 the moment a
	# pedal device is unplugged (otherwise device_id would stay valid, Input
	# would return 0.0 on every axis, and the invert flags would normalize
	# that to 0.5 → stuck-at-half-pressed throttle / brake / clutch).
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected and device_id == -1:
		# Re-acquire on hot-plug. If the new device matches our prefer_fanatec
		# filter (or we don't care), start processing again.
		device_id = _pick_device()
		if device_id != -1:
			set_process(true)
			if debug_print:
				print("FanatecPedals: Reconnected to device ", device_id, " (", Input.get_joy_name(device_id), ")")
	elif not connected and device == device_id:
		if debug_print:
			print("FanatecPedals: Device ", device_id, " disconnected.")
		device_id = -1
		set_process(false)
		# Flush cached state so the next reconnect emits fresh transitions
		# instead of comparing against stale "last frame" values.
		_last_throttle = 0.0
		_last_brake = 0.0
		_last_clutch = 0.0
		_last_raw_throttle = 0.0
		_last_raw_brake = 0.0
		_last_raw_clutch = 0.0

func _process(_delta: float) -> void:
	# If we are currently mapping a pedal, skip normal driving logic
	if _is_mapping:
		_process_mapping()
		return

	_process_pedals()

func _process_pedals() -> void:
	# THROTTLE
	var raw_throttle: float = Input.get_joy_axis(device_id, throttle_axis)
	if raw_throttle != _last_raw_throttle:
		throttle_raw_changed.emit(raw_throttle)
		_last_raw_throttle = raw_throttle

	var throttle_val: float = _normalize_pedal(raw_throttle, invert_throttle)
	if throttle_val != _last_throttle:
		throttle_changed.emit(throttle_val)
		_last_throttle = throttle_val

		if debug_print and abs(throttle_val - _last_printed_throttle) >= debug_pedal_threshold:
			print("FanatecPedals Debug: throttle_changed (Axis ID: %d) | Norm: %.4f | Raw: %.4f" % [throttle_axis, throttle_val, raw_throttle])
			_last_printed_throttle = throttle_val

	# BRAKE
	var raw_brake: float = Input.get_joy_axis(device_id, brake_axis)
	if raw_brake != _last_raw_brake:
		brake_raw_changed.emit(raw_brake)
		_last_raw_brake = raw_brake

	var brake_val: float = _normalize_pedal(raw_brake, invert_brake)
	if brake_val != _last_brake:
		brake_changed.emit(brake_val)
		_last_brake = brake_val

		if debug_print and abs(brake_val - _last_printed_brake) >= debug_pedal_threshold:
			print("FanatecPedals Debug: brake_changed (Axis ID: %d) | Norm: %.4f | Raw: %.4f" % [brake_axis, brake_val, raw_brake])
			_last_printed_brake = brake_val

	# CLUTCH
	var raw_clutch: float = Input.get_joy_axis(device_id, clutch_axis)
	if raw_clutch != _last_raw_clutch:
		clutch_raw_changed.emit(raw_clutch)
		_last_raw_clutch = raw_clutch

	var clutch_val: float = _normalize_pedal(raw_clutch, invert_clutch)
	if clutch_val != _last_clutch:
		clutch_changed.emit(clutch_val)
		_last_clutch = clutch_val

		if debug_print and abs(clutch_val - _last_printed_clutch) >= debug_pedal_threshold:
			print("FanatecPedals Debug: clutch_changed (Axis ID: %d) | Norm: %.4f | Raw: %.4f" % [clutch_axis, clutch_val, raw_clutch])
			_last_printed_clutch = clutch_val

# --- POLLING GETTERS ---
#
# Prefer these over the signals for per-frame physics code. They read straight
# from Input on demand, so there's no latency between the wheel update and your
# physics tick, no signal plumbing in your game scripts, and they return a
# safe default (0.0) when the device isn't connected.
#
# Typical usage in a car / vehicle script:
#     gas_input    = $FanatecPedals.get_throttle()
#     brake_input  = $FanatecPedals.get_brake()
#     clutch_input = $FanatecPedals.get_clutch()

## Returns [code]true[/code] when a pedal device is currently connected and
## being polled. When this is [code]false[/code], the [code]get_*[/code]
## getters all return [code]0.0[/code].
func is_device_connected() -> bool:
	return device_id != -1

## Returns the throttle pedal position in the range [code]0.0[/code] (resting)
## to [code]1.0[/code] (floored). Honors [member invert_throttle].
func get_throttle() -> float:
	if device_id == -1: return 0.0
	return _normalize_pedal(Input.get_joy_axis(device_id, throttle_axis), invert_throttle)

## Returns the brake pedal position in the range [code]0.0[/code] (resting)
## to [code]1.0[/code] (fully pressed). For the CSL Elite V2 load cell this
## reflects pressure rather than travel. Honors [member invert_brake].
func get_brake() -> float:
	if device_id == -1: return 0.0
	return _normalize_pedal(Input.get_joy_axis(device_id, brake_axis), invert_brake)

## Returns the clutch pedal position in the range [code]0.0[/code] (resting)
## to [code]1.0[/code] (fully pressed). Honors [member invert_clutch].
func get_clutch() -> float:
	if device_id == -1: return 0.0
	return _normalize_pedal(Input.get_joy_axis(device_id, clutch_axis), invert_clutch)

## Returns the raw throttle axis value (typically [code]-1.0[/code] to [code]1.0[/code]).
## Useful for diagnostics; most game code wants [method get_throttle] instead.
func get_throttle_raw() -> float:
	if device_id == -1: return 0.0
	return Input.get_joy_axis(device_id, throttle_axis)

## Returns the raw brake axis value (typically [code]-1.0[/code] to [code]1.0[/code]).
func get_brake_raw() -> float:
	if device_id == -1: return 0.0
	return Input.get_joy_axis(device_id, brake_axis)

## Returns the raw clutch axis value (typically [code]-1.0[/code] to [code]1.0[/code]).
func get_clutch_raw() -> float:
	if device_id == -1: return 0.0
	return Input.get_joy_axis(device_id, clutch_axis)


# --- MANUAL MAPPING FUNCTIONS ---

## Halts standard input processing and waits for the player to press a physical pedal.
## Once an axis change greater than 0.5 is detected, it assigns that axis to the requested pedal
## and resumes normal operation.
## [br][br]
## [b]Tip:[/b] On Fanatec hardware the steering wheel axis is usually axis 0
## ([constant JOY_AXIS_LEFT_X]). When mapping a pedal, make sure your wheel is
## centered so the steering axis doesn't accidentally get picked up.
## [br][br]
## [b]Example Usage:[/b]
## [codeblock]
## # Called when a player clicks a "Remap Throttle" button in the UI
## func _on_remap_throttle_button_pressed():
##     $FanatecPedals.start_mapping_pedal("throttle")
## [/codeblock]
## [br]
## Accepted strings: [code]"throttle"[/code], [code]"brake"[/code], [code]"clutch"[/code].
func start_mapping_pedal(pedal_name: String) -> void:
	if pedal_name not in ["throttle", "brake", "clutch"]:
		push_error("FanatecPedals: Invalid pedal name. Use 'throttle', 'brake', or 'clutch'.")
		return

	_pedal_being_mapped = pedal_name
	_is_mapping = true

	if debug_print:
		print("FanatecPedals Debug: Press the ", pedal_name, " pedal now to map it...")

func _process_mapping() -> void:
	# Rapidly scan all possible joystick axes
	for axis: int in range(JOY_AXIS_MAX):
		var value: float = Input.get_joy_axis(device_id, axis)

		# If an axis is pressed hard enough (ignoring tiny stick drift)
		if abs(value) > 0.5:
			# Skip the steering axis if it's where the user happens to have
			# turned the wheel. The steering axis is normally axis 0.
			if axis == JOY_AXIS_LEFT_X:
				continue

			_assign_axis_to_pedal(_pedal_being_mapped, axis)
			_is_mapping = false
			mapping_complete.emit(_pedal_being_mapped, axis)

			if debug_print:
				print("FanatecPedals Debug: Success! ", _pedal_being_mapped, " mapped to axis ", axis)
			return

func _assign_axis_to_pedal(pedal_name: String, axis: int) -> void:
	if pedal_name == "throttle": throttle_axis = axis
	elif pedal_name == "brake": brake_axis = axis
	elif pedal_name == "clutch": clutch_axis = axis

# --- UTILITIES ---

func _normalize_pedal(raw_value: float, invert: bool) -> float:
	# Fanatec pedals rest at -1.0 (axis fully negative) and report +1.0 when
	# floored. A reading of exactly 0.0 means "the axis isn't reporting" —
	# the wheel base is asleep, the pedal cable is unplugged, or the joypad
	# slot we picked doesn't actually have that pedal on it. The naive
	# normalization (raw + 1) / 2 turns that into 0.5, which after inversion
	# stays 0.5 and reads as a permanently half-pressed pedal. Snap that
	# corner case to resting.
	if is_zero_approx(raw_value):
		return 0.0
	var normalized: float = (raw_value + 1.0) / 2.0
	if invert: return 1.0 - normalized
	return normalized

func _pick_device() -> int:
	var pads: Array[int] = Input.get_connected_joypads()
	if pads.is_empty(): return -1
	if prefer_fanatec:
		for id: int in pads:
			var joy_name: String = Input.get_joy_name(id)
			if "Fanatec" in joy_name or "FANATEC" in joy_name \
			or "CSL" in joy_name or "ClubSport" in joy_name:
				return id
	return pads[0]
