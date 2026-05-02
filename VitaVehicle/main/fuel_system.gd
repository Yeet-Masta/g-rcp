## A heavy BSFC-style fuel model with VE, MAF estimate, AFR, DFCO,
## ignition-aware behavior and compression-ignition support.
##
## How it works:
##  1) Compute MAF (mass air flow, g/s) from RPM, displacement, VE and boost.
##  2) Pick a target AFR based on load (richer at WOT, stoichiometric at cruise).
##  3) Fuel mass flow = MAF / AFR. Convert to volume using fuel density.
##  4) Override with BSFC map look-up if power output is meaningful.
##     Volumetric model dominates at idle/light load; BSFC dominates under load.
##  5) DFCO zeroes consumption while coasting in gear with throttle closed.
##  6) Ignition off zeroes consumption.
##
## All units are SI internally; the returned value is in liters/sec to keep
## the existing call site (Car.simulate_fuel) compatible.
##
## Notes on units:
## decimeters^3/sec = liters/sec
## g/kWh is the canonical unit for BSFC.

class_name Fuel extends Resource



enum IgnitionType {
	SPARK,       ## Petrol, ethanol, etc. Needs a key/spark to ignite.
	COMPRESSION, ## Diesel. Will auto-ignite when cranked above a threshold RPM.
}



#region exports (preserved for backward compatibility)
## The maximum amount of fuel in [code]liters[/code].
@export var max_fuel := 40.0

## The idle engine consumption in [code]liters/sec[/code].
@export var idle_consumption := 0.0002

## The load engine consumption coefficient. (arbitrary value to help mimic realistic-ish consumption under load)
@export var load_consumption_coefficient := 0.0001

## Deceleration fuel cut-off (DFCO)
## Turn off the fuel injection when decelerating in gear.
@export var deceleration_fuel_cutoff := false
#endregion


#region exports (new, additive)
@export_group("Engine model")
## Engine ignition type. Compression engines (diesel) auto-ignite if cranked
## above [member compression_autoignite_rpm].
@export var ignition_type := IgnitionType.SPARK

## Engine displacement, in liters. Defaults to a 2.0 L typical road-car engine.
@export_range(0.1, 12.0, 0.05, "suffix:L") var displacement := 2.0

## Fuel density in [code]kg/L[/code]. ~0.745 for gasoline, ~0.832 for diesel,
## ~0.789 for ethanol. Used for mass <-> volume conversion.
@export_range(0.5, 1.0, 0.001, "suffix:kg/L") var fuel_density := 0.745

## Stoichiometric air-fuel ratio. ~14.7 for gasoline, ~14.5 for diesel,
## ~9.0 for ethanol. Mass of air per mass of fuel for complete combustion.
@export_range(5.0, 20.0, 0.1) var stoichiometric_afr := 14.7

## RPM above which a compression-ignition engine self-ignites (only used when
## [member ignition_type] = COMPRESSION).
@export var compression_autoignite_rpm := 250.0

@export_group("Volumetric efficiency curve")
## Volumetric efficiency at idle/very-low RPM (0.0–1.2). Realistic ~0.6.
@export_range(0.0, 1.5, 0.01) var ve_low := 0.55
## Peak volumetric efficiency. Realistic NA ~0.85–0.95, performance NA ~1.0+.
@export_range(0.0, 1.5, 0.01) var ve_peak := 0.92
## Volumetric efficiency at redline. Drops off with intake/exhaust losses.
@export_range(0.0, 1.5, 0.01) var ve_high := 0.78
## RPM at which VE peaks (typically near peak torque RPM).
@export var ve_peak_rpm := 4000.0

@export_group("Air-fuel ratio targets")
## AFR multiplier at idle (~1.0 = stoich; <1 = rich, >1 = lean).
@export_range(0.6, 1.4, 0.01) var afr_idle_factor := 0.98
## AFR multiplier at light cruise. Engines run lean of stoich for economy
## when modern ECU lean-cruise is active.
@export_range(0.6, 1.4, 0.01) var afr_cruise_factor := 1.0
## AFR multiplier at WOT. Real engines enrich (~12.5:1 gasoline) for power.
@export_range(0.6, 1.4, 0.01) var afr_wot_factor := 0.85
## Throttle position above which the engine fully enriches.
@export_range(0.0, 1.0, 0.01) var afr_enrich_threshold := 0.85

@export_group("BSFC map")
## Best-case BSFC in [code]g/kWh[/code]. Modern NA petrol ~240–260,
## modern diesel ~200–220. The map scales around this value.
@export_range(150.0, 500.0, 1.0, "suffix:g/kWh") var bsfc_optimal := 250.0
## RPM at which BSFC is best.
@export var bsfc_optimal_rpm := 2800.0
## Load (0–1) at which BSFC is best. Real engines are most efficient at
## ~70–80% load (high MEP, but not over-enriched).
@export_range(0.0, 1.0, 0.01) var bsfc_optimal_load := 0.75
## How fast BSFC degrades away from the optimum island. Higher = sharper map.
@export_range(0.5, 5.0, 0.05) var bsfc_falloff := 1.6

@export_group("Behavior")
## Throttle position below which DFCO can engage.
@export_range(0.0, 0.5, 0.01) var dfco_throttle_threshold := 0.05
## RPM above which DFCO can engage (typically idle + safety margin).
@export var dfco_min_rpm := 1300.0
#endregion


#region telemetry (read-only)
## Last computed mass air flow in g/s.
var last_maf_gps := 0.0
## Last commanded AFR (mass of air per mass of fuel).
var last_afr := 14.7
## Last computed engine load (0..1, throttle * VE-ish).
var last_load := 0.0
## Last BSFC value used (g/kWh). 0 when DFCO/off.
var last_bsfc := 0.0
## True when DFCO is suppressing injection right now.
var dfco_active := false
#endregion


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Returns instantaneous fuel consumption in [code]liters/sec[/code].
##
## [param car] is the [Car] sourcing telemetry: [code]rpm[/code],
## [code]throttle[/code], [code]gaspedal[/code], [code]engine_torque[/code],
## [code]turbopsi[/code], [code]is_ignition_on[/code], gear/in-gear state.
##
## Backward-compatible: callers may still pass an engine torque + RPM by using
## [method get_consumption_legacy].
func get_consumption(car) -> float:
	if car == null:
		return 0.0
	
	# Off / stalled — no injection.
	if not car.is_ignition_on:
		_reset_telemetry()
		return 0.0
	
	# DFCO: closed throttle, in gear, RPM well above idle.
	if _should_apply_dfco(car):
		dfco_active = true
		last_bsfc = 0.0
		last_load = 0.0
		last_maf_gps = 0.0
		return 0.0
	dfco_active = false
	
	# RPM is signed in this codebase (reverse spins it negative). Clamp.
	var rpm: float = absf(car.rpm)
	var throttle: float = clampf(car.throttle, 0.0, 1.0)
	
	# --- 1. Volumetric efficiency at this RPM. ---
	var ve := _ve_at(rpm)
	
	# --- 2. Boost ratio (forced induction). ---
	# 1.0 atm = 14.7 PSI. Boost adds proportional air.
	var boost_psi := 0.0
	if "turbopsi" in car:
		boost_psi = maxf(car.turbopsi, 0.0)
	var boost_ratio := 1.0 + boost_psi / 14.7
	
	# --- 3. MAF estimate (g/s) from speed-density. ---
	# n_dot (revs/sec) * displacement_per_rev * VE * air_density * boost
	# 4-stroke: each cylinder fires once per 2 revs => /2.
	# air density at sea level ≈ 1.225 g/L
	const AIR_DENSITY_GPL := 1.225
	var revs_per_sec := rpm / 60.0
	var maf_gps := (revs_per_sec / 2.0) * displacement * ve * AIR_DENSITY_GPL * boost_ratio
	maf_gps *= throttle  # closed throttle => closed plate => no air (approx).
	
	# Idle bypass: even at zero throttle a running engine pulls some air to
	# keep itself spinning. Floor at idle equivalent.
	var idle_bypass_gps := (revs_per_sec / 2.0) * displacement * ve_low * AIR_DENSITY_GPL * 0.05
	maf_gps = maxf(maf_gps, idle_bypass_gps)
	last_maf_gps = maf_gps
	
	# --- 4. AFR target (commanded richness). ---
	var afr_factor := _afr_factor_at(throttle)
	var commanded_afr: float = stoichiometric_afr * afr_factor
	commanded_afr = maxf(commanded_afr, 1.0)  # safety
	last_afr = commanded_afr
	
	# --- 5. Volumetric mass-flow consumption (g/s). ---
	var fuel_gps_volumetric := maf_gps / commanded_afr
	
	# --- 6. BSFC-based consumption (g/s) when producing power. ---
	# Power in kW = torque_Nm * rpm / 9549.
	# Mass flow = bsfc(g/kWh) * power(kW) / 3600.
	var torque_nm: float = absf(car.engine_torque) if "engine_torque" in car else 0.0
	var power_kw := (torque_nm * rpm) / 9549.0
	power_kw = maxf(power_kw, 0.0)
	last_load = clampf(throttle * ve, 0.0, 1.0)
	var bsfc := _bsfc_at(rpm, last_load)
	last_bsfc = bsfc
	var fuel_gps_bsfc := (bsfc * power_kw) / 3600.0
	
	# --- 7. Combine: take the larger of the two estimates. ---
	# At idle/very low load, BSFC * power -> 0 but the engine still drinks
	# air/fuel to spin. The volumetric model captures that.
	# Under load, the BSFC map captures pumping/combustion losses better.
	var fuel_gps := maxf(fuel_gps_volumetric, fuel_gps_bsfc)
	
	# --- 8. Convert g/s -> L/s. ---
	# liters = grams / (kg/L * 1000)
	var fuel_lps := fuel_gps / (fuel_density * 1000.0)
	
	# --- 9. Floor with the legacy idle term so very small numbers don't vanish. ---
	fuel_lps = maxf(fuel_lps, idle_consumption)
	
	return fuel_lps


## Legacy signature for older callers that didn't have a Car reference.
## Approximates consumption from torque & RPM only (no DFCO, no AFR shift).
func get_consumption_legacy(engine_torque: float, rpm: float) -> float:
	var torque_nm := absf(engine_torque)
	var r := absf(rpm)
	var power_kw := (torque_nm * r) / 9549.0
	var bsfc := _bsfc_at(r, 0.5)
	var fuel_gps := (bsfc * power_kw) / 3600.0
	var fuel_lps := fuel_gps / (fuel_density * 1000.0)
	fuel_lps = maxf(fuel_lps, idle_consumption)
	return fuel_lps


## True if the engine should self-ignite when cranked. Spark engines never do;
## diesels do above their auto-ignition RPM threshold.
func should_compression_autostart(rpm: float) -> bool:
	return ignition_type == IgnitionType.COMPRESSION and absf(rpm) >= compression_autoignite_rpm


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _ve_at(rpm: float) -> float:
	# Piecewise linear: low -> peak -> high. Cheap & adjustable.
	if rpm <= 0.0:
		return ve_low
	if rpm <= ve_peak_rpm:
		var t: float = clampf(rpm / maxf(ve_peak_rpm, 1.0), 0.0, 1.0)
		return lerpf(ve_low, ve_peak, t)
	# Above peak: drift toward ve_high over the next ~3000 rpm.
	var t2: float = clampf((rpm - ve_peak_rpm) / 3000.0, 0.0, 1.0)
	return lerpf(ve_peak, ve_high, t2)


func _afr_factor_at(throttle: float) -> float:
	# Piecewise: idle -> cruise (linear up to enrich threshold), then enrich
	# linearly toward WOT.
	if throttle < 0.05:
		return afr_idle_factor
	if throttle < afr_enrich_threshold:
		var t: float = (throttle - 0.05) / maxf(afr_enrich_threshold - 0.05, 0.001)
		return lerpf(afr_idle_factor, afr_cruise_factor, t)
	var t2: float = (throttle - afr_enrich_threshold) / maxf(1.0 - afr_enrich_threshold, 0.001)
	return lerpf(afr_cruise_factor, afr_wot_factor, clampf(t2, 0.0, 1.0))


func _bsfc_at(rpm: float, load: float) -> float:
	# Distance from optimum island in normalized RPM/load space, then
	# multiply BSFC by (1 + falloff * dist^2). Sharp islands feel realistic.
	var rpm_norm: float = (rpm - bsfc_optimal_rpm) / 4000.0  # 4000 rpm scale
	var load_norm := load - bsfc_optimal_load
	var dist_sq := rpm_norm * rpm_norm + load_norm * load_norm
	return bsfc_optimal * (1.0 + bsfc_falloff * dist_sq)


func _should_apply_dfco(car) -> bool:
	if not deceleration_fuel_cutoff:
		return false
	if not "throttle" in car:
		return false
	if car.throttle > dfco_throttle_threshold:
		return false
	if absf(car.rpm) < dfco_min_rpm:
		return false
	# Only cut off when the engine is being driven by the wheels: in gear
	# with the clutch engaged.
	if "actualgear" in car and car.actualgear == 0:
		return false
	if "clutchpedal" in car and car.clutchpedal < 0.5:
		return false
	return true


func _reset_telemetry() -> void:
	last_maf_gps = 0.0
	last_load = 0.0
	last_bsfc = 0.0
	dfco_active = false
