extends SceneTree

# Tyres (brief DP3, 2026-10-11), headless and silent, scripted driver.
# Unit part (no car):
# - slow leak: a kerb strike over the free line starts one; 1 -> 0.55 takes
#   120 s just over the line and 60 s at the hardest strike that does not
#   burst the tyre; it keeps leaking down to the rim (hands over to LM)
# - the air machine: back to 1, then about 5 minutes to 0.55; the garage ends it
# - bent rim: runout in proportion to the strike, 4 mm at most; a bent rim
#   leaks from a gentler kerb (a threshold, the same every time)
# - flat spot: a wheel locked for 1.5 s in one go gets 1.5 mm
# - what the car feels: the wobble force rises with speed squared up to the
#   tyre's limit and with the runout; a soft tyre drags more the softer it
#   is, is less stiff, grips a little less, rolls harder and sits lower
# - the Damage setting, the save, the repair bill, the lamps
# - no dice: the same strikes and steps give the same numbers
# Drive part (Game.tscn, straight flat road, no traffic):
# - LEAN: parked, a soft front tyre (0.55) lowers its corner
# - PULL: a soft front tyre (0.55), wheel straight at ~70 km/h for 5 s: the
#   car drifts to that side; the other side mirrors it
# - WOBBLE: a rim 4 mm out of round: the camera shake is bigger at 110 km/h
#   than at 45 km/h
# - SKID: handbrake held from 100 km/h. On a dry road the handbrake only
#   slows the rear wheels (and every car has ABS on the foot brake), so this
#   prints how far they slowed and checks the flat spots agree with it: none
#   unless a wheel really stayed locked for 1.5 s
# - LEAK: a real strike on the car: the pressure in the offsets falls as timed
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 120 --audio-driver Dummy --path . -s res://tests/car/tyre_damage.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const DamageOffsets := preload("res://scripts/car/damage_offsets.gd")
const FlatTyre := preload("res://scripts/car/flat_tyre.gd")

enum Step { BOOT, LEAN, PULL_BASE, PULL_FL, PULL_FR, WOBBLE_SLOW, WOBBLE_FAST, SKID, LEAK, DONE }

var game: Node
var step := Step.BOOT
var t := 0
var tick := 0
var hz := 120
var failures: Array[String] = []
var rest := Transform3D()
var x0 := 0.0
var drift := {}
var roll := {}
var shake := {}
var roll_sum := 0.0
var roll_n := 0
var shake_max := 0.0
var rear_turn_min := 1.0
var lean_i := 0

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		print("  FAIL: " + what)

func _initialize() -> void:
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	_unit_leak()
	_unit_rim()
	_unit_feel()
	game = Harness.boot(self, 0, 150.0, 7)

## Seconds until tyre i of d has leaked from where it is to `to`, stepping at 60 Hz.
func _seconds_to(d: CarDamage, i: int, to: float) -> float:
	var secs := 0.0
	while d.pressure[i] > to and secs < 2000.0:
		d.step_tyres(1.0 / 60.0)
		secs += 1.0 / 60.0
	return secs

func _unit_leak() -> void:
	var D := CarDamage
	var free := D.KERB_FREE_MS
	var d := CarDamage.new()
	d.apply_kerb_strike(0, free - 0.1)
	_check(d.leak[0] == 0.0 and d.leaks_started == 0 and not d.step_tyres(60.0) and d.pressure[0] == 1.0, "a kerb met under the free line starts no leak")
	# just over the line: 120 s to 0.55
	d.apply_kerb_strike(0, free + 0.01)
	_check(d.leak[0] > 0.0 and d.leaks_started == 1 and d.leak[1] == 0.0, "a kerb strike over the free line starts a leak on that wheel only")
	_check(d.pressure[0] == 1.0 and d.offsets.get_wheel(0, DamageOffsets.PRESSURE_MULT) == 1.0, "the tyre is still full at the moment of the strike")
	var slow := _seconds_to(d, 0, D.LEAK_TO)
	_check(absf(slow - D.LEAK_SLOW_S) < 2.0, "a light strike: 1 -> 0.55 in %.1f s (120)" % slow)
	_check(absf(d.offsets.get_wheel(0, DamageOffsets.PRESSURE_MULT) - d.pressure[0]) < 1.0e-5, "the offsets follow the pressure as it falls")
	_check(d.any_tyre_low() and not d.any_tyre_flat(), "a soft tyre lights the TYRE lamp, it is not flat yet")
	# the hardest strike that does not burst the tyre: 60 s
	var h := CarDamage.new()
	h.apply_kerb_strike(1, free * D.RIM_STRIKE - 0.01)
	var fast := _seconds_to(h, 1, D.LEAK_TO)
	_check(absf(fast - D.LEAK_FAST_S) < 2.0, "a hard strike: 1 -> 0.55 in %.1f s (60)" % fast)
	var m := CarDamage.new()
	m.apply_kerb_strike(1, free * (1.0 + D.RIM_STRIKE) * 0.5)
	var mid := _seconds_to(m, 1, D.LEAK_TO)
	_check(mid < slow and mid > fast, "a harder strike leaks faster (%.0f s between %.0f and %.0f)" % [mid, fast, slow])
	print("leak 1 -> 0.55: %.1f s just over the free line, %.1f s halfway, %.1f s at the hardest strike" % [slow, mid, fast])
	# a second, lighter strike never slows a leak
	var rate := h.leak[1]
	h.apply_kerb_strike(1, free + 0.5)
	_check(h.leak[1] == rate, "a lighter strike does not slow a leak that is already there")
	# it keeps going: down to the rim, where LM takes over
	_check(not FlatTyre.on_rim(h.offsets, 1), "at 0.55 the wheel is not on its rim")
	var to_rim := fast + _seconds_to(h, 1, FlatTyre.RIM_PRESSURE)
	_check(h.tyre_flat(1) and FlatTyre.on_rim(h.offsets, 1) and is_equal_approx(h.offsets.get_wheel(1, DamageOffsets.GRIP_MULT), D.RIM_GRIP), "a leak that empties ends on the rim, %.0f s after the strike" % to_rim)
	h.step_tyres(1000.0)
	_check(h.pressure[1] == 0.0, "the pressure stops at zero")
	# the air machine
	var air := CarDamage.new()
	_check(air.air_refill() == 0, "the air machine has nothing to do on four full tyres")
	air.apply_kerb_strike(2, free + 3.0)
	air.step_tyres(40.0)
	var before := air.pressure[2]
	_check(air.air_refill() == 1 and air.pressure[2] == 1.0 and before < 1.0, "the air machine pumps the soft tyre back to 1 (%.2f before)" % before)
	_check(air.offsets.get_wheel(2, DamageOffsets.PRESSURE_MULT) == 1.0, "and the offsets say so")
	var again := _seconds_to(air, 2, D.LEAK_TO)
	_check(absf(again - D.LEAK_REFILL_S) < 3.0, "it leaks again: 1 -> 0.55 in %.0f s (about 5 minutes)" % again)
	var burst := CarDamage.new()
	burst.apply_kerb_strike(3, free * D.RIM_STRIKE + 1.0)
	_check(burst.tyre_flat(3), "a strike over 2.5 x the free line bursts the tyre at once")
	burst.air_refill()
	_check(not burst.tyre_flat(3) and is_equal_approx(burst.leak[3], (1.0 - D.LEAK_TO) / D.LEAK_REFILL_S), "the air machine gets a burst tyre going again, with the slow leak")
	var price := air.repair_price()
	air.garage_repair(null)
	_check(price > 0 and air.leak[2] == 0.0 and air.runout[2] == 0.0 and not air.step_tyres(100.0) and air.pressure[2] == 1.0, "the garage mends the leak for good (bill %d)" % price)
	# no dice
	var a := CarDamage.new()
	var b := CarDamage.new()
	for c: CarDamage in [a, b]:
		c.apply_kerb_strike(0, 7.3)
		c.step_tyres(33.0)
		c.apply_kerb_strike(3, 11.0)
		for i in 600:
			c.step_tyres(1.0 / 60.0)
			c.step_lock(2, 1.0 / 60.0, i > 100)
	_check(a.pressure == b.pressure and a.leak == b.leak and a.runout == b.runout and a.offsets.data == b.offsets.data and a.parts == b.parts, "the same strikes and steps always give the same tyres")
	# Damage setting, save
	var looks := CarDamage.new()
	looks.mode = GameSettings.Damage.LOOKS_ONLY
	looks.apply_kerb_strike(0, free * D.RIM_STRIKE - 0.5)
	looks.step_tyres(80.0)
	_check(looks.pressure[0] < 0.5 and looks.runout[0] > 0.0 and looks.offsets.is_neutral(), "Looks only: the tyre goes down on the bill, the car drives as new")
	looks.sync_settings(GameSettings.Damage.LIGHT, looks.difficulty)
	_check(absf(looks.offsets.get_wheel(0, DamageOffsets.PRESSURE_MULT) - (1.0 + (looks.pressure[0] - 1.0) * 0.5)) < 1.0e-5 and absf(looks.offsets.get_wheel(0, DamageOffsets.RUNOUT) - looks.runout[0] * 0.5) < 1.0e-6, "Light: half the pressure loss and half the runout")
	looks.step_tyres(1.0)
	_check(absf(looks.offsets.get_wheel(0, DamageOffsets.PRESSURE_MULT) - (1.0 + (looks.pressure[0] - 1.0) * 0.5)) < 1.0e-5, "Light stays half while the tyre keeps leaking")
	var copy := CarDamage.new()
	copy.from_dict(a.to_dict())
	_check(copy.pressure == a.pressure and copy.leak == a.leak and copy.runout == a.runout and copy.offsets.data == a.offsets.data, "the save keeps pressure, leak and runout")
	var off := CarDamage.new()
	off.enabled = false
	off.apply_kerb_strike(0, 20.0)
	_check(off.leak[0] == 0.0 and not off.step_tyres(10.0), "a car with damage off never leaks")

func _unit_rim() -> void:
	var D := CarDamage
	var free := D.KERB_FREE_MS
	# bent rim: in proportion, capped
	var d := CarDamage.new()
	d.apply_kerb_strike(0, free + (free * (D.RIM_STRIKE - 1.0)) * 0.5)
	_check(absf(d.runout[0] - D.RUNOUT_MAX * 0.5) < 1.0e-6 and d.runout[1] == 0.0, "a strike halfway to the bursting speed bends the rim 2 mm (%.2f mm)" % (d.runout[0] * 1000.0))
	_check(absf(d.offsets.get_wheel(0, DamageOffsets.RUNOUT) - d.runout[0]) < 1.0e-6, "the offsets carry the runout")
	d.apply_kerb_strike(0, 30.0)
	d.apply_kerb_strike(0, 30.0)
	_check(d.runout[0] == D.RUNOUT_MAX, "a rim never bends more than 4 mm")
	# a bent rim leaks from a gentler kerb: a threshold
	var bent := CarDamage.new()
	bent.runout[0] = D.RUNOUT_MAX
	var line := bent.leak_free_ms(0)
	_check(is_equal_approx(line, free * (1.0 - D.BENT_RIM_LEAK_DROP)) and is_equal_approx(bent.leak_free_ms(1), free), "a fully bent rim leaks from %.1f m/s, a true one from %.1f" % [line, free])
	bent.apply_kerb_strike(0, line - 0.05)
	_check(bent.leak[0] == 0.0, "just under the bent rim's line: no leak")
	bent.apply_kerb_strike(0, line + 0.05)
	_check(bent.leak[0] > 0.0 and bent.kerb_strikes == 0 and bent.part(D.Part.STEER_FL) == 0.0, "just over it: a leak, and nothing else bends (it was under the free line)")
	bent.apply_kerb_strike(1, line + 0.05)
	_check(bent.leak[1] == 0.0, "the same kerb does nothing to a true rim")
	var half := CarDamage.new()
	half.runout[2] = D.RUNOUT_MAX * 0.5
	_check(half.leak_free_ms(2) < free and half.leak_free_ms(2) > line, "a half-bent rim sits in between")
	# flat spot
	var f := CarDamage.new()
	for i in 89:
		f.step_lock(2, 1.0 / 60.0, true)
	_check(f.runout[2] == 0.0 and f.flat_spots == 0, "a wheel locked for 1.48 s has no flat spot yet")
	f.step_lock(2, 1.0 / 60.0, false)
	for i in 89:
		f.step_lock(2, 1.0 / 60.0, true)
	_check(f.runout[2] == 0.0, "two short skids do not add up")
	for i in 3:
		f.step_lock(2, 1.0 / 60.0, true)
	_check(is_equal_approx(f.runout[2], D.FLAT_SPOT_RUNOUT) and f.flat_spots == 1 and f.runout[3] == 0.0, "a wheel locked for 1.5 s gets a 1.5 mm flat spot")
	_check(absf(f.offsets.get_wheel(2, DamageOffsets.RUNOUT) - D.FLAT_SPOT_RUNOUT) < 1.0e-6, "and the offsets carry it")
	for i in 600:
		f.step_lock(2, 1.0 / 60.0, true)
	_check(is_equal_approx(f.runout[2], D.FLAT_SPOT_RUNOUT) and f.flat_spots == 1, "a longer skid does not make it worse")
	var both := CarDamage.new()
	both.runout[1] = 0.003
	for i in 200:
		both.step_lock(1, 1.0 / 60.0, true)
	_check(is_equal_approx(both.runout[1], 0.003), "a flat spot never straightens a rim that is bent further")
	_check(f.repair_price() == roundi(D.RIM_PRICE * D.FLAT_SPOT_RUNOUT / D.RUNOUT_MAX), "a flat spot is on the repair bill (%d)" % f.repair_price())

func _unit_feel() -> void:
	# wobble: speed squared, then the tyre's limit; in proportion to the runout
	var r := 0.3
	var w30 := FlatTyre.wobble_force(0.004, 30.0 / 3.6 / r)
	var w60 := FlatTyre.wobble_force(0.004, 60.0 / 3.6 / r)
	var w200 := FlatTyre.wobble_force(0.004, 200.0 / 3.6 / r)
	var w300 := FlatTyre.wobble_force(0.004, 300.0 / 3.6 / r)
	print("wobble, 4 mm of runout: %.0f N at 30 km/h, %.0f N at 60, %.0f N at 200, %.0f N at 300" % [w30, w60, w200, w300])
	_check(w30 > 0.0 and is_equal_approx(w60, 4.0 * w30), "the wobble rises with the square of the speed")
	_check(w200 > w60 and is_equal_approx(w200, w300) and is_equal_approx(w200, 0.004 * FlatTyre.WOBBLE_STIFFNESS), "up to what the tyre lets through")
	_check(FlatTyre.wobble_force(0.004, 0.0) == 0.0 and FlatTyre.wobble_force(0.0, 100.0) == 0.0, "no wobble standing still, none on a true rim")
	_check(is_equal_approx(FlatTyre.wobble_force(0.0015, 60.0), FlatTyre.wobble_force(0.004, 60.0) * 0.375), "a 1.5 mm flat spot wobbles 3/8 as hard as a 4 mm bend")
	# a soft tyre
	_check(FlatTyre.soft_drag_share(1.0) == 0.0 and FlatTyre.soft_drag_share(0.55) > 0.0 and FlatTyre.soft_drag_share(0.3) > FlatTyre.soft_drag_share(0.55), "a soft tyre drags, more the softer it is")
	_check(FlatTyre.soft_drag_share(0.11) <= FlatTyre.SOFT_DRAG and FlatTyre.SOFT_DRAG < FlatTyre.RIM_DRAG, "and always less than a rim does")
	_check(FlatTyre.radius_mult(1.0) == 1.0 and FlatTyre.radius_mult(0.55) < 1.0 and is_equal_approx(FlatTyre.radius_mult(0.0), 1.0 - FlatTyre.SIDEWALL_SAG), "a soft tyre sits lower, an empty one by SIDEWALL_SAG")
	var w := Wheel.new()
	FlatTyre.write_pressure(w, 1.0, 2.2, 2.2, 0.31)
	_check(w.pressure_stiffness_mult == 1.0 and w.pressure_grip_mult == 1.0 and w.pressure_roll_mult == 1.0 and is_equal_approx(w.tire_radius, 0.31), "full pressure writes the tuned tyre back exactly")
	FlatTyre.write_pressure(w, 0.55, 2.2, 2.2, 0.31)
	print("a tyre at 0.55 of 2.2 bar: stiffness x%.2f, grip x%.2f, rolling resistance x%.2f, radius %.1f mm less" % [w.pressure_stiffness_mult, w.pressure_grip_mult, w.pressure_roll_mult, (0.31 - w.tire_radius) * 1000.0])
	_check(w.pressure_stiffness_mult < 1.0 and w.pressure_grip_mult < 1.0 and w.pressure_roll_mult > 1.0 and w.tire_radius < 0.31, "at 0.55 the tyre is less stiff, grips less, rolls harder and is smaller")
	var stiff55 := w.pressure_stiffness_mult
	FlatTyre.write_pressure(w, 0.2, 2.2, 2.2, 0.31)
	_check(w.pressure_stiffness_mult < stiff55 and w.pressure_stiffness_mult > 0.9, "softer still at 0.2, and never a different tyre")
	var tuned := Wheel.new()
	tuned.set_tyre_setup(1.8, 2.2, 0.0, 0.0, 1.0)
	FlatTyre.write_pressure(w, 1.0, 1.8, 2.2, 0.31)
	_check(is_equal_approx(w.pressure_stiffness_mult, tuned.pressure_stiffness_mult) and is_equal_approx(w.pressure_grip_mult, tuned.pressure_grip_mult) and is_equal_approx(w.pressure_roll_mult, tuned.pressure_roll_mult), "a Tuner pressure survives: full pressure gives exactly what the Tuner set")
	FlatTyre.write_pressure(w, 0.05, 2.2, 2.2, 0.31)
	_check(w.pressure_grip_mult == 1.0 and w.pressure_roll_mult == 1.0 and w.pressure_stiffness_mult < 1.0, "on the rim the grip and the drag are the rim's own")
	w.free()
	tuned.free()

func _launch(p: PlayerCar, speed: float) -> void:
	p.global_transform = rest
	p.linear_velocity = Vector3.ZERO
	p.angular_velocity = Vector3.ZERO
	Harness.move_player_to_lane(p, Harness.lane_x(1))
	x0 = p.global_position.x
	Harness.launch_player(p, speed)
	t = 0
	roll_sum = 0.0
	roll_n = 0
	shake_max = 0.0

func _fresh(p: PlayerCar) -> void:
	GameSettings.set_damage(GameSettings.Damage.FULL)
	p.damage.garage_repair(null)
	p.health.repair()
	p.fuel.litres = FuelTank.CAPACITY_L

func _hold(throttle: float, handbrake := 0.0) -> Callable:
	return func(c: Vehicle) -> void:
		c.steering_input = 0.0
		c.throttle_input = throttle
		c.brake_input = 0.0
		c.handbrake_input = handbrake

func _soft(p: PlayerCar, i: int) -> void:
	_fresh(p)
	if i >= 0:
		p.damage.pressure[i] = CarDamage.LEAK_TO
		p.damage.rebuild_offsets()

func _pull_step(p: PlayerCar, name: String, next: Step, next_soft: int) -> void:
	if t >= hz * 5:
		drift[name] = p.global_position.x - x0
		_check(p.damage.hits == 0 and p.damage.kerb_strikes == 0, "%s: the car stayed on the road for the 5 s" % name)
		_soft(p, next_soft)
		_launch(p, 19.5)
		p.driver = _hold(0.25)
		step = next

func _physics_process(_delta: float) -> bool:
	tick += 1
	t += 1
	hz = Engine.physics_ticks_per_second
	if tick > hz * 240:
		return _end("timed out in %s" % Step.keys()[step])
	var p: PlayerCar = game.get("player") if game != null else null
	if p == null:
		return tick > hz * 10 and _end("Game never became ready")
	if not Harness.finite(p):
		return _end("non-finite car state in %s" % Step.keys()[step])
	shake_max = maxf(shake_max, p.wheel_shake)
	match step:
		Step.BOOT:
			if t >= hz:
				rest = p.global_transform
				print("car: %s" % PlayerCar.chassis_kind())
				_soft(p, -1)
				_launch(p, 0.0)
				p.driver = _hold(0.0)
				step = Step.LEAN
		Step.LEAN:
			# roll: the car's right-hand axis tips up when the left side sits lower
			if t > hz:
				roll_sum += p.global_transform.basis.x.y
				roll_n += 1
			if t >= hz * 2:
				roll[["base", "fl", "fr"][lean_i]] = roll_sum / maxf(roll_n, 1)
				lean_i += 1
				_soft(p, [0, 1, -1][lean_i - 1])
				if lean_i < 3:
					_launch(p, 0.0)
				else:
					print("lean, parked (right axis tipping up = left side lower): healthy %+.5f, front-left at 0.55 %+.5f, front-right at 0.55 %+.5f" % [roll["base"], roll["fl"], roll["fr"]])
					_check(roll["fl"] > roll["base"] + 0.0003 and roll["fr"] < roll["base"] - 0.0003, "the car leans to the soft corner")
					_launch(p, 19.5)
					p.driver = _hold(0.25)
					step = Step.PULL_BASE
		Step.PULL_BASE:
			_pull_step(p, "base", Step.PULL_FL, 0)
		Step.PULL_FL:
			if t == hz * 3:
				var w: Wheel = p.wheel_array[0]
				_check(w.tire_radius < p.front_tire_radius and w.pressure_stiffness_mult < p.wheel_array[1].pressure_stiffness_mult, "the soft front-left tyre is smaller and less stiff than the right one")
			_pull_step(p, "fl", Step.PULL_FR, 1)
		Step.PULL_FR:
			_pull_step(p, "fr", Step.WOBBLE_SLOW, -1)
			if step == Step.WOBBLE_SLOW:
				print("soft tyre pull, 5 s at ~70 km/h wheel straight: healthy %+.2f m, front-left at 0.55 %+.2f m, front-right at 0.55 %+.2f m (x: + is right)" % [drift["base"], drift["fl"], drift["fr"]])
				_check(drift["fl"] < drift["base"] - 0.3, "a soft front-left tyre pulls the car left")
				_check(drift["fr"] > drift["base"] + 0.3, "a soft front-right tyre pulls the car right")
				_check(absf(drift["fl"]) < 3.0 and absf(drift["fr"]) < 3.0, "the pull is one a driver can hold: under 3 m in 5 s with the wheel straight")
				# a rim 4 mm out of round, slow then fast
				p.damage.runout[0] = CarDamage.RUNOUT_MAX
				p.damage.rebuild_offsets()
				_launch(p, 12.5)
				p.driver = Harness.lane_driver(Harness.lane_x(1), 0.2, 12.5)
		Step.WOBBLE_SLOW:
			if t == 3:
				_check(p.wheel_array[1].tire_radius == p.front_tire_radius and p.wheel_array[1].pressure_stiffness_mult == p.wheel_array[0].pressure_stiffness_mult and p.wheel_array[1].pressure_roll_mult == p.wheel_array[0].pressure_roll_mult, "after the repair the tuned tyre is back exactly")
			if t >= hz * 4:
				shake["slow"] = shake_max
				_launch(p, 30.5)
				p.driver = Harness.lane_driver(Harness.lane_x(1), 0.5, 30.5)
				step = Step.WOBBLE_FAST
		Step.WOBBLE_FAST:
			if t >= hz * 4:
				shake["fast"] = shake_max
				print("bent rim, 4 mm: camera shake %.2f at 45 km/h, %.2f at 110 km/h" % [shake["slow"], shake["fast"]])
				_check(shake["slow"] > 0.0 and shake["fast"] > shake["slow"] * 2.0, "the wobble is felt, and more at speed")
				_check(absf(p.global_position.x - Harness.lane_x(1)) < 1.0, "the car still holds its lane with a bent rim (%.2f m off)" % absf(p.global_position.x - Harness.lane_x(1)))
				_fresh(p)
				_launch(p, 28.0)
				p.driver = _hold(0.0, 1.0)
				step = Step.SKID
		Step.SKID:
			if t > hz / 2 and p.current_speed() > 1.0:
				rear_turn_min = minf(rear_turn_min, absf(p.wheel_array[2].spin) * p.wheel_array[2].tire_radius / p.current_speed())
			if t >= hz * 3 or p.current_speed() < 4.0:
				print("  rear tread speed fell to %.2f of the car's speed" % rear_turn_min)
				print("handbrake skid from 100 km/h: flat spots %d, rear runout %.1f and %.1f mm, front %.1f and %.1f mm, %.1f s, down to %.0f km/h" % [p.damage.flat_spots, p.damage.runout[2] * 1000.0, p.damage.runout[3] * 1000.0, p.damage.runout[0] * 1000.0, p.damage.runout[1] * 1000.0, t / float(hz), p.current_speed() * 3.6])
				var locked := rear_turn_min < CarDamage.LOCKED_SHARE
				_check(locked or p.damage.flat_spots == 0, "wheels that kept turning (%.2f of the car's speed) get no flat spot" % rear_turn_min)
				_check(not locked or p.damage.flat_spots > 0 or t < hz * 2, "wheels that stayed locked get a flat spot")
				_check(p.damage.runout[0] == 0.0 and p.damage.runout[1] == 0.0, "the front wheels kept turning: no flat spot")
				_fresh(p)
				_launch(p, 25.0)
				p.driver = Harness.lane_driver(Harness.lane_x(1), 0.3, 25.0)
				p.damage.apply_kerb_strike(1, CarDamage.KERB_FREE_MS * CarDamage.RIM_STRIKE - 0.01)
				step = Step.LEAK
		Step.LEAK:
			if t >= hz * 20:
				var want := 1.0 - 20.0 * (1.0 - CarDamage.LEAK_TO) / CarDamage.LEAK_FAST_S
				var got: float = p.damage.offsets.get_wheel(1, DamageOffsets.PRESSURE_MULT)
				print("leak on the car, 20 s after a hard strike: pressure %.3f (expected %.3f), front-right radius %.1f mm less" % [got, want, (p.front_tire_radius - p.wheel_array[1].tire_radius) * 1000.0])
				_check(absf(got - want) < 0.01, "the car's tyre leaks as timed (%.3f vs %.3f)" % [got, want])
				_check(p.wheel_array[1].tire_radius < p.front_tire_radius and p.wheel_array[0].tire_radius == p.front_tire_radius, "only that wheel has gone down")
				_check(not p.limp.is_limping(), "a leak is not a limp")
				step = Step.DONE
		Step.DONE:
			return _end("")
	return false

func _end(why: String) -> bool:
	if why != "":
		failures.append(why)
		print("  FAIL: " + why)
	GameSettings.reset_defaults()
	print("tyre_damage: %s" % ("PASS" if failures.is_empty() else "%d failure(s)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
	return true
