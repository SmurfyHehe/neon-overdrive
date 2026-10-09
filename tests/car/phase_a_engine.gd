extends SceneTree

# Phase A engine checks (2026-10-05), headless and silent, in the real Game.tscn
# with a scripted driver (no keys, so no window-focus flakiness):
# - idle: engine standing in gear settles at 900-1100 rpm and stays within +-60
# - throttle lag: from closed, throttle_amount takes more than 5 ticks to open
# - shift map: a light throttle upshifts early (< 75% of max rpm), full throttle
#   late (>= 92%), and the gearbox never shifts more than twice in 3 s at a
#   steady throttle (no hunting)
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/car/phase_a_engine.gd

const TIMEOUT_TICKS := 60 * 60
const IDLE_SETTLE_TICKS := 60 * 3
const IDLE_WATCH_TICKS := 60 * 2

enum Step { BOOT, IDLE_SETTLE, IDLE_WATCH, LIGHT, FULL, DONE }

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var demand := 0.0
var idle_min := 1e9
var idle_max := -1e9
var prev_shifting := false
var last_rpm := 0.0
var up_rpms: Array[float] = []   # rpm at each upshift, in order
var shift_ticks: Array[int] = []
var lag_ticks := -1

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")  # an empty road, whatever run_tests.bat or the saved settings say
	change_scene_to_file("res://Game.tscn")

func _drive(c: PlayerCar) -> void:
	c.throttle_input = demand
	c.brake_input = 0.0
	c.steering_input = 0.0

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("player") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	var p: PlayerCar = game.player
	p.driver = _drive
	var waited := tick - step_start
	# log the rpm at the start of every shift
	if p.is_shifting and not prev_shifting:
		shift_ticks.append(tick)
		if p.requested_gear > p.current_gear:
			up_rpms.append(last_rpm)
	prev_shifting = p.is_shifting
	last_rpm = p.motor_rpm
	match step:
		Step.BOOT:
			if waited == 1:
				_check(p.automatic_transmission, "the car should start in automatic")
			if waited >= 30:
				_go(Step.IDLE_SETTLE)
		Step.IDLE_SETTLE:
			if waited >= IDLE_SETTLE_TICKS:
				_go(Step.IDLE_WATCH)
		Step.IDLE_WATCH:
			idle_min = minf(idle_min, p.motor_rpm)
			idle_max = maxf(idle_max, p.motor_rpm)
			if waited >= IDLE_WATCH_TICKS:
				print("idle: %.0f to %.0f rpm" % [idle_min, idle_max])
				_check(idle_min > 900.0 and idle_max < 1100.0, "idle should sit in 900-1100 rpm, got %.0f to %.0f" % [idle_min, idle_max])
				_check(idle_max - idle_min < 120.0, "idle hunts by %.0f rpm" % (idle_max - idle_min))
				demand = 1.0
				lag_ticks = 0
				p.throttle_amount = 0.0
				_go(Step.LIGHT)
				demand = 0.3
		Step.LIGHT:
			if waited == 4:
				pass
			if up_rpms.size() >= 1:
				print("light throttle first upshift at %.0f rpm" % up_rpms[0])
				_check(up_rpms[0] < p.max_rpm * 0.75, "30%% throttle should upshift early, got %.0f rpm" % up_rpms[0])
				demand = 1.0
				_go(Step.FULL)
			elif waited > TIMEOUT_TICKS / 2:
				return _end("light throttle never upshifted")
		Step.FULL:
			if up_rpms.size() >= 2:
				print("full throttle upshift at %.0f rpm" % up_rpms[1])
				_check(up_rpms[1] >= p.max_rpm * 0.92, "full throttle should upshift late, got %.0f rpm" % up_rpms[1])
				return _end("")
			elif waited > TIMEOUT_TICKS / 2:
				return _end("full throttle never upshifted")
	return false

func _go(next: Step) -> void:
	step = next
	step_start = tick

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _end(msg: String) -> bool:
	if msg != "":
		failures.append(msg)
	# hunting: never more than 2 shifts inside any 3 s window
	for i in shift_ticks.size():
		var n := 0
		for t in shift_ticks:
			if t >= shift_ticks[i] and t < shift_ticks[i] + 180:
				n += 1
		if n > 2:
			failures.append("%d shifts inside 3 s (hunting)" % n)
			break
	for f in failures:
		printerr("FAIL: ", f)
	print("phase_a_engine: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
