extends SceneTree

# Speed-feel check (2026-10-10): the real game, a straight road, the player's
# car held at 60, 100, 200, 300 and 400 km/h in turn (no car reaches 400 on its
# own, so the speed is set, not driven). At each speed it saves a chase-view and
# a cockpit screenshot and prints one line of numbers: the camera's field of
# view, vignette and streak strength, wind level, how many cars are in the
# player's own lane ahead and in sight, and how many the player passed there.
#
# The player passes through traffic here (collisions with it are switched off),
# so one crash does not end the comparison.
#
# Needs the real renderer (no --headless) and NEON_TEST=1. It refuses to run
# without test mode: outside it the game resumes and autosaves the real save
# slot, and this tool's held speeds and ghost car went into slot 1 that way on
# 2026-10-10.
#   set NEON_TEST=1
#   Godot_v4.7.2-stable_win64_console.exe --audio-driver Dummy --path . -s res://tools/speed_feel_shots.gd
# Env: SHOT_DIR (default user://speed_feel), SHOT_TAG (file name prefix),
#      SHOT_SPEEDS (km/h, comma separated), SHOT_CARS (traffic count, default 40),
#      NEON_CAR (which player car).

const Harness := preload("res://tests/traffic/traffic_harness.gd")

const SETTLE_SECS := 7.0   # at each speed before measuring
const MEASURE_SECS := 8.0
const LANE := 1            # the lane the player holds
const SIGHT := 300.0       # m ahead that counts as "in sight"

var game: Node
var speeds: Array[float] = [60.0, 100.0, 200.0, 300.0, 400.0]
var target_ms := 0.0
var holding := false

func _initialize() -> void:
	if OS.get_environment("NEON_TEST") != "1":
		push_error("speed_feel_shots: set NEON_TEST=1 first (it must not touch the real save)")
		quit(1)
		return
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	var env := OS.get_environment("SHOT_SPEEDS")
	if env != "":
		speeds.clear()
		for part in env.split(","):
			speeds.append(float(part))
	var cars := int(OS.get_environment("SHOT_CARS")) if OS.get_environment("SHOT_CARS") != "" else 40
	game = Harness.boot(self, cars, 150.0, 20261010)
	_run()

func _physics_process(_delta: float) -> bool:
	if not holding or game == null:
		return false
	var p: PlayerCar = game.get("player")
	# Hold the speed along the road (straight here, so world -Z); sideways and
	# vertical motion stay the sim's.
	var fwd := Vector3.FORWARD
	p.linear_velocity += fwd * (target_ms - p.linear_velocity.dot(fwd))
	return false

## The player and traffic pass through each other: the player's body is on no
## layer (nothing hits it, no wheel ray finds it) and neither its body nor its
## wheel rays look at the car layer. Traffic still knows where the player is
## (TrafficManager's own index, not physics).
func _ghost(p: PlayerCar, _traffic: TrafficManager) -> void:
	var cars := 1 << (CarSpec.CAR_LAYER - 1)
	p.collision_layer = 0
	p.collision_mask &= ~cars
	for w in p.wheel_array:
		w.collision_mask &= ~cars

func _run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	if dir == "":
		dir = "user://speed_feel"
	DirAccess.make_dir_recursive_absolute(dir)
	var tag := OS.get_environment("SHOT_TAG")
	await process_frame
	var p: PlayerCar = game.get("player")
	var traffic: TrafficManager = game.get("traffic")
	_ghost(p, traffic)
	for i in 30:
		await process_frame
	var road_y := RoadFrame.unroll(p.global_position).y
	var camera: ChaseCamera = game.get("camera")
	var lane_x: float = Harness.lane_x(LANE)
	Harness.move_player_to_lane(p, lane_x)
	p.driver = Harness.lane_driver(lane_x, 0.4)
	print("SPEEDFEEL car=%s tag=%s" % [PlayerCar.chassis_kind(), tag])
	for kmh in speeds:
		target_ms = kmh / 3.6
		_ghost(p, traffic)
		Harness.launch_player(p, target_ms)
		holding = true
		await create_timer(SETTLE_SECS, true, true).timeout
		# measure
		var ahead_before := {}
		var passed := 0
		var lane_sum := 0.0
		var sight_sum := 0.0
		var samples := 0
		var frames := 0
		var t0 := Time.get_ticks_usec()
		while Time.get_ticks_usec() - t0 < int(MEASURE_SECS * 1e6):
			await process_frame
			frames += 1
			if frames % 6 != 0:
				continue
			var pz := RoadFrame.unroll(p.global_position).z
			var in_lane := 0
			var in_sight := 0
			for car in traffic.cars:
				if car.benched:
					continue
				var u := RoadFrame.unroll(car.global_position)
				var ahead := pz - u.z
				var same_lane: bool = car.direction < 0.0 and absf(u.x - lane_x) < RoadChunkBuilder.LANE_W * 0.5
				if ahead > 0.0 and ahead <= SIGHT:
					in_sight += 1
					if same_lane:
						in_lane += 1
				var id: int = car.get_instance_id()
				if same_lane and ahead_before.get(id, false) and ahead <= 0.0 and ahead > -30.0:
					passed += 1
				ahead_before[id] = same_lane and ahead > 0.0 and ahead < 60.0
			lane_sum += in_lane
			sight_sum += in_sight
			samples += 1
		var secs := float(Time.get_ticks_usec() - t0) / 1e6
		var at := RoadFrame.unroll(p.global_position)
		if absf(at.y - road_y) > 0.5 or absf(at.x - lane_x) > 1.5 or p.global_transform.basis.y.y < 0.9:
			print("SPEEDFEEL INVALID kmh=%d: the car left its lane or the road (x %.1f, y %.1f)" % [int(kmh), at.x - lane_x, at.y - road_y])
		var fx: Node = game.get("fx")
		var screen: Node = fx.get("screen") if fx != null else null
		var audio: Node = null
		for child in p.get_children():
			if child is CarAudio:
				audio = child
		print("SPEEDFEEL kmh=%d real_kmh=%.0f fov=%.1f vignette=%.3f lines=%.3f wind=%.2f lane_ahead=%.2f sight_ahead=%.1f passed_in_lane=%d active=%d/%d frame_ms=%.1f" % [
			int(kmh), p.current_speed() * 3.6, camera.fov,
			float(screen.get("vignette")) if screen != null else -1.0,
			float(screen.get("lines")) if screen != null else -1.0,
			float(audio.get("wind_level")) if audio != null else -1.0,
			lane_sum / maxf(samples, 1.0), sight_sum / maxf(samples, 1.0), passed,
			traffic.active_count(), traffic.cars.size(), secs * 1000.0 / maxf(frames, 1.0)])
		root.get_viewport().get_texture().get_image().save_png("%s/%s%03d_chase.png" % [dir, tag, int(kmh)])
		camera.set_view(ChaseCamera.View.COCKPIT)
		await create_timer(1.0, true, true).timeout
		for i in 3:
			await process_frame
		print("SPEEDFEEL kmh=%d cockpit_fov=%.1f" % [int(kmh), camera.fov])
		root.get_viewport().get_texture().get_image().save_png("%s/%s%03d_cockpit.png" % [dir, tag, int(kmh)])
		camera.set_view(ChaseCamera.View.CHASE)
	print("SPEEDFEEL done -> %s" % ProjectSettings.globalize_path(dir))
	quit(0)
