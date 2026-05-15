## A custom node for handling Logitech G29 Racing Wheel input, optimized for simultaneous shifter use.
##
## [G29WheelShifter] does the same “raw input → easy signals” job as a normal wheel node,
## but adds one important safety feature for people using the Logitech H-pattern shifter.
## On some platforms/drivers, the shifter and the wheel’s D-Pad can report the *same*
## internal button IDs. When that happens, changing gears may accidentally look like a
## D-Pad press (or a D-Pad press may look like a gear change) depending on how your game reads input.
## [br]
## To solve this, [member shifter_priority] can be enabled. When it is [code]true[/code],
## this node intentionally ignores the specific D-Pad directions that commonly overlap
## with the shifter slots (Down/Left/Right). This prevents “dual-firing” bugs where one
## physical action triggers two different controls in-game.
## [br]
## Aside from the overlap protection, it still:
## [br]
## - Detects a connected wheel automatically (preferring devices named “G29”/“Logitech” if enabled).
## - Reads the steering axis each frame and converts -1.0..1.0 into degrees using [member wheel_range_degrees].
## - Emits clear pressed/released signals for face buttons, paddles, system buttons, and the D-Pad.
## - Tracks previous button states so signals only fire on transitions (down → pressed, up → released).
## [br][br]
## [b]Example Usage:[/b]
## [codeblock]
## func _ready():
##     # If you have a G29Shifter node active in your scene, enable this:
##     $G29WheelShifter.shifter_priority = true
##     $G29WheelShifter.steering_changed.connect(_on_steer)
##     $G29WheelShifter.cross_pressed.connect(_on_handbrake)
## [/codeblock]

@icon("res://addons/logitech_g29/icons/G29 Steering.svg")
class_name G29WheelShifter
extends Node

## Emitted when the steering wheel angle changes. The [param degrees] value is calculated using the raw axis and [member wheel_range_degrees].
signal steering_changed(degrees: float)
## Emitted when the raw steering axis changes. The [param value] is typically between -1.0 (left) and 1.0 (right).
signal steering_raw_changed(value: float)

# Face Buttons
## Emitted when the Cross (X) button is pressed down.
signal cross_pressed
## Emitted when the Cross (X) button is released.
signal cross_released
## Emitted when the Circle button is pressed down.
signal circle_pressed
## Emitted when the Circle button is released.
signal circle_released
## Emitted when the Square button is pressed down.
signal square_pressed
## Emitted when the Square button is released.
signal square_released
## Emitted when the Triangle button is pressed down.
signal triangle_pressed
## Emitted when the Triangle button is released.
signal triangle_released

# D-Pad
## Emitted when the D-pad Up direction is pressed.
signal dpad_up_pressed
## Emitted when the D-pad Up direction is released.
signal dpad_up_released
## Emitted when the D-pad Down direction is pressed. Ignored if [member shifter_priority] is true.
signal dpad_down_pressed
## Emitted when the D-pad Down direction is released. Ignored if [member shifter_priority] is true.
signal dpad_down_released
## Emitted when the D-pad Left direction is pressed. Ignored if [member shifter_priority] is true.
signal dpad_left_pressed
## Emitted when the D-pad Left direction is released. Ignored if [member shifter_priority] is true.
signal dpad_left_released
## Emitted when the D-pad Right direction is pressed. Ignored if [member shifter_priority] is true.
signal dpad_right_pressed
## Emitted when the D-pad Right direction is released. Ignored if [member shifter_priority] is true.
signal dpad_right_released

# Shoulders & Paddles
## Emitted when the L1 button (left paddle) is pressed.
signal l1_pressed
## Emitted when the L1 button (left paddle) is released.
signal l1_released
## Emitted when the R1 button (right paddle) is pressed.
signal r1_pressed
## Emitted when the R1 button (right paddle) is released.
signal r1_released
## Emitted when the L2 button is pressed.
signal l2_pressed
## Emitted when the L2 button is released.
signal l2_released
## Emitted when the R2 button is pressed.
signal r2_pressed
## Emitted when the R2 button is released.
signal r2_released
## Emitted when the L3 button is pressed.
signal l3_pressed
## Emitted when the L3 button is released.
signal l3_released
## Emitted when the R3 button is pressed.
signal r3_pressed
## Emitted when the R3 button is released.
signal r3_released

# System & Dials
## Emitted when the Share button is pressed.
signal share_pressed
## Emitted when the Share button is released.
signal share_released
## Emitted when the Options button is pressed.
signal options_pressed
## Emitted when the Options button is released.
signal options_released
## Emitted when the PlayStation (PS) button is pressed.
signal ps_pressed
## Emitted when the PlayStation (PS) button is released.
signal ps_released
## Emitted when the Plus (+) button is pressed.
signal plus_pressed
## Emitted when the Plus (+) button is released.
signal plus_released
## Emitted when the Minus (-) button is pressed.
signal minus_pressed
## Emitted when the Minus (-) button is released.
signal minus_released
## Emitted when the red selection dial is turned right.
signal dial_right_pressed
## Emitted when the red selection dial right-turn is released.
signal dial_right_released
## Emitted when the red selection dial is turned left.
signal dial_left_pressed
## Emitted when the red selection dial left-turn is released.
signal dial_left_released
## Emitted when the button inside the red selection dial is pressed.
signal dial_enter_pressed
## Emitted when the button inside the red selection dial is released.
signal dial_enter_released


@export_group("Device Settings")

## If [code]true[/code], the node will prioritize connecting to a joypad with "G29" or "Logitech" in its name.
@export var prefer_logitech_g29: bool = true

## The internal joypad ID assigned by Godot. Read-only during gameplay.
@export var device_id: int = -1

## The maximum physical rotation of the wheel in degrees. The G29 defaults to 900 degrees.
@export var wheel_range_degrees: float = 900.0

## The joypad axis used to track steering. Defaults to [constant JOY_AXIS_LEFT_X].
@export var steering_axis: JoyAxis = JOY_AXIS_LEFT_X

## Set to [code]true[/code] if you are using an external H-pattern shifter. 
## This mutes specific D-pad inputs (Down, Left, Right) that share hardware button IDs with the shifter slots, 
## preventing dual-firing glitches in your game.
@export var shifter_priority: bool = false


@export_group("Debug")

## If [code]true[/code], prints connection status, button presses, and steering changes to the console.
@export var debug_print: bool = true

## The minimum change in degrees required before a new debug message is printed for steering.
@export var debug_steering_threshold: float = 0.5


var _previous_button_states: Dictionary = {}
var _last_steering: float = 0.0
var _last_raw_steering: float = 0.0
var _last_printed_steering: float = 0.0

var _shifter_overlap_ids: Array[int] = [
	JOY_BUTTON_DPAD_DOWN,
	JOY_BUTTON_DPAD_LEFT,
	JOY_BUTTON_DPAD_RIGHT
]

var _button_map: Dictionary = {}
var _dpad_map: Dictionary = {}

func _ready() -> void:
	_button_map = {
		0: "cross",        
		1: "square",       
		2: "circle",       
		3: "triangle",     
		4: "r1",           
		5: "l1",           
		6: "r2",           
		7: "l2",           
		8: "share",        
		9: "options",      
		10: "r3",          
		11: "l3",          
		19: "plus",        
		20: "minus",       
		21: "dial_right",  
		22: "dial_left",   
		23: "dial_enter",  
		24: "ps"           
	}
	
	_dpad_map = {
		JOY_BUTTON_DPAD_UP: "dpad_up",
		JOY_BUTTON_DPAD_DOWN: "dpad_down",
		JOY_BUTTON_DPAD_LEFT: "dpad_left",
		JOY_BUTTON_DPAD_RIGHT: "dpad_right"
	}

	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_attempt_connection()

func _process(_delta: float) -> void:
	if _button_map.is_empty() or _dpad_map.is_empty():
		return
		
	_process_steering()
	_process_buttons(_button_map)
	_process_buttons(_dpad_map)

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
			print("G29Wheel Debug: steering_changed | Degrees: %.2f | Raw: %.4f" % [current_steer_deg, raw_steer])
			_last_printed_steering = current_steer_deg

func _process_buttons(map_to_check: Dictionary) -> void:
	for joy_btn: int in map_to_check.keys():
		# Skips processing if this button ID conflicts with the shifter
		if shifter_priority and joy_btn in _shifter_overlap_ids:
			continue
			
		var btn_name: String = map_to_check[joy_btn]
		var is_pressed: bool = Input.is_joy_button_pressed(device_id, joy_btn)
		var was_pressed: bool = _previous_button_states.get(btn_name, false)
		
		if is_pressed and not was_pressed: 
			emit_signal(btn_name + "_pressed")
			if debug_print: print("G29Wheel Debug: ", btn_name, "_pressed emitted (Button ID: ", joy_btn, ")")
		elif not is_pressed and was_pressed: 
			emit_signal(btn_name + "_released")
			if debug_print: print("G29Wheel Debug: ", btn_name, "_released emitted (Button ID: ", joy_btn, ")")
			
		_previous_button_states[btn_name] = is_pressed

func _attempt_connection() -> void:
	device_id = _pick_device()
	if device_id == -1:
		if debug_print: print("G29Wheel Warning: No wheel found.")
		set_process(false)
		return
	
	for btn_name: String in _button_map.values(): _previous_button_states[btn_name] = false
	for btn_name: String in _dpad_map.values(): _previous_button_states[btn_name] = false
	set_process(true)

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected and device_id == -1: _attempt_connection()
	elif not connected and device == device_id:
		device_id = -1
		set_process(false)

func _pick_device() -> int:
	var pads: Array[int] = Input.get_connected_joypads()
	if pads.is_empty(): return -1
	if prefer_logitech_g29:
		for id: int in pads:
			var joy_name: String = Input.get_joy_name(id)
			if "G29" in joy_name or "Logitech" in joy_name: return id
	return pads[0]
