extends "res://tests/view/parked_cockpit.gd"

# Camera upgrade C2 (2026-10-10): the horizon stays steadier than the cabin.
# The player car is parked and posed with a body roll and pitch (a steady
# 0.8 g left turn rolls the body a few degrees); the cockpit camera's roll
# against the world must be 50% of the body roll (ChaseCamera.HORIZON_ROLL_LEVEL)
# and its pitch 70% of the body pitch (HORIZON_PITCH_LEVEL = 0.3 levelled), both
# within 0.3 degrees. A big tilt (a rollover) is NOT levelled: shown whole.
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/view/cockpit_horizon.gd

const TOL_DEG := 0.3
## [roll, pitch] poses, degrees: a steady 0.8 g left turn is about 3-6 deg of roll.
const POSES := [[6.0, 0.0], [-6.0, 0.0], [3.0, 0.0], [0.0, 5.0], [0.0, -5.0], [5.0, -4.0]]

var idx := 0

func _init() -> void:
	name_ = "cockpit_horizon"

func _step(n: int) -> bool:
	# the head's sway from the car's last moments settles first (rate 6/s)
	const WARMUP := 60
	if n == WARMUP:
		pose(POSES[0][0], POSES[0][1])
		return false
	if n < WARMUP + SETTLE_TICKS or (n - WARMUP) % SETTLE_TICKS != 0:
		return false
	if idx < POSES.size():
		var body := tilt_of(p.global_basis)     # (pitch, roll) as the sim has it
		var seen := tilt_of(cam.global_basis)
		var want_pitch := body.x * (1.0 - ChaseCamera.HORIZON_PITCH_LEVEL)
		var want_roll := body.y * (1.0 - ChaseCamera.HORIZON_ROLL_LEVEL)
		print("pose %s: body pitch %.2f roll %.2f -> camera pitch %.2f roll %.2f" % [POSES[idx], body.x, body.y, seen.x, seen.y])
		_check(absf(seen.y - want_roll) < TOL_DEG, "pose %s: camera roll %.2f is 50%% of body roll %.2f (want %.2f)" % [POSES[idx], seen.y, body.y, want_roll])
		_check(absf(seen.x - want_pitch) < TOL_DEG, "pose %s: camera pitch %.2f is 70%% of body pitch %.2f (want %.2f)" % [POSES[idx], seen.x, body.x, want_pitch])
		idx += 1
		if idx < POSES.size():
			pose(POSES[idx][0], POSES[idx][1])
			return false
		pose(80.0, 0.0)   # on its side: shown whole, not halved
		return false
	var body2 := tilt_of(p.global_basis)
	var seen2 := tilt_of(cam.global_basis)
	print("on its side: body roll %.1f -> camera roll %.1f" % [body2.y, seen2.y])
	_check(absf(seen2.y - body2.y) < 1.0, "a rollover is not levelled (body %.1f, camera %.1f)" % [body2.y, seen2.y])
	return _end("")
