extends Node3D

var pitch := 0.0
var volume := 0.0
var fade := 0.0

var vacuum := 0.0
var maxfades := 0.0

@export var car: Car

@export var pitch_calibrate := 7500.0
@export var vacuum_crossfade := 0.7
@export var vacuum_loudness := 4.0
@export var crossfade_vvt := 5.0
@export var crossfade_throttle := 0.0
@export var crossfade_influence := 5.0
@export var overall_volume := 1.0

var pitch_influence := 1.0

var childcount := 0


#region methods
func play():
	for i in get_children():
		i.play()
#endregion methods


#region internal
func _ready():
	play()
	childcount = get_child_count()
	maxfades = float(childcount-1.0)
	# Set the 3D-audio ceiling ONCE. Re-writing this every physics frame
	# alongside volume_db is what was causing the engine sound to slowly
	# drift to deafening levels until a car swap reset the nodes.
	for i in get_children():
		i.max_db = 3.0

func _physics_process(_delta):
	if !car.is_ignition_on:
		for i in get_children():
			i.volume_db = -60.0
		return
	
	pitch = abs(car.rpm*pitch_influence)/pitch_calibrate
	
	volume = 0.5 +car.throttle*0.5
	fade = (get_node("100500").pitch_scale  -0.22222)*(crossfade_influence +float(car.throttle)*crossfade_throttle +float(car.is_vvt_active())*crossfade_vvt)
	
	fade = clamp(fade, 0.0, childcount-1.0)
	
	vacuum = (car.gaspedal-car.throttle)*4.0
	vacuum = clamp(vacuum, 0.0, 1.0)
	
	var sfk := 1.0-(vacuum*car.throttle)
	sfk = max(sfk, vacuum_crossfade)
	
	fade *= sfk
	
	volume += (1.0-sfk)*vacuum_loudness
	
	# Clamp the additive volume term so vacuum_loudness can't drive the bus
	# above unity gain. Without this, volume could reach ~5.0 (= +14 dB),
	# which on top of crossfade overlaps causes cumulative loudness drift.
	volume = clamp(volume, 0.0, 1.0)
	
	for i in get_children():
		var maxvol := float(i.get_child(0).name)/100.0
		var maxpitch := float(i.name)/100000.0 # TODO
		
		var index := float(i.get_index())
		var dist := pow(absf(index - fade), 2)
		
		var vol := 1.0 - dist
		vol = clamp(vol, 0.0, 1.0)
		var db := linear_to_db((vol*maxvol)*(volume*(overall_volume)))
		db = max(db, -60.0)
		
		i.volume_db = db
		var pit := absf(pitch*maxpitch)
		pit = clamp(pit, 0.01, 5.0)
		i.pitch_scale = pit
#endregion internal
