## A custom node for handling input from a Fanatec ClubSport Shifter SQ V1.5.
##
## [FanatecShifter] monitors the joypad buttons associated with the H-pattern
## shifter and emits corresponding signals when gears are engaged or
## disengaged. The SQ V1.5 has two modes selectable on a hardware slider:
## [br]
## - [b]H-Pattern[/b] (slider in "8" position): A traditional 7-speed gate
##   with reverse gear locked behind a press-down inhibitor. Each gear slot
##   reports as its own joypad button. The gear stays engaged while the lever
##   is in that position.
## - [b]Sequential[/b] (slider in "SEQ" position): The lever returns to
##   neutral after each push. Pushing forward fires an "up shift" pulse,
##   pulling back fires a "down shift" pulse. The corresponding signals are
##   [signal seq_up_pressed] / [signal seq_down_pressed].
## [br][br]
## [b]Important note on Reverse / 7th gear:[/b] The SQ V1.5 has a reverse
## inhibitor — to engage reverse you must press the knob [i]down[/i] into
## the housing and shift to the upper-right slot. To engage 7th gear you
## simply shift to the upper-right slot without pressing down. The inhibitor
## is mechanical, but the resulting button events are distinct.
## [br][br]
## When connected to a Fanatec wheel base via the "Shifter 1" RJ12 port
## (recommended), the shifter buttons appear on the same joypad device as
## the wheel and pedals, with button IDs appended after the wheel's buttons.
## When using the optional ClubSport USB Adapter on PC, the shifter appears
## as its own device.
## [br][br]
## [b]Mapping uncertainty:[/b] The exact button IDs the shifter reports
## depend on the wheel base firmware version and driver. The defaults below
## assume gear slots are reported as buttons 12-18 (matching the layout used
## by older Logitech / Thrustmaster shifters and by Fanatec's older
## documentation), with the 7th-gear and reverse positions distinguished by
## whether the inhibitor button is also pressed. If your gears come through
## on different IDs, enable [member print_debug_ids] and watch the console
## while shifting through each gate — then update [member shifter_map] in
## code or the inspector.
## [br][br]
## [b]Example Usage:[/b]
## [codeblock]
## func _ready():
##     $FanatecShifter.gear_1_pressed.connect(_on_gear_1_engaged)
##     $FanatecShifter.gear_reverse_pressed.connect(_on_reverse_engaged)
##
## func _on_gear_1_engaged():
##     current_gear = 1
##     print("Shifted into 1st gear!")
## [/codeblock]
@icon("res://addons/logitech_g29/icons/G29 Shifter.svg")
class_name FanatecShifter
extends Node

# --- H-PATTERN GEAR SIGNALS ---

## Emitted when the shifter is moved into the 1st gear slot.
signal gear_1_pressed
## Emitted when the shifter is moved out of the 1st gear slot.
signal gear_1_released

## Emitted when the shifter is moved into the 2nd gear slot.
signal gear_2_pressed
## Emitted when the shifter is moved out of the 2nd gear slot.
signal gear_2_released

## Emitted when the shifter is moved into the 3rd gear slot.
signal gear_3_pressed
## Emitted when the shifter is moved out of the 3rd gear slot.
signal gear_3_released

## Emitted when the shifter is moved into the 4th gear slot.
signal gear_4_pressed
## Emitted when the shifter is moved out of the 4th gear slot.
signal gear_4_released

## Emitted when the shifter is moved into the 5th gear slot.
signal gear_5_pressed
## Emitted when the shifter is moved out of the 5th gear slot.
signal gear_5_released

## Emitted when the shifter is moved into the 6th gear slot.
signal gear_6_pressed
## Emitted when the shifter is moved out of the 6th gear slot.
signal gear_6_released

## Emitted when the shifter is moved into the 7th gear slot
## (upper-right position, [i]without[/i] pressing the knob down).
signal gear_7_pressed
## Emitted when the shifter is moved out of the 7th gear slot.
signal gear_7_released

## Emitted when the shifter is pressed down and moved into the reverse
## position. The SQ V1.5 has a reverse inhibitor: you must press the knob
## down for the input to register as reverse rather than 7th gear.
signal gear_reverse_pressed
## Emitted when the shifter is moved out of the reverse position.
signal gear_reverse_released

# --- SEQUENTIAL MODE SIGNALS ---

## Emitted when the lever is pushed up (one upshift) while in sequential mode.
signal seq_up_pressed
## Emitted when the upshift button is released.
signal seq_up_released

## Emitted when the lever is pulled down (one downshift) while in sequential mode.
signal seq_down_pressed
## Emitted when the downshift button is released.
signal seq_down_released


@export_group("Device Settings")

## If [code]true[/code], the node will prioritize connecting to a joypad whose
## name contains "Fanatec", "CSL", or "ClubSport".
@export var prefer_fanatec: bool = true

## The internal joypad ID assigned by Godot. Read-only during gameplay.
## When the shifter is connected through a Fanatec wheel base, this will be
## the same as the wheel's device_id.
@export var device_id: int = -1


@export_group("Button Mapping")

## Maps Godot joypad button IDs to gear slot names. The defaults match the
## most commonly reported layout for Fanatec wheel bases on Windows. If your
## hardware reports different IDs, enable [member print_debug_ids], shift
## through each gear, and update these values.
@export var shifter_map: Dictionary = {
	12: "gear_1",
	13: "gear_2",
	14: "gear_3",
	15: "gear_4",
	16: "gear_5",
	17: "gear_6",
	18: "gear_7",
	19: "gear_reverse",
}

## Maps Godot joypad button IDs to sequential-mode events. Used only when the
## shifter's hardware slider is set to "SEQ".
@export var sequential_map: Dictionary = {
	12: "seq_up",   # Same physical position as gear 1 in many drivers
	13: "seq_down", # Same physical position as gear 2 in many drivers
}

## When [code]true[/code], the node listens to [member sequential_map]
## instead of [member shifter_map]. Set this in code (or expose a UI toggle)
## to match the position of the slider on the underside of the shifter.
@export var sequential_mode: bool = false


@export_group("Troubleshooting")

## If [code]true[/code], continuously scans all 64 possible joypad buttons
## and prints to the console whenever a button state changes. Very useful
## for diagnosing which physical gear position fires which Godot button ID.
@export var print_debug_ids: bool = true


# Internal State Tracking
var _previous_button_states: Dictionary = {}
var _debug_pressed_buttons: Array[int] = []

func _ready() -> void:
	if device_id == -1: device_id = _pick_device()
	if device_id == -1:
		set_process(false)
		return

	if print_debug_ids:
		print("FanatecShifter: Connected to device ", device_id, " (", Input.get_joy_name(device_id), ")")

	# Pre-populate state cache for every signal we might emit, so the first
	# real press always counts as a transition.
	for btn_name: String in shifter_map.values():
		_previous_button_states[btn_name] = false
	for btn_name: String in sequential_map.values():
		_previous_button_states[btn_name] = false

func _process(_delta: float) -> void:
	if print_debug_ids:
		_run_debug_scanner()

	var active_map: Dictionary = sequential_map if sequential_mode else shifter_map

	for joy_btn: int in active_map.keys():
		var btn_name: String = active_map[joy_btn]
		var is_pressed: bool = Input.is_joy_button_pressed(device_id, joy_btn)
		var was_pressed: bool = _previous_button_states.get(btn_name, false)

		if is_pressed and not was_pressed: emit_signal(btn_name + "_pressed")
		elif not is_pressed and was_pressed: emit_signal(btn_name + "_released")
		_previous_button_states[btn_name] = is_pressed

func _run_debug_scanner() -> void:
	for i: int in range(64):
		var is_pressed: bool = Input.is_joy_button_pressed(device_id, i)
		var was_pressed: bool = i in _debug_pressed_buttons

		if is_pressed and not was_pressed:
			print("DEBUG - Shifter button ID pressed: ", i)
			_debug_pressed_buttons.append(i)
		elif not is_pressed and was_pressed:
			print("DEBUG - Shifter button ID released: ", i)
			_debug_pressed_buttons.erase(i)


# --- POLLING GETTERS ---

## Returns [code]true[/code] when a shifter device is currently connected.
func is_device_connected() -> bool:
	return device_id != -1

## Returns [code]true[/code] if the named gear / sequential event is currently
## active. Names are the values from [member shifter_map] / [member sequential_map]
## ([code]"gear_1"[/code]..[code]"gear_7"[/code], [code]"gear_reverse"[/code],
## [code]"seq_up"[/code], [code]"seq_down"[/code]).
func is_gear_engaged(gear_name: String) -> bool:
	if device_id == -1: return false
	var active_map: Dictionary = sequential_map if sequential_mode else shifter_map
	for joy_btn: int in active_map.keys():
		if active_map[joy_btn] == gear_name:
			return Input.is_joy_button_pressed(device_id, joy_btn)
	return false

## Returns the currently engaged H-pattern gear as an integer:
## [code]1[/code]..[code]7[/code] for forward gears, [code]-1[/code] for
## reverse, [code]0[/code] for neutral (no gear engaged) or when the shifter
## is in sequential mode or disconnected.
func get_current_gear() -> int:
	if device_id == -1 or sequential_mode: return 0
	for joy_btn: int in shifter_map.keys():
		if Input.is_joy_button_pressed(device_id, joy_btn):
			var n: String = shifter_map[joy_btn]
			if n == "gear_reverse": return -1
			if n.begins_with("gear_"):
				return int(n.trim_prefix("gear_"))
	return 0

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
