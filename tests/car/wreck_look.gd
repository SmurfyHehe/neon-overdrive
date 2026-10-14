extends SceneTree

# The totalled look's pure rules (Roy 1555, 2026-10-14): scripts/car/wreck_look.gd
# and the CarDamage side (look_stage, head_lamp_dark, headlight_share,
# rattle_level). No game, no car.
# - stage 0 makes no smoke, no sparks, no lamp, no rattle floor
# - smoke rises with the stage; stage 2 smokes more on the throttle than off,
#   stage 3 and 4 smoke the same whatever the pedal; darker every stage
# - sparks only from stage 3 and over 40 km/h, more with speed, capped
# - the stage lamp: none under stage 2; from stage 2 the side that took the
#   most front damage (tie: left); never written into CarDamage.lamps and never
#   charged at the garage
# - the rattle floor rises with the stage and never lowers a louder rattle
# - the garage repair clears every look; "Looks only" keeps the look of a
#   meter it did not move (the stage is read from the number, nothing else)
# - a disabled CarDamage (sim-only car) shows nothing
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/car/wreck_look.gd

const WreckLook := preload("res://scripts/car/wreck_look.gd")
const TotalledMeter := preload("res://scripts/car/totalled_meter.gd")

var failures: Array[String] = []

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		print("  FAIL: " + what)

func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001

func _initialize() -> void:
	_stages()
	_smoke()
	_sparks()
	_lamp()
	_rattle()
	_repair()
	print("wreck_look: %s" % ("PASS" if failures.is_empty() else "%d failure(s)" % failures.size()))
	quit(0 if failures.is_empty() else 1)

func _stages() -> void:
	_check(WreckLook.stage(0.0) == 0, "stage 0 at 0")
	_check(WreckLook.stage(0.29) == 0, "stage 0 under 0.30")
	_check(WreckLook.stage(0.30) == 1, "stage 1 at 0.30")
	_check(WreckLook.stage(0.60) == 2, "stage 2 at 0.60")
	_check(WreckLook.stage(0.90) == 3, "stage 3 at 0.90")
	_check(WreckLook.stage(1.0) == 4, "stage 4 at 1.0")
	for m in [0.0, 0.3, 0.6, 0.9, 1.0]:
		_check(WreckLook.stage(m) == TotalledMeter.stage(m), "the look stage is the meter's stage at %.2f" % m)

func _smoke() -> void:
	_check(_near(WreckLook.smoke_rate(0, 0.0), 0.0) and _near(WreckLook.smoke_rate(0, 1.0), 0.0), "stage 0: no bonnet smoke")
	var last := 0.0
	for st in [1, 2, 3, 4]:
		var idle := WreckLook.smoke_rate(st, 0.0)
		_check(idle > last, "stage %d smokes more than the stage before off the throttle (%.1f > %.1f)" % [st, idle, last])
		last = idle
	_check(WreckLook.smoke_rate(2, 1.0) > WreckLook.smoke_rate(2, 0.0), "stage 2: more smoke on the throttle")
	_check(_near(WreckLook.smoke_rate(3, 1.0), WreckLook.smoke_rate(3, 0.0)), "stage 3: the pedal makes no difference")
	_check(_near(WreckLook.smoke_rate(4, 1.0), WreckLook.smoke_rate(4, 0.0)), "stage 4: the pedal makes no difference")
	_check(WreckLook.smoke_rate(2, 0.5) > WreckLook.smoke_rate(2, 0.0) and WreckLook.smoke_rate(2, 0.5) < WreckLook.smoke_rate(2, 1.0), "half throttle sits between")
	_check(_near(WreckLook.smoke_rate(2, 2.0), WreckLook.smoke_rate(2, 1.0)), "the pedal is clamped")
	_check(_near(WreckLook.smoke_dark(1), 0.0), "stage 1 is pale steam")
	_check(WreckLook.smoke_dark(2) > 0.0 and WreckLook.smoke_dark(3) > WreckLook.smoke_dark(2) and WreckLook.smoke_dark(4) >= WreckLook.smoke_dark(3), "darker every stage")
	_check(WreckLook.smoke_dark(4) <= 1.0, "darkness stays inside 0..1")
	_check(WreckLook.smoke_life(3) > WreckLook.smoke_life(1) and WreckLook.smoke_size(3) > WreckLook.smoke_size(1), "oil smoke lingers and is bigger than steam")
	_check(_near(WreckLook.smoke_rate(9, 1.0), WreckLook.smoke_rate(4, 1.0)) and _near(WreckLook.smoke_rate(-1, 1.0), 0.0), "stages out of range clamp")
	# the pool: the heaviest stage's smoke and sparks fit in TyreSmoke's ring with room for the tyres
	var live := WreckLook.smoke_rate(4, 1.0) * WreckLook.smoke_life(4) + WreckLook.SPARK_RATE * WreckLook.SPARK_LIFE
	print("live wreck puffs at stage 4 flat out: %.0f of %d" % [live, TyreSmoke.MAX_PUFFS])
	_check(live < TyreSmoke.MAX_PUFFS * 0.5, "the look leaves half the pool for the tyres (%.0f)" % live)

func _sparks() -> void:
	for st in [0, 1, 2]:
		_check(_near(WreckLook.spark_rate(st, 200.0), 0.0), "stage %d: no sparks at any speed" % st)
	_check(_near(WreckLook.spark_rate(3, 39.0), 0.0), "stage 3: no sparks under 40 km/h")
	_check(_near(WreckLook.spark_rate(3, 0.0), 0.0), "stage 3: none standing")
	var slow := WreckLook.spark_rate(3, 45.0)
	var fast := WreckLook.spark_rate(3, 80.0)
	_check(slow > 0.0 and fast > slow, "sparks rise with speed (%.1f, %.1f)" % [slow, fast])
	_check(_near(WreckLook.spark_rate(3, 200.0), WreckLook.SPARK_RATE), "capped at the full rate")
	_check(_near(WreckLook.spark_rate(4, 200.0), WreckLook.SPARK_RATE), "stage 4 sparks too")

func _lamp() -> void:
	_check(WreckLook.dark_lamp(0, 1.0, 0.0) == -1 and WreckLook.dark_lamp(1, 1.0, 0.0) == -1, "no stage lamp under stage 2")
	_check(WreckLook.dark_lamp(2, 0.2, 0.7) == 1, "stage 2: the right lamp when the right arm took more")
	_check(WreckLook.dark_lamp(2, 0.7, 0.2) == 0, "stage 2: the left lamp when the left arm took more")
	_check(WreckLook.dark_lamp(2, 0.0, 0.0) == 0, "a tie goes to the left")
	_check(WreckLook.dark_lamp(3, 0.0, 0.5) == 1 and WreckLook.dark_lamp(4, 0.0, 0.5) == 1, "stages 3 and 4 keep it")
	# the CarDamage side
	var d := CarDamage.new()
	_check(_near(d.headlight_share(), 1.0) and not d.head_lamp_dark(0) and not d.head_lamp_dark(1), "a fresh car: both lamps")
	d.totalled = 0.59
	_check(_near(d.headlight_share(), 1.0), "0.59: both lamps")
	d.totalled = 0.60
	d.parts[CarDamage.Part.STEER_FR] = 0.5
	_check(d.head_lamp_dark(1) and not d.head_lamp_dark(0), "0.60 with a right-side hit: the right lamp dark")
	_check(_near(d.headlight_share(), 0.5), "half the beam")
	_check(not d.lamps[CarDamage.Lamp.HEAD_R] and not d.lamps[CarDamage.Lamp.HEAD_L], "the stage lamp is never written into lamps")
	var price_before := d.repair_price()
	d.totalled = 0.0
	var price_after := d.repair_price()
	_check(price_before == price_after, "the stage lamp costs nothing at the garage (%d vs %d)" % [price_before, price_after])
	_check(_near(d.headlight_share(), 1.0), "meter back at 0: both lamps again")
	# a lamp really broken by a hit on the other side: both out
	d.totalled = 0.60
	d.lamps[CarDamage.Lamp.HEAD_L] = true
	_check(d.head_lamp_dark(0) and d.head_lamp_dark(1) and _near(d.headlight_share(), 0.0), "a broken left lamp plus the stage's right: no beam")
	# the save keeps the meter, so the look comes back with it
	var d2 := CarDamage.new()
	d2.from_dict(d.to_dict())
	_check(d2.look_stage() == 2 and d2.head_lamp_dark(1), "the look survives to_dict / from_dict")
	# a sim-only car shows nothing
	var d3 := CarDamage.new()
	d3.enabled = false
	d3.totalled = 1.0
	_check(d3.look_stage() == 0 and _near(d3.headlight_share(), 1.0), "a disabled CarDamage has no look")

func _rattle() -> void:
	_check(_near(WreckLook.rattle_floor(0), 0.0), "no rattle floor at stage 0")
	var last := 0.0
	for st in [1, 2, 3, 4]:
		var f := WreckLook.rattle_floor(st)
		_check(f > last and f <= 1.0, "stage %d rattle floor rises (%.2f)" % [st, f])
		last = f
	var d := CarDamage.new()
	_check(_near(d.rattle_level(), 0.0), "a fresh car does not rattle")
	d.totalled = 0.30
	_check(_near(d.rattle_level(), WreckLook.rattle_floor(1)), "stage 1 with no broken parts rattles at the floor")
	d.totalled = 0.90
	for i in d.parts.size():
		d.parts[i] = 1.0
	_check(d.rattle_level() >= 1.0, "a wrecked car at stage 3 rattles at full, not less")
	d.totalled = 0.0
	_check(d.rattle_level() >= 1.0, "the floor never lowers a louder rattle")

func _repair() -> void:
	var d := CarDamage.new()
	d.totalled = 0.95
	d.parts[CarDamage.Part.STEER_FL] = 0.6
	_check(d.look_stage() == 3 and d.head_lamp_dark(0), "stage 3 before the repair")
	d.garage_repair(null)
	_check(d.look_stage() == 0 and not d.head_lamp_dark(0) and _near(d.rattle_level(), 0.0), "the garage repair clears every look")
	# the station patch: 0.95 -> 0.60, the look thins to stage 2 and keeps the lamp
	d.totalled = 0.95
	d.parts[CarDamage.Part.STEER_FR] = 0.6
	d.station_patch(3)
	_check(_near(d.totalled, 0.60) and d.look_stage() == 2 and d.head_lamp_dark(1), "a station patch thins the look to stage 2, lamp still dark")
