extends SceneTree

# Realistic clutch test (Phase C, 2026-10-05), headless and silent, scripted driver:
# - off by default: the engine is running and realistic_clutch is false
# - automatic, on: it creeps at idle with no throttle, launches without stalling
#   (the clutch slips, then closes), and does not stall when braked to a stop
# - manual gearbox, on: pulling away in 3rd with the pedal up stalls the engine;
#   with the pedal in, the starter restarts it, and it keeps idling afterwards
# - the engine sound is silent while stalled (EngineAudio drops the synth volume)
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/clutch_model.gd

const TIMEOUT_TICKS := 60 * 120

enum Step { BOOT, CREEP, LAUNCH, STOP, STALL, RESTART, IDLE, DONE }

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var throttle := 0.0
var brake := 0.0
var pedal := 0.0
var starter := false
var slipped_at_launch := 1.0
var stalled_during := false

func _initialize() -> void:
	change_scene_to_file("res://Game.tscn")

func _drive(c: PlayerCar) -> void:
	c.throttle_input = throttle
	c.brake_input = brake
	c.steering_input = 0.0
	c.clutch_input = pedal
	c.starter_input = starter

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
			_check(not p.realistic_clutch, "the realistic clutch should be off by default")
			_check(p.engine_running, "the engine should start running")
			p.realistic_clutch = true
			_go(Step.CREEP)
		Step.CREEP:
			if waited >= 60 * 6:
				_check(p.engine_running, "the engine stalled while creeping")
				_check(p.current_speed() > 0.3 and p.current_speed() < 3.5, "creep speed %.2f m/s should be 0.3-3.5" % p.current_speed())
				throttle = 1.0
				_go(Step.LAUNCH)
		Step.LAUNCH:
			if not p.engine_running:
				stalled_during = true
			if waited == 20:
				slipped_at_launch = p.clutch_amount
			if p.current_speed() > 20.0:
				_check(not stalled_during, "the engine stalled during the launch")
				_check(p.clutch_amount < 0.1, "the clutch should be closed at speed (%.2f)" % p.clutch_amount)
				throttle = 0.0
				brake = 1.0
				_go(Step.STOP)
			elif waited > 60 * 20:
				return _end("never launched past %.1f m/s" % p.current_speed())
		Step.STOP:
			if not p.engine_running:
				stalled_during = true
			if waited >= 60 * 14:
				_check(p.current_speed() < 0.5, "should have stopped (%.1f m/s)" % p.current_speed())
				_check(not stalled_during, "the automatic stalled while braking to a stop")
				_check(p.engine_running, "the engine should still be running after braking to a stop")
				brake = 1.0
				p.automatic_transmission = false
				p.current_gear = 3
				p.clutch_pedal = 0.0
				pedal = 0.0
				brake = 0.0
				throttle = 0.0
				_go(Step.STALL)
		Step.STALL:
			if not p.engine_running:
				var audio: EngineAudio = null
				for c in p.get_children():
					if c is EngineAudio:
						audio = c
				if audio != null:
					_check(is_zero_approx(audio.synth.volume), "a stalled engine should be silent (volume %.2f)" % audio.synth.volume)
				pedal = 1.0
				starter = true
				_go(Step.RESTART)
			elif waited > 60 * 8:
				return _end("pulling away in 3rd with the pedal up never stalled (rpm %.0f, speed %.1f)" % [p.motor_rpm, p.current_speed()])
		Step.RESTART:
			if p.engine_running:
				starter = false
				_go(Step.IDLE)
			elif waited > 60 * 6:
				return _end("the starter never restarted the engine (rpm %.0f)" % p.motor_rpm)
		Step.IDLE:
			if waited >= 60 * 3:
				_check(p.engine_running, "the engine should keep idling after the restart")
				_check(p.motor_rpm > 700.0, "idle rpm %.0f is too low" % p.motor_rpm)
				return _end("")
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
	for f in failures:
		printerr("FAIL: ", f)
	print("clutch_model: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
