extends Node


@export var this_camera: Camera3D
@onready var original_camera: Camera3D = get_tree().get_first_node_in_group("camera")

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("change_camera"):
		if original_camera.current:
			this_camera.current = true
		else:
			original_camera.current = true
