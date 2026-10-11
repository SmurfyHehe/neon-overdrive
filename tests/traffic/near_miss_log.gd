extends SceneTree

# Near-miss log unit test (scripts/traffic/near_miss_log.gd).
#
#   godot --headless --fixed-fps 120 --path . -s res://tests/traffic/near_miss_log.gd
#
# Cars are placed by writing the manager's position index directly (the log
# reads nothing else), then the check is run by hand, so each case is exact and
# independent of the physics. Asserts: the kind, who moved and what the car
# was doing for a side pass, a nose and a tail closing, a touch, a spawn tag,
# a car that was just far enough away (no record), the per-car 3 s gap, the
# counters on the manager, the file and its summary line, and that the check
# costs under COST_MAX_MS per physics tick on average with 16 cars on the road.

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const NearMissLog := preload("res://scripts/traffic/near_miss_log.gd")
const RATE := 120
const COST_MAX_MS := 0.02
const COST_SECS := 6.0
const FILE := "user://near_miss_unit.txt"

var logger := Harness.ErrorCounter.new()
var game: Node
var traffic: TrafficManager
var nm
var fails: Array[String] = []
var done_cases := false
var cost_from_ticks := 0
var cost_from_usec := 0
var end_tick := 0

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	OS.set_environment("NEON_CURVES", "0.0")
	OS.set_environment("NEON_HILLS", "0.0")
	OS.set_environment("NEON_NEAR_MISS_LOG", "")
	OS.set_environment("NEON_NEAR_MISS_FILE", FILE)
	var g := ProjectSettings.globalize_path(FILE)
	if FileAccess.file_exists(FILE):
		DirAccess.remove_absolute(g)   # this test's own scratch file
	game = Harness.boot(self, 16, 300.0, 5, 300.0)

func _physics_process(_delta: float) -> bool:
	var p: PlayerCar = game.get("player")
	if p == null or not p.is_ready or Engine.get_physics_frames() < RATE:
		return false
	if not done_cases:
		done_cases = true
		traffic = game.get("traffic")
		nm = traffic.near_miss
		if nm == null:
			fails.append("the log is not on by default")
			return _end()
		_cases()
		cost_from_ticks = nm.ticks_seen
		cost_from_usec = nm.cost_usec
		end_tick = Engine.get_physics_frames() + int(COST_SECS * RATE)
		return false
	if Engine.get_physics_frames() >= end_tick:
		var ticks: int = nm.ticks_seen - cost_from_ticks
		var ms: float = float(nm.cost_usec - cost_from_usec) / 1000.0 / float(maxi(ticks, 1))
		print("near_miss_log: check cost %.4f ms per physics tick over %d ticks (16 cars; budget %.2f)" % [ms, ticks, COST_MAX_MS])
		if ms > COST_MAX_MS:
			fails.append("the check costs %.4f ms per tick (limit %.2f)" % [ms, COST_MAX_MS])
		return _end()
	return false

# ---------- cases ----------

## Index entry of cars[i] is i + 1. Writes x range, z, z-velocity, half length.
func _put(i: int, x: float, hw: float, z: float, vz: float, hl := 1.7) -> TrafficCar:
	var k := i + 1
	traffic._lo[k] = x - hw
	traffic._hi[k] = x + hw
	traffic._z[k] = z
	traffic._vz[k] = vz
	traffic._hl[k] = hl
	var car := traffic.cars[i]
	car.global_transform = RoadFrame.pose(x, car.rest_y, z, 0.0)   # a car mid lane change is read from its node
	return car

func _far(from_i: int) -> void:
	for i in range(from_i, traffic.cars.size()):
		_put(i, 0.0, 1.0, 900.0 + 30.0 * i, 0.0)

func _player(x: float, vz: float) -> void:
	traffic._lo[0] = x - 1.0
	traffic._hi[0] = x + 1.0
	traffic._z[0] = 0.0
	traffic._vz[0] = vz
	traffic._hl[0] = 2.2

## Runs the check twice (the second one finds the crossing over and writes it).
func _run(away := true) -> void:
	nm._check()
	if away:
		_far(0)
	nm._check()

func _last() -> Dictionary:
	return nm.records.back() if not nm.records.is_empty() else {}

func _expect(label: String, rec: Dictionary, kind: String, who: String, doing: String) -> void:
	if rec.is_empty():
		fails.append("%s: no record" % label)
		return
	if rec.kind != kind or rec.who != who or rec.doing != doing:
		fails.append("%s: got %s / %s / %s, wanted %s / %s / %s" % [label, rec.kind, rec.who, rec.doing, kind, who, doing])
	else:
		print("  ok  %-26s -> %s" % [label, NearMissLog.line_for(rec)])

func _cases() -> void:
	traffic.flow = -1.0
	# Case 1: a car moves over beside you (mid lane change, unflashed), 0.3 m between bodies.
	_far(0)
	_player(1.6, -30.0)
	var a := _put(0, 1.6 + 1.0 + 0.3 + 0.9, 0.9, 1.0, -30.0)
	a.kind = "n2_cityhatch"
	a.changing = true
	a.doing = TrafficCar.DO_MOVING_OVER_UNFLASHED
	_run()
	_expect("side, car moved over", _last(), "side", "traffic", "moving_over_unflashed")
	if absf(float(_last().get("closest", 9.0)) - 0.3) > 0.05:
		fails.append("side: closest gap %.2f, wanted 0.3" % float(_last().get("closest", 9.0)))
	a.changing = false
	a.doing = TrafficCar.DO_CRUISING
	a.spawn_frame = -1000000

	# Case 2: same pass, nobody moving, 0.3 m: close but nobody's fault.
	nm._t += 4.0
	_far(0)
	_put(0, 1.6 + 2.2, 0.9, 1.0, -30.0)
	_run()
	_expect("side, nobody moved", _last(), "side", "neither", "cruising")

	# Case 3: you slide toward a car beside you (your sideways speed over 1 m/s).
	nm._t += 4.0
	nm._have_p = true
	nm._p_x = 1.6 - 0.2   # you were 0.2 m to the left a check ago, 30 checks/s: 6 m/s
	nm._last_check_t = nm._t - 1.0 / 30.0
	_far(0)
	_put(0, 1.6 + 2.2, 0.9, 1.0, -30.0)
	nm._check()
	_far(0)
	nm._check()
	_expect("side, you moved", _last(), "side", "you", "cruising")

	# Case 4: you come up on a slower car in your lane: nose, you closed from behind.
	nm._t += 4.0
	_far(0)
	_put(0, 1.6, 0.9, -12.0, -20.0)
	_run()
	_expect("nose, you closed", _last(), "nose", "you", "cruising")
	if float(_last().get("ttc", 9.0)) > 1.0:
		fails.append("nose: time to contact %.2f over a second" % float(_last().get("ttc", 9.0)))

	# Case 5: a faster car comes up behind you in your lane: tail, traffic.
	nm._t += 4.0
	_far(0)
	_put(0, 1.6, 0.9, 10.0, -45.0)
	_run()
	_expect("tail, car closed", _last(), "tail", "traffic", "cruising")

	# Case 6: a car pulls out and cuts in front of you (mid change, same corridor).
	nm._t += 4.0
	_far(0)
	var c := _put(0, 1.6 + 0.4, 0.9, -9.0, -22.0)
	c.changing = true
	c.doing = TrafficCar.DO_RB_CUT_IN
	_run()
	_expect("nose, car cut in", _last(), "nose", "traffic", "rule_breaker_cut_in")
	c.changing = false
	c.doing = TrafficCar.DO_CRUISING

	# Case 7: bodies overlap.
	nm._t += 4.0
	_far(0)
	_put(0, 1.6 + 1.0, 0.9, 0.5, -30.0)
	_run()
	_expect("touch", _last(), "touch", "neither", "cruising")

	# Case 8: a car that spawned behind 2 s ago and is now beside you.
	nm._t += 4.0
	_far(0)
	var d := _put(0, 1.6 + 2.2, 0.9, 1.0, -30.0)
	d.spawn_frame = Engine.get_physics_frames() - 2 * RATE
	d.spawned_behind = true
	_run()
	_expect("side, spawned behind", _last(), "side", "neither", "spawned_behind")
	d.spawn_frame = -1000000

	# Case 9: 0.6 m between bodies is not a near miss; neither is a car 60 m ahead.
	nm._t += 4.0
	var before: int = nm.count
	_far(0)
	_put(0, 1.6 + 1.0 + 0.6 + 0.9, 0.9, 1.0, -30.0)
	_put(1, 1.6, 0.9, -60.0, -10.0)
	_run()
	if nm.count != before:
		fails.append("0.6 m beside and 60 m ahead counted as %d near misses" % (nm.count - before))

	# Case 10: the same car again within 3 s writes nothing more.
	nm._t += 4.0
	_far(0)
	_put(0, 1.6 + 2.2, 0.9, 1.0, -30.0)
	_run()
	var n1: int = nm.count
	nm._t += 1.0
	_far(0)
	_put(0, 1.6 + 2.2, 0.9, 1.0, -30.0)
	_run()
	if nm.count != n1:
		fails.append("a second record for the same car 1 s later (%d -> %d)" % [n1, nm.count])

	# Counters on the manager, the file and the summary.
	if traffic.near_miss_count != nm.count or traffic.near_miss_count < 8:
		fails.append("manager counter %d, log counter %d" % [traffic.near_miss_count, nm.count])
	if traffic.near_miss_records.size() != nm.records.size():
		fails.append("manager records %d vs %d" % [traffic.near_miss_records.size(), nm.records.size()])
	var causes: Dictionary = traffic.near_miss_by_cause
	for key in ["traffic:moving_over_unflashed", "you", "neither", "traffic:cruising", "traffic:rule_breaker_cut_in"]:
		if not causes.has(key):
			fails.append("no counter for cause '%s' (have %s)" % [key, str(causes.keys())])
	var s: String = nm.summary_text()
	print("  summary: ", s)
	if not s.contains("close calls") or not s.contains("traffic caused") or not s.contains("you caused"):
		fails.append("summary line: " + s)
	# Leave the road tidy for the cost run: every car placed afresh.
	nm._pending.clear()
	for car in traffic.cars:
		car.changing = false
		traffic._respawn(car)

func _file_text() -> String:
	var f := FileAccess.open(FILE, FileAccess.READ)
	return f.get_as_text() if f != null else ""

func _end() -> bool:
	if nm != null:
		nm.finish()
		var txt := _file_text()
		if txt == "":
			fails.append("no file written at " + ProjectSettings.globalize_path(FILE))
		else:
			if not txt.contains("==== game start"):
				fails.append("no header line in the file")
			if not txt.contains("moved over into you (not flashed)"):
				fails.append("the moved-over line is not in the file")
			if not txt.contains("last "):
				fails.append("no summary line in the file")
			print("  file: %d lines, %d bytes at %s" % [txt.count("\n"), txt.length(), ProjectSettings.globalize_path(FILE)])
	if not logger.errors.is_empty():
		fails.append("%d engine errors, first: %s" % [logger.errors.size(), logger.errors[0]])
	for f in fails:
		printerr("FAIL: " + f)
	print("near_miss_log: %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(1 if not fails.is_empty() else 0)
	return true
