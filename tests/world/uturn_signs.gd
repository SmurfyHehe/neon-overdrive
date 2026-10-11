extends SceneTree

# Signed U-turns (T1): the barrier's two kinds of opening read differently.
#
# The map's gaps (RoadMap.gaps, one at the start of each district that has no
# crossing there; ring sites R1 moved them) are legal U-turns; the
# emergency crossovers (RoadBarriers.has_gap, about one per district) are for
# cops. RoadBarriers.gap_kind() says which a chunk's opening is, and the signs
# and paint are decided from that and the chunk number alone.
#
# Checks (act 1, every lap chunk, plus the next lap):
# - gap_kind is "uturn" exactly on RoadMap.gap_in chunks, "emergency" only on
#   RoadBarriers.has_gap chunks that are not also map gaps, "" everywhere else,
#   and the same one lap on;
# - a "uturn" chunk carries a median U-turn sign for each direction, one lamp
#   head, and the advance signs stand 4 chunks before it (own side) and 4
#   after it (oncoming); an "emergency" chunk carries two no-U-turn signs and
#   no lamp, and nothing announces it;
# - paint: a U-arrow in the inner lane 2 and 1 chunks before a "uturn" chunk
#   (own side) and 1 and 2 after it (oncoming, turned round), and nowhere else;
# - built chunks: the sign MultiMesh draws the parts, and a "uturn" chunk has
#   one more lamp pool than lamp posts.
#
# Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/world/uturn_signs.gd

const RoadMap := preload("res://scripts/world/road_map.gd")
const RoadPaint := preload("res://scripts/world/road_paint.gd")
const RoadSigns := preload("res://scripts/world/road_signs.gd")
const WordAtlas := preload("res://scripts/world/word_atlas.gd")
const Districts := preload("res://scripts/world/districts.gd")
const B := preload("res://scripts/world/road_chunk_builder.gd")

var failures: Array[String] = []
var checks := 0

func _check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		failures.append(msg)

func _initialize() -> void:
	RoadFrame.align = null
	RoadFrame.layout = null
	RoadFrame.origin_index = 0
	RoadMap.use(0, 1)
	_kinds()
	_signs()
	_paint()
	_built()
	print("uturn_signs: %d checks, %d failed" % [checks, failures.size()])
	for f in failures:
		print("FAIL ", f)
	quit(1 if not failures.is_empty() else 0)

func _kinds() -> void:
	var n := RoadMap.period
	var uturns := 0
	var emergencies := 0
	for c in n:
		var k := RoadBarriers.gap_kind(c)
		var map_gap := RoadMap.gap_in(c)
		var cross := RoadBarriers.has_gap(c)
		if map_gap:
			uturns += 1
			_check(k == "uturn", "chunk %d is a map gap but its kind is '%s'" % [c, k])
		elif cross:
			emergencies += 1
			_check(k == "emergency", "chunk %d is a crossover but its kind is '%s'" % [c, k])
		else:
			_check(k == "", "chunk %d has no opening but its kind is '%s'" % [c, k])
		_check(RoadBarriers.gap_kind(c + n) == k and RoadBarriers.gap_kind(c - n) == k, "chunk %d has a different kind one lap on" % c)
	_check(uturns == RoadMap.gaps().size(), "%d chunks are U-turns for %d map gaps" % [uturns, RoadMap.gaps().size()])
	_check(emergencies > 0, "no emergency crossover on the lap that is not also a map gap")
	print("uturn_signs: %d U-turn chunks, %d emergency crossovers on a %d-chunk lap" % [uturns, emergencies, n])

func _count(signs: Array, part: String) -> int:
	var c := 0
	for s in signs:
		if s.part == part:
			c += 1
	return c

func _signs() -> void:
	var n := RoadMap.period
	var ahead := int(round(RoadSigns.UTURN_ADVANCE_M / B.CHUNK_LEN))
	_check(ahead == 4, "the advance sign is %d chunks before, expected 4 (200 m)" % ahead)
	for c in n:
		var sigs := B.rule_signs(c)
		var k := RoadBarriers.gap_kind(c)
		var med := 0
		var lamps := 0
		for s in sigs:
			if s.part == "median":
				med += 1
				_check(s.kind == k, "chunk %d: a median sign of kind '%s' on a '%s' opening" % [c, s.kind, k])
				if s.lamp:
					lamps += 1
		_check(med == (2 if k != "" else 0), "chunk %d (%s) has %d median signs" % [c, k, med])
		_check(lamps == (1 if k == "uturn" else 0), "chunk %d (%s) has %d lamp heads" % [c, k, lamps])
		var own_adv := RoadBarriers.gap_kind(c + ahead) == "uturn"
		var onc_adv := RoadBarriers.gap_kind(c - ahead) == "uturn"
		var advs := _count(sigs, "advance")
		_check(advs == int(own_adv) + int(onc_adv), "chunk %d has %d advance signs, expected %d" % [c, advs, int(own_adv) + int(onc_adv)])
	# the parts: a U-turn sign is a pole, a panel, an arrow (+ arm and head with a lamp);
	# a no-U-turn sign adds the ring
	var u := RoadSigns.median_parts("uturn", 1.0, false)
	var ul := RoadSigns.median_parts("uturn", 1.0, true)
	var e := RoadSigns.median_parts("emergency", -1.0, false)
	_check(u.size() == 3 and ul.size() == 5 and e.size() == 4, "median parts: %d / %d / %d (expected 3 / 5 / 4)" % [u.size(), ul.size(), e.size()])
	var adv := RoadSigns.uturn_advance(Vector3(14.0, 0.0, -15.0), 0.0, 1.0)
	var low := 1e9
	for it in adv:
		var xf: Transform3D = it.xf
		if int(it.cd.a) == RoadSigns.PANEL:
			low = xf.origin.y - xf.basis.get_scale().y / 2.0
			_check(xf.origin.x < 14.0, "the advance sign's panel is not over the road side of its post")
	_check(low >= 2.0, "the advance sign's panel is only %.2f m up" % low)
	var red := false
	for it in e:
		if int(it.cd.b) == RoadSigns.RED:
			red = true
	_check(red, "the no-U-turn sign has no red ring")
	_check(WordAtlas.layer_count() <= 32, "the atlas has %d layers (32 max)" % WordAtlas.layer_count())

func _paint() -> void:
	var n := RoadMap.period
	var inner := B.MEDIAN_GAP + 0.5 * B.LANE_W
	var layer := WordAtlas.layer("#UTURN")
	_check(layer >= 0, "no atlas layer for the U-turn arrow")
	var arrows := 0
	for c in range(0, n):
		var marks := RoadPaint.marks(c, Districts.name_at(c), Districts.RUN, 2, false, INF, B.MEDIAN_GAP, B.LANE_W, B.CHUNK_LEN)
		var own := 0
		var onc := 0
		for m in marks:
			if int(m.cd.r) != layer:
				continue
			arrows += 1
			if m.x > 0.0:
				own += 1
				_check(absf(m.x - inner) < 0.01 and absf(m.yaw) < 0.001, "chunk %d: an own-side U-arrow at x %.2f yaw %.2f" % [c, m.x, m.yaw])
			else:
				onc += 1
				_check(absf(m.x + inner) < 0.01 and absf(absf(m.yaw) - PI) < 0.001, "chunk %d: an oncoming U-arrow at x %.2f yaw %.2f" % [c, m.x, m.yaw])
		var want_own := int(RoadBarriers.uturn_at(c + 2)) + int(RoadBarriers.uturn_at(c + 1))
		var want_onc := int(RoadBarriers.uturn_at(c - 2)) + int(RoadBarriers.uturn_at(c - 1))
		_check(own == want_own and onc == want_onc, "chunk %d draws %d / %d U-arrows (own / oncoming), expected %d / %d" % [c, own, onc, want_own, want_onc])
	_check(arrows == RoadMap.gaps().size() * 4, "%d U-arrows for %d gaps (expected 4 each)" % [arrows, RoadMap.gaps().size()])

func _built() -> void:
	var n := RoadMap.period
	var u := -1
	var e := -1
	for c in range(Districts.RUN, n):
		if u < 0 and RoadBarriers.gap_kind(c) == "uturn" and RoadBarriers.gap_kind(c - 4) == "" and RoadBarriers.gap_kind(c + 4) == "":
			u = c
		if e < 0 and RoadBarriers.gap_kind(c) == "emergency":
			e = c
	_check(u >= 0 and e >= 0, "no chunk to build (U-turn %d, emergency %d)" % [u, e])
	if u < 0 or e < 0:
		return
	var cfg := {"own_lanes": 2, "onc_lanes": 2, "barrier": "concrete", "gap": false, "gap_kind": ""}
	var gap_cfg := {"own_lanes": 2, "onc_lanes": 2, "barrier": "concrete", "gap": true, "gap_kind": "uturn"}
	var counts := {}
	var extra_pool := {}
	for what in [["uturn", u, gap_cfg], ["before", u - 4, cfg], ["after", u + 4, cfg], ["emergency", e, gap_cfg], ["plain", u + 1, cfg]]:
		var root := B.build_chunk(int(what[1]), cfg, what[2])
		var signs := (root.get_node(^"NameSigns") as MultiMeshInstance3D)
		var pools := (root.get_node(^"LampPools") as MultiMeshInstance3D).multimesh
		var lamps := (root.get_node(^"Lamps") as MultiMeshInstance3D).multimesh
		counts[what[0]] = signs.multimesh.visible_instance_count
		extra_pool[what[0]] = pools.visible_instance_count - lamps.visible_instance_count
		_check(signs.visible == (counts[what[0]] > 0), "chunk %s: NameSigns visible %s with %d parts" % [what[0], signs.visible, counts[what[0]]])
		root.free()
	# U-turn chunk: two U-turn signs (3 parts each) + lamp arm and head; the advance chunks: pole, panel, arrow
	_check(counts.uturn >= 8, "the U-turn chunk draws %d sign parts (expected 8)" % counts.uturn)
	# a chunk 200 m from this opening may also be 200 m from the next or the
	# last one (gaps are 8 chunks apart): 3 parts per advance sign
	for w in [["before", u - 4], ["after", u + 4]]:
		# (an exit gantry in the same chunk is 8 more: post, arm, panel, 3 lines, 2 lamps)
		var want := 3 * _count(B.rule_signs(int(w[1])), "advance") + 8 * _count(B.rule_signs(int(w[1])), "exit")
		if B.name_sign_kind(int(w[1])) != "":
			continue
		_check(want >= 3 and counts[w[0]] == want, "the chunk 200 m %s draws %d parts (expected %d)" % [w[0], counts[w[0]], want])
	_check(counts.emergency >= 8, "the emergency chunk draws %d sign parts (expected 8)" % counts.emergency)
	_check(extra_pool.uturn == 1, "the U-turn chunk has %d more lamp pools than lamp posts (expected 1)" % extra_pool.uturn)
	_check(extra_pool.emergency == 0 and extra_pool.plain == 0, "an ordinary or emergency chunk has extra lamp pools: %s" % [extra_pool])
