## A single wheel: raycast suspension + tyre force model + per-wheel ABS state.
##
## [b]class_name[/b] is set so other scripts can do [code]if node is Wheel:[/code]
## instead of duck-typing on [code]"TyreSettings" in node[/code]. The old
## duck-type pattern accidentally matched anything that happened to expose
## that property, and broke silently if the property was ever renamed.
##
## NOTES on the recent refactor:
##   • Child nodes ([code]geometry[/code], [code]velocity[/code], etc.) are now
##     cached as [code]@onready[/code] refs and reused. Each
##     [method _physics_process] used to do ~10 [code]get_node[/code] string
##     lookups per wheel per tick.
##   • The longitudinal-and-lateral tyre force math (previously duplicated
##     between the "wv update" block and the "directional_force output" block)
##     lives in [method _slip_to_force]. Bookkeeping unique to each block
##     (slip_perc / slip_sk / skvol / etc.) stays inline.

class_name Wheel extends RayCast3D

@export var car: Car

@export var RealismOptions := {
}

@export var Steer := true
@export var Differed_Wheel := ""
@export var SwayBarConnection := ""

@export var W_PowerBias := 1.0
@export var TyreSettings: Dictionary[String, float] = {
	"GripInfluence": 1.0,
	"Width (mm)": 185.0,
	"Aspect Ratio": 60.0,
	"Rim Size (in)": 14.0
}
@export var TyrePressure := 30.0
@export var Camber := 0.0
@export var Caster := 0.0
@export var Toe := 0.0

@export var CompoundSettings: Dictionary[String, float] = {
	"OptimumTemp": 50.0,
	"Stiffness": 1.0,
	"TractionFactor": 1.0,
	"DeformFactor": 1.0,
	"ForeFriction": 0.125,
	"ForeStiffness": 0.0,
	"GroundDragAffection": 1.0,
	"BuildupAffection": 1.0,
	"CoolRate": 0.000075
}
@export var S_Stiffness := 47.0
@export var S_Damping := 3.5
@export var S_ReboundDamping := 3.5
@export var S_RestLength := 0.0
@export var S_MaxCompression := 0.5
@export var A_InclineArea := 0.2
@export var A_ImpactForce := 1.5
@export var AR_Stiff := 0.5
@export var AR_Elast := 0.1
@export var B_Torque := 15.0
@export var B_Bias := 1.0
@export var B_Saturation := 1.0 # leave this at 1.0 unless you have a heavy vehicle with large wheels, set it higher depending on how big it is
@export var HB_Bias := 0.0
@export var A_Geometry1 := 1.15
@export var A_Geometry2 := 1.0
@export var A_Geometry3 := 0.0
@export var A_Geometry4 := 0.0
@export var Solidify_Axles := NodePath()
@export var ContactABS := true
@export var ESP_Role := ""
@export var ContactBTCS := false
@export var ContactTTCS := false


var dist := 0.0
var w_size := 1.0
var w_size_read := 1.0
var w_weight_read := 0.0
var w_weight := 0.0
var wv := 0.0
var wv_ds := 0.0
var wv_diff := 0.0
var c_tp := 0.0
var effectiveness := 0.0

var angle := 0.0
var snap := 0.0
var absolute_wv := 0.0
var absolute_wv_brake := 0.0
var absolute_wv_diff := 0.0
var output_wv := 0.0
var offset := 0.0
var c_p := 0.0
var wheelpower := 0.0
var wheelpower_global := 0.0
var stress := 0.0
var rolldist := 0.0
var rd := 0.0
var c_camber := 0.0
var cambered := 0.0

var rollvol := 0.0
var sl := 0.0
var skvol := 0.0 # Amount of skidding
var skvol_d := 0.0
var velocity := Vector3(0, 0, 0)
var velocity2 := Vector3(0, 0, 0)
var compress := 0.0
var compensate := 0.0
var axle_position := 0.0

var heat_rate := 1.0
var wear_rate := 1.0

var ground_bump := 0.0
var ground_bump_up := false
var ground_bump_frequency := 0.0
var ground_bump_frequency_random := 1.0
var ground_bump_height := 0.0

var ground_friction := 1.0
var ground_stiffness := 1.0
var fore_friction := 0.0
var fore_stiffness := 0.0
var drag := 0.0
var ground_builduprate := 0.0
var ground_dirt := false
var hitposition := Vector3(0, 0, 0)

var cache_tyrestiffness := 0.0
var cache_friction_action := 0.0

var directional_force := Vector3(0, 0, 0)
var slip_perc := Vector2(0, 0)
var slip_perc2 := 0.0
var slip_percpre := 0.0

var velocity_last := Vector3(0, 0, 0)
var velocity2_last := Vector3(0, 0, 0)

## Extra brake pressure (0..1) applied to this wheel only by stability
## systems (BTCS, ESP). Cleared each physics frame after being consumed.
var tc_brake := 0.0

## Per-wheel ABS brake modulation in 0..1. Driven by [code]Car.apply_abs[/code].
## 1.0 = full brake passthrough, 0.0 = brake fully released. Multiplies the
## driver brake AND any stability-system brake injection on this wheel, so
## ABS can release pressure even while ESP/BTCS are trying to add it.
## In legacy ABS mode this stays at 1.0 and the global [code]Car.brake_allowed[/code]
## does the modulating; in advanced mode this is set per-wheel each frame.
var abs_modulation := 1.0
## Internal first-order valve state (-1..1). Smooths the bang-bang command
## from the ABS controller via the configured hydraulic time constant.
var abs_valve_state := 0.0
## True while the advanced ABS is actively cycling brake pressure on this
## wheel (modulation < ~0.95). Used to drive the dash light.
var abs_active := false
## Longitudinal slip ratio s = 1 − (ω·r)/v computed each frame for the
## advanced ABS controller. Exposed for telemetry/debug.
var abs_slip_ratio := 0.0


# Cached child node references. Looked up once in _ready / @onready instead
# of resolved via NodePath strings every physics tick. [VitaVehicleSimulation]
# and [Car] read these directly, so they're public.
@onready var geom_node: Node3D = $geometry
@onready var velocity_node: Node3D = $velocity
@onready var velocity2_node: Node3D = $velocity2
@onready var _vel_step: Node3D = $velocity/step
@onready var _vel2_step: Node3D = $velocity2/step
@onready var _animation_node: Node3D = $animation
@onready var _camber_node: Node3D = $animation/camber
@onready var _wheel_mesh: Node3D = $animation/camber/wheel


func power():
	if not c_p == 0:
		dist *= (car.clutchpedal*car.clutchpedal)/(car.currentstable)
		var dist_cache := dist
		
		var tol := (.1475/1.3558)*car.ClutchGrip
		
		dist_cache = clamp(dist_cache, -tol, tol)
		
		var dist2 := dist_cache
		
		car.dsweight += c_p
		car.stress += stress*c_p
		
		if car.dsweightrun>0.0:
			if car.rpm>car.DeadRPM:
				wheelpower -= (((dist2/car.ds_weight)/(car.dsweightrun/2.5))*c_p)/w_weight
			car.resistance += (((dist_cache*(10.0))/car.dsweightrun)*c_p)


func diffs():
	if car.locked>0.0:
		if not Differed_Wheel == "":
			var d_w := car.get_node(Differed_Wheel)
			snap = abs(d_w.wheelpower_global)/(car.locked*16.0) +1.0
			absolute_wv = output_wv+(offset*snap)
			var distanced2 := absf(absolute_wv - d_w.absolute_wv_diff)/(car.locked*16.0)
			distanced2 += abs(d_w.wheelpower_global)/(car.locked*16.0)
			if distanced2<snap:
				distanced2 = snap
			distanced2 += 1.0/cache_tyrestiffness
			if distanced2>0.0:
				wheelpower += -((absolute_wv_diff - d_w.absolute_wv_diff)/distanced2)


func sway():
	if not SwayBarConnection == "":
		var linkedwheel := car.get_node(SwayBarConnection)
		rolldist = rd - linkedwheel.rd


## Core tyre-force math, shared between the longitudinal-update block and the
## directional-force-output block in [method _physics_process].
##
## Caller supplies pre-stiffness [param distx]/[param disty] slips and the
## current [param grip] budget. Returns a [Vector3] of
## [code](forcex, forcey, slip_after_traction)[/code].
##
## Both call sites also need the post-stiffness [code]distx[/code] (with the
## angle/wv adjustment) for various bookkeeping, so we hand it back via the
## [member _post_stiffness_distx] / [member _post_stiffness_disty] scratch
## fields instead of allocating a struct.
##
## NOTE: a [code]grip <= 0[/code] input zeroes the returned forces but still
## populates the post-stiffness scratch values so callers that read them
## (e.g. block 1's [code]slip_perc[/code]) see consistent state.
var _post_stiffness_distx := 0.0
var _post_stiffness_disty := 0.0

func _slip_to_force(distx: float, disty: float, grip: float, tyre_stiffness: float, rigidity: float) -> Vector3:
	disty *= tyre_stiffness
	distx *= tyre_stiffness
	distx -= atan2(absf(wv), 1.0) * ((angle * 10.0) * w_size)
	_post_stiffness_distx = distx
	_post_stiffness_disty = disty

	if grip <= 0.0:
		return Vector3.ZERO

	var slip := Vector2(distx, disty).length() / grip
	slip /= slip * ground_builduprate + 1.0
	slip -= CompoundSettings["TractionFactor"]
	slip = maxf(slip, 0.0)

	var forcey := -disty / (slip + 1.0)
	var forcex := -distx / (slip + 1.0)

	# Smoothing: clamp the per-axis force magnitudes to 1.0, square the x
	# component, then divide by a rigidity-weighted blend so very small forces
	# pass through linearly and large ones saturate.
	var yesx := minf(absf(forcex), 1.0)
	var smoothx := minf(yesx * yesx, 1.0)
	var yesy := minf(absf(forcey), 1.0)
	var smoothy := minf(yesy, 1.0)
	forcex /= smoothx * rigidity + (1.0 - rigidity)
	forcey /= smoothy * rigidity + (1.0 - rigidity)

	return Vector3(forcex, forcey, slip)


#region internal
func _ready():
	c_tp = TyrePressure


func _physics_process(delta):
	var translation := position
	var cast_to := target_position
	var global_translation := global_position
	var last_translation := position

	if Steer and absf(car.final_steer) > 0:
		var lasttransform := global_transform

		look_at_from_position(translation, Vector3(car.steering_geometry[0], 0.0, car.steering_geometry[1]))

		# just making this use origin fixed it. lol
		global_transform.origin = lasttransform.origin

		if car.final_steer > 0.0:
			rotate_object_local(Vector3(0,1,0), -deg_to_rad(90.0))
		else:
			rotate_object_local(Vector3(0,1,0), deg_to_rad(90.0))

		var roter := global_rotation.y

		look_at_from_position(translation, Vector3(car.Steer_Radius, 0, car.steering_geometry[1]), Vector3(0, 1, 0))
		# this one too
		global_transform.origin = lasttransform.origin
		rotate_object_local(Vector3(0,1,0), deg_to_rad(90.0))
		var roter_estimateed := rad_to_deg(global_rotation.y)

		get_parent().steering_angles.append(roter_estimateed)

		rotation_degrees = Vector3(0, 0, 0)
		rotation = Vector3(0, 0, 0)

		rotation.y = roter

		rotation_degrees += Vector3(0, -Toe * sign(translation.x), 0)
	else:
		rotation_degrees = Vector3(0, -Toe * sign(translation.x), 0)

	translation = last_translation

	c_camber = Camber + Caster * rotation.y * sign(translation.x)

	directional_force = Vector3(0, 0, 0)

	velocity_node.position = Vector3(0, 0, 0)


	w_size = ((abs(int(TyreSettings["Width (mm)"])) * ((abs(int(TyreSettings["Aspect Ratio"])) * 2.0) / 100.0) + abs(int(TyreSettings["Rim Size (in)"])) * 25.4) * 0.003269) / 2.0 # TODO: Use the constant and adjust for the fact this is in mm.
	w_weight = pow(w_size, 2.0)

	w_size_read = w_size
	w_size_read = max(w_size_read, 1.0)
	w_weight_read = max(w_weight_read, 1.0)

	velocity2_node.global_position = geom_node.global_position

	_vel_step.global_position = velocity_last
	_vel2_step.global_position = velocity2_last
	velocity_last = velocity_node.global_position
	velocity2_last = velocity2_node.global_position

	velocity = -_vel_step.position / delta
	velocity2 = -_vel2_step.position / delta

	velocity_node.rotation = Vector3(0, 0, 0)
	velocity2_node.rotation = Vector3(0, 0, 0)

	# VARS
	var elasticity := S_Stiffness
	var damping := S_Damping
	var damping_rebound := S_ReboundDamping

	var swaystiff := AR_Stiff
	var swayelast := AR_Elast

	var s := rolldist
	s = clamp(s, -1.0, 1.0)

	elasticity *= swayelast * s + 1.0
	damping *= swaystiff * s + 1.0
	damping_rebound *= swaystiff * s + 1.0

	elasticity = max(elasticity, 0.0)
	damping = max(damping, 0.0)
	damping_rebound = max(damping_rebound, 0.0)

	sway()

	var tyre_maxgrip := TyreSettings["GripInfluence"] / CompoundSettings["TractionFactor"]

	var tyre_stiffness2 := absf(int(TyreSettings["Width (mm)"])) / (absf(int(TyreSettings["Aspect Ratio"])) / 1.5)

	var deviding := (Vector2(velocity.x,velocity.z).length() / 50.0 +0.5) * CompoundSettings["DeformFactor"]

	deviding /= ground_stiffness +fore_stiffness * CompoundSettings["ForeStiffness"]
	deviding = max(deviding, 1.0)
	tyre_stiffness2 /= deviding


	var tyre_stiffness := (tyre_stiffness2 * ((c_tp / 30.0) * 0.1 +0.9) ) * CompoundSettings["Stiffness"] +effectiveness
	tyre_stiffness = max(tyre_stiffness, 1.0)

	cache_tyrestiffness = tyre_stiffness

	absolute_wv = output_wv+(offset * snap) -compensate * 1.15296
	absolute_wv_brake = output_wv+((offset / w_size_read) * snap) -compensate * 1.15296
	absolute_wv_diff = output_wv

	wheelpower = 0.0

	# BTCS / ESP injection: per-wheel brake pressure that adds on top of the
	# driver's brake. Multiplied by both the global brake_allowed (legacy ABS
	# pump) AND this wheel's abs_modulation (advanced ABS), so per-wheel ABS
	# can release pressure even when ESP/BTCS are trying to add it. In legacy
	# mode abs_modulation == 1.0; in advanced mode brake_allowed == 1.0.
	var stability_brake: float = clampf(tc_brake, 0.0, 1.0) * car.brake_allowed * abs_modulation
	tc_brake = 0.0  # consumed; stability systems must re-assert each frame

	# Driver brake also gets the per-wheel ABS multiplier. car.brakeline is
	# already brakepedal*brake_allowed (legacy global), so this composes:
	# legacy → mod by brake_allowed only; advanced → mod by abs_modulation only.
	var braked := (car.brakeline * abs_modulation) * B_Bias + car.handbrakepull*HB_Bias + stability_brake
	braked = min(braked, 1.0)
	var bp := (B_Torque*braked)/w_weight_read

	if car.actualgear != 0 and car.dsweightrun > 0.0:
		bp += ((car.stall_resistance*(c_p/car.ds_weight))*car.clutchpedal)*(((500.0/(car.RevSpeed*100.0))/(car.dsweightrun/2.5))/w_weight_read)
	if bp>0.0:
		if abs(absolute_wv)>0.0:
			var distanced := absf(absolute_wv)/bp
			distanced = max(distanced - car.brakeline, snap*(w_size_read/B_Saturation))
			wheelpower += -absolute_wv/distanced
		else:
			wheelpower += -absolute_wv

	wheelpower_global = wheelpower

	power()
	diffs()

	snap = 1.0
	offset = 0.0

	# WHEEL — first physics pass: compute the longitudinal force, update wv,
	# and gather skidding telemetry.
	if is_colliding():
		var collider := get_collider()
		if "drag" in collider:
			drag = collider.get("drag") * CompoundSettings["GroundDragAffection"] * CompoundSettings["GroundDragAffection"]
		if "ground_friction" in collider:
			ground_friction = collider.get("ground_friction")
		if "fore_friction" in collider:
			fore_friction = collider.get("fore_friction")
		if "ground_stiffness" in collider:
			ground_stiffness = collider.get("ground_stiffness")
		if "fore_stiffness" in collider:
			fore_stiffness = collider.get("fore_stiffness")
		if "ground_builduprate" in collider:
			ground_builduprate = collider.get("ground_builduprate")*CompoundSettings["BuildupAffection"]
		if "ground_dirt" in collider:
			ground_dirt = collider.get("ground_dirt")
		if "ground_bump_frequency" in collider:
			ground_bump_frequency = collider.get("ground_bump_frequency")
		if "ground_bump_frequency_random" in collider:
			ground_bump_frequency_random = collider.get("ground_bump_frequency_random") +1.0
		if "ground_bump_height" in collider:
			ground_bump_height = collider.get("ground_bump_height")
		if "wear_rate" in collider:
			wear_rate = collider.get("wear_rate")
		if "heat_rate" in collider:
			heat_rate = collider.get("heat_rate")
		if ground_bump_up:
			ground_bump -= randf_range(ground_bump_frequency/ground_bump_frequency_random,ground_bump_frequency*ground_bump_frequency_random)*(velocity.length()/1000.0)
			if ground_bump<0.0:
				ground_bump = 0.0
				ground_bump_up = false
		else:
			ground_bump += randf_range(ground_bump_frequency/ground_bump_frequency_random,ground_bump_frequency*ground_bump_frequency_random)*(velocity.length()/1000.0)
			if ground_bump>1.0:
				ground_bump = 1.0
				ground_bump_up = true

		var suspforce := VitaVehicleSimulation.suspension(self,S_MaxCompression,A_InclineArea,A_ImpactForce,S_RestLength, elasticity,damping,damping_rebound, velocity.y,abs(cast_to.y),global_translation,get_collision_point(),car.mass,ground_bump,ground_bump_height)
		compress = suspforce

		# FRICTION
		var grip := (suspforce*tyre_maxgrip)*(ground_friction +fore_friction*CompoundSettings["ForeFriction"])
		stress = grip
		var rigidity := 0.67

		wv += (wheelpower*(1.0-(1.0/tyre_stiffness)))
		var disty := velocity2.z - wv*w_size

		offset = disty/w_size
		offset = clamp(offset, -grip, grip)

		var distx := velocity2.x

		var compensate2 := suspforce
		var basis_up_local := geom_node.global_transform.basis.orthonormalized().transposed() * Vector3(0, 1, 0)
		var grav_incline := basis_up_local.x
		var grav_incline2 := basis_up_local.z
		compensate = grav_incline2*(compensate2/tyre_stiffness)

		distx -= (grav_incline * (compensate2 / tyre_stiffness)) * 1.1

		# Run the shared force calc. Returns Vector3(forcex, forcey, slip).
		var force_result := _slip_to_force(distx, disty, grip, tyre_stiffness, rigidity)

		if grip > 0:
			# slip_percpre uses the RAW (pre-builduprate, pre-traction) slip,
			# divided by tyre_stiffness. Recompute that here cheaply.
			var raw_slip := Vector2(_post_stiffness_distx, _post_stiffness_disty).length() / grip
			slip_percpre = raw_slip / tyre_stiffness

			var slip: float = force_result.z
			var forcey: float = force_result.y

			# Extra slip-volume telemetry for skid sounds. slip_sk uses double
			# the lateral component to bias the sound trigger to skids over
			# wheelspin; slip_sk's divisor uses `slip` (the post-traction
			# scalar) — original behaviour preserved verbatim.
			var slip_sk := Vector2(_post_stiffness_distx*2.0, _post_stiffness_disty).length()/grip
			slip_sk /= slip*ground_builduprate +1
			slip_sk -= CompoundSettings["TractionFactor"]
			slip_sk = max(slip_sk, 0.0)

			# Legacy ABS trigger: writes to car.abs_delay so the global
			# pump in Car.apply_abs() drops brake_allowed for a few frames.
			# The advanced controller does its own slip calc in Car.apply_abs
			# directly, so this block is skipped for it.
			if car.abs and not car.abs.use_advanced_controller and abs(_post_stiffness_disty) /(tyre_stiffness/3.0)>(car.abs.slip_threshold/grip)*(ground_friction*ground_friction) and abs(velocity.z)>car.abs.min_speed and ContactABS:
				car.abs_delay = car.abs.pump_duration
				if abs(_post_stiffness_distx) /(tyre_stiffness/3.0)>(car.abs.lateral_slip_threshold/grip)*(ground_friction*ground_friction):
					car.abs_delay = car.abs.lateral_pump_duration

			# `ok` is a normalized lateral-force factor used to scale the
			# wv subtraction and the friction-action telemetry.
			var distyw := Vector2(_post_stiffness_distx, _post_stiffness_disty).length()
			var tr2 := (grip/tyre_stiffness)
			var afg := tyre_stiffness*tr2
			distyw /= CompoundSettings["TractionFactor"]
			distyw = max(distyw, afg)

			var ok := ((distyw/tyre_stiffness)/grip)/w_size
			ok = min(ok, 1.0)

			snap = ok*w_weight_read
			snap = min(snap, 1.0)

			wv -= forcey*ok

			cache_friction_action = forcey*ok

			wv += (wheelpower*(1.0/tyre_stiffness))

			rollvol = velocity.length()*grip

			sl = slip_sk-tyre_stiffness
			sl = max(sl, 0.0)
			skvol = sl / 4.0

			skvol_d = slip * 25.0
	else:
		wv += wheelpower
		stress = 0.0
		rollvol = 0.0
		sl = 0.0
		skvol = 0.0
		skvol_d = 0.0
		compress = 0.0
		compensate = 0.0

	slip_perc = Vector2(0, 0)
	slip_perc2 = 0.0

	wv_diff = wv
	# FORCE — second physics pass: compute the directional force the wheel
	# applies to the car body. Uses the same _slip_to_force helper as the
	# wv-update block above; the only difference is how disty is computed
	# (rolling drag + Differed_Wheel blending) and that we don't write back
	# into wv.
	if is_colliding():
		hitposition = get_collision_point()
		directional_force.y = VitaVehicleSimulation.suspension(self,S_MaxCompression,A_InclineArea,A_ImpactForce,S_RestLength, elasticity,damping,damping_rebound, velocity.y,abs(cast_to.y),global_translation,get_collision_point(),car.mass,ground_bump,ground_bump_height)

		# FRICTION
		var grip := (directional_force.y*tyre_maxgrip)*(ground_friction +fore_friction*CompoundSettings["ForeFriction"])
		var rigidity := 0.67

		var disty := velocity2.z - (wv*w_size)/(drag +1.0)
		if not Differed_Wheel == "":
			var d_w := car.get_node(Differed_Wheel)
			disty = velocity2.z - ((wv*(1.0-get_parent().locked) +d_w.wv_diff*get_parent().locked)*w_size)/(drag +1)

		var distx := velocity2.x

		var compensate2 := directional_force.y
		var grav_incline := (geom_node.global_transform.basis.orthonormalized().transposed() * Vector3(0,1,0)).x

		distx -= (grav_incline*(compensate2/tyre_stiffness))*1.1

		# Stored BEFORE the stiffness multiply — preserves original semantics.
		slip_perc = Vector2(distx, disty)

		# Shared core force math.
		var force_result := _slip_to_force(distx, disty, grip, tyre_stiffness, rigidity)

		if grip > 0:
			slip_perc2 = force_result.z
			directional_force.x = force_result.x
			directional_force.z = force_result.y
	else:
		geom_node.position = cast_to

	output_wv = wv
	_wheel_mesh.rotate_x(deg_to_rad(wv))

	geom_node.position.y += w_size

	var inned := (absf(cambered)+A_Geometry4)/90.0
	inned *= inned -A_Geometry4/90.0

	geom_node.position.x = -inned*translation.x

	_camber_node.rotation.z = -(deg_to_rad(c_camber*sign(translation.x)) -deg_to_rad(cambered*sign(translation.x))*A_Geometry2)

	var g: float
	axle_position = geom_node.position.y

	if str(Solidify_Axles) == "":
		g = (geom_node.position.y+(abs(cast_to.y) -A_Geometry1))/(abs(translation.x)+A_Geometry3 +1.0)
		g /= abs(g) +1.0
		cambered = (g*90.0) -A_Geometry4
	else:
		g = (geom_node.position.y - get_node(Solidify_Axles).axle_position)/(abs(translation.x) +1.0)
		g /= abs(g) +1.0
		cambered = (g*90.0)

	_animation_node.position = geom_node.position

	var forces = velocity2_node.global_transform.basis.orthonormalized() * directional_force


	car.apply_impulse(forces, hitposition-car.global_transform.origin)

	# torque
	#var torqed := (wheelpower*w_weight)/4.0
	wv_ds = wv
#endregion internal
