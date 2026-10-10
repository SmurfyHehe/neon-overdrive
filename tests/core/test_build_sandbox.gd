extends SceneTree

# Test build sandbox (2026-10-10, Roy: "the game is incomplete and as long as
# that is the case it needs to be treated as an infinite testing ground").
# One boot with the switch on (NEON_TEST_BUILD=1) and the parked start
# (NEON_PARKED=1), then one step after another:
#
#  1 start      parked at the kerb, engine off, silent, does not move on the
#               throttle; Engine and Turbo buses open although they were left
#               muted before the boot (the "no sound after spawning" bug)
#  2 X          a TAP of the starter key cranks (starter sound), the engine
#               catches, the automatic box is back, the car drives
#  3 money      bank and cash at zero: the pump fills the tank, payments go
#               through, nothing is taken
#  4 barrier    driven into the median barrier at speed: the run goes on
#               (no wreck, no restart, no cash lost); put_back parks it
#  5 wall       the same into the side wall
#  6 on barrier dropped on top of the median barrier: put_back parks it
#  7 roof       left on its roof in a lane: parked by itself
#  8 dry + dead tank empty and engine dead: put_back parks it, fuelled and
#               running again after X
# "Parked" is asserted each time: at the kerb (park_x), inside the walls, at
# ride height, upright, 3+ wheels down, standing still, nose down the road,
# engine off, screen clear; then X must start it.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/core/test_build_sandbox.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const TestDriver := preload("res://scripts/core/test_driver.gd")
const GasStation := preload("res://scripts/world/gas_station.gd")
const TestBuild := preload("res://scripts/core/test_build.gd")

var rate := 120
var logger := Harness.ErrorCounter.new()
var game: Node
var rescue: OffMapRescue
var p: PlayerCar
var starter: Node
var tick := 0
var fails: Array[String] = []
var keys := 0
var step := 0
var sub := 0
var began := false
var t := 0.0
var rest_y := 0.0
var crank_heard := false
var count_before := 0
var top_speed := 0.0
var hit_speed := 0.0

func _initialize() -> void:
	OS.add_logger(logger)
	OS.set_environment("NEON_TEST_BUILD", "1")
	OS.set_environment("NEON_PARKED", "1")
	ExhaustTune.save_path = "user://autotune/test_sandbox_exhaust.json"
	Engine.physics_ticks_per_second = rate
	# As a restart from the pause menu leaves them.
	for bus_name in [&"Engine", &"Turbo"]:
		AudioServer.set_bus_mute(AudioServer.get_bus_index(bus_name), true)
	game = Harness.boot(self, 6, 300.0, 4242)

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails.append("step %d: %s" % [step, what])
		print("  FAIL step %d: %s" % [step, what])

func _u() -> Vector3:
	return RoadFrame.unroll(p.global_position)

func _engine_audio() -> EngineAudio:
	for c in p.get_children():
		if c is EngineAudio:
			return c
	return null

func _wheels_down() -> int:
	var n := 0
	for w in p.wheel_array:
		if (w as Wheel).is_colliding():
			n += 1
	return n

func _check_parked(what: String) -> void:
	var u := _u()
	var s := RoadFrame.s_at(u.z)
	var b := rescue._bounds_at(u.z)
	var nose := RoadFrame.dir_to_road(u.z, -p.global_transform.basis.z)
	print("  %s: x %.2f (kerb spot %.2f, road edge %.2f, wall %.2f), y %.2f, up %.3f, wheels %d, speed %.2f, nose z %.3f, engine %s" % [
		what, u.x, OffMapRescue.park_x(s), GasStation.own_edge(s), b.x, u.y, p.global_transform.basis.y.y, _wheels_down(),
		p.linear_velocity.length(), nose.z, "on" if p.engine_running else "off"])
	_check(absf(u.x - OffMapRescue.park_x(s)) < 0.4, "%s: not at the kerb spot (x %.2f, spot %.2f)" % [what, u.x, OffMapRescue.park_x(s)])
	_check(u.x > 2.0 and u.x < b.x - 1.0, "%s: not between the lanes' start and the wall (x %.2f, wall %.2f)" % [what, u.x, b.x])
	_check(absf(u.y - rest_y) < 0.15, "%s: not at ride height (y %.2f, rest %.2f)" % [what, u.y, rest_y])
	_check(p.global_transform.basis.y.y > 0.97, "%s: not level (up %.3f)" % [what, p.global_transform.basis.y.y])
	_check(_wheels_down() >= 3, "%s: %d wheels down" % [what, _wheels_down()])
	_check(p.linear_velocity.length() < 0.3, "%s: moving at %.2f m/s" % [what, p.linear_velocity.length()])
	_check(nose.z < -0.98, "%s: not pointing down the road (nose z %.3f)" % [what, nose.z])
	_check(not p.engine_running and p.is_switched_off(), "%s: engine not off" % what)
	_check(rescue.phase == OffMapRescue.Phase.WATCH, "%s: screen not clear" % what)
	_check(game.game_state.state == GameState.State.PLAYING, "%s: not PLAYING" % what)

func _next() -> void:
	step += 1
	sub = 0
	began = false
	t = 0.0
	keys = 0

## Tap X, wait for the engine: true once this sub-sequence is over.
func _start_engine(delta: float) -> bool:
	if sub == 0:
		keys = PlayerCar.KEY_STARTER
		if t > 0.05:
			keys = 0
			sub = 1
			crank_heard = false
		return false
	if sub == 1:
		crank_heard = crank_heard or starter.level > 0.2
		if p.engine_running and not p.is_switched_off():
			print("  X: engine caught after %.2f s, rpm %.0f, box %s" % [t, p.motor_rpm, PlayerCar.TRANSMISSION_LETTERS[p.transmission_mode()]])
			_check(crank_heard, "the starter was not heard")
			_check(p.transmission_mode() == PlayerCar.Transmission.AUTO and not p.realistic_clutch, "the automatic box did not come back")
			sub = 2
			t = 0.0
		elif t > 3.0:
			_check(false, "the engine did not start within 3 s of a tap of X")
			p.ignition_on()
			sub = 2
			t = 0.0
		return false
	if sub == 2 and t > 0.5:
		var ea := _engine_audio()
		_check(ea.synth.volume > 0.0, "engine voice silent after the start")
		_check(not AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Engine")), "Engine bus muted")
		return true
	return false

## After a put-back: wait for the fade and the settle, check, start the engine.
func _parked_then_start(delta: float, what: String) -> bool:
	if sub == 10:
		if rescue.count > count_before and rescue.phase == OffMapRescue.Phase.WATCH and t > 2.0:
			_check_parked(what)
			sub = 0
			t = 0.0
		elif t > 12.0:
			_check(false, "%s: never put back" % what)
			return true
		return false
	return _start_engine(delta)

func _physics_process(delta: float) -> bool:
	tick += 1
	if tick < rate:
		return false
	if tick == rate:
		p = game.get("player")
		rescue = game.get("rescue")
		starter = p.get_node("StarterAudio")
		p.driver = func(c: PlayerCar) -> void: c.apply_keys(keys)
		rest_y = _u().y
		_check(TestBuild.on(), "the switch is not on")
		print("test_build_sandbox: step 1, the start")
		step = 1
		_check_parked("start")
		_check(not AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Engine")), "Engine bus still muted after the boot")
		_check(not AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Turbo")), "Turbo bus still muted after the boot")
		keys = PlayerCar.KEY_ACCEL
		return false
	t += delta
	match step:
		1:
			if t > 1.5:
				_check(p.linear_velocity.length() < 0.3, "moved on the throttle with the engine off (%.2f m/s)" % p.linear_velocity.length())
				_check(_engine_audio().synth.volume == 0.0, "engine voice not silent while off")
				_check(starter.cranks == 0, "the starter turned without X")
				print("test_build_sandbox: step 2, X")
				_next()
		2:
			if sub < 3:
				if _start_engine(delta):
					sub = 3
					t = 0.0
					keys = PlayerCar.KEY_ACCEL
			elif t > 4.0:
				print("  drove off: %.1f km/h after 4 s" % (p.linear_velocity.length() * 3.6))
				_check(p.linear_velocity.length() > 5.0, "did not drive after the start (%.2f m/s)" % p.linear_velocity.length())
				print("test_build_sandbox: step 3, money")
				_next()
		3:
			var w: Node = game.get("wallet")
			w.cash = 0
			w.bank = 0
			p.fuel.litres = 2.0
			var got: float = p.fuel.refuel(w)
			print("  pump with $0: %.0f L in, tank %.0f of %.0f L, bank %d" % [got, p.fuel.litres, FuelTank.CAPACITY_L, w.bank])
			_check(got > 40.0 and p.fuel.litres > FuelTank.CAPACITY_L - 1.0, "the pump did not fill the tank with an empty bank")
			_check(w.spend_bank(5000), "a payment was refused")
			_check(w.bank == 0 and w.cash == 0, "money went below or above zero")
			w.add_cash(300)
			_check(w.take_cash(300) == 0 and w.cash == 300, "cash was taken")
			_check(p.damage.garage_repair(w) >= 0, "repair refused")
			_check(not game.wrecks_on(), "wrecks are on")
			print("test_build_sandbox: step 4, the median barrier at speed")
			_next()
		4, 5:
			if not began:
				began = true
				# 4: from lane 0 into the median; 5: from the kerbside lane into the wall
				var left := step == 4
				TestDriver.place(p, 2.0 if left else 11.6, 60.0, deg_to_rad(50.0 if left else -50.0), 40.0)
				keys = PlayerCar.KEY_ACCEL
				hit_speed = 0.0
				top_speed = 40.0
				sub = 21
				t = 0.0
			elif sub == 21:
				hit_speed = maxf(hit_speed, top_speed - p.linear_velocity.length())
				if t > 3.0:
					var u := _u()
					print("  after the hit: x %.2f, y %.2f, up %.2f, lost %.0f km/h, state %d, wreck phase %d, cash %d" % [
						u.x, u.y, p.global_transform.basis.y.y, hit_speed * 3.6, game.game_state.state, game.run_end.phase, game.wallet.cash])
					_check(hit_speed > 8.0, "no hit happened")
					_check(game.game_state.state == GameState.State.PLAYING, "the hit ended the run")
					_check(game.run_end.phase == 0, "the crash screen started")
					_check(game.wallet.cash == 300, "the hit cost cash")
					count_before = rescue.count
					keys = 0
					_check(game.put_back(), "put_back refused")
					sub = 10
					t = 0.0
			elif _parked_then_start(delta, "after the barrier" if step == 4 else "after the wall"):
				print("test_build_sandbox: step %d" % (step + 1))
				_next()
		6:
			if not began:
				began = true
				var u := _u()
				p.global_transform = RoadFrame.pose(0.0, 1.2, u.z - 40.0, 0.4)
				TrafficCar.set_moving(p, 0.0)
				p.reset_physics_interpolation()
				sub = 21
				t = 0.0
			elif sub == 21:
				if t > 2.5:
					var u := _u()
					print("  on the median barrier: x %.2f, y %.2f, up %.2f, wheels %d" % [u.x, u.y, p.global_transform.basis.y.y, _wheels_down()])
					count_before = rescue.count
					_check(game.put_back(), "put_back refused")
					sub = 10
					t = 0.0
			elif _parked_then_start(delta, "off the barrier"):
				print("test_build_sandbox: step 7, on its roof")
				_next()
		7:
			if not began:
				began = true
				var u := _u()
				var xf := RoadFrame.pose(5.2, 1.4, u.z - 40.0, 0.0)
				xf.basis = xf.basis * Basis(Vector3.FORWARD, PI)
				p.global_transform = xf
				TrafficCar.set_moving(p, 0.0)
				p.reset_physics_interpolation()
				count_before = rescue.count
				sub = 10
				t = 0.0
			elif _parked_then_start(delta, "off its roof"):
				_check(rescue.last_reason == OffMapRescue.REASON_FLIPPED, "not put back for being on its roof (%s)" % rescue.last_reason)
				print("test_build_sandbox: step 8, dry tank and dead engine")
				_next()
		8:
			if not began:
				began = true
				p.fuel.litres = 0.0
				p.damage.parts[CarDamage.Part.RADIATOR] = 1.0
				_check(p.damage.is_engine_dead() and p.fuel.is_empty(), "could not break the car")
				count_before = rescue.count
				_check(game.put_back(), "put_back refused")
				sub = 10
				t = 0.0
			elif sub == 3:
				if t > 4.0:
					print("  dry and dead, then put back: tank %.0f L, engine dead %s, %.1f km/h after 4 s" % [p.fuel.litres, p.damage.is_engine_dead(), p.linear_velocity.length() * 3.6])
					_check(not p.damage.is_engine_dead() and not p.fuel.is_empty(), "still dry or dead after the put-back")
					_check(p.linear_velocity.length() > 5.0, "did not drive on")
					_next()
			elif _parked_then_start(delta, "dry and dead"):
				sub = 3
				t = 0.0
				keys = PlayerCar.KEY_ACCEL
		_:
			for e in logger.errors:
				print("  ENGINE ERROR: %s" % e)
			_check(logger.errors.is_empty(), "%d engine errors" % logger.errors.size())
			print("test_build_sandbox: %s (%d put-backs)" % ["PASS" if fails.is_empty() else "FAIL: %s" % "; ".join(fails), rescue.count])
			for bus_name in [&"Engine", &"Turbo"]:
				AudioServer.set_bus_mute(AudioServer.get_bus_index(bus_name), false)
			quit(0 if fails.is_empty() else 1)
			return true
	return false
