class_name AutoTuneRules
extends RefCounted

# Auto-Tune step 4: what the search is asked for (goals), what it may not touch
# (locks) and what a tune has to satisfy to be a gearbox and a car at all
# (constraints). Pure functions over spec dictionaries and TuneTrack metrics, no
# physics, so tests/tuning/auto_tune_rules.gd runs in milliseconds.
#
# A request is a Dictionary:
#   {"goals": {"accel": 2.0, "braking": 1.0}, "locks": {"final_drive": true}}
# goals: name -> weight (> 0; absent or 0 = not asked for). locks: path -> true.

## Each gear must be at least this much shorter (numerically smaller ratio) than
## the one below it. tests/tuning/tune_track.gd found that gears out of order leave the
## car unable to launch; the sweep that proved the car stays sane used 1.05.
const GEAR_STEP := 1.05

## A metric the player did NOT ask to improve may get at most this much worse
## (fraction of the baseline) in a verified result. Without it "top speed" is
## happy to wreck braking and grip. Applied to verified candidates only.
const GUARD_REGRESSION := 0.25

const KIND_ACCEL := 0
const KIND_BRAKE := 1
const KIND_CORNER := 2

## goal -> TuneTrack metric, direction (+1 bigger is better, -1 smaller is
## better) and which scripted run produces the metric (TuneTrack.Kind values).
const GOALS := {
	"accel": {"label": "Acceleration (0-100)", "metric": "t_0_100", "dir": -1, "kind": KIND_ACCEL},
	"top_speed": {"label": "Top speed", "metric": "top_speed_kmh", "dir": 1, "kind": KIND_ACCEL},
	"braking": {"label": "Braking (100-0)", "metric": "brake_dist_100", "dir": -1, "kind": KIND_BRAKE},
	"grip": {"label": "Cornering grip", "metric": "peak_lat_g", "dir": 1, "kind": KIND_CORNER},
}

## Metrics checked by the guard, with the direction that counts as "better".
const METRIC_DIR := {
	"t_0_100": -1, "top_speed_kmh": 1, "brake_dist_100": -1, "peak_lat_g": 1,
}

const EPS := 1e-6

# ---------- goals ----------

## Weighted goals actually in force, as {goal: weight}.
static func active_goals(request: Dictionary) -> Dictionary:
	var out := {}
	for g in request.get("goals", {}):
		if GOALS.has(g) and float(request.goals[g]) > 0.0:
			out[g] = float(request.goals[g])
	return out

## The scripted runs needed to score these goals (TuneTrack.Kind values).
static func kinds_needed(request: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for g in active_goals(request):
		var k: int = GOALS[g].kind
		if not out.has(k):
			out.append(k)
	out.sort()
	return out

## Weighted mean relative improvement over the baseline: 0 = same as baseline,
## +0.10 = 10% better on average (weights respected). A goal metric that is
## missing from the candidate (a run failed to produce it) makes the whole tune
## worthless: -1e9.
static func score(metrics: Dictionary, base_metrics: Dictionary, request: Dictionary) -> float:
	var goals := active_goals(request)
	if goals.is_empty():
		return 0.0
	var total := 0.0
	var wsum := 0.0
	for g in goals:
		var key: String = GOALS[g].metric
		if not metrics.has(key) or not is_finite(metrics[key]):
			return -1e9
		var b: float = base_metrics.get(key, NAN)
		if not is_finite(b) or absf(b) < EPS:
			continue
		total += goals[g] * float(GOALS[g].dir) * (metrics[key] - b) / b
		wsum += goals[g]
	return total / wsum if wsum > 0.0 else 0.0

## Metrics that got more than GUARD_REGRESSION worse and that no active goal
## asked about. Empty = fine. Needs full metrics (all three runs).
static func guard_failures(metrics: Dictionary, base_metrics: Dictionary, request: Dictionary) -> Array[String]:
	var asked := {}
	for g in active_goals(request):
		asked[GOALS[g].metric] = true
	var out: Array[String] = []
	for key in METRIC_DIR:
		if asked.has(key):
			continue
		var b: float = base_metrics.get(key, NAN)
		if not base_metrics.has(key) or absf(b) < EPS:
			continue
		if not metrics.has(key) or not is_finite(metrics[key]):
			out.append("%s missing" % key)
			continue
		var worse: float = -float(METRIC_DIR[key]) * (metrics[key] - b) / b
		if worse > GUARD_REGRESSION:
			out.append("%s %.0f%% worse" % [key, worse * 100.0])
	return out

# ---------- locks ----------

static func is_locked(request: Dictionary, path: String) -> bool:
	return request.get("locks", {}).get(path, false)

## The Auto-Tune paths the search may move.
static func free_paths(request: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for path in TuneParams.auto_paths():
		if not is_locked(request, path):
			out.append(path)
	return out

# ---------- constraints ----------

## Brings `spec` inside every constraint by moving only unlocked values:
## each Auto-Tune value inside its registry range, gears in order with at least
## GEAR_STEP between neighbours. Returns false when that is impossible (locked
## gears already out of order, or the order cannot fit inside the gear range);
## the spec may be partly changed then, so callers discard it.
static func repair(spec: Dictionary, request: Dictionary) -> bool:
	for path in TuneParams.auto_paths():
		if is_locked(request, path):
			continue
		var e := TuneParams.find(path)
		TuneParams.set_value(spec, path, clampf(TuneParams.get_value(spec, path), e.min, e.max))
	var n: int = spec.gear_ratios.size()
	for _pass in 4 * n:
		var changed := false
		for i in n - 1:
			var lo := "gear_ratios/%d" % (i + 1)  # the shorter (higher) gear
			var hi := "gear_ratios/%d" % i
			var need: float = TuneParams.get_value(spec, lo) * GEAR_STEP
			if TuneParams.get_value(spec, hi) >= need - EPS:
				continue
			changed = true
			var e_hi := TuneParams.find(hi)
			var e_lo := TuneParams.find(lo)
			var cur_hi := TuneParams.get_value(spec, hi)
			# Lengthen the lower gear if it has room, else shorten the higher one.
			if not is_locked(request, hi) and need <= e_hi.max + EPS:
				TuneParams.set_value(spec, hi, need)
			elif not is_locked(request, lo) and cur_hi / GEAR_STEP >= e_lo.min - EPS:
				TuneParams.set_value(spec, lo, cur_hi / GEAR_STEP)
			else:
				return false
		if not changed:
			break
	return violations(spec, request, spec).is_empty()

## Everything wrong with `spec`: a value out of range, gears out of order, or a
## locked value that differs from `origin` (the spec the search started from).
static func violations(spec: Dictionary, request: Dictionary, origin: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for path in TuneParams.auto_paths():
		var e := TuneParams.find(path)
		var v := TuneParams.get_value(spec, path)
		# Auto-Tune searches the safe range, but a locked value the player set
		# on the Advanced page only has to be inside the hard limits.
		var lo: float = e.adv_min if is_locked(request, path) else e.min
		var hi: float = e.adv_max if is_locked(request, path) else e.max
		if v < lo - EPS or v > hi + EPS or not is_finite(v):
			out.append("%s out of range (%f)" % [path, v])
		if is_locked(request, path) and absf(v - TuneParams.get_value(origin, path)) > EPS:
			out.append("%s is locked but changed" % path)
	var n: int = spec.gear_ratios.size()
	for i in n - 1:
		var a: float = spec.gear_ratios[i]
		var b: float = spec.gear_ratios[i + 1]
		if a < b * GEAR_STEP - EPS:
			out.append("gear %d (%.3f) is not %.2fx longer than gear %d (%.3f)" % [i + 1, a, GEAR_STEP, i + 2, b])
	return out
