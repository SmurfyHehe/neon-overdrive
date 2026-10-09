extends SceneTree

# The game at its real tick rate, 120 Hz (Phase C, 2026-10-05), headless and silent.
# Most other tests run at 60 (tests/run_tests.bat sets NEON_TICKS=60 because they
# count ticks as sixtieths of a second); this one sets 120 itself so the shipped
# rate is covered too:
# - the project default is 120 and the autoload honours NEON_TICKS
# - from standstill the engine idles, an automatic launch reaches speed and shifts
#   up through the gears; then, with no driver (the real keyboard path), a held
#   steer key ramps the steering over several ticks instead of snapping, turns
#   the car, and releasing it centres the wheel again, and the chase camera has
#   widened its FOV for the speed and stays near the car
# - the default coupe on TuneTrack is inside the feel targets at 120 Hz:
#   top speed 235-250 km/h, 0-100 4.6-6.4 s, 100-0 36-47 m, peak lateral g 0.9-1.5
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/core/tick_rate_120.gd

const RATE := 120
const TIMEOUT_TICKS := RATE * 60

enum Step { BOOT, IDLE, ACCEL, STEER, RELEASE, DONE }

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var throttle := 0.0
var idle_min := 1e9
var idle_max := -1e9
var max_gear := 0
var use_driver := true
var yaw_start := 0.0
var steer_at_2 := 0.0

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")  # an empty road, whatever run_tests.bat or the saved settings say
	_check(int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second")) == RATE, "the project should default to 120 Hz")
	Engine.physics_ticks_per_second = RATE
	change_scene_to_file("res://Game.tscn")

func _drive(c: PlayerCar) -> void:
	c.throttle_input = throttle
	c.brake_input = 0.0
	c.steering_input = 0.0

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("player") == null:
		return tick > 600 and _end("Game never became ready")
	var p: PlayerCar = game.player
	if use_driver:
		p.driver = _drive
	var waited := tick - step_start
	match step:
		Step.BOOT:
			_check(Engine.physics_ticks_per_second == RATE, "tick rate should be %d, is %d" % [RATE, Engine.physics_ticks_per_second])
			_go(Step.IDLE)
		Step.IDLE:
			if waited > RATE * 3:
				idle_min = minf(idle_min, p.motor_rpm)
				idle_max = maxf(idle_max, p.motor_rpm)
			if waited >= RATE * 5:
				_check(idle_min > 900.0 and idle_max < 1100.0, "idle at 120 Hz should sit in 900-1100 rpm, got %.0f to %.0f" % [idle_min, idle_max])
				throttle = 1.0
				_go(Step.ACCEL)
		Step.ACCEL:
			max_gear = maxi(max_gear, p.current_gear)
			if p.current_speed() > 30.0 and max_gear >= 3:
				_check(p.engine_running, "the engine should be running")
				_check(p.health.engine_temp < PowertrainHealth.DERATE_C, "the engine should not overheat in a launch")
				# Hand the car to the keyboard path (PlayerCar._read_keyboard) for the
				# steering ramp: hold W and D. The ramp is per second, so it must
				# take the same time at 120 Hz as at 60.
				use_driver = false
				p.driver = Callable()
				Input.action_press("accelerate")
				Input.action_press("steer_right")
				yaw_start = p.global_rotation.y
				_go(Step.STEER)
			elif waited > RATE * 40:
				return _end("never reached 30 m/s in 3rd at 120 Hz (speed %.1f, gear %d)" % [p.current_speed(), max_gear])
		Step.STEER:
			var steer := p.steering_input  # D is negative (PlayerCar._read_keyboard)
			if waited == 2:
				steer_at_2 = steer
				# A snap would put the wheel at the full lock for this speed (~0.58) at once; the ramp is
				# ~0.04 per tick, but one run read 0.16 here, so the limit has room.
				_check(absf(steer) < 0.3, "the steering should ramp, not snap: %.3f two ticks after pressing D" % steer)
			elif waited == RATE / 2:
				_check(steer < -0.3 and steer >= -1.0, "half a second into D the wheel should be well over (negative), got %.3f" % steer)
				_check(absf(steer) > absf(steer_at_2), "the steering should have grown since the press (%.3f then %.3f)" % [steer_at_2, steer])
				var cam: ChaseCamera = game.camera
				_check(cam != null, "the game has no chase camera")
				if cam != null:
					_check(cam.fov > ChaseCamera.FOV_REST + 3.0, "at %.0f m/s the camera FOV should be wider than rest: %.1f vs %.1f" % [p.current_speed(), cam.fov, ChaseCamera.FOV_REST])
					_check(cam.speed_t > 0.3, "the camera's speed factor should be up at %.0f m/s: %.2f" % [p.current_speed(), cam.speed_t])
					var gap := cam.global_position.distance_to(p.global_position)
					print("120 Hz steering ramp: %.3f at 2 ticks, %.3f at 0.5 s; camera fov %.1f (rest %.1f), speed factor %.2f, %.1f m from the car" % [steer_at_2, steer, cam.fov, ChaseCamera.FOV_REST, cam.speed_t, gap])
					_check(gap > 2.0 and gap < 12.0, "the chase camera should sit near the car, it is %.1f m away" % gap)
			elif waited == RATE:
				var turned := absf(wrapf(p.global_rotation.y - yaw_start, -PI, PI))
				_check(turned > 0.02, "holding D for a second should turn the car, it turned %.3f rad" % turned)
				print("120 Hz steering: the car turned %.3f rad in 1 s of holding D at %.0f m/s" % [turned, p.current_speed()])
				Input.action_release("steer_right")
				_go(Step.RELEASE)
		Step.RELEASE:
			if waited == RATE / 2:
				_check(absf(p.steering_input) < 0.02, "half a second after letting go the wheel should be centred, got %.3f" % p.steering_input)
				Input.action_release("accelerate")
				_go(Step.DONE)
				_targets()
	return false

func _targets() -> void:
	var track := TuneTrack.new()
	root.add_child(track)
	await process_frame
	var res: Array = await track.evaluate([CarSpec.coupe_default()])
	var m: Dictionary = res[0]
	print("120 Hz default coupe: top %.1f km/h, 0-100 %.2f s, 100-0 %.1f m, peak %.2f g" % [m.top_speed_kmh, m.t_0_100, m.brake_dist_100, m.peak_lat_g])
	_check(m.top_speed_kmh >= 235.0 and m.top_speed_kmh <= 250.0, "top speed %.1f outside 235-250" % m.top_speed_kmh)
	_check(m.t_0_100 >= 4.6 and m.t_0_100 <= 6.4, "0-100 %.2f outside 4.6-6.4" % m.t_0_100)
	_check(m.brake_dist_100 >= 36.0 and m.brake_dist_100 <= 47.0, "100-0 %.1f outside 36-47" % m.brake_dist_100)
	_check(m.peak_lat_g >= 0.9 and m.peak_lat_g <= 1.5, "peak lateral g %.2f outside 0.9-1.5" % m.peak_lat_g)
	_end("")

func _go(next: Step) -> void:
	step = next
	step_start = tick

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _end(msg: String) -> bool:
	if msg != "":
		failures.append(msg)
	for f in failures:
		printerr("FAIL: ", f)
	print("tick_rate_120: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
