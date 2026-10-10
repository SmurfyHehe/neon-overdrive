extends SceneTree

# The gear lever follows the gearbox mode (2026-10-07), headless and silent:
# - AUTO in a car built with a manual box (every car so far): the H-gate
#   stick stays in the cabin and does not move, no paddle flicks, and the
#   right hand stays on the rim through the automatic's own shifts
# - AUTO in a car built with an automatic: the T-handle selector and the
#   P R N D pattern show, the others hide; in a forward gear it sits in D
#   (tilted back one row)
# - SEMI: the sequential stick shows and rests in the centre; an upshift
#   rocks it back, a downshift forward, and it springs back to the centre;
#   the right hand is on the knob for each tap and back on the rim after
# - MANUAL: the H-gate knob shows and the lever sits in the gear's H slot;
#   a shift moves it to the next gear's slot
# - no engine errors during any of it
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/view/cockpit_shifter.gd

const TIMEOUT_TICKS := 60 * 40
const GRIP_TOL := 0.02
const TILT_TOL := 0.5

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

enum Step { BOOT, AUTO, SEMI_UP, SEMI_DOWN, MANUAL, DONE }

static func ticks(secs: float) -> int:
	return int(round(secs * Engine.physics_ticks_per_second))

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var throttle := 0.0
var clutch := 0.0
var logger := ErrorCounter.new()
var hand_busy := false
var max_tilt := -90.0
var min_tilt := 90.0
var hand_at_knob := false
var stick_moved := false
var paddle_flicked := false
var gear_before := 0

func _initialize() -> void:
	ExhaustTune.save_path = "user://autotune/test_cockpit_shifter_exhaust.json"
	OS.add_logger(logger)
	change_scene_to_file("res://Game.tscn")

func _drive(c: PlayerCar) -> void:
	c.throttle_input = throttle
	c.brake_input = 0.0
	c.handbrake_input = 0.0
	c.steering_input = 0.0
	c.clutch_input = clutch

## Only the mode's knob and gate pattern are visible.
func _check_heads(frame: CockpitFrame, mode: int, label: String, shown := -1) -> void:
	_check(frame.lever_mode == mode, "%s: the lever is in mode %d (is %d)" % [label, mode, frame.lever_mode])
	for m in frame._lever_heads:
		var want: bool = m == (mode if shown < 0 else shown)
		_check((frame._lever_heads[m] as Node3D).visible == want, "%s: knob %s visible %s" % [label, (frame._lever_heads[m] as Node).name, want])
		_check((frame._gate_labels[m] as Node3D).visible == want, "%s: gate %s visible %s" % [label, (frame._gate_labels[m] as Node).name, want])

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("player") == null or game.get("camera") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	var p: PlayerCar = game.player
	var cam: ChaseCamera = game.camera
	p.driver = _drive
	var frame: CockpitFrame = cam.frame
	var d: DriverModel = frame.driver
	var waited := tick - step_start
	var knob: Vector3 = frame.lever.transform * frame.lever_knob.position
	var tilt := frame.lever.rotation_degrees.x
	match step:
		Step.BOOT:
			cam.set_view(ChaseCamera.View.COCKPIT)
			p.set_transmission_mode(PlayerCar.Transmission.AUTO)
			throttle = 1.0
			_go(Step.AUTO)
		Step.AUTO:
			hand_busy = hand_busy or d.is_busy()
			stick_moved = stick_moved or frame.lever_moving or absf(tilt) > TILT_TOL
			paddle_flicked = paddle_flicked or frame.wheel._paddle_t[-1] > 0.0 or frame.wheel._paddle_t[1] > 0.0 or d.paddle_t > 0.0
			if waited == ticks(2.5):
				_check(p.auto_box.box == AutoBox.BOX_MANUAL, "the coupe was built with a manual box")
				_check_heads(frame, PlayerCar.Transmission.AUTO, "auto, manual box", PlayerCar.Transmission.MANUAL)
				_check(p.gear >= 1, "auto: driving off puts the box in a forward gear (%d)" % p.gear)
				_check(not stick_moved, "auto, manual box: the stick does not move (tilt %.1f)" % tilt)
				_check(not paddle_flicked, "auto: no paddle flick on a car without paddles")
				_check(not hand_busy, "auto, manual box: the right hand stays on the rim")
				p.auto_box.box = AutoBox.BOX_AUTO   # the same car as if built with an automatic
			if waited == ticks(3.3):
				_check_heads(frame, PlayerCar.Transmission.AUTO, "auto")
				_check((frame._gate_labels[PlayerCar.Transmission.AUTO] as Label3D).text.replace(char(10), "").begins_with("PRND"), "auto: the selector pattern starts P R N D")
				_check(absf(tilt - CockpitFrame.LEVER_ROW_TILT) < TILT_TOL, "auto: the selector sits in D (tilt %.1f, want %.1f)" % [tilt, CockpitFrame.LEVER_ROW_TILT])
				_check(not hand_busy, "auto: the right hand stays on the rim")
				p.auto_box.box = AutoBox.BOX_MANUAL
				throttle = 0.4
				p.set_transmission_mode(PlayerCar.Transmission.SEMI)
				_go(Step.SEMI_UP)
		Step.SEMI_UP, Step.SEMI_DOWN:
			if waited == ticks(0.3):
				if step == Step.SEMI_UP:
					_check_heads(frame, PlayerCar.Transmission.SEMI, "semi")
				_check(absf(tilt) < TILT_TOL and not frame.lever_moving, "semi: the stick rests in the centre (tilt %.1f)" % tilt)
				gear_before = p.gear
				p.shift(1 if step == Step.SEMI_UP else -1)
				max_tilt = -90.0
				min_tilt = 90.0
				hand_at_knob = false
			if waited > ticks(0.3):
				max_tilt = maxf(max_tilt, tilt)
				min_tilt = minf(min_tilt, tilt)
				if d.hand_position(1).distance_to(knob) < 0.06 and absf(tilt) > 3.0:
					hand_at_knob = true
			if waited == ticks(1.6):
				var up := step == Step.SEMI_UP
				_check(p.gear == gear_before + (1 if up else -1), "semi: the shift went through (%d -> %d)" % [gear_before, p.gear])
				if up:
					_check(max_tilt > 0.7 * CockpitFrame.LEVER_ROW_TILT and min_tilt > -1.0, "semi: an upshift rocks the stick back only (%.1f..%.1f)" % [min_tilt, max_tilt])
				else:
					_check(min_tilt < -0.7 * CockpitFrame.LEVER_ROW_TILT and max_tilt < 1.0, "semi: a downshift rocks the stick forward only (%.1f..%.1f)" % [min_tilt, max_tilt])
				_check(absf(tilt) < TILT_TOL and not frame.lever_moving, "semi: the stick springs back to the centre (tilt %.1f)" % tilt)
				_check(hand_at_knob, "semi: the right hand is on the knob while the stick moves")
				_check(not d.is_busy() and d.hand_position(1).distance_to(d.grip_position(1)) <= GRIP_TOL, "semi: the hand is back on the rim")
				if up:
					_go(Step.SEMI_DOWN)
				else:
					clutch = 1.0
					p.set_transmission_mode(PlayerCar.Transmission.MANUAL)
					_go(Step.MANUAL)
		Step.MANUAL:
			if waited == ticks(0.3):
				_check_heads(frame, PlayerCar.Transmission.MANUAL, "manual")
				_check(absf(tilt - CockpitFrame.LEVER_ROW_TILT * frame._slot_of(p.gear).y) < TILT_TOL, "manual: the lever sits in the H slot of gear %d (tilt %.1f)" % [p.gear, tilt])
				gear_before = p.gear
				p.shift(1)
			if waited == ticks(1.8):
				_check(p.gear == gear_before + 1, "manual: the shift went through (%d -> %d)" % [gear_before, p.gear])
				var slot := frame._slot_of(p.gear)
				var rot := frame.lever.rotation_degrees
				_check(not frame.lever_moving and absf(rot.x - CockpitFrame.LEVER_ROW_TILT * slot.y) < TILT_TOL and absf(rot.z + CockpitFrame.LEVER_COL_TILT * slot.x) < TILT_TOL, "manual: the lever settles in gear %d's H slot (%s)" % [p.gear, rot])
				_check(logger.errors.is_empty(), "engine errors: %s" % [logger.errors.slice(0, 5)])
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
	print("cockpit_shifter: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
