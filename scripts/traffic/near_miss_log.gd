extends RefCounted

# Near-miss log (traffic near-miss fix, step 1, 2026-10-10: Roy was nearly hit
# by traffic several times back to back and nothing recorded who moved).
# Checked at 30 Hz from TrafficManager, on the position index it already
# builds (_lo/_hi/_z/_vz/_hl, entry 0 is the player). Only cars within RANGE_M
# of the player along the road. One record per car per PER_CAR_S at most.
#
# Kinds
#   side   lengthwise overlap with the player, sideways gap between bodies
#          under SIDE_GAP
#   nose   a car ahead of the player, same corridor across the road, closing
#          faster than CLOSE_V, under CLOSE_T s to contact
#   tail   the same with the car behind the player
#   touch  bodies overlap, or a physics contact between player and car
# A crossing lasts a few checks, so a record is held open while the condition
# lasts (at most HOLD_S) and written with the closest gap and shortest time to
# contact seen.
#
# Who moved: "traffic" (the car was mid lane change, weaving, or edging toward
# you at over EDGE_V), "you" (your sideways speed toward it over YOU_V, or you
# closed on it from behind in its lane), "both", or "neither" (a pass that was
# simply close). What the car was doing is TrafficCar.doing, with
# spawned_behind / spawned_ahead for the first SPAWN_TAG_S after a spawn.
#
# Output: near-misses.txt next to the game exe in an exported build (where
# benchmark-results.txt goes), user://logs/near-misses.txt from the editor
# (test_near-misses.txt in test mode). NEON_NEAR_MISS_FILE overrides the path,
# NEON_NEAR_MISS_LOG=0 turns the log off. Appends; one header per game start;
# past MAX_BYTES the file becomes near-misses.old.txt (one old copy kept).
#
# No class_name on purpose: preload it, like drive_recorder.gd.

const TestMode := preload("res://scripts/core/test_mode.gd")

const CHECK_HZ := 30.0
const RANGE_M := 40.0
const SIDE_GAP := 0.5
const CLOSE_V := 3.0
const CLOSE_T := 1.0
const PER_CAR_S := 3.0
const HOLD_S := 0.5
const EDGE_V := 0.5
const YOU_V := 1.0
const TELEPORT_V := 8.0
const SPAWN_TAG_S := 5.0
const SUMMARY_EVERY_S := 60.0
const WINDOW_S := 600.0
const MAX_BYTES := 1048576
const KEEP_RECORDS := 200
const FILE_NAME := "near-misses.txt"
const OLD_NAME := "near-misses.old.txt"
const PATROL_GROUP := "patrol_cars"

const KIND_SIDE := "side"
const KIND_NOSE := "nose"
const KIND_TAIL := "tail"
const KIND_TOUCH := "touch"

const KIND_NAMES := {
	"n1_commuter": "commuter", "n2_cityhatch": "city hatch", "n3_pickup": "pickup", "c1_patrol": "patrol",
}
const TRAFFIC_PHRASE := {
	"moving_over_unflashed": "moved over into you (not flashed)",
	"moving_over_flashed": "moved over into you (flashed)",
	"passing": "pulled out to pass beside you",
	"obstacle": "changed lane round an obstacle next to you",
	"keep_right": "moved back right next to you",
	"rule_breaker_cut_in": "cut in on you (rule breaker)",
	"weaving": "weaved into you",
	"spawned_behind": "had just spawned behind you",
	"spawned_ahead": "had just spawned ahead of you",
	"yielding_to_traffic": "moved over for a car behind it, next to you",
	"abort": "was steering back out of your way",
	"swerve": "swerved round you",
	"pull_over_siren": "was pulling over for a siren next to you",
}

var tm: Node
var write_file := true
var path := ""
var records: Array[Dictionary] = []
var count := 0
var by_cause := {}
## The same records counted three other ways (the weave baseline prints them).
var by_kind := {}
var by_who := {}
var by_doing := {}
## What the check has seen, whether or not it was a near miss (the baseline
## prints these so a run with no records still says how close it got):
## cars looked at, the smallest sideways gap between bodies while overlapping
## lengthwise, the shortest time to contact in a shared corridor, and how many
## passes (per car, 3 s apart) came under LOOSE_GAP / LOOSE_T.
const LOOSE_GAP := 1.0
const LOOSE_T := 2.0
var evaluated := 0
var min_side_gap := INF
var min_ttc := INF
var loose_count := 0
var _loose_last := {}
## Tests: physics ticks seen and microseconds spent in step() over them.
var ticks_seen := 0
var cost_usec := 0

var _every := 4
var _acc := 0
var _t := 0.0            # driving seconds (sum of the physics deltas)
var _last_check_t := 0.0
var _check_no := 0
var _p_x := 0.0
var _have_p := false
var _px := {}            # car instance id -> its x at the last check
var _pt := {}            # ... and when
var _pending := {}       # car instance id -> the record held open
var _last_emit := {}     # car instance id -> _t of its last written record
var _events: Array = []  # [t, cause] over the last WINDOW_S, for the summary
var _next_summary := SUMMARY_EVERY_S
var _file: FileAccess
var _bytes := 0
var _boot_ms := 0
var _finished := false

func _init(manager: Node, to_file := true) -> void:
	tm = manager
	write_file = to_file
	_every = maxi(1, roundi(Engine.physics_ticks_per_second / CHECK_HZ))
	_boot_ms = Time.get_ticks_msec()
	if write_file:
		path = file_path()
		_open()

static func enabled() -> bool:
	return OS.get_environment("NEON_NEAR_MISS_LOG") != "0"

static func file_path() -> String:
	var o := OS.get_environment("NEON_NEAR_MISS_FILE")
	if o != "":
		return o
	if OS.has_feature("template"):
		return OS.get_executable_path().get_base_dir().path_join(FILE_NAME)
	return TestMode.path("user://logs/" + FILE_NAME)

# ---------- the check ----------

## Once per physics tick, after the manager's index is current.
func step(delta: float) -> void:
	ticks_seen += 1
	_t += delta
	_acc += 1
	if _acc < _every:
		return
	_acc = 0
	var t0 := Time.get_ticks_usec()
	_check()
	if _t >= _next_summary:
		_next_summary += SUMMARY_EVERY_S
		_summary()
	cost_usec += Time.get_ticks_usec() - t0

func _check() -> void:
	var m = tm
	var cars: Array = m.cars
	var n: int = m._z.size()
	if n < 2 or m._index_cars != cars.size() or m.player == null:
		return
	_check_no += 1
	var dt := _t - _last_check_t
	_last_check_t = _t
	var pxc: float = (m._lo[0] + m._hi[0]) * 0.5
	var phw: float = (m._hi[0] - m._lo[0]) * 0.5
	var pz: float = m._z[0]
	var pvz: float = m._vz[0]
	var phl: float = m._hl[0]
	var pvx := 0.0
	if _have_p and dt > 0.0:
		pvx = (pxc - _p_x) / dt
		if absf(pvx) > TELEPORT_V:
			pvx = 0.0
	_p_x = pxc
	_have_p = true
	var touching := {}
	var pl = m.player
	if pl is RigidBody3D and pl.get_contact_count() > 0:
		for b in pl.get_colliding_bodies():
			if b is TrafficCar:
				touching[b.get_instance_id()] = true
	for k in range(1, n):
		var dz: float = m._z[k] - pz
		if absf(dz) > RANGE_M:
			continue
		var car: TrafficCar = cars[k - 1]
		if car.benched:
			continue
		var x: float
		var hw: float
		if car.changing:
			x = RoadFrame.unroll(car.global_position).x
			hw = car.half_w
		else:
			x = (m._lo[k] + m._hi[k]) * 0.5
			hw = (m._hi[k] - m._lo[k]) * 0.5
		_eval(car, x, hw, dz, m._vz[k], m._hl[k], pxc, phw, pvz, phl, pvx, touching.has(car.get_instance_id()))
	if get_group_size() > 0:
		for node in m.get_tree().get_nodes_in_group(PATROL_GROUP):
			var pc := node as TrafficCar
			if pc == null or not pc.is_inside_tree():
				continue
			var u := RoadFrame.unroll(pc.global_position)
			var vz := RoadFrame.dir_to_road(u.z, pc.linear_velocity).z
			if absf(u.z - pz) <= RANGE_M:
				_eval(pc, u.x, pc.half_w, u.z - pz, vz, pc.half_l, pxc, phw, pvz, phl, pvx, touching.has(pc.get_instance_id()))
	_flush(false)
	if _px.size() > 256:
		_px.clear()
		_pt.clear()
	if _last_emit.size() > 256:
		_last_emit.clear()

func get_group_size() -> int:
	var t: SceneTree = tm.get_tree()
	return t.get_node_count_in_group(PATROL_GROUP) if t != null else 0

func _eval(car: TrafficCar, x: float, hw: float, dz: float, vz: float, hl: float,
		pxc: float, phw: float, pvz: float, phl: float, pvx: float, contact: bool) -> void:
	var id := car.get_instance_id()
	# The car's own sideways speed, from its x at the last check.
	var car_vx := 0.0
	if _pt.has(id):
		var span := _t - float(_pt[id])
		if span > 0.0 and span < 0.5:
			car_vx = (x - float(_px[id])) / span
			if absf(car_vx) > TELEPORT_V:
				car_vx = 0.0
	_px[id] = x
	_pt[id] = _t
	var gap_len := absf(dz) - hl - phl
	var gap_x := absf(x - pxc) - hw - phw
	evaluated += 1
	if gap_len < 0.0 and gap_x >= 0.0:
		min_side_gap = minf(min_side_gap, gap_x)
		if gap_x < LOOSE_GAP:
			_loose(id)
	elif gap_len >= 0.0 and gap_x < 0.0:
		var cl := (pvz - vz) * signf(dz)
		if cl > CLOSE_V:
			min_ttc = minf(min_ttc, gap_len / cl)
			if gap_len / cl < LOOSE_T:
				_loose(id)
	var kind := ""
	var closest := 0.0
	var ttc := INF
	if contact or (gap_len < 0.0 and gap_x < 0.0):
		kind = KIND_TOUCH
	elif gap_len < 0.0 and gap_x < SIDE_GAP:
		kind = KIND_SIDE
		closest = gap_x
	elif gap_x < 0.0:
		var closing := (pvz - vz) * signf(dz)
		if closing > CLOSE_V and gap_len / closing < CLOSE_T:
			ttc = maxf(gap_len, 0.0) / closing
			closest = gap_len
			kind = KIND_NOSE if dz * float(tm.flow) > 0.0 else KIND_TAIL
	if kind == "":
		return
	var rec = _pending.get(id)
	if rec == null:
		if _t - float(_last_emit.get(id, -1000.0)) < PER_CAR_S:
			return
		var toward := signf(pxc - x)
		var traffic_moved: bool = car.changing or car.weave > 0.0 or car_vx * toward > EDGE_V
		var you_moved := pvx * -toward > YOU_V
		var lateral_you := you_moved
		if kind == KIND_NOSE and not traffic_moved and not you_moved:
			you_moved = true   # you closed on it from behind in its lane
		elif kind == KIND_TAIL and not traffic_moved and not you_moved:
			traffic_moved = true   # it closed on you from behind
		rec = {
			"clock": _clock_text(), "night": _night(), "boot_s": (Time.get_ticks_msec() - _boot_ms) / 1000,
			"t": _t, "kind": kind, "z": roundf(float(tm._z[0])), "speed_kmh": roundi(absf(pvz) * 3.6),
			"car_kind": String(KIND_NAMES.get(car.kind, car.kind)),
			"car_lane": _lane_text(x), "you_lane": _lane_text(pxc),
			"closest": closest, "ttc": ttc,
			"who": "both" if (traffic_moved and you_moved) else ("traffic" if traffic_moved else ("you" if you_moved else "neither")),
			"lateral_you": lateral_you, "doing": doing_of(car),
			"seen": _check_no, "first": _check_no, "honked": false,
		}
		_pending[id] = rec
		return
	rec["seen"] = _check_no
	rec["closest"] = minf(float(rec["closest"]), closest)
	rec["ttc"] = minf(float(rec["ttc"]), ttc)
	if kind == KIND_TOUCH:
		rec["kind"] = KIND_TOUCH

func _loose(id: int) -> void:
	if _t - float(_loose_last.get(id, -1000.0)) >= PER_CAR_S:
		loose_count += 1
	_loose_last[id] = _t

## What a car was doing, with the spawn tags over a plain cruise or follow.
func doing_of(car: TrafficCar) -> String:
	var d := car.doing
	if d == TrafficCar.DO_CRUISING or d == TrafficCar.DO_FOLLOWING:
		var since := float(Engine.get_physics_frames() - car.spawn_frame) / float(Engine.physics_ticks_per_second)
		if since < SPAWN_TAG_S:
			return TrafficCar.DO_SPAWNED_BEHIND if car.spawned_behind else TrafficCar.DO_SPAWNED_AHEAD
	return d

## Writes the records whose crossing is over (or has been held long enough).
func _flush(all: bool) -> void:
	if _pending.is_empty():
		return
	var done := []
	for id in _pending:
		var rec: Dictionary = _pending[id]
		var age := float(_check_no - int(rec["first"])) * float(_every) / Engine.physics_ticks_per_second
		if all or int(rec["seen"]) != _check_no or age >= HOLD_S:
			done.append(id)
	for id in done:
		# Did it sound its horn over this? (The horn comes a reaction time after
		# the moment, so it is looked up when the record is written.)
		var car := instance_from_id(id) as TrafficCar
		if car != null and float(tm.now) - car.honk_at < 3.0:
			_pending[id]["honked"] = true
		_emit(_pending[id])
		_last_emit[id] = _t
		_pending.erase(id)

func _emit(rec: Dictionary) -> void:
	var cause := _cause_key(rec)
	count += 1
	by_cause[cause] = int(by_cause.get(cause, 0)) + 1
	by_kind[rec["kind"]] = int(by_kind.get(rec["kind"], 0)) + 1
	by_who[rec["who"]] = int(by_who.get(rec["who"], 0)) + 1
	by_doing[rec["doing"]] = int(by_doing.get(rec["doing"], 0)) + 1
	records.append(rec)
	if records.size() > KEEP_RECORDS:
		records.pop_front()
	_events.append([_t, cause])
	if tm != null:
		tm.near_miss_count = count
		tm.near_miss_by_cause = by_cause
		tm.near_miss_records = records
	_write(line_for(rec))

static func _cause_key(rec: Dictionary) -> String:
	match String(rec["who"]):
		"traffic":
			return "traffic:" + String(rec["doing"])
		"you":
			return "you"
	return String(rec["who"])

# ---------- text ----------

## One plain line per moment (the near-misses.txt format).
static func line_for(rec: Dictionary) -> String:
	var car := String(rec["car_kind"])
	var kind := String(rec["kind"])
	var what := ""
	match String(rec["who"]):
		"traffic":
			var d := String(rec["doing"])
			var plain := "closed on you from behind" if kind == KIND_TAIL else ("was in your way" if kind == KIND_NOSE else "was driving beside you")
			what = "%s %s" % [car, String(TRAFFIC_PHRASE.get(d, plain if d == "cruising" or d == "following" else "was %s next to you" % d.replace("_", " ")))]
		"you":
			if kind == KIND_NOSE and not bool(rec["lateral_you"]):
				what = "you closed on a %s from behind" % car
			elif kind == KIND_NOSE or kind == KIND_TAIL:
				what = "you cut in on a %s" % car
			elif kind == KIND_TOUCH:
				what = "you moved into a %s" % car
			else:
				what = "you swung into a %s's lane edge" % car
		"both":
			what = "you and a %s both moved" % car
		_:
			if kind == KIND_TOUCH:
				what = "you and a %s touched (it was %s)" % [car, String(rec["doing"]).replace("_", " ")]
			else:
				what = "a %s and you came close (it was %s)" % [car, String(rec["doing"]).replace("_", " ")]
	var gap := ""
	if kind == KIND_TOUCH:
		gap = "TOUCH"
	elif float(rec["ttc"]) < INF:
		gap = "%.1f s to contact" % float(rec["ttc"])
	else:
		gap = "closest %.1f m" % maxf(float(rec["closest"]), 0.0)
	if bool(rec.get("honked", false)):
		gap += ", it honked"
	return "%s  night %d  %s  %s  you %d km/h  [%s, lanes you %s / it %s, road %d m, it was %s, boot+%d s]" % [
		rec["clock"], rec["night"], what, gap, rec["speed_kmh"],
		kind, rec["you_lane"], rec["car_lane"], rec["z"], String(rec["doing"]).replace("_", " "), rec["boot_s"]]

## "last 10 min: 7 close calls (traffic caused 3: moved over 2, spawned behind 1; you caused 4)".
func summary_text() -> String:
	var cutoff := _t - WINDOW_S
	var traffic := {}
	var n_traffic := 0
	var n_you := 0
	var n_both := 0
	var n_neither := 0
	var total := 0
	for e in _events:
		if float(e[0]) < cutoff:
			continue
		total += 1
		var c := String(e[1])
		if c.begins_with("traffic:"):
			n_traffic += 1
			var d := c.substr(8)
			traffic[d] = int(traffic.get(d, 0)) + 1
		elif c == "you":
			n_you += 1
		elif c == "both":
			n_both += 1
		else:
			n_neither += 1
	var parts := PackedStringArray()
	for d in traffic:
		var label := String(d).replace("_", " ").replace("moving over unflashed", "moved over (not flashed)")
		if d == "cruising" or d == "following":
			label = "plain driving"
		parts.append("%s %d" % [label, traffic[d]])
	var s := "last %d min: %d close calls (traffic caused %d" % [roundi(minf(_t, WINDOW_S) / 60.0), total, n_traffic]
	if not parts.is_empty():
		s += ": " + ", ".join(parts)
	s += "; you caused %d" % n_you
	if n_both > 0:
		s += "; both %d" % n_both
	if n_neither > 0:
		s += "; neither %d" % n_neither
	return s + ")"

func _summary() -> void:
	_write("%s  night %d  %s" % [_clock_text(), _night(), summary_text()])

func _clock_text() -> String:
	var nc = tm.get("night_clock") if tm != null else null
	if nc == null:
		return "--:--:--"
	var total := int(float(nc.minutes) * 60.0) + NightClock.START_HOUR * 3600
	return "%02d:%02d:%02d" % [(total / 3600) % 24, (total / 60) % 60, total % 60]

func _night() -> int:
	var nc = tm.get("night_clock") if tm != null else null
	return int(nc.night) if nc != null else 0

## "+2" = second lane from the centre line on the right (own side), "-3" on the left.
static func _lane_text(x: float) -> String:
	var i := RoadChunkBuilder.lane_at(absf(x)) + 1
	return "%s%d" % ["+" if x >= 0.0 else "-", i]

# ---------- the file ----------

func _open() -> void:
	var g := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(g.get_base_dir())
	if FileAccess.file_exists(path) and _size_of(path) > MAX_BYTES:
		_rotate()
	_file = FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if _file == null:
		push_warning("near-miss log: could not open %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		write_file = false
		return
	_file.seek_end()
	_bytes = _file.get_position()
	_write("==== game start %s  (times are the in-game clock, 24 h; lanes: + right side, - left, 1 = next to the centre line) ====" % Time.get_datetime_string_from_system(false, true))

func _size_of(p: String) -> int:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return 0
	var n := f.get_length()
	f.close()
	return n

func _rotate() -> void:
	if _file != null:
		_file.close()
		_file = null
	var old := path.get_base_dir().path_join(OLD_NAME)
	var gp := ProjectSettings.globalize_path(path)
	var go := ProjectSettings.globalize_path(old)
	if FileAccess.file_exists(old):
		DirAccess.remove_absolute(go)   # the one old copy gives way to the newer one
	DirAccess.rename_absolute(gp, go)

func _write(line: String) -> void:
	if not write_file or _file == null:
		return
	if _bytes > MAX_BYTES:
		_rotate()
		_file = FileAccess.open(path, FileAccess.WRITE)
		_bytes = 0
		if _file == null:
			write_file = false
			return
	_file.store_line(line)
	_file.flush()
	_bytes += line.length() + 2

## Held records out, a closing summary, file closed. Safe to call twice.
func finish() -> void:
	if _finished:
		return
	_finished = true
	_flush(true)
	if _t > 1.0:
		_summary()
	if _file != null:
		_file.close()
		_file = null
