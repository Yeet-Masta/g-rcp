extends Control



@export var open_graphics_button: Button
@export var settings_container: VBoxContainer



func apply_graphics_settings():
	get_tree().get_first_node_in_group("sun").shadow_enabled = ConfigManager.data.graphics.shadows


func load_settings():
	for i: CheckBox in settings_container.get_children():
		i.button_pressed = ConfigManager.data.graphics.get(i.var_name)
		i.get_node("amount").text = str(i.button_pressed)


func set_setting(setting_name: String, value: bool):
	ConfigManager.data.graphics.set(setting_name, value)


func _on_setting_pressed(setting: CheckBox):
	set_setting(setting.var_name, setting.button_pressed)


func _ready():
	load_settings()
	
	open_graphics_button.pressed.connect(_on_open_graphics_pressed)
	for i: CheckBox in settings_container.get_children():
		i.pressed.connect(_on_setting_pressed.bind(i))


func _process(_delta):
	load_settings()
	apply_graphics_settings()


func _input(_event):
	if Input.is_action_just_pressed("ui_cancel"):
		visible = false
	elif Input.is_action_just_pressed("toggle_fs"):
		settings_container.find_child("_FULLSCREEN").button_pressed = !settings_container.find_child("_FULLSCREEN").button_pressed


func _on_open_graphics_pressed():
	open_graphics_button.release_focus()
	if visible:
		visible = false
		ConfigManager.save_config()
	else:
		Input.action_press("ui_cancel")
		await get_tree().create_timer(0.1).timeout
		Input.action_release("ui_cancel")
		visible = true
