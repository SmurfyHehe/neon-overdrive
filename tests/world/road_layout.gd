extends SceneTree

# Road layout plan test (road lane proposal step 1, 2026-10-08). Headless, no
# game: RoadLayout on its own, over a long road.
#
# 1. Same seed, same plan, in any request order: one layout is generated
#    front to back, another is asked at random distances first; the change
#    lists must match exactly.
# 2. Every rule of proposal section 3 holds over RUN_KM of road with the
#    bendiest, hilliest alignment (and kickers): lanes 2-4 per side, one
#    lane at a time from the outside, taper lengths, district spacing, a
#    drop's warning stretch clear, no change on a tight bend or kicker crest,
#    drift back to 4+4.
# 3. Districts are the same for every road seed (fixed map).
# 4. Busy-ness: 0 makes no changes, a spacing makes one about that often.
# 5. Step 1 is invisible: with lanes_live off, game.gd's sections stay 4+4.
#
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/world/road_layout.gd

const RUN_KM := 200.0
const SEED := 7071

var fails: Array[String] = []

func _initialize() -> void:
	var align := RoadAlignment.new(SEED, 1.0, 1.0, 0.3)
	var lay := RoadLayout.new(SEED, align)
	var end_s := RUN_KM * 1000.0
	lay.ensure(end_s)

	# 1. Order independence.
	var other := RoadLayout.new(SEED, RoadAlignment.new(SEED, 1.0, 1.0, 0.3))
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 200:
		var s := rng.randf_range(0.0, end_s)
		other.width_lanes(rng.randf() < 0.5, s)
		other.median_extra(s)
		other.district_at(s)
	other.ensure(end_s)
	var n := mini(lay.changes.size(), other.changes.size())
	var same := n > 0
	for i in n:
		if str(lay.changes[i]) != str(other.changes[i]):
			same = false
			_check(false, "1: change %d differs: %s vs %s" % [i, lay.changes[i], other.changes[i]])
			break
	print("1. order: %d changes in %.0f km, random-order copy matches: %s" % [lay.changes.size(), RUN_KM, same])

	# 2. Rules.
	var counts := {"drop": 0, "add": 0, "split": 0, "exit": 0}
	var lanes := {"own": 4, "onc": 4}
	var prev_end := -INF
	var away_start := {"own": -1.0, "onc": -1.0}
	var longest_away := 0.0
	var gaps := {"city": [], "outskirts": []}
	var at_44 := 0.0
	var last_s := 0.0
	for c in lay.changes:
		if c.s1 > end_s:
			break
		counts[c.kind] += 1
		# Time at 4+4.
		if lanes.own == 4 and lanes.onc == 4:
			at_44 += c.s0 - last_s
		last_s = c.s0
		var gap: float = c.s0 - prev_end
		var dist := lay.district_at(prev_end) if prev_end > 0.0 else "city"
		if prev_end > 0.0:
			gaps[dist].append(gap)
			_check(gap >= RoadLayout.CITY_GAP.x - 1.0, "2: change at %.0f only %.0f m after the last" % [c.s0, gap])
		if c.kind == "drop":
			_check(gap >= RoadLayout.WARN_FAR or prev_end < 0.0, "2: drop at %.0f has %.0f m of warning stretch" % [c.s0, gap])
		if c.kind == "drop" or c.kind == "add":
			var side: String = c.side
			_check(c.from == lanes[side], "2: %s at %.0f starts from %d lanes, road has %d" % [c.kind, c.s0, c.from, lanes[side]])
			_check(absi(c.to - c.from) == 1, "2: %s at %.0f changes %d lanes" % [c.kind, c.s0, absi(c.to - c.from)])
			_check(c.to >= RoadLayout.MIN_LANES and c.to <= RoadLayout.MAX_LANES, "2: %d lanes at %.0f" % [c.to, c.s0])
			var taper: float = c.s1 - c.s0
			var want := RoadLayout.DROP_TAPER if c.kind == "drop" else RoadLayout.ADD_TAPER
			_check(absf(taper - want) < 0.01, "2: %s taper %.0f m, want %.0f" % [c.kind, taper, want])
			lanes[side] = c.to
			if c.to < 4 and away_start[side] < 0.0:
				away_start[side] = c.s1
			elif c.to == 4 and away_start[side] >= 0.0:
				longest_away = maxf(longest_away, c.s0 - away_start[side])
				away_start[side] = -1.0
		_check(not lay._shape_blocks(c.s0 - (RoadLayout.WARN_FAR if c.kind == "drop" else 0.0), c.s1), "2: %s at %.0f on a tight bend or kicker" % [c.kind, c.s0])
		prev_end = c.s1
	# Width and lanes queries agree with the list.
	for i in 400:
		var s := rng.randf_range(0.0, end_s)
		for onc in [false, true]:
			var w := lay.width_lanes(onc, s)
			var k := lay.lanes_at(onc, s)
			_check(w >= 2.0 - 1e-4 and w <= 4.0 + 1e-4, "2: width %.2f lanes at %.0f" % [w, s])
			_check(k >= 2 and k <= 4 and absf(w - k) < 1.0, "2: %d lanes vs width %.2f at %.0f" % [k, w, s])
	at_44 += end_s - last_s
	var mean := func(a: Array) -> float:
		var t := 0.0
		for x in a:
			t += x
		return t / maxf(a.size(), 1.0)
	print("2. rules: %s; city gaps mean %.0f m (%d), outskirts %.0f m (%d); longest away from 4 lanes %.0f m; %.0f%% of the road at 4+4" % [
		counts, mean.call(gaps.city), gaps.city.size(), mean.call(gaps.outskirts), gaps.outskirts.size(), longest_away, 100.0 * at_44 / end_s])
	_check(counts.drop > 0 and counts.add > 0 and counts.split > 0 and counts.exit > 0, "2: not every kind of change appears: %s" % [counts])
	_check(mean.call(gaps.city) < mean.call(gaps.outskirts), "2: city changes are not more frequent than outskirts ones")
	# Drift back: back to 4 within DRIFT_BACK plus one outskirts spacing (two
	# if the other side was due first) and a bend shift (2 km).
	var limit := RoadLayout.DRIFT_BACK + 2.0 * RoadLayout.OUTSKIRTS_GAP.y + 2000.0 + RoadLayout.DROP_TAPER
	_check(longest_away <= limit, "2: %.0f m away from 4 lanes (limit %.0f)" % [longest_away, limit])

	# 3. Fixed districts.
	var lay2 := RoadLayout.new(SEED + 1, RoadAlignment.new(SEED + 1, 0.5, 0.5))
	var districts_same := true
	for s in range(0, int(end_s), 997):
		if lay.district_at(float(s)) != lay2.district_at(float(s)):
			districts_same = false
	var changes_differ := str(lay.changes_between(0.0, 20000.0)) != str(lay2.changes_between(0.0, 20000.0))
	print("3. districts identical across seeds: %s; changes differ: %s" % [districts_same, changes_differ])
	_check(districts_same, "3: districts change with the road seed")
	_check(changes_differ, "3: two road seeds gave the same changes")

	# 4. Busy-ness.
	var none := RoadLayout.new(SEED, null, 0.0)
	_check(none.changes_between(0.0, 50000.0).is_empty() and none.lanes_at(false, 30000.0) == 4, "4: busy 0 still changes the road")
	var dense := RoadLayout.new(SEED, null, 600.0)
	var dc := dense.changes_between(0.0, 30000.0)
	var dgap := 0.0
	for i in range(1, dc.size()):
		dgap += dc[i].s0 - dc[i - 1].s1
	dgap /= maxf(dc.size() - 1, 1)
	print("4. busy 0: %d changes; busy 600 m: %d changes in 30 km, mean gap %.0f m" % [none.changes.size(), dc.size(), dgap])
	_check(dgap >= 590.0 and dgap <= 700.0, "4: busy 600 gives a %.0f m mean gap" % dgap)

	# 5. Game sections stay 4+4 while lanes_live is off.
	var game: Node = (load("res://Game.tscn") as PackedScene).instantiate()
	RoadFrame.layout = lay
	var bad := 0
	for idx in range(-2, 4000):
		var cfg: Dictionary = game.call("_section_at", idx)
		if cfg.own_lanes != 4 or cfg.onc_lanes != 4:
			bad += 1
	game.free()
	RoadFrame.layout = null
	print("5. game sections not 4+4 with lanes_live off: %d of 4002" % bad)
	_check(bad == 0, "5: %d sections are not 4+4" % bad)

	for f in fails:
		printerr("FAIL: ", f)
	print("RESULT: ", "PASS" if fails.is_empty() else "FAIL")
	quit(0 if fails.is_empty() else 1)

func _check(ok: bool, msg: String) -> void:
	if not ok and fails.size() < 30:
		fails.append(msg)
