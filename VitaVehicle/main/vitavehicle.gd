@tool
extends Node

## Vehicle-physics math autoload.
##
## Holds helpers used by [Wheel] and [Car] (suspension, fastest/slowest wheel,
## basis alignment). The old [code]multivariate[/code] torque shim is gone —
## callers (the dyno in [code]draw.gd[/code]) talk to [EngineModel.CurveParams]
## directly now.


func fastest_wheel(array: Array) -> Wheel:
	var val := -INF
	var obj: Wheel = null
	for i in array:
		if absf(i.absolute_wv) > val:
			val = absf(i.absolute_wv)
			obj = i
	return obj


func slowest_wheel(array: Array) -> Wheel:
	var val := INF
	var obj: Wheel = null
	for i in array:
		if absf(i.absolute_wv) < val:
			val = absf(i.absolute_wv)
			obj = i
	return obj


func alignAxisToVector(xform: Transform3D, norm: Vector3) -> Transform3D:
	# i named this literally out of blender
	xform.basis.y = norm
	xform.basis.x = -xform.basis.z.cross(norm)
	xform.basis = xform.basis.orthonormalized()
	return xform


## Suspension force at a single wheel's contact patch.
##
## [param own] is the [Wheel] driving the cast; its cached child nodes
## (geometry / velocity / velocity2) are read off the wheel directly to avoid
## six [code]get_node[/code] string lookups per wheel per frame.
func suspension(own: Wheel, maxcompression: float, incline_free: float, incline_impact: float, rest: float,
				elasticity: float, damping: float, damping_rebound: float,
				linearz: float, g_range: float, located: Vector3, hit_located: Vector3,
				weight: float, ground_bump: float, ground_bump_height: float) -> float:
	var geom: Node3D = own.geom_node
	var vel_node: Node3D = own.velocity_node
	var vel2_node: Node3D = own.velocity2_node

	geom.global_position = own.get_collision_point()
	geom.position.y -= ground_bump * ground_bump_height
	geom.position.y = maxf(geom.position.y, -g_range)
	vel_node.global_transform = alignAxisToVector(vel_node.global_transform, own.get_collision_normal())
	vel2_node.global_transform = alignAxisToVector(vel2_node.global_transform, own.get_collision_normal())

	own.angle = (geom.rotation_degrees.z
				 - (-own.c_camber * float(own.position.x > 0.0) + own.c_camber * float(own.position.x < 0.0))
				 + (-own.cambered * float(own.position.x > 0.0) + own.cambered * float(own.position.x < 0.0)) * own.A_Geometry2
				) / 90.0

	var incline: float = (own.get_collision_normal() - (own.global_transform.basis.orthonormalized() * Vector3(0, 1, 0))).length()

	incline = ((incline / (1.0 - incline_free)) - incline_free) * incline_impact
	incline = clampf(incline, 0.0, 1.0)

	geom.position.y = minf(geom.position.y, -g_range + maxcompression * (1.0 - incline))

	var damp_variant := damping_rebound
	if linearz < 0:
		damp_variant = damping

	var compressed: float = g_range - (located - hit_located).length() - (ground_bump * ground_bump_height)
	var compressed2: float = compressed - (maxcompression + (ground_bump * ground_bump_height))

	var j := maxf(compressed - rest, 0.0)
	compressed2 = maxf(compressed2, 0.0)

	var elasticity2: float = elasticity * (1.0 - incline) + weight * incline
	var damping2: float = damp_variant * (1.0 - incline) + (weight / 10.0) * incline
	var elasticity3 := weight
	var damping3 := weight / 10.0
	var suspforce: float = j * elasticity2

	if compressed2 > 0.0:
		suspforce -= linearz * damping3
		suspforce += compressed2 * elasticity3

	suspforce -= linearz * damping2
	own.rd = compressed

	return maxf(suspforce, 0.0)
