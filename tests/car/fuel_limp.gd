extends SceneTree

# Fuel and limp mode (Stage C, 2026-10-09), headless and silent, scripted driver.
# Unit part (no car):
# - FuelTank: idle and full-load burn, refuel from the bank (full, short, empty
#   bank), the real start is a third of the tank
# - LimpMode: the slowest cause wins, caps and torque cuts never stack, the
#   throttle governor fades over the band
# Drive part (Game.tscn, straight road, no traffic), a sweep:
# - calibration: a mixed city cycle (pull, cruise, brake, idle); one full tank
#   must last 12-19 minutes (most of a 20-minute night). Prints the numbers.
# - for each gearbox (auto, semi, manual): run the tank dry at full throttle;
#   the car must keep crawling at 45-63 km/h, never above
# - dry above the cap (at ~110 km/h): it coasts down under the cap, no brake
# - dry AND overheated: the cap is fuel's 60, torque is 0.5 (not 0.5 x 0.5)
# - refuel from the bank while still hot: overheat's 80 takes over
# - refuel cool: limp ends and the car pulls past 70
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --audio-driver Dummy --path . -s res://tests/car/fuel_limp.gd

## Physics ticks per second, read from the engine (the game runs 120, run_tests 60).
var HZ := 60

class StubBank:
	extends RefCounted
	var bank := 0
	func _init(b: int) -> void:
		bank = b
	func spend_bank(amount: int) -> bool:
		if amount < 0 or amount > bank:
			return false
		bank -= amount
		return true

enum Step { BOOT, CAL, DRY_START, DRY_ROLL, DRY_RUN, DRY_STOP, OVER_PULL, OVER_COAST,
	HOT_DRY, HOT_REFUEL, COOL_REFUEL, DONE }

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var throttle := 0.0
var brake := 0.0
var hot := false
var pedal := 0.0
var x0 := 0.0

# calibration
var cal_litres0 := 0.0
var cal_ticks := 0
# gearbox sweep
var modes := [PlayerCar.Transmission.AUTO, PlayerCar.Transmission.SEMI, PlayerCar.Transmission.MANUAL]
var mode_i := 0
var dry_at := -1
var dry_max_kmh := 0.0
var dry_sum := 0.0
var dry_n := 0
var peak := 0.0
var under_once := false

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	_unit_tests()
	change_scene_to_file("res://Game.tscn")

func _unit_tests() -> void:
	var f := FuelTank.new()
	_check(is_equal_approx(f.litres, FuelTank.CAPACITY_L), "tests start with a full tank")
	_check(is_equal_approx(FuelTank.START_FRACTION, 1.0 / 3.0), "the real start is a third of a tank")
	var idle_min := FuelTank.CAPACITY_L / FuelTank.burn_rate(0.0) / 60.0
	var full_min := FuelTank.CAPACITY_L / FuelTank.burn_rate(1.0) / 60.0
	print("fuel: full tank lasts %.1f min idling, %.1f min flat out" % [idle_min, full_min])
	_check(full_min < idle_min, "full load must burn faster than idle")
	f.litres = 10.0
	f.step_values(10.0, 1.0, false)
	_check(is_equal_approx(f.litres, 10.0), "a stalled engine burns nothing")
	f.step_values(1.0e6, 1.0, true)
	_check(f.litres == 0.0 and f.is_empty(), "the tank stops at zero")
	# refuel: rich bank fills it, short bank buys what it can, empty bank nothing
	var rich := StubBank.new(10000)
	var got := f.refuel(rich)
	_check(is_equal_approx(f.litres, FuelTank.CAPACITY_L) and is_equal_approx(got, FuelTank.CAPACITY_L), "a rich bank fills the tank")
	_check(rich.bank == 10000 - int(FuelTank.CAPACITY_L) * FuelTank.PRICE_PER_LITRE, "the bank paid %d" % (10000 - rich.bank))
	_check(f.refuel(rich) == 0.0 and rich.bank == 10000 - int(FuelTank.CAPACITY_L) * FuelTank.PRICE_PER_LITRE, "a full tank buys nothing")
	f.litres = 0.0
	var short := StubBank.new(FuelTank.PRICE_PER_LITRE * 7 + 1)
	got = f.refuel(short)
	_check(is_equal_approx(got, 7.0) and short.bank == 1, "a short bank buys 7 L, bought %.1f, left %d" % [got, short.bank])
	var broke := StubBank.new(0)
	_check(f.refuel(broke) == 0.0 and is_equal_approx(f.litres, 7.0), "an empty bank changes nothing")
	f.litres = 0.0
	_check(is_equal_approx(f.refuel(StubBank.new(10000), 5.0), 5.0), "max_litres caps the fill")
	f.enabled = false
	f.litres = 0.0
	_check(not f.is_empty(), "a disabled tank never reads empty")

	var l := LimpMode.new()
	_check(l.update(false, 90.0) == INF and not l.is_limping(), "no cause, no limp")
	_check(l.throttle_scale(200.0) == 1.0, "no cap, full throttle")
	l.update(true, 90.0)
	_check(l.cap_kmh == LimpMode.FUEL_KMH and l.cause == LimpMode.Cause.FUEL, "dry tank caps at 60")
	l.update(false, PowertrainHealth.LIMP_C + 5.0)
	_check(l.cap_kmh == LimpMode.OVERHEAT_KMH and l.cause == LimpMode.Cause.OVERHEAT, "overheat alone caps at 80")
	l.update(true, PowertrainHealth.LIMP_C + 5.0)
	_check(l.cap_kmh == LimpMode.FUEL_KMH and l.active_causes == (LimpMode.Cause.FUEL | LimpMode.Cause.OVERHEAT), "fuel + overheat: slowest (60) wins")
	l.engine_damage_kmh = 40.0
	l.update(true, PowertrainHealth.LIMP_C + 5.0)
	_check(l.cap_kmh == 40.0 and l.cause == LimpMode.Cause.ENGINE, "engine damage at 40 beats fuel")
	l.engine_damage_kmh = 75.0
	l.update(true, 90.0)
	_check(l.cap_kmh == LimpMode.FUEL_KMH, "fuel 60 beats engine damage 75")
	_check(is_equal_approx(l.torque_mult(PowertrainHealth.TORQUE_FLOOR), minf(PowertrainHealth.TORQUE_FLOOR, LimpMode.LIMP_TORQUE)), "torque cuts take the worse, never the product")
	_check(is_equal_approx(l.torque_mult(1.0), LimpMode.LIMP_TORQUE), "limping uses LIMP_TORQUE")
	l.update(true, 90.0)
	_check(l.throttle_scale(40.0) == 1.0, "full throttle well under the cap")
	_check(is_equal_approx(l.throttle_scale(LimpMode.FUEL_KMH - LimpMode.GOV_BAND_KMH * 0.5), 0.5), "half throttle mid-band")
	_check(l.throttle_scale(70.0) == 0.0, "no throttle over the cap")

func _drive(c: PlayerCar) -> void:
	c.throttle_input = throttle
	c.brake_input = brake
	# keep the lane: back toward the start x, nose straight down -Z (+ steers left)
	var fx := -c.global_transform.basis.z.x
	c.steering_input = clampf(0.03 * (c.global_position.x - x0) + 1.5 * fx, -0.25, 0.25)
	c.clutch_input = pedal

func _kmh(p: PlayerCar) -> float:
	return p.current_speed() * 3.6

func _physics_process(_delta: float) -> bool:
	tick += 1
	HZ = Engine.physics_ticks_per_second
	if tick > HZ * 900:
		return _end("timed out in step %s" % Step.keys()[step])
	var game := current_scene
	if game == null or game.get("player") == null:
		return tick > 600 and _end("Game never became ready")
	var p: PlayerCar = game.player
	p.driver = _drive
	if hot:
		p.health.engine_temp = PowertrainHealth.LIMP_C + 8.0
	var t := tick - step_start
	var kmh := _kmh(p)
	match step:
		Step.BOOT:
			_check(p.fuel.enabled, "the player's tank should be on")
			p.set_transmission_mode(PlayerCar.Transmission.AUTO)
			x0 = p.global_position.x
			cal_litres0 = p.fuel.litres
			_go(Step.CAL)
		Step.CAL:
			# 30 s cycle x 4: pull 8 s, cruise at a third 10 s, brake 4 s, idle 8 s
			var c := t % (HZ * 30)
			throttle = 1.0 if c < HZ * 8 else (0.33 if c < HZ * 18 else 0.0)
			brake = 1.0 if c >= HZ * 18 and c < HZ * 22 else 0.0
			p.health.engine_temp = minf(p.health.engine_temp, 95.0)  # keep overheat out of it
			if t >= HZ * 120:
				var used := cal_litres0 - p.fuel.litres
				var lps := used / 120.0
				var tank_min := FuelTank.CAPACITY_L / maxf(lps, 1e-6) / 60.0
				print("fuel calibration: %.2f L in 120 s city cycle -> a full tank lasts %.1f min (night = 20 min), a third %.1f min" % [used, tank_min, tank_min / 3.0])
				_check(tank_min >= 12.0 and tank_min <= 19.0, "a full tank should last 12-19 min of city driving, got %.1f" % tank_min)
				throttle = 0.0
				brake = 1.0
				_go(Step.DRY_STOP)
		Step.DRY_STOP:
			throttle = 0.0
			brake = 1.0
			p.health.engine_temp = 90.0
			if absf(kmh) < 1.0 and t > HZ:
				if mode_i >= modes.size():
					p.set_transmission_mode(PlayerCar.Transmission.AUTO)
					p.fuel.litres = FuelTank.CAPACITY_L
					_go(Step.OVER_PULL)
				else:
					p.set_transmission_mode(PlayerCar.Transmission.AUTO)
					p.fuel.litres = FuelTank.CAPACITY_L
					brake = 0.0
					_go(Step.DRY_ROLL)
		Step.DRY_ROLL:
			# roll away in auto, then hand over to the gearbox under test at 35 km/h
			throttle = 1.0
			if kmh > 35.0:
				p.set_transmission_mode(modes[mode_i])
				p.fuel.litres = 0.25
				dry_at = -1
				under_once = false
				dry_max_kmh = 0.0
				dry_sum = 0.0
				dry_n = 0
				_go(Step.DRY_RUN)
			elif t > HZ * 20:
				return _end("never rolled away (mode %d) at %s, %.1f km/h" % [modes[mode_i], p.global_position, kmh])
		Step.DRY_RUN:
			throttle = 1.0
			# semi and manual: shift up to 3rd once (manual with the pedal in)
			if modes[mode_i] != PlayerCar.Transmission.AUTO:
				pedal = 1.0 if modes[mode_i] == PlayerCar.Transmission.MANUAL and t < HZ * 2 else 0.0
				if (t == 20 or t == 60) and p.gear < 3:
					p.manual_shift(1)
			p.health.engine_temp = minf(p.health.engine_temp, 100.0)
			if p.fuel.is_empty() and dry_at < 0:
				dry_at = t
			# dry above the cap it coasts down first; from the first time under, never above
			if dry_at >= 0 and kmh < LimpMode.FUEL_KMH:
				under_once = true
			if under_once:
				dry_max_kmh = maxf(dry_max_kmh, kmh)
				if t - dry_at > HZ * 25:
					dry_sum += kmh
					dry_n += 1
			if t > HZ * 45:
				var name: String = PlayerCar.TRANSMISSION_LETTERS[modes[mode_i]]
				var avg := dry_sum / maxf(dry_n, 1)
				print("dry tank, gearbox %s: crawl %.1f km/h (max %.1f), engine running %s, gear %d, x off lane %.1f m" % [name, avg, dry_max_kmh, p.engine_running, p.gear, p.global_position.x - x0])
				_check(dry_at >= 0, "%s: the tank never ran dry" % name)
				_check(under_once, "%s: never got under the cap" % name)
				_check(p.limp.cause == LimpMode.Cause.FUEL, "%s: limp cause should be fuel" % name)
				_check(avg >= 45.0 and avg <= 63.0, "%s: dry crawl should be 45-63 km/h, got %.1f" % [name, avg])
				_check(dry_max_kmh <= 64.0, "%s: never above the cap, peaked %.1f" % [name, dry_max_kmh])
				_check(p.gear >= 2, "%s: should crawl in 2nd or higher (not on the 1st-gear limiter), gear %d" % [name, p.gear])
				mode_i += 1
				_go(Step.DRY_STOP)
		Step.OVER_PULL:
			brake = 0.0
			throttle = 1.0
			p.health.engine_temp = minf(p.health.engine_temp, 100.0)
			if kmh > 110.0:
				p.fuel.litres = 0.0
				peak = kmh
				_go(Step.OVER_COAST)
			elif t > HZ * 40:
				return _end("could not reach 110 km/h for the coast-down")
		Step.OVER_COAST:
			throttle = 1.0
			p.health.engine_temp = minf(p.health.engine_temp, 100.0)
			_check(p.brake_input == 0.0, "the governor must not brake")
			if kmh < 62.0:
				print("dry at %.0f km/h: coasted under the cap in %.1f s" % [peak, t / float(HZ)])
				hot = true
				_go(Step.HOT_DRY)
			elif t > HZ * 120:
				return _end("dry at 110 km/h: still %.1f km/h after 120 s" % kmh)
		Step.HOT_DRY:
			throttle = 1.0
			if t == HZ * 20:
				print("dry + overheated: %.1f km/h, cap %.0f, cause %s, torque_mult %.2f" % [kmh, p.limp.cap_kmh, LimpMode.cause_name(p.limp.cause), p.torque_mult])
				_check(p.limp.cause == LimpMode.Cause.FUEL and p.limp.cap_kmh == LimpMode.FUEL_KMH, "dry + hot: fuel's cap wins")
				_check(is_equal_approx(p.torque_mult, minf(PowertrainHealth.TORQUE_FLOOR, LimpMode.LIMP_TORQUE)), "dry + hot: torque %.3f should be the worse cut, not the product" % p.torque_mult)
				_check(kmh <= 63.0 and kmh >= 40.0, "dry + hot: speed %.1f should sit under 60" % kmh)
				var bank := StubBank.new(1000)
				var got := p.fuel.refuel(bank)
				_check(got > 0.0 and bank.bank < 1000, "refuel must take Cred from the bank")
				_go(Step.HOT_REFUEL)
		Step.HOT_REFUEL:
			throttle = 1.0
			if t == HZ * 25:
				print("refuelled, still hot: %.1f km/h, cap %.0f, cause %s" % [kmh, p.limp.cap_kmh, LimpMode.cause_name(p.limp.cause)])
				_check(p.limp.cause == LimpMode.Cause.OVERHEAT, "hot after refuel: overheat should be the cause")
				_check(kmh > 66.0 and kmh <= LimpMode.OVERHEAT_KMH + 3.0, "hot after refuel: %.1f should rise to overheat's 80 cap" % kmh)
				hot = false
				p.health.engine_temp = 90.0
				_go(Step.COOL_REFUEL)
		Step.COOL_REFUEL:
			throttle = 1.0
			p.health.engine_temp = minf(p.health.engine_temp, 95.0)
			if kmh > 90.0:
				_check(not p.limp.is_limping(), "cool and fuelled: no limp")
				_go(Step.DONE)
			elif t > HZ * 30:
				return _end("cool and fuelled, still only %.1f km/h after 30 s (limping: %s)" % [kmh, p.limp.is_limping()])
		Step.DONE:
			return _end("")
	return false

func _go(next: Step) -> void:
	step = next
	step_start = tick

func _check(ok: bool, msg: String) -> void:
	if not ok and msg != "":
		failures.append(msg)

func _end(msg: String) -> bool:
	if msg != "":
		failures.append(msg)
	for f in failures:
		printerr("FAIL: ", f)
	print("fuel_limp: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
