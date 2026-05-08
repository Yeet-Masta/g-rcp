# TODO: Automatically generate the sliders instead of managing them from the editor.

extends Control



@export var open_controls_button: Button
@export var settings_container: VBoxContainer
var car: Car



func setcar():
	car = CarManager.get_active()


func _on_open_controls_pressed():
	open_controls_button.release_focus()
	if visible:
		visible = false
		ConfigManager.save_config()
	else:
		var cancel_event = InputEventAction.new()
		cancel_event.action = "ui_cancel"
		cancel_event.pressed = true
		Input.parse_input_event(cancel_event)
		#Input.action_press("ui_cancel")
		await get_tree().create_timer(0.1).timeout # TODO: swap this for different logic
		
		Input.action_release("ui_cancel")
		visible = true


#region internal
func _ready():
	setcar()
	# Refresh `car` whenever a different car becomes active (cycle, swap, first spawn).
	CarManager.active_car_changed.connect(_on_active_car_changed)
	
	for setting in settings_container.get_children():
		if setting.var_name == "shift_assist_level":
			setting.value = ConfigManager.data.controls.shift_assist_level
			setting.get_node("amount").text = str(setting.value)
		elif ConfigManager.data.controls.get(setting.var_name) != null:
			if ConfigManager.data.controls.get(setting.var_name) is bool:
				setting.button_pressed = ConfigManager.data.controls.get(setting.var_name)
				setting.get_node("amount").text = str(setting.button_pressed)
			else:
				setting.value = ConfigManager.data.controls.get(setting.var_name)
				setting.get_node("amount").text = str(setting.value)
		else:
			# Guard: a car-backed slider can't initialize without a car.
			if car == null:
				continue
			if setting.get_class() == "HSlider":
				setting.value = car.get(setting.var_name)
				setting.get_node("amount").text = str(setting.value)
			else:
				setting.button_pressed = car.get(setting.var_name)
				setting.get_node("amount").text = str(setting.button_pressed)
	
	open_controls_button.pressed.connect(_on_open_controls_pressed)


func _on_active_car_changed(_new_car: Node) -> void:
	setcar()


func _process(_delta):
	# NOTE: removed the top-level `if !car: return`. ConfigManager-backed
	# sliders don't need a car; only the third branch does.
	for setting in settings_container.get_children():
		if setting.var_name == "shift_assist_level":
			ConfigManager.data.controls.shift_assist_level = setting.value
			setting.get_node("amount").text = str(setting.value)
		elif ConfigManager.data.controls.get(setting.var_name) != null:
			if ConfigManager.data.controls.get(setting.var_name) is bool:
				ConfigManager.data.controls.set(setting.var_name, setting.button_pressed)
				setting.get_node("amount").text = str(setting.button_pressed)
			else:
				ConfigManager.data.controls.set(setting.var_name, setting.value)
				setting.get_node("amount").text = str(setting.value)
		else:
			if car == null:
				continue
			if setting.get_class() == "HSlider":
				car.set(setting.var_name, setting.value)
				setting.get_node("amount").text = str(setting.value)
			else:
				car.set(setting.var_name, setting.button_pressed)
				setting.get_node("amount").text = str(setting.button_pressed)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		visible = false
#endregion internal
