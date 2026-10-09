extends SceneTree

# Takeover feel check: can the current car hold a burnout and spin a donut
# with keyboard inputs? A measurement, not a pass/fail gate -- it prints one
# line per run so tuning changes can be compared.
#
# Each run drops a fresh PlayerCar on a flat "Road" slab and holds keys
# through Input.action_press, the same path a player's keyboard takes.
#
#   burnout: brake + throttle from a stop in 1st (power brake), 4 s.
#            Good = rear tyre surface speed well above car speed, car
#            creeping under ~2 m/s.
#   donut:   roll off in 1st for 1.5 s, then full right + throttle, with a
#            0.4 s handbrake flick to break the rear loose, held 8 s.
#            Good = rear tyre slip angle over 30 deg (rear out, not a grip
#            circle), yaw over 1.5 rad/s, car stays inside ~8 m.
#
# Variants turn the vendored assists off one at a time so the numbers show
# which knob is in the way. Run (headless is fine):
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/car/takeover_feel.gd

const HZ := 60

const VARIANTS := {
	"stock": {},
	"no TCS": {"traction_control_max_slip": -1.0},
	"no TCS, no stability": {"traction_control_max_slip": -1.0, "enable_stability": false},
	"no TCS/stab/steer assists": {"traction_control_max_slip": -1.0, "enable_stability": false,
		"countersteer_assist": 0.0, "steering_slip_assist": 10.0},
	"all off + line lock": {"traction_control_max_slip": -1.0, "enable_stability": false,
		"countersteer_assist": 0.0, "steering_slip_assist": 10.0, "front_brake_bias": 1.0},
	# Grip: "cof" sets every tyre's Road friction, "rear_cof" only the rears.
	# Stock Road is 3.0 (GEVP default, ~2.9 g); real street tyres are ~1.0.
	"all off, grip 2.0": {"traction_control_max_slip": -1.0, "enable_stability": false,
		"countersteer_assist": 0.0, "steering_slip_assist": 10.0, "front_brake_bias": 1.0, "cof": 2.0},
	"all off, grip 1.5": {"traction_control_max_slip": -1.0, "enable_stability": false,
		"countersteer_assist": 0.0, "steering_slip_assist": 10.0, "front_brake_bias": 1.0, "cof": 1.5},
	"all off, rear grip 1.5": {"traction_control_max_slip": -1.0, "enable_stability": false,
		"countersteer_assist": 0.0, "steering_slip_assist": 10.0, "front_brake_bias": 1.0, "rear_cof": 1.5},
	"stock assists, rear grip 1.5": {"front_brake_bias": 1.0, "rear_cof": 1.5},
}

func _initialize() -> void:
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	col.shape = box
	col.position.y = -0.5
	ground.add_child(col)
	ground.add_to_group("Road")
	root.add_child(ground)

	for name in VARIANTS:
		print("--- %s" % name)
		print("  burnout: " + await _burnout(VARIANTS[name]))
		print("  donut:   " + await _donut(VARIANTS[name]))
	quit(0)

func _spawn(overrides: Dictionary) -> PlayerCar:
	var car: PlayerCar = load("res://scripts/car/player.gd").new()
	car.position = Vector3(0, 0.3, 0)
	root.add_child(car)
	await process_frame
	for key in overrides:
		if key == "cof" or key == "rear_cof":
			var wheels: Array = car.wheel_array if key == "cof" else [car.rear_left_wheel, car.rear_right_wheel]
			for w in wheels:
				w.coefficient_of_friction = {"Road": overrides[key], "Dirt": 2.0}
				w.current_cof = overrides[key]
		else:
			car.set(key, overrides[key])
	if overrides.has("front_brake_bias"):
		# initialize() already copied the bias onto the axles.
		car.front_axle.brake_bias = car.front_brake_bias
		car.rear_axle.brake_bias = 1.0 - car.front_brake_bias
	await _frames(HZ)  # settle on the springs
	return car

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _release_all() -> void:
	for a in ["accelerate", "brake", "handbrake", "steer_left", "steer_right"]:
		Input.action_release(a)

func _rear_surface_speed(car: PlayerCar) -> float:
	var w := car.rear_left_wheel
	return absf((car.rear_left_wheel.spin + car.rear_right_wheel.spin) * 0.5 * w.tire_radius)

func _burnout(overrides: Dictionary) -> String:
	var car := await _spawn(overrides)
	var start := car.global_position
	Input.action_press("brake")
	Input.action_press("accelerate")
	var tyre := 0.0
	var tcs := 0
	var n := 4 * HZ
	for i in n:
		await physics_frame
		if i >= HZ:  # skip the first second of spin-up
			tyre += _rear_surface_speed(car)
		if car.tcs_active:
			tcs += 1
	_release_all()
	var moved := Vector2(car.global_position.x - start.x, car.global_position.z - start.z).length()
	var out := "rear tyre %.1f m/s avg, car %.1f m/s, moved %.1f m, rpm %d, TCS on %d%%" % [
		tyre / (n - HZ), absf(car.current_speed()), moved, car.motor_rpm, 100 * tcs / n]
	car.free()
	return out

func _donut(overrides: Dictionary) -> String:
	var car := await _spawn(overrides)
	Input.action_press("accelerate")
	await _frames(int(1.5 * HZ))
	Input.action_press("steer_right")
	Input.action_press("handbrake")
	await _frames(int(0.4 * HZ))
	Input.action_release("handbrake")
	var centre := Vector2.ZERO
	var pts: Array[Vector2] = []
	var slip_sum := 0.0
	var slip_frames := 0
	var yaw_sum := 0.0
	var turned := 0.0
	var speed_sum := 0.0
	var n := 8 * HZ
	for i in n:
		await physics_frame
		var v := car.local_velocity
		# Rear tyre slip angle: how far the rear is sliding sideways. A grip
		# circle keeps this near zero; a donut holds it high.
		var slip := rad_to_deg(absf(car.rear_left_wheel.slip_vector.x + car.rear_right_wheel.slip_vector.x) * 0.5)
		if i >= HZ:  # measure the held part, not the entry
			slip_sum += slip
			if slip > 30.0:
				slip_frames += 1
			yaw_sum += absf(car.angular_velocity.y)
			speed_sum += v.length()
			pts.append(Vector2(car.global_position.x, car.global_position.z))
		turned += car.angular_velocity.y / HZ
	_release_all()
	for p in pts:
		centre += p
	centre /= pts.size()
	var radius := 0.0
	for p in pts:
		radius = maxf(radius, p.distance_to(centre))
	var m := float(pts.size())
	var out := "rear slip %.0f deg avg (>30 deg %d%% of time), yaw %.2f rad/s, %.1f turns, speed %.1f m/s, radius %.1f m, gear %d, rpm %d" % [
		slip_sum / m, int(100.0 * slip_frames / m), yaw_sum / m, absf(turned) / TAU, speed_sum / m, radius, car.current_gear, car.motor_rpm]
	car.free()
	return out
