extends SceneTree

# Stage A camera test (2026-10-04): drives the real Game.tscn with held keys
# (the same InputMap path a keyboard uses) and checks the chase camera's speed
# feel does what it says.
#
# Phases, one fresh game each where it matters:
#   rest     -- car settles; FOV, distance and height sit at their rest values
#   launch   -- full throttle with upshifts; FOV and dolly follow speed
#   brake    -- hard braking from speed must NOT read as an impact
#   kerb     -- steer onto the sidewalk ("Dirt"); surface rumble turns on
#   wall     -- fresh game, a wall dropped across the road; impact shake fires
#
# Asserts (exit code 1 on failure):
# - rest: fov within 0.5 deg of FOV_REST, dist/height at DIST/HEIGHT
# - launch: reaches 28 m/s; fov rises with speed (correlation > 0.9), ends
#   at least 8 deg wider; camera distance shortens (dolly)
# - brake: largest per-tick velocity change stays under IMPACT_DV, trauma 0
# - kerb: surface_t > 0.25 while wheels are on the sidewalk
# - wall: trauma > 0.3 after the hit, and the drawn camera differs from the
#   unshaken chase anchor (shake actually applied), all values finite
# - shake at cruising speed stays subtle: under 0.6 deg off the chase aim
# - zero errors logged
#
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/camera_feel.gd

class ErrorCounter extends Logger:
	var errors: Array[String] = []
	var _lock := Mutex.new()
	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_lock.lock()
		errors.append("%s (%s:%d in %s)" % [rationale if rationale != "" else code, file, line, function])
		_lock.unlock()
	func _log_message(_message: String, _error: bool) -> void:
		pass

const C := preload("res://scripts/chase_camera.gd")
const MAX_TICKS := 60 * 90

var logger := ErrorCounter.new()
var fails := 0
var game: Node
var phase := "rest"
var ticks := 0
var phase_ticks := 0
var speeds: PackedFloat32Array = []
var fovs: PackedFloat32Array = []
var start_dist := 0.0
var brake_max_dv := 0.0
var brake_max_trauma := 0.0
var prev_v := Vector3.ZERO
var kerb_max := 0.0
var kerb_trauma := 0.0
var max_shake_angle := 0.0
var wall_hit_trauma := 0.0
var shake_seen := false

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")  # an empty road, whatever run_tests.bat or the saved settings say
	OS.add_logger(logger)
	seed(777)
	_spawn()

func _spawn() -> void:
	if game:
		game.queue_free()
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for k in [KEY_W, KEY_S, KEY_A, KEY_D, KEY_SPACE]:
		_press(k, false)

## Held "keys" are flags read by a driver on the player car, not input events: a
## windowed run loses held keys when the window loses focus, and headless frame
## pacing made this bot's steering vary run to run (the kerb phase was marginal).
## The car shifts itself (automatic default), so E is ignored.
var keys := {}

func _press(k: Key, down: bool) -> void:
	keys[k] = down

func _drive(c: PlayerCar) -> void:
	c.throttle_input = 1.0 if keys.get(KEY_W, false) else 0.0
	c.brake_input = 1.0 if keys.get(KEY_S, false) else 0.0
	c.handbrake_input = 1.0 if keys.get(KEY_SPACE, false) else 0.0
	var steer := (1.0 if keys.get(KEY_D, false) else 0.0) - (1.0 if keys.get(KEY_A, false) else 0.0)
	c.steering_input = -steer  # same sign flip as PlayerCar._read_keyboard

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL ", msg)

func _player() -> PlayerCar:
	return game.get("player")

func _cam() -> ChaseCamera:
	return game.get("camera")

## Lateral position of the middle of the right-hand sidewalk where the car is
## now (lane counts change chunk to chunk, so it is looked up, not fixed).
func _sidewalk_x(p: PlayerCar) -> float:
	var idx := int(floor(-p.global_position.z / RoadChunkBuilder.CHUNK_LEN)) + int(game.get("origin_index"))
	var cfg: Dictionary = game.call("_section_at", idx)
	return RoadChunkBuilder._lane_w(cfg.own_lanes) + RoadChunkBuilder.SHOULDER_W + RoadChunkBuilder.CURB_W + RoadChunkBuilder.SIDEWALK_W / 2.0

## Holds the heading down the road toward lateral position aim_x, like
## chunk_drive.gd's bot (which is aim_x = 0, max_term = 0.05).
func _hold_heading(p: PlayerCar, aim_x: float = 0.0, max_term: float = 0.05) -> void:
	var err: float = p.global_rotation.y + clampf((aim_x - p.global_position.x) * 0.02, -max_term, max_term)
	_press(KEY_A, err < -0.02)
	_press(KEY_D, err > 0.02)

func _upshift(p: PlayerCar) -> void:
	if p.gear >= 1 and p.gear < 5 and p.linear_velocity.length() > 9.0 * p.gear and not p.is_shifting:
		_press(KEY_E, true)
		_press(KEY_E, false)

## Angle between where the camera points and where the unshaken rig aims.
func _shake_angle(cam: ChaseCamera) -> float:
	return (cam.aim - cam.anchor).normalized().angle_to(-cam.global_basis.z)

func _physics_process(_delta: float) -> bool:
	ticks += 1
	phase_ticks += 1
	if ticks > MAX_TICKS:
		_fail("timed out in phase %s" % phase)
		return _finish()
	var p := _player()
	var cam := _cam()
	if p == null or cam == null:
		return false
	if not p.driver.is_valid():
		p.driver = _drive
	var v := p.linear_velocity
	var speed := p.current_speed()
	match phase:
		"rest":
			if phase_ticks == 90:
				print("rest: fov=%.2f dist=%.2f height=%.2f" % [cam.fov, cam.dist_now, cam.height_now])
				if absf(cam.fov - C.FOV_REST) > 0.5:
					_fail("rest fov %.2f, expected %.1f" % [cam.fov, C.FOV_REST])
				if absf(cam.dist_now - C.DIST) > 0.05 or absf(cam.height_now - C.HEIGHT) > 0.05:
					_fail("rest framing dist %.2f height %.2f" % [cam.dist_now, cam.height_now])
				start_dist = cam.dist_now
				_next("launch")
				_press(KEY_W, true)
		"launch":
			_hold_heading(p)
			_upshift(p)
			speeds.append(speed)
			fovs.append(cam.fov)
			if speed > 20.0:
				max_shake_angle = maxf(max_shake_angle, _shake_angle(cam))
			if speed >= 28.0:
				print("launch: %.1f m/s after %.1f s, fov=%.2f dist=%.2f height=%.2f" % [speed, phase_ticks / 60.0, cam.fov, cam.dist_now, cam.height_now])
				var corr := _corr(speeds, fovs)
				print("launch: speed/fov correlation %.3f" % corr)
				if corr < 0.9:
					_fail("fov does not follow speed (r=%.3f)" % corr)
				if cam.fov < C.FOV_REST + 8.0:
					_fail("fov only %.2f at %.1f m/s" % [cam.fov, speed])
				if cam.dist_now >= start_dist - 0.2:
					_fail("no dolly: dist %.2f vs %.2f at rest" % [cam.dist_now, start_dist])
				_next("brake")
				_press(KEY_W, false)
				_press(KEY_S, true)
				prev_v = v
			elif phase_ticks > 60 * 40:
				_fail("launch never reached 28 m/s (%.1f)" % speed)
				return _finish()
		"brake":
			_hold_heading(p)
			brake_max_dv = maxf(brake_max_dv, (v - prev_v).length())
			prev_v = v
			brake_max_trauma = maxf(brake_max_trauma, cam.trauma)
			if speed < 3.0:
				print("brake: largest per-tick dv %.3f m/s (impact threshold %.1f), trauma max %.3f" % [brake_max_dv, C.IMPACT_DV, brake_max_trauma])
				if brake_max_dv >= C.IMPACT_DV:
					_fail("hard braking crosses the impact threshold")
				if brake_max_trauma > 0.0:
					_fail("hard braking produced impact shake")
				_press(KEY_S, false)
				_press(KEY_W, true)
				_next("kerb")
		"kerb":
			_upshift(p)
			# Ease toward the right-hand sidewalk once moving.
			if speed > 12.0:
				_hold_heading(p, _sidewalk_x(p), 0.15)
			else:
				_hold_heading(p)
			kerb_max = maxf(kerb_max, cam.surface_t)
			kerb_trauma = maxf(kerb_trauma, cam.trauma)
			var on_dirt := false
			for w in p.wheel_array:
				if w.is_colliding() and w.surface_type == "Dirt":
					on_dirt = true
			if on_dirt and cam.surface_t > 0.25:
				shake_seen = cam.global_position.distance_to(cam.anchor) > 0.0
				print("kerb: surface_t %.2f at %.1f m/s, shake offset %.4f m, impact trauma on the kerb %.2f" % [cam.surface_t, speed, cam.global_position.distance_to(cam.anchor), kerb_trauma])
				_next("wall")
				_spawn()
				_press(KEY_W, true)
			elif phase_ticks > 60 * 20:
				_fail("never got onto the sidewalk (surface_t max %.2f)" % kerb_max)
				_next("wall")
				_spawn()
				_press(KEY_W, true)
		"wall":
			_hold_heading(p)
			_upshift(p)
			if not game.has_node("TestWall") and speed > 20.0:
				var wall := StaticBody3D.new()
				wall.name = "TestWall"
				var col := CollisionShape3D.new()
				var box := BoxShape3D.new()
				box.size = Vector3(40.0, 3.0, 1.0)
				col.shape = box
				wall.add_child(col)
				game.add_child(wall)
				wall.global_position = Vector3(0.0, 1.5, p.global_position.z - 30.0)
			if game.has_node("TestWall"):
				wall_hit_trauma = maxf(wall_hit_trauma, cam.trauma)
				if cam.trauma > 0.3 and not shake_seen:
					shake_seen = cam.global_position.distance_to(cam.anchor) > 0.0
				var ok := is_finite(cam.fov) and cam.global_position.is_finite()
				if not ok:
					_fail("camera went non-finite after the hit")
					return _finish()
				if phase_ticks > 60 * 30 or (wall_hit_trauma > 0.3 and speed < 1.0):
					print("wall: trauma max %.2f" % wall_hit_trauma)
					if wall_hit_trauma <= 0.3:
						_fail("hitting a wall at speed gave trauma %.2f" % wall_hit_trauma)
					return _finish()
	return false

func _next(name: String) -> void:
	phase = name
	phase_ticks = 0

func _corr(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var n := a.size()
	var ma := 0.0
	var mb := 0.0
	for i in n:
		ma += a[i]
		mb += b[i]
	ma /= n
	mb /= n
	var sab := 0.0
	var saa := 0.0
	var sbb := 0.0
	for i in n:
		sab += (a[i] - ma) * (b[i] - mb)
		saa += (a[i] - ma) * (a[i] - ma)
		sbb += (b[i] - mb) * (b[i] - mb)
	return sab / sqrt(saa * sbb) if saa > 0.0 and sbb > 0.0 else 0.0

func _finish() -> bool:
	print("cruise shake: max %.3f deg off the chase aim above 20 m/s" % rad_to_deg(max_shake_angle))
	if max_shake_angle > deg_to_rad(0.6):
		_fail("speed shake too strong: %.3f deg" % rad_to_deg(max_shake_angle))
	if not shake_seen:
		_fail("shake never moved the camera off its anchor")
	for e in logger.errors:
		_fail("logged error: " + e)
	print("camera_feel: %s" % ("PASS" if fails == 0 else "%d failure(s)" % fails))
	OS.remove_logger(logger)
	quit(0 if fails == 0 else 1)
	return true
