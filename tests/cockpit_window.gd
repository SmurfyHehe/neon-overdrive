extends SceneTree

# The side window animation (2026-10-09, Roy: "the Z to roll up and roll down
# needs an animation"), headless and silent, for both window controls:
# - the cockpit has a door glass pane and, per the car's spec, a crank
#   (NEON_WINDOW_CONTROL=crank) or an armrest rocker switch (the coupe's own)
# - holding the window key rolls the glass down: its bottom edge tracks
#   PerspectiveAudio.window (ChaseCamera.window_openness()) tick by tick, and
#   after WINDOW_DOWN_SECS the pane is fully inside the door
# - while the key is held the left hand is off the rim at the control (on the
#   crank's knob, which has turned; on the rocker, which is tilted), and back
#   on the rim shortly after the window stops; the right hand never leaves
# - a tap rolls it back up; the glass and the hand follow
# - the hands never rise above DriverModel.HAND_TOP_MIN_DEG below the eye
#   (the sightline spec), no engine errors
# Exit code 1 on failure. Run (the crank variant sets the env first):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/cockpit_window.gd

const TIMEOUT_TICKS := 60 * 40
const GRIP_TOL := 0.02

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

enum Step { BOOT, DOWN, REST, TAP, DONE }   # BOOT waits 0.5 s for the car to settle

static func ticks(secs: float) -> int:
	return int(round(secs * Engine.physics_ticks_per_second))

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var logger := ErrorCounter.new()
var control := ""
var samples := 0
var hand_at_control := false
var hand_right_off := false
var min_below_eye := 90.0
var min_below_where := ""
var trace: Array[String] = []

func _initialize() -> void:
	ExhaustTune.save_path = "user://autotune/test_cockpit_window_exhaust.json"
	OS.add_logger(logger)
	change_scene_to_file("res://Game.tscn")

func _drive(c: PlayerCar) -> void:
	c.throttle_input = 0.0
	c.brake_input = 0.0
	c.handbrake_input = 0.0
	c.steering_input = 0.0

func _track_view(d: DriverModel, where: String) -> void:
	var eye := ChaseCamera.COCKPIT_EYE
	for side in [-1, 1]:
		var hand: MeshInstance3D = d.hands[side]
		for c in 8:
			var pt: Vector3 = hand.transform * hand.get_aabb().get_endpoint(c)
			var v: Vector3 = eye - pt
			var below := rad_to_deg(atan2(v.y, Vector2(v.x, v.z).length()))
			if below < min_below_eye:
				min_below_eye = below
				min_below_where = "%s hand %d" % [where, side]

## The glass bottom edge is exactly where the window value says, every tick.
func _check_glass(frame: CockpitFrame, cam: ChaseCamera, where: String) -> void:
	samples += 1
	var want := CockpitFrame.GLASS_BOTTOM - CockpitFrame.GLASS_TRAVEL * cam.window_openness()
	if absf(frame.glass_bottom_y() - want) > 1e-4:
		_check(false, "%s: glass bottom at %.4f, want %.4f for window %.3f" % [where, frame.glass_bottom_y(), want, cam.window_openness()])
	if absf(frame.window - cam.window_openness()) > 1e-6:
		_check(false, "%s: the frame's window value %.3f differs from the camera's %.3f" % [where, frame.window, cam.window_openness()])

func _control_pos(frame: CockpitFrame) -> Vector3:
	return frame.crank_knob_position() if control == "crank" else frame.switch_press_position()

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
	if step != Step.BOOT:
		_track_view(d, Step.keys()[step])
		_check_glass(frame, cam, Step.keys()[step])
		if waited % ticks(0.25) == 0:
			var crank_deg := rad_to_deg(frame.crank.rotation.x) if frame.crank != null else 0.0
			trace.append("%s +%.2fs window %.2f glass %.3f left hand at window %s crank %.0f deg" % [Step.keys()[step], waited / float(Engine.physics_ticks_per_second), cam.window_openness(), frame.glass_bottom_y(), str(d.left_at_window()), crank_deg])
	match step:
		Step.BOOT:
			if waited < ticks(0.5):
				return false   # let the car settle and the driver's hands find the rim
			control = frame.window_control
			print("window control: ", control)
			_check(frame.glass != null and frame.glass.get_parent() == frame, "the cockpit has a door glass pane")
			var glass_tris: int = frame.glass.mesh.surface_get_array_len(0) / 3
			_check(glass_tris == 4, "the pane is two faces, 4 triangles (%d)" % glass_tris)
			_check((frame.glass as VisualInstance3D).layers == CockpitFrame.INTERIOR_BIT, "the pane is on the interior layer")
			if control == "crank":
				_check(frame.crank != null and frame.window_switch == null, "a crank car has a crank and no switch")
				_check(frame.get_node_or_null("WindowControl/Crank/Arm") != null, "the crank has an arm")
			else:
				_check(control == "switch", "the control is crank or switch (%s)" % control)
				_check(frame.window_switch != null and frame.crank == null, "a switch car has a rocker and no crank")
				_check(frame.get_node_or_null("WindowControl/Switch/Rocker") != null, "the switch has a rocker")
			_check(cam.window_openness() == 0.0 and frame.glass_bottom_y() == CockpitFrame.GLASS_BOTTOM, "the window starts closed, the glass up")
			_check(not d.left_at_window(), "the left hand starts on the rim")
			cam.set_view(ChaseCamera.View.COCKPIT)
			Input.action_press("window")
			_go(Step.DOWN)
		Step.DOWN:
			if d.left_at_window():
				hand_at_control = true
				var gap: float = d.hand_position(-1).distance_to(_control_pos(frame))
				if gap > 0.08:
					_check(false, "the left hand holds the %s: %.3f m away" % [control, gap])
				if control == "switch":
					_check(absf(frame.window_switch.rotation_degrees.x - CockpitFrame.SWITCH_TILT_DEG) < 1e-3, "the rocker tilts while the window goes down (%.1f)" % frame.window_switch.rotation_degrees.x)
			if d.hand_position(1).distance_to(d.grip_position(1)) > GRIP_TOL:
				hand_right_off = true
			if waited == ticks(0.5):
				_check(cam.window_openness() > 0.1 and cam.window_openness() < 0.3, "after 0.5 s held the window is part way (%.2f)" % cam.window_openness())
				_check(d.left_at_window(), "the left hand is at the %s after 0.5 s" % control)
				if control == "crank":
					var turned := -frame.crank.rotation.x / TAU
					_check(absf(turned - cam.window_openness() * CockpitFrame.CRANK_TURNS) < 1e-3, "the crank has turned with the window (%.2f turns for %.2f)" % [turned, cam.window_openness()])
			if waited == ticks(PerspectiveAudio.WINDOW_DOWN_SECS + 0.3):
				_check(cam.window_openness() == 1.0, "held %.1f s the window is fully down (%.2f)" % [PerspectiveAudio.WINDOW_DOWN_SECS + 0.3, cam.window_openness()])
				_check(frame.glass_bottom_y() <= CockpitFrame.GLASS_BOTTOM - CockpitFrame.GLASS_TRAVEL + 1e-4, "the glass is all the way into the door")
				_check(hand_at_control, "the left hand went to the %s" % control)
				_check(not hand_right_off, "the right hand stayed on the rim")
				_check(d.left_at_window(), "the hand stays on the %s while the key is held at the stop" % control)
				Input.action_release("window")
				_go(Step.REST)
		Step.REST:
			if waited == ticks(1.0):
				_check(cam.window_openness() == 1.0, "released after a long hold the window stays down (%.2f)" % cam.window_openness())
				_check(not d.left_at_window() and d.hand_position(-1).distance_to(d.grip_position(-1)) <= GRIP_TOL, "the left hand is back on the rim 1 s after the window stopped")
				if control == "switch":
					_check(frame.window_switch.rotation_degrees.x == 0.0, "the rocker is level at rest")
				Input.action_press("window")
				_go(Step.TAP)
		Step.TAP:
			if waited == ticks(0.1):
				Input.action_release("window")   # a tap: shorter than WINDOW_TAP_SECS
			if waited == ticks(0.6):
				_check(cam.window_openness() < 1.0 and cam.window_openness() > 0.0, "a tap starts rolling the window up (%.2f)" % cam.window_openness())
				_check(d.left_at_window(), "the left hand is at the %s while it rolls up" % control)
				if control == "switch":
					_check(absf(frame.window_switch.rotation_degrees.x + CockpitFrame.SWITCH_TILT_DEG) < 1e-3, "the rocker tilts the other way rolling up (%.1f)" % frame.window_switch.rotation_degrees.x)
			if waited == ticks(PerspectiveAudio.WINDOW_UP_SECS + 1.0):
				_check(cam.window_openness() == 0.0, "after the tap the window is shut (%.2f)" % cam.window_openness())
				_check(frame.glass_bottom_y() == CockpitFrame.GLASS_BOTTOM, "the glass is back up")
				_check(not d.left_at_window() and d.hand_position(-1).distance_to(d.grip_position(-1)) <= GRIP_TOL, "the left hand is back on the rim after rolling up")
				_go(Step.DONE)
		Step.DONE:
			for line in trace:
				print(line)
			print("glass samples: %d; highest hand point %.1f deg below the eye (%s)" % [samples, min_below_eye, min_below_where])
			_check(min_below_eye >= DriverModel.HAND_TOP_MIN_DEG, "a hand rose to %.1f deg below the eye (%s), min %.0f" % [min_below_eye, min_below_where, DriverModel.HAND_TOP_MIN_DEG])
			_check(logger.errors.is_empty(), "engine errors: %s" % str(logger.errors.slice(0, 5)))
			return _end("")
	if tick > TIMEOUT_TICKS:
		return _end("timeout in step %s" % Step.keys()[step])
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
	print("cockpit_window: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
