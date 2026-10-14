extends SceneTree

# The wrong-way classifier (PoliceRules.is_wrong_way), no game and no nodes.
# Wrong way = TRAVELLING against the flow of the carriageway the car is on,
# not being on one half of the road. The +x carriageway flows down the road
# (-z), the -x one back up it (+z).
# - the 8 cases: each side x each direction of travel x forward / reverse;
# - the speed line (PoliceRules.WRONG_WAY_KMH along the road);
# - the shoulder: backing up it under SHOULDER_BACK_KMH never counts, backing
#   up the lanes does, driving nose-first up the shoulder does;
# - the strip between the carriageways belongs to neither;
# - a spin (turning fast, or sliding across its own axis) never counts.
#   <godot> --headless --path . -s res://tests/traffic/wrong_way_pure.gd

const LANES := 4
const DOWN := Vector3(0, 0, -1)
const UP := Vector3(0, 0, 1)

var failures: Array[String] = []

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _wrong(x: float, travel: Vector3, kmh: float, nose: Vector3, yaw := 0.0) -> bool:
	return PoliceRules.is_wrong_way(x, travel * (kmh / 3.6), nose, LANES, yaw)

func _initialize() -> void:
	var lane := RoadChunkBuilder.lane_offset(1)
	# [side, travel, nose, wrong, what]
	var cases := [
		[1.0, DOWN, DOWN, false, "+x, forward down the road (with the flow)"],
		[1.0, UP, UP, true, "+x, forward up the road (turned round on its own side)"],
		[1.0, DOWN, UP, false, "+x, backing down the road (moving with the flow)"],
		[1.0, UP, DOWN, true, "+x, backing up the lanes"],
		[-1.0, UP, UP, false, "-x, forward up the road (turned round at a gap, legal)"],
		[-1.0, DOWN, DOWN, true, "-x, forward down the road (into the traffic)"],
		[-1.0, UP, DOWN, false, "-x, backing up the road (moving with the flow)"],
		[-1.0, DOWN, UP, true, "-x, backing down the lanes"],
	]
	for c in cases:
		var got := _wrong(c[0] * lane, c[1], 40.0, c[2])
		_check(got == c[3], "%s: wrong way %s, expected %s" % [c[4], got, c[3]])
		print("  %-58s -> %s" % [c[4], "WRONG WAY" if got else "ok"])
	# The speed line.
	_check(not _wrong(lane, UP, PoliceRules.WRONG_WAY_KMH - 1.0, UP), "under the speed line counted")
	_check(_wrong(lane, UP, PoliceRules.WRONG_WAY_KMH + 1.0, UP), "over the speed line did not count")
	_check(not _wrong(lane, Vector3(-1, 0, 0), 30.0, Vector3(-1, 0, 0)), "driving straight across the road counted")
	# The shoulder.
	var shoulder := RoadChunkBuilder.MEDIAN_GAP + LANES * RoadChunkBuilder.LANE_W + RoadChunkBuilder.SHOULDER_W * 0.5
	for side in [1.0, -1.0]:
		var back: Vector3 = UP if side > 0.0 else DOWN
		_check(PoliceRules.on_shoulder(side * shoulder, LANES) and not PoliceRules.on_shoulder(side * lane, LANES), "on_shoulder, side %+.0f" % side)
		_check(not _wrong(side * shoulder, back, 18.0, -back), "side %+.0f: backing up the shoulder at 18 km/h counted" % side)
		_check(_wrong(side * shoulder, back, 25.0, -back), "side %+.0f: backing up the shoulder at 25 km/h did not count" % side)
		_check(_wrong(side * shoulder, back, 18.0, back), "side %+.0f: nose-first up the shoulder at 18 km/h did not count" % side)
		_check(_wrong(side * lane, back, 18.0, -back), "side %+.0f: backing up the lanes at 18 km/h did not count" % side)
	# A narrower road: the shoulder moves in with the lanes.
	var edge2 := RoadChunkBuilder.MEDIAN_GAP + 2 * RoadChunkBuilder.LANE_W + 0.7
	_check(PoliceRules.on_shoulder(edge2, 2) and not PoliceRules.on_shoulder(edge2, 4), "the shoulder of a 2-lane side")
	# The strip between the carriageways.
	_check(PoliceRules.flow_at(0.1) == 0.0 and PoliceRules.flow_at(-0.1) == 0.0, "the centre strip has a flow")
	_check(PoliceRules.flow_at(lane) == -1.0 and PoliceRules.flow_at(-lane) == 1.0, "carriageway flows")
	_check(not _wrong(0.1, UP, 60.0, UP) and not _wrong(-0.1, DOWN, 60.0, DOWN), "on the centre strip counted")
	# A spin: turning fast, or sliding across its own axis, whichever way it moves.
	_check(not _wrong(lane, UP, 60.0, UP, PoliceRules.SPIN_YAW + 0.5), "turning fast counted")
	_check(not _wrong(lane, UP, 60.0, UP, -PoliceRules.SPIN_YAW - 0.5), "turning fast the other way counted")
	_check(not _wrong(lane, UP, 60.0, Vector3(1, 0, 0)), "sliding sideways up the road counted")
	_check(not _wrong(-lane, DOWN, 60.0, Vector3(1, 0, -0.9).normalized()), "sliding at ~48 degrees counted")
	_check(_wrong(lane, UP, 60.0, Vector3(0.3, 0, 1).normalized()), "a small drift angle the wrong way did not count")
	for f in failures:
		printerr("FAIL: " + f)
	print("wrong_way_pure: %s" % ("PASS" if failures.is_empty() else "FAIL (%d)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
