extends Node3D

#region Exports
@export var car: Node  # Replace with your actual Car class type if available
@export var overall_volume: float = 1.0
@export var pitch_calibrate: float = 7500.0
@export var pitch_offset: float = 0.22222  # Replaces hardcoded magic number
@export var crossfade_influence: float = 5.0
@export var crossfade_throttle: float = 0.0
@export var crossfade_vvt: float = 5.0
@export_range(0.1, 5.0) var crossfade_width: float = 1.0  # Controls layer overlap
@export var vacuum_crossfade: float = 0.7
@export var vacuum_loudness: float = 4.0
@export var vacuum_sensitivity: float = 4.0
@export var min_pitch_scale: float = 0.01
@export var max_pitch_scale: float = 5.0
@export var silence_db: float = -60.0
@export var max_db_ceiling: float = 3.0
@export var reference_player: AudioStreamPlayer3D  # Optional: specific node to track for fade calc

# New tuning
@export_range(0.0, 1.0) var fade_pos_smoothing: float = 0.3  # 0 = no smoothing, 1 = instant. Lower = smoother.
@export var normalize_power: bool = true  # Equal-power normalization across overlapping layers
#endregion

const HALF_PI: float = PI * 0.5

var pitch_influence: float = 1.0
var audio_layers: Array[AudioLayer] = []
var max_fade_index: float = 0.0
var _smoothed_fade_pos: float = 0.0
var _smoothed_fade_pos_initialized: bool = false

class AudioLayer:
	var player: AudioStreamPlayer3D
	var index: float
	var max_volume: float
	var max_pitch: float
	var vol_factor: float = 0.0  # Scratch space for per-frame calc

func _ready() -> void:
	if not car:
		push_error("Car reference not assigned in Crossfade node.")
		set_physics_process(false)
		return
	
	_setup_audio_layers()
	max_fade_index = float(audio_layers.size() - 1)
	play()

func _setup_audio_layers() -> void:
	for child in get_children():
		if child is AudioStreamPlayer3D:
			var layer = AudioLayer.new()
			layer.player = child
			layer.index = float(child.get_index())
			
			# Parse max_volume from first child's name (legacy compatibility)
			if child.get_child_count() > 0:
				var vol_str = child.get_child(0).name
				layer.max_volume = float(vol_str) / 100.0 if vol_str.is_valid_float() else 1.0
			else:
				layer.max_volume = 1.0
			
			# Parse max_pitch from node name (legacy compatibility)
			var pitch_str = child.name
			layer.max_pitch = float(pitch_str) / 100000.0 if pitch_str.is_valid_float() else 1.0
			
			# Set ceiling ONCE to prevent cumulative loudness drift
			child.max_db = max_db_ceiling
			audio_layers.append(layer)
	
	if audio_layers.is_empty():
		push_warning("No AudioStreamPlayer3D children found for crossfading.")

func play() -> void:
	for layer in audio_layers:
		if not layer.player.playing:
			layer.player.play()

# Equal-power crossfade weight: raised cosine.
# Returns 1.0 at dist=0, 0.0 at dist>=1, with zero slope at both ends.
# Two adjacent layers with this curve sum to constant POWER (sum of squares = 1),
# which is the correct shape for blending phase-incoherent material like engine recordings.
func _equal_power_weight(dist: float) -> float:
	if dist >= 1.0:
		return 0.0
	# cos(dist * pi/2) gives an amplitude curve where amplitude^2 sums to 1
	# between two adjacent layers, preserving perceived loudness through the crossover.
	var c: float = cos(dist * HALF_PI)
	return c * c  # Squared so the "amplitude" applied later is cos(dist*pi/2)

func _physics_process(_delta: float) -> void:
	if not car or not car.is_ignition_on:
		for layer in audio_layers:
			layer.player.volume_db = silence_db
		# Reset smoothing so we don't carry stale state into next ignition
		_smoothed_fade_pos_initialized = false
		return
	
	# Base pitch from RPM
	var current_pitch: float = absf(car.rpm * pitch_influence) / pitch_calibrate
	
	# Base volume from throttle (0.5 idle -> 1.0 full throttle)
	var current_volume: float = 0.5 + car.throttle * 0.5
	
	# Crossfade position calculation
	var ref_pitch: float = reference_player.pitch_scale if reference_player else current_pitch
	var fade_mod: float = crossfade_influence + car.throttle * crossfade_throttle + float(car.is_vvt_active()) * crossfade_vvt
	var fade_pos: float = (ref_pitch - pitch_offset) * fade_mod
	fade_pos = clamp(fade_pos, 0.0, max_fade_index)
	
	# Vacuum/overrun calculation
	var vacuum: float = clamp((car.gaspedal - car.throttle) * vacuum_sensitivity, 0.0, 1.0)
	var sfk: float = max(1.0 - (vacuum * car.throttle), vacuum_crossfade)
	
	fade_pos *= sfk
	current_volume += (1.0 - sfk) * vacuum_loudness
	current_volume = clamp(current_volume, 0.0, 1.0)
	
	# Smooth fade_pos over time to kill zipper noise from RPM jitter
	# (gear shifts, wheelspin oscillation, tach noise can all cause sub-frame wobble
	#  right at a crossover boundary, which becomes audible as flutter).
	if _smoothed_fade_pos_initialized:
		_smoothed_fade_pos = lerp(_smoothed_fade_pos, fade_pos, fade_pos_smoothing)
	else:
		_smoothed_fade_pos = fade_pos
		_smoothed_fade_pos_initialized = true
	
	# Pass 1: compute raw equal-power weights for each layer
	var sum_sq: float = 0.0
	for layer in audio_layers:
		var dist: float = absf(layer.index - _smoothed_fade_pos) / crossfade_width
		# Equal-power weight: this is the squared cosine, i.e., the POWER contribution.
		# We take its sqrt below to get the amplitude (volume) we actually apply.
		var power_weight: float = _equal_power_weight(dist)
		layer.vol_factor = power_weight
		sum_sq += power_weight
	
	# Pass 2: normalize so total power == 1 across all contributing layers
	# Without this, when 3+ layers overlap (wide crossfade_width) you'd get a loudness
	# bump in the middle of the range vs the edges. With it, sum of squared amplitudes
	# is always 1.0 regardless of how many layers contribute.
	var norm: float = 1.0
	if normalize_power and sum_sq > 0.0001:
		norm = 1.0 / sum_sq
	
	# Pass 3: apply to layers 
	for layer in audio_layers:
		# Convert power contribution -> amplitude (the actual volume multiplier).
		# Since power = amplitude^2, amplitude = sqrt(power).
		var amplitude: float = sqrt(layer.vol_factor * norm)
		
		var final_vol: float = amplitude * layer.max_volume * current_volume * overall_volume
		var db: float = linear_to_db(final_vol)
		db = max(db, silence_db)
		layer.player.volume_db = db
		
		var final_pitch: float = absf(current_pitch * layer.max_pitch)
		final_pitch = clamp(final_pitch, min_pitch_scale, max_pitch_scale)
		layer.player.pitch_scale = final_pitch
