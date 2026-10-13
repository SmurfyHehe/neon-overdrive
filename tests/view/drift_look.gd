extends "res://tests/view/parked_cockpit.gd"

# Drift look and head sway (Roy 1492, #640, #641; camera proposal step 4,
# 2026-10-13), cockpit view, no traffic.
# - the drift_look rule itself: under 5 deg of slip it is the grip corner look;
#   at 30 deg of slip it is the travel direction, capped at 20 deg; a spin
#   (over 100 deg) fades it to 0; never past 20 deg at any slip
# - head sway on grip (#641), real driving: full lock at 18 m/s, a steady
#   circle. Once it has settled the sideways acceleration the head follows
#   agrees with yaw rate x speed (within 0.15 g, same side: nothing changes on
#   steady grip) and the head moves outward. Then 2 s of full throttle on
#   full lock; printed: the peak of the old reading (yaw rate x speed)
#   against the real force
# - a held slide, posed: the car frozen and given a velocity off its nose
#   (10 to 45 deg either side) while it turns the other way, the way a drift
#   does. The view settles on drift_look's value (within 0.2 deg), on the
#   side the car is going (from 12 deg of slip), where the old corner look
#   (yaw rate) pointed the other way (#640); the hood view gets half of it
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/view/drift_look.gd

enum S { RULE, ACCEL, CIRCLE, SPIN, POSE, DONE }
const POSES := [[10.0, 1], [25.0, 1], [45.0, 1], [10.0, -1], [25.0, -1], [45.0, -1]]   # slip deg, side (+1 travel to the left)
const POSE_SPEED := 15.0
const POSE_YAW := 0.8      # rad/s, turning away from the travel side
const POSE_TICKS := 90     # 1.5 s: the look eases at 4/s
var s := S.RULE
var s_start := 0
var throttle := 1.0
var steer := 0.0
var lat_new: Array[float] = []
var lat_old: Array[float] = []
var circle_frames := 0
var circle_agree := 0
var head_outward := 0
var spin_old := 0.0
var spin_new := 0.0
var pose_i := 0
var hood := false
var origin := Transform3D.IDENTITY

func _init() -> void:
	name_ = "drift_look"
	park = false

func _drive(c: PlayerCar) -> void:
	c.throttle_input = throttle
	c.brake_input = 0.0
	c.handbrake_input = 0.0
	c.steering_input = steer

func _go(next: S, n: int) -> void:
	s = next
	s_start = n

func _rule() -> void:
	var C := ChaseCamera
	_check(is_equal_approx(C.drift_look(-6.0, 3.0, 3.0), -6.0), "under 5 deg of slip it is the grip look")
	_check(is_equal_approx(C.drift_look(-6.0, 30.0, 30.0), 20.0), "at 30 deg of slip it is the travel side, capped at 20 (%.2f)" % C.drift_look(-6.0, 30.0, 30.0))
	_check(is_equal_approx(C.drift_look(6.0, -12.0, 30.0), -12.0), "under the cap it is the travel direction itself")
	_check(absf(C.drift_look(6.0, -150.0, 150.0)) < 0.001, "a spin fades it to 0")
	for slip in range(0, 181, 5):
		for sgn in [-1.0, 1.0]:
			var v := C.drift_look(6.0 * sgn, slip * -sgn, float(slip))
			_check(absf(v) <= C.DRIFT_LOOK_MAX_DEG + 0.001, "never past 20 deg (%.2f at slip %d)" % [v, slip])

## Averages of the last 0.25 s: (new sideways g, old yaw rate x speed g).
func _window(w: float, hz: float) -> Vector2:
	lat_new.append(cam.lat_accel / 9.81)
	lat_old.append(w * p.current_speed() / 9.81)
	var keep := int(hz * 0.25)
	while lat_new.size() > keep:
		lat_new.pop_front()
		lat_old.pop_front()
	var a := 0.0
	var b := 0.0
	for i in lat_new.size():
		a += lat_new[i]
		b += lat_old[i]
	return Vector2(a, b) / lat_new.size()

func _step(n: int) -> bool:
	var t := n - s_start
	var hz := float(Engine.physics_ticks_per_second)
	var w := p.angular_velocity.y
	match s:
		S.RULE:
			_rule()
			_go(S.ACCEL, n)
		S.ACCEL:
			if p.current_speed() > 18.0:
				steer = -1.0      # full lock right
				throttle = 0.5
				_go(S.CIRCLE, n)
			elif t > hz * 25.0:
				return _end("never got up to speed (%.1f m/s)" % p.current_speed())
		S.CIRCLE:
			var g := _window(w, hz)
			# judged once the circle has settled, 1 s in, to 1.5 s (before the wall).
			# While it builds up the two differ by design: yaw rate x speed misses
			# the slip angle still growing (it read 1.04 g against a real 0.70)
			if t > int(hz * 1.0) and absf(g.y) > 0.3 and cam.trauma <= 0.0:
				circle_frames += 1
				if absf(g.x - g.y) < 0.15 and signf(g.x) == signf(g.y):
					circle_agree += 1
				if signf(cam.head_offset.x) == signf(g.x):
					head_outward += 1
			if t >= int(hz * 1.5):
				print("grip circle: %d frames, sideways force agrees with yaw rate x speed in %d, head outward in %d (now %.2f g vs %.2f g)" % [circle_frames, circle_agree, head_outward, g.x, g.y])
				_check(circle_frames >= int(hz * 0.4), "a steady grip circle to judge (%d frames)" % circle_frames)
				_check(circle_agree >= 0.9 * circle_frames, "on grip the head follows the same g as before (%d of %d)" % [circle_agree, circle_frames])
				_check(head_outward >= 0.9 * circle_frames, "the head moves outward in the turn (%d of %d)" % [head_outward, circle_frames])
				throttle = 1.0
				_go(S.SPIN, n)
		S.SPIN:
			var g := _window(w, hz)
			if cam.trauma <= 0.0:
				spin_new = maxf(spin_new, absf(g.x))
				spin_old = maxf(spin_old, absf(g.y))
			if t >= int(hz * 2.0):
				print("full throttle on full lock (impact frames left out): yaw rate x speed reads up to %.2f g, the real sideways force %.2f g (head sway full at %.1f g)" % [spin_old, spin_new, ChaseCamera.HEAD_G_FULL])
				throttle = 0.0
				steer = 0.0
				p.freeze = true
				origin = p.global_transform
				_go(S.POSE, n)
		S.POSE:
			var slip: float = POSES[pose_i][0]
			var side: int = POSES[pose_i][1]
			p.global_transform = origin
			var dir := Vector3(0, 0, -1).rotated(Vector3.UP, deg_to_rad(slip * side))
			p.linear_velocity = origin.basis * dir * POSE_SPEED
			p.angular_velocity = Vector3(0.0, -POSE_YAW * side, 0.0)
			if t < POSE_TICKS:
				return false
			var grip := -signf(side) * ChaseCamera.CORNER_LOOK_MAX_DEG   # yaw rate well past full: the old look, away from travel
			var want := ChaseCamera.drift_look(grip, cam.travel_deg, cam.slip_deg) * (ChaseCamera.HOOD_STRENGTH if hood else 1.0)
			print("%s posed slide %.0f deg to the %s: travel read %.1f, look %.2f deg (want %.2f, the old look %.1f)" % ["hood" if hood else "cockpit", slip, "left" if side > 0 else "right", cam.travel_deg, cam.corner_yaw, want, grip * (ChaseCamera.HOOD_STRENGTH if hood else 1.0)])
			_check(absf(cam.travel_deg - slip * side) < 1.0, "the camera reads the travel direction (%.1f vs %.1f)" % [cam.travel_deg, slip * side])
			_check(absf(cam.corner_yaw - want) < 0.2, "the look settles on drift_look (%.2f vs %.2f)" % [cam.corner_yaw, want])
			if slip >= 12.0:
				_check(signf(cam.corner_yaw) == float(side), "a %.0f deg slide turns the view toward travel (%.2f)" % [slip, cam.corner_yaw])
			_check(absf(cam.corner_yaw) <= ChaseCamera.DRIFT_LOOK_MAX_DEG + 0.01, "never past 20 deg (%.2f)" % cam.corner_yaw)
			pose_i += 1
			if pose_i >= POSES.size():
				if hood:
					return _end("")
				hood = true
				pose_i = 0
				cam.set_view(ChaseCamera.View.HOOD)
			_go(S.POSE, n)
	return false
