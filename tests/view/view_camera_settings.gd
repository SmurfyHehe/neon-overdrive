extends "res://tests/view/parked_cockpit.gd"

# The View page as the camera sees it (camera proposal step 2, 2026-10-13).
# The car is parked and frozen, so every number is the camera's:
# - chase distance: Near 0.85x and Far 1.4x the Normal distance, Far 0.6 m
#   higher; the drawn camera really sits that far back (within 5 cm)
# - chase FOV: the chase view rests at the slider's value
# - hood FOV: applies in the hood view only; the cockpit keeps its own, the
#   chase view is untouched
# - camera shake 0: a full-strength hit leaves the chase camera exactly on its
#   unshaken anchor; at 1 it moves
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/view/view_camera_settings.gd

## Ticks to wait after a change. The FOV moves at most 0.5 deg per drawn frame
## (FOV_MAX_STEP_DEG), and headless several ticks can share one frame.
const SETTLE := 240
const EPS := 0.01

var phase := 0
var phase_start := 0
var normal_dist := 0.0
var normal_h := 0.0
var normal_cam_dist := 0.0
var shaken := 0.0

func _init() -> void:
	name_ = "view_camera_settings"

func _go(n: int) -> void:
	phase += 1
	phase_start = n

## Horizontal distance from the car to the drawn camera.
func _cam_dist() -> float:
	var d := cam.global_position - p.get_global_transform_interpolated().origin
	return Vector2(d.x, d.z).length()

func _step(n: int) -> bool:
	var t := n - phase_start
	match phase:
		0:
			ViewSettings.reset_view()
			cam.set_view(ChaseCamera.View.CHASE)
			cam.shake_enabled = false
			_go(n)
		1:
			if t < SETTLE:
				return false
			_check(absf(cam.fov - ViewSettings.CHASE_FOV_DEFAULT) < 0.1, "chase rests at FOV 58 (%.2f)" % cam.fov)
			normal_dist = cam.dist_now - cam.give
			normal_h = cam.height_now
			normal_cam_dist = _cam_dist()
			ViewSettings.set_chase_distance(2)
			_go(n)
		2:
			if t < SETTLE:
				return false
			print("Far: dist %.2f (Normal %.2f), height %.2f (Normal %.2f), drawn %.2f m back (Normal %.2f)" % [cam.dist_now, normal_dist, cam.height_now, normal_h, _cam_dist(), normal_cam_dist])
			_check(absf(cam.dist_now - cam.give - normal_dist * 1.4) < EPS, "Far is 1.4x the distance (%.2f vs %.2f)" % [cam.dist_now, normal_dist * 1.4])
			_check(absf(cam.height_now - (normal_h + 0.6)) < EPS, "Far is 0.6 m higher (%.2f vs %.2f)" % [cam.height_now, normal_h + 0.6])
			_check(absf(_cam_dist() - normal_cam_dist * 1.4) < 0.05 or cam.wall_hit, "the drawn camera sits 1.4x back (%.2f vs %.2f)" % [_cam_dist(), normal_cam_dist * 1.4])
			ViewSettings.set_chase_distance(0)
			_go(n)
		3:
			if t < SETTLE:
				return false
			_check(absf(cam.dist_now - cam.give - normal_dist * 0.85) < EPS and absf(cam.height_now - normal_h) < EPS, "Near is 0.85x at the same height (%.2f, %.2f)" % [cam.dist_now, cam.height_now])
			ViewSettings.set_chase_distance(1)
			ViewSettings.set_chase_fov(66.0)
			_go(n)
		4:
			if t < SETTLE:
				return false
			_check(absf(cam.fov - 66.0) < 0.1, "Chase FOV 66 shows in the chase view (%.2f)" % cam.fov)
			ViewSettings.set_hood_fov(80.0)
			ViewSettings.set_cockpit_fov(60.0)
			cam.set_view(ChaseCamera.View.HOOD)
			_go(n)
		5:
			if t < SETTLE:
				return false
			print("hood view fov %.2f (hood 80, cockpit 60)" % cam.fov)
			_check(absf(cam.fov - 80.0) < 0.1, "Hood FOV 80 shows in the hood view (%.2f)" % cam.fov)
			cam.set_view(ChaseCamera.View.COCKPIT)
			_go(n)
		6:
			if t < SETTLE:
				return false
			_check(absf(cam.fov - 60.0) < 0.1, "the cockpit keeps its own FOV 60 (%.2f)" % cam.fov)
			cam.set_view(ChaseCamera.View.CHASE)
			_go(n)
		7:
			if t < SETTLE:
				return false
			_check(absf(cam.fov - 66.0) < 0.1, "the chase view is untouched by the hood FOV (%.2f)" % cam.fov)
			cam.shake_enabled = true
			AccessSettings.set_shake_scale(0.0)
			_go(n)
		8:
			cam.trauma = 1.0
			if t < 10:
				return false
			var off := cam.global_position.distance_to(cam.anchor)
			var ang := (cam.aim - cam.anchor).normalized().angle_to(-cam.global_basis.z)
			print("shake 0 at full trauma: %.5f m, %.5f rad off the anchor" % [off, ang])
			_check(off < 1e-4 and ang < 1e-4, "Camera shake 0: no shake at a full hit (%.5f m, %.5f rad)" % [off, ang])
			AccessSettings.set_shake_scale(1.0)
			_go(n)
		9:
			cam.trauma = 1.0
			shaken = maxf(shaken, cam.global_position.distance_to(cam.anchor))
			if t < 20:
				return false
			print("shake 1 at full trauma: up to %.3f m off the anchor" % shaken)
			_check(shaken > 0.01, "Camera shake 100%%: a full hit shakes (%.3f m)" % shaken)
			ViewSettings.reset_view()
			return _end("")
	return false
