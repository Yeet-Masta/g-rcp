extends Control

@onready var button = $scroll/container/_DEFAULT.duplicate()

@export_custom(PROPERTY_HINT_DIR, "") var pathh: String
var canclick = true
var literal_cache = {}

@onready var default_position = get_tree().get_first_node_in_group("car").global_position # TODO: Fragile, add a thing in a separate group per scene instead. Also why the UI has to know this?

func load_and_cache(path):
	var loaded = null
	
	if !path in literal_cache:
		literal_cache[path] = load(path)
	
	loaded = literal_cache[path]
	return loaded

func swapcar(path):
	visible = false
	get_parent().get_node("swap car").visible = false
	if canclick:
		canclick = false
		get_parent().get_node("vgs").clear()
		
		default_position = get_tree().get_first_node_in_group("car").global_position
		
		get_tree().get_first_node_in_group("car").queue_free()
		
		await get_tree().create_timer(1.0).timeout
		
		var d = load_and_cache(str(path)+str("/scene")+str(".tscn")).instantiate()
		
		Helper.get_ancestor(self, 2).add_child(d)
		
		d.global_position = default_position + Vector3(0,5,0)
		var car = get_tree().get_first_node_in_group("car")
		
		get_parent()
		get_parent()._ready()
		get_parent().get_node("controls manipulator").setcar()
		
		get_parent().get_node("power_graph").Generation_Range = float(int(float(car.RPMLimit / 1000.0)) * 1000 + 1000)
		get_parent().get_node("power_graph").Draw_RPM = car.IdleRPM
		
		get_parent().get_node("power_graph")._ready()
		
		var peak = max(get_parent().get_node("power_graph").peaktq[0],get_parent().get_node("power_graph").peakhp[0])
		
		get_parent().get_node("power_graph").draw_scale = 1.0/peak
		get_parent().get_node("power_graph")._ready()
		
		get_parent().get_node("tacho").Redline = int(float(car.RPMLimit / 1000.0)) * 1000
		get_parent().get_node("tacho").RPM_Range = int(float(car.RPMLimit / 1000.0)) * 1000 + 2000
		get_parent().get_node("tacho").Turbo_Visible = car.TurboEnabled
		get_parent().get_node("tacho").Max_PSI = car.MaxPSI * car.TurboAmount
		
		get_parent().get_node("tacho")._ready()
		
		canclick = true
	get_parent().get_node("swap car").visible = true


func _ready():
	var d = Helper.get_dir_children(pathh + "/").folders
	
	for i: String in d:
		var but = button.duplicate()
		$scroll/container.add_child(but)
		but.visible = true
		but.get_node("carname").text = i.get_file()
		but.get_node("icon").texture = load(str(i)+str("/thumbnail")+str(".png"))
		but.pressed.connect(swapcar.bind(i))

func _input(_event):
	if Input.is_action_just_pressed("ui_cancel"):
		visible = false

func _on_swap_car_pressed():
	get_parent().get_node("swap car").release_focus()
	if visible:
		visible = false
	else:
		Input.action_press("ui_cancel")
		await get_tree().create_timer(0.1).timeout
		
		Input.action_release("ui_cancel")
		visible = true
