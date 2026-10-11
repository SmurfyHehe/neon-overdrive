extends SceneTree

# The totalled meter's pure rules (TM1, 2026-10-11): scripts/car/totalled_meter.gd
# and the CarDamage side (scripts/car/car_damage.gd). No game, no car.
# - a hit's step by wall speed: 54 adds 0, 55 adds 0.30, 99 adds 0.30, 100 adds
#   0.60; one hit never adds more than 0.60; no randomness (same hit, same step)
# - the same object within 0.5 s of a counted hit counts once; a different
#   object, or the same one later, counts again; a bump does not start the window
# - roll steps per kind (car 0.25, m1_monster 0.20, l1_lowrider 0.50)
# - stages at 0.30 / 0.60 / 0.90 / 1.0
# - the difficulty factor is 1.0 on all three, "Looks only" is not on this base
# - the meter is kept inside 0..1 and survives to_dict / from_dict; the garage
#   sets it to 0; a restart carries it (carry_over / take_carried)
# - the station patch: 0.95 -> 0.60 once a night, 0.85 stays 0.85
# - the tow row: from 0.60 or in limp, never in a chase
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/car/totalled_meter.gd

const TotalledMeter := preload("res://scripts/car/totalled_meter.gd")
const WreckRules := preload("res://scripts/car/wreck_rules.gd")

var failures: Array[String] = []

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		print("  FAIL: " + what)

func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001

func _initialize() -> void:
	_steps()
	_same_hit()
	_rolls()
	_stages()
	_settings()
	_damage_side()
	print("totalled_meter: %s" % ("PASS" if failures.is_empty() else "%d failure(s)" % failures.size()))
	quit(0 if failures.is_empty() else 1)

func _steps() -> void:
	var T := TotalledMeter
	_check(T.step_for_hit(0.0) == 0.0, "no hit, no step")
	_check(T.step_for_hit(54.0) == 0.0, "a 54 km/h wall adds 0")
	_check(T.step_for_hit(54.99) == 0.0, "just under the line adds 0")
	_check(_near(T.step_for_hit(55.0), 0.30), "a 55 km/h wall adds 0.30")
	_check(_near(T.step_for_hit(99.0), 0.30), "a 99 km/h wall adds 0.30")
	_check(_near(T.step_for_hit(99.99), 0.30), "just under 100 adds 0.30")
	_check(_near(T.step_for_hit(100.0), 0.60), "a 100 km/h wall adds 0.60")
	_check(_near(T.step_for_hit(400.0), 0.60), "one hit never adds more than 0.60")
	_check(_near(T.scaled(5.0), 0.60), "even a stray big step is capped at one hit's worth")
	_check(T.step_for_hit(80.0) == T.step_for_hit(80.0), "the same hit gives the same step")
	_check(WreckRules.WRECK_KMH == 55.0 and WreckRules.BIG_HIT_KMH == 100.0, "the lines are 55 and 100 km/h")
	var m := 0.0
	for i in 3:
		m = T.add(m, 0.30)
	_check(_near(m, 0.90) and not T.is_totalled(m), "three 0.30 hits are 0.90, not totalled")
	m = T.add(m, 0.30)
	_check(_near(m, 1.0) and T.is_totalled(m), "a fourth totals the car, kept at 1.0")
	_check(T.add(0.9, 0.6) == 1.0 and T.add(0.1, -5.0) == 0.0, "the meter stays inside 0..1")

func _same_hit() -> void:
	var T := TotalledMeter
	var t := T.new()
	var m := t.after_hit(0.0, 80.0, 7, 10.0)
	_check(_near(m, 0.30), "the first hit counts")
	m = t.after_hit(m, 80.0, 7, 10.3)
	_check(_near(m, 0.30), "the same object 0.3 s later is the same hit")
	m = t.after_hit(m, 120.0, 7, 10.49)
	_check(_near(m, 0.30), "even a harder contact inside the window is the same hit")
	m = t.after_hit(m, 80.0, 8, 10.3)
	_check(_near(m, 0.60), "another object counts at once")
	m = t.after_hit(m, 80.0, 8, 10.8)
	_check(_near(m, 0.90), "the same object 0.5 s after a counted hit counts again")
	var b := T.new()
	var bm := b.after_hit(0.0, 30.0, 3, 0.0)
	bm = b.after_hit(bm, 80.0, 3, 0.1)
	_check(_near(bm, 0.30), "a bump does not start the window")
	_check(T.new().after_hit(0.0, 54.0, 0, 0.0) == 0.0, "a 54 km/h hit adds nothing through the object path either")

func _rolls() -> void:
	var T := TotalledMeter
	_check(_near(T.step_for_roll("car"), 0.25), "a car roll adds 0.25")
	_check(_near(T.step_for_roll("m1_monster"), 0.20), "a monster truck roll adds 0.20")
	_check(_near(T.step_for_roll("l1_lowrider"), 0.50), "a lowrider roll adds 0.50")
	_check(_near(T.step_for_roll("p1_coupe"), 0.25), "any other car rolls like a car")
	_check(not T.ROLL_STEP.has("bike") and not T.ROLL_STEP.has("trike"), "bikes and the trike are not built: no rows yet")

func _stages() -> void:
	var T := TotalledMeter
	_check(T.STAGE_AT == [0.30, 0.60, 0.90, 1.0], "the stages start at 0.30 / 0.60 / 0.90 / 1.0")
	_check(T.stage(0.0) == 0 and T.stage(0.29) == 0, "under 0.30 is stage 0")
	_check(T.stage(0.30) == 1 and T.stage(0.59) == 1, "0.30 is stage 1")
	_check(T.stage(0.60) == 2 and T.stage(0.89) == 2, "0.60 is stage 2")
	_check(T.stage(0.90) == 3 and T.stage(0.99) == 3, "0.90 is stage 3")
	_check(T.stage(1.0) == 4, "1.0 is stage 4: totalled")
	var m := 0.0
	for i in 3:
		m += 0.30  # float sums: 0.3 + 0.3 + 0.3 is 0.8999999
	_check(T.stage(m) == 3, "three 0.30 hits are stage 3 despite float sums")

func _settings() -> void:
	var T := TotalledMeter
	_check(T.DIFFICULTY_MULT == {"daily": 1.0, "weekend": 1.0, "racer": 1.0}, "every difficulty is 1.0 until Roy decides")
	_check(T.difficulty_mult() == 1.0, "the factor in use is 1.0")
	_check(T.counts(), "the meter counts (Damage: Full)")
	# TODO(DP4a+DP7): when the Damage setting exists, add a test that "Looks only"
	# adds nothing and can never total the car, and "Light" counts in full.

func _damage_side() -> void:
	var D := CarDamage
	var d := D.new()
	d.totalled = 0.7
	var copy := D.new()
	copy.from_dict(d.to_dict())
	_check(_near(copy.totalled, 0.7), "the meter survives to_dict / from_dict")
	copy.from_dict({"totalled": 5.0})
	_check(copy.totalled == 1.0, "a bad saved value stays inside 0..1")
	# the garage
	d.totalled = 0.8
	d.garage_repair(null)
	_check(d.totalled == 0.0, "garage_repair sets the meter to 0")
	# a restart carries it, once
	d.totalled = 0.45
	D.carry_over(d)
	var fresh := D.new()
	fresh.take_carried()
	_check(_near(fresh.totalled, 0.45), "a restart carries the meter to the new car")
	var again := D.new()
	again.take_carried()
	_check(again.totalled == 0.0, "the carried meter is taken once")
	# the station patch
	var s := D.new()
	s.totalled = 0.95
	_check(s.station_patch(4) and _near(s.totalled, 0.60), "a station patch takes 0.95 down to 0.60")
	s.totalled = 0.95
	_check(not s.station_patch(4) and _near(s.totalled, 0.95), "only one patch a night, meter included")
	_check(s.station_patch(5) and _near(s.totalled, 0.60), "a new night, a new patch")
	var low := D.new()
	low.totalled = 0.85
	_check(not low.station_patch(1) and _near(low.totalled, 0.85), "0.85 is under the patch's reach and stays")
	var both := D.new()
	both.totalled = 0.9
	both.parts[D.Part.RADIATOR] = 0.9
	_check(both.station_patch(2) and _near(both.totalled, 0.60) and both.part(D.Part.RADIATOR) < D.FREE_BELOW, "one patch does the radiator and the meter")
	# the tow row
	var t := D.new()
	t.totalled = 0.59
	_check(not t.tow_offered(false, false), "no tow below 0.60 on a healthy car")
	t.totalled = 0.60
	_check(t.tow_offered(false, false), "the tow is offered at 0.60")
	_check(not t.tow_offered(false, true), "no tow in a chase")
	t.totalled = 0.0
	_check(t.tow_offered(true, false) and not t.tow_offered(true, true), "a limping car can call a tow, not in a chase")
