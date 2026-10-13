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
#   godot --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/world/rebuild_pacing.gd
#   NEON_REBUILD_STAGES=3 godot ... (the old pacing, for the comparison)

const Harness := preload("res://tests/traffic/traffic_harness.gd")

const RATE := 120
const DRIVE_SECS := 40.0
const WARMUP_SECS := 4.0
const REST_SECS := 1.0
const LANE := 3
## Top speed of the drive, m/s (198 km/h); SPEED_MS=<n> drives faster (111 = 400 km/h).
var max_speed := float(OS.get_environment("SPEED_MS")) if OS.get_environment("SPEED_MS").is_valid_float() else 55.0
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
var oldest_job := 0
## Rolling hash of the player's position and velocity every tick of the drive:
## equal between two runs only if the car moved bit for bit the same.
var trace := 0

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	game = Harness.boot(self, 0, 150.0, 777)

func _physics_process(_delta: float) -> bool:
	var p: PlayerCar = game.get("player")
	if p == null:
		return false
	tick += 1
	if tick == 1:
		p.driver = Harness.lane_driver(Harness.lane_x(LANE), 1.0, max_speed)
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
		var live := {}
		for j in jobs:
			live[j.root.get_instance_id()] = true
			job_age[j.root.get_instance_id()] = int(job_age.get(j.root.get_instance_id(), 0)) + 1
			oldest_job = maxi(oldest_job, int(job_age[j.root.get_instance_id()]))
		for k in job_age.keys():
			if not live.has(k):
				job_age.erase(k)
	if t >= DRIVE_SECS + REST_SECS:
		return _end(p)
	return false

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
	var mode: String = "fixed %d/frame (old)" % game.get("rebuild_stages_per_frame") if not game.get("rebuild_paced") else "paced (one stage a frame, cap %d)" % game.get("rebuild_stages_per_frame")
	var recycled: int = int(game.get("rebuild_count")) - recycled_at_warmup
	print("rebuild_pacing: %s, %d Hz, %.0f s, top speed %.0f km/h" % [mode, RATE, DRIVE_SECS - WARMUP_SECS, max_speed * 3.6])
	print("  rebuilds finished after warm-up: %d; oldest job lived %d frames" % [recycled, oldest_job])
	print("  stages run per frame (stages:frames):%s" % h)
	if not s.is_empty():
		print("  road-work ms in frames that had any: mean %.3f  p99 %.3f  max %.3f  (%d frames)" % [sum / n, s[int(s.size() * 0.99)], s[s.size() - 1], s.size()])
	print("  player at the end: x=%.4f y=%.4f z=%.4f speed=%.4f" % [p.global_position.x, p.global_position.y, p.global_position.z, p.current_speed()])
	print("  player trace hash over %d ticks (position + velocities, every tick): %d" % [tick, trace])
	if recycled < 10:
		fails.append("only %d chunks were rebuilt: the drive did not exercise the recycling" % recycled)
	if busy_over > 0:
		fails.append("%d frames ran more than %d stages" % [busy_over, BUSY_MAX_STAGES])
	if game.get("rebuild_paced") and oldest_job > MAX_JOB_FRAMES:
		fails.append("a rebuild took %d frames, over %d" % [oldest_job, MAX_JOB_FRAMES])
	var left: Array = game.get("_rebuild_jobs")
	if left.size() > 1:
		fails.append("%d rebuilds still in flight after a second at rest" % left.size())
	for e in logger.errors:
		fails.append("logged error: " + e)
	for f in fails:
		printerr("FAIL: ", f)
	print("rebuild_pacing: ", "PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	OS.remove_logger(logger)
	quit(0 if fails.is_empty() else 1)
	return true
