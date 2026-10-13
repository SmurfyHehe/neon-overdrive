extends RefCounted

# Max tune (2026-10-13, Roy: "tune cars and add turbo and things like that to
# max the car"): a TEST-ONLY profile that puts every player car at its real top
# speed, so the benchmark, the stress bot and the speed tests can run each car
# flat out. It is never saved and never shown in the garage: it is built on the
# stock spec at spawn and nothing writes it back (see the save rules below).
#
# What it fits, in order:
#   1. ModTree.everything_fit: the car's tree (showcase path and side nodes),
#      every Workshop item and the top rung of every part (slicks, sequential
#      box, carbon panels...), exactly the test build's sandbox car.
#   2. A car with no boost gets the turbo branch from the tree templates
#      (_templates.json): service, small turbo, big single turbo, and the drag
#      trim side node, the same ops a tree car buys. Specials (monster truck,
#      lowrider) are story-end cars, fully kitted already: no turbo.
#   3. Gearing for top speed: the top gear is set so the engine sits near its
#      peak-power rpm at the car's flat-out top speed, measured per car on
#      the flat (TOP_RATIO, from tools/top_speed_sweep.gd --calibrate). The
#      lower gears are respaced evenly (geometric) from first, which keeps
#      its launch ratio. A car not in the table gets a ratio worked out from
#      its numbers (overall_for_top: peak power against air drag and GEVP's
#      rolling resistance). Every number stays inside the Tuner's hard
#      limits (TuneParams.ADVANCED).
#
# Steps 1-2 are what the garage sells (or will: the other cars' trees are
# not in data/ yet, so they get the coupe's turbo branch); step 3 is a tune
# any player can set in the Tuner.
#
# Nothing about how a car handles is changed beyond what the parts change:
# springs, tyres, aero, steering and assists are the fitted build's.
#
# How it is switched on: NEON_MAX_TUNE=1, or `-- --max-tune` (benchmark and
# bot runs), or `forced` from a test. PlayerCar fits it instead of the test
# build's sandbox car and does not read or write a saved tune while it is on;
# the game turns saving off for the run.
#
# No class_name on purpose: preload it, so no class cache refresh is needed.

const FLAG := "--max-tune"
const ENV := "NEON_MAX_TUNE"
## Tests: 1 forces it on, 0 off, -1 follows the flag and the environment.
static var forced := -1

## [overall top-gear ratio (top gear x final drive), top speed km/h it gave]
## per car, measured: the fastest flat-out run with the engine at or under
## redline at top speed (above it the sim still pulls, up to the limiter at
## 1.1 x redline). tools/top_speed_sweep.gd --calibrate, 2026-10-13, on the
## Linux GDScript sim, sim-only car (no engine heat). A car not listed gets
## overall_for_top()'s ratio, worked out from its numbers.
## tests/car/max_tune_speed.gd holds every car to its speed here.
const TOP_RATIO := {
	"p0_beater": [2.123, 229.5],
	"p1_coupe": [2.060, 406.5],
	"p2_hothatch": [2.710, 296.1],
	"p7_wagon": [2.476, 236.7],
	"p3_tuner": [2.640, 337.1],
	"p4_kei": [3.095, 288.9],
	"p5_muscle": [1.909, 398.1],
	"p6_crossover": [2.674, 312.8],
	"p17_work_pickup": [2.539, 316.9],
	"p8_driftcoupe": [2.568, 338.7],
	"p10_truck": [2.444, 301.7],
	"m1_monster": [2.319, 335.2],
	"l1_lowrider": [2.319, 335.2],
}

## Built top speed (km/h, fully modded) by the tier the car arrives at; the
## coupe's big single build is a T5 build (_shared.json t5_builds), so 340.
## Bone car (400) is not built.
const LADDER_TOP_KMH := {"T0": 225.0, "T1": 250.0, "T2": 280.0, "T3": 300.0, "T4": 320.0, "T5": 340.0}
const T5_CARS := ["p1_coupe"]
## Drivetrain efficiency the sums use (clutch and tyre slip). Only the
## fallback for a car with no measured TOP_RATIO; the sums are within about
## 10% of the measured speeds.
const EFFICIENCY := 0.93
const G := 9.81
## Highest rpm share the top gear is set for at top speed. The torque curve
## ends at max_rpm (GEVP holds its last value above it) and the limiter cuts
## at 1.1 x max_rpm, so 1.0 keeps a tenth in hand.
const TOP_RPM_SHARE := 1.0
const TURBO_PATH := ["service", "turbo_small", "turbo_big_single", "side_drag_trim"]

static func on() -> bool:
	if forced >= 0:
		return forced == 1
	return OS.get_environment(ENV) == "1" or FLAG in OS.get_cmdline_user_args()

## The ladder top speed for a car, km/h (0 for a special).
static func ladder_top(id: String) -> float:
	if PlayerCars.is_special(id):
		return 0.0
	if id in T5_CARS:
		return LADDER_TOP_KMH.T5
	return float(LADDER_TOP_KMH.get(String(PlayerCars.info(id).tier), 0.0))

## The max-tuned spec for a player car (a fresh dictionary; the stock spec is
## left alone).
static func spec(id: String) -> Dictionary:
	return build(id).spec

## {spec, nodes (what went on, in order), measured_gearing, predicted_kmh,
## ladder_kmh}. `top_ratio` > 0 sets the overall top-gear ratio (calibration).
static func build(id: String, top_ratio := -1.0) -> Dictionary:
	var stock := CarSpec.player_spec(id)
	TuneParams.set_gear_count((stock.gear_ratios as Array).size())
	var b := ModTree.build(stock, ModTree.everything_fit(id))
	var s: Dictionary = b.spec
	var nodes: Array = b.nodes.duplicate()
	if float(s.get("turbo_boost_max", 0.0)) <= 0.0 and not PlayerCars.is_special(id):
		var tpl := ModTree.templates()
		for t in TURBO_PATH:
			for op in (tpl[t] as Dictionary).get("ops", []):
				ModTree.apply_op(s, op)
			nodes.append(t)
	var r := wheel_radius(id)
	var measured := top_ratio > 0.0 or TOP_RATIO.has(id)
	gear_for_top(s, top_ratio if top_ratio > 0.0 else float(TOP_RATIO[id][0]) if TOP_RATIO.has(id) else overall_for_top(s, r))
	return {"spec": s, "nodes": nodes, "measured_gearing": measured, "predicted_kmh": top_speed(s) * 3.6, "ladder_kmh": ladder_top(id)}

## One line for a log.
static func spec_report(id: String) -> String:
	var b := build(id)
	var s: Dictionary = b.spec
	return "%s: %s; %.0f Nm x%.2f boost, %.0f rpm, %.0f kg, final %.2f, gears %s (%s); ladder %.0f km/h" % [
		id, ", ".join(PackedStringArray(b.nodes)), float(s.max_torque), ModTree.boost_mult(s), float(s.max_rpm),
		float(s.vehicle_mass), float(s.final_drive), str(Array(s.gear_ratios).map(func(g: float) -> String: return "%.2f" % g)),
		"measured top gear" if b.measured_gearing else "top gear from the sums", b.ladder_kmh]

static func wheel_radius(id: String) -> float:
	return float(PlayerCar.wheel_config(id).get("wheel_r", 0.34))

# ---- the sums ---------------------------------------------------------------

## Torque multiplier from boost at rpm share x, flat out, boost settled.
static func boost_at(s: Dictionary, x: float) -> float:
	if float(s.get("turbo_boost_max", 0.0)) <= 0.0:
		return 1.0
	var gain := float(s.get("turbo_gain", 0.0))
	var mx := float(s.max_rpm)
	var thresh := float(s.get("turbo_rpm_thresh", mx * 0.5))
	match ForcedInduction.valid_kind(String(s.get("boost_kind", "single"))):
		"single":
			return 1.0 + gain * clampf((x * mx - thresh) / maxf(mx - thresh, 1.0), 0.0, 1.0)
		"roots":
			return 1.0 + gain * ForcedInduction.ROOTS_GAIN * (ForcedInduction.ROOTS_FLOOR + (1.0 - ForcedInduction.ROOTS_FLOOR) * x) - ForcedInduction.ROOTS_DRAG * x
		"twin":
			var t := thresh * ForcedInduction.TWIN_THRESH
			var f := clampf((x * mx - t) / maxf(mx - t, 1.0), 0.0, 1.0)
			return 1.0 + gain * ForcedInduction.TWIN_GAIN * f * f * (3.0 - 2.0 * f)
	return ModTree.boost_mult(s)

## Engine power at rpm share x, W, net of GEVP's motor drag.
static func power_at(s: Dictionary, x: float, curve: Curve) -> float:
	var rpm := x * float(s.max_rpm)
	var t := float(s.max_torque) * curve.sample_baked(x) * boost_at(s, x) - rpm * float(s.get("motor_drag", 0.005))
	return t * rpm * TAU / 60.0

## [peak power W, rpm share it is at].
static func peak_power(s: Dictionary) -> Array:
	var sh: Dictionary = s.get("torque_shape", CarSpec.DEFAULT_TORQUE_SHAPE)
	var curve := CarSpec.build_torque_curve(sh.low_end, sh.peak_pos, sh.plateau, sh.falloff)
	var best := 0.0
	var at := 1.0
	for i in range(30, 101):
		var x := i / 100.0
		var p := power_at(s, x, curve)
		if p > best:
			best = p
			at = x
	return [best, at]

## Force holding the car back at v m/s on a flat road, N: air drag plus GEVP's
## rolling resistance (gevp_wheel.gd process_rolling_resistance) on the car's
## weight and downforce.
static func resistance(s: Dictionary, v: float) -> float:
	var q := 0.5 * 1.225 * v * v
	var area := float(s.get("frontal_area", 1.9))
	var drag := q * area * float(s.get("coefficient_of_drag", 0.3))
	var down := q * area * (float(s.get("aero_downforce_coefficient_front", 0.0)) + float(s.get("aero_downforce_coefficient_rear", 0.0)))
	var st := v * 0.036
	var crr := 0.005 + 0.5 * (0.01 + 0.0095 * st * st)
	var roll: float = float((s.get("rolling_resistance", {}) as Dictionary).get("Road", 1.0))
	return drag + crr * roll * (float(s.vehicle_mass) * G + down)

## Top speed, m/s, if the gearing lets the engine reach its peak power there.
static func top_speed(s: Dictionary) -> float:
	var p: float = peak_power(s)[0] * EFFICIENCY
	var lo := 1.0
	var hi := 200.0
	for i in 40:
		var mid := (lo + hi) * 0.5
		if resistance(s, mid) * mid < p:
			lo = mid
		else:
			hi = mid
	return lo

## The overall top-gear ratio (gear x final drive) that puts the engine at its
## peak-power rpm at top_speed(), no higher than TOP_RPM_SHARE of redline (a
## turbo that makes most at redline peaks there).
static func overall_for_top(s: Dictionary, r: float) -> float:
	var x := minf(float(peak_power(s)[1]), TOP_RPM_SHARE)
	return x * float(s.max_rpm) * TAU / 60.0 / (top_speed(s) / r)

## Gives the car an overall top-gear ratio of `overall`: the top gear changes,
## first gear is kept, the gears between are respaced geometrically. Inside the
## Tuner's hard limits; the final drive moves only when the top gear alone
## cannot do it.
static func gear_for_top(s: Dictionary, overall: float) -> void:
	var gears: Array = s.gear_ratios
	var n := gears.size()
	var fd := float(s.final_drive)
	var lim_g: Array = TuneParams.ADVANCED["gear_ratios/0"]
	var lim_fd: Array = TuneParams.ADVANCED["final_drive"]
	var top := overall / fd
	if top < float(lim_g[0]):
		fd = clampf(overall / float(lim_g[0]), float(lim_fd[0]), float(lim_fd[1]))
		top = clampf(overall / fd, float(lim_g[0]), float(lim_g[1]))
	var first := maxf(float(gears[0]), top)
	for i in n:
		var k := float(i) / maxf(float(n - 1), 1.0)
		gears[i] = clampf(first * pow(top / first, k), float(lim_g[0]), float(lim_g[1]))
	s["final_drive"] = fd
