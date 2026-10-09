# ForcedInduction (C1 boost stages, 2026-10-09): every way the engine can be
# boosted, moved out of the vendored Vehicle (gevp_vehicle.gd deviation (7)),
# which now makes one call a tick: ForcedInduction.step(self, delta).
#
# The setup is plain spec data, like the rest of the car (CarSpec):
#   turbo_boost_max  bar at full boost; 0 = naturally aspirated (every kind)
#   boost_kind       "single" (default), "twin", "roots", "sequential", "twincharger"
#   turbo_rpm_thresh, turbo_tau_up, turbo_tau_down, turbo_gain  the base turbo;
#                    each kind scales them (see KINDS)
# The Vehicle keeps boost (bar), blow_off_count and the turbo_* exports, so the
# HUD, EngineAudio and the Tuner read and write them exactly as before.
#
# A naturally aspirated car never gets a ForcedInduction object: step() returns
# exactly 1.0 and touches nothing else, so handling and the physics rate of a
# car without boost are unchanged. "single" is the old GEVP turbo, bit for bit.
#
# Sound and parts read the per-car state with ForcedInduction.of(vehicle) (null
# on an NA car) or snapshot(); see the "Readable state" block.
extends RefCounted
class_name ForcedInduction

const META := &"forced_induction"
const KIND_NAMES := ["single", "twin", "roots", "sequential", "twincharger"]
## Each kind's stages, [name, type], in the order `stages` lists them.
const STAGE_DEFS := {
	"single": [["main", "turbo"]],
	"twin": [["left", "turbo"], ["right", "turbo"]],
	"roots": [["blower", "blower"]],
	"sequential": [["small", "turbo"], ["big", "turbo"]],
	"twincharger": [["blower", "blower"], ["turbo", "turbo"]],
}

## Per-kind numbers, all relative to the car's own turbo_* values.
## Twin (two small turbos side by side): spools earlier and smoother, slightly
## less top power than one big single (Roy, Q173-185).
const TWIN_THRESH := 0.7     # x turbo_rpm_thresh: boost starts lower
const TWIN_TAU := 0.6        # x turbo_tau_up: spools faster
const TWIN_GAIN := 0.93      # x turbo_gain: a little less at full boost
## Roots blower: belt driven, boost follows engine speed with no lag, strongest
## low down; it costs crank power to turn (parasitic drag) and has no blow-off.
const ROOTS_TAU := 0.05      # s: practically instant
const ROOTS_FLOOR := 0.55    # fraction of full boost the blower makes just off idle
const ROOTS_GAIN := 0.85     # x turbo_gain: less top end than a turbo
const ROOTS_DRAG := 0.04     # torque lost at max rpm, as a fraction of the boosted multiplier
## Sequential twins: a small turbo alone low down, the big one joins at the handover.
const SEQ_SMALL_SHARE := 0.55  # the small turbo's share of full boost
const SEQ_SMALL_THRESH := 0.6  # x turbo_rpm_thresh
const SEQ_SMALL_TAU := 0.5     # x turbo_tau_up
const SEQ_HANDOVER := 0.6      # fraction of max_rpm where the big turbo comes in
const SEQ_HANDOVER_HYST := 0.04
## Twincharger: a supercharger fills the bottom, then a clutch drops it out as
## the turbo takes over.
const TC_SC_SHARE := 0.6       # the supercharger's share of full boost
const TC_SC_OFF_START := 0.45  # fraction of max_rpm where the supercharger starts to bypass
const TC_SC_OFF_END := 0.65    # fully bypassed (clutch open) here
const TC_SC_DRAG := 0.03

# ---- Readable state (sound, parts, HUD) ----------------------------------------
var kind := "single"
## Total boost in bar, the same number as Vehicle.boost.
var boost := 0.0
## 0..1 of turbo_boost_max.
var boost_frac := 0.0
## Each charger as its own stage: {"name", "type" ("turbo"/"blower"),
## "boost" (0..1 of this stage's share), "spool" (0..1 shaft-speed proxy),
## "active" (bool)}. Order is fixed per kind: single [main]; twin [left, right];
## roots [blower]; sequential [small, big]; twincharger [blower, turbo].
var stages: Array[Dictionary] = []
## Blower whine drive 0..1 (crank speed while a blower is engaged), 0 with none.
var blower_whine := 0.0
## Sequential: 1 (small turbo only) or 2 (both); bumps handover_count on 1 -> 2.
var seq_stage := 1
var handover_count := 0
## Twincharger: true while the supercharger's clutch is in.
var sc_engaged := false
## The torque multiplier applied this tick (1.0 = no effect).
var torque_mult := 1.0

var _parts: Array[float] = [0.0, 0.0]

## Called once a tick from Vehicle.process_motor(). Returns the torque multiplier.
static func step(v: Vehicle, delta: float) -> float:
	if v.turbo_boost_max <= 0.0:
		v.boost = 0.0
		v._prev_throttle = v.throttle_amount
		return 1.0
	var fi := of(v, true)
	var mult := fi._step(v, delta)
	v._prev_throttle = v.throttle_amount
	return mult

## The car's ForcedInduction, or null on a naturally aspirated car (make = true
## creates it). The kind comes from the boost_kind meta CarSpec.apply() sets.
static func of(v: Vehicle, make := false) -> ForcedInduction:
	if v.has_meta(META):
		return v.get_meta(META)
	if not make or v.turbo_boost_max <= 0.0:
		return null
	var fi := ForcedInduction.new()
	fi.kind = valid_kind(String(v.get_meta(&"boost_kind", "single")))
	for d in STAGE_DEFS[fi.kind]:
		fi.stages.append({"name": d[0], "type": d[1], "boost": 0.0, "spool": 0.0, "active": true})
	v.set_meta(META, fi)
	return fi

## Spec key boost_kind -> the car (CarSpec.apply routes it here; Vehicle has no
## such property). Changing kind resets the stages.
static func set_kind(v: Vehicle, kind_name: String) -> void:
	var k := valid_kind(kind_name)
	v.set_meta(&"boost_kind", k)
	if v.has_meta(META) and (v.get_meta(META) as ForcedInduction).kind != k:
		v.remove_meta(META)
		v.boost = 0.0

static func valid_kind(k: String) -> String:
	return k if k in KIND_NAMES else "single"

## Plain-data copy of the readable state, for code that should not hold the object.
func snapshot() -> Dictionary:
	return {"kind": kind, "boost": boost, "boost_frac": boost_frac, "stages": stages.duplicate(true),
		"blower_whine": blower_whine, "seq_stage": seq_stage, "handover_count": handover_count,
		"sc_engaged": sc_engaged, "torque_mult": torque_mult}

func _step(v: Vehicle, delta: float) -> float:
	var mx := v.turbo_boost_max
	var rpm := v.motor_rpm
	var thr := v.throttle_amount
	var rpm_frac := clampf(rpm / maxf(v.max_rpm, 1.0), 0.0, 1.0)
	var gain := v.turbo_gain
	var mult := 1.0
	match kind:
		"twin":
			var flow := _flow(v, v.turbo_rpm_thresh * TWIN_THRESH)
			# smoothstep the flow: the pair comes in gently instead of on a ramp
			flow = flow * flow * (3.0 - 2.0 * flow)
			v.boost = _lag(v.boost, mx * flow, v.turbo_tau_up * TWIN_TAU, v.turbo_tau_down, delta)
			_blow_off(v, mx)
			mult = 1.0 + gain * TWIN_GAIN * v.boost / mx
			_set_stages([v.boost / mx, v.boost / mx])
		"roots":
			var target := mx * thr * (ROOTS_FLOOR + (1.0 - ROOTS_FLOOR) * rpm_frac) if rpm > v.idle_rpm * 0.9 else 0.0
			v.boost = _lag(v.boost, target, ROOTS_TAU, ROOTS_TAU, delta)
			mult = 1.0 + gain * ROOTS_GAIN * v.boost / mx - ROOTS_DRAG * rpm_frac
			blower_whine = rpm_frac
			_set_stages([v.boost / mx])
		"sequential":
			var small_max := mx * SEQ_SMALL_SHARE
			var small_flow := _flow(v, v.turbo_rpm_thresh * SEQ_SMALL_THRESH)
			_parts[0] = _lag(_parts[0], small_max * small_flow, v.turbo_tau_up * SEQ_SMALL_TAU, v.turbo_tau_down, delta)
			var hand := SEQ_HANDOVER - (SEQ_HANDOVER_HYST if seq_stage == 2 else 0.0)
			var next_stage := 2 if rpm_frac >= hand and thr > 0.3 else 1
			if next_stage == 2 and seq_stage == 1:
				handover_count += 1
			seq_stage = next_stage
			var big_flow := thr * clampf((rpm_frac - SEQ_HANDOVER) / maxf(1.0 - SEQ_HANDOVER, 0.01) + 0.25, 0.0, 1.0) if seq_stage == 2 else 0.0
			_parts[1] = _lag(_parts[1], (mx - small_max) * big_flow, v.turbo_tau_up, v.turbo_tau_down, delta)
			v.boost = _parts[0] + _parts[1]
			_blow_off(v, mx)
			mult = 1.0 + gain * v.boost / mx
			_set_stages([_parts[0] / small_max, _parts[1] / maxf(mx - small_max, 0.001)])
			stages[1].active = seq_stage == 2
		"twincharger":
			var sc_max := mx * TC_SC_SHARE
			# the supercharger: instant, fades out through its bypass, clutch opens at the top
			var sc_on := 1.0 - clampf((rpm_frac - TC_SC_OFF_START) / (TC_SC_OFF_END - TC_SC_OFF_START), 0.0, 1.0)
			sc_engaged = sc_on > 0.0 and rpm > v.idle_rpm * 0.9
			_parts[0] = _lag(_parts[0], sc_max * thr * sc_on if sc_engaged else 0.0, ROOTS_TAU, ROOTS_TAU, delta)
			_parts[1] = _lag(_parts[1], mx * _flow(v, v.turbo_rpm_thresh), v.turbo_tau_up, v.turbo_tau_down, delta)
			v.boost = minf(_parts[0] + _parts[1], mx)
			_blow_off(v, mx)
			mult = 1.0 + gain * v.boost / mx - (TC_SC_DRAG * rpm_frac if sc_engaged else 0.0)
			blower_whine = rpm_frac if sc_engaged else 0.0
			_set_stages([_parts[0] / sc_max, _parts[1] / mx])
			stages[0].active = sc_engaged
		_:
			# "single": the original GEVP turbo (deviation 7), unchanged.
			var flow := thr * clampf((rpm - v.turbo_rpm_thresh) / maxf(v.max_rpm - v.turbo_rpm_thresh, 1.0), 0.0, 1.0)
			var target := mx * flow
			var tau := v.turbo_tau_up if target > v.boost else v.turbo_tau_down
			v.boost += (target - v.boost) * (1.0 - exp(-delta / maxf(tau, 0.01)))
			_blow_off(v, mx)
			mult = 1.0 + gain * v.boost / mx
			_set_stages([v.boost / mx])
	boost = v.boost
	boost_frac = clampf(v.boost / mx, 0.0, 1.0)
	torque_mult = mult
	return mult

## Exhaust flow through a turbo that starts making boost at thresh rpm.
func _flow(v: Vehicle, thresh: float) -> float:
	return v.throttle_amount * clampf((v.motor_rpm - thresh) / maxf(v.max_rpm - thresh, 1.0), 0.0, 1.0)

static func _lag(x: float, target: float, tau_up: float, tau_down: float, delta: float) -> float:
	var tau := tau_up if target > x else tau_down
	return x + (target - x) * (1.0 - exp(-delta / maxf(tau, 0.01)))

## The blow-off rule the GEVP turbo always had: a one-tick throttle drop off a
## hot boost (a shift or the limiter cut). The Roots blower has none.
func _blow_off(v: Vehicle, mx: float) -> void:
	if v._prev_throttle > 0.5 and v.throttle_amount < 0.2 and v.boost > 0.3 * mx:
		v.blow_off_count += 1

func _set_stages(fracs: Array) -> void:
	for i in stages.size():
		var f := clampf(float(fracs[i]), 0.0, 1.0)
		stages[i].boost = f
		# shaft speed leads boost a little: a spinning turbo whistles before it makes pressure
		stages[i].spool = sqrt(f)
