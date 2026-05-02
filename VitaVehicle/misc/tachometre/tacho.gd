extends Control

var currentrpm := 0.0
var currentpsi := 0.0

@export var Turbo_Visible := false
@export var Max_PSI := 13.0
@export var RPM_Range := 9000.0
@export var Redline := 7000.0

var generated := []

func _ready():
	$turbo.visible = Turbo_Visible
	$turbo/maxpsi.text = str(int(Max_PSI))
	if len(generated)>0:
		for i in generated:
			i.queue_free()
		generated.clear()
	
	var lowangle := -120.0
	var highangle := 120.0
	
	var maximum := int(RPM_Range/1000.0)
	var red := Redline/1000.0 -0.001
	
	for i in range(maximum + 1):
		var dist := float(i)/float(maximum)
		var dist2 := (float(i)+0.25)/float(maximum)
		var dist3 := (float(i)+0.5)/float(maximum)
		var dist4 := (float(i)+0.75)/float(maximum)
		
		var d := $tacho/major.duplicate(true)
		$tacho.add_child(d)
		d.rotation_degrees = lowangle*(1.0-dist) + highangle*dist
		d.visible = true
		d.get_node("tetx").text = str(i)
		d.get_node("tetx").rotation_degrees = -d.rotation_degrees
		generated.append(d)
		
		if float(i) > red:
			d.color = Color(1, 0, 0)
		
		if len(d.get_node("tetx").text)>1:
			d.get_node("tetx").position.y += 5
		
		if not i == maximum:
			d = $tacho/minor.duplicate(true)
			$tacho.add_child(d)
			d.rotation_degrees = lowangle*(1.0-dist2) + highangle*dist2
			d.visible = true
			generated.append(d)
			if float(i+0.25)>red:
				d.color = Color(1,0,0)
			
			d = $tacho/minor.duplicate(true)
			$tacho.add_child(d)
			d.rotation_degrees = lowangle*(1.0-dist3) + highangle*dist3
			d.visible = true
			generated.append(d)
			if float(i+0.5)>red:
				d.color = Color(1,0,0)
			
			d = $tacho/minor.duplicate(true)
			$tacho.add_child(d)
			d.rotation_degrees = lowangle*(1.0-dist4) + highangle*dist4
			d.visible = true
			generated.append(d)
			if float(i+0.75)>red:
				d.color = Color(1,0,0)

func _process(_delta):
	# 1. Dynamically retrieve the currently active car
	var active_car = CarManager.get_active()
	
	# 2. Check if the active car is valid before trying to read it
	if is_instance_valid(active_car):
		# Fetch the live engine data from the car instance
		if "rpm" in active_car:
			currentrpm = active_car.rpm
		elif "EngineRPM" in active_car:
			currentrpm = active_car.get("EngineRPM")
			
		if "turbopsi" in active_car:
			currentpsi = active_car.turbopsi
	else:
		# If no car is found/active, smoothly drop to 0 instead of getting stuck
		currentrpm = move_toward(currentrpm, 0.0, 50.0)
		currentpsi = move_toward(currentpsi, 0.0, 0.5)

	# Update needles
	$tacho/needle.rotation_degrees = remap(abs(currentrpm), 0.0, RPM_Range, -120.0, 120.0)
	$turbo/needle.rotation_degrees = remap(currentpsi, 0.0, Max_PSI, -90.0, 90.0)
	$turbo/needle.rotation_degrees = max($turbo/needle.rotation_degrees, -90.0)
