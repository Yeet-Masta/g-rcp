extends Control



@onready var button := $scroll/container/_DEFAULT.duplicate()

@export_custom(PROPERTY_HINT_DIR, "") var pathh: String
var canclick := true
var literal_cache := {}
@export var swap_map_button: Button

@export var current_map := NodePath()



func load_and_cache(path: String) -> Resource:
	var loaded: Resource
	
	if path in literal_cache:
		pass
	else:
		literal_cache[path] = load(path)
	
	loaded = literal_cache[path]
	return loaded


func swapmap(naem: String):
	visible = false
	get_node(current_map).queue_free()
	
	var d: Node = load_and_cache(pathh + "/" + naem + "/scene.tscn").instantiate()
	
	Helper.get_ancestor(self, 2).add_child(d)
	
	current_map = "../../" + d.name
	
	await get_tree().create_timer(0.1).timeout
	var car: Car = get_tree().get_first_node_in_group("car")
	car.global_position *= Vector3.ZERO
	car.global_rotation *= Vector3.ZERO
	car.linear_velocity *= Vector3.ZERO
	car.angular_velocity *= Vector3.ZERO


func _ready():
	swap_map_button.pressed.connect(_on_button_pressed)
	
	$scroll/container/_DEFAULT.queue_free()
	
	
	for i in DirAccess.get_directories_at(pathh):
		var but := button.duplicate()
		$scroll/container.add_child(but)
		but.get_node("mapname").text = i
		but.get_node("icon").texture = load(pathh + "/" +  i + "/thumbnail.png")
		but.pressed.connect(swapmap.bind(i))


func _input(_event):
	if Input.is_action_just_pressed("ui_cancel"):
		visible = false


func _on_button_pressed():
	swap_map_button.release_focus()
	if visible:
		visible = false
	else:
		var cancel_event = InputEventAction.new()
		cancel_event.action = "ui_cancel"
		cancel_event.pressed = true
		Input.parse_input_event(cancel_event)
		#Input.action_press("ui_cancel")
		await get_tree().create_timer(0.1).timeout
		Input.action_release("ui_cancel")
		visible = true
