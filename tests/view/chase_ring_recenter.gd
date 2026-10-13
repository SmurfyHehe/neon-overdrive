extends SceneTree

# The chase camera round a roundabout (Roy, 2026-10-13: "when driving in a
# circle it's not useful, it doesn't recenter fast enough").
#
# A bot drives up exit 2's ramp onto the raised ring and goes round it one and
# a half times at RING_SPEED, then a second run at RING_FAST. Every tick the
# chase rig's heading (where it looks, before shake) is compared with the
# car's heading. Checks, per run:
# - once on the ring, the camera is back within SETTLED_DEG of the car's
#   heading within RECENTER_S seconds, and stays there for the rest of the ring;
# - for the last lap the error never goes past STEADY_DEG (it trails the car
#   a little in a steady turn, never by a quarter turn);
# - no jitter: the camera's own turn rate never jumps more than JERK_DEG_S
#   deg/s from one tick to the next;
# - smoothing settings A, B and C all pass (C is the default's neighbour and
#   keeps its slower reverse swing).
# Before the fix the rig looked down the highway the whole time, so on the
# ring it pointed up to 60 degrees off the car and then flipped 180 degrees.
#
# Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tests/view/chase_ring_recenter.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const RoadMap := preload("res://scripts/world/road_map.gd")
const RoadRamps := preload("res://scripts/world/road_ramps.gd")
const SaveDirector := preload("res://scripts/save/save_director.gd")

const L := 50.0
const SITE := 1             # index into RoadMap.rings(): exit 2
const LANE_X := 11.6
const SLIP_X := RoadRamps.X_LANE + RoadRamps.HALF
const RAMP_SPEED := 13.0
const RING_SPEED := 10.0
const RING_FAST := 14.0

const RECENTER_S := 1.0     # s from reaching the ring's lane to settled
const SETTLED_DEG := 8.0
const STEADY_DEG := 8.0
const JERK_DEG_S := 60.0    # deg/s change of the camera's turn rate in one tick

var game: Node
var cam: ChaseCamera
var ticks := 0
var fails: Array[String] = []
var checks := 0
var path: Array[Vector3] = []   # (x across, w metres past the ring's centre, speed)
var path_i := 0
var ring_from := 0
var ring_lap := 0
var site_s := 0.0
var runs: Array = [[1, RING_SPEED], [2, RING_SPEED], [0, RING_SPEED], [1, RING_FAST]]
var run_i := -1
var run_ticks := 0
var on_ring_t := -1.0
var last_bad_t := -1.0
var steady_max := 0.0
var peak_err := 0.0
var max_jerk := 0.0
var prev_yaw := INF
var prev_rate := INF
var log_next := 0.0
var last_frame := -1
var last_frame_t := 0.0

func _fail(msg: String) -> void:
	fails.append(msg)
	print("FAIL ", msg)

func _check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		_fail(msg)

func _initialize() -> void:
	OS.set_environment("NEON_CURVES", "0.5")
	OS.set_environment("NEON_HILLS", "0.5")
	OS.set_environment("NEON_ROAD", "")
	OS.set_environment("NEON_ACT", "")
	OS.set_environment("NEON_ROAD_SEED", "4242")
	game = Harness.boot(self, 0, 150.0, 7)

func _z_of(w: float) -> float:
	return float(RoadFrame.origin_index) * L - (site_s + w)

## Up from the +1 carriageway and one and a half times round the ring.
func _line(ring_speed: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var w := -260.0
	while w < -RoadRamps.V_GORE - 1.0:
		out.append(Vector3(lerpf(LANE_X, SLIP_X, smoothstep(-250.0, -205.0, w)), w, RAMP_SPEED))
		w += 2.0
	w = -RoadRamps.V_GORE
	while w < 0.0:
		out.append(Vector3(RoadRamps.x_at(-w), w, ring_speed if w > -40.0 else RAMP_SPEED))
		w += 2.0
	ring_from = out.size()
	ring_lap = ring_from + 96 / 2
	for i in range(0, 96 + 96 / 2):
		var a := TAU * float(i) / 96.0
		out.append(Vector3(RoadRamps.X_TOP * cos(a), RoadRamps.X_TOP * sin(a), ring_speed))
	return out

func _stand(p: PlayerCar, t: Transform3D) -> void:
	game.saver.restore_car(p, {"xform": SaveDirector.xform_to_array(t), "lin_vel": [0.0, 0.0, 0.0], "ang_vel": [0.0, 0.0, 0.0], "gear": 1})
	game.call("_update_chunk_pool", RoadFrame.unroll(p.global_position).z)
	game.call("flush_rebuilds")
	cam.forget_motion()

func _drive(p: PlayerCar) -> void:
	p.driver = func(c: Vehicle) -> void:
		if path.is_empty() or path_i >= path.size() - 1:
			c.throttle_input = 0.0
			c.brake_input = 1.0
			return
		var u := RoadFrame.unroll(c.global_position)
		var best := INF
		for i in range(path_i, mini(path_i + 12, path.size())):
			var d := Vector2(path[i].x - u.x, _z_of(path[i].y) - u.z).length()
			if d < best:
				best = d
				path_i = i
		var speed := c.linear_velocity.length()
		var look := clampf(speed * 0.6, 4.0, 9.0)
		var j := path_i
		var run := 0.0
		while j < path.size() - 1 and run < look:
			run += Vector2(path[j + 1].x - path[j].x, path[j + 1].y - path[j].y).length()
			j += 1
		var target := RoadFrame.roll(Vector3(path[j].x, 0.0, _z_of(path[j].y)))
		var fwd := -c.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var right := fwd.cross(Vector3.UP)
		var to := target - c.global_position
		var alpha := atan2(to.dot(right), to.dot(fwd))
		var dist := maxf(Vector2(to.dot(right), to.dot(fwd)).length(), 0.5)
		var want := clampf(atan(2.6 * 2.0 * sin(alpha) / dist) / c.max_steering_angle, -1.0, 1.0)
		c.steering_input = -signf(want) * pow(absf(want), 1.0 / maxf(c.steering_exponent, 0.1))
		var goal := path[path_i].z
		c.throttle_input = clampf((goal - speed) * 0.5, 0.0, 1.0)
		c.brake_input = clampf((speed - goal - 1.0) * 0.4, 0.0, 1.0)
		if c.current_gear < 1:
			c.current_gear = 1

static func _flat_yaw(v: Vector3) -> float:
	return atan2(-v.x, -v.z)

func _start_run(p: PlayerCar) -> void:
	run_i += 1
	run_ticks = 0
	on_ring_t = -1.0
	last_bad_t = -1.0
	steady_max = 0.0
	peak_err = 0.0
	max_jerk = 0.0
	prev_yaw = INF
	prev_rate = INF
	log_next = 0.0
	last_frame = -1
	cam.mode = int(runs[run_i][0])
	path = _line(float(runs[run_i][1]))
	path_i = 0
	_stand(p, RoadFrame.pose(path[0].x, 0.45, _z_of(path[0].y), 0.0))
	_drive(p)

func _end_run() -> void:
	var name := "smoothing %s at %.0f m/s" % [["A", "B", "C"][cam.mode], float(runs[run_i][1])]
	var settle := (last_bad_t - on_ring_t) if last_bad_t >= on_ring_t else 0.0
	print("chase_ring_recenter: %s: settled %.2f s after reaching the ring, last lap error up to %.1f deg, worst %.1f deg, turn-rate jump up to %.0f deg/s per tick" % [name, settle, steady_max, peak_err, max_jerk])
	_check(on_ring_t >= 0.0, "%s: never reached the ring" % name)
	_check(settle <= RECENTER_S, "%s: settled behind the car %.2f s after reaching the ring (limit %.1f)" % [name, settle, RECENTER_S])
	_check(steady_max <= STEADY_DEG, "%s: up to %.1f deg off the car's heading on the last lap (limit %.0f)" % [name, steady_max, STEADY_DEG])
	_check(max_jerk <= JERK_DEG_S, "%s: the camera's turn rate jumped %.0f deg/s in one tick (limit %.0f)" % [name, max_jerk, JERK_DEG_S])

func _physics_process(delta: float) -> bool:
	if game == null or not game.is_inside_tree():
		return false
	ticks += 1
	if ticks < 3:
		return false
	var p: PlayerCar = game.get("player")
	if cam == null:
		cam = game.camera
		cam.shake_enabled = false
		cam.set_view(ChaseCamera.View.CHASE)
		site_s = float(RoadMap.rings()[SITE].s)
		_start_run(p)
		return false
	run_ticks += 1
	if run_ticks > Engine.physics_ticks_per_second * 120:
		_fail("timed out at path point %d of %d" % [path_i, path.size()])
		return _finish()
	var t := float(run_ticks) * delta
	if path_i >= path.size() - 3:
		_end_run()
		if run_i + 1 >= runs.size():
			return _finish()
		_start_run(p)
		return false
	# The camera moves once per drawn frame (the project ticks physics faster
	# than --fixed-fps draws), so it is read once per frame.
	var fr := Engine.get_process_frames()
	if fr == last_frame:
		return false
	var dt := t - last_frame_t
	last_frame = fr
	last_frame_t = t
	var car_yaw := _flat_yaw(p.global_transform.basis.z)
	var cam_yaw := _flat_yaw(cam.anchor - cam.aim)
	var err := absf(rad_to_deg(wrapf(cam_yaw - car_yaw, -PI, PI)))
	if prev_yaw != INF and dt > 0.0:
		var rate := rad_to_deg(wrapf(cam_yaw - prev_yaw, -PI, PI)) / dt
		if prev_rate != INF and run_ticks > 30:
			max_jerk = maxf(max_jerk, absf(rate - prev_rate))
		prev_rate = rate
	prev_yaw = cam_yaw
	if path_i >= ring_from:
		if on_ring_t < 0.0:
			on_ring_t = t
		peak_err = maxf(peak_err, err)
		if err > SETTLED_DEG:
			last_bad_t = t
		if path_i >= ring_lap:
			steady_max = maxf(steady_max, err)
		if t >= log_next:
			log_next = t + 0.5
			print("  t %.1f  on ring %.1f s  speed %.1f  car %.0f  cam %.0f  error %.1f deg" % [t, t - on_ring_t, p.linear_velocity.length(), rad_to_deg(car_yaw), rad_to_deg(cam_yaw), err])
	return false

func _finish() -> bool:
	print("chase_ring_recenter: %d checks, %d failed" % [checks, fails.size()])
	quit(1 if not fails.is_empty() else 0)
	return true
