extends RefCounted
class_name RoadLayout

# The road's layout along its length (road lane proposal step 1, 2026-10-08;
# docs/planning/road-lane-changes-proposal-2026-10-08.md sections 3 and 10):
# how many lanes each side has, how wide the median is, and where the exits
# are, as a list of changes along the road. The road stops being one fixed
# 4+4 strip: an outside lane ends or opens, the two carriageways split apart
# and come back, an exit peels off and rejoins.
#
# Distances are metres along the road from the start of chunk 0 (s = chunk
# index x CHUNK_LEN + metres into the chunk), so they never change with the
# floating origin. Before s = 0 the road is the plain 4+4.
#
# Two random streams:
# - Districts come from a FIXED seed (MAP_SEED): the same city and outskirts
#   stretches every run (Roy, 2026-10-08: fixed districts, landmarks and
#   exits; bends and traffic new each run).
# - Which change happens where comes from the run's road seed, its own
#   stream (the alignment's bends and hills use two others), so changing
#   this never changes the curves.
# The sequence is generated from s = 0 forward and cached, so the same seeds
# give the same layout whatever order it is asked in, like RoadAlignment.
#
# Rules (proposal section 3, from US highway practice):
# - One change at a time, spaced by district: city every CITY_GAP, outskirts
#   every OUTSKIRTS_GAP (WSDOT interchange spacing, decision 8).
# - Lanes 2 to 4 per side (decision 7); drops and adds take the OUTSIDE lane
#   only, so the other lanes never change number.
# - A drop tapers over DROP_TAPER (MUTCD L = W x S), an add over ADD_TAPER.
#   Drops get warning signs at WARN_FAR and WARN_NEAR before the taper, so
#   nothing else starts in the WARN_FAR before a drop.
# - No change on a tight bend (radius under MIN_CHANGE_RADIUS) or a kicker
#   crest: the change slides forward until it is clear.
# - Drift back: after DRIFT_BACK away from 4+4, a change that restores a lane
#   is picked first.
#
# Step 1 builds the plan only. The road and traffic still run 4+4 until
# `lanes_live` is switched on (step 3); median splits and exits wait for
# steps 4 and 5 (`splits_live`, `exits_live`).

const L := RoadChunkBuilder.CHUNK_LEN
const MAP_SEED := 20261008

const MAX_LANES := 4
const MIN_LANES := 2
const DROP_TAPER := 225.0
const ADD_TAPER := 100.0
const WARN_FAR := 450.0
const WARN_NEAR := 150.0
## Change spacing by district, metres (min, max).
const CITY_GAP := Vector2(1500.0, 2000.0)
const OUTSKIRTS_GAP := Vector2(4000.0, 5000.0)
## District lengths, metres (min, max).
const CITY_LEN := Vector2(4000.0, 8000.0)
const OUTSKIRTS_LEN := Vector2(8000.0, 16000.0)
## Where the first change may come, so a run starts on the plain highway.
const FIRST_CHANGE := 1200.0
const DRIFT_BACK := 3000.0
const MIN_CHANGE_RADIUS := 500.0
## Median split: open and close over SPLIT_TAPER, held SPLIT_HOLD, 10-30 m
## between the carriageways (proposal section 1).
const SPLIT_TAPER := 250.0
const SPLIT_HOLD := Vector2(600.0, 1500.0)
const SPLIT_WIDTH := Vector2(10.0, 30.0)
## Exit and on-ramp pair (loops back, decision 10): the ramp leaves at
## `s0` and rejoins EXIT_LOOP later.
const EXIT_LOOP := Vector2(350.0, 600.0)
## The same-way share of each kind of change, by weight.
const W_LANE := 0.55
const W_SPLIT := 0.25
const W_EXIT := 0.20

var road_seed := 0
## Busy-ness for the tests' slider sweep: 0 = no changes at all (plain 4+4),
## 1 = the normal district spacing, and a spacing in metres > 1 = a change
## every that many metres, district ignored.
var busy := 1.0
var align: RoadAlignment

## Switches for what the game builds from the plan (see the header).
var lanes_live := false
var splits_live := false
var exits_live := false

var _rng := RandomNumberGenerator.new()
var _map_rng := RandomNumberGenerator.new()
## Districts: [{s0, s1, kind}], kind "city" or "outskirts", generated forward.
var _districts: Array[Dictionary] = []
## Changes in order of s0: {kind, side, s0, s1, ...}. kind "drop" / "add"
## (side "own" / "onc", from, to), "split" (s0 = opening starts, s1 = closed
## again, open_end, close_start, width), "exit" (s0 = exit gore, s1 = rejoin).
var changes: Array[Dictionary] = []
## Lane counts after the last generated change, and how far generation got.
var _own := MAX_LANES
var _onc := MAX_LANES
## Per side, where it last dropped below MAX_LANES (-1 = it has all lanes).
var _away_since := {"own": -1.0, "onc": -1.0}
var _next_s := FIRST_CHANGE
var _gen_to := 0.0

func _init(seed_value: int, alignment: RoadAlignment = null, busy_value: float = 1.0) -> void:
	road_seed = seed_value
	align = alignment
	busy = busy_value
	_rng.seed = hash([seed_value, "road_layout"])
	_map_rng.seed = MAP_SEED

# ---------- queries ----------

## District at s: "city" or "outskirts".
func district_at(s: float) -> String:
	_ensure_districts(s)
	for d in _districts:
		if s < d.s1:
			return d.kind
	return _districts[-1].kind

## Lane-count change of side `oncoming` covering or after s, as a lane width
## in lanes: whole numbers outside tapers, between them inside one. What the
## road geometry follows (step 2).
func width_lanes(oncoming: bool, s: float) -> float:
	var n := float(MAX_LANES)
	_ensure(s)
	for c in changes:
		if c.s0 > s:
			break
		if c.kind != "drop" and c.kind != "add":
			continue
		if (c.side == "onc") != oncoming:
			continue
		if s >= c.s1:
			n = float(c.to)
		else:
			n = lerpf(float(c.from), float(c.to), smoothstep(c.s0, c.s1, s))
	return n

## Lanes traffic may drive in at s on that side: a dropping lane is gone from
## the start of its taper, an added one only counts once it is full width.
func lanes_at(oncoming: bool, s: float) -> int:
	var n := MAX_LANES
	_ensure(s)
	for c in changes:
		if c.s0 > s:
			break
		if (c.kind != "drop" and c.kind != "add") or (c.side == "onc") != oncoming:
			continue
		if c.kind == "drop":
			n = c.to
		elif s >= c.s1:
			n = c.to
		else:
			n = c.from
	return n

## Lane counts as the old fixed-section config expects them, at s.
func lanes_pair(s: float) -> Vector2i:
	return Vector2i(lanes_at(false, s), lanes_at(true, s))

## The next lane drop on that side starting after s (its taper start), or
## INF. Traffic starts merging from the first warning sign (step 3).
func next_drop(oncoming: bool, s: float) -> Dictionary:
	_ensure(s + WARN_FAR + DROP_TAPER)
	for c in changes:
		if c.kind == "drop" and (c.side == "onc") == oncoming and c.s0 > s:
			return c
	return {}

## Extra width between the carriageways at s, metres on top of the normal
## median (0 outside a split).
func median_extra(s: float) -> float:
	_ensure(s)
	for c in changes:
		if c.s0 > s:
			break
		if c.kind != "split" or s >= c.s1:
			continue
		if s < c.open_end:
			return c.width * smoothstep(c.s0, c.open_end, s)
		if s < c.close_start:
			return c.width
		return c.width * (1.0 - smoothstep(c.close_start, c.s1, s))
	return 0.0

## Every change that overlaps [a, b].
func changes_between(a: float, b: float) -> Array[Dictionary]:
	_ensure(b)
	var out: Array[Dictionary] = []
	for c in changes:
		if c.s0 > b:
			break
		if c.s1 >= a:
			out.append(c)
	return out

## Generates the plan at least as far as s.
func ensure(s: float) -> void:
	_ensure(s)

# ---------- generation ----------

func _ensure(s: float) -> void:
	if busy <= 0.0:
		return
	while _gen_to < s + DROP_TAPER + WARN_FAR:
		_generate_next()

func _ensure_districts(s: float) -> void:
	while _districts.is_empty() or _districts[-1].s1 <= s:
		var s0: float = 0.0 if _districts.is_empty() else _districts[-1].s1
		var kind := "city" if _districts.size() % 2 == 0 else "outskirts"
		var r := CITY_LEN if kind == "city" else OUTSKIRTS_LEN
		_districts.append({"s0": s0, "s1": s0 + _map_rng.randf_range(r.x, r.y), "kind": kind})

func _spacing(s: float) -> float:
	if busy > 1.0:
		return busy
	var r := CITY_GAP if district_at(s) == "city" else OUTSKIRTS_GAP
	return _rng.randf_range(r.x, r.y)

## Whether a change over [a, b] sits on a tight bend or a kicker crest.
func _shape_blocks(a: float, b: float) -> bool:
	if align == null:
		return false
	for i in range(floori(a / L), floori(b / L) + 1):
		if i < 0:
			continue
		if absf(align.curvature(i)) > 1.0 / MIN_CHANGE_RADIUS:
			return true
		if align.vcurve(i) < -1.0 / RoadAlignment.CREST_MIN_RADIUS - 1e-6:
			return true
	return false

func _generate_next() -> void:
	var s0 := _next_s
	var change := _pick(s0)
	# Slide forward off tight bends and kicker crests (at most 2 km).
	var tries := 0
	while _shape_blocks(change.s0 - (WARN_FAR if change.kind == "drop" else 0.0), change.s1) and tries < 40:
		var shift := L
		change.s0 += shift
		change.s1 += shift
		for k in ["open_end", "close_start"]:
			if change.has(k):
				change[k] += shift
		tries += 1
	if tries >= 40:
		# No clear stretch: skip this change, try again further on.
		_next_s = s0 + 2000.0
		_gen_to = _next_s
		return
	_apply(change)
	changes.append(change)
	var gap := _spacing(change.s1)
	# A drop needs its warning stretch clear of the change before it.
	_next_s = change.s1 + maxf(gap, WARN_FAR + 50.0)
	_gen_to = change.s1

## Chooses the next change starting at s0 (before any bend shift).
func _pick(s0: float) -> Dictionary:
	# Drift back: a side that has been short of lanes for DRIFT_BACK gets one
	# back, the one that has waited longest first.
	var due := ""
	for side in ["own", "onc"]:
		var since: float = _away_since[side]
		if since >= 0.0 and s0 - since >= DRIFT_BACK and (due == "" or since < _away_since[due]):
			due = side
	if due != "":
		return _lane_change(due, true, s0)
	var r := _rng.randf() * (W_LANE + W_SPLIT + W_EXIT)
	if r < W_LANE:
		var side := "own" if _rng.randf() < 0.5 else "onc"
		var n := _own if side == "own" else _onc
		var add: bool
		if n <= MIN_LANES:
			add = true
		elif n >= MAX_LANES:
			add = false
		else:
			add = _rng.randf() < 0.5
		return _lane_change(side, add, s0)
	if r < W_LANE + W_SPLIT:
		var open_end := s0 + SPLIT_TAPER
		var close_start := open_end + _rng.randf_range(SPLIT_HOLD.x, SPLIT_HOLD.y)
		return {"kind": "split", "side": "both", "s0": s0, "s1": close_start + SPLIT_TAPER,
			"open_end": open_end, "close_start": close_start, "width": _rng.randf_range(SPLIT_WIDTH.x, SPLIT_WIDTH.y)}
	return {"kind": "exit", "side": "own", "s0": s0, "s1": s0 + _rng.randf_range(EXIT_LOOP.x, EXIT_LOOP.y)}

func _lane_change(side: String, add: bool, s0: float) -> Dictionary:
	var n := _own if side == "own" else _onc
	var to := mini(n + 1, MAX_LANES) if add else maxi(n - 1, MIN_LANES)
	var taper := ADD_TAPER if add else DROP_TAPER
	return {"kind": "add" if add else "drop", "side": side, "s0": s0, "s1": s0 + taper, "from": n, "to": to}

func _apply(c: Dictionary) -> void:
	if c.kind == "drop" or c.kind == "add":
		if c.side == "own":
			_own = c.to
		else:
			_onc = c.to
		if c.to == MAX_LANES:
			_away_since[c.side] = -1.0
		elif _away_since[c.side] < 0.0:
			_away_since[c.side] = c.s1
