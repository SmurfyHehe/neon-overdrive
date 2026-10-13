extends SceneTree

# Stress layer A, the speed ladder (notes/stress-test-and-readiness-2026-10-13.md,
# section 4; Roy said yes 2026-10-13). One max-tuned car (scripts/tuning/max_tune.gd)
# on the game's own road (bends, hills, the tunnel and the ring exits, the same
# road seed every run), in traffic, driven by the shared test driver's
# "flatout" mode: it holds 200, 250, 300 and 340 km/h in turn (each rung
# LADDER_RUNG_SECS of game time) and then goes flat out (LADDER_FLAT_SECS). A
# rung over the car's own top speed is skipped. Engine heat, fuel and damage
# are on, as in the game.
#
#   godot --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tests/core/speed_ladder.gd
#
# --fixed-fps 60: one frame every two physics ticks, as on the laptop at
# 60 fps, so the road pool (rebuilt per frame) is tested at a real frame rate.
#
# Env: LADDER_CAR (default p1_coupe), LADDER_TRAFFIC (16), LADDER_SEED (777),
# LADDER_RUNGS ("200,250,300,340"), LADDER_RUNG_SECS (30), LADDER_FLAT_SECS (60),
# LADDER_CURVES / LADDER_HILLS (0.5 each, the game's own), LADDER_OUT (a file
# the one-line result is appended to, for the stress report).
#
# Fails on, at any speed:
#   - an engine or script error (camera, HUD, audio, road builder: anything);
#   - a NaN or the car under the road (TestDriver.sanity);
#   - the car off its carriageway without touching a wall (through a barrier);
#   - the car body touching the road (belly, CarSpec.WORLD_LAYER contact) on
#     a rung below 250 km/h and not within 3 s of a crash, which car_scrape
#     holds at 0 (above that it is counted and reported, #585);
#   - damage or a flat tyre with no contact to cause it;
#   - road missing ahead: no finished chunk, or no road under a ray, within
#     ROAD_AHEAD_MIN of the car (the pool keeps 300 m built ahead);
#   - the camera gone or more than CAMERA_MAX from the car.
# Reported (not failed): contacts with traffic and walls (the bot, not the car,
# picks the gaps), the speed held per rung, the top speed, air time, frame-time
# spikes and what ran in them (SpikeLog).

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const TestDriver := preload("res://scripts/core/test_driver.gd")
const MaxTune := preload("res://scripts/tuning/max_tune.gd")
const RATE := 120
const KMH := 1.0 / 3.6
const Districts := preload("res://scripts/world/districts.gd")
## Least finished road ahead of the car, m. CHUNKS_AHEAD is 6 (300 m) and the
## fog has the road from there; under 200 m a missing chunk can be seen.
const ROAD_AHEAD_MIN := 200.0
const CAMERA_MAX := 30.0
## A frame this much slower than the median, and over SPIKE_MS, is a spike.
const SPIKE_X := 4.0
const SPIKE_MS := 20.0

var logger := Harness.ErrorCounter.new()
var game: Node
var p: PlayerCar
var bot: TestDriver
var car_id := "p1_coupe"
var rungs: Array[float] = []
var rung_secs := 30.0
var flat_secs := 60.0
var out_path := ""
## LADDER_DEBUG=1 prints every body contact.
var debug := OS.get_environment("LADDER_DEBUG") == "1"

var ticks := 0
var rung_i := 0
var rung_t := 0.0
var top := 0.0
var fails: Array[String] = []
var notes: Array[String] = []
var rung_rows: Array[String] = []
var _rung_sum := 0.0
var _rung_n := 0
var _rung_min := INF
var _rung_max := 0.0

var belly_ticks := 0
var belly_ticks_slow := 0
var belly_first := ""
var air_t := 0.0
var air_max := 0.0
var off_road := 0
var min_ahead := INF
var min_ahead_at := ""
var ray_miss := 0
var cam_bad := 0
var max_cam := 0.0
var dist := 0.0
var _last_pos := Vector3.ZERO
var _was_flat := [false, false, false, false]
var _prop_hits := 0
var _touched := 0
var _last_hit := -1000000
var prop_log: Array[String] = []

var frames: PackedFloat32Array = []
var spikes: Array[String] = []
var _frame_us := 0
var _events_frame: Array = []

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	car_id = _env("LADDER_CAR", "p1_coupe")
	for s in _env("LADDER_RUNGS", "200,250,300,340").split(","):
		rungs.append(float(s))
	rung_secs = float(_env("LADDER_RUNG_SECS", "30"))
	flat_secs = float(_env("LADDER_FLAT_SECS", "60"))
	out_path = _env("LADDER_OUT", "")
	OS.set_environment("NEON_CURVES", _env("LADDER_CURVES", "0.5"))
	OS.set_environment("NEON_HILLS", _env("LADDER_HILLS", "0.5"))
	OS.set_environment("NEON_CAR", car_id)
	if not OS.get_environment("NEON_ROAD_SEED").is_valid_int():
		OS.set_environment("NEON_ROAD_SEED", "37")
	MaxTune.forced = 1
	SpikeLog.enabled = true
	game = Harness.boot(self, int(_env("LADDER_TRAFFIC", "16")), 300.0, int(_env("LADDER_SEED", "777")))

static func _env(key: String, fallback: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else fallback

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	var ev := SpikeLog.take()
	if p != null and _frame_us > 0:
		var ms := float(now - _frame_us) / 1000.0
		frames.append(ms)
		if frames.size() > 120:
			var med := _median_recent()
			if ms > SPIKE_MS and ms > med * SPIKE_X and spikes.size() < 40:
				var what: Array[String] = []
				for e in _events_frame:
					what.append("%s %.1f" % [e[0], e[1]])
				spikes.append("%.1f ms at t=%.1f s %.0f km/h [%s]" % [ms, float(ticks) / RATE, p.current_speed() * 3.6, ", ".join(what)])
	_events_frame = ev
	_frame_us = now
	if OS.get_environment("LADDER_PROFILE") == "1" and p != null and frames.size() > 0:
		if frames[-1] > 25.0:
			_prof_report(frames[-1])
		_prof.proc.clear()
		_prof.phys.clear()
	return false

## LADDER_PROFILE=1: a Probe after each child of Game and of the car; on a
## frame over 25 ms it prints which subtrees the time went to.
class Probe extends Node:
	var label := ""
	var shared: Dictionary
	func _process(_d: float) -> void:
		shared.proc.append([label, Time.get_ticks_usec()])
	func _physics_process(_d: float) -> void:
		shared.phys.append([label, Time.get_ticks_usec()])

var _prof := {"proc": [], "phys": []}
func _install_probes() -> void:
	var kids := game.get_children()
	for k in p.get_children():
		var pp: Node = Probe.new()
		pp.label = "car/" + String(k.name)
		pp.shared = _prof
		p.add_child(pp)
		p.move_child(pp, k.get_index() + 1)
	var first: Node = Probe.new()
	first.label = "<start>"
	first.shared = _prof
	game.add_child(first)
	game.move_child(first, 0)
	for k in kids:
		var pr: Node = Probe.new()
		pr.label = String(k.name)
		pr.shared = _prof
		game.add_child(pr)
		game.move_child(pr, k.get_index() + 1)

func _prof_report(ms: float) -> void:
	for key in ["proc", "phys"]:
		var a: Array = _prof[key]
		var rows: Array = []
		for i in range(1, a.size()):
			var d: float = float(a[i][1] - a[i - 1][1]) / 1000.0
			if d > 3.0:
				rows.append("%s %.1f" % [a[i][0], d])
		if not rows.is_empty():
			print("    prof %s (frame %.1f ms) t=%.2f s %.0f km/h gear %d: %s" % [key, ms, float(ticks) / RATE, p.current_speed() * 3.6, p.current_gear, ", ".join(rows)])

func _median_recent() -> float:
	var a := frames.slice(maxi(0, frames.size() - 240))
	a.sort()
	return a[a.size() / 2]

func _rung_target() -> float:
	return rungs[rung_i] if rung_i < rungs.size() else 999.0

func _rung_len() -> float:
	return rung_secs if rung_i < rungs.size() else flat_secs

func _physics_process(_delta: float) -> bool:
	if p == null:
		p = game.get("player")
		if p == null or not p.is_ready or Engine.get_physics_frames() < RATE:
			p = null
			return false
		var built := MaxTune.TOP_RATIO.get(car_id, [0.0, INF])[1] as float
		while rung_i < rungs.size() and rungs[rung_i] > built:
			notes.append("rung %.0f skipped (max-tune top %.0f km/h)" % [rungs[rung_i], built])
			rung_i += 1
		bot = TestDriver.start(game, "flatout", {"speed": _rung_target()})
		if OS.get_environment("LADDER_PROFILE") == "1":
			_install_probes()
		_last_pos = p.global_position
		return false
	ticks += 1
	rung_t += 1.0 / RATE
	var v := p.current_speed()
	top = maxf(top, v)
	_check(v)
	if not fails.is_empty():
		return _end()
	# The second half of a rung is the hold; the first is getting there.
	if rung_t > _rung_len() * 0.5:
		_rung_sum += v
		_rung_n += 1
		_rung_min = minf(_rung_min, v)
		_rung_max = maxf(_rung_max, v)
	if ticks % (RATE * 10) == 0 or (debug and ticks % 12 == 0):
		var uu := RoadFrame.unroll(p.global_position)
		print("  t=%5.1f s  %5.1f km/h  gear %d  lane %d  s %6.0f m  x %5.1f y %4.2f  steer %+.2f  ahead %3.0f m  engine x%.2f" % [float(ticks) / RATE, v * 3.6, p.current_gear,
			bot.lane, RoadFrame.s_at(uu.z), uu.x, uu.y, p.steering_input, _road_ahead(), p.health.torque_mult])
		if debug:
			var sv := RoadFrame.dir_to_road(uu.z, p.linear_velocity).x
			print("      lane_x %.2f side_v %+.2f slip %+.3f yaw %+.3f curv %.5f us %.5f amount %+.3f wheels %s" % [TrafficManager.lane_centre(bot.lane, false), sv,
				TestDriver.slip_angle(p), p.angular_velocity.y, RoadFrame.curvature_at(uu.z), bot._understeer, p.steering_amount,
				[p.wheel_array[0].is_colliding(), p.wheel_array[1].is_colliding(), p.wheel_array[2].is_colliding(), p.wheel_array[3].is_colliding()]])
	if rung_t >= _rung_len():
		_close_rung()
		rung_i += 1
		rung_t = 0.0
		if rung_i > rungs.size():
			return _end()
		bot.target_speed = _rung_target() * KMH
	return false

func _close_rung() -> void:
	var name := "flat" if rung_i >= rungs.size() else "%.0f" % rungs[rung_i]
	var mean := _rung_sum / maxf(1.0, float(_rung_n))
	rung_rows.append("%s: held %.0f (%.0f-%.0f) km/h" % [name, mean * 3.6, _rung_min * 3.6, _rung_max * 3.6])
	_rung_sum = 0.0
	_rung_n = 0
	_rung_min = INF
	_rung_max = 0.0

func _check(v: float) -> void:
	var t := float(ticks) / RATE
	var bad := TestDriver.sanity(p)
	if bad != "":
		fails.append("%s at t=%.1f s, %.0f km/h" % [bad, t, v * 3.6])
		return
	dist += p.global_position.distance_to(_last_pos) if p.global_position.distance_to(_last_pos) < 20.0 else 0.0
	_last_pos = p.global_position
	# Body on the road: anything the body touches that is not a car or a wall.
	var wall_only := 1 << (CarSpec.WALL_LAYER - 1)
	var belly := ""
	if p.get_contact_count() > 0:
		for b in p.get_colliding_bodies():
			if b is Vehicle:
				continue
			var n := String(b.name)
			var wall := b is CollisionObject3D and ((b as CollisionObject3D).collision_layer & wall_only) != 0
			if not (wall or n.begins_with("Boundary") or n.begins_with("Building") or n == "BarrierCol" or n == "CushionCol"):
				belly = n
	if debug and p.get_contact_count() > 0:
		var st := PhysicsServer3D.body_get_direct_state(p.get_rid())
		for i in st.get_contact_count():
			var o := st.get_contact_collider_object(i)
			print("  contact t=%.2f s %.0f km/h: %s layer %d normal %s at x %.2f" % [t, v * 3.6, o.get_path() if o is Node else str(o),
				(o as CollisionObject3D).collision_layer if o is CollisionObject3D else -1, st.get_contact_local_normal(i), RoadFrame.unroll(p.global_position).x])
	var touched := bot.car_ticks + bot.wall_ticks
	if touched != _touched:
		_touched = touched
		_last_hit = ticks
	if belly != "":
		belly_ticks += 1
		# A crash pitches the car into the road: that is the crash, not the ride.
		if v < 250.0 * KMH and ticks - _last_hit > 3 * RATE:
			belly_ticks_slow += 1
		if belly_first == "":
			belly_first = "%s at t=%.1f s, %.0f km/h, s %.0f m" % [belly, t, v * 3.6, RoadFrame.s_at(RoadFrame.unroll(p.global_position).z)]
	# Air time: no wheel on anything.
	var any := false
	for w in p.wheel_array:
		if w.is_colliding():
			any = true
	air_t = 0.0 if any else air_t + 1.0 / RATE
	air_max = maxf(air_max, air_t)
	# Off the carriageway without a wall contact: through a barrier.
	var u := RoadFrame.unroll(p.global_position)
	var s := RoadFrame.s_at(u.z)
	var kerb := SurfaceMap.edge_at(s, false) + Districts.shoulder_at(floori(s / RoadChunkBuilder.CHUNK_LEN))
	if (u.x > kerb + 2.0 or u.x < -1.0) and bot.wall_contacts == 0:
		off_road += 1
		if off_road == 1:
			fails.append("off the carriageway at x %.1f m (kerb %.1f) with no wall contact, t=%.1f s, %.0f km/h, s %.0f m" % [u.x, kerb, t, v * 3.6, s])
	# Damage and tyres with nothing to cause them.
	var brk: Node = game.get("breaker")
	var prop_hits := 0 if brk == null else int(brk.get("hits"))
	if prop_hits > _prop_hits:
		_prop_hits = prop_hits
		var last: Dictionary = brk.get("last")
		prop_log.append("t=%.1f s %.0f km/h s %.0f m x %.1f (kerb %.1f, lane %d): %s" % [t, v * 3.6, s, u.x, kerb, bot.lane, last])
		if debug:
			print("  prop " + prop_log[-1])
	if p.damage.hits > 0 and bot.wall_contacts == 0 and bot.car_contacts == 0 and belly_ticks == 0 and _prop_hits == 0:
		fails.append("damage counted %d hits with no contact, t=%.1f s, %.0f km/h" % [p.damage.hits, t, v * 3.6])
	for i in 4:
		var flat := p.damage.tyre_flat(i)
		if flat and not _was_flat[i] and bot.wall_contacts == 0 and bot.car_contacts == 0:
			fails.append("tyre %d went flat with no contact, t=%.1f s, %.0f km/h (kerb strikes %d)" % [i, t, v * 3.6, p.damage.kerb_strikes])
		_was_flat[i] = flat
	# Road ahead: built chunks, and solid road under a ray where the car will be in 1 s.
	if ticks % 6 == 0:
		var ahead := _road_ahead()
		if ahead < min_ahead:
			min_ahead = ahead
			min_ahead_at = "t=%.1f s, %.0f km/h, s %.0f m" % [t, v * 3.6, s]
		if ahead < ROAD_AHEAD_MIN and fails.size() < 5:
			fails.append("only %.0f m of finished road ahead at t=%.1f s, %.0f km/h, s %.0f m" % [ahead, t, v * 3.6, s])
		var look := clampf(v * 1.0, 20.0, 150.0)
		var at := RoadFrame.pose(u.x, u.y, u.z - look, 0.0).origin
		var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 30, 0), at - Vector3(0, 30, 0), 1)
		if p.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			ray_miss += 1
			if ray_miss == 1:
				fails.append("no road under a ray %.0f m ahead at t=%.1f s, %.0f km/h, s %.0f m" % [look, t, v * 3.6, s])
		var cam := root.get_viewport().get_camera_3d()
		var cd := INF if cam == null else cam.global_position.distance_to(p.global_position)
		max_cam = maxf(max_cam, cd)
		if cd > CAMERA_MAX:
			cam_bad += 1
			if cam_bad == 1:
				fails.append("camera %s at t=%.1f s, %.0f km/h, s %.0f m (%s; game.camera %s)" % ["missing" if cam == null else "%.0f m from the car" % cd, t, v * 3.6, s,
					"none" if cam == null else str(cam.get_path()), "is it" if cam == game.get("camera") else "is not it"])

## Metres of finished road (built, not mid-rebuild) ahead of the car, counted
## chunk by chunk from the one it is on.
func _road_ahead() -> float:
	var pool: Array = game.get("chunk_pool")
	var jobs: Array = game.get("_rebuild_jobs")
	var busy := {}
	for j in jobs:
		busy[j.root] = true
	var have := {}
	for c in pool:
		if not busy.has(c.root):
			have[int(c.index)] = true
	var origin: int = game.get("origin_index")
	var z := -RoadFrame.unroll(p.global_position).z
	var here := floori(z / RoadChunkBuilder.CHUNK_LEN) + origin
	var k := here
	while have.has(k + 1):
		k += 1
	if not have.has(here):
		return 0.0
	return float(k + 1 - origin) * RoadChunkBuilder.CHUNK_LEN - z

func _end() -> bool:
	if rung_i <= rungs.size() and rung_t > 0.0 and fails.is_empty():
		_close_rung()
	var kind := PlayerCar.chassis_kind()
	var fr := frames.duplicate()
	fr.sort()
	var p50 := fr[fr.size() / 2] if fr.size() > 0 else 0.0
	var p99 := fr[int(fr.size() * 0.99)] if fr.size() > 0 else 0.0
	var fmax := fr[fr.size() - 1] if fr.size() > 0 else 0.0
	if belly_ticks_slow > 0:
		fails.append("body touched the road under 250 km/h for %d ticks, first %s" % [belly_ticks_slow, belly_first])
	if not logger.errors.is_empty():
		fails.append("%d engine errors, first: %s" % [logger.errors.size(), logger.errors[0]])
	var line := "speed_ladder %s traffic %s: %s | top %.1f km/h | %.1f km | %s | belly %d ticks%s | air max %.2f s | road ahead min %.0f m (%s) | cam max %.1f m | frame p50 %.1f p99 %.1f max %.1f ms, %d spikes | dmg hits %d kerb %d props %d | %s" % [
		kind, _env("LADDER_TRAFFIC", "16"), "PASS" if fails.is_empty() else "FAIL", top * 3.6, dist / 1000.0,
		"; ".join(rung_rows), belly_ticks, "" if belly_first == "" else " (first " + belly_first + ")", air_max,
		min_ahead, min_ahead_at, max_cam, p50, p99, fmax, spikes.size(), p.damage.hits, p.damage.kerb_strikes, _prop_hits,
		bot.summary() if bot != null else "no bot"]
	for n in notes:
		print("  note: " + n)
	for n in prop_log:
		print("  prop hit: " + n)
	for sp in spikes.slice(0, 10):
		print("  spike: " + sp)
	print(line)
	for f in fails:
		printerr("FAIL: " + f)
		line += "\n    FAIL: " + f
	for sp in spikes.slice(0, 5):
		line += "\n    spike: " + sp
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.READ_WRITE if FileAccess.file_exists(out_path) else FileAccess.WRITE)
		if f != null:
			f.seek_end()
			f.store_line(line)
	print("speed_ladder: %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(1 if not fails.is_empty() else 0)
	return true
