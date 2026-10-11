extends "res://tests/view/parked_cockpit.gd"

# Camera upgrade: tap vs hold on the look keys (2026-10-10). A short tap of
# Left/Right (0.15 s) sends the head to the door mirror and stops there
# (LOOK_MIRROR_YAW, 35 degrees), with that mirror focused; holding the key
# keeps turning to LOOK_YAW_MAX (110). Release eases back straight ahead.
# Frame-clock test (the hold time is measured in drawn-frame time): run with
# --fixed-fps 60.
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --audio-driver Dummy --path . -s res://tests/view/look_tap_hold.gd

const TAP_TICKS := 9      # 0.15 s at 60 Hz
const AFTER_TAP := 40     # ticks after release: the head has settled on the mirror (latch is 0.9 s)
const HOLD_TICKS := 60    # 1 s

enum S { TAP_LEFT, TAP_LEFT_CHECK, BACK1, TAP_RIGHT, TAP_RIGHT_CHECK, BACK2, HOLD_LEFT, HOLD_CHECK, BACK3, DONE }
var s := S.TAP_LEFT
var s_start := 0

func _init() -> void:
	name_ = "look_tap_hold"

func _go(next: S, n: int) -> void:
	s = next
	s_start = n

func _step(n: int) -> bool:
	if n == 0:
		_go(S.TAP_LEFT, n)
		Input.action_press("look_left")
		return false
	var t := n - s_start
	match s:
		S.TAP_LEFT:
			if t == TAP_TICKS:
				Input.action_release("look_left")
				_go(S.TAP_LEFT_CHECK, n)
		S.TAP_LEFT_CHECK:
			if t == AFTER_TAP:
				print("tap left (0.15 s): yaw %.1f, focus %d" % [cam.look_yaw, cam._look_focus])
				_check(absf(cam.look_yaw - ChaseCamera.LOOK_MIRROR_YAW) < 1.5, "a 0.15 s tap left stops at the door mirror, 35 deg (%.1f)" % cam.look_yaw)
				_check(cam._look_focus == -1, "and focuses the left door mirror (%d)" % cam._look_focus)
				_go(S.BACK1, n)
		S.BACK1:
			if t == 120:   # the latch (0.9 s) has run out and the head has eased home
				_check(absf(cam.look_yaw) < 1.0, "the head comes back after a tap (%.1f)" % cam.look_yaw)
				_go(S.TAP_RIGHT, n)
				Input.action_press("look_right")
		S.TAP_RIGHT:
			if t == TAP_TICKS:
				Input.action_release("look_right")
				_go(S.TAP_RIGHT_CHECK, n)
		S.TAP_RIGHT_CHECK:
			if t == AFTER_TAP:
				print("tap right (0.15 s): yaw %.1f" % cam.look_yaw)
				_check(absf(cam.look_yaw + ChaseCamera.LOOK_MIRROR_YAW) < 1.5, "a 0.15 s tap right stops at the door mirror, -35 deg (%.1f)" % cam.look_yaw)
				_go(S.BACK2, n)
		S.BACK2:
			if t == 120:
				_check(absf(cam.look_yaw) < 1.0, "the head comes back (%.1f)" % cam.look_yaw)
				_go(S.HOLD_LEFT, n)
				Input.action_press("look_left")
		S.HOLD_LEFT:
			if t == HOLD_TICKS:
				print("hold left (1 s): yaw %.1f" % cam.look_yaw)
				_check(cam.look_yaw >= ChaseCamera.LOOK_YAW_MAX - 2.0, "holding Left for 1 s reaches 110 deg (%.1f)" % cam.look_yaw)
				_check(cam.look_yaw <= ChaseCamera.LOOK_YAW_MAX + 0.01, "and not past it (%.1f)" % cam.look_yaw)
				Input.action_release("look_left")
				_go(S.BACK3, n)
		S.BACK3:
			if t == 60:
				_check(absf(cam.look_yaw) < 1.0, "released after a hold, the head is straight again (%.1f)" % cam.look_yaw)
				return _end("")
	return false
