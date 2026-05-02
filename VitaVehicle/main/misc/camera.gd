extends Marker3D

var default_cam_pos: Vector3
var can_drag := false
var just_resetted := false

@export var mobile_controls := NodePath()
# 1. Change this to a direct Node reference instead of a hardcoded NodePath
var car: Node = null
@export var debugger := NodePath()

var drag_velocity := Vector2(0,0)
var last_pos := Vector2(0,0)

var resetdel := 0
var default_zoom: float


#region internal
func _ready():
	default_cam_pos = $orbit/Camera.position
	default_zoom = default_cam_pos.z
	
	# 2. Connect to the CarManager signal to dynamically update the car reference
	CarManager.active_car_changed.connect(_on_active_car_changed)
	
	# 3. Set the initial car if there is already an active one
	car = CarManager.get_active()


func _on_active_car_changed(new_car: Node) -> void:
	# Updates the camera's target car whenever you cycle
	car = new_car


func _process(_delta):
	# Allow the debugger to override if necessary
	if has_node(debugger):
		car = get_node(debugger).car
		
	# 4. Use is_instance_valid() to verify our car reference is active and loaded
	if is_instance_valid(car):
		if car.has_node("CAMERA_CENTRE"):
			look_at(car.get_node("CAMERA_CENTRE").global_position, Vector3(0,1,0))
			position = car.get_node("CAMERA_CENTRE").global_position
		else:
			look_at(car.position, Vector3(0,1,0))
			position = car.position
		translate_object_local(Vector3(0,0,14.5))
		
		$orbit.global_position = car.global_position
		$orbit/Camera.position = default_cam_pos - $orbit.position


func _physics_process(_delta):
	# 5. Only process camera orbital controls if we are following a valid car
	if not is_instance_valid(car):
		return
		
	default_cam_pos.z += 0.05 * Input.get_axis("zoom_in", "zoom_out")
	$orbit.rotation_degrees.y += 1 * Input.get_axis("CAM_orbit_right", "CAM_orbit_left")
	
	if Input.is_action_pressed("CAM_orbit_reset"):
		$orbit.rotation_degrees.y = 0.0
		default_cam_pos.z = default_zoom
	
	resetdel -= 1


func _input(event):
	if not is_instance_valid(car):
		return

	if not str(mobile_controls) == "":
		if get_node(mobile_controls).visible:
			can_drag = true
			for i in get_node(mobile_controls).get_children():
				if i.is_pressed():
					can_drag = false
			if event is InputEventScreenTouch and can_drag:
				last_pos = event.position
				if not event.is_pressed():
					if resetdel>0:
						$orbit.rotation_degrees.y = 0.0
						default_cam_pos.z = default_zoom
						just_resetted = true
					resetdel = 15
			else:
				just_resetted = false
			
			if event is InputEventScreenDrag:
				if can_drag and not just_resetted:
					drag_velocity.x = event.position.x - last_pos.x
					drag_velocity.y = event.position.y - last_pos.y
					last_pos = event.position
					
					if abs(drag_velocity.y)>Constants.CAM_DRAG_UNLOCK_VELOCITY:
						default_cam_pos.z += drag_velocity.y/200.0
					if abs(drag_velocity.x)>Constants.CAM_DRAG_UNLOCK_VELOCITY:
						$orbit.rotation_degrees.y -= drag_velocity.x/2.0
					
					resetdel = -1
#endregion internal
