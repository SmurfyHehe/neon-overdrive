extends SceneTree

# Driving-feel pass, motion (2026-10-08): near-miss whoosh + camera nudge,
# camera dip on landings. Headless and silent; asserts on counters and the
# camera's spring state.
#
# Near misses use stand-in traffic (plain nodes with the fields NearMiss reads)
# so the gaps and speeds are exact: the player is held at a speed and a
# parked or moving stand-in is placed ahead at a side gap.
# - 25 m/s past a parked car 0.5 m away: one near miss on that side, the
#   camera shoves away from it and settles back within a second
# - 3 m away, at 10 m/s, at a closing speed of 5 m/s, overlapping (a crash),
#   or with near_miss off: none
# - a drop from 2.5 m: one landing, the camera dips at least 10 cm and comes
#   back; with landing_dip off it is counted but does not dip
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/driving_feel_motion.gd

const TIMEOUT := 90.0

class FakeCar extends Node3D:
	var detailed := true
	var wrecked := false
	var half_w := 1.0
	var linear_velocity := Vector3.ZERO
	func _physics_process(delta: float) -> void:
		global_position += linear_velocity * delta

class FakeTraffic extends Node:
	var cars: Array = []

var fails := 0
var game: Node
var t := 0.0
var step := "boot"
var step_t := 0.0
var p: PlayerCar
var fx: FxPack
var cam: ChaseCamera
var nm: NearMiss
var traffic := FakeTraffic.new()
var quit_in := 0
var samples := {}
var cases: Array = []
var case_i := -1
var fwd := Vector3.ZERO
var right := Vector3.ZERO
var speed := 25.0

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	AudioSettings.path = "user://driving_feel_motion_test.cfg"   # defaults, never the real file
	DirAccess.remove_absolute(ProjectSettings.globalize_path(AudioSettings.path))
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	# name, player speed, stand-in speed along the road, side gap (m), side, near_miss on, expected count
	cases = [
		["close pass right", 25.0, 0.0, 0.5, 1, true, 1],
		["close pass left", 25.0, 0.0, 0.4, -1, true, 1],
		["3 m away", 25.0, 0.0, 3.0, 1, true, 0],
		["too slow", 10.0, 0.0, 0.5, 1, true, 0],
		["closing 5 m/s", 25.0, 20.0, 0.5, 1, true, 0],
		["overlapping", 25.0, 0.0, -0.6, 1, true, 0],
		["switched off", 25.0, 0.0, 0.5, 1, false, 0],
	]

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL ", msg)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fail(msg)

func _go(s: String) -> void:
	step = s
	step_t = 0.0

func _hold(c: PlayerCar) -> void:
	c.throttle_input = 0.0
	c.brake_input = 0.0
	c.handbrake_input = 0.0
	c.steering_input = 0.0

func _process(delta: float) -> bool:
	if quit_in > 0:
		quit_in -= 1
		if quit_in == 0:
			quit(0 if fails == 0 else 1)
		return false
	if game == null:
		return false
	t += delta
	step_t += delta
	if t > TIMEOUT:
		_fail("timed out in step %s" % step)
		_finish()
		return false
	match step:
		"boot":
			p = game.get("player")
			if p == null or step_t < 1.0:
				return false
			p.driver = _hold
			fx = game.get("fx")
			cam = game.get("camera")
			nm = fx.near_miss if fx != null else null
			_check(nm != null, "NearMiss not built")
			if nm == null:
				_finish()
				return false
			_check(nm.get_node_or_null("WhooshL") != null and nm.get_node_or_null("WhooshR") != null, "whoosh players missing")
			var w := NearMiss.stream("whoosh0_l")
			_check(w != null and w.data.size() > 32000, "the whoosh should be a real sound")
			game.add_child(traffic)
			nm._traffic = traffic
			fwd = -p.global_transform.basis.z
			fwd.y = 0.0
			fwd = fwd.normalized()
			right = fwd.cross(Vector3.UP)
			_go("next_case")
		"next_case":
			for c in traffic.cars:
				c.queue_free()
			traffic.cars.clear()
			case_i += 1
			if case_i >= cases.size():
				_go("landing")
				return false
			var c: Array = cases[case_i]
			speed = c[1]
			FxSettings.set_on("near_miss", c[5])
			fx.apply_settings()
			var car := FakeCar.new()
			game.add_child(car)
			var my_half_w := float(p.chassis_visual.get_meta("half_w", 0.9))
			var lat: float = (my_half_w + car.half_w + float(c[3])) * float(c[4])
			car.global_position = p.global_position + fwd * 11.0 + right * lat
			car.linear_velocity = fwd * float(c[2])
			traffic.cars.append(car)
			samples.count = nm.count
			samples.peak = 0.0
			cam.nudge_x = 0.0
			_go("pass")
		"pass":
			p.linear_velocity = fwd * speed
			samples.peak = maxf(samples.peak, absf(cam.nudge_x)) if nm.count > samples.count else samples.peak
			var c: Array = cases[case_i]
			var car: Node3D = traffic.cars[0]
			var behind := (car.global_position - p.global_position).dot(fwd) < -3.0
			if behind or step_t > 4.0:
				if step_t > 4.0 and int(c[6]) > 0:
					_fail("%s: the stand-in never went past" % c[0])
				samples.settle = 0.0
				_go("settle_case")
		"settle_case":
			p.linear_velocity = fwd * speed
			if step_t > 1.2:
				var c: Array = cases[case_i]
				var n: int = nm.count - samples.count
				print("%s: %d near miss(es), side %d, strength %.2f, camera peak %.2f, after 1.2 s %.3f" % [
					c[0], n, nm.last_side if n > 0 else 0, nm.last_strength if n > 0 else 0.0, samples.peak, cam.nudge_x])
				_check(n == int(c[6]), "%s: expected %d near miss(es), got %d" % [c[0], c[6], n])
				if n > 0:
					_check(nm.last_side == int(c[4]), "%s: wrong side (%d)" % [c[0], nm.last_side])
					_check(samples.peak > 0.3 and samples.peak < 1.3, "%s: camera nudge peak %.2f, expected 0.3-1.3" % [c[0], samples.peak])
					_check(absf(cam.nudge_x) < 0.03, "%s: the nudge should settle (%.3f)" % [c[0], cam.nudge_x])
				_go("next_case")
		"landing":
			_hold(p)
			if step_t > 0.1 and step_t < 0.2:
				p.linear_velocity = Vector3.ZERO
			elif step_t > 1.5:
				FxSettings.set_on("landing_dip", true)
				samples.lands = cam.landing_count
				samples.dip = 0.0
				p.global_position += Vector3.UP * 2.5
				p.linear_velocity = Vector3.ZERO
				p.angular_velocity = Vector3.ZERO
				_go("drop")
		"drop":
			samples.dip = minf(samples.dip, cam.dip)
			if step_t > 2.5:
				print("drop from 2.5 m: %d landing(s), camera dip peak %.2f (x %.2f m), after %.3f" % [
					cam.landing_count - samples.lands, samples.dip, ChaseCamera.DIP_POS, cam.dip])
				_check(cam.landing_count - samples.lands == 1, "a 2.5 m drop should be one landing (%d)" % (cam.landing_count - samples.lands))
				_check(samples.dip < -0.45, "the camera should dip on landing (%.2f)" % samples.dip)
				_check(absf(cam.dip) < 0.03, "the dip should spring back (%.3f)" % cam.dip)
				FxSettings.set_on("landing_dip", false)
				samples.lands = cam.landing_count
				samples.dip = 0.0
				p.global_position += Vector3.UP * 2.5
				p.linear_velocity = Vector3.ZERO
				p.angular_velocity = Vector3.ZERO
				_go("drop_off")
		"drop_off":
			samples.dip = minf(samples.dip, cam.dip)
			if step_t > 2.5:
				print("drop with landing_dip off: %d landing(s), dip peak %.2f" % [cam.landing_count - samples.lands, samples.dip])
				_check(cam.landing_count - samples.lands == 1, "the off switch should still see the landing")
				_check(samples.dip > -0.01, "landing_dip off should not dip (%.2f)" % samples.dip)
				FxSettings.set_on("landing_dip", true)
				_finish()
	return false

func _finish() -> void:
	if quit_in > 0 or game == null:
		return
	print("driving_feel_motion: %s" % ("PASS" if fails == 0 else "%d failure(s)" % fails))
	game.queue_free()
	game = null
	quit_in = 30
