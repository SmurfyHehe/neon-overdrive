extends "res://tests/view/parked_cockpit.gd"

# Look around outside (2026-10-11): in the chase view the arrow keys orbit the
# camera round the car. Hold Left/Right: 100 degrees to that side of the CAR
# (also while reversing, when the rig sits in front); tap: a 35 degree glance
# held 0.9 s; release eases back at 8/s without crossing 0; Up lifts the
# camera 2.5 m, Down drops it to 0.6 m above the road; B wins and the orbit
# eases to 0 under the look-back swing; F clears it; a pause with a key
# touched does not leave a latch behind; and the path does not depend on how
# fast frames are drawn (60 / 120 / 144 fps).
# Frame-clock test (hold times are drawn-frame time): run with --fixed-fps 60.
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --audio-driver Dummy --path . -s res://tests/view/chase_orbit.gd

const CRUISE := 27.0         # m/s, ~97 km/h (the starter tops out near here)
const SECOND := 60           # ticks
const RATES := [60, 120, 144]
const SAMPLES := [0.5, 0.75, 1.0, 1.25, 1.5]   # s; the keys are released at 1.0

enum S { ACCEL, HOLD_LEFT, RELEASE, TAP, TAP_BACK, UP, DOWN, SETTLE, B_ALONE, B_ALONE_BACK, B_LEFT, B_RELEASE,
		REVERSE, F_HOLD, F_CHECK, F_BACK, PAUSE_TAP, PAUSE_WAIT, PAUSE_CHECK, RATES }
var s := S.ACCEL
var s_start := 0
var at_speed := 0
var last_frame := -1
var frame_n := 0
var base_y := 0.0
var peak := 0.0
var lowest := 0.0
var look_back_pose := Transform3D.IDENTITY

func _init() -> void:
	name_ = "chase_orbit"
	park = false

func _initialize() -> void:
	OS.set_environment("NEON_CURVES", "0")   # a straight road: the checks are about the orbit, not the bend
	OS.set_environment("NEON_HILLS", "0")
	super._initialize()

## Cruise at CRUISE m/s, steering straight.
func _drive(c: PlayerCar) -> void:
	c.steering_input = 0.0
	c.handbrake_input = 0.0
	var err := CRUISE - c.current_speed()
	c.throttle_input = clampf(err * 0.3, 0.0, 1.0)
	c.brake_input = clampf(-err * 0.3, 0.0, 1.0)

func _parked(c: PlayerCar) -> void:
	c.throttle_input = 0.0
	c.brake_input = 0.0
	c.handbrake_input = 0.0
	c.steering_input = 0.0

func _go(next: S, n: int) -> void:
	s = next
	s_start = n

## The camera's place in the car's own frame: x < 0 is the car's left side.
func _rel() -> Vector3:
	return p.global_transform.affine_inverse() * cam.global_position

func _above_road() -> float:
	return RoadFrame.unroll(cam.global_position).y

func _step(tick_n: int) -> bool:
	# Everything below is counted in DRAWN frames (the project ticks physics at
	# 120 Hz, two ticks to a frame at --fixed-fps 60).
	var fr := Engine.get_process_frames()
	if fr == last_frame:
		return false
	last_frame = fr
	frame_n += 1
	var n := frame_n
	var t := n - s_start
	if n == 1:
		root.size = Vector2i(1280, 720)   # headless defaults to 64x64
		cam.set_view(ChaseCamera.View.CHASE)
		cam.shake_enabled = false
	if s != S.ACCEL and s != S.RATES and p.freeze:
		p.linear_velocity = Vector3.ZERO
	match s:
		S.ACCEL:
			p.driver = _drive
			# at cruise speed for 1.5 s, so the dolly and the squat have settled
			at_speed = at_speed + 1 if (n > 30 and absf(p.current_speed() - CRUISE) < 1.5) else 0
			if n > SECOND * 40:
				return _end("never reached cruise speed (%.1f m/s)" % p.current_speed())
			if at_speed >= 90:
				base_y = cam.global_position.y
				_check(absf(cam.orbit_yaw) < 0.01 and absf(cam.orbit_lift) < 0.01, "no orbit before any key (%.2f, %.2f)" % [cam.orbit_yaw, cam.orbit_lift])
				Input.action_press("look_left")
				_go(S.HOLD_LEFT, n)
		S.HOLD_LEFT:
			if t == SECOND:
				var rel := _rel()
				var centre := _body_centre()
				var scr := cam.unproject_position(centre)
				var size := Vector2(root.size)
				var off := (scr - size * 0.5) / size
				print("100 km/h, hold Left 1 s: orbit %.1f deg, camera in car frame %s, car centre %.1f%% / %.1f%% off screen centre (body centre %.2f m above the road, origin %.2f), %.1f m/s, dist %.2f" % [cam.orbit_yaw, rel, off.x * 100.0, off.y * 100.0, RoadFrame.unroll(centre).y, RoadFrame.unroll(p.global_position).y, p.current_speed(), cam.dist_now])
				_check(absf(cam.orbit_yaw - 100.0) <= 3.0, "hold Left: orbit 100 +- 3 (%.1f)" % cam.orbit_yaw)
				_check(rel.x < -0.8 * rel.length(), "the camera is on the car's left flank (%s)" % rel)
				var flat := Vector2(rel.x, rel.z).length()
				_check(absf(flat - cam.dist_now) < 0.1, "at the usual chase distance (%.2f vs %.2f)" % [flat, cam.dist_now])
				_check(absf(off.x) <= 0.05 and absf(off.y) <= 0.05, "the car sits mid-screen side-on (%.1f%%, %.1f%%)" % [off.x * 100.0, off.y * 100.0])
				_check(p.current_speed() > 25.0, "still at speed (%.1f)" % p.current_speed())
				Input.action_release("look_left")
				lowest = cam.orbit_yaw
				_go(S.RELEASE, n)
		S.RELEASE:
			lowest = minf(lowest, cam.orbit_yaw)
			if t == 36:   # 0.6 s
				print("release after full swing: %.2f deg at 0.6 s, lowest %.2f" % [cam.orbit_yaw, lowest])
				_check(absf(cam.orbit_yaw) < 2.0, "release: under 2 deg within 0.6 s (%.2f)" % cam.orbit_yaw)
				_check(lowest > -0.01, "and it never crosses past 0 (%.3f)" % lowest)
				Input.action_press("look_left")
				peak = 0.0
				_go(S.TAP, n)
		S.TAP:
			peak = maxf(peak, cam.orbit_yaw)
			if t == 9:   # 0.15 s
				Input.action_release("look_left")
				_go(S.TAP_BACK, n)
		S.TAP_BACK:
			peak = maxf(peak, cam.orbit_yaw)
			if t == 75:   # 1.4 s after the press
				print("tap 0.15 s: peak %.1f deg, %.2f deg at 1.4 s" % [peak, cam.orbit_yaw])
				_check(absf(peak - 35.0) <= 3.0, "tap: peak 35 +- 3 (%.1f)" % peak)
				# The glance is kept 0.9 s after release, then eases back at 8/s, so
				# 0.35 s later it is 35 * e^-2.8 = 2.1 deg.
				_check(cam.orbit_yaw < 2.5, "tap: nearly home by 1.4 s (%.2f)" % cam.orbit_yaw)
			if t == 81:   # 1.5 s
				_check(cam.orbit_yaw < 2.0, "tap: under 2 deg by 1.5 s (%.2f)" % cam.orbit_yaw)
				Input.action_press("look_up")
				_go(S.UP, n)
		S.UP:
			if t == SECOND:
				var up := cam.global_position.y - base_y
				print("Up 1 s: camera %.2f m above normal height, lift %.2f" % [up, cam.orbit_lift])
				_check(absf(up - 2.5) <= 0.1, "Up: 2.5 +- 0.1 m above normal height (%.2f)" % up)
				Input.action_release("look_up")
				Input.action_press("look_down")
				_go(S.DOWN, n)
		S.DOWN:
			if t == SECOND:
				var above := _above_road()
				print("Down 1 s: camera %.2f m above the road" % above)
				_check(absf(above - 0.6) <= 0.1, "Down: 0.6 +- 0.1 m above the road (%.2f)" % above)
				Input.action_release("look_down")
				_go(S.SETTLE, n)
		S.SETTLE:
			if t == SECOND:
				_check(absf(cam.global_position.y - base_y) < 0.1, "released, the height is back (%.2f)" % (cam.global_position.y - base_y))
				# park the car for the pose comparisons that follow
				p.driver = _parked
				p.freeze = true
				p.linear_velocity = Vector3.ZERO
				p.angular_velocity = Vector3.ZERO
				cam.mode = 0
				Input.action_press("look_back")
				_go(S.B_ALONE, n)
		S.B_ALONE:
			if t == 120:
				look_back_pose = cam.global_transform
				Input.action_release("look_back")
				_go(S.B_ALONE_BACK, n)
		S.B_ALONE_BACK:
			if t == SECOND:
				Input.action_press("look_back")
				Input.action_press("look_left")
				_go(S.B_LEFT, n)
		S.B_LEFT:
			if t == 120:
				var cur := cam.global_transform
				var ang := rad_to_deg(look_back_pose.basis.get_rotation_quaternion().angle_to(cur.basis.get_rotation_quaternion()))
				var dist := look_back_pose.origin.distance_to(cur.origin)
				print("B + Left: %.2f deg and %.3f m from plain look-back, orbit %.2f" % [ang, dist, cam.orbit_yaw])
				_check(ang <= 1.0, "B + Left: camera within 1 deg of plain look-back (%.2f)" % ang)
				_check(dist < 0.1, "and in the same place (%.3f m)" % dist)
				Input.action_release("look_back")   # Left still down: the orbit carries on
				_go(S.B_RELEASE, n)
		S.B_RELEASE:
			if t == SECOND:
				_check(absf(cam.orbit_yaw - 100.0) <= 3.0, "B released, Left still down: the orbit carries on (%.1f)" % cam.orbit_yaw)
				Input.action_release("look_left")
				_go(S.REVERSE, n)
		S.REVERSE:
			if t == 1:
				p.current_gear = -1
				Input.action_press("look_left")
			if t == SECOND + 30:   # the rig has swung round to the front
				var rel := _rel()
				print("reverse, hold Left: orbit %.1f, camera in car frame %s" % [cam.orbit_yaw, rel])
				_check(p.gear == -1, "the car is in reverse (%d)" % p.gear)
				_check(absf(cam.orbit_yaw - 100.0) <= 3.0, "reverse: orbit 100 +- 3 (%.1f)" % cam.orbit_yaw)
				_check(rel.x < -0.8 * rel.length(), "reverse: the camera is on the car's left flank (%s)" % rel)
				Input.action_release("look_left")
				p.current_gear = 1
				_go(S.F_HOLD, n)
		S.F_HOLD:
			if t == 1:
				Input.action_press("look_left")
			if t == SECOND + 1:
				_check(cam.orbit_yaw > 90.0, "orbiting before F (%.1f)" % cam.orbit_yaw)
				Input.action_press("camera_view")
				_go(S.F_CHECK, n)
		S.F_CHECK:
			if t == 2:
				print("F during an orbit: orbit %.2f, view %s" % [cam.orbit_yaw, cam.view])
				_check(cam.view == ChaseCamera.View.COCKPIT, "F switches view")
				_check(cam.orbit_yaw == 0.0 and cam.orbit_lift == 0.0, "F: orbit is 0 next frame (%.2f)" % cam.orbit_yaw)
				Input.action_release("camera_view")
				Input.action_release("look_left")
				_go(S.F_BACK, n)
		S.F_BACK:
			if t == 20:
				Input.action_press("camera_view")
			if t == 24:
				_check(cam.view == ChaseCamera.View.HOOD, "F again: the hood view")
				Input.action_release("camera_view")
			if t == 28:
				Input.action_press("camera_view")
			if t == 32:
				_check(cam.view == ChaseCamera.View.CHASE, "F once more: back in the chase view")
				_check(absf(cam.orbit_yaw) < 0.01, "and straight behind the car (%.2f)" % cam.orbit_yaw)
				Input.action_release("camera_view")
				_go(S.PAUSE_TAP, n)
		S.PAUSE_TAP:
			if t == 10:
				Input.action_press("look_left")
			if t == 15:   # 5 frames: well under a tap
				cam.get_tree().paused = true
				Input.action_release("look_left")
				_go(S.PAUSE_WAIT, n)
		S.PAUSE_WAIT:
			if t == 10:
				print("paused: camera can_process %s, orbit %.1f" % [cam.can_process(), cam.orbit_yaw])
				cam.get_tree().paused = false
				peak = cam.orbit_yaw
				_go(S.PAUSE_CHECK, n)
		S.PAUSE_CHECK:
			peak = maxf(peak, cam.orbit_yaw)
			if t == 40:
				print("unpaused, key released meanwhile: highest %.1f deg since, %.2f now" % [peak, cam.orbit_yaw])
				_check(cam.orbit_yaw < 2.0, "unpaused: the orbit eases to 0 (%.2f)" % cam.orbit_yaw)
				_check(peak < 45.0 and cam.orbit_yaw < peak or peak < 2.0, "and no glance was latched (%.1f)" % peak)
				_go(S.RATES, n)
		S.RATES:
			_rates()
			return _end("")
	return false

## The same key sequence at 60, 120 and 144 drawn fps (the camera stepped by hand,
## the car parked): the orbit, the lift and the camera's place agree.
func _rates() -> void:
	cam.set_process(false)
	var runs := {}
	for r in RATES:
		runs[r] = _run_rate(r)
	for i in SAMPLES.size():
		var ref: Dictionary = runs[60][i]
		for r in [120, 144]:
			var got: Dictionary = runs[r][i]
			_check(absf(ref.yaw - got.yaw) <= 1.0, "t=%.2f s: orbit %.3f at 60 fps vs %.3f at %d fps" % [SAMPLES[i], ref.yaw, got.yaw, r])
			_check(absf(ref.lift - got.lift) <= 0.01, "t=%.2f s: lift %.3f at 60 fps vs %.3f at %d fps" % [SAMPLES[i], ref.lift, got.lift, r])
			_check(ref.pos.distance_to(got.pos) <= 0.08, "t=%.2f s: camera %s at 60 fps vs %s at %d fps" % [SAMPLES[i], ref.pos, got.pos, r])
	var d: Dictionary = runs[60][2]
	var e: Dictionary = runs[144][2]
	print("1.0 s: orbit %.2f / %.2f deg, lift %.3f / %.3f at 60 / 144 fps" % [d.yaw, e.yaw, d.lift, e.lift])
	cam.set_process(true)

func _run_rate(rate: int) -> Array:
	Input.action_release("look_left")
	Input.action_release("look_up")
	cam.reset_orbit()
	cam.look_back = false
	cam.mode = 0
	cam._process(1.0 / 240.0)
	Input.action_press("look_left")
	Input.action_press("look_up")
	var out := []
	var dt := 1.0 / float(rate)
	var next_i := 0
	var frames := int(round(SAMPLES[-1] * rate))
	for f in range(1, frames + 1):
		var t := f * dt
		if f == int(round(1.0 * rate)) + 1:
			Input.action_release("look_left")
			Input.action_release("look_up")
		cam._process(dt)
		if next_i < SAMPLES.size() and absf(t - SAMPLES[next_i]) < dt * 0.5:
			out.append({"yaw": cam.orbit_yaw, "lift": cam.orbit_lift, "pos": cam.global_position})
			next_i += 1
	Input.action_release("look_left")
	Input.action_release("look_up")
	return out

## The middle of the car's body: the union of its visible parts, in the world.
func _body_centre() -> Vector3:
	var box := AABB()
	var first := true
	for n in p.chassis_visual.find_children("*", "VisualInstance3D", true, false):
		var vi := n as VisualInstance3D
		if not vi.is_visible_in_tree():
			continue
		var b := vi.global_transform * vi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box.get_center()
