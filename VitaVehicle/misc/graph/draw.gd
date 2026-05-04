extends Control

@export_enum("ft⋅lb", "nm", "kg/m") var Torque_Unit := 1
@export_enum("hp", "bhp", "ps", "kW") var Power_Unit := 0


#engine
@export var RevSpeed := 2.0 # Flywheel lightness
@export var EngineFriction := 18000.0
@export var EngineDrag := 0.006
@export var ThrottleResponse := 0.5

#ECU
@export var IdleRPM := 800.0 # set this beyond the rev range to disable it, set it to 0 to use this vvt state permanently
@export var RPMLimit := 7000.0 # set this beyond the rev range to disable it, set it to 0 to use this vvt state permanently
@export var VVTRPM := 4500.0 # set this beyond the rev range to disable it, set it to 0 to use this vvt state permanently

#torque normal state
@export var BuildUpTorque := 0.0035
@export var TorqueRise := 30.0
@export var RiseRPM := 1000.0
@export var OffsetTorque := 110
@export var FloatRate := 0.1
@export var DeclineRate := 1.5
@export var DeclineRPM := 3500.0
@export var DeclineSharpness := 1.0

#torque @export variable valve timing triggered
@export var VVT_BuildUpTorque := 0.0
@export var VVT_TorqueRise := 60.0
@export var VVT_RiseRPM := 1000.0
@export var VVT_OffsetTorque := 70
@export var VVT_FloatRate := 0.1
@export var VVT_DeclineRate := 2.0
@export var VVT_DeclineRPM := 5000.0
@export var VVT_DeclineSharpness := 1.0

@export var TurboEnabled := false
@export var MaxPSI := 8.0
@export var TurboAmount := 1 # Turbo power multiplication.
@export var EngineCompressionRatio := 8.0 # Piston travel distance
@export var SuperchargerEnabled := false # Enables supercharger
@export var SCRPMInfluence := 1.0
@export var BlowRate := 35.0
@export var SCThreshold := 6.0


@export var draw_scale := 0.005
@export var Generation_Range := 7000.0
@export var Draw_RPM := 800.0

var peakhp := [0.0,0.0]
var peaktq := [0.0,0.0]

func _ready():
	# Reset all per-graph state so nothing from the previous car can leak in.
	peakhp = [0.0,0.0]
	peaktq = [0.0,0.0]
	$torque.clear_points()
	$power.clear_points()
	
	# --- Pass 1: find the peaks so we can pick a draw_scale that fits this
	# car's curves into the graph regardless of what the previous car's
	# scale was. We DON'T add points or move the peak markers yet, because
	# the y-coordinates depend on draw_scale, which we don't know yet.
	for i in range(Generation_Range):
		if i > Draw_RPM:
			var tq = VitaVehicleSimulation.multivariate(RiseRPM,TorqueRise,BuildUpTorque,EngineFriction,EngineDrag,OffsetTorque,i,DeclineRPM,DeclineRate,FloatRate,MaxPSI,TurboAmount,EngineCompressionRatio,TurboEnabled,VVTRPM,VVT_BuildUpTorque,VVT_TorqueRise,VVT_RiseRPM,VVT_OffsetTorque,VVT_FloatRate,VVT_DeclineRPM,VVT_DeclineRate,SuperchargerEnabled,SCRPMInfluence,BlowRate,SCThreshold,DeclineSharpness,VVT_DeclineSharpness)
			var hp = (i/5252.0)*tq
			
			if Torque_Unit == 1:
				tq *= 1.3558179483
			elif Torque_Unit == 2:
				tq *= 0.138255
			
			if Power_Unit == 1:
				hp *= 0.986
			elif Power_Unit == 2:
				hp *= 1.01387
			elif Power_Unit == 3:
				hp *= 0.7457
			
			if hp > peakhp[0]:
				peakhp = [hp, i]
			if tq > peaktq[0]:
				peaktq = [tq, i]
	
	# Auto-fit draw_scale to the peak so the curves always fill the graph.
	# Leaves a small headroom (0.95) so the peak isn't drawn at y = 0.
	var peak: float = max(peaktq[0], peakhp[0])
	if peak > 0.0:
		draw_scale = 0.95 / peak
	
	# --- Pass 2: now that draw_scale is correct, draw the lines and place
	# the peak markers using the same scale.
	var skip = 0
	for i in range(Generation_Range):
		if i > Draw_RPM:
			var tq = VitaVehicleSimulation.multivariate(RiseRPM,TorqueRise,BuildUpTorque,EngineFriction,EngineDrag,OffsetTorque,i,DeclineRPM,DeclineRate,FloatRate,MaxPSI,TurboAmount,EngineCompressionRatio,TurboEnabled,VVTRPM,VVT_BuildUpTorque,VVT_TorqueRise,VVT_RiseRPM,VVT_OffsetTorque,VVT_FloatRate,VVT_DeclineRPM,VVT_DeclineRate,SuperchargerEnabled,SCRPMInfluence,BlowRate,SCThreshold,DeclineSharpness,VVT_DeclineSharpness)
			var hp = (i/5252.0)*tq
			
			if Torque_Unit == 1:
				tq *= 1.3558179483
			elif Torque_Unit == 2:
				tq *= 0.138255
			
			if Power_Unit == 1:
				hp *= 0.986
			elif Power_Unit == 2:
				hp *= 1.01387
			elif Power_Unit == 3:
				hp *= 0.7457
			
			var tq_p = Vector2((i/Generation_Range)*size.x,size.y -(tq*size.y)*draw_scale)
			var hp_p = Vector2((i/Generation_Range)*size.x,size.y -(hp*size.y)*draw_scale)
			
			# Place peak markers when we hit the (already-known) peak rpm.
			if i == int(peakhp[1]):
				$power/peak.position = hp_p
			if i == int(peaktq[1]):
				$torque/peak.position = tq_p
			
			skip -= 1
			if skip <= 0:
				$torque.add_point(tq_p)
				$power.add_point(hp_p)
				skip = 100
