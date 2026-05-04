extends Control



@onready var button = $scroll/container/_DEFAULT.duplicate()

@export_custom(PROPERTY_HINT_DIR, "") var pathh: String
var canclick := true
var literal_cache := {}
@export var swap_car_button: Button

@onready var default_position: Vector3 = get_tree().get_first_node_in_group("car").global_position # TODO: Fragile, add a thing in a separate group per scene instead. Also why the UI has to know this?



func load_and_cache(path):
	var loaded = null
	
	if !path in literal_cache:
		literal_cache[path] = load(path)
	
	loaded = literal_cache[path]
	return loaded

func swapcar(path: String):
	visible = false
	swap_car_button.visible = false
	if not canclick:
		return
	
	canclick = false
	get_parent().get_node("vgs").clear()
	
	# 1. Get the current active car and remember where it is
	var current_car: Node = CarManager.get_active()
	if current_car == null:
		current_car = get_tree().get_first_node_in_group("car")
	
	if current_car != null:
		default_position = current_car.global_position
		# Unregister BEFORE freeing so CarManager doesn't briefly
		# fall back to it during the await.
		CarManager.unregister(current_car)
		current_car.queue_free()
	
	# Allow Godot to completely remove the old car from memory
	await get_tree().create_timer(1.0).timeout
	
	# 2. Instantiate and add the new car
	var d = load_and_cache(path + "/scene.tscn").instantiate()
	Helper.get_ancestor(self, 2).add_child(d)
	d.global_position = default_position + Vector3(0, 5, 0)
	
	# 3. Make sure it's in the "car" group (other scripts look for it there)
	if not d.is_in_group("car"):
		d.add_to_group("car")
	
	# 4. Force start the engine and enable control IMMEDIATELY
	if "Controlled" in d:
		d.Controlled = true
	if d.has_method("start_engine"):
		d.start_engine()
	
	# 5. Register with CarManager and explicitly activate it.
	# Car._ready() may have already registered it, but register() is idempotent.
	CarManager.register(d)
	CarManager.set_active(d)
	
	var car: Car = d
	
	# 6. Tell the rest of the UI to refresh against the new car.
	# If your debug.gd is hooked to CarManager.active_car_changed,
	# reload() will already have run by now — but calling it again is safe.
	get_parent().reload()
	
	var manipulator = get_parent().get_node_or_null("controls manipulator")
	if manipulator and manipulator.has_method("setcar"):
		if "car" in manipulator:
			manipulator.car = car
		manipulator.setcar()
	
	# Power graph
	var power_graph = get_parent().get_node("power_graph")
	if "car" in power_graph:
		power_graph.car = car
	power_graph.Generation_Range = float(int(float(car.RPMLimit / 1000.0)) * 1000 + 1000)
	power_graph.Draw_RPM = car.IdleRPM
	# draw.gd._ready() now auto-fits draw_scale to the new car's peaks,
	# so we no longer need a second call to re-draw with a corrected scale.
	power_graph._ready()
	
	# Tacho
	var tacho = get_parent().get_node("tacho")
	if "car" in tacho:
		tacho.car = car
	tacho.Redline = int(float(car.RPMLimit / 1000.0)) * 1000
	tacho.RPM_Range = int(float(car.RPMLimit / 1000.0)) * 1000 + 2000
	tacho.Turbo_Visible = car.TurboEnabled
	tacho.Max_PSI = car.MaxPSI * car.TurboAmount
	tacho._ready()
	
	canclick = true
	swap_car_button.visible = true

func _ready():
	swap_car_button.pressed.connect(_on_button_pressed)
	
	for i: String in DirAccess.get_directories_at(pathh):
		var but = button.duplicate()
		$scroll/container.add_child(but)
		but.visible = true
		but.get_node("carname").text = i
		but.get_node("icon").texture = load(pathh + "/" + i + "/thumbnail.png")
		but.pressed.connect(swapcar.bind(pathh + "/" + i))


func _input(_event):
	if Input.is_action_just_pressed("ui_cancel"):
		visible = false


func _on_button_pressed():
	swap_car_button.release_focus()
	if visible:
		visible = false
	else:
		Input.action_press("ui_cancel")
		await get_tree().create_timer(0.1).timeout
		
		Input.action_release("ui_cancel")
		visible = true
