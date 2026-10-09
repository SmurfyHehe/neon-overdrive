extends SceneTree

# Tyre smoke (2026-10-07), headless and silent: boots the real Game.tscn and
# checks that
# - game.fx.smoke (TyreSmoke) is in the tree, the tyre_smoke flag defaults on
#   and turns the node off and on, and the pause menu has the two sliders
# - the rate rules hold: a chirp's scorch makes no smoke, a burnout pours more
#   than a drift at the same slip, a hot tyre more than a cold one, a slider at
#   0 makes none, the colour hook reads a spec's tyre_smoke_colour
# - a short wheelspin from a standstill (a chirp) emits nothing
# - a handbrake slide at speed emits drift smoke, and with the drift slider at
#   0 the same slide emits none
# - holding the car on the brakes at full throttle (a burnout) emits burnout
#   smoke, more puffs per second than the drift
# - shift_world() moves every live puff
# - nothing logs an error the whole time
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/fx/tyre_smoke.gd

const TIMEOUT_TICKS := 60 * 120

enum Step { BOOT, CHECK, CHIRP, CHIRP_SETTLE, LAUNCH, SLIDE, STOP, LAUNCH2, SLIDE_OFF, STOP2, BURNOUT, SHIFT }

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

var logger := ErrorCounter.new()
var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var throttle := 0.0
var brake := 0.0
var steer := 0.0
var handbrake := 0.0
var mark := 0
var drift_rate := 0.0
var start_x := 0.0

func _initialize() -> void:
	ExhaustTune.save_path = "user://autotune/test_tyre_smoke_exhaust.json"
	OS.add_logger(logger)
	seed(4242)
	change_scene_to_file("res://Game.tscn")

func _sec(seconds: float) -> int:
	return int(seconds * Engine.physics_ticks_per_second)

func _drive(c: PlayerCar) -> void:
	c.throttle_input = throttle
	c.brake_input = brake
	c.steering_input = steer
	c.handbrake_input = handbrake

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("player") == null or game.get("fx") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	if tick > TIMEOUT_TICKS:
		return _end("timed out in step %d" % step)
	var p: PlayerCar = game.player
	var fx: FxPack = game.fx
	var s: TyreSmoke = fx.smoke
	p.driver = _drive
	var waited := tick - step_start
	match step:
		Step.BOOT:
			_go(Step.CHECK)
		Step.CHECK:
			if waited < 5:
				return false
			# never depend on the player's saved amounts
			FxSettings.set_smoke(1.0, 1.0)
			start_x = p.global_position.x
			_check(s != null and s.is_inside_tree(), "TyreSmoke should be in the tree")
			_check(FxSettings.is_on("tyre_smoke"), "tyre_smoke should default on")
			fx.set_effect("tyre_smoke", false)
			_check(not s.enabled and not s.visible and not s.is_physics_processing(), "tyre_smoke off should hide and stop TyreSmoke")
			fx.set_effect("tyre_smoke", true)
			_check(s.enabled and s.visible and s.is_physics_processing(), "tyre_smoke on should restart TyreSmoke")
			var menu: PauseMenu = null
			for c in game.get_children():
				if c is PauseMenu:
					menu = c
			_check(menu != null and menu.smoke_burnout_slider != null and menu.smoke_drift_slider != null,
				"the pause menu should have Burnout and Drift smoke sliders")
			_check(menu == null or menu.smoke_burnout_slider.focus_mode != Control.FOCUS_NONE, "the smoke sliders should take keyboard focus")
			_unit_checks(s)
			s.clear()
			s.emitted = 0
			throttle = 1.0
			_go(Step.CHIRP)
		Step.CHIRP:
			# a tenth of a second of full throttle off the line, then off
			if waited >= _sec(0.12):
				throttle = 0.0
				brake = 1.0
				_go(Step.CHIRP_SETTLE)
		Step.CHIRP_SETTLE:
			if waited >= _sec(1.0):
				print("chirp: %d puffs" % s.emitted)
				_check(s.emitted == 0, "a chirp off the line should make no smoke (%d puffs)" % s.emitted)
				brake = 0.0
				throttle = 1.0
				_go(Step.LAUNCH)
		Step.LAUNCH:
			if p.linear_velocity.length() > 16.0:
				throttle = 0.0
				handbrake = 1.0
				steer = 1.0
				mark = s.emitted
				_go(Step.SLIDE)
			elif waited > _sec(25):
				return _end("launch never reached 16 m/s (%.1f)" % p.linear_velocity.length())
		Step.SLIDE:
			if waited >= _sec(2.0):
				var n := s.emitted - mark
				drift_rate = n / 2.0
				print("drift: %d puffs in 2 s (%d drift, %d burnout total), %d live" % [n, s.emitted_drift, s.emitted_burnout, s.live_count()])
				_check(n > 0, "a handbrake slide at speed should make drift smoke")
				_go(Step.STOP)
		Step.STOP:
			handbrake = 0.0
			steer = 0.0
			brake = 1.0
			if p.linear_velocity.length() < 0.5 and waited > _sec(1.0):
				_straighten(p)
				brake = 0.0
				throttle = 1.0
				FxSettings.set_smoke(1.0, 0.0)
				_go(Step.LAUNCH2)
		Step.LAUNCH2:
			if p.linear_velocity.length() > 16.0:
				throttle = 0.0
				handbrake = 1.0
				steer = 1.0
				mark = s.emitted
				_go(Step.SLIDE_OFF)
			elif waited > _sec(25):
				return _end("second launch never reached 16 m/s")
		Step.SLIDE_OFF:
			if waited >= _sec(2.0):
				var n := s.emitted - mark
				print("drift with slider 0: %d puffs" % n)
				_check(s.emitted_burnout >= 0 and n <= 1, "the drift slider at 0 should stop drift smoke (%d puffs)" % n)
				FxSettings.set_smoke(1.0, 1.0)
				_go(Step.STOP2)
		Step.STOP2:
			handbrake = 0.0
			steer = 0.0
			brake = 1.0
			if p.linear_velocity.length() < 0.5 and waited > _sec(1.0):
				_straighten(p)
				# burnout: brakes on, full throttle; the front brakes hold, the rears spin
				throttle = 1.0
				brake = 1.0
				p.traction_control_max_slip = 0.0
				mark = s.emitted
				_go(Step.BURNOUT)
		Step.BURNOUT:
			if waited >= _sec(3.0):
				var n := s.emitted - mark
				print("burnout: %d puffs in 3 s, %d live, rear tyres %.0f / %.0f degC, rear slip %.2f" % [n, s.live_count(),
					p.health.tyre_temp[2], p.health.tyre_temp[3], p.wheel_array[2].slip_vector.y])
				_check(n > 0, "a burnout should make smoke")
				_check(n / 3.0 > drift_rate, "a burnout should pour more smoke than a drift (%.1f vs %.1f puffs/s)" % [n / 3.0, drift_rate])
				_check(s.emitted_burnout > 0, "the burnout should read as burnout smoke")
				throttle = 0.0
				_go(Step.SHIFT)
		Step.SHIFT:
			var before: Array[Vector3] = []
			var idx: Array[int] = []
			for i in TyreSmoke.MAX_PUFFS:
				if s._t - s._birth[i] <= s._life[i]:
					idx.append(i)
					before.append(s.puff_origin(i))
			var offset := Vector3(0.0, 0.0, 150.0)
			fx.shift_world(offset)
			var moved := true
			for k in idx.size():
				if not s.puff_origin(idx[k]).is_equal_approx(before[k] + offset):
					moved = false
			_check(idx.size() > 0 and moved, "shift_world should move every live puff (%d puffs)" % idx.size())
			return _end("")
	return false

## Back in the start lane, pointing down the road, at rest.
func _straighten(p: PlayerCar) -> void:
	p.global_transform = Transform3D(Basis.IDENTITY, Vector3(start_x, p.global_position.y + 0.05, p.global_position.z))
	p.linear_velocity = Vector3.ZERO
	p.angular_velocity = Vector3.ZERO

func _unit_checks(s: TyreSmoke) -> void:
	# a chirp: 0.12 s of full slip from cold builds the scorch to about 0.3
	s.clear()
	var sc := 0.0
	for _k in _sec(0.12):
		sc = s.step_scorch(0, 1.0, 1.0 / Engine.physics_ticks_per_second)
	_check(TyreSmoke.puff_rate(0.0, 1.0, sc, 60.0, 1.0, 1.0) == 0.0, "a chirp's scorch (%.2f) should make no smoke" % sc)
	for _k in _sec(1.0):
		sc = s.step_scorch(0, 1.0, 1.0 / Engine.physics_ticks_per_second)
	_check(TyreSmoke.puff_rate(0.0, 1.0, sc, 60.0, 1.0, 1.0) > 0.0, "a second of wheelspin (scorch %.2f) should smoke" % sc)
	s.clear()
	var burn := TyreSmoke.puff_rate(0.0, 1.0, 1.0, 100.0, 1.0, 1.0)
	var drift := TyreSmoke.puff_rate(1.0, 0.0, 1.0, 100.0, 1.0, 1.0)
	_check(burn > drift * 2.0, "burnout (%.1f/s) should be generous next to drift (%.1f/s)" % [burn, drift])
	_check(TyreSmoke.puff_rate(0.0, 1.0, 1.0, 120.0, 1.0, 1.0) > TyreSmoke.puff_rate(0.0, 1.0, 1.0, 40.0, 1.0, 1.0), "a hot tyre should smoke more than a cold one")
	_check(TyreSmoke.puff_rate(0.0, 1.0, 1.0, 100.0, 0.0, 1.0) == 0.0, "burnout slider 0 should stop burnout smoke")
	_check(TyreSmoke.puff_rate(1.0, 0.0, 1.0, 100.0, 1.0, 0.0) == 0.0, "drift slider 0 should stop drift smoke")
	_check(is_equal_approx(TyreSmoke.puff_rate(0.0, 1.0, 1.0, 100.0, 2.0, 1.0), burn * 2.0), "the burnout slider should scale the amount")
	_check(TyreSmoke.colour_from_spec({"tyre_smoke_colour": Color(0.9, 0.2, 0.2)}) == Color(0.9, 0.2, 0.2), "a spec's tyre_smoke_colour should reach the smoke")
	_check(TyreSmoke.colour_from_spec({}) == TyreSmoke.DEFAULT_COLOUR, "no colour in the spec means the default smoke")
	var m := s.amount_mods()
	_check(m[0] > 0.0 and m[1] > 0.0, "amount multipliers should be positive (%s)" % [m])

func _go(next: Step) -> void:
	step = next
	step_start = tick

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _end(msg: String) -> bool:
	if msg != "":
		failures.append(msg)
	for e in logger.errors:
		failures.append("logged error: " + e)
	for f in failures:
		printerr("FAIL: ", f)
	print("tyre_smoke: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	OS.remove_logger(logger)
	quit(0 if failures.is_empty() else 1)
	return true
