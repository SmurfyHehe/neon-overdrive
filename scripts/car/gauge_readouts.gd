class_name GaugeReadouts
extends RefCounted

## What the bolt-on gauge pod reads (2026-10-09, Roy: an AFR gauge and a PSI
## gauge; the pod comes free with the first boost setup, AFR is a reading only,
## nothing breaks when it is off).
##
## Both numbers come from the car's own sim, nothing is stored on the car:
## - PSI is the manifold pressure. On boost it is GEVP's `boost` (bar) in psi;
##   off the throttle the manifold pulls a vacuum, so the needle sits below
##   zero at idle (about -9 psi, 18 inHg) and deeper on the overrun. A car with
##   no boost setup never has a pod, so the gauge only ever reads a vacuum
##   while the turbo is off boost.
## - AFR is what a wideband would show. Stoich (14.7) at idle, a touch lean on
##   a light cruise, rich at full throttle and richer still under boost (the
##   ECU adds fuel to keep the charge cool), lean pegs on a fuel cut: the rev
##   limiter and the overrun (closed throttle, in gear, above idle). A sharp
##   stab of throttle leans for a moment before the pump catches up, and the
##   lift-off from boost dips rich as the blow-off dumps the charge.
## The gauge needles lag the targets like a real pointer; `update()` each tick.

const PSI_PER_BAR := 14.5038
const STOICH := 14.7
const AFR_MIN := 10.0        # the gauge's rich end
const AFR_MAX := 20.0        # the gauge's lean end; a fuel cut pegs it
const IDLE_VACUUM_PSI := 9.0 # closed throttle at idle
const OVERRUN_VACUUM_PSI := 13.0
const WOT_AFR := 12.8        # full throttle, no boost
const BOOST_ENRICH := 1.4    # taken off the AFR at full boost
const CRUISE_LEAN := 0.5     # added at a closed throttle with the engine idling
const TIP_IN_LEAN := 1.2     # at most, on a throttle stab
const BLOW_OFF_RICH := 11.2
const NEEDLE_TAU := 0.10     # seconds, pointer lag
const BLOW_OFF_SECS := 0.35

var afr := STOICH
var psi := 0.0
var fuel_cut := false        # limiter or overrun: the gauge reads a lean peg
var boosting := false        # manifold above atmospheric
var _prev_throttle := 0.0
var _prev_blow_offs := -1
var _blow_off_t := 0.0

## The pod only exists on a car with a boost setup (Roy, 2026-10-09).
static func has_pod(car: Vehicle) -> bool:
	return car != null and car.turbo_boost_max > 0.0

func update(car: Vehicle, delta: float) -> void:
	if delta <= 0.0:
		return
	var running: bool = car.engine_running or not car.realistic_clutch
	var thr := clampf(car.throttle_amount, 0.0, 1.0)
	var rpm_frac := clampf(car.motor_rpm / maxf(car.max_rpm, 1.0), 0.0, 1.0)
	var boost_max := maxf(car.turbo_boost_max, 0.0)
	var boost_frac := clampf(car.boost / boost_max, 0.0, 1.0) if boost_max > 0.0 else 0.0
	# --- manifold pressure ---
	var psi_target := 0.0
	if running:
		var vacuum := lerpf(IDLE_VACUUM_PSI, OVERRUN_VACUUM_PSI, rpm_frac) * pow(1.0 - thr, 1.5)
		psi_target = car.boost * PSI_PER_BAR - vacuum
	# --- air/fuel ratio ---
	var afr_target := 0.0   # engine off: the needle rests at the rich stop
	fuel_cut = false
	if running:
		var over_idle: bool = car.motor_rpm > car.idle_rpm * 1.5
		var in_gear: bool = car.gear != 0 and car.clutch_amount < 0.5   # GEVP: 1 = pedal down, disengaged
		fuel_cut = bool(car.limiter_cut) or (thr < 0.03 and over_idle and in_gear)
		if fuel_cut:
			afr_target = AFR_MAX + 2.0   # pegged
		else:
			var load := smoothstep(0.0, 1.0, thr)
			afr_target = lerpf(STOICH + CRUISE_LEAN * (1.0 - rpm_frac), WOT_AFR, load)
			afr_target -= BOOST_ENRICH * boost_frac
			var stab := clampf((thr - _prev_throttle) / delta * 0.25, 0.0, 1.0)
			afr_target += TIP_IN_LEAN * stab
			if car.blow_off_count != _prev_blow_offs and _prev_blow_offs >= 0:
				_blow_off_t = BLOW_OFF_SECS
			if _blow_off_t > 0.0:
				afr_target = minf(afr_target, BLOW_OFF_RICH)
	_prev_blow_offs = car.blow_off_count
	_blow_off_t = maxf(_blow_off_t - delta, 0.0)
	_prev_throttle = thr
	var k := 1.0 - exp(-delta / NEEDLE_TAU)
	psi += (psi_target - psi) * k
	afr += (afr_target - afr) * k
	boosting = psi > 0.5

## Needle fraction 0..1 across the AFR face (rich end to lean end).
func afr_frac() -> float:
	return clampf((afr - AFR_MIN) / (AFR_MAX - AFR_MIN), 0.0, 1.0)

## Needle fraction 0..1 across a PSI face that runs from -psi_min to psi_max.
func psi_frac(psi_min: float, psi_max: float) -> float:
	return clampf((psi + psi_min) / (psi_max + psi_min), 0.0, 1.0)
