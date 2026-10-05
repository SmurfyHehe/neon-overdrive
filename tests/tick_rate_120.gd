extends SceneTree

# The game at its real tick rate, 120 Hz (Phase C, 2026-10-05), headless and silent.
# Most other tests run at 60 (tests/run_tests.bat sets NEON_TICKS=60 because they
# count ticks as sixtieths of a second); this one sets 120 itself so the shipped
# rate is covered too:
# - the project default is 120 and the autoload honours NEON_TICKS
# - from standstill the engine idles, an automatic launch reaches speed and shifts
#   up through the gears, the steering ramp and the camera still work
# - the default coupe on TuneTrack is inside the feel targets at 120 Hz:
#   top speed 235-250 km/h, 0-100 4.6-6.4 s, 100-0 36-47 m, peak lateral g 0.9-1.5
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/tick_rate_120.gd

const RATE := 120
const TIMEOUT_TICKS := RATE * 60

enum Step { BOOT, IDLE, ACCEL, DONE }

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var throttle := 0.0
var idle_min := 1e9
var idle_max := -1e9
var max_gear := 0

func _initialize() -> void:
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
				_go(Step.DONE)
				_targets()
			elif waited > RATE * 40:
				return _end("never reached 30 m/s in 3rd at 120 Hz (speed %.1f, gear %d)" % [p.current_speed(), max_gear])
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
