## Spawns multiple cars into the world and registers them with [CarManager].
##
## Drop this node anywhere in your scene (typically as a sibling of the
## current car). Configure [member car_scenes] with the [PackedScene]s of
## the cars you want available.
##
## Default keys:
##   [b]F6[/b]  — spawn another instance of the active car
##   [b]Tab[/b] — cycle control to the next car (set up the action in input map)
##
## You can also call [method spawn_at] from other scripts (e.g. the freecam
## or a command panel).

extends Node3D



## A car scene to spawn (its root must inherit from [Car]).
@export var car_scenes: Array[PackedScene] = []

## Default spawn offset relative to the active car.
@export var spawn_offset := Vector3(6, 1.0, 1.0)

## If true, listens for the actions below and spawns/cycles in response.
@export var enable_input := true

## Input action that spawns a new car at the active car's position.
@export var spawn_action := "spawn_car"

## Input action that cycles control to the next spawned car.
@export var cycle_action := "cycle_active_car"



func _ready() -> void:
	# Make sure the existing scene car (if any) is registered so cycling works
	# with whatever was placed by hand.
	for c in get_tree().get_nodes_in_group("car"):
		CarManager.register(c)


func _unhandled_input(event: InputEvent) -> void:
	if not enable_input:
		return
	
	# The 'false' argument disables echo events
	if InputMap.has_action(spawn_action) and event.is_action_pressed(spawn_action, false):
		#print("spawn_action is being pressed")
		spawn_default()
		
	elif InputMap.has_action(cycle_action) and event.is_action_pressed(cycle_action, false):
		#print("cycle_action is being pressed")
		CarManager.cycle_active(1)
		get_viewport().set_input_as_handled()
	elif InputMap.has_action("despawn_car") and event.is_action_pressed("despawn_car", false):
		despawn()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Spawns the first car in [member car_scenes]. Returns the new car or null.
func spawn_default() -> Node:
	if car_scenes.is_empty():
		push_warning("CarSpawner: no car_scenes configured.")
		return null
	return spawn_scene(car_scenes[0])


## Spawns a specific [PackedScene] near the active car.
func spawn_scene(scene: PackedScene) -> Node:
	if scene == null:
		return null
	var pos := _default_spawn_position()
	var rot := _default_spawn_rotation()
	return spawn_at(scene, pos, rot)


## Spawns a car at an explicit world position and Y rotation. Returns the car.
func spawn_at(scene: PackedScene, position: Vector3, rotation_y: float = 0.0) -> Node:
	if scene == null:
		return null
	var instance := scene.instantiate()
	# Parent under the same parent as the active car so the world graph stays consistent.
	var parent := _spawn_parent()
	if parent == null:
		push_warning("CarSpawner: no suitable parent found.")
		instance.queue_free()
		return null
	parent.add_child(instance)
	if instance is Node3D:
		(instance as Node3D).global_position = position
		(instance as Node3D).rotation.y = rotation_y
	# Group + manager registration. Many existing scripts look for "car" group.
	if not instance.is_in_group("car"):
		instance.add_to_group("car")
	CarManager.register(instance)
	return instance


## Despawns a specific car (or the active one if null).
func despawn(car: Node = null) -> void:
	var target := car if car != null else CarManager.get_active()
	if target == null:
		return
	CarManager.unregister(target)
	target.queue_free()


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _default_spawn_position() -> Vector3:
	var active := CarManager.get_active()
	if active != null and active is Node3D:
		var t := (active as Node3D).global_transform
		
		# Zero out pitch and roll to keep the spawn horizontal relative to the world
		var forward := -t.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		
		var right := t.basis.x
		right.y = 0.0
		right = right.normalized()
		
		# Position the car to the right/forward/up based on your local offset
		var horizontal_offset = (right * spawn_offset.x) + (forward * spawn_offset.z)
		var vertical_offset = Vector3(0.0, spawn_offset.y, 0.0)
		
		return t.origin + horizontal_offset + vertical_offset
		
	return global_position


func _default_spawn_rotation() -> float:
	var active := CarManager.get_active()
	if active != null and active is Node3D:
		var t := (active as Node3D).global_transform
		
		# Extracts Euler angles (X, Y, Z rotation) in radians.
		# .y returns the exact rotation around the Y axis.
		return t.basis.get_euler().y
		
	return 0.0


func _spawn_parent() -> Node:
	var active := CarManager.get_active()
	if active != null and active.get_parent() != null:
		return active.get_parent()
	# Fallback: current scene root.
	return get_tree().current_scene
