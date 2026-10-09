class_name AutoTuneSearch
extends RefCounted

# Auto-Tune step 5: search for a better tune on the hidden test track, then
# verify the best few before offering any of them.
#
# Method (no estimator: the real sim is fast enough, ROADMAP step 2): coordinate
# search with step halving. Each round probes every active parameter one step up
# and one step down from the current tune, keeps the best improving move per
# parameter, tries all of them together, and moves to the best of those. When a
# round finds nothing the step halves. After round one only parameters that
# helped stay active, which is what keeps the budget small. Every candidate goes
# through AutoTuneRules.repair() first (range, gear order, locks), so the search
# never spends an evaluation on a tune that is not a car.
#
# While searching, a candidate is run only on the scripted runs its goals need
# (TuneTrack kinds): asking for braking costs one run, not three. The best
# VERIFY_COUNT candidates are then run on ALL runs and must (a) run cleanly,
# (b) satisfy every constraint and lock, (c) not wreck a metric nobody asked
# about (AutoTuneRules.GUARD_REGRESSION), and (d) still beat the baseline on
# the full score. The best that passes is the result; if none passes, the
# result is "no better tune found" and the spec is unchanged.
#
# Deterministic: no randomness, same inputs -> same result. Cooperative: it
# awaits the track's physics frames, so it runs in the background of the
# caller. Usage:
#   var r: Dictionary = await AutoTuneSearch.new().run(track, spec, request, 60)

const FIRST_STEP := 0.12   # of each parameter's range
const MIN_STEP := 0.02
const VERIFY_COUNT := 3
const IMPROVE_EPS := 1e-4  # a move must beat the current score by this much

## `track` must be in the tree. `request`: see AutoTuneRules. `budget`: how many
## candidate runs the search may spend (verification is extra, at most
## VERIFY_COUNT + 1 full evaluations). `progress`, if valid, is called as
## progress(evals_done, budget, best_score) after every evaluation.
## Returns {
##   improved: bool, spec: Dictionary (the base spec when not improved),
##   base_metrics, metrics (full, verified), score (full score, 0 if none),
##   evals, notes: Array[String],
##   verified: Array of {spec, search_score, full_score, metrics, accepted, why} }
func run(track: TuneTrack, base: Dictionary, request: Dictionary, budget: int, progress := Callable()) -> Dictionary:
	var result := {
		"improved": false, "spec": CarSpec.clone_spec(base), "base_metrics": {}, "metrics": {},
		"score": 0.0, "evals": 0, "notes": [] as Array[String], "verified": [],
	}
	if AutoTuneRules.active_goals(request).is_empty():
		result.notes.append("No goal selected.")
		return result
	var kinds: Array = AutoTuneRules.kinds_needed(request)
	var evals := 0

	var base_full: Dictionary = (await track.evaluate([base], TuneTrack.ALL_KINDS))[0]
	evals += 1
	result.base_metrics = base_full
	if not base_full.ok:
		result.notes.append("The starting tune does not run cleanly on the test track: %s" % str(base_full.problems))
		result.evals = evals
		return result
	for g in AutoTuneRules.active_goals(request):
		if not base_full.has(AutoTuneRules.GOALS[g].metric):
			result.notes.append("The starting tune produced no %s result, so it cannot be improved on." % g)
			result.evals = evals
			return result

	var archive: Array = []   # {spec, score}
	var current := CarSpec.clone_spec(base)
	var cur_score := 0.0
	var step := FIRST_STEP
	var active: Array[String] = AutoTuneRules.free_paths(request)
	if active.is_empty():
		result.notes.append("Everything is locked.")
		result.evals = evals
		return result

	while evals < budget and step >= MIN_STEP and not active.is_empty():
		var moves := {}  # path -> best {spec, score, path} among that path's probes
		for path in active:
			for sign in [1.0, -1.0]:
				if evals >= budget:
					break
				var cand := _probe(current, path, sign * step, request)
				if cand.is_empty():
					continue
				var e := await _evaluate(track, cand, kinds, base_full, request)
				evals += 1
				archive.append(e)
				if e.score > cur_score + IMPROVE_EPS and (not moves.has(path) or e.score > moves[path].score):
					moves[path] = {"spec": cand, "score": e.score, "path": path}
				if progress.is_valid():
					progress.call(evals, budget, maxf(cur_score, _best(archive)))
		if moves.is_empty():
			step *= 0.5
			continue
		var best: Dictionary = {}
		for path in moves:
			if best.is_empty() or moves[path].score > best.score:
				best = moves[path]
		if moves.size() > 1 and evals < budget:
			var combo := CarSpec.clone_spec(current)
			for path in moves:
				TuneParams.set_value(combo, path, TuneParams.get_value(moves[path].spec, path))
			if AutoTuneRules.repair(combo, request):
				var e := await _evaluate(track, combo, kinds, base_full, request)
				evals += 1
				archive.append(e)
				if e.score > best.score:
					best = {"spec": combo, "score": e.score}
				if progress.is_valid():
					progress.call(evals, budget, maxf(cur_score, _best(archive)))
		current = best.spec
		cur_score = best.score
		var still: Array[String] = []
		for path in moves:
			still.append(path)
		active = still

	await _verify(track, base, request, base_full, archive, result)
	result.evals = evals + result.verified.size()
	return result

## One candidate: `current` with `path` moved by `delta` x its range, repaired.
## Empty if it is impossible or the same tune.
func _probe(current: Dictionary, path: String, delta: float, request: Dictionary) -> Dictionary:
	var e := TuneParams.find(path)
	var cand := CarSpec.clone_spec(current)
	var v: float = TuneParams.get_value(current, path) + delta * (e.max - e.min)
	TuneParams.set_value(cand, path, clampf(v, e.min, e.max))
	if not AutoTuneRules.repair(cand, request) or _same(cand, current):
		return {}
	return cand

func _evaluate(track: TuneTrack, spec: Dictionary, kinds: Array, base_full: Dictionary, request: Dictionary) -> Dictionary:
	var m: Dictionary = (await track.evaluate([spec], kinds))[0]
	var sc := AutoTuneRules.score(m, base_full, request) if m.ok else -1e9
	return {"spec": spec, "score": sc, "metrics": m}

func _best(archive: Array) -> float:
	var b := 0.0
	for e in archive:
		b = maxf(b, e.score)
	return b

func _verify(track: TuneTrack, base: Dictionary, request: Dictionary, base_full: Dictionary, archive: Array, result: Dictionary) -> void:
	archive.sort_custom(func(a, b): return a.score > b.score)
	var picked: Array = []
	for e in archive:
		if picked.size() >= VERIFY_COUNT or e.score <= IMPROVE_EPS:
			break
		var dup := false
		for p in picked:
			dup = dup or _same(p.spec, e.spec)
		if not dup:
			picked.append(e)
	if picked.is_empty():
		result.notes.append("No candidate beat the starting tune.")
		return
	var winner: Dictionary = {}
	for e in picked:
		var full: Dictionary = (await track.evaluate([e.spec], TuneTrack.ALL_KINDS))[0]
		var v := {"spec": e.spec, "search_score": e.score, "full_score": -1e9, "metrics": full, "accepted": false, "why": ""}
		var why := ""
		if not full.ok:
			why = "did not run cleanly: %s" % str(full.problems)
		else:
			var bad := AutoTuneRules.violations(e.spec, request, base)
			var guard := AutoTuneRules.guard_failures(full, base_full, request)
			v.full_score = AutoTuneRules.score(full, base_full, request)
			if not bad.is_empty():
				why = "breaks a rule: %s" % str(bad)
			elif not guard.is_empty():
				why = "costs too much elsewhere: %s" % ", ".join(guard)
			elif v.full_score <= IMPROVE_EPS:
				why = "no better than the starting tune"
		v.accepted = why == ""
		v.why = why
		result.verified.append(v)
		if v.accepted and (winner.is_empty() or v.full_score > winner.full_score):
			winner = v
	if winner.is_empty():
		result.notes.append("The best candidates failed verification; keeping the starting tune.")
		return
	result.improved = true
	result.spec = winner.spec
	result.metrics = winner.metrics
	result.score = winner.full_score

## Same Auto-Tune values (within float noise).
func _same(a: Dictionary, b: Dictionary) -> bool:
	for path in TuneParams.auto_paths():
		if absf(TuneParams.get_value(a, path) - TuneParams.get_value(b, path)) > 1e-9:
			return false
	return true
