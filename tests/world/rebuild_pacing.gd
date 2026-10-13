extends SceneTree

# Chunk rebuild pacing (2026-10-13, benchmark and profile pass). A recycled
# chunk is rebuilt a stage at a time (RoadChunkBuilder.STAGES, 0.1 to 1.3 ms
# each). With one rebuild in flight Game runs ONE stage a frame, not three, so
# the road work in any frame stays under ~1.3 ms; a backlog (jobs waiting) runs
# up to rebuild_stages_per_frame, so it clears as fast as it always did.
#
# This drives the real Game.tscn at 198 km/h for DRIVE_SECS with no traffic and
# checks, after the first WARMUP_SECS (the pool fills in a burst at the start):
# - chunks were recycled and every rebuild finished (nothing left in flight
#   after a rest at the end, nothing older than MAX_JOB_FRAMES frames)
# - frames that ran road work ran at most BUSY_MAX_STAGES stages
# - no engine error
# It prints, for reading against the old pacing (NEON_REBUILD_STAGES=3 turns
# pacing off and runs 3 stages every frame, which is what the game did before):
# stages-per-frame histogram, road-work ms per frame (mean, p99, max), and the
# player's final position and speed, which must be identical in both modes
# (the road is built 250-350 m ahead; pacing only moves WHEN a far chunk
# appears, never the car).
#
# Streaming at speed (Roy, 2026-10-13: "you're not going 340 km/h like I can"):
# SPEED_KMH=340 (or 400) drives the real car with the jet_drive.gd thrust (the
# stock coupe's gearing tops out near 245 km/h, so above 50 m/s the gearbox goes
# to neutral and a speed-held force does the rest). The road then streams in
# 1.7 times (340) or 2.0 times (400) faster than at 198 km/h. Reported, and
# asserted for the new pacing: the most rebuilds queued at once, the longest a
# rebuild lived (frames and seconds), and the NEAREST chunk still being rebuilt
# ahead of the car, in metres: it must stay beyond MIN_AHEAD_M (the fog hides
# the road at 300 m). CARS=<n> adds traffic.
#
#   godot --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/world/rebuild_pacing.gd
#   NEON_REBUILD_STAGES=3 godot ... (the old pacing, for the comparison)
#   SPEED_KMH=340 godot ...   (and 400)

const Harness := preload("res://tests/traffic/traffic_harness.gd")

const RATE := 120
## SECS=<n> changes the run length (a jet run needs ~17 s just to get up to speed).
var DRIVE_SECS := float(OS.get_environment("SECS")) if OS.get_environment("SECS").is_valid_float() else 40.0
const WARMUP_SECS := 4.0
const REST_SECS := 1.0
const LANE := 3
## Top speed of the drive, km/h; SPEED_KMH=<n> drives faster (above 245 the jet thrust takes over).
var speed_kmh := float(OS.get_environment("SPEED_KMH")) if OS.get_environment("SPEED_KMH").is_valid_float() else 198.0
var max_speed := speed_kmh / 3.6
const JET_FROM := 50.0  # m/s: the engine does the work below this, thrust above (jet_drive.gd)
const JET_KP := 1500.0  # N per m/s of speed error
const JET_MAX := 40000.0  # N
## The nearest chunk still being rebuilt must stay at least this far ahead of the car, m.
const MIN_AHEAD_M := 150.0
var cars := int(OS.get_environment("CARS")) if OS.get_environment("CARS").is_valid_int() else 0
## One stage a frame with one job in flight, the cap with a backlog.
const BUSY_MAX_STAGES := 3
## A job is eight stages: one a frame, finished within this many frames of starting.
const MAX_JOB_FRAMES := 48

var logger := Harness.ErrorCounter.new()
var game: Node
var tick := 0
var fails: Array[String] = []
var hist := {}
var ms := PackedFloat32Array()
var busy_over := 0
var recycled_at_warmup := 0
var job_age := {}
var last_frame := -1
var oldest_job := 0
## Rolling hash of the player's position and velocity every tick of the drive:
## equal between two runs only if the car moved bit for bit the same.
var trace := 0
var queue_hist := {}
var top_kmh := 0.0
var speed_sum := 0.0
var speed_n := 0
var nearest_ahead := INF
var near_ticks := 0
const RebuildPark := 1000.0  # RoadChunkBuilder.PARK_BELOW, undone

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	game = Harness.boot(self, cars, 150.0, 777)

func _physics_process(_delta: float) -> bool:
	var p: PlayerCar = game.get("player")
	if p == null:
		return false
	tick += 1
	if tick == 1:
		p.driver = _jet_driver() if speed_kmh > 245.0 else Harness.lane_driver(Harness.lane_x(LANE), 1.0, max_speed)
		Harness.move_player_to_lane(p, Harness.lane_x(LANE))
	var t := float(tick) / RATE
	trace = hash([trace, p.global_position, p.linear_velocity, p.angular_velocity])
	if t > WARMUP_SECS and t <= DRIVE_SECS:
		if t - 1.0 / RATE <= WARMUP_SECS:
			recycled_at_warmup = game.get("rebuild_count")
		var st: int = game.get("rebuild_stages_last")
		hist[st] = int(hist.get(st, 0)) + 1
		if st > 0:
			ms.append(float(game.get("rebuild_us_last")) / 1000.0)
		if st > BUSY_MAX_STAGES:
			busy_over += 1
		# age of the oldest job in flight, in frames
		var jobs: Array = game.get("_rebuild_jobs")
		queue_hist[jobs.size()] = int(queue_hist.get(jobs.size(), 0)) + 1
		top_kmh = maxf(top_kmh, p.current_speed() * 3.6)
		if t > WARMUP_SECS + 8.0:
			speed_sum += p.current_speed() * 3.6
			speed_n += 1
		var pz := RoadFrame.unroll(p.global_position).z
		for j in jobs:
			# metres from the car to the near edge of the chunk (road forward is -z)
			var ahead := pz - RoadFrame.unroll(j.root.global_position + Vector3(0.0, RebuildPark, 0.0)).z
			if ahead > -50.0:
				nearest_ahead = minf(nearest_ahead, ahead)
				if ahead < MIN_AHEAD_M:
					near_ticks += 1
		# age counts rendered frames, not physics ticks (a slow machine runs several ticks a frame)
		var new_frame := Engine.get_process_frames() != last_frame
		last_frame = Engine.get_process_frames()
		var live := {}
		for j in jobs:
			live[j.root.get_instance_id()] = true
			if new_frame:
				job_age[j.root.get_instance_id()] = int(job_age.get(j.root.get_instance_id(), 0)) + 1
			oldest_job = maxi(oldest_job, int(job_age[j.root.get_instance_id()]))
		for k in job_age.keys():
			if not live.has(k):
				job_age.erase(k)
	if t >= DRIVE_SECS + REST_SECS:
		return _end(p)
	return false

## The legacy lane driver with the jet_drive.gd thrust above JET_FROM.
func _jet_driver() -> Callable:
	var lane := Harness.lane_driver(Harness.lane_x(LANE), 1.0, INF)
	return func(c: Vehicle) -> void:
		lane.call(c)
		var v: float = c.current_speed()
		if v < JET_FROM:
			c.throttle_input = 1.0
			return
		c.throttle_input = 0.0
		if c.current_gear != 0:
			c.current_gear = 0
		var f := clampf(JET_KP * (max_speed - v), -JET_MAX * 0.25, JET_MAX)
		var fwd := -c.global_transform.basis.z
		fwd.y = 0.0
		c.apply_central_force(fwd.normalized() * f)

func _end(p: PlayerCar) -> bool:
	var s := Array(ms)
	s.sort()
	var sum := 0.0
	for v in s:
		sum += v
	var n := maxi(1, s.size())
	var keys := hist.keys()
	keys.sort()
	var h := ""
	for k in keys:
		h += " %d:%d" % [k, hist[k]]
	var qk := queue_hist.keys()
	qk.sort()
	var qh := ""
	for k in qk:
		qh += " %d:%d" % [k, queue_hist[k]]
	var mode: String = "fixed %d/frame (old)" % game.get("rebuild_stages_per_frame") if not game.get("rebuild_paced") else "paced (one stage a frame, cap %d)" % game.get("rebuild_stages_per_frame")
	var recycled: int = int(game.get("rebuild_count")) - recycled_at_warmup
	print("rebuild_pacing: %s, %d Hz, %.0f s, top speed %.0f km/h" % [mode, RATE, DRIVE_SECS - WARMUP_SECS, max_speed * 3.6])
	print("  rebuilds finished after warm-up: %d; oldest job lived %d frames" % [recycled, oldest_job])
	print("  stages run per frame (stages:frames):%s" % h)
	print("  rebuilds queued at once (jobs:ticks):%s" % qh)
	print("  car speed: top %.0f km/h, mean after 8 s %.0f km/h; %d traffic cars" % [top_kmh, speed_sum / maxf(1.0, speed_n), cars])
	print("  nearest chunk still being rebuilt, ahead of the car: %.0f m (%.2f s at the mean speed); frames with one nearer than %.0f m: %d" % [nearest_ahead, nearest_ahead / maxf(1.0, speed_sum / maxf(1.0, speed_n) / 3.6), MIN_AHEAD_M, near_ticks])
	if not s.is_empty():
		print("  road-work ms in frames that had any: mean %.3f  p99 %.3f  max %.3f  (%d frames)" % [sum / n, s[int(s.size() * 0.99)], s[s.size() - 1], s.size()])
	print("  player at the end: x=%.4f y=%.4f z=%.4f speed=%.4f" % [p.global_position.x, p.global_position.y, p.global_position.z, p.current_speed()])
	print("  player trace hash over %d ticks (position + velocities, every tick): %d" % [tick, trace])
	if recycled < 10:
		fails.append("only %d chunks were rebuilt: the drive did not exercise the recycling" % recycled)
	if nearest_ahead < MIN_AHEAD_M:
		fails.append("a chunk was still being rebuilt %.0f m ahead of the car, under %.0f m" % [nearest_ahead, MIN_AHEAD_M])
	if busy_over > 0:
		fails.append("%d frames ran more than %d stages" % [busy_over, BUSY_MAX_STAGES])
	if game.get("rebuild_paced") and oldest_job > MAX_JOB_FRAMES:
		fails.append("a rebuild took %d frames, over %d" % [oldest_job, MAX_JOB_FRAMES])
	var left: Array = game.get("_rebuild_jobs")
	# a car doing 340+ km/h is still on the move during the rest, so one more chunk is always due
	if left.size() > (2 if top_kmh > 245.0 else 1):
		fails.append("%d rebuilds still in flight after a second at rest" % left.size())
	for e in logger.errors:
		fails.append("logged error: " + e)
	for f in fails:
		printerr("FAIL: ", f)
	print("rebuild_pacing: ", "PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	OS.remove_logger(logger)
	quit(0 if fails.is_empty() else 1)
	return true
