extends SceneTree

# After the key start (2026-10-11): the cabin shake, the coughs, the rev blip
# and the fast idle, in the game. One boot with the parked start
# (NEON_PARKED=1), the handbrake held throughout, then:
#
#  1 cold start   X cranks: the car shakes with the starter, two coughs, a
#                 full bump at the catch; the revs blip over the fast idle,
#                 which sits at 1500-1800 rpm, is part way down at 10 s and
#                 back at the car's own idle by 20 s; the shake is long gone
#  2 key off      X: off, and the idle is the car's own again
#  3 warm start   one cough; a smaller fast idle, over in 3 s
#  4 off mid way  a cold start switched off at 5 s: the idle is the car's own
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/car/fast_idle.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")

var rate := 120
var logger := Harness.ErrorCounter.new()
var game: Node
var p: PlayerCar
var starter: Node
var tick := 0
var fails: Array[String] = []
var keys := 0
var step := 0
var sub := 0
var t := 0.0
var base := 0.0
var top_rpm := 0.0
var crank_shake := 0.0
var catch_shake := 0.0
var cold_top := 0.0
var coughs_before := 0
var done := {}

func _initialize() -> void:
	OS.add_logger(logger)
	OS.set_environment("NEON_PARKED", "1")
	ExhaustTune.save_path = "user://autotune/test_fast_idle_exhaust.json"
	Engine.physics_ticks_per_second = rate
	game = Harness.boot(self, 0, 300.0, 4242)

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails.append("step %d: %s" % [step, what])
		print("  FAIL step %d: %s" % [step, what])

func _next() -> void:
	step += 1
	sub = 0
	t = 0.0
	done = {}
	keys = PlayerCar.KEY_HANDBRAKE
	print("fast_idle: step %d" % step)

## True the first time the clock passes `at` in this step.
func _at(at: float) -> bool:
	if t >= at and not done.has(at):
		done[at] = true
		return true
	return false

## Tap X and wait for the catch: true on the tick the engine runs.
func _start() -> bool:
	if sub == 0:
		keys = PlayerCar.KEY_HANDBRAKE | PlayerCar.KEY_STARTER
		coughs_before = starter.coughs
		crank_shake = 0.0
		if t > 0.05:
			keys = PlayerCar.KEY_HANDBRAKE
			sub = 1
		return false
	if sub == 1:
		if p.engine_running and not p.is_switched_off():
			catch_shake = p.start_shake
			top_rpm = 0.0
			sub = 2
			t = 0.0
			done = {}
			return true
		crank_shake = maxf(crank_shake, p.start_shake)
		if t > 4.0:
			_check(false, "the engine did not start within 4 s of a tap of X")
			p.ignition_on()
	return false

func _stop() -> void:
	keys = PlayerCar.KEY_HANDBRAKE | PlayerCar.KEY_STARTER
	p.apply_keys(keys)
	_check(not p.engine_running, "X did not switch the engine off (%.2f m/s)" % p.linear_velocity.length())
	_check(p.base_idle_rpm == 0.0 and is_equal_approx(p.idle_rpm, base), "idle left at %.0f with the engine off (the car's own is %.0f)" % [p.idle_rpm, base])

func _physics_process(delta: float) -> bool:
	tick += 1
	if tick < rate:
		return false
	if tick == rate:
		p = game.get("player")
		starter = p.get_node("StarterAudio")
		p.driver = func(c: PlayerCar) -> void: c.apply_keys(keys)
		base = p.idle_rpm
		_check(not p.engine_running and p.is_switched_off(), "not parked with the engine off")
		_check(p.start_shake == 0.0, "shaking before the key")
		_next()
		return false
	t += delta
	top_rpm = maxf(top_rpm, p.motor_rpm)
	match step:
		1:
			if sub < 2:
				if _start():
					print("  cold: crank %.2f s, shake %.2f cranking, %.2f at the catch, %d coughs" % [p.crank_hold, crank_shake, catch_shake, starter.coughs - coughs_before])
					_check(crank_shake >= PlayerCar.CRANK_SHAKE and crank_shake < 0.8, "crank shake %.2f" % crank_shake)
					_check(catch_shake > 0.95, "no bump at the catch (%.2f)" % catch_shake)
					_check(starter.coughs - coughs_before == 2, "%d coughs on a cold start" % (starter.coughs - coughs_before))
			else:
				if _at(0.1):
					_check(p.start_throttle > 0.0, "no throttle for the engine voice on the blip")
				if _at(1.5):
					cold_top = p.idle_rpm
					print("  cold: blip to %.0f rpm, fast idle %.0f, revs %.0f at 1.5 s (own idle %.0f)" % [top_rpm, p.idle_rpm, p.motor_rpm, base])
					_check(top_rpm > p.idle_rpm * 1.2, "no rev blip at the catch (top %.0f rpm)" % top_rpm)
					_check(p.idle_rpm >= 1500.0 and p.idle_rpm <= 1800.0, "fast idle %.0f rpm" % p.idle_rpm)
					_check(absf(p.motor_rpm - p.idle_rpm) < 200.0, "revs %.0f not on the fast idle %.0f at 1.5 s" % [p.motor_rpm, p.idle_rpm])
					_check(p.start_shake < 0.01 and p.start_throttle == 0.0, "still shaking at 1.5 s (%.3f)" % p.start_shake)
				if _at(10.0):
					print("  cold: idle %.0f, revs %.0f at 10 s" % [p.idle_rpm, p.motor_rpm])
					_check(p.idle_rpm > base + 50.0 and p.idle_rpm < cold_top - 50.0, "idle %.0f at 10 s (own %.0f, top %.0f)" % [p.idle_rpm, base, cold_top])
					_check(absf(p.motor_rpm - p.idle_rpm) < 150.0, "revs %.0f not on the idle %.0f at 10 s" % [p.motor_rpm, p.idle_rpm])
				if _at(20.2):
					_check(p.base_idle_rpm == 0.0 and is_equal_approx(p.idle_rpm, base), "idle %.0f at 20 s, not the car's own %.0f" % [p.idle_rpm, base])
				if _at(22.0):
					print("  cold: idle %.0f, revs %.0f at 22 s, %.2f m/s" % [p.idle_rpm, p.motor_rpm, p.linear_velocity.length()])
					_check(absf(p.motor_rpm - base) < 120.0, "revs %.0f at 22 s, idle is %.0f" % [p.motor_rpm, base])
					_check(p.engine_running, "the engine did not keep running")
					_next()
		2:
			if sub == 0:
				_stop()
				sub = 1
			elif t > 2.0:
				p._warmth = 1.0  # as after a drive
				_next()
		3:
			if sub < 2:
				if _start():
					print("  warm: crank %.2f s, %d coughs" % [p.crank_hold, starter.coughs - coughs_before])
					_check(starter.coughs - coughs_before == 1, "%d coughs on a warm start" % (starter.coughs - coughs_before))
			elif sub == 2:
				if _at(1.0):
					print("  warm: fast idle %.0f, revs %.0f at 1 s" % [p.idle_rpm, p.motor_rpm])
					_check(p.idle_rpm > base + 30.0 and p.idle_rpm < cold_top - 100.0, "warm fast idle %.0f (own %.0f, cold %.0f)" % [p.idle_rpm, base, cold_top])
				if _at(3.1):
					_check(p.base_idle_rpm == 0.0 and is_equal_approx(p.idle_rpm, base), "warm idle %.0f at 3 s, not %.0f" % [p.idle_rpm, base])
				if _at(5.0):
					_check(absf(p.motor_rpm - base) < 120.0, "revs %.0f at 5 s after a warm start, idle is %.0f" % [p.motor_rpm, base])
					_stop()
					sub = 3
					t = 0.0
			if sub == 3 and t > 2.0:
				p._warmth = 0.0  # as after a night parked
				_next()
		4:
			if sub < 2:
				_start()
			else:
				if _at(5.0):
					_check(p.idle_rpm > base + 100.0, "no fast idle on the second cold start (%.0f)" % p.idle_rpm)
					_stop()
					_next()
		_:
			for e in logger.errors:
				print("  ENGINE ERROR: %s" % e)
			_check(logger.errors.is_empty(), "%d engine errors" % logger.errors.size())
			print("fast_idle: %s" % ("PASS" if fails.is_empty() else "FAIL: %s" % "; ".join(fails)))
			quit(0 if fails.is_empty() else 1)
			return true
	return false
