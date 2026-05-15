## A custom node for handling input from a Fanatec ClubSport Steering Wheel RS
## attached to a Fanatec CSL Elite Wheel Base.
##
## [FanatecWheel] is a "translator" between the wheel and your game.
## Godot gives wheel input as low-level joypad data (axis values and button IDs),
## which can be hard to work with directly. This node:
## [br]
## - Watches for a racing wheel to be connected (and reconnects if it's unplugged).
## - Reads the steering axis each frame and converts it from a raw -1.0..1.0 value
##   into a real steering angle in degrees using [member wheel_range_degrees].
## - Emits clear, named signals (like [code]cross_pressed[/code] or [code]r1_released[/code])
##   instead of making you remember numeric button indexes.
## - Keeps track of previous button states so it only emits "pressed" once when a
##   button goes down, and "released" once when it comes back up.
## [br][br]
## Button mapping is based on the official Fanatec ClubSport Steering Wheel RS
## "PC" column. The PC values are 1-indexed in the Fanatec manual; Godot uses
## 0-indexed buttons, so each value here is the manual value minus 1.
## [br][br]
## By default, if [member prefer_fanatec] is enabled, it will try to pick the
## correct device automatically by looking for "Fanatec", "CSL", or "ClubSport"
## in the device name. If it can't find a match, it falls back to the first
## connected joypad.

@icon("res://addons/logitech_g29/icons/G29 Steering.svg")
class_name FanatecWheel
extends Node

## Emitted when the steering wheel angle changes. The [param degrees] value is calculated using the raw axis and [member wheel_range_degrees].
signal steering_changed(degrees: float)

## Emitted when the raw steering axis changes. The [param value] is typically between -1.0 (left) and 1.0 (right).
signal steering_raw_changed(value: float)

# Face Buttons (right side of the wheel - the four colored buttons)
## Emitted when the Cross (X) button is pressed down. (Wheel button #1)
signal cross_pressed
## Emitted when the Cross (X) button is released.
signal cross_released
## Emitted when the Circle button is pressed down. (Wheel button #2)
signal circle_pressed
## Emitted when the Circle button is released.
signal circle_released
## Emitted when the Triangle button is pressed down. (Wheel button #3)
signal triangle_pressed
## Emitted when the Triangle button is released.
signal triangle_released
## Emitted when the Square button is pressed down. (Wheel button #4)
signal square_pressed
## Emitted when the Square button is released.
signal square_released

# Center / System buttons
## Emitted when the Options (menu) button is pressed. (Wheel button #5)
signal options_pressed
## Emitted when the Options (menu) button is released.
signal options_released
## Emitted when the Share button is pressed. (Wheel button #6)
signal share_pressed
## Emitted when the Share button is released.
signal share_released
## Emitted when the R3 (right thumb-stick click) is pressed. (Wheel button #7)
signal r3_pressed
## Emitted when the R3 button is released.
signal r3_released
## Emitted when the L3 (left thumb-stick click) is pressed. (Wheel button #8)
signal l3_pressed
## Emitted when the L3 button is released.
signal l3_released

# Shoulders & Paddles
## Emitted when the right rear thumb paddle (R2) is pressed. (Wheel button #9)
signal r2_pressed
## Emitted when the right rear thumb paddle (R2) is released.
signal r2_released
## Emitted when the left rear thumb paddle (L2) is pressed. (Wheel button #10)
signal l2_pressed
## Emitted when the left rear thumb paddle (L2) is released.
signal l2_released
## Emitted when the right magnetic shifter paddle (R1 / upshift) is pressed. (Wheel button #11)
signal r1_pressed
## Emitted when the right magnetic shifter paddle (R1) is released.
signal r1_released
## Emitted when the left magnetic shifter paddle (L1 / downshift) is pressed. (Wheel button #12)
signal l1_pressed
## Emitted when the left magnetic shifter paddle (L1) is released.
signal l1_released

# PS / Tuning / FunkySwitch
## Emitted when the PS button (small button at bottom center) is pressed. (Wheel button #13)
signal ps_pressed
## Emitted when the PS button is released.
signal ps_released
## Emitted when the Tuning Menu confirm button is pressed. (Wheel button #14)
## NOTE: This is the small button to the left of the LED display. Pressing the
## Tuning button itself doesn't generate a normal joypad input — it opens the
## on-wheel hardware menu instead.
signal tuning_confirm_pressed
## Emitted when the Tuning Menu confirm button is released.
signal tuning_confirm_released

# FunkySwitch (the 7-way encoder/joystick on the right spoke - wheel button #15)
## Emitted when the FunkySwitch is pressed straight in (the click).
signal funky_click_pressed
## Emitted when the FunkySwitch click is released.
signal funky_click_released
## Emitted when the FunkySwitch is rotated clockwise one detent.
signal funky_rotate_cw
## Emitted when a FunkySwitch CW rotation event ends.
signal funky_rotate_cw_released
## Emitted when the FunkySwitch is rotated counter-clockwise one detent.
signal funky_rotate_ccw
## Emitted when a FunkySwitch CCW rotation event ends.
signal funky_rotate_ccw_released

# FunkySwitch directional inputs (mapped to D-pad)
## Emitted when the FunkySwitch is pushed up.
signal funky_up_pressed
## Emitted when the FunkySwitch up direction is released.
signal funky_up_released
## Emitted when the FunkySwitch is pushed down.
signal funky_down_pressed
## Emitted when the FunkySwitch down direction is released.
signal funky_down_released
## Emitted when the FunkySwitch is pushed left.
signal funky_left_pressed
## Emitted when the FunkySwitch left direction is released.
signal funky_left_released
## Emitted when the FunkySwitch is pushed right.
signal funky_right_pressed
## Emitted when the FunkySwitch right direction is released.
signal funky_right_released


@export_group("Device Settings")

## If [code]true[/code], the node will prioritize connecting to a joypad whose
## name contains "Fanatec", "CSL", or "ClubSport".
@export var prefer_fanatec: bool = true

## The internal joypad ID assigned by Godot. Read-only during gameplay; automatically assigned by [method _pick_device].
@export var device_id: int = -1

## The maximum physical rotation of the wheel in degrees. The CSL Elite Wheel
## Base defaults to 1080 degrees (540 left, 540 right). The ClubSport RS is a
## 320 mm road-style wheel and is typically used at 900 or 1080 degrees.
## Set this to match your base's currently configured SEN value.
@export var wheel_range_degrees: float = 1080.0

## The joypad axis used to track steering. Defaults to [constant JOY_AXIS_LEFT_X],
## which is what SDL2 reports for the Fanatec wheel's X axis on Windows.
@export var steering_axis: JoyAxis = JOY_AXIS_LEFT_X


@export_group("Debug")

## If [code]true[/code], the node will print connection status, button presses, and steering changes to the console.
@export var debug_print: bool = true

## The minimum change in degrees required before a new debug message is printed for steering. Prevents console spam.
@export var debug_steering_threshold: float = 0.5

## If [code]true[/code], scans all 64 possible joypad buttons every frame and
## prints any state change. Useful for figuring out which physical button maps
## to which numeric ID on your specific Fanatec firmware/driver combo.
@export var print_unknown_buttons: bool = false


# Internal variables (Double hashes are omitted here as they do not need public documentation)
var _previous_button_states: Dictionary = {}
var _last_steering: float = 0.0
var _last_raw_steering: float = 0.0
var _last_printed_steering: float = 0.0

var _button_map: Dictionary = {}
var _dpad_map: Dictionary = {}
var _debug_pressed_buttons: Array[int] = []

func _ready() -> void:
	# Button IDs are derived from the official Fanatec ClubSport Steering Wheel
	# RS PC mapping table (from the wheel manual). PC values are 1-indexed so we
	# subtract 1 for Godot's 0-indexed JoyButton IDs.
	#
	# Manual #  | PC (1-idx) | Godot (0-idx) | Function
	# ----------+------------+---------------+------------------
	#    1      |     2      |       1       | Cross (X)
	#    2      |     3      |       2       | Circle
	#    3      |     4      |       3       | Triangle
	#    4      |     1      |       0       | Square
	#    5      |    10      |       9       | Options (≡)
	#    6      |     9      |       8       | Share
	#    7      |    11      |      10       | R3
	#    8      |    12      |      11       | L3
	#    9      |     7      |       6       | R2 (right rear thumb)
	#   10      |     8      |       7       | L2 (left rear thumb)
	#   11      |     5      |       4       | R1 (right shift paddle)
	#   12      |     6      |       5       | L1 (left shift paddle)
	#   13      |    22      |      21       | PS button
	#   14      |    26      |      25       | Tuning confirm
	#   15      |    25      |      24       | FunkySwitch click
	#  GSB1     |    23      |      22       | FunkySwitch rotate CW
	#  GSB2     |    24      |      23       | FunkySwitch rotate CCW
	_button_map = {
		0:  "square",
		1:  "cross",
		2:  "circle",
		3:  "triangle",
		4:  "up_shift",
		5:  "down_shift",
		6:  "r2",
		7:  "l2",
		8:  "share",
		9:  "options",
		10: "r3",
		11: "l3", 
		21: "ps",
		22: "funky_rotate_ccw",
		23: "funky_rotate_cw",
		24: "funky_click",
		25: "tuning_confirm",
	}

	# The FunkySwitch directional inputs come through as D-Pad presses on the
	# CSL Elite Wheel Base for most wheels (including the ClubSport RS).
	_dpad_map = {
		JOY_BUTTON_DPAD_UP:    "funky_up",
		JOY_BUTTON_DPAD_DOWN:  "funky_down",
		JOY_BUTTON_DPAD_LEFT:  "funky_left",
		JOY_BUTTON_DPAD_RIGHT: "funky_right",
	}

	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_attempt_connection()

func _process(_delta: float) -> void:
	if _button_map.is_empty() or _dpad_map.is_empty():
		return

	_process_steering()
	_process_buttons(_button_map)
	_process_buttons(_dpad_map)

	if print_unknown_buttons:
		_run_debug_scanner()

func _process_steering() -> void:
	var raw_steer: float = Input.get_joy_axis(device_id, steering_axis)
	if raw_steer != _last_raw_steering:
		steering_raw_changed.emit(raw_steer)
		_last_raw_steering = raw_steer

	var current_steer_deg: float = raw_steer * (wheel_range_degrees * 0.5)
	if current_steer_deg != _last_steering:
		steering_changed.emit(current_steer_deg)
		_last_steering = current_steer_deg

		if debug_print and abs(current_steer_deg - _last_printed_steering) >= debug_steering_threshold:
			print("FanatecWheel Debug: steering_changed | Degrees: %.2f | Raw: %.4f" % [current_steer_deg, raw_steer])
			_last_printed_steering = current_steer_deg

func _process_buttons(map_to_check: Dictionary) -> void:
	for joy_btn: int in map_to_check.keys():
		var btn_name: String = map_to_check[joy_btn]
		var is_pressed: bool = Input.is_joy_button_pressed(device_id, joy_btn)
		var was_pressed: bool = _previous_button_states.get(btn_name, false)

		if is_pressed and not was_pressed:
			emit_signal(btn_name + "_pressed")
			if debug_print: print("FanatecWheel Debug: ", btn_name, "_pressed emitted (Button ID: ", joy_btn, ")")
		elif not is_pressed and was_pressed:
			emit_signal(btn_name + "_released")
			if debug_print: print("FanatecWheel Debug: ", btn_name, "_released emitted (Button ID: ", joy_btn, ")")

		_previous_button_states[btn_name] = is_pressed

# --- POLLING GETTERS ---
#
# Prefer these over the signals for per-frame physics / control code. They
# read Input directly so there's no latency, no signal plumbing, and they
# return a safe default when the device isn't connected.
#
# Typical usage in a car / vehicle script:
#     steer_input = $FanatecWheel.get_steering_normalized()
#     if $FanatecWheel.is_button_pressed("up_shift"): upshift()

## Returns [code]true[/code] when a wheel device is currently connected.
## When this is [code]false[/code], the steering getters return [code]0.0[/code]
## and [method is_button_pressed] always returns [code]false[/code].
func is_device_connected() -> bool:
	return device_id != -1

## Returns the steering wheel position normalized to [code]-1.0[/code] (full
## left) .. [code]1.0[/code] (full right). This is the raw axis value and
## ignores [member wheel_range_degrees] — it's the value most vehicle scripts
## want for "how far is the wheel turned, as a fraction of its travel".
func get_steering_normalized() -> float:
	if device_id == -1: return 0.0
	return Input.get_joy_axis(device_id, steering_axis)

## Returns the steering wheel angle in degrees, computed from the raw axis
## and [member wheel_range_degrees]. Negative values are left rotation.
func get_steering_degrees() -> float:
	if device_id == -1: return 0.0
	return Input.get_joy_axis(device_id, steering_axis) * (wheel_range_degrees * 0.5)

## Returns [code]true[/code] if the named button is currently held. Use the
## short names from [member _button_map] / [member _dpad_map]
## ([code]"cross"[/code], [code]"up_shift"[/code], [code]"down_shift"[/code],
## [code]"funky_up"[/code] etc). Returns [code]false[/code] if the name
## isn't mapped or the device isn't connected.
func is_button_pressed(button_name: String) -> bool:
	if device_id == -1: return false
	for joy_btn: int in _button_map.keys():
		if _button_map[joy_btn] == button_name:
			return Input.is_joy_button_pressed(device_id, joy_btn)
	for joy_btn: int in _dpad_map.keys():
		if _dpad_map[joy_btn] == button_name:
			return Input.is_joy_button_pressed(device_id, joy_btn)
	return false


## Continuously scans button IDs 0..63 and reports any changes. Useful when
## you don't know which button on the wheel maps to which Godot ID.
func _run_debug_scanner() -> void:
	for i: int in range(64):
		var is_pressed: bool = Input.is_joy_button_pressed(device_id, i)
		var was_pressed: bool = i in _debug_pressed_buttons
		if is_pressed and not was_pressed:
			print("FanatecWheel DEBUG SCAN - Button ID pressed: ", i)
			_debug_pressed_buttons.append(i)
		elif not is_pressed and was_pressed:
			print("FanatecWheel DEBUG SCAN - Button ID released: ", i)
			_debug_pressed_buttons.erase(i)

## Attempts to find and connect to a valid joypad device based on [member prefer_fanatec].
func _attempt_connection() -> void:
	device_id = _pick_device()
	if device_id == -1:
		if debug_print: print("FanatecWheel Warning: No wheel found.")
		set_process(false)
		return

	if debug_print:
		print("FanatecWheel: Connected to device ", device_id, " (", Input.get_joy_name(device_id), ")")

	for btn_name: String in _button_map.values(): _previous_button_states[btn_name] = false
	for btn_name: String in _dpad_map.values(): _previous_button_states[btn_name] = false
	set_process(true)

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected and device_id == -1: _attempt_connection()
	elif not connected and device == device_id:
		device_id = -1
		set_process(false)

## Scans connected joypads and returns the device ID of the wheel. Returns -1 if no wheel is found.
func _pick_device() -> int:
	var pads: Array[int] = Input.get_connected_joypads()
	if pads.is_empty(): return -1
	if prefer_fanatec:
		for id: int in pads:
			var joy_name: String = Input.get_joy_name(id)
			# Common identifiers for Fanatec hardware on Windows / Linux:
			# - "FANATEC CSL Elite Wheel Base"
			# - "Fanatec ClubSport Wheel Base"
			# - "Fanatec Podium Wheel Base"
			if "Fanatec" in joy_name or "FANATEC" in joy_name \
			or "CSL" in joy_name or "ClubSport" in joy_name:
				return id
	return pads[0]
