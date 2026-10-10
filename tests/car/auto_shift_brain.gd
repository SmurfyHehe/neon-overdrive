extends SceneTree

# Realistic automatic, the shift brain half (step A2), on a bare pad at the
# game's 120 Hz. One car per family: the beater (old), the coupe (90s) and the
# coupe with a modern box.
#   - no hunting: held at 60 km/h for 20 s there is no shift once it has
#     settled; a steady half throttle from 60 km/h never goes back to a gear
#     it left; the throttle swept 0 -> 1 -> 0 over 30 s never shifts one way
#     and back within a second
#   - kickdown: in top at 80 km/h, floored: one shift, up to two gears down
#     (two on the coupe), within the family's delay + 0.1 s, revs under max
#   - corner hold: a 0.5 g circle at about 60 km/h, lift: no upshift until a
#     second after the car is straight again (the same lift on the straight
#     upshifts well before that)
#   - brake downshift: 120 km/h, brake 0.6 to a stop: down one gear at a time,
#     at least 0.35 s apart, ends in 1st; the modern box blips the revs onto
#     the lower gear's speed within 0.12 s, the others do not
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/car/auto_shift_brain.gd

const H := preload("res://tests/car/auto_box_harness.gd")
const AUTO := PlayerCar.Transmission.AUTO
const MODERN := {"auto": {"family": "modern"}}
## [kind, spec overrides, family]
const CARS := [
	["p0_beater", {}, "old"],
	["p1_coupe", {}, "90s"],
	["p1_coupe", MODERN, "modern"],
]

var fails: Array[String] = []
var dt := 1.0 / 120.0

func _initialize() -> void:
	Engine.physics_ticks_per_second = 120  # the game's rate, whatever NEON_TICKS says
	_run()

func _run() -> void:
	dt = 1.0 / Engine.physics_ticks_per_second
	H.ground(root)
	await physics_frame
	for car in CARS:
		await _hold_60(car)
		await _half_throttle(car)
		await _sweep(car)
		await _kickdown(car)
		await _brake_down(car)
	await _corner(true)
	await _corner(false)
	for f in fails:
		printerr("FAIL: ", f)
	print("auto_shift_brain: ", "PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	quit(0 if fails.is_empty() else 1)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)

func _spawn(car: Array, p: H.Pedals) -> PlayerCar:
	var c: PlayerCar = H.car(root, car[0], AUTO, p, car[1])
	_check(c.auto_box != null and c.auto_box.family == car[2], "%s should have a %s box" % [car[0], car[2]])
	await H.settle(self, p)
	return c

## Full throttle to `kmh`, then off.
func _run_up(c: PlayerCar, p: H.Pedals, kmh: float) -> void:
	p.throttle = 1.0
	var t := 0.0
	while H.kmh(c) < kmh and t < 60.0:
		await physics_frame
		t += dt
	p.throttle = 0.0

func _hold_60(car: Array) -> void:
	var p := H.Pedals.new()
	var c := await _spawn(car, p)
	var late_shifts := 0
	var gear := c.current_gear
	var total := int(28.0 / dt)
	for i in total:
		await physics_frame
		p.throttle = clampf(0.2 + 0.15 * (60.0 - H.kmh(c)), 0.0, 1.0)
		if c.current_gear != gear:
			gear = c.current_gear
			if i > int(8.0 / dt):
				late_shifts += 1
	print("%s: held 60 km/h in gear %d at %.0f rpm, %d shifts after settling" % [car[2], gear, c.motor_rpm, late_shifts])
	_check(absf(H.kmh(c) - 60.0) < 3.0, "%s: the hold drifted to %.0f km/h" % [car[2], H.kmh(c)])
	_check(late_shifts == 0, "%s: %d shifts while holding 60 km/h" % [car[2], late_shifts])
	await H.remove(self, c)

func _half_throttle(car: Array) -> void:
	var p := H.Pedals.new()
	var c := await _spawn(car, p)
	await _run_up(c, p, 60.0)
	p.throttle = 0.5
	var seen: Array[int] = [c.current_gear]
	var went_back := false
	for i in int(20.0 / dt):
		await physics_frame
		if c.current_gear != seen[-1]:
			if c.current_gear in seen:
				went_back = true
			seen.append(c.current_gear)
	print("%s: half throttle from 60 km/h for 20 s went through gears %s" % [car[2], str(seen)])
	_check(not went_back, "%s: half throttle hunted: %s" % [car[2], str(seen)])
	await H.remove(self, c)

func _sweep(car: Array) -> void:
	var p := H.Pedals.new()
	var c := await _spawn(car, p)
	await _run_up(c, p, 40.0)
	var gear := c.current_gear
	var last_dir := 0
	var last_t := -10.0
	var quickest := INF
	var shifts := 0
	var t := 0.0
	while t < 30.0:
		await physics_frame
		t += dt
		p.throttle = t / 15.0 if t < 15.0 else 2.0 - t / 15.0
		if c.current_gear != gear:
			var dir := signi(c.current_gear - gear)
			if last_dir != 0 and dir != last_dir:
				quickest = minf(quickest, t - last_t)
			last_dir = dir
			last_t = t
			gear = c.current_gear
			shifts += 1
	print("%s: throttle sweep, %d shifts, quickest change of mind %s" % [car[2], shifts, "%.2f s" % quickest if is_finite(quickest) else "none"])
	_check(quickest >= 1.0, "%s: shifted one way and back within %.2f s on the sweep" % [car[2], quickest])
	await H.remove(self, c)

func _kickdown(car: Array) -> void:
	var p := H.Pedals.new()
	var c := await _spawn(car, p)
	var top := c.gear_ratios.size()
	# into top on a light throttle, then let it roll down to 80 km/h
	var t := 0.0
	while (c.current_gear < top or H.kmh(c) < 95.0) and t < 90.0:
		await physics_frame
		t += dt
		p.throttle = 0.45
	p.throttle = 0.0
	t = 0.0
	while H.kmh(c) > 80.0 and t < 60.0:
		await physics_frame
		t += dt
	await H.wait(self, 0.05)
	_check(c.current_gear == top, "%s: should be in top (%d) at 80 km/h off the throttle, is in %d" % [car[2], top, c.current_gear])
	var from := c.current_gear
	var count0: int = c.auto_box.shift_count
	p.throttle = 1.0
	var shift_t := INF
	var peak := 0.0
	t = 0.0
	while t < c.auto_box.kickdown_delay + 1.2:
		await physics_frame
		t += dt
		if c.current_gear != from and not is_finite(shift_t):
			shift_t = t
		peak = maxf(peak, c.motor_rpm)
	var down := from - c.current_gear
	var shifts: int = c.auto_box.shift_count - count0
	print("%s kickdown: %d -> %d at %.2f s (delay %.2f), %d shift(s), peak %.0f of %.0f rpm" % [car[2], from, c.current_gear, shift_t, c.auto_box.kickdown_delay, shifts, peak, c.max_rpm])
	_check(down >= 1 and down <= 2, "%s: kickdown went %d gears down" % [car[2], down])
	if car[0] == "p1_coupe":
		_check(down == 2, "the coupe should kick down two gears from top at 80 km/h, went %d" % down)
	_check(shifts == 1, "%s: the kickdown took %d shifts, wanted one" % [car[2], shifts])
	_check(shift_t <= c.auto_box.kickdown_delay + 0.1, "%s: kickdown after %.2f s, delay is %.2f" % [car[2], shift_t, c.auto_box.kickdown_delay])
	_check(shift_t >= c.auto_box.kickdown_delay - 0.02, "%s: kickdown came before its delay (%.2f s)" % [car[2], shift_t])
	_check(peak < c.max_rpm, "%s: the kickdown over-revved to %.0f rpm" % [car[2], peak])
	await H.remove(self, c)

func _brake_down(car: Array) -> void:
	var p := H.Pedals.new()
	var c := await _spawn(car, p)
	await _run_up(c, p, 125.0)
	var t := 0.0
	while H.kmh(c) > 120.0 and t < 30.0:
		await physics_frame
		t += dt
	p.brake = 0.6
	var gear := c.current_gear
	var seq: Array[int] = [gear]
	var in_order := true
	var closest := INF
	var last_t := -10.0
	var blips := 0          # downshifts where the revs were on the new gear's speed within the blip time
	var steps := 0
	var check_at := -1.0
	t = 0.0
	while H.kmh(c) > 0.5 and t < 30.0:
		await physics_frame
		t += dt
		if c.current_gear != gear:
			if c.current_gear != gear - 1:
				in_order = false
			closest = minf(closest, t - last_t)
			last_t = t
			gear = c.current_gear
			seq.append(gear)
			steps += 1
			check_at = t + AutoBox.BLIP_TIME + 2.0 * dt
		if check_at > 0.0 and t >= check_at:
			check_at = -1.0
			if H.kmh(c) > 20.0 and c.motor_rpm >= 0.95 * H.gearbox_rpm(c):
				blips += 1
	print("%s braking from 120: gears %s, closest steps %.2f s apart, %d of %d with the revs matched in %.2f s" % [car[2], str(seq), closest, blips, steps, AutoBox.BLIP_TIME])
	_check(in_order, "%s: skipped a gear on the brakes: %s" % [car[2], str(seq)])
	_check(seq[-1] == 1, "%s: stopped in gear %d, wanted 1st" % [car[2], seq[-1]])
	_check(steps >= 2, "%s: only %d downshift(s) from 120 km/h" % [car[2], steps])
	_check(closest >= AutoBox.BRAKE_STEP_GAP - dt, "%s: two brake downshifts %.2f s apart" % [car[2], closest])
	if car[2] == "modern":
		_check(blips >= steps - 1, "the modern box blipped on %d of %d downshifts" % [blips, steps])
	else:
		_check(blips <= 1, "the %s box matched the revs like a blip on %d of %d downshifts" % [car[2], blips, steps])
	await H.remove(self, c)

## A 0.5 g circle at about 60 km/h entered flat out in a low gear, then a lift.
## cornering false = the same lift on the straight, to show the corner is what holds the gear.
func _corner(cornering: bool) -> void:
	var p := H.Pedals.new()
	var c: PlayerCar = H.car(root, "p1_coupe", AUTO, p)
	await H.settle(self, p)
	await _run_up(c, p, 50.0)
	p.throttle = 1.0
	var t := 0.0
	var peak_g := 0.0
	var steer := 0.0
	# turn in and hold 0.5 g on the yaw rate while it pulls up to 60 km/h
	while H.kmh(c) < 60.0 and t < 10.0:
		await physics_frame
		t += dt
		if cornering:
			steer = clampf(steer + (0.5 * 9.81 / maxf(c.current_speed(), 5.0) - absf(c.angular_velocity.y)) * 2.0 * dt, 0.0, 0.6)
			p.steer = steer
	var gear := c.current_gear
	p.throttle = 0.0   # the lift
	var up_t := INF
	var straight_t := 2.0   # keep turning for 2 s after the lift, then straighten
	t = 0.0
	while t < 8.0:
		await physics_frame
		t += dt
		if cornering and t < straight_t:
			steer = clampf(steer + (0.5 * 9.81 / maxf(c.current_speed(), 5.0) - absf(c.angular_velocity.y)) * 2.0 * dt, 0.0, 0.6)
			p.steer = steer
			peak_g = maxf(peak_g, absf(c.angular_velocity.y) * c.current_speed() / 9.81)
		else:
			p.steer = 0.0
		if c.current_gear > gear and not is_finite(up_t):
			up_t = t
	if cornering:
		print("corner hold: %.2f g, lift in gear %d, upshift %.2f s after the lift (straight at %.1f s)" % [peak_g, gear, up_t, straight_t])
		_check(peak_g >= 0.45, "the circle only reached %.2f g" % peak_g)
		_check(up_t >= straight_t + 0.95, "upshifted %.2f s after the lift, still inside the corner hold (straight at %.1f s)" % [up_t, straight_t])
		_check(up_t <= straight_t + 4.0, "never upshifted after the corner")
	else:
		print("same lift on the straight: upshift %.2f s after it" % up_t)
		_check(up_t < 2.0, "on the straight the lift should upshift within 2 s, took %.2f" % up_t)
	await H.remove(self, c)
