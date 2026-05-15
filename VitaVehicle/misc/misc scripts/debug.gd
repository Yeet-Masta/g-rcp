class_name Debug extends Control



@export var start_engine_button: Button

var changed_graph_size = Vector2(0,0)
var car: Car



#region methods
func _on_start_engine_pressed():
	if !car: return
	car.start_engine()


func toggle_forces():
	Input.action_press("toggle_debug_mode")


func reload():
	# Always clear stale wheel refs first, even if we're about to bail.
	$vgs.clear()
	
	var active := CarManager.get_active()
	if active != null:
		car = active
	else:
		car = get_tree().get_first_node_in_group("car")
	if !car: return
	
	for d in car.get_children():
		if "TyreSettings" in d:
			$vgs.append_wheel(d.position, d.TyreSettings, d)
	
	for i in $power_graph.get_script().get_script_property_list():
		if i["name"] != "peakhp" and i["name"] != "tr" and i["name"] != "hp" and i["name"] != "skip" and i["name"] != "scale":
			if i["name"] in car:
				$power_graph.set(i["name"], car.get(i["name"]))
	
	# These exports don't exist by name on Car (it has RPMLimit / IdleRPM),
	# so the loop above can't copy them. Without these explicit assignments,
	# cycling cars leaves the previous car's RPM range on the graph and the
	# curves come out distorted.
	$power_graph.Generation_Range = float(int(float(car.RPMLimit / 1000.0)) * 1000 + 1000)
	$power_graph.Draw_RPM = car.IdleRPM
	
	$power_graph._ready()
	
	if has_node("tacho"):
		$tacho.Redline = int(float(car.RPMLimit / 1000.0)) * 1000
		$tacho.RPM_Range = int(float(car.RPMLimit / 1000.0)) * 1000 + 2000
		$tacho.Turbo_Visible = car.TurboEnabled
		$tacho.Max_PSI = car.MaxPSI * car.TurboAmount
		$tacho._ready()
#endregion methods


#region internal
func _ready():
	start_engine_button.pressed.connect(_on_start_engine_pressed)
	# Listen for car cycling so all the UI follows the active car.
	CarManager.active_car_changed.connect(_on_active_car_changed)
	reload()


func _on_active_car_changed(_new_car: Node) -> void:
	reload()


func _physics_process(_delta):
	if !car: return
	
	$vgs.gforce -= ($vgs.gforce - Vector2(car.gforce.x, car.gforce.z)) * 0.5
	
	$tacho/abs.visible = _is_abs_active() and car.brakepedal > 0.1
	$tacho/tcs.visible = car.tcsflash or car.tcsweight > 0
	$tacho/esp.visible = car.espflash


## True if ABS is currently intervening on any wheel (advanced mode) or
## the legacy global pump delay is still counting down (legacy mode).
func _is_abs_active() -> bool:
	if car.abs_delay > 0:
		return true
	for child in car.get_children():
		if "abs_active" in child and child.abs_active:
			return true
	return false


func _process(delta):
	if delta > 0:
		get_node("container/fps").text = "fps: " + str(Engine.get_frames_per_second())
		if car:
			$sw.rotation_degrees = car.final_steer * 380.0
			$sw_desired.rotation_degrees = car.steer_target * 380.0
			if car._wheel_node != null and car._wheel_node.is_device_connected():
				$sw.rotation_degrees = car.final_steer * (car._wheel_node.wheel_range_degrees/2)
				$sw_desired.rotation_degrees = car.steer_target * (car._wheel_node.wheel_range_degrees/2)
			if car.Debug_Mode:
				get_node("container/weight_dist").text = "weight distribution: F%f/R%f" % [car.weight_dist[0] * 100,car.weight_dist[1] * 100]
			else:
				get_node("container/weight_dist").text = "[ enable Debug_Mode or press F to\nfetch weight distribution ]"
	
	if changed_graph_size != $power_graph.size:
		changed_graph_size = $power_graph.size
		$power_graph._ready()
	
	if !car: return
	
	start_engine_button.visible = !car.is_ignition_on
	
	$throttle.bar_scale = car.gaspedal
	$brake.bar_scale = car.brakepedal
	$handbrake.bar_scale = car.handbrakepull
	$clutch.bar_scale = car.clutchpedalreal
	if car.fuel and car.fuel.max_fuel > 0.0:
		$fuel.bar_scale = car.current_fuel / car.fuel.max_fuel
	else:
		$fuel.bar_scale = 0.0
	
	var car_speed := car.linear_velocity.length()
	$tacho/speedk.text = "KMH: " + str(int(car_speed*Constants.UNIT_TO_KMH))
	$tacho/speedm.text = "MPH: " + str(int(Convert.kmh_to_mph(car_speed*Constants.UNIT_TO_KMH)))
	
	var hpunit := "hp"
	if $power_graph.Power_Unit == 1:
		hpunit = "bhp"
	elif $power_graph.Power_Unit == 2:
		hpunit = "ps"
	elif $power_graph.Power_Unit == 3:
		hpunit = "kW"
	$hp.text = "Power: %s %s @ %s RPM" % [String.num($power_graph.peakhp[0], 1), hpunit ,String.num($power_graph.peakhp[1], 1)]
	
	var tqunit := "ft⋅lb"
	if $power_graph.Torque_Unit == 1:
		tqunit = "nm"
	elif $power_graph.Torque_Unit == 2:
		tqunit = "kg/m"
	$tq.text = "Torque: %s %s @ %s RPM" % [String.num($power_graph.peaktq[0], 1), tqunit ,String.num($power_graph.peaktq[1], 1)]
	
	$power_graph/rpm.position.x = (car.rpm/$power_graph.Generation_Range)*$power_graph.size.x -1.0
	$power_graph/redline.position.x = (car.RPMLimit/$power_graph.Generation_Range)*$power_graph.size.x -1.0
	
	$g.text = "Gs:\nx %s\ny %s\nz %s" % [String.num(car.gforce.x, 2), String.num(car.gforce.y, 2), String.num(car.gforce.z, 2)]
	
	$tacho.currentpsi = car.turbopsi*(car.TurboAmount)
	$tacho.currentrpm = car.rpm
	$tacho/rpm.text = str(int(car.rpm))
	
	$tacho/rpm.self_modulate = Color.RED if car.rpm < 0 else Color.WHITE
	
	if car.gear == 0:
		$tacho/gear.text = "N"
	elif car.gear == -1:
		$tacho/gear.text = "R"
	else:
		if car.transmission_type == Car.TransmissionType.AUTOMATIC or car.transmission_type == Car.TransmissionType.CONTINUOUSLY_VARIABLE:
			$tacho/gear.text = "D"
		else:
			$tacho/gear.text = str(car.gear)
#endregion internal
