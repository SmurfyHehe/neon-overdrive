extends SceneTree

# Traction control (2026-10-08), headless: the game-side TC in
# scripts/traction_control.gd, on a flat "Road" slab with a fresh PlayerCar
# per run (the takeover_feel setup), driven through PlayerCar.driver.
# Checks, for each level the Tuner can set (Off 0, Low = stock 8, High 4):
# - the level mapping, and that the vendor's own check stays out of the way
# - a full-throttle launch: Off never cuts; Low lets the tyres flare more
#   than High; High holds wheelspin lowest; TC does not chatter
# - a line-lock burnout is untouched by TC at every level
# - a handbrake donut on Low turns about as well as on Off
# - braking hard from 25 m/s never wakes TC
# - a reverse launch on High cuts too (Roy: TC works in reverse)
# Prints one line per run so tuning can be compared. Exit code 1 on failure.
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 120 --path . -s res://tests/traction_control.gd

const LEVELS := {"Off": 0.0, "Low": 8.0, "High": 4.0}

var failures: Array[String] = []
var throttle := 0.0
var brake := 0.0
var steer := 0.0
var handbrake := 0.0

func _initialize() -> void:
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1200, 1, 1200)
	col.shape = box
	col.position.y = -0.5
	ground.add_child(col)
	ground.add_to_group("Road")
	root.add_child(ground)

	_check(TractionControl.level_of(0.0) == TractionControl.Level.OFF and TractionControl.level_of(-1.0) == TractionControl.Level.OFF,
		"0 and below should map to Off")
	_check(TractionControl.level_of(8.0) == TractionControl.Level.LOW and TractionControl.level_of(20.0) == TractionControl.Level.LOW,
		"the stock 8 (and the slider top) should map to Low")
	_check(TractionControl.level_of(4.0) == TractionControl.Level.HIGH, "4 should map to High")

	var launch := {}
	for lv in LEVELS:
		launch[lv] = await _launch(LEVELS[lv], 1)
		print("launch %-4s: %s" % [lv, _fmt(launch[lv])])
	_check(launch.Off.cut_max == 0.0, "Off should never cut")
	_check(launch.Off.excess_max > 3.0, "the stock car should spin its tyres on an Off launch (peak %.1f m/s), or this test proves nothing" % launch.Off.excess_max)
	_check(launch.High.cut_max > 0.0, "High should cut on a full-throttle launch")
	_check(launch.High.excess_mean < launch.Low.excess_mean and launch.Low.excess_mean <= launch.Off.excess_mean * 1.05,
		"mean wheelspin should fall Off ~>= Low > High (%.2f / %.2f / %.2f m/s)" % [launch.Off.excess_mean, launch.Low.excess_mean, launch.High.excess_mean])
	# Low lets the stock coupe's launch chirp through; on a low-grip rear it has real wheelspin to catch.
	var slick_off := await _launch(LEVELS.Off, 1, 1.0)
	var slick_low := await _launch(LEVELS.Low, 1, 1.0)
	print("launch Off, rear grip 1.0: %s" % _fmt(slick_off))
	print("launch Low, rear grip 1.0: %s" % _fmt(slick_low))
	_check(slick_low.cut_max > 0.0 and slick_low.excess_mean < slick_off.excess_mean * 0.8,
		"Low should catch real wheelspin on a low-grip rear (%.2f vs Off %.2f m/s)" % [slick_low.excess_mean, slick_off.excess_mean])
	for lv in ["Low", "High"]:
		_check(launch[lv].toggles_per_s < 8.0, "%s should not chatter (%.1f on/off per s)" % [lv, launch[lv].toggles_per_s])
		_check(launch[lv].speed >= launch.Off.speed * (0.95 if lv == "Low" else 0.85), "%s should not strangle the launch (%.1f vs Off %.1f m/s)" % [lv, launch[lv].speed, launch.Off.speed])

	for lv in LEVELS:
		var b := await _burnout(LEVELS[lv])
		print("burnout %-4s: %s" % [lv, _fmt(b)])
		_check(b.cut_max == 0.0, "%s: TC should stand aside for a line-lock burnout" % lv)
		_check(b.rear > 10.0, "%s: the line-lock burnout should still spin the rears (%.1f m/s)" % [lv, b.rear])

	var d_off := await _donut(LEVELS.Off)
	var d_low := await _donut(LEVELS.Low)
	print("donut Off: %s" % _fmt(d_off))
	print("donut Low: %s" % _fmt(d_low))
	# Low may trim the 1.5 s roll-off before the flick a little; the slide itself runs uncut.
	_check(d_low.yaw >= d_off.yaw * 0.8, "Low should not kill a donut (yaw %.2f vs Off %.2f rad/s)" % [d_low.yaw, d_off.yaw])

	var br := await _brake_run(LEVELS.High)
	print("braking High: %s" % _fmt(br))
	_check(br.cut_max == 0.0, "braking from 25 m/s should never wake TC")

	var rev_off := await _launch(LEVELS.Off, -1)
	var rev_high := await _launch(LEVELS.High, -1)
	print("reverse Off : %s" % _fmt(rev_off))
	print("reverse High: %s" % _fmt(rev_high))
	_check(rev_off.excess_max <= 3.0 or rev_high.cut_max > 0.0, "High should cut a reverse wheelspin")

	for f in failures:
		printerr("FAIL: ", f)
	print("traction_control: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _fmt(r: Dictionary) -> String:
	var parts: Array[String] = []
	for k in r:
		parts.append("%s %.2f" % [k, r[k]])
	return ", ".join(parts)

func _drive(c: PlayerCar) -> void:
	c.throttle_input = throttle
	c.brake_input = brake
	c.steering_input = steer
	c.handbrake_input = handbrake

func _spawn(tc: float, rear_cof := 0.0) -> PlayerCar:
	throttle = 0.0
	brake = 1.0
	steer = 0.0
	handbrake = 0.0
	var car: PlayerCar = load("res://scripts/player.gd").new()
	car.sim_only = true
	car.position = Vector3(0, 0.3, 0)
	car.driver = _drive
	root.add_child(car)
	await process_frame
	car.traction_control_max_slip = tc
	if rear_cof > 0.0:  # the takeover_feel way: only the rear tyres, Road surface
		for w in [car.rear_left_wheel, car.rear_right_wheel]:
			w.coefficient_of_friction = {"Road": rear_cof, "Dirt": 2.0}
			w.current_cof = rear_cof
	await _ticks(1.0)  # settle on the springs
	return car

func _ticks(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame

func _rear_surface(car: PlayerCar) -> float:
	return absf((car.rear_left_wheel.spin + car.rear_right_wheel.spin) * 0.5 * car.rear_left_wheel.tire_radius)

## Full throttle from a stop for 5 s, forward (dir 1) or in reverse (-1).
func _launch(tc: float, dir: int, rear_cof := 0.0) -> Dictionary:
	var car := await _spawn(tc, rear_cof)
	if dir < 0:
		car.toggle_reverse()
		await _ticks(0.6)
	brake = 0.0
	throttle = 1.0
	var r := {"excess_max": 0.0, "excess_mean": 0.0, "cut_max": 0.0, "cut_mean": 0.0, "toggles_per_s": 0.0}
	var n := int(5.0 * Engine.physics_ticks_per_second)
	var was := false
	var toggles := 0
	for i in n:
		await physics_frame
		var e := TractionControl.excess_speed(car)
		r.excess_max = maxf(r.excess_max, e)
		r.excess_mean += e / n
		r.cut_max = maxf(r.cut_max, car.traction.cut)
		r.cut_mean += car.traction.cut / n
		if car.tcs_active != was:
			toggles += 1
			was = car.tcs_active
	r.toggles_per_s = toggles / 5.0
	r["speed"] = car.speed
	car.free()
	return r

## Line-lock burnout: brake + throttle from a stop for 3 s.
func _burnout(tc: float) -> Dictionary:
	var car := await _spawn(tc)
	throttle = 1.0
	var r := {"cut_max": 0.0, "rear": 0.0}
	var n := int(3.0 * Engine.physics_ticks_per_second)
	for i in n:
		await physics_frame
		r.cut_max = maxf(r.cut_max, car.traction.cut)
		if i >= n / 3:
			r.rear += _rear_surface(car) / (n - n / 3)
	car.free()
	return r

## Roll off 1.5 s, then full lock + throttle with a 0.4 s handbrake flick, 6 s.
func _donut(tc: float) -> Dictionary:
	var car := await _spawn(tc)
	brake = 0.0
	throttle = 1.0
	await _ticks(1.5)
	steer = 1.0
	handbrake = 1.0
	await _ticks(0.4)
	handbrake = 0.0
	var r := {"yaw": 0.0, "cut_mean": 0.0}
	var n := int(6.0 * Engine.physics_ticks_per_second)
	for i in n:
		await physics_frame
		r.yaw += absf(car.angular_velocity.y) / n
		r.cut_mean += car.traction.cut / n
	car.free()
	return r

## Up to 25 m/s, then full brakes (throttle off) to a stop.
func _brake_run(tc: float) -> Dictionary:
	var car := await _spawn(tc)
	brake = 0.0
	throttle = 1.0
	var guard := 0
	while car.speed < 25.0 and guard < 30 * Engine.physics_ticks_per_second:
		await physics_frame
		guard += 1
	throttle = 0.0
	brake = 1.0
	var r := {"cut_max": 0.0}
	for i in int(4.0 * Engine.physics_ticks_per_second):
		await physics_frame
		r.cut_max = maxf(r.cut_max, car.traction.cut)
	car.free()
	return r
