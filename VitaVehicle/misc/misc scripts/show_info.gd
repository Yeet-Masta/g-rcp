extends Control



@export var open_info_button: Button



func _ready() -> void:
	open_info_button.pressed.connect(_on_button_pressed)


func _input(_event):
	if Input.is_action_just_pressed("ui_cancel"):
		visible = false


func _on_button_pressed():
	open_info_button.release_focus()
	if visible:
		visible = false
	else:
		var cancel_event = InputEventAction.new()
		cancel_event.action = "ui_cancel"
		cancel_event.pressed = true
		Input.parse_input_event(cancel_event)
		#Input.action_press("ui_cancel") # TODO BUG: fix this hack in every single script that uses it, can't use this with _input as per the documentation, use parse_input_event instead
		await get_tree().create_timer(0.1).timeout
		Input.action_release("ui_cancel")
		visible = true
