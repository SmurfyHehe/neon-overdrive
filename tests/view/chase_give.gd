extends "res://tests/view/parked_cockpit.gd"

# Throttle and brake give in the chase view (Roy 1493, camera proposal step 4,
# 2026-10-13), real driving, no traffic:
# - the spring itself: a step to 0.5 m lands in the same place whether it is
#   run at 60, 120 or 144 frames a second (within 2 mm at 0.25, 0.5 and 1 s),
#   never overshoots, and is past 75% of the way in a quarter second
# - standing on the brake: no give (under 2 cm)
# - full throttle from rest: the car pulls away 0.2 to 0.5 m
# - throttle off: the give is back under 0.1 m within 1 s
# - hard braking: the camera closes in 0.2 to 0.5 m; stopped, back under
#   0.05 m within 1 s
# - Speed FOV widening off: a second launch to 20 m/s leaves the chase FOV
#   at its rest value (within 0.1 deg) the whole way
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/view/chase_give.gd

enum S { SPRING, PARKED, LAUNCH, COAST, BRAKE, STOPPED, FLAT_LAUNCH, DONE }
const GIVE := ChaseCamera.GIVE_M
var s := S.SPRING
var s_start := 0
var throttle := 0.0
var brake := 0.0
var peak := 0.0
var low := 0.0
var since := -1
var fov_dev := 0.0

func _init() -> void:
	name_ = "chase_give"
	park = false

func _drive(c: PlayerCar) -> void:
	c.throttle_input = throttle
	c.brake_input = brake
	c.handbrake_input = 0.0
	c.steering_input = 0.0

func _go(next: S, n: int) -> void:
	s = next
	s_start = n
	since = -1

## Runs the give spring from 0 toward GIVE for `secs` at `fps`.
static func _run_spring(fps: float, secs: float) -> Vector2:
	var xv := Vector2.ZERO
	var dt := 1.0 / fps
	var steps := int(round(secs * fps))
	var top := 0.0
	for i in steps:
		xv = ChaseCamera.spring(xv.x, xv.y, GIVE, ChaseCamera.GIVE_HALF_LIFE, dt)
		top = maxf(top, xv.x)
	return Vector2(xv.x, top)

func _step(n: int) -> bool:
	var t := n - s_start
	var hz := float(Engine.physics_ticks_per_second)
	match s:
		S.SPRING:
			for secs in [0.25, 0.5, 1.0]:
				var a := _run_spring(60.0, secs)
				var b := _run_spring(120.0, secs)
				var c := _run_spring(144.0, secs)
				print("spring at %.2f s: %.4f / %.4f / %.4f m (60 / 120 / 144 fps)" % [secs, a.x, b.x, c.x])
				_check(absf(a.x - b.x) < 0.002 and absf(a.x - c.x) < 0.002, "the spring is frame-rate independent at %.2f s (%.4f %.4f %.4f)" % [secs, a.x, b.x, c.x])
			var long := _run_spring(144.0, 3.0)
			_check(long.y <= GIVE + 0.0005, "the spring never overshoots (%.4f)" % long.y)
			var quarter := _run_spring(60.0, 0.25)
			_check(quarter.x > 0.75 * GIVE, "past 75%% of the way in a quarter second (%.3f m)" % quarter.x)
			cam.set_view(ChaseCamera.View.CHASE)
			brake = 1.0
			_go(S.PARKED, n)
		S.PARKED:
			if t > hz * 0.5:
				peak = maxf(peak, absf(cam.give))
				if absf(cam.give) > 0.02:
					print("parked tick %d: give %.3f, accel %.2f m/s^2, speed %.3f" % [t, cam.give, cam._accel, p.current_speed()])
			if t >= int(hz * 1.5):
				print("parked: give up to %.3f m" % peak)
				_check(peak < 0.02, "no give standing on the brake (%.3f m)" % peak)
				peak = 0.0
				brake = 0.0
				throttle = 1.0
				_go(S.LAUNCH, n)
		S.LAUNCH:
			peak = maxf(peak, cam.give)
			_check(cam.give <= GIVE + 0.005, "the give never passes %.1f m (%.3f)" % [GIVE, cam.give])
			if p.current_speed() > 22.0:
				print("launch: give peaked at %.3f m on the way to %.0f m/s" % [peak, p.current_speed()])
				_check(peak >= 0.2 and peak <= GIVE + 0.005, "full throttle lets the car pull away 0.2 to 0.5 m (%.3f)" % peak)
				throttle = 0.0
				_go(S.COAST, n)
			elif t > hz * 25.0:
				return _end("never got up to speed (%.1f m/s)" % p.current_speed())
		S.COAST:
			if absf(cam.give) < 0.1 and since < 0:
				since = t
				print("throttle off: give under 0.1 m after %.2f s" % (t / hz))
			if t >= int(hz * 1.0):
				_check(since >= 0, "the give is back under 0.1 m within 1 s of lifting (%.3f m)" % cam.give)
				brake = 1.0
				low = 0.0
				_go(S.BRAKE, n)
		S.BRAKE:
			low = minf(low, cam.give)
			_check(cam.give >= -GIVE - 0.005, "the close-in never passes %.1f m (%.3f)" % [GIVE, cam.give])
			if p.current_speed() < 0.3:
				print("braking: camera closed in %.3f m" % -low)
				_check(low <= -0.2, "hard braking closes the camera in 0.2 to 0.5 m (%.3f)" % low)
				_go(S.STOPPED, n)
			elif t > hz * 15.0:
				return _end("never stopped (%.1f m/s)" % p.current_speed())
		S.STOPPED:
			if absf(cam.give) < 0.05 and since < 0:
				since = t
				print("stopped: give under 0.05 m after %.2f s" % (t / hz))
			if t >= int(hz * 1.0):
				_check(since >= 0, "stopped, the give is back under 0.05 m within 1 s (%.3f m)" % cam.give)
				brake = 0.0
				throttle = 1.0
				AccessSettings.fov_widening = false
				_go(S.FLAT_LAUNCH, n)
		S.FLAT_LAUNCH:
			if t > 2:
				fov_dev = maxf(fov_dev, absf(cam.fov - ViewSettings.chase_fov))
			if p.current_speed() > 20.0:
				print("widening off: chase FOV within %.3f deg of %.0f up to %.0f m/s" % [fov_dev, ViewSettings.chase_fov, p.current_speed()])
				_check(fov_dev < 0.1, "Speed FOV widening off holds the chase FOV (%.3f deg off)" % fov_dev)
				AccessSettings.fov_widening = true
				throttle = 0.0
				return _end("")
			elif t > hz * 25.0:
				AccessSettings.fov_widening = true
				return _end("never got up to speed again (%.1f m/s)" % p.current_speed())
	return false
