extends SceneTree

# Kerb strike and kerb grip group test (pavements steps 3 and 4, 2026-10-10).
#
# Asserts (exit code 1 on failure), all from raw numbers, no sim:
# - CarDamage.apply_kerb_strike: nothing at or under KERB_FREE_MS; above it
#   the struck corner takes (approach - free) x KERB_DAMAGE_PER_MS (a front
#   corner's steering arm, a rear corner's spring), the body a share, the
#   counters move; a disabled model takes nothing; a 100 % arm bends the
#   wheel's toe by MAX_TOE_BEND
# - CarSpec.apply gives every car (player cars, traffic, the worn coupe) a
#   "Kerb" and a "Grass" entry in all five surface dictionaries, derived from
#   the spec's own "Dirt", and leaves a "Kerb" entry the spec already has
#
# Run: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/car/kerb_strike.gd

var fails := 0
var checks := 0

func _check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL ", msg)

func _near(a: float, b: float, msg: String) -> void:
	_check(absf(a - b) < 1e-4, "%s: %.4f, expected %.4f" % [msg, a, b])

func _initialize() -> void:
	_damage()
	_surfaces()
	print("kerb_strike: %d checks, %d failures" % [checks, fails])
	quit(1 if fails > 0 else 0)

func _damage() -> void:
	var d := CarDamage.new()
	d.apply_kerb_strike(0, CarDamage.KERB_FREE_MS)
	d.apply_kerb_strike(1, 2.0)
	d.apply_kerb_strike(2, -6.0)  # moving away from the kerb
	_check(d.kerb_strikes == 0 and not d.warning(), "a slow mount or a retreat counted as a strike")
	_near(d.part(CarDamage.Part.STEER_FL), 0.0, "front arm under the free speed")

	d.apply_kerb_strike(0, CarDamage.KERB_FREE_MS + 4.0)
	var amount := 4.0 * CarDamage.KERB_DAMAGE_PER_MS
	_near(d.part(CarDamage.Part.STEER_FL), amount, "FL arm after a strike 4 m/s over")
	_near(d.part(CarDamage.Part.BODY), amount * CarDamage.KERB_BODY_SHARE, "body share")
	_near(d.part(CarDamage.Part.STEER_FR), 0.0, "the other front arm untouched")
	_check(d.kerb_strikes == 1 and absf(d.last_kerb_strike - 9.0) < 1e-4, "strike counters %d / %.1f" % [d.kerb_strikes, d.last_kerb_strike])

	d.apply_kerb_strike(2, 12.0)
	_near(d.part(CarDamage.Part.SUSP_RL), 7.0 * CarDamage.KERB_DAMAGE_PER_MS, "RL spring after a rear strike")
	_check(d.spring_mult(2) < 1.0 or d.part(CarDamage.Part.SUSP_RL) < CarDamage.FREE_BELOW, "rear spring mult")

	# a hard strike bends the arm all the way: toe at MAX_TOE_BEND, clamped at 1.0
	d.apply_kerb_strike(1, 40.0)
	_near(d.part(CarDamage.Part.STEER_FR), 1.0, "FR arm clamps at 1")
	_near(d.toe_offset(1), -CarDamage.MAX_TOE_BEND, "bent right wheel's toe")

	var off := CarDamage.new()
	off.enabled = false
	off.apply_kerb_strike(0, 30.0)
	_check(off.kerb_strikes == 0 and off.part(CarDamage.Part.STEER_FL) == 0.0, "a disabled model took a strike")

	# a strike on the repair list gets priced like any steering arm
	_check(d.repair_price() > 0, "a struck car has no repair price")

func _surfaces() -> void:
	var specs := {"coupe": CarSpec.coupe_default(), "worn": CarSpec.coupe_worn(), "traffic": CarSpec.traffic_default()}
	for k in PlayerCars.KINDS:
		specs[String(k.id)] = CarSpec.player_spec(String(k.id))
	for kind in NpcCarBuilder.KINDS:
		specs["npc " + String(kind)] = CarSpec.npc_spec(String(kind))
	for name in specs:
		var v := Vehicle.new()
		CarSpec.apply(v, specs[name])
		for key in CarSpec.SURFACE_KEYS:
			var dict: Dictionary = v.get(key)
			_check(dict.has("Kerb") and dict.has("Grass") and dict.has("Dirt"), "%s: %s lacks Kerb/Grass (%s)" % [name, key, str(dict.keys())])
			if dict.has("Kerb") and dict.has("Dirt"):
				_near(float(dict["Kerb"]), float(dict["Dirt"]) * float(CarSpec.KERB_SURFACE[key]), "%s %s Kerb" % [name, key])
		v.free()
	# an explicit Kerb entry stays
	var spec := CarSpec.coupe_default()
	spec["coefficient_of_friction"] = {"Road": 1.2, "Dirt": 0.9, "Kerb": 0.5}
	var v2 := Vehicle.new()
	CarSpec.apply(v2, spec)
	_near(float(v2.coefficient_of_friction["Kerb"]), 0.5, "explicit Kerb friction")
	_check(v2.coefficient_of_friction.has("Grass"), "Grass still derived next to an explicit Kerb")
	v2.free()
