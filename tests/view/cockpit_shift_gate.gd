extends SceneTree

# The manual shift animation on one car (2026-10-09, Roy: the lever did not
# move to the gear and the hand went through the knob), headless and silent.
# In MANUAL with the clutch held the box is stepped through every gear,
# 1 -> 5 -> 1, then at a standstill neutral, reverse, neutral, first, and
# for every shift:
# - the right hand reaches the knob and holds it while the lever travels
#   (DriverModel.hand_on_knob), locked to it: the hand's grip sits on the
#   knob to within GRIP_TOL the whole way;
# - nothing of the knob or the lever shaft is inside the hand: the knob's
#   surface and the shaft, sampled, all lie outside every hand box
#   (DriverModel.hand_boxes) and the cuff, by CLIP_TOL;
# - the lever travels through the neutral rail and its tip lands on the
#   gear's gate position (CockpitFrame.gate_tip) within TIP_TOL;
# - the lever lands as the box engages: within LAND_TOL_SECS of the gear
#   change (shifts between gears; out of neutral the box engages at once);
# - the hand is back on the rim afterwards;
# - no engine errors.
# NEON_CAR picks the car (tests/run_tests.bat runs it for each player car);
# the car's own gate (CarSpec.shifter) is what the lever is held to.
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --audio-driver Dummy --path . -s res://tests/view/cockpit_shift_gate.gd

const TIMEOUT_TICKS := 60 * 60
const GRIP_TOL := 0.003
const CLIP_TOL := 0.0005
const TIP_TOL := 0.003
const LAND_TOL_SECS := 0.12
const RIM_TOL := 0.02
## Gears in order, from first: up the box, down, then at a standstill N, R, N, 1.
const SEQUENCE := [2, 3, 4, 5, 4, 3, 2, 1, 0, -1, 0, 1]

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

enum Step { BOOT, ROLL, SHIFT, SETTLE, STOP, DONE }

static func ticks(secs: float) -> int:
	return int(round(secs * Engine.physics_ticks_per_second))

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var throttle := 0.0
var brake := 0.0
var logger := ErrorCounter.new()
var seq_i := 0
var target := 0
var gear_before := 0
# per shift
var held_ticks := 0
var max_grip_err := 0.0
var clip_hits: Array[String] = []
var change_tick := -1
var land_tick := -1
var started := false
var passed_rail := false
var worst_hand_knob := 0.0

func _initialize() -> void:
	ExhaustTune.save_path = "user://autotune/test_cockpit_shift_gate_exhaust.json"
	OS.add_logger(logger)
	change_scene_to_file("res://Game.tscn")

func _drive(c: PlayerCar) -> void:
	c.throttle_input = throttle
	c.brake_input = brake
	c.handbrake_input = 0.0
	c.steering_input = 0.0
	c.clutch_input = 1.0

## Sample points on the knob's surface and the shaft, lever space.
func _lever_points(frame: CockpitFrame) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var knob: Vector3 = frame.lever_knob.position
	var r: float = CockpitFrame.KNOB_R
	for i in 16:
		var a := TAU * float(i) / 16.0
		for x in [-0.016, 0.0, 0.016]:
			pts.append(knob + Vector3(x, r * cos(a), r * sin(a)))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			pts.append(knob + Vector3(sx * 0.007, r, sz * 0.007))   # the silver top's corners
	for i in 10:
		var y: float = (frame.lever_len - 0.02) * float(i) / 9.0
		for a in [0.0, PI / 2.0, PI, 1.5 * PI]:
			pts.append(Vector3(0.008 * cos(a), y, 0.008 * sin(a)))
	return pts

## Points of the lever that are inside the right hand, as "where (x, y, z)".
func _clips(frame: CockpitFrame, d: DriverModel) -> Array[String]:
	var out: Array[String] = []
	var hand: Node3D = d.hands[1]
	var to_hand := hand.transform.affine_inverse() * frame.lever.transform
	var boxes: Array = DriverModel.hand_boxes(1)
	for p in _lever_points(frame):
		var h: Vector3 = to_hand * p
		for b in boxes:
			var half: Vector3 = (b[0] as Vector3) * 0.5 - Vector3.ONE * CLIP_TOL
			var c: Vector3 = b[1]
			if absf(h.x - c.x) < half.x and absf(h.y - c.y) < half.y and absf(h.z - c.z) < half.z:
				out.append("box %s at %s" % [b[1], h])
				break
		var cuff := Vector2(h.x - DriverModel.WRIST_X, h.y).length()
		if cuff < DriverModel.CUFF_R - CLIP_TOL and h.z > DriverModel.CUFF_Z0 + CLIP_TOL and h.z < DriverModel.CUFF_Z1 - CLIP_TOL:
			out.append("cuff at %s" % h)
	return out

func _reset_shift() -> void:
	held_ticks = 0
	max_grip_err = 0.0
	clip_hits.clear()
	change_tick = -1
	land_tick = -1
	started = false
	passed_rail = false
	worst_hand_knob = 0.0

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
	if tick > TIMEOUT_TICKS:
		return _end("timed out in step %d" % step)
	match step:
		Step.BOOT:
			cam.set_view(ChaseCamera.View.COCKPIT)
			p.set_transmission_mode(PlayerCar.Transmission.MANUAL)
			throttle = 0.5
			_go(Step.ROLL)
		Step.ROLL:
			if waited == ticks(1.5):
				_check(p.gear == 1 and not frame.lever_moving, "rolling in first with the lever still (gear %d)" % p.gear)
				_check(frame.lever_tip().distance_to(frame.gate_tip(1)) < TIP_TOL, "the lever starts in first's gate position")
				_begin_shift(p)
		Step.SHIFT:
			if change_tick < 0 and p.gear == target:
				change_tick = tick
			if frame.lever_started:
				started = true
			if frame.lever_passed_rail():
				passed_rail = true
			if started and land_tick < 0 and not frame.lever_moving:
				land_tick = tick
			if d.hand_on_knob():
				held_ticks += 1
				max_grip_err = maxf(max_grip_err, d.knob_grip_error())
				worst_hand_knob = maxf(worst_hand_knob, d.hand_position(1).distance_to(frame.lever_tip()))
				if clip_hits.size() < 3:
					for c in _clips(frame, d):
						clip_hits.append("tick %d gear %d->%d: %s" % [tick, gear_before, target, c])
			if waited == ticks(1.5):
				_judge_shift(p, frame, d)
				_go(Step.SETTLE)
		Step.SETTLE:
			if waited == ticks(0.2):
				seq_i += 1
				if seq_i >= SEQUENCE.size():
					_go(Step.DONE)
				elif SEQUENCE[seq_i] <= 0 or p.gear == 0 or p.gear < 0:
					# into neutral and reverse only at a standstill
					throttle = 0.0
					brake = 1.0
					_go(Step.STOP)
				else:
					_begin_shift(p)
		Step.STOP:
			if absf(p.current_speed()) < 0.3 and waited > ticks(0.5):
				brake = 0.0
				_begin_shift(p)
		Step.DONE:
			_check(logger.errors.is_empty(), "engine errors: %s" % [logger.errors.slice(0, 5)])
			return _end("")
	return false

func _begin_shift(p: PlayerCar) -> void:
	target = SEQUENCE[seq_i]
	gear_before = p.gear
	_reset_shift()
	p.shift(target - p.gear)
	_go(Step.SHIFT)

func _judge_shift(p: PlayerCar, frame: CockpitFrame, d: DriverModel) -> void:
	var label := "shift %d -> %d" % [gear_before, target]
	_check(p.gear == target, "%s: the shift went through (gear %d)" % [label, p.gear])
	_check(held_ticks > 0, "%s: the hand took the knob" % label)
	_check(started and land_tick >= 0, "%s: the lever travelled and landed" % label)
	_check(max_grip_err <= GRIP_TOL, "%s: the hand stayed on the knob (grip error %.4f m)" % [label, max_grip_err])
	_check(clip_hits.is_empty(), "%s: the knob or shaft is inside the hand: %s" % [label, clip_hits])
	_check(not frame.lever_moving, "%s: the lever is still after 1.5 s" % label)
	var tip := frame.lever_tip()
	var want := frame.gate_tip(target)
	_check(tip.distance_to(want) < TIP_TOL, "%s: the lever tip is on the gate position (%s, want %s)" % [label, tip, want])
	if gear_before != 0 and target != 0:
		_check(passed_rail, "%s: the lever went through the neutral rail" % label)
	# the box takes shift_time over a shift between gears; out of neutral it
	# engages at once (GEVP) and the lever can only follow
	if gear_before != 0 and change_tick >= 0 and land_tick >= 0:
		var gap := float(land_tick - change_tick) / Engine.physics_ticks_per_second
		_check(absf(gap) <= LAND_TOL_SECS, "%s: the lever lands as the box engages (%.2f s after the gear change)" % [label, gap])
	_check(not d.is_busy() and d.hand_position(1).distance_to(d.grip_position(1)) <= RIM_TOL, "%s: the hand is back on the rim" % label)
	print("%s: held %d ticks, grip error %.4f, hand-knob %.3f, landed %+d ticks from the change" % [label, held_ticks, max_grip_err, worst_hand_knob, (land_tick - change_tick) if change_tick >= 0 and land_tick >= 0 else 0])

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
	print("cockpit_shift_gate (%s): %s" % [PlayerCar.chassis_kind(), "PASS" if failures.is_empty() else "FAIL"])
	quit(0 if failures.is_empty() else 1)
	return true
