extends SceneTree

# The Damage setting, difficulty and the radiator heat window (briefs DP4a and
# DP7, 2026-10-11), headless and silent, scripted driver.
# Unit part (no car):
# - Looks only: a big hit leaves the offsets neutral while the lamps break and
#   the parts, repair bill, steam and rattle are all still there
# - Light: every offset is half of Full's; switching the setting rebuilds the
#   offsets at once
# - difficulty: damage per hit x0.6 / x1.0 / x1.3 (wall hits and kerb
#   strikes), the auto-trim share and effects-at-once numbers, a harder
#   difficulty cools worse
# - the same hit always does the same damage
# - a radiator sets no limp of its own on any difficulty
# - the [game] settings save and load "damage" and "difficulty" by name
# Drive part (Game.tscn, straight road, no traffic): the heat window. With a
# 100 % radiator, from 120 km/h at full throttle, the seconds until the engine
# reaches PowertrainHealth.LIMP_C must be within 15 s of each difficulty's
# heat_window_s; at 60 % throttle on Weekend Warrior it must take at least
# twice the full-throttle time.
#
# NEON_HEAT_SWEEP=<cooling multipliers, comma separated> skips the checks and
# prints the full-throttle time for each value instead (how COOLING_LOSS and
# the cooling factors were tuned), e.g. NEON_HEAT_SWEEP=0.3,0.2,0.1.
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --audio-driver Dummy --path . -s res://tests/car/damage_settings.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const DamageOffsets := preload("res://scripts/car/damage_offsets.gd")
const DamageDifficulty := preload("res://scripts/car/damage_difficulty.gd")

const START_MS := 33.3          # 120 km/h
const WINDOW_TOLERANCE_S := 15.0
const GENTLE_THROTTLE := 0.6
const TRIAL_CAP_S := 260.0

var game: Node
var tick := 0
var t := 0
var hz := 60
var failures: Array[String] = []
var rest := Transform3D()
var booted := false

## Each trial: difficulty index, throttle, cooling multiplier forced (< 0 =
## the car's own), and the seconds it took (-1 = never within the cap).
var trials: Array[Dictionary] = []
var trial_i := -1
var sweep := false
var speed_sum := 0.0
var limp_tick := -1
var load_sum := 0.0

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		print("  FAIL: " + what)

func _initialize() -> void:
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	var sweep_env := OS.get_environment("NEON_HEAT_SWEEP")
	if sweep_env != "":
		sweep = true
		for v in sweep_env.split(",", false):
			trials.append({"difficulty": DamageDifficulty.WEEKEND_WARRIOR, "throttle": float(OS.get_environment("NEON_HEAT_THROTTLE")) if OS.get_environment("NEON_HEAT_THROTTLE") != "" else 1.0, "cooling": float(v), "secs": -1.0})
	else:
		_unit_tests()
		for d in [DamageDifficulty.WEEKEND_WARRIOR, DamageDifficulty.DAILY_DRIVER, DamageDifficulty.RACER]:
			trials.append({"difficulty": d, "throttle": 1.0, "cooling": -1.0, "secs": -1.0})
		trials.append({"difficulty": DamageDifficulty.WEEKEND_WARRIOR, "throttle": GENTLE_THROTTLE, "cooling": -1.0, "secs": -1.0})
	game = Harness.boot(self, 0, 150.0, 7)

func _hit(mode: int, difficulty: int, dv: Vector3) -> CarDamage:
	var d := CarDamage.new()
	d.mode = mode
	d.difficulty = difficulty
	d.apply_hit(dv)
	return d

func _unit_tests() -> void:
	var D := CarDamage
	var WW := DamageDifficulty.WEEKEND_WARRIOR
	_check(GameSettings.damage == GameSettings.Damage.FULL and GameSettings.difficulty == WW, "defaults: Full damage, Weekend Warrior")
	_check(", ".join(GameSettings.DAMAGE_NAMES) == "Full, Light, Looks only", "the Damage row reads Full / Light / Looks only")

	# Looks only: a big front hit, then a big rear one
	var looks := _hit(GameSettings.Damage.LOOKS_ONLY, WW, Vector3(0, 0, 25.0))
	looks.apply_hit(Vector3(4.0, 0, -25.0))
	_check(looks.offsets.is_neutral(), "Looks only: the offsets are neutral after two big hits")
	_check(looks.lamps[D.Lamp.HEAD_L] and looks.lamps[D.Lamp.HEAD_R] and looks.headlight_share() == 0.0, "Looks only: the head lamps still break")
	_check(looks.part(D.Part.RADIATOR) > 0.9 and looks.part(D.Part.SUSP_RL) > D.FREE_BELOW, "Looks only: the parts still take the damage")
	_check(looks.repair_price() > 0 and looks.steam_rate() > 0.0 and looks.rattle_level() > 0.0 and looks.warning(), "Looks only: repair bill, steam, rattle and the DMG lamp stay")
	looks.apply_kerb_strike(0, 20.0)
	_check(looks.offsets.is_neutral() and looks.kerb_strikes == 1, "Looks only: a kerb strike counts but bends nothing you can feel")

	# Light: half of Full, slot by slot
	var full := _hit(GameSettings.Damage.FULL, WW, Vector3(0, 0, 25.0))
	full.apply_hit(Vector3(4.0, 0, -25.0))
	var light := _hit(GameSettings.Damage.LIGHT, WW, Vector3(0, 0, 25.0))
	light.apply_hit(Vector3(4.0, 0, -25.0))
	_check(full.parts == light.parts, "Light: the parts take the same damage as Full")
	_check(not full.offsets.is_neutral(), "Full: the same hits give offsets")
	var changed := 0
	var halves := true
	for i in DamageOffsets.SIZE:
		var n := DamageOffsets.neutral_value(i)
		var f := full.offsets.data[i] - n
		var l := light.offsets.data[i] - n
		if f != 0.0:
			changed += 1
		if absf(l - f * 0.5) > 1.0e-6:
			halves = false
	_check(changed >= 4 and halves, "Light: each of the %d changed offsets is half of Full's" % changed)
	_check(light.lamps == full.lamps and light.repair_price() == full.repair_price(), "Light: same lamps and repair bill as Full")
	# changeable any time
	full.sync_settings(GameSettings.Damage.LOOKS_ONLY, WW)
	_check(full.offsets.is_neutral(), "switching to Looks only neutralises the offsets at once")
	full.sync_settings(GameSettings.Damage.LIGHT, WW)
	_check(full.offsets.data == light.offsets.data, "switching to Light gives Light's offsets")
	full.sync_settings(GameSettings.Damage.FULL, WW)
	_check(is_equal_approx(full.offsets.get_car(DamageOffsets.COOLING_MULT), full.cooling_mult()), "and back to Full gives the full offsets")

	# difficulty: damage per hit and trim
	var mults := [0.6, 1.0, 1.3]
	var trims := [0.85, 0.70, 0.40]
	var at_once := [2, 3, 3]
	var base := _hit(0, WW, Vector3(0, 0, 8.0))
	for k in 3:
		var d := _hit(0, k, Vector3(0, 0, 8.0))
		var name: String = DamageDifficulty.NAMES[k]
		_check(is_equal_approx(d.damage_mult(), mults[k]), "%s: damage per hit x%.1f" % [name, mults[k]])
		_check(absf(d.part(D.Part.RADIATOR) - base.part(D.Part.RADIATOR) * mults[k]) < 1.0e-6, "%s: the radiator takes %.3f (x%.1f of %.3f)" % [name, d.part(D.Part.RADIATOR), mults[k], base.part(D.Part.RADIATOR)])
		_check(absf(d.part(D.Part.STEER_FL) - base.part(D.Part.STEER_FL) * mults[k]) < 1.0e-6, "%s: the front-left arm scales the same" % name)
		_check(is_equal_approx(d.auto_trim_share(), trims[k]), "%s: auto-trim share %.2f" % [name, trims[k]])
		_check(d.effects_at_once() == at_once[k], "%s: %d handling effects at once" % [name, at_once[k]])
		var kerb := CarDamage.new()
		kerb.difficulty = k
		kerb.apply_kerb_strike(1, 12.0)
		_check(absf(kerb.part(D.Part.STEER_FR) - (12.0 - D.KERB_FREE_MS) * D.KERB_DAMAGE_PER_MS * mults[k]) < 1.0e-6, "%s: a kerb strike scales the same" % name)
		var rad := CarDamage.new()
		rad.difficulty = k
		rad.parts[D.Part.RADIATOR] = 1.0
		rad.rebuild_offsets()
		_check(rad.engine_cap_kmh() == INF and not rad.is_engine_dead(), "%s: a 100 %% radiator sets no limp of its own" % name)
		_check(rad.cooling_mult() > 0.0 and rad.cooling_mult() < 1.0, "%s: a 100 %% radiator still cools a little (%.3f)" % [name, rad.cooling_mult()])
	var cool := []
	for k in 3:
		var r := CarDamage.new()
		r.difficulty = k
		r.parts[D.Part.RADIATOR] = 1.0
		cool.append(r.cooling_mult())
	_check(cool[0] > cool[1] and cool[1] > cool[2], "a harder difficulty cools worse (%.3f > %.3f > %.3f)" % cool)
	_check(DamageDifficulty.row(99) == DamageDifficulty.row(DamageDifficulty.DEFAULT), "an unknown difficulty reads as the default")
	# no random damage
	var a := _hit(0, WW, Vector3(3.0, 0, 11.0))
	var b := _hit(0, WW, Vector3(3.0, 0, 11.0))
	_check(a.parts == b.parts and a.lamps == b.lamps and a.offsets.data == b.offsets.data, "the same hit always does the same damage")

	# saved with the other game settings, by name
	var real_path := AudioSettings.path
	AudioSettings.path = "user://damage_settings_test.cfg"
	GameSettings.set_damage(GameSettings.Damage.LOOKS_ONLY)
	GameSettings.set_difficulty(DamageDifficulty.RACER)
	_check(GameSettings.save_settings(), "the game settings save")
	GameSettings.reset_defaults()
	GameSettings.load_settings()
	_check(GameSettings.damage == GameSettings.Damage.LOOKS_ONLY and GameSettings.difficulty == DamageDifficulty.RACER, "Damage and difficulty come back from the file")
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)
	_check(cfg.get_value("game", "damage", "") == "Looks only", "saved as the name 'Looks only'")
	cfg.set_value("game", "damage", "Nonsense")
	cfg.save(AudioSettings.path)
	GameSettings.load_settings()
	_check(GameSettings.damage == GameSettings.Damage.FULL, "an unknown saved value reads as Full")
	GameSettings.reset_defaults()
	GameSettings.save_settings()
	AudioSettings.path = real_path

func _start_trial(p: PlayerCar) -> void:
	trial_i += 1
	t = 0
	speed_sum = 0.0
	load_sum = 0.0
	limp_tick = -1
	if trial_i >= trials.size():
		return
	var tr := trials[trial_i]
	GameSettings.set_damage(GameSettings.Damage.FULL)
	GameSettings.set_difficulty(tr["difficulty"])
	p.damage.garage_repair(null)
	p.health.repair()
	p.fuel.litres = FuelTank.CAPACITY_L
	p.damage.sync_settings(GameSettings.damage, GameSettings.difficulty)
	p.damage.parts[CarDamage.Part.RADIATOR] = 1.0
	p.damage.rebuild_offsets()
	if tr["cooling"] >= 0.0:
		p.damage.offsets.set_car(DamageOffsets.COOLING_MULT, tr["cooling"])
	tr["cooling_used"] = p.damage.offsets.get_car(DamageOffsets.COOLING_MULT)
	p.global_transform = rest
	p.angular_velocity = Vector3.ZERO
	Harness.move_player_to_lane(p, Harness.lane_x(1))
	Harness.launch_player(p, START_MS)
	p.driver = Harness.lane_driver(Harness.lane_x(1), tr["throttle"])

func _physics_process(_delta: float) -> bool:
	tick += 1
	t += 1
	hz = Engine.physics_ticks_per_second
	var p: PlayerCar = game.get("player") if game != null else null
	if p == null:
		return tick > hz * 10 and _end("Game never became ready")
	if not Harness.finite(p):
		return _end("non-finite car state in trial %d" % trial_i)
	if not booted:
		if t >= hz:
			booted = true
			rest = p.global_transform
			p.set_transmission_mode(PlayerCar.Transmission.AUTO)
			print("car: %s" % PlayerCar.chassis_kind())
			_start_trial(p)
		return false
	if trial_i >= trials.size():
		return _report()
	var tr := trials[trial_i]
	speed_sum += p.current_speed()
	load_sum += p.health.engine_load
	if limp_tick < 0 and p.health.engine_temp >= PowertrainHealth.LIMP_C:
		limp_tick = t
	var limped := limp_tick >= 0
	var secs := (limp_tick if limped else t) / float(hz)
	# two more ticks after LIMP_C, so LimpMode has seen the temperature
	if (limped and t >= limp_tick + 2) or secs >= TRIAL_CAP_S:
		tr["secs"] = secs if limped else -1.0
		tr["temp"] = p.health.engine_temp
		tr["kmh"] = speed_sum / t * 3.6
		tr["load"] = load_sum / t
		tr["limp"] = LimpMode.cause_name(p.limp.cause)
		print("%s, throttle %.0f %%, cooling x%.3f: %s (engine %.0f C, average %.0f km/h, average load %.2f, limp cause '%s')" % [
			DamageDifficulty.NAMES[tr["difficulty"]], tr["throttle"] * 100.0, tr["cooling_used"],
			("LIMP_C after %.1f s" % secs) if limped else ("not at LIMP_C after %.0f s" % secs),
			tr["temp"], tr["kmh"], tr["load"], tr["limp"]])
		_start_trial(p)
	return false

func _report() -> bool:
	if sweep:
		return _end("")
	var full_ww := -1.0
	for tr in trials:
		var name: String = DamageDifficulty.NAMES[tr["difficulty"]]
		var target := float(DamageDifficulty.row(tr["difficulty"])["heat_window_s"])
		if tr["throttle"] >= 1.0:
			if tr["difficulty"] == DamageDifficulty.WEEKEND_WARRIOR:
				full_ww = tr["secs"]
			_check(tr["secs"] >= 0.0 and absf(tr["secs"] - target) <= WINDOW_TOLERANCE_S, "%s: heat window %.1f s, target %.0f s +-%.0f" % [name, tr["secs"], target, WINDOW_TOLERANCE_S])
			_check(tr["limp"] == "OVERHEAT", "%s: the limp at the end of the window is the overheat limp ('%s')" % [name, tr["limp"]])
		else:
			_check(tr["secs"] < 0.0 or tr["secs"] >= 2.0 * full_ww, "%s at %.0f %% throttle: %.1f s must be at least twice the full-throttle %.1f s" % [name, tr["throttle"] * 100.0, tr["secs"], full_ww])
	return _end("")

func _end(why: String) -> bool:
	if why != "":
		failures.append(why)
		print("  FAIL: " + why)
	GameSettings.reset_defaults()
	print("damage_settings: %s" % ("PASS" if failures.is_empty() else "%d failure(s)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
	return true
