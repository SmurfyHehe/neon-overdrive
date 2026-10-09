extends SceneTree

# The gear lever's R-N-D selector and how fast the lever answers a gear change
# (PR #151 follow-up, 2026-10-07), headless and silent:
# - AUTO at a standstill: the selector sits in N or D to match the box
# - AUTO, R (toggle_reverse): the selector starts for R within a couple of
#   rendered frames of the gear change and settles in R (forward row); R again
#   puts it back in D
# - MANUAL: the lever starts within a couple of rendered frames of the shift
# - SEMI: the stick starts its tap after SEQ_WAIT (the hand's reach), no later
# - no engine errors during any of it
# The game has no park position, so there is no P to check.
# Lag is counted in rendered (process) frames, since the cockpit moves the lever
# in _process: headless runs several 120 Hz physics ticks per rendered frame.
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/view/cockpit_shifter_rnd.gd

const TIMEOUT_TICKS := 120 * 40
const TILT_TOL := 0.5
const START_FRAMES := 2      # the lever must start within this many rendered frames
const SETTLE_SECS := 0.5     # and be in the new slot within this much game time

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

enum Step { BOOT, AUTO_STOP, AUTO_R, AUTO_D, MANUAL, SEMI, DONE }

static func ticks(secs: float) -> int:
	return int(round(secs * Engine.physics_ticks_per_second))

static func frames() -> int:
	return Engine.get_process_frames()

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var clutch := 0.0
var logger := ErrorCounter.new()
var gear_before := 0
var change_tick := -1    # tick the gear (or the shift) changed
var change_frame := -1   # and the rendered frame
var start_frame := -1    # rendered frame the lever answered (moving or off its slot)
var tilt_tick := -1      # tick the lever first left its slot
var tilt_frame := -1
var settle_tick := -1    # tick the lever reached the new slot
var start_tilt := 0.0

func _initialize() -> void:
	ExhaustTune.save_path = "user://autotune/test_cockpit_shifter_rnd_exhaust.json"
	OS.add_logger(logger)
	change_scene_to_file("res://Game.tscn")

func _drive(c: PlayerCar) -> void:
	c.throttle_input = 0.0
	c.brake_input = 1.0
	c.handbrake_input = 0.0
	c.steering_input = 0.0
	c.clutch_input = clutch

func _reset_watch(tilt: float) -> void:
	change_tick = -1
	change_frame = -1
	start_frame = -1
	tilt_tick = -1
	tilt_frame = -1
	settle_tick = -1
	start_tilt = tilt

func _mark_change() -> void:
	change_tick = tick
	change_frame = frames()

## Tracks when the lever answered, left its slot and reached want_tilt.
func _watch(frame: CockpitFrame, tilt: float, want_tilt: float) -> void:
	if change_tick < 0:
		return
	var off := absf(tilt - start_tilt) > 0.1
	if start_frame < 0 and (frame.lever_moving or off):
		start_frame = frames()
	if tilt_tick < 0 and off:
		tilt_tick = tick
		tilt_frame = frames()
	if settle_tick < 0 and absf(tilt - want_tilt) < TILT_TOL and not frame.lever_moving:
		settle_tick = tick

func _check_start(label: String) -> void:
	_check(change_tick >= 0, "%s: the gear changed" % label)
	_check(start_frame >= 0 and start_frame - change_frame <= START_FRAMES, "%s: the lever answers within %d frames (%d)" % [label, START_FRAMES, start_frame - change_frame])

func _check_settle(label: String) -> void:
	_check(settle_tick >= 0 and settle_tick - change_tick <= ticks(SETTLE_SECS), "%s: the lever settles within %.1f s (%d ticks)" % [label, SETTLE_SECS, settle_tick - change_tick])

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("player") == null or game.get("camera") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	var p: PlayerCar = game.player
	var cam: ChaseCamera = game.camera
	p.driver = _drive
	var frame: CockpitFrame = cam.frame
	var waited := tick - step_start
	var tilt := frame.lever.rotation_degrees.x
	var row := CockpitFrame.LEVER_ROW_TILT
	match step:
		Step.BOOT:
			cam.set_view(ChaseCamera.View.COCKPIT)
			p.set_transmission_mode(PlayerCar.Transmission.AUTO)
			_go(Step.AUTO_STOP)
		Step.AUTO_STOP:
			if waited == ticks(1.5):
				_check(frame.lever_mode == PlayerCar.Transmission.AUTO, "auto: the lever is the selector")
				_check(p.gear >= 0, "auto: standing still the box is in N or D (%d)" % p.gear)
				_check(absf(tilt - row * signf(float(p.gear))) < TILT_TOL, "auto: the selector sits in %s (tilt %.1f)" % ["D" if p.gear > 0 else "N", tilt])
				gear_before = p.gear
				_reset_watch(tilt)
				_check(p.toggle_reverse(), "auto: R is accepted at a standstill")
				_go(Step.AUTO_R)
		Step.AUTO_R, Step.AUTO_D:
			var to_r := step == Step.AUTO_R
			if change_tick < 0 and p.gear != gear_before:
				_mark_change()
			_watch(frame, tilt, -row if to_r else row)
			if waited == ticks(1.5):
				var label := "auto R" if to_r else "auto D"
				if to_r:
					_check(p.gear == -1, "auto: R puts the box in reverse (%d)" % p.gear)
				else:
					_check(p.gear >= 1, "auto: R again puts the box back in a forward gear (%d)" % p.gear)
				_check_start(label)
				_check_settle(label)
				_check(absf(tilt - (-row if to_r else row)) < TILT_TOL and not frame.lever_moving, "%s: the selector rests in its slot (tilt %.1f)" % [label, tilt])
				if to_r:
					gear_before = p.gear
					_reset_watch(tilt)
					_check(p.toggle_reverse(), "auto: R again is accepted")
					_go(Step.AUTO_D)
				else:
					clutch = 1.0
					p.set_transmission_mode(PlayerCar.Transmission.MANUAL)
					_go(Step.MANUAL)
		Step.MANUAL, Step.SEMI:
			var semi := step == Step.SEMI
			if waited == ticks(0.5):
				gear_before = p.gear
				_reset_watch(tilt)
				p.shift(1)
			# the lever follows the shift as it starts (is_shifting), not the end
			if waited > ticks(0.5) and change_tick < 0 and (p.is_shifting or p.gear != gear_before):
				_mark_change()
			_watch(frame, tilt, 0.0 if semi else row * frame._slot_of(gear_before + 1).y)
			if waited == ticks(2.0):
				var label := "semi" if semi else "manual"
				_check(p.gear == gear_before + 1, "%s: the shift went through (%d -> %d)" % [label, gear_before, p.gear])
				_check_start(label)
				if semi:
					# the stick waits SEQ_WAIT for the hand, then taps; allow a
					# couple of rendered frames on top of that
					var per_frame := float(tilt_tick - change_tick) / maxf(1.0, float(tilt_frame - change_frame))
					var limit := ticks(CockpitFrame.SEQ_WAIT) + int(ceil(START_FRAMES * per_frame))
					_check(tilt_tick >= 0 and tilt_tick - change_tick <= limit, "semi: the stick taps within SEQ_WAIT + %d frames (%d ticks, limit %d)" % [START_FRAMES, tilt_tick - change_tick, limit])
				else:
					_check_settle(label)
				if semi:
					_check(logger.errors.is_empty(), "engine errors: %s" % [logger.errors.slice(0, 5)])
					return _end("")
				clutch = 0.0
				p.set_transmission_mode(PlayerCar.Transmission.SEMI)
				_go(Step.SEMI)
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
	print("cockpit_shifter_rnd: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
