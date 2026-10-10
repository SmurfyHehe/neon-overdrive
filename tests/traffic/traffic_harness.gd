extends RefCounted

# Shared pieces for the traffic tests (tests/traffic_*.gd), preloaded by each:
# the error logger from tests/core/smoke.gd, a Game boot with a chosen traffic
# count, a scripted lane-keeping player, finiteness and overlap checks, and
# percentile stats.

# Collects everything the engine logs as an error, from any thread.
class ErrorCounter extends Logger:
	var errors: Array[String] = []
	var warnings := 0
	var _lock := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		_lock.lock()
		if error_type == ERROR_TYPE_WARNING:
			warnings += 1
		else:
			var msg := rationale if rationale != "" else code
			errors.append("%s (%s:%d in %s)" % [msg, file, line, function])
		_lock.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

const TestDriver := preload("res://scripts/core/test_driver.gd")
const SETTINGS_PATH := "user://traffic_test_settings.cfg"

## Boots Game.tscn with `car_count` traffic cars and the given draw distance.
## Game reads both from the settings file, so a scratch file is written first
## (the real user://settings.cfg is left alone). Pass 0 and configure the
## TrafficManager (lanes used etc.) before set_car_count() when the test needs
## control over the initial placement.
static func boot(tree: SceneTree, car_count: int, detail: float, seed_value: int, recenter: float = 0.0) -> Node:
	# NEON_TEST_SEED=<n> reruns any harness test on another seed.
	var seed_env := OS.get_environment("NEON_TEST_SEED")
	if seed_env.is_valid_int():
		seed_value = int(seed_env)
	seed(seed_value)
	# Game._ready would randomize() over the seed above; this keeps it.
	OS.set_environment("NEON_RNG_SEED", str(seed_value))
	OS.set_environment("NEON_TRAFFIC", "")  # run_tests.bat sets 0 for the other tests
	AudioSettings.path = SETTINGS_PATH
	TrafficSettings.set_car_count(car_count)
	TrafficSettings.set_detail_distance(detail)
	TrafficSettings.save_settings()
	var game: Node = (load("res://Game.tscn") as PackedScene).instantiate()
	if recenter > 0.0:
		game.set("recenter_dist", recenter)
	tree.root.add_child(game)
	return game

## A driver for PlayerCar.driver: holds the lane centre `lane_x` with the same
## pure-pursuit steering the traffic uses and a fixed throttle, lifted above
## `max_speed` (m/s). The player's wheelbase is 2.5 m (player.gd CFG, axle_z 1.25).
##
## Plus a damping term: it aims LAT_DAMP_T seconds of its own sideways
## velocity short of the lane centre. Plain pure pursuit is barely damped at
## 240 km/h: a 1 m/s sideways kick swung the player 1.8 m off the lane and was
## still swinging +-0.6 m 25 s later (2026-10-06, probe at 120 Hz), and every
## floating-origin shift or close pass gave it another kick, until it wandered
## into the next lane. With the term the same kick peaks at 0.9 m and is gone
## in ~10 s. Test driver only; traffic keeps plain pure pursuit (its lane
## changes move the target on purpose, and it never goes 240).
const LAT_DAMP_T := 3.0
## The player car's own bend feed-forward (TrafficCar.UNDERSTEER_FF is the
## traffic tune): with the traffic's 0.0015 this driver crept 1.3 m to the
## inside of a 351 m bend at 120 km/h, with none 0.95 m to the outside of a
## 1245 m one (tests/world/curve_drive.gd, 2026-10-07).
const PLAYER_UNDERSTEER_FF := 0.0008

## The code lives in the shared test driver now (scripts/core/test_driver.gd,
## mode "legacy_lane"); the behaviour is unchanged: fixed throttle under
## max_speed, never brakes, never looks at traffic.
static func lane_driver(lane_x: float, throttle: float, max_speed: float = INF) -> Callable:
	return TestDriver.legacy_lane(lane_x, throttle, max_speed)

## Own-direction lane centre, lane 0 nearest the centre line (the fast lane).
static func lane_x(i: int) -> float:
	return TrafficManager.lane_centre(i, false)

## Puts a standing player on a lane centre before it moves, with the sim's
## saved positions moved along so the teleport is not read as a velocity.
static func move_player_to_lane(p: PlayerCar, lane: float) -> void:
	var offset := Vector3(lane - p.global_position.x, 0.0, 0.0)
	p.global_position += offset
	p.previous_global_position += offset
	for w in p.wheel_array:
		w.previous_global_position += offset
		w.last_collision_point += offset
	p.reset_physics_interpolation()

## Sets a standing player moving at `speed` m/s straight ahead, sim history,
## wheel spin and gear made consistent (the same handover traffic gets), so a
## test can start at highway speed instead of spending 30 s accelerating.
static func launch_player(p: PlayerCar, speed: float) -> void:
	TrafficCar.set_moving(p, speed)
	p.reset_physics_interpolation()

## False if any number the sim carries from tick to tick is NaN or infinite.
static func finite(v: Vehicle) -> bool:
	if not v.global_position.is_finite() or not v.linear_velocity.is_finite() or not v.angular_velocity.is_finite():
		return false
	if not v.global_transform.basis.is_finite() or not is_finite(v.motor_rpm) or not is_finite(v.speed):
		return false
	for w in v.wheel_array:
		if not is_finite(w.spin) or not is_finite(w.spring_current_length) or not w.force_vector.is_finite():
			return false
	return true

## True if b's centre lies inside a box of these half-extents around a, in a's
## own frame. With half_x 1.5 and half_z 3.0 (the cars are 1.6 x 3.4 m) that
## is bodies touching. The box has a height bound too (half_y): without it a
## car lying on its side, whose local frame is tipped, "overlapped" a car 13 m
## away along its own up axis, and traffic_stability reported tunnelling that
## never happened (2026-10-06).
static func overlaps(a: Node3D, b: Node3D, half_x: float, half_z: float, half_y: float = 1.5) -> bool:
	var l := a.to_local(b.global_position)
	return absf(l.x) < half_x and absf(l.z) < half_z and absf(l.y) < half_y

## True if the two bodies' centres are closer than `dist` metres, in any
## orientation: one car has passed (nearly) through the other. The cars are
## 1.6 x 1.0 x 3.4 m boxes, so centres under 1 m apart is already some
## interpenetration, and a pile-up of 3+ bodies at 100 km/h leaves 0.6-0.9 m
## for a while without any body having tunnelled (seen 2026-10-06, centres
## 0.58 m apart in a rolled wreck). Concentric centres (under 0.5 m) is what
## passing through looks like.
static func tunnelled(a: Node3D, b: Node3D, dist: float = 0.5) -> bool:
	return a.global_position.distance_to(b.global_position) < dist

static func stats(samples: PackedFloat32Array) -> Dictionary:
	var s: Array = Array(samples)
	s.sort()
	var n := s.size()
	if n == 0:
		return {"n": 0, "mean": 0.0, "p50": 0.0, "p95": 0.0, "max": 0.0}
	var sum := 0.0
	for x in s:
		sum += x
	return {"n": n, "mean": sum / n, "p50": s[n / 2], "p95": s[mini(int(n * 0.95), n - 1)], "max": s[n - 1]}

static func kmh(ms: float) -> float:
	return ms * 3.6
