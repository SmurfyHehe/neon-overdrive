extends SceneTree

# Fix the car (scripts/car/fix_car.gd), headless, no game boot:
# - a hit breaks parts and a lamp; fix() puts every part and lamp back, and
#   warning() goes false
# - the engine, brakes and tyres that were hurt come back to new (health)
# - the damage's motion memory is cleared, so the next step after the fix does
#   not read a hit
# - a player with no health or damage, and a null player, do nothing and do not
#   error
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --audio-driver Dummy --path . -s res://tests/car/fix_car.gd

const FixCar := preload("res://scripts/car/fix_car.gd")

class StubPlayer:
	extends RefCounted
	var health = null
	var damage = null

var failures: Array[String] = []

func _initialize() -> void:
	var p := StubPlayer.new()
	p.health = PowertrainHealth.new()
	p.damage = CarDamage.new()
	p.damage.apply_hit(Vector3(0, 0, 20))
	p.health.engine_temp = 120.0
	p.health.tyre_wear[0] = 0.6
	_check(p.damage.warning(), "a hit leaves a warning before the fix")
	var hits_before: int = p.damage.hits

	FixCar.fix(p)

	_check(not p.damage.warning(), "the fix clears the warning")
	for i in CarDamage.Part.BODY + 1:
		_check(p.damage.parts[i] == 0.0, "part %d is back to 0" % i)
	for i in p.damage.lamps.size():
		_check(not p.damage.lamps[i], "lamp %d is fixed" % i)
	_check(p.health.engine_temp == 85.0, "engine temperature is back to service value")
	_check(p.health.tyre_wear[0] == 0.0, "tyre wear is back to new")
	_check(p.damage.hits == hits_before, "the fix does not count as a hit")
	# after forget_motion the velocity memory is zero, so a car at rest reads no hit
	p.damage.step_values(1.0 / 60.0, Vector3.ZERO, Basis(), true)
	_check(not p.damage.warning(), "the next step after the fix reads no hit")

	var empty := StubPlayer.new()
	FixCar.fix(empty)
	FixCar.fix(null)

	_end()

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		print("  FAIL: " + what)

func _end() -> void:
	print("fix_car: %s" % ("PASS" if failures.is_empty() else "%d failure(s)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
