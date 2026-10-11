extends SceneTree

# The key (2026-10-10): X starts a stopped engine and switches a running one
# off (PlayerCar.key_off), with the starter, catch and shutdown sounds
# (StarterAudio). One boot with the parked start (NEON_PARKED=1), then:
#
#  1 cold start   a tap of X cranks, the engine catches after crank_hold and
#                 flares over idle; the automatic box is back
#  2 key off      X again, standing: off at once, the revs fall away, the
#                 shutdown plays and never with the crank; X still held does
#                 not crank it again; lights and radio as they were
#  3 warm start   let go, press again: it starts, and a warm engine cranks
#                 for less time than the cold one did
#  4 manual       the same off and on in the manual box, which comes back
#  5 at speed     X while driving does nothing; standing again it works
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/car/engine_key.gd

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
var cold_hold := 0.0
var lights := true
var station := -1
var rpm_at_off := 0.0
var top_rpm := 0.0
var overlap := false

func _initialize() -> void:
	OS.add_logger(logger)
	OS.set_environment("NEON_PARKED", "1")
	ExhaustTune.save_path = "user://autotune/test_engine_key_exhaust.json"
	Engine.physics_ticks_per_second = rate
	game = Harness.boot(self, 0, 300.0, 4242)

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails.append("step %d: %s" % [step, what])
		print("  FAIL step %d: %s" % [step, what])

func _engine_audio() -> EngineAudio:
	for c in p.get_children():
		if c is EngineAudio:
			return c
	return null

func _next() -> void:
	step += 1
	sub = 0
	t = 0.0
	keys = 0
	print("engine_key: step %d" % step)

## Tap X and wait for the engine: true once it runs and the catch has played.
func _start(mode: int) -> bool:
	if sub == 0:
		keys = PlayerCar.KEY_STARTER
		if t > 0.05:
			keys = 0
			sub = 1
			top_rpm = 0.0
		return false
	if sub == 1:
		if p.engine_running and not p.is_switched_off():
			print("  X: caught after %.2f s (crank_hold %.2f, coldness %.2f), rpm %.0f, idle %.0f" % [t, p.crank_hold, p.coldness(), p.motor_rpm, p.idle_rpm])
			_check(absf(t - p.crank_hold) < 0.25, "caught after %.2f s, not the %.2f s picked" % [t, p.crank_hold])
			_check(p.transmission_mode() == mode, "the box did not come back")
			sub = 2
			t = 0.0
		elif t > 3.0:
			_check(false, "the engine did not start within 3 s of a tap of X")
			p.ignition_on()
			sub = 2
			t = 0.0
		return false
	top_rpm = maxf(top_rpm, p.motor_rpm)
	if sub == 2 and t > 0.6:
		_check(top_rpm > p.idle_rpm * 1.2, "no rev flare at the catch (top %.0f rpm)" % top_rpm)
		_check(_engine_audio().synth.volume > 0.0, "engine voice silent after the start")
		_check(not starter.sounding().has("crank"), "the starter still sounds with the engine running")
		_check(p.engine_running, "the engine did not keep running")
		return true
	return false

## Tap X on the running engine, hold it a while: true once it is over.
func _stop(mode: int) -> bool:
	if sub == 0:
		var offs := p.key_offs
		var cranks: int = starter.cranks
		rpm_at_off = p.motor_rpm
		keys = PlayerCar.KEY_STARTER
		p.apply_keys(keys)
		_check(p.key_offs == offs + 1 and not p.engine_running, "X did not switch the engine off")
		_check(p.is_switched_off() and p.transmission_mode() == mode, "the box picked was lost")
		_check(not p.is_cranking() and starter.cranks == cranks, "the same press cranked it again")
		sub = 1
		t = 0.0
		return false
	if sub == 1:
		if t < 0.1 and t > 0.03:
			_check(p.motor_rpm > 0.0 and p.motor_rpm < rpm_at_off, "the revs did not fall away (%.0f from %.0f)" % [p.motor_rpm, rpm_at_off])
			_check(starter.sounding().has("shutdown"), "no shutdown sound")
			_check(_engine_audio().synth.volume == 0.0, "engine voice not silent once off")
		if t > 0.6:
			_check(not p.engine_running and not p.is_cranking(), "X held on started it again")
			keys = 0
			sub = 2
		return false
	if t > 2.0:
		print("  off: rpm %.0f, %.2f m/s, sounding %s" % [p.motor_rpm, p.linear_velocity.length(), starter.sounding()])
		_check(p.motor_rpm < 50.0, "the engine is still turning 2 s after the key (%.0f rpm)" % p.motor_rpm)
		_check(starter.sounding().is_empty(), "still sounding 2 s after the key: %s" % [starter.sounding()])
		_check(p.linear_velocity.length() < 0.3, "the car rolled off switched off")
		_check(p.headlights_on == lights, "the lights changed with the engine")
		_check(game.radio == null or game.radio.station == station, "the radio changed with the engine")
		return true
	return false

func _physics_process(delta: float) -> bool:
	tick += 1
	if tick < rate:
		return false
	if tick == rate:
		p = game.get("player")
		starter = p.get_node("StarterAudio")
		p.driver = func(c: PlayerCar) -> void: c.apply_keys(keys)
		lights = p.headlights_on
		station = game.radio.station if game.radio != null else -1
		_check(not p.engine_running and p.is_switched_off(), "not parked with the engine off")
		_check(p.coldness() > 0.99, "not cold at the start")
		_next()
		return false
	t += delta
	var s: PackedStringArray = starter.sounding()
	if s.has("crank") and s.has("shutdown"):
		overlap = true
	var mode := p.transmission_mode()
	match step:
		1:
			if _start(PlayerCar.Transmission.AUTO):
				cold_hold = p.crank_hold
				_check(starter.cranks == 1 and starter.catches == 1, "cranks %d, catches %d" % [starter.cranks, starter.catches])
				_next()
		2:
			if _stop(PlayerCar.Transmission.AUTO):
				_check(starter.shutdowns == 1, "shutdowns %d" % starter.shutdowns)
				p._warmth = 1.0  # as after a drive
				_next()
		3:
			if _start(PlayerCar.Transmission.AUTO):
				_check(p.crank_hold < cold_hold * 0.75, "a warm engine cranked as long as the cold one (%.2f, cold %.2f)" % [p.crank_hold, cold_hold])
				p.set_transmission_mode(PlayerCar.Transmission.MANUAL)
				p.current_gear = 0
				_next()
		4:
			if sub < 10:
				if t > 0.5 and sub == 0:
					_check(p.engine_running and mode == PlayerCar.Transmission.MANUAL, "not idling in the manual box")
				if (t > 0.5 or sub > 0) and _stop(PlayerCar.Transmission.MANUAL):
					sub = 10
					t = 0.0
			else:
				sub -= 10
				var done := _start(PlayerCar.Transmission.MANUAL)
				sub += 10
				if done:
					_check(p.realistic_clutch and mode == PlayerCar.Transmission.MANUAL, "the manual box did not come back")
					p.set_transmission_mode(PlayerCar.Transmission.AUTO)
					_next()
		5:
			if sub == 0:
				keys = PlayerCar.KEY_ACCEL
				if p.linear_velocity.length() > 6.0:
					var offs := p.key_offs
					keys = PlayerCar.KEY_ACCEL | PlayerCar.KEY_STARTER
					p.apply_keys(keys)
					_check(p.engine_running and p.key_offs == offs, "X switched the engine off at %.1f m/s" % p.linear_velocity.length())
					sub = 1
					t = 0.0
				elif t > 8.0:
					_check(false, "did not drive off (%.2f m/s)" % p.linear_velocity.length())
					sub = 1
			elif sub == 1:
				keys = PlayerCar.KEY_BRAKE
				if p.linear_velocity.length() < 0.2 or t > 8.0:
					keys = 0
					sub = 2
					t = 0.0
			elif sub == 2:
				if t > 0.3:
					sub = 20
					t = 0.0
			else:
				sub -= 20
				var done := _stop(PlayerCar.Transmission.AUTO)
				sub += 20
				if done:
					_next()
		_:
			_check(not overlap, "the crank and the shutdown sounded together")
			for e in logger.errors:
				print("  ENGINE ERROR: %s" % e)
			_check(logger.errors.is_empty(), "%d engine errors" % logger.errors.size())
			print("engine_key: %s (%d cranks, %d catches, %d shutdowns)" % ["PASS" if fails.is_empty() else "FAIL: %s" % "; ".join(fails), starter.cranks, starter.catches, starter.shutdowns])
			quit(0 if fails.is_empty() else 1)
			return true
	return false
