@tool
extends Node

## Vehicle-physics math autoload.
##
## Historically [method multivariate] held its own copy of the engine torque
## curve while [Car.simulate_engine] held an identical copy — guaranteed to
## drift apart eventually. The implementation now delegates to [EngineModel]
## so the dyno graph and the runtime simulation read from the same math.
## The signature is preserved so [code]draw.gd[/code] doesn't change.



func multivariate(RiseRPM,TorqueRise,BuildUpTorque,EngineFriction,EngineDrag,OffsetTorque,RPM,DeclineRPM,DeclineRate,FloatRate,PSI,TurboAmount,EngineCompressionRatio,TEnabled,VVTRPM,VVT_BuildUpTorque,VVT_TorqueRise,VVT_RiseRPM,VVT_OffsetTorque,VVT_FloatRate,VVT_DeclineRPM,VVT_DeclineRate,SCEnabled,SCRPMInfluence,BlowRate,SCThreshold,DeclineSharpness,VVT_DeclineSharpness) -> float:
	# Pack the flat argument list into the shared CurveParams struct and
	# delegate to the dyno path of EngineModel.
	var p := EngineModel.CurveParams.new()
	p.build_up_torque        = BuildUpTorque
	p.torque_rise            = TorqueRise
	p.rise_rpm               = RiseRPM
	p.offset_torque          = OffsetTorque
	p.float_rate             = FloatRate
	p.decline_rate           = DeclineRate
	p.decline_rpm            = DeclineRPM
	p.decline_sharpness      = DeclineSharpness
	p.vvt_rpm                = VVTRPM
	p.vvt_build_up_torque    = VVT_BuildUpTorque
	p.vvt_torque_rise        = VVT_TorqueRise
	p.vvt_rise_rpm           = VVT_RiseRPM
	p.vvt_offset_torque      = VVT_OffsetTorque
	p.vvt_float_rate         = VVT_FloatRate
	p.vvt_decline_rate       = VVT_DeclineRate
	p.vvt_decline_rpm        = VVT_DeclineRPM
	p.vvt_decline_sharpness  = VVT_DeclineSharpness
	p.engine_friction        = EngineFriction
	p.engine_drag            = EngineDrag
	p.engine_compression_ratio = EngineCompressionRatio
	p.psi                    = PSI
	p.max_psi                = PSI
	p.turbo_amount           = TurboAmount
	p.turbo_enabled          = TEnabled
	p.supercharger_enabled   = SCEnabled
	p.sc_rpm_influence       = SCRPMInfluence
	p.blow_rate              = BlowRate
	p.sc_threshold           = SCThreshold
	return EngineModel.torque_dyno(p, RPM)


func fastest_wheel(array):
	var val := -INF
	var obj
	for i in array:
		if abs(i.absolute_wv) > val:
			val = abs(i.absolute_wv)
			obj = i
	return obj


func slowest_wheel(array):
	var val := INF
	var obj
	for i in array:
		if abs(i.absolute_wv) < val:
			val = abs(i.absolute_wv)
			obj = i
	return obj


func alignAxisToVector(xform, norm): # i named this literally out of blender
	xform.basis.y = norm
	xform.basis.x = -xform.basis.z.cross(norm)
	xform.basis = xform.basis.orthonormalized()
	return xform


func suspension(own,maxcompression,incline_free,incline_impact,rest,      elasticity,damping,damping_rebound     ,linearz,g_range,located,hit_located,weight,ground_bump,ground_bump_height) -> float:
	own.get_node("geometry").global_position = own.get_collision_point()
	own.get_node("geometry").position.y -= (ground_bump*ground_bump_height)
	own.get_node("geometry").position.y = max(own.get_node("geometry").position.y, -g_range)
	own.get_node("velocity").global_transform = alignAxisToVector(own.get_node("velocity").global_transform,own.get_collision_normal())
	own.get_node("velocity2").global_transform = alignAxisToVector(own.get_node("velocity2").global_transform,own.get_collision_normal())
	
	own.angle = (own.get_node("geometry").rotation_degrees.z -(-own.c_camber*float(own.position.x>0.0) + own.c_camber*float(own.position.x<0.0)) +(-own.cambered*float(own.position.x>0.0) + own.cambered*float(own.position.x<0.0))*own.A_Geometry2)/90.0
	
	var incline: float = (own.get_collision_normal()-(own.global_transform.basis.orthonormalized() * Vector3(0,1,0))).length()
	
	incline = ((incline/(1.0-incline_free)) - incline_free) * incline_impact
	incline = clamp(incline, 0.0, 1.0)
	
	own.get_node("geometry").position.y = min(own.get_node("geometry").position.y, -g_range +maxcompression*(1.0-incline))
	
	var damp_variant = damping_rebound
	if linearz<0:
		damp_variant = damping
	
	var compressed = g_range -(located - hit_located).length() - (ground_bump*ground_bump_height)
	var compressed2 = g_range -(located - hit_located).length() - (ground_bump*ground_bump_height)
	compressed2 -= maxcompression + (ground_bump*ground_bump_height)
	
	var j = compressed-rest
	j = max(j, 0.0)
	
	compressed2 = max(compressed2, 0.0)
	
	var elasticity2 = elasticity*(1.0-incline) + (weight)*incline
	var damping2 = damp_variant*(1.0-incline) + (weight/10.0)*incline
	var elasticity3 = weight
	var damping3 = weight/10.0
	var suspforce = j*elasticity2
	
	if compressed2>0.0:
		suspforce -= linearz*damping3
		suspforce += compressed2*elasticity3
	
	suspforce -= linearz*damping2
	own.rd = compressed
	
	suspforce = max(suspforce, 0.0)
	
	return suspforce
