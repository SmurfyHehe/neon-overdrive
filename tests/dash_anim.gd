extends SceneTree

# Dashboard animations (2026-10-09, DashAnim), headless and silent:
# - the pure laws: redline shake zero below SHAKE_START and bounded above it,
#   idle vibration only near idle and standing still, sweep curve 0 -> 1 -> 0
# - in the real Game.tscn cockpit: the start-up sweep drives the tach needle
#   above its idle position after spawn, the cold-start puff shows, a car at
#   idle shakes the eye a little (and not when the engine is off), and each
#   FxSettings flag switches its own effect off
# - nothing logs an error
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/dash_anim.gd

const TIMEOUT_TICKS := 60 * 40

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

enum Step { BOOT, SWEEP, SETTLE, IDLE, OFF, DONE }

var logger := ErrorCounter.new()
var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var low_tach := 99.0
var peak_shake := 0.0

func _initialize() -> void:
	ExhaustTune.save_path = "user://autotune/test_dash_anim_exhaust.json"
	OS.add_logger(logger)
	_laws()
	change_scene_to_file("res://Game.tscn")

func _laws() -> void:
	_check(DashAnim.needle_shake_deg(0.5, 1.234) == 0.0, "no shake mid-range")
	_check(DashAnim.needle_shake_deg(DashAnim.SHAKE_START, 0.3) == 0.0, "no shake exactly at SHAKE_START")
	var worst := 0.0
	for i in 400:
		worst = maxf(worst, absf(DashAnim.needle_shake_deg(1.0, float(i) * 0.013)))
	_check(worst > 0.5 * DashAnim.SHAKE_DEG and worst <= DashAnim.SHAKE_DEG, "redline shake visible but capped (%.2f deg)" % worst)
	_check(DashAnim.idle_amount(true, 800.0, 800.0, 0.0) == 1.0, "idle, standing: full vibration")
	_check(DashAnim.idle_amount(false, 0.0, 800.0, 0.0) == 0.0, "engine off: none")
	_check(DashAnim.idle_amount(true, 3000.0, 800.0, 0.0) == 0.0, "revved: none")
	_check(DashAnim.idle_amount(true, 800.0, 800.0, 20.0) == 0.0, "driving: none")
	_check(DashAnim.idle_shake(0.0, 800.0, 0.5).pos == Vector3.ZERO, "zero amount: zero shake")
	_check(DashAnim.sweep_curve(-1.0) == 0.0 and DashAnim.sweep_curve(DashAnim.SWEEP_TOTAL + 0.1) == 0.0, "sweep is 0 outside its window")
	_check(is_equal_approx(DashAnim.sweep_curve(DashAnim.SWEEP_UP + 0.01), 1.0), "sweep reaches full")
	var d := DashAnim.new()
	_check(d.update(true, 0.016), "first running frame counts as a start")
	_check(not d.update(true, 0.016), "no second start while running")
	d.update(false, 0.016)
	_check(d.update(true, 0.016), "a restart counts")

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("player") == null or game.get("camera") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	var p: PlayerCar = game.player
	var cam: ChaseCamera = game.camera
	var frame: CockpitFrame = cam.frame
	if frame == null:
		return false
	var flames: ExhaustFlames = game.fx.flames
	var waited := tick - step_start
	p.throttle_input = 0.0
	p.brake_input = 1.0
	match step:
		Step.BOOT:
			cam.shake_enabled = false
			cam.set_view(ChaseCamera.View.COCKPIT)
			frame.dash_anim.sweep_t = 0.0   # the spawn sweep may be over already: replay it
			_go(Step.SWEEP)
		Step.SWEEP:
			# rotation.z is 135 deg at 0 revs and falls to -135 at max: the sweep must get near the end
			low_tach = minf(low_tach, frame.tach_needle.rotation.z)
			if (frame.dash_anim.sweep_t < 0.0 and waited > 10) or waited > 600:
				_check(frame.dash_anim.sweep_t < 0.0, "the sweep ends")
				_check(low_tach < deg_to_rad(-120.0), "start-up sweep drives the tach to full (lowest %.0f deg)" % rad_to_deg(low_tach))
				print("after sweep: sweep_t %.2f rpm %.0f idle %.0f" % [frame.dash_anim.sweep_t, p.motor_rpm, p.idle_rpm])
				_check(frame.tach_needle.rotation.z > deg_to_rad(60.0), "tach is back near idle after the sweep (%.0f deg)" % rad_to_deg(frame.tach_needle.rotation.z))
				_go(Step.SETTLE)
		Step.SETTLE:
			if waited == 120:
				_check(flames.puffs >= 1, "cold-start puff shown on spawn (%d)" % flames.puffs)
				_go(Step.IDLE)
		Step.IDLE:
			peak_shake = maxf(peak_shake, cam.idle_shake.length())
			if waited == 90:
				print("idle shake peak %.5f m" % peak_shake)
				_check(peak_shake > 0.0003 and peak_shake <= DashAnim.IDLE_SHAKE_M * 1.2, "idle shakes the eye a little (%.5f m)" % peak_shake)
				FxSettings.set_on("idle_shake", false)
				peak_shake = 0.0
				_go(Step.OFF)
		Step.OFF:
			if waited == 10:
				peak_shake = 0.0   # let a frame or two of the old value pass
			elif waited > 10:
				peak_shake = maxf(peak_shake, cam.idle_shake.length())
			if waited == 40:
				_check(peak_shake == 0.0, "idle_shake flag off: no shake (%.5f)" % peak_shake)
				FxSettings.set_on("idle_shake", true)
				var before := flames.puffs
				FxSettings.set_on("coldstart_puff", false)
				flames._was_running = false
				for i in 3:
					flames._watch_start()
				_check(flames.puffs == before, "coldstart_puff flag off: no puff")
				_go(Step.DONE)
		Step.DONE:
			return _end("")
	return false

func _go(s: Step) -> void:
	step = s
	step_start = tick

func _check(ok: bool, what: String) -> void:
	if what != "" and not ok:
		failures.append(what)
		print("FAIL: " + what)

func _end(msg: String) -> bool:
	if msg != "":
		failures.append(msg)
	for e in logger.errors:
		failures.append("logged error: " + e)
	print("dash_anim: %s" % ("PASS" if failures.is_empty() else "FAIL %d" % failures.size()))
	quit(0 if failures.is_empty() else 1)
	return true
