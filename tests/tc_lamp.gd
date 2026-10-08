extends SceneTree

# TC light + sound (2026-10-08), headless and silent: boots the real Game.tscn,
# sets traction control to High and the rear tyres to low grip so a launch
# makes TC cut, and checks over 3 s of full throttle in the cockpit view
# - the HUD warning strip's TC light flickers (seen both lit and dark)
# - the cockpit cluster's fifth lamp flickers the same way
# - the engine note chops (EngineAudio.tc_stutter() dips below 1)
# then lifts off and checks that all three go quiet once TC stops cutting,
# and that nothing logs an error. Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/tc_lamp.gd

const TIMEOUT_TICKS := 60 * 60

enum Step { BOOT, LAUNCH, LIFT }

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
var seen := {"active": 0, "hud_on": 0, "hud_off": 0, "lamp_on": 0, "lamp_off": 0, "chop": 0}
var quiet_bad := 0

func _initialize() -> void:
	ExhaustTune.save_path = "user://autotune/test_tc_lamp_exhaust.json"
	OS.add_logger(logger)
	seed(4242)
	change_scene_to_file("res://Game.tscn")

func _sec(seconds: float) -> int:
	return int(seconds * Engine.physics_ticks_per_second)

func _drive(c: PlayerCar) -> void:
	c.throttle_input = throttle
	c.brake_input = 0.0
	c.steering_input = 0.0
	c.handbrake_input = 0.0

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("player") == null or game.get("camera") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	if tick > TIMEOUT_TICKS:
		return _end("timed out in step %d" % step)
	var p: PlayerCar = game.player
	var cam: ChaseCamera = game.camera
	p.driver = _drive
	var lights: WarningLights = null
	for c in game.get_children():
		if c is WarningLights:
			lights = c
	var audio: EngineAudio = null
	for c in p.get_children():
		if c is EngineAudio:
			audio = c
	var waited := tick - step_start
	match step:
		Step.BOOT:
			if waited < 5:
				return false
			if lights == null or audio == null or cam.frame == null:
				return _end("missing WarningLights, EngineAudio or the cockpit frame")
			_check(lights.tc_label != null and lights.tc_label.text == "TC", "the HUD strip should have a TC light")
			_check(cam.frame.lamps.multimesh.instance_count == CockpitFrame.LAMP_COUNT and CockpitFrame.LAMP_COUNT == 5,
				"the cockpit cluster should have five lamps")
			cam.set_view(ChaseCamera.View.COCKPIT)
			p.traction_control_max_slip = 4.0  # High
			for w in [p.rear_left_wheel, p.rear_right_wheel]:
				w.coefficient_of_friction = {"Road": 1.0, "Dirt": 2.0}
				w.current_cof = 1.0
			p.linear_velocity = Vector3.ZERO
			throttle = 1.0
			_go(Step.LAUNCH)
		Step.LAUNCH:
			if p.tcs_active:
				seen.active += 1
				seen.hud_on += 1 if lights.tc_label.visible else 0
				seen.hud_off += 0 if lights.tc_label.visible else 1
				var a := 1.0 if cam.frame.tc_lamp_lit else 0.0
				seen.lamp_on += 1 if a > 0.5 else 0
				seen.lamp_off += 1 if a < 0.5 else 0
				seen.chop += 1 if audio.tc_stutter() < 1.0 else 0
			if waited >= _sec(3.0):
				print("tc_lamp: TC active %d ticks; HUD lit %d / dark %d; lamp lit %d / dark %d; chopped %d" % [
					seen.active, seen.hud_on, seen.hud_off, seen.lamp_on, seen.lamp_off, seen.chop])
				_check(seen.active > _sec(0.3), "High TC on a low-grip rear should cut for a while (%d ticks)" % seen.active)
				_check(seen.hud_on > 0 and seen.hud_off > 0, "the HUD TC light should flicker while TC cuts")
				_check(seen.lamp_on > 0 and seen.lamp_off > 0, "the cockpit TC lamp should flicker while TC cuts")
				_check(seen.chop > 0, "the engine note should chop while TC cuts")
				throttle = 0.0
				_go(Step.LIFT)
		Step.LIFT:
			if waited >= _sec(0.6):
				if p.tcs_active or lights.tc_label.visible or cam.frame.tc_lamp_lit or audio.tc_stutter() < 1.0:
					quiet_bad += 1
			if waited >= _sec(1.5):
				_check(quiet_bad == 0, "off the throttle the TC light, lamp and chop should stop (%d ticks not quiet)" % quiet_bad)
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
	for e in logger.errors:
		failures.append("logged error: " + e)
	for f in failures:
		printerr("FAIL: ", f)
	print("tc_lamp: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	OS.remove_logger(logger)
	quit(0 if failures.is_empty() else 1)
	return true
