extends "res://tests/view/parked_cockpit.gd"

# Camera upgrade C4 (2026-10-10): the view leans into a bend by itself.
# Real driving, cockpit view, no traffic:
# - straight cruise: no corner look (0 deg, under 0.2)
# - a hard right turn: the view turns right (corner_yaw negative), more than
#   1 degree and never past CORNER_LOOK_MAX_DEG (6), also at about 1 g
# - an arrow key held in the bend: the corner look is gone (0, under 0.3)
# - steering back to straight: the corner look returns to 0 within 1 s of the
#   car no longer turning
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/view/look_into_corner.gd

enum S { ACCEL, CRUISE, TURN, KEY, UNKEY, STRAIGHT, DONE }
var s := S.ACCEL
var s_start := 0
var throttle := 1.0
var steer := 0.0
var peak := 0.0
var peak_g := 0.0
var straight_max := 0.0
var still_since := -1

func _init() -> void:
	name_ = "look_into_corner"
	park = false

func _drive(c: PlayerCar) -> void:
	c.throttle_input = throttle
	c.brake_input = 0.0
	c.handbrake_input = 0.0
	c.steering_input = steer

func _go(next: S, n: int) -> void:
	s = next
	s_start = n

func _step(n: int) -> bool:
	var t := n - s_start
	var w := p.angular_velocity.y
	peak = maxf(peak, absf(cam.corner_yaw))
	_check(absf(cam.corner_yaw) <= ChaseCamera.CORNER_LOOK_MAX_DEG + 0.01, "corner look never past the cap (%.2f)" % cam.corner_yaw)
	match s:
		S.ACCEL:
			if p.current_speed() > 25.0:
				throttle = 0.35
				_go(S.CRUISE, n)
			elif t > 60 * 20:
				return _end("never got up to speed (%.1f m/s)" % p.current_speed())
		S.CRUISE:
			if t > 60 * 2:
				straight_max = maxf(straight_max, absf(cam.corner_yaw))
			if t == 60 * 5:
				print("straight: speed %.0f km/h, corner look max %.3f deg" % [p.current_speed() * 3.6, straight_max])
				_check(straight_max < 0.2, "no corner look on a straight (%.3f deg)" % straight_max)
				peak = 0.0
				steer = -0.6   # right, short of a spin (as in cockpit_head_motion)
				_go(S.TURN, n)
		S.TURN:
			peak_g = maxf(peak_g, absf(w) * p.current_speed() / 9.81)
			if t == 60 * 3:
				var sign_ok := cam.corner_yaw < 0.0   # right turn: view turns right (- = right)
				print("right turn: %.1f m/s, yaw rate %.2f rad/s, peak %.2f g, corner look %.2f deg" % [p.current_speed(), w, peak_g, cam.corner_yaw])
				_check(sign_ok, "a right turn looks right (%.2f)" % cam.corner_yaw)
				_check(absf(cam.corner_yaw) > 1.0, "a hard turn turns the view more than 1 deg (%.2f)" % cam.corner_yaw)
				Input.action_press("look_left")
				_go(S.KEY, n)
		S.KEY:
			if t == 40:
				print("arrow key held in the bend: corner look %.3f deg" % cam.corner_yaw)
				_check(absf(cam.corner_yaw) < 0.3, "no corner look while an arrow key is held (%.3f)" % cam.corner_yaw)
				Input.action_release("look_left")
				steer = 0.0
				throttle = 0.0
				_go(S.STRAIGHT, n)
		S.STRAIGHT:
			# time from the car no longer turning (yaw rate under the dead zone) to the view being straight
			if absf(w) < ChaseCamera.CORNER_RATE_DEAD:
				if still_since < 0:
					still_since = n
			else:
				still_since = -1
			if still_since >= 0 and n - still_since >= 60:
				print("1 s after the turn ended: corner look %.3f deg" % cam.corner_yaw)
				_check(absf(cam.corner_yaw) < 0.3, "the corner look is back to 0 within 1 s of the bend ending (%.3f)" % cam.corner_yaw)
				return _end("")
			if t > 60 * 15:
				return _end("the car never stopped turning (yaw rate %.2f)" % w)
	return false
