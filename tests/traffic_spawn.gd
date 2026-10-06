extends SceneTree

# Traffic spawn test (milestone 3, stage B step 3; spawn rules milestone 4):
# 40 cars, the real Game.tscn, a scripted player at full throttle in the fast
# lane for 40 s, with the floating origin recentering every 200 m so shifts
# happen too.
#
# Asserts (exit code 1 on failure):
# - the car count never changes: recycling moves cars, it never adds or frees
# - no car is ever placed within SPAWN_MIN of the player; a placement ahead is
#   inside the spawn band, which starts beyond the draw distance (hidden, no
#   pop-in); a placement behind is inside the behind band and out of the
#   camera's view; every placement is on a lane centre, pointing the lane's
#   way, at least the lane gap from anything in that lane, and at least
#   SPAWN_TTC from contact with anything in it (SPAWN_TTC_PLAYER for the player)
# - no own-direction car ever drives in the player's lane (excluded here, for
#   spawns and lane changes alike)
# - cars recycled (the car got far enough to exercise the path)
# - a car's position minus its saved previous position is one tick of its
#   velocity, every tick, including the ticks the origin shifted and the tick
#   after a respawn (a teleport the sim reads as a velocity burst would show
#   here as a 1 km jump)
# - every full-sim car holds its path (lane centre, or its lane-change S)
# - set_car_count() (the pause-menu slider) removes and adds cars live
# - TrafficSettings round-trips through its file and leaves the audio section
# - no engine or script errors logged
# Reports the settled chassis height (TrafficManager.REST_Y).
#
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tests/traffic_spawn.gd

const Harness := preload("res://tests/traffic_harness.gd")

const RATE := 60
const CARS := 40
const RUN_TICKS := RATE * 40
const TIMEOUT_TICKS := RUN_TICKS * 2
const PLAYER_LANE := 0  # the passing lane, next to the oncoming lanes
const CRUISE_MAX := 45.0  # m/s, ~160 km/h

var logger := Harness.ErrorCounter.new()
var game: Node
var traffic: TrafficManager
var tick := 0
var fails: Array[String] = []
var last_origin := 0
var shifts := 0
var checked_spawns := 0
var min_spawn_dist := INF
var min_spawn_gap := INF
var min_spawn_ttc := INF
var behind_spawns := 0
var max_lane_err := 0.0
var worst_lane_note := ""
var worst_step_err := 0.0
var rest_y_sum := 0.0
var rest_y_n := 0
var live_checked := false

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	game = Harness.boot(self, 0, 300.0, 777, 200.0)

## The scene is ready on the first tick, not inside _initialize (same as the
## other scene tests), so the traffic is configured and filled here.
func _setup() -> void:
	traffic = game.get("traffic")
	traffic.own_lanes_used = [1, 2, 3]  # the player's lane stays clear
	traffic.log_spawns = true
	traffic.set_car_count(CARS)
	var p: PlayerCar = game.get("player")
	# Held to ~160 km/h: this test recenters every 200 m, and above ~230 km/h
	# each recenter gives the player a small yaw kick (seen with no traffic at
	# all; not from this branch) that eventually puts it into a neighbour.
	# Stability at full speed is tests/traffic_stability.gd's job.
	p.driver = Harness.lane_driver(Harness.lane_x(PLAYER_LANE), 1.0, CRUISE_MAX)
	Harness.move_player_to_lane(p, Harness.lane_x(PLAYER_LANE))
	# Initial placement: every car clear of the player (ahead, behind, or
	# parked far away for a retry when no slot was free).
	for car in traffic.cars:
		var d := p.global_position.z - car.global_position.z
		_check(absf(d) >= traffic.spawn_min, "initial car only %.1f m from the player" % d)

func _physics_process(delta: float) -> bool:
	# A tick that errors out never reaches _end, so a hard stop keeps the suite moving.
	if Engine.get_physics_frames() > TIMEOUT_TICKS:
		printerr("FAIL: timed out after ", Engine.get_physics_frames(), " ticks")
		quit(1)
		return true
	if traffic == null:
		if game.get("player") == null:
			return false
		_setup()
		return false
	tick += 1
	var p: PlayerCar = game.get("player")
	var origin: int = game.get("origin_index")
	if origin != last_origin:
		shifts += 1
		last_origin = origin

	_check(traffic.cars.size() == CARS, "car count changed to %d at tick %d" % [traffic.cars.size(), tick])
	for car in traffic.cars:
		if not Harness.finite(car):
			return _end("non-finite state in a traffic car at tick %d" % tick)
		# One tick of velocity between the saved and the current position, with
		# a small allowance for the teleport-and-step on a respawn tick.
		if car.detailed:
			var step: Vector3 = car.global_position - car.previous_global_position
			var want: Vector3 = car.linear_velocity * delta
			worst_step_err = maxf(worst_step_err, (step - want).length())
			if (step - want).length() > 0.5:
				_check(false, "car position jumped %.2f m against its velocity at tick %d (origin shifts %d)" % [(step - want).length(), tick, shifts])
			if car.direction < 0.0 and car.lane_i == PLAYER_LANE:
				_check(false, "an own-direction car is in the player's excluded lane at tick %d" % tick)
			if tick > RATE * 2 and car.global_position.z < p.global_position.z - 5.0:
				var err := absf(car.global_position.x - car.path_x())
				if err > max_lane_err:
					max_lane_err = err
					worst_lane_note = "tick %d, %s car, %.0f m ahead, player at %.0f km/h, live change %s" % [
						tick, "own" if car.direction < 0 else "oncoming", p.global_position.z - car.global_position.z,
						Harness.kmh(p.current_speed()), "done" if live_checked else "not yet"]
				if tick > RATE * 5:
					rest_y_sum += car.global_position.y
					rest_y_n += 1
	if not Harness.finite(p):
		return _end("non-finite player state at tick %d" % tick)

	# Every placement since last tick.
	while checked_spawns < traffic.spawn_log.size():
		var s: Dictionary = traffic.spawn_log[checked_spawns]
		checked_spawns += 1
		min_spawn_dist = minf(min_spawn_dist, absf(s.dist))
		min_spawn_gap = minf(min_spawn_gap, s.gap)
		min_spawn_ttc = minf(min_spawn_ttc, s.ttc)
		_check(absf(s.dist) >= traffic.spawn_min, "spawned %.1f m from the player (min %.0f)" % [s.dist, traffic.spawn_min])
		if s.behind:
			behind_spawns += 1
			_check(s.direction < 0.0, "an oncoming car spawned behind the player")
			_check(-s.dist >= traffic.spawn_behind_min and -s.dist <= traffic.spawn_behind_max, "spawned %.1f m behind, outside the behind band" % -s.dist)
			_check(s.speed > s.player_speed, "spawned behind at %.1f m/s, not faster than the player (%.1f)" % [s.speed, s.player_speed])
		else:
			var band: Vector2 = traffic._spawn_band()
			_check(s.dist >= band.x and s.dist <= band.y, "spawned %.1f m ahead, outside the hidden band %.0f-%.0f" % [s.dist, band.x, band.y])
			_check(s.dist > traffic.detail_distance, "spawned %.1f m ahead, inside the draw distance (pop-in)" % s.dist)
		_check(not s.in_view, "spawned in the camera's view")
		_check(s.gap >= traffic.lane_gap, "spawned %.1f m from a car in its lane (min %.0f)" % [s.gap, traffic.lane_gap])
		_check(s.ttc >= TrafficManager.SPAWN_TTC, "spawned %.1f s from contact (min %.0f)" % [s.ttc, TrafficManager.SPAWN_TTC])
		var lane_i := (absf(s.lane_x) - RoadChunkBuilder.MEDIAN_GAP) / RoadChunkBuilder.LANE_W - 0.5
		_check(is_equal_approx(lane_i, roundf(lane_i)) and lane_i >= -0.01 and lane_i < 4.0, "lane_x %.2f is not a lane centre" % s.lane_x)
		_check((s.lane_x > 0.0) == (s.direction < 0.0), "direction %.0f does not match lane side x=%.2f" % [s.direction, s.lane_x])
		if s.lane_x > 0.0:
			_check(int(roundf(lane_i)) != PLAYER_LANE, "spawned in the player's lane, which was excluded")

	if tick == RUN_TICKS - RATE * 3 and not live_checked:
		live_checked = true
		_live_count_change(p)
	if tick >= RUN_TICKS:
		return _end("")
	return false

## The pause-menu slider path: fewer cars, then back up, all placed clear.
func _live_count_change(p: PlayerCar) -> void:
	traffic.set_car_count(25)
	_check(traffic.cars.size() == 25, "set_car_count(25) left %d cars" % traffic.cars.size())
	traffic.set_car_count(CARS)
	_check(traffic.cars.size() == CARS, "set_car_count(%d) left %d cars" % [CARS, traffic.cars.size()])
	# Only the cars just added are new placements; the others may legitimately
	# be beside or just behind the player.
	for car in traffic.cars.slice(25):
		var d: float = p.global_position.z - car.global_position.z
		_check(absf(d) >= traffic.spawn_min, "a re-added car is only %.1f m from the player" % d)

func _settings_roundtrip() -> void:
	AudioSettings.set_volume("Music", 0.4)
	AudioSettings.save_settings()
	TrafficSettings.set_car_count(55)
	TrafficSettings.set_detail_distance(120.0)
	TrafficSettings.save_settings()
	TrafficSettings.car_count = 1
	TrafficSettings.detail_distance = 1.0
	TrafficSettings.load_settings()
	AudioSettings.load_settings()
	_check(TrafficSettings.car_count == 55 and is_equal_approx(TrafficSettings.detail_distance, 120.0),
		"traffic settings did not round-trip (%d, %.0f)" % [TrafficSettings.car_count, TrafficSettings.detail_distance])
	_check(is_equal_approx(AudioSettings.volumes["Music"], 0.4), "saving traffic settings lost the audio section")

func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)

func _end(msg: String) -> bool:
	if msg != "":
		fails.append(msg)
	_settings_roundtrip()
	var p: PlayerCar = game.get("player")
	_check(traffic.recycle_count >= 30, "only %d recycles in %d ticks" % [traffic.recycle_count, tick])
	_check(shifts >= 2, "only %d origin shifts" % shifts)
	_check(max_lane_err < 1.0, "a full-sim car drifted %.2f m off its lane centre (%s)" % [max_lane_err, worst_lane_note])
	var rest_y := rest_y_sum / maxi(rest_y_n, 1)
	print("traffic_spawn: ticks=%d player_speed=%.0f km/h spawns=%d recycles=%d deferred=%d shifts=%d" % [
		tick, Harness.kmh(p.current_speed()), traffic.spawn_count, traffic.recycle_count, traffic.deferred_count, shifts])
	print("traffic_spawn: min spawn distance %.1f m (limit %.0f), min lane gap at spawn %.1f m (limit %.0f), min time to contact at spawn %.1f s (limit %.0f), %d spawned behind, max path error %.2f m, worst step error %.3f m" % [
		min_spawn_dist, traffic.spawn_min, min_spawn_gap, traffic.lane_gap, min_spawn_ttc, TrafficManager.SPAWN_TTC, behind_spawns, max_lane_err, worst_step_err])
	print("traffic_spawn: settled chassis y = %.3f m (TrafficManager.REST_Y is %.3f)" % [rest_y, TrafficManager.REST_Y])
	for e in logger.errors:
		fails.append("logged error: " + e)
	for f in fails:
		printerr("FAIL: ", f)
	print("errors=%d warnings=%d" % [logger.errors.size(), logger.warnings])
	print("traffic_spawn: ", "PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	OS.remove_logger(logger)
	quit(0 if fails.is_empty() else 1)
	return true
