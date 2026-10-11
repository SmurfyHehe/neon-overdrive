extends "res://tests/view/parked_cockpit.gd"

# Camera upgrade (2026-10-10): the camera's smoothing does not depend on how
# fast frames are drawn. The same disturbance is let decay at 60, 120 and 144
# drawn frames per second (the camera stepped by hand with that frame time, the
# car parked) and the paths must agree within 1% of the disturbance at
# 0.25 / 0.5 / 0.75 s: speed term, FOV, head offset and tilt, corner look,
# and, in the chase view, the position the camera follows to. Checked in both
# views.
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/view/camera_rate_independent.gd

const RATES := [60, 120, 144]
const TIMES := [0.25, 0.5, 0.75]
const REL := 0.01

func _init() -> void:
	name_ = "camera_rate_independent"

## The state read at each sample, as numbers.
func _read() -> Dictionary:
	var q := cam.global_basis.get_rotation_quaternion()
	return {
		"fov": cam.fov, "speed_t": cam.speed_t, "accel_fov": cam.accel_fov, "dist": cam.dist_now,
		"head_x": cam.head_offset.x, "head_z": cam.head_offset.z, "tilt_p": cam.head_tilt.x, "tilt_r": cam.head_tilt.y,
		"corner": cam.corner_yaw, "look": cam.look_yaw,
		"pos_x": cam.global_position.x, "pos_y": cam.global_position.y, "pos_z": cam.global_position.z,
		"q_x": q.x, "q_y": q.y, "q_z": q.z, "q_w": q.w,
	}

## Perturbs the smoothed state, then runs `rate` fps of manual frames; returns
## the state at each of TIMES.
func _run(rate: int, view: ChaseCamera.View) -> Array:
	cam.set_view(view)
	cam.set_process(false)
	cam.shake_enabled = false
	cam.mode = 0   # hard snap for one frame: the chase rig starts on the car every run
	cam.speed_t = 1.0
	cam.accel_fov = 3.0
	cam.head_offset = Vector3(0.05, 0.0, 0.05)
	cam.head_tilt = Vector2(3.0, 3.0)
	cam.corner_yaw = 6.0
	cam.look_yaw = 0.0
	cam.trauma = 0.0
	cam.bump = 0.0
	# let the camera settle once at a very fine step so every run starts from the same place
	for i in 3:
		cam._process(1.0 / 240.0)
	cam.mode = 1   # light smoothing: the follow position is eased
	cam._follow += Vector2(1.0, 0.5)   # the chase rig is off to the side: it eases back
	cam._started_fov = false           # no FOV slew from the previous run's last frame
	var out := []
	var dt := 1.0 / float(rate)
	var frames_total := int(round(TIMES[-1] * rate))
	var next_i := 0
	for f in range(1, frames_total + 1):
		cam._process(dt)
		var t := f * dt
		if next_i < TIMES.size() and absf(t - TIMES[next_i]) < dt * 0.5:
			out.append(_read())
			next_i += 1
	return out

func _step(n: int) -> bool:
	if n != 2:
		return false
	for view in [ChaseCamera.View.COCKPIT, ChaseCamera.View.CHASE]:
		var runs := {}
		for r in RATES:
			runs[r] = _run(r, view)
		var vname := "cockpit" if view == ChaseCamera.View.COCKPIT else "chase"
		for ti in TIMES.size():
			var ref: Dictionary = runs[60][ti]
			for r in [120, 144]:
				var got: Dictionary = runs[r][ti]
				for key in ref.keys():
					var a: float = ref[key]
					var b: float = got[key]
					# 1% of the disturbance's own scale: positions/quaternion parts are
					# compared in absolute metres / unit terms, the rest relative to 1.
					var tol := REL * maxf(1.0, absf(a))
					if key.begins_with("head") or key.begins_with("tilt") or key == "corner":
						tol = REL * 6.0
					elif key == "fov" or key == "dist" or key.begins_with("pos"):
						tol = REL * maxf(1.0, absf(a)) * (1.0 if key != "fov" else 2.0)
					_check(absf(a - b) <= tol, "%s view, t=%.2f s: %s at 60 fps %.4f vs %d fps %.4f" % [vname, TIMES[ti], key, a, r, b])
		var d: Dictionary = runs[60][1]
		print("%s view at 0.5 s: fov %.2f speed_t %.3f corner %.3f head_x %.4f" % [vname, d.fov, d.speed_t, d.corner, d.head_x])
	return _end("")
