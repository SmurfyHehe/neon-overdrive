extends SceneTree

# Heat and wear test (Phase B, 2026-10-05), headless and silent:
# - pure model: at idle the engine settles near 85 degC, cruise sits 80-98, hard
#   load on the limiter overheats it, cooling restores it; torque and brake
#   multipliers never go under their floors; warnings follow the thresholds
# - in the real game: holding 1st gear on the rev limiter overheats the engine, the
#   ENG light and a torque derate appear, the car still moves, and it cools again
# - TuneTrack cars (sim_only) never heat, so Auto-Tune numbers are untouched
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tests/powertrain_health.gd

const TIMEOUT_TICKS := 60 * 240
const HEAT_BRAKE := 0.5

enum Step { BOOT, HEAT, COOL, DONE }

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var throttle := 0.0
# Dragging the brakes in the HEAT step keeps the engine on the limiter at low
# airspeed. Before 2026-10-07 the car drifted across the road in 1st and got
# stuck on a wall, which did the same by accident; walls now let it slide off
# (tests/wall_hit.gd), and at a free 24 m/s airflow holds it near 105 C.
var brake := 0.0
var eng_light_seen := false
var peak_temp := 0.0

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")  # an empty road, whatever run_tests.bat or the saved settings say
	_pure()
	change_scene_to_file("res://Game.tscn")

func _pure() -> void:
	var h := PowertrainHealth.new()
	for i in 60 * 300:  # 5 minutes at idle
		h.step_values(1.0 / 60.0, 0.03, false, 0.0, 0.0)
	_check(absf(h.engine_temp - 85.0) < 6.0, "idle should settle near 85 C, got %.1f" % h.engine_temp)
	_check(h.warnings == 0, "no warning at idle")
	var h2 := PowertrainHealth.new()
	for i in 60 * 300:  # cruise at 30 m/s, light load
		h2.step_values(1.0 / 60.0, 0.3, false, 30.0, 0.0)
	_check(h2.engine_temp > 80.0 and h2.engine_temp < 98.0, "cruise should sit 80-98 C, got %.1f" % h2.engine_temp)
	var h3 := PowertrainHealth.new()
	for i in 60 * 400:  # full load, slow, on the limiter
		h3.step_values(1.0 / 60.0, 0.9, true, 10.0, 0.0)
		_check(h3.torque_mult >= PowertrainHealth.TORQUE_FLOOR - 1e-6, "torque below its floor")
	_check(h3.engine_temp > PowertrainHealth.DERATE_C, "sustained limiter should overheat (%.1f)" % h3.engine_temp)
	_check(h3.is_warning(PowertrainHealth.Warn.ENG_DERATE) and h3.torque_mult < 1.0, "derate warning and torque cut expected")
	for i in 60 * 400:  # cool at speed with the throttle lifted
		h3.step_values(1.0 / 60.0, 0.05, false, 35.0, 0.0)
	_check(h3.engine_temp < PowertrainHealth.WARN_C and h3.torque_mult > 0.999, "should cool back down (%.1f)" % h3.engine_temp)
	var b := PowertrainHealth.new()
	var before := b.brake_temp
	for i in 60 * 8:  # hard braking
		b.step_values(1.0 / 60.0, 0.0, false, 20.0, 90000.0)
	_check(b.brake_temp > before + 100.0, "braking should heat the brakes (%.0f)" % b.brake_temp)
	for i in 60 * 120:
		b.step_values(1.0 / 60.0, 0.0, false, 25.0, 90000.0)
		_check(b.brake_mult >= PowertrainHealth.BRAKE_FLOOR - 1e-6, "brake below its floor")
	_check(b.brake_mult < 1.0 and b.is_warning(PowertrainHealth.Warn.BRK_FADE), "sustained braking should fade the brakes")
	for i in 60 * 300:
		b.step_values(1.0 / 60.0, 0.0, false, 30.0, 0.0)
	_check(b.brake_mult > 0.999, "brakes should recover when cool (%.0f C)" % b.brake_temp)

func _drive(c: PlayerCar) -> void:
	c.throttle_input = throttle
	c.brake_input = brake
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
			_check(p.health.enabled, "health should be on in the real game")
			p.automatic_transmission = false  # hold 1st: the engine sits on the limiter
			p.current_gear = 1
			throttle = 1.0
			brake = HEAT_BRAKE
			_go(Step.HEAT)
		Step.HEAT:
			p.current_gear = 1
			peak_temp = maxf(peak_temp, p.health.engine_temp)
			if p.health.is_warning(PowertrainHealth.Warn.ENG):
				eng_light_seen = true
			if p.health.is_warning(PowertrainHealth.Warn.ENG_DERATE):
				_check(p.torque_mult < 1.0, "the derate should reach the vehicle")
				_check(p.torque_mult >= PowertrainHealth.TORQUE_FLOOR - 1e-6, "the derate must keep its floor (the car never dies)")
				throttle = 0.0
				brake = 0.0
				p.automatic_transmission = true
				_go(Step.COOL)
			elif waited > TIMEOUT_TICKS - 600:
				return _end("never overheated on the limiter (peak %.0f C, speed %.1f, rpm %.0f)" % [peak_temp, p.current_speed(), p.motor_rpm])
		Step.COOL:
			if waited >= 60 * 90:
				_check(eng_light_seen, "the ENG light should have come on before the derate")
				_check(p.health.engine_temp < peak_temp - 5.0, "should have started cooling (%.0f from %.0f)" % [p.health.engine_temp, peak_temp])
				return _tracktune()
	return false

func _tracktune() -> bool:
	var car := PlayerCar.new()
	car.sim_only = true
	car.spec = CarSpec.clone_spec(CarSpec.coupe_default())
	current_scene.add_child(car)
	_check(not car.health.enabled, "TuneTrack-style cars must not run heat and wear")
	return _end("")

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
	print("powertrain_health: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
