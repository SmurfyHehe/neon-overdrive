extends "res://tests/view/parked_cockpit.gd"

# Camera upgrade (2026-10-10): the FOV never changes by more than
# ChaseCamera.FOV_MAX_STEP_DEG (0.5 deg) in one drawn frame. A real run that
# provokes it: a standing start at full throttle, a hard stop, switching
# between the chase and cockpit views (their FOVs differ by ~10 deg) and
# dragging the cockpit FOV setting. The FOV is sampled once per drawn frame
# (before the camera's own _process runs, so each sample is the previous
# frame's), and the largest difference between consecutive samples is checked.
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/view/fov_step_limit.gd

enum S { LAUNCH, STOP, VIEWS, SLIDER, DONE }
var s := S.LAUNCH
var s_start := 0
var throttle := 1.0
var brake := 0.0
var last_fov := -1.0
var max_step := 0.0
var step_at := ""
var frames := 0
var in_n := 0

func _init() -> void:
	name_ = "fov_step_limit"
	park = false

func _drive(c: PlayerCar) -> void:
	c.throttle_input = throttle
	c.brake_input = brake
	c.handbrake_input = 0.0
	c.steering_input = 0.0

## Once per drawn frame, before the camera's own _process.
func _process(_delta: float) -> bool:
	if cam == null or boot_tick < 0:
		return false
	if last_fov >= 0.0:
		var d := absf(cam.fov - last_fov)
		if d > max_step:
			max_step = d
			step_at = "%s tick %d" % [S.keys()[s], in_n]
		frames += 1
	last_fov = cam.fov
	return false

func _go(next: S, n: int) -> void:
	s = next
	s_start = n

func _step(n: int) -> bool:
	in_n = n
	var t := n - s_start
	match s:
		S.LAUNCH:
			if t == 60 * 5:
				throttle = 0.0
				brake = 1.0
				_go(S.STOP, n)
		S.STOP:
			if t == 60 * 2:
				_go(S.VIEWS, n)
		S.VIEWS:
			if t % 20 == 0 and t < 200:
				cam.set_view(ChaseCamera.View.CHASE if (t / 20) % 2 == 0 else ChaseCamera.View.COCKPIT)
			if t == 200:
				cam.set_view(ChaseCamera.View.COCKPIT)
				_go(S.SLIDER, n)
		S.SLIDER:
			if t == 0:
				ViewSettings.set_cockpit_fov(90.0)
			if t == 40:
				ViewSettings.set_cockpit_fov(50.0)
			if t == 100:
				print("%d frames sampled; largest FOV change in one drawn frame %.3f deg (%s)" % [frames, max_step, step_at])
				_check(frames > 200, "enough frames were sampled (%d)" % frames)
				_check(max_step <= ChaseCamera.FOV_MAX_STEP_DEG + 0.001, "FOV changed %.3f deg in one frame (%s)" % [max_step, step_at])
				ViewSettings.set_cockpit_fov(ViewSettings.COCKPIT_FOV_DEFAULT)
				return _end("")
	return false
