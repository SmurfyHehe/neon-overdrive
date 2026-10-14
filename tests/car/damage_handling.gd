extends SceneTree

# Wheel-corner damage, caps and auto-trim (briefs DP1 + DP2, 2026-10-11),
# headless and silent, scripted keys.
# Unit part (no car):
# - each part alone at 100 % gives the table's offset, half way gives half,
#   25 % gives nothing; the rack and the brakes wait for 50 %
# - each cause hurts its parts: a rear corner hit the rear toe, a side hit the
#   camber on that side, a front hit the front springs and the rack, a corner
#   hit that brake, the third kerb strike and a hard landing the damper
# - the caps: four hurt parts give three effects, one hit adds at most 0.5,
#   an axle's toe adds stay inside +-0.02, the grip multipliers multiply to at
#   least 0.85
# - the fade: a hit reaches its offsets in exactly FADE_TICKS ticks; a repair
#   is at once
# - the same hits twice give the same parts and offsets
# Drive part (Game.tscn, straight flat road, no traffic):
# - DRIFT: 100 km/h, no keys, 10 s. Clean; front-left arm at 100 % with the
#   auto-trim share at 0.85, at 0.40 and at 0 (for the report); then repaired.
#   The car drifts toward the bent side, less at 0.85 than at 0.40, and the
#   repaired car holds the clean car's line. The median barrier is 4 m to the
#   left of the start lane and the car reaches it inside 10 s at 0.40 and
#   inside 5 s with no trim, so 0.85 against 0.40 is compared at 5 s and
#   0.40 against no trim at 2 s; the 10 s numbers are printed for all
# - BRAKE: front-left brake at 100 %: no turn while coasting, a turn toward
#   the healthy (right) side on the brakes, more than a clean car's
# - WHEEL: the cockpit wheel's rest angle is STEER_CENTRE with a bent arm
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 120 --audio-driver Dummy --path . -s res://tests/car/damage_handling.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const DamageOffsets := preload("res://scripts/car/damage_offsets.gd")

const SPEED := 100.0 / 3.6
const DRIFT_SECS := 10
const COAST_SECS := 2
const BRAKE_SECS := 2

enum Step { BOOT, CLEAN, ARM_85, ARM_40, ARM_0, REPAIRED, BRAKE_CLEAN, BRAKE_HURT, DONE }

var game: Node
var step := Step.BOOT
var t := 0
var tick := 0
var hz := 120
var failures: Array[String] = []
var x0 := 0.0
var rest := Transform3D()
var drift := {}
var drift_2s := {}
var drift_5s := {}
var turn_coast := {}
var turn_brake := {}
var keys := 0
## Ticks left of the stand-still before a run's launch (see _launch).
var settle_left := 0

func _initialize() -> void:
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	_unit_tests()
	game = Harness.boot(self, 0, 300.0, 4242)

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		print("  FAIL: " + what)

func _near(a: float, b: float, what: String, tol := 1e-5) -> void:
	_check(absf(a - b) <= tol, "%s (%.6f, want %.6f)" % [what, a, b])

## A CarDamage with one part set, offsets rebuilt.
func _one(p: int, amount: float) -> CarDamage:
	var d := CarDamage.new()
	d.parts[p] = amount
	d.rebuild_offsets()
	return d

func _unit_tests() -> void:
	var D := CarDamage
	var P := CarDamage.Part
	# --- the table, each part alone
	_near(_one(P.TOE_RL, 1.0).offsets.get_wheel(2, DamageOffsets.TOE_ADD), 0.003, "rear-left toe at 100 %: 0.003 rad toe-out (left)")
	_near(_one(P.TOE_RR, 1.0).offsets.get_wheel(3, DamageOffsets.TOE_ADD), -0.003, "rear-right toe at 100 %: 0.003 rad toe-out (right)")
	_near(_one(P.STEER_FL, 1.0).offsets.get_wheel(0, DamageOffsets.TOE_ADD), D.MAX_TOE_BEND, "the front arm keeps its slice 1 bend")
	for i in 4:
		_near(_one(D.CAMBER_PARTS[i], 1.0).offsets.get_wheel(i, DamageOffsets.CAMBER_ADD), -deg_to_rad(2.5), "camber %d at 100 %%: 2.5 deg, top in" % i)
		_near(_one(D.DAMPER_PARTS[i], 1.0).offsets.get_wheel(i, DamageOffsets.DAMPER_MULT), 0.35, "damper %d at 100 %%: x0.35" % i)
		_near(_one(D.BRAKE_PARTS[i], 1.0).offsets.get_wheel(i, DamageOffsets.BRAKE_MULT), 0.78, "brake %d at 100 %%: x0.78 (Roy 1470: softer than the brief's 0.6)" % i)
		var sag := _one(D.SPRING_PARTS[i], 1.0)
		_near(sag.offsets.get_wheel(i, DamageOffsets.SPRING_MULT), 0.65, "spring %d at 100 %%: x0.65" % i)
		_near(sag.offsets.get_wheel(i, DamageOffsets.RIDE_DROP), 0.025, "corner %d at 100 %%: 25 mm low" % i)
	_near(_one(P.RACK, 1.0).offsets.get_car(DamageOffsets.STEER_LOCK_MULT), 0.8, "rack at 100 %: x0.8 lock")
	# scaled from 0 at 25 %
	_check(_one(P.TOE_RL, 0.25).offsets.is_neutral() and _one(P.SAG_FL, 0.24).offsets.is_neutral() and _one(P.DAMPER_RR, 0.2).offsets.is_neutral(), "nothing under 25 %")
	_near(_one(P.TOE_RL, 0.625).offsets.get_wheel(2, DamageOffsets.TOE_ADD), 0.0015, "half way between 25 % and 100 % is half the toe")
	_near(_one(P.SAG_FR, 0.625).offsets.get_wheel(1, DamageOffsets.RIDE_DROP), 0.0125, "and half the drop")
	# the gates
	_check(_one(P.RACK, 0.49).offsets.is_neutral() and _one(P.BRAKE_FL, 0.49).offsets.is_neutral(), "the rack and the brakes do nothing under 50 %")
	_near(_one(P.RACK, 0.5).offsets.get_car(DamageOffsets.STEER_LOCK_MULT), 1.0 - 0.2 / 3.0, "the rack at 50 %")
	_near(_one(P.BRAKE_RR, 0.5).offsets.get_wheel(3, DamageOffsets.BRAKE_MULT), 1.0 - D.BRAKE_LOSS / 3.0, "a brake at 50 %")
	_check(_one(P.CAMBER_FL, 0.8).warning() and not _one(P.CAMBER_FL, 0.2).warning(), "a corner part lights DMG past 25 %")
	# the wheel sits crooked by the front toe x the steering ratio; the pull is one angle
	var arm := _one(P.STEER_FL, 1.0)
	_near(arm.offsets.get_car(DamageOffsets.STEER_CENTRE), D.MAX_TOE_BEND * arm.steering_ratio, "STEER_CENTRE = front toe bend x steering ratio")
	_near(D.pull_angle(arm.offsets), D.MAX_TOE_BEND * 0.5, "a bent front-left arm pulls left by half its toe")
	_near(D.pull_angle(_one(P.TOE_RL, 1.0).offsets), -0.0015, "a toed-out rear-left yaws the car right")
	# --- causes
	var rl := CarDamage.new()
	rl.apply_hit(Vector3(7.0, 0, -7.0))   # from the rear-left corner
	_check(rl.part(P.TOE_RL) > 0.3 and rl.part(P.TOE_RR) < 0.001 and is_equal_approx(rl.part(P.TOE_RL), rl.part(P.SUSP_RL)), "a rear-left hit bends the rear-left toe (%.2f)" % rl.part(P.TOE_RL))
	_check(rl.part(P.BRAKE_RL) > 0.0 and rl.part(P.BRAKE_FL) == 0.0 and rl.part(P.RACK) == 0.0 and rl.part(P.SAG_FL) < 0.001, "and that brake, not the rack or the front")
	var side := CarDamage.new()
	side.apply_hit(Vector3(12.0, 0, 0))   # from the left
	_check(side.part(P.CAMBER_FL) > 0.2 and is_equal_approx(side.part(P.CAMBER_FL), side.part(P.CAMBER_RL)), "a hit from the left bends both left cambers alike (%.2f)" % side.part(P.CAMBER_FL))
	_check(side.part(P.CAMBER_FR) == 0.0 and side.part(P.CAMBER_RR) == 0.0, "the right side's camber is untouched")
	var shallow := CarDamage.new()
	shallow.apply_hit(Vector3(4.0, 0, 12.0))   # 10 % from the side
	_check(shallow.part(P.CAMBER_FL) == 0.0, "a hit that is under 40 % from the side bends no camber")
	var front := CarDamage.new()
	front.apply_hit(Vector3(0, 0, 13.0))
	_check(front.part(P.SAG_FL) > 0.0 and is_equal_approx(front.part(P.SAG_FL), front.part(P.SAG_FR)) and is_equal_approx(front.part(P.SAG_FL), front.part(P.STEER_FL)), "a front hit sags both front corners by their share")
	_check(front.part(P.RACK) > 0.0 and front.part(P.TOE_RL) == 0.0 and front.part(P.CAMBER_FL) == 0.0, "and reaches the rack, not the rear or the camber")
	var corner := CarDamage.new()
	corner.apply_hit(Vector3(9.0, 0, 9.0))   # front-left corner: half from the front
	_check(corner.part(P.BRAKE_FL) > 0.0 and corner.part(P.BRAKE_FR) == 0.0 and corner.part(P.RACK) == 0.0, "a corner hit takes that brake and spares the rack (front share under 0.6)")
	var kerb := CarDamage.new()
	kerb.apply_kerb_strike(2, 9.0)
	_check(kerb.part(P.TOE_RL) > 0.0 and is_equal_approx(kerb.part(P.TOE_RL), kerb.part(P.SUSP_RL)), "a rear kerb strike bends the rear toe")
	kerb.apply_kerb_strike(2, 9.0)
	_check(kerb.part(P.DAMPER_RL) == 0.0, "two strikes leave the damper alone")
	kerb.apply_kerb_strike(2, 9.0)
	_near(kerb.part(P.DAMPER_RL), 4.0 * D.KERB_DAMAGE_PER_MS, "the third strike on one corner hurts its damper")
	kerb.apply_kerb_strike(0, 9.0)
	_check(kerb.part(P.DAMPER_FL) == 0.0, "another corner counts its own strikes")
	var land := CarDamage.new()
	land.apply_landing(1, D.LANDING_FREE_MS)
	_check(land.landings == 0 and land.part(P.DAMPER_FR) == 0.0, "a soft landing does nothing")
	land.apply_landing(1, D.LANDING_FREE_MS + 5.0)
	_near(land.part(P.DAMPER_FR), 5.0 * D.LANDING_DAMAGE_PER_MS, "a hard landing hurts that wheel's damper")
	# --- caps
	var four := CarDamage.new()
	four.parts[P.STEER_FL] = 1.0
	four.parts[P.SAG_FR] = 0.9
	four.parts[P.DAMPER_RR] = 0.8
	four.parts[P.CAMBER_RL] = 0.6
	four.rebuild_offsets()
	_check(four.active_effects() == [P.STEER_FL, P.SAG_FR, P.DAMPER_RR], "four hurt parts: the worst three count (%s)" % [four.active_effects()])
	_check(four.offsets.get_wheel(2, DamageOffsets.CAMBER_ADD) == 0.0 and four.felt(P.CAMBER_RL) == 0.0 and four.handling_effect(P.CAMBER_RL) > 0.0, "the fourth stays looks and sound")
	_check(four.offsets.get_wheel(0, DamageOffsets.TOE_ADD) > 0.0 and four.offsets.get_wheel(1, DamageOffsets.SPRING_MULT) < 1.0 and four.offsets.get_wheel(3, DamageOffsets.DAMPER_MULT) < 1.0, "the three are all felt")
	four.parts[P.CAMBER_RL] = 0.95   # now worse than the damper
	four.rebuild_offsets()
	_check(four.active_effects() == [P.STEER_FL, P.CAMBER_RL, P.SAG_FR], "a part that gets worse takes a place (%s)" % [four.active_effects()])
	var wreck := CarDamage.new()
	for p in wreck.parts.size():
		wreck.parts[p] = 1.0
	wreck.rebuild_offsets()
	_check(wreck.active_effects().size() == 3, "a wreck still has three handling effects (%d)" % wreck.active_effects().size())
	var big := CarDamage.new()
	big.apply_hit(Vector3(20.0, 0, 60.0))
	var most := 0.0
	for a in big.parts:
		most = maxf(most, a)
	_near(most, D.MAX_PER_HIT, "one huge hit adds at most 0.5 to any part")
	var toe := DamageOffsets.new()
	toe.set_wheel(0, DamageOffsets.TOE_ADD, 0.03)
	toe.set_wheel(1, DamageOffsets.TOE_ADD, 0.01)
	toe.set_wheel(2, DamageOffsets.TOE_ADD, -0.05)
	D.apply_caps(toe)
	_near(toe.get_wheel(0, DamageOffsets.TOE_ADD) + toe.get_wheel(1, DamageOffsets.TOE_ADD), 0.02, "the front axle's toe adds are clamped to +0.02")
	_near(toe.get_wheel(2, DamageOffsets.TOE_ADD) + toe.get_wheel(3, DamageOffsets.TOE_ADD), -0.02, "the rear axle's to -0.02")
	_check(absf(wreck.offsets.get_wheel(0, DamageOffsets.TOE_ADD) + wreck.offsets.get_wheel(1, DamageOffsets.TOE_ADD)) <= 0.02
			and absf(wreck.offsets.get_wheel(2, DamageOffsets.TOE_ADD) + wreck.offsets.get_wheel(3, DamageOffsets.TOE_ADD)) <= 0.02, "a wreck's toe is inside the Tuner's range")
	var grip := DamageOffsets.new()
	for i in 4:
		grip.set_wheel(i, DamageOffsets.GRIP_MULT, 0.9 if i < 3 else 0.8)
	D.apply_caps(grip)
	var product := 1.0
	for i in 4:
		product *= grip.get_wheel(i, DamageOffsets.GRIP_MULT)
	_near(product, 0.85, "grip multipliers of 0.58 in all are raised to 0.85", 1e-4)
	_check(grip.get_wheel(3, DamageOffsets.GRIP_MULT) < grip.get_wheel(0, DamageOffsets.GRIP_MULT), "the worst wheel is still the worst")
	var mild := DamageOffsets.new()
	mild.set_wheel(0, DamageOffsets.GRIP_MULT, 0.93)
	D.apply_caps(mild)
	_near(mild.get_wheel(0, DamageOffsets.GRIP_MULT), 0.93, "a loss inside the cap is left alone")
	# --- fade
	var f := CarDamage.new()
	f.apply_hit(Vector3(9.0, 0, 9.0))
	_check(f.applied.is_neutral() and not f.offsets.is_neutral(), "right after a hit the car still reads the old numbers")
	var target: float = f.offsets.get_wheel(0, DamageOffsets.TOE_ADD)
	for i in 120:
		f.fade_step()
	_near(f.applied.get_wheel(0, DamageOffsets.TOE_ADD), target * 0.5, "half way after 120 ticks", 1e-6)
	for i in 119:
		f.fade_step()
	_check(f.applied.data != f.offsets.data, "not there after 239 ticks")
	f.fade_step()
	_check(f.applied.data == f.offsets.data, "there after 240 ticks")
	_check(not f.fade_step(), "and the fade is over")
	f.apply_hit(Vector3(9.0, 0, 9.0))   # a second hit fades on from where the first got to
	_near(f.applied.get_wheel(0, DamageOffsets.TOE_ADD), target, "a new hit starts from the numbers in use", 1e-7)
	f.garage_repair(null)
	_check(f.applied.is_neutral() and f.offsets.is_neutral(), "a repair is at once")
	# --- the same hits twice
	var runs := []
	for n in 2:
		var d := CarDamage.new()
		d.apply_hit(Vector3(6.0, 0, 11.0))
		for i in 100:
			d.fade_step()
		d.apply_kerb_strike(3, 11.0)
		d.apply_hit(Vector3(-13.0, 0, -2.0))
		d.apply_landing(0, 9.5)
		for i in 3:
			d.apply_kerb_strike(1, 8.0)
		for i in 77:
			d.fade_step()
		runs.append([d.to_dict(), d.offsets.data.duplicate(), d.applied.data.duplicate(), d.active_effects()])
	_check(runs[0][0] == runs[1][0] and runs[0][1] == runs[1][1] and runs[0][2] == runs[1][2] and runs[0][3] == runs[1][3], "the same hits twice give the same parts and offsets")
	var copy := CarDamage.new()
	copy.from_dict(runs[0][0])
	_check(copy.offsets.data == runs[0][1] and copy.applied.data == runs[0][1], "a load rebuilds the same offsets, already faded in")
	print("unit part: %s" % ("ok" if failures.is_empty() else "%d failure(s)" % failures.size()))

# ---------- drive ----------

## Every run starts from the same car: put back on the boot pose, standing on
## the foot brake for SETTLE_SECS so the suspension, wheel spin and ABS state
## of the run before (a barrier hit, a full stop) have died away, then set
## moving. Without the stand-still that state carried over, and the brake
## runs' heading turned by up to 0.04 rad more or less with the order of
## the runs before them.
const SETTLE_SECS := 1.0
func _launch(p: PlayerCar) -> void:
	_place(p)
	Harness.launch_player(p, 0.0)
	# The stop is the test's, not a hit. ARM_40 and ARM_0 end their 10 s
	# sliding along the median barrier at about 70 km/h (on the damage chain's
	# own branch, before the raised coupe hull, they bounced off it and
	# stopped), and the
	# barrier contact is still there on the next tick, so the jump to a stand-
	# still read as a 20 m/s front hit: it bent the next run's front corners
	# and the REPAIRED car drifted into the barrier.
	p.damage.forget_motion()
	keys = PlayerCar.KEY_BRAKE
	p.driver = func(c: Vehicle) -> void: (c as PlayerCar).apply_keys(keys)
	settle_left = int(SETTLE_SECS * Engine.physics_ticks_per_second)
	t = 0

func _place(p: PlayerCar) -> void:
	p.global_transform = rest
	p.angular_velocity = Vector3.ZERO
	Harness.move_player_to_lane(p, Harness.lane_x(1))

func _go(p: PlayerCar) -> void:
	_place(p)
	x0 = p.global_position.x
	Harness.launch_player(p, SPEED)
	keys = 0
	t = 0

func _fresh(p: PlayerCar) -> void:
	p.damage.garage_repair(null)
	p.health.repair()
	p.fuel.litres = FuelTank.CAPACITY_L
	p.auto_trim_share = PlayerCar.AUTO_TRIM_WEEKEND

func _begin(p: PlayerCar, s: int) -> void:
	_fresh(p)
	match s:
		Step.ARM_85, Step.ARM_40, Step.ARM_0, Step.REPAIRED:
			p.damage.parts[CarDamage.Part.STEER_FL] = 1.0
			p.damage.rebuild_offsets()
			p.auto_trim_share = {Step.ARM_85: PlayerCar.AUTO_TRIM_DAILY, Step.ARM_40: PlayerCar.AUTO_TRIM_RACER, Step.ARM_0: 0.0}.get(s, PlayerCar.AUTO_TRIM_WEEKEND)
			if s == Step.REPAIRED:
				p.damage.garage_repair(null)
		Step.BRAKE_HURT:
			p.damage.parts[CarDamage.Part.BRAKE_FL] = 1.0
			p.damage.rebuild_offsets()
	step = s as Step
	_launch(p)
	p.damage.hits = 0

## How far the nose points right of straight down the road (rad, small angles).
func _heading(p: PlayerCar) -> float:
	return (-p.global_transform.basis.z).x

func _physics_process(_delta: float) -> bool:
	tick += 1
	t += 1
	hz = Engine.physics_ticks_per_second
	if tick > hz * 300:
		return _end("timed out in %s" % Step.keys()[step])
	var p: PlayerCar = game.get("player") if game != null else null
	if p == null:
		return tick > hz * 10 and _end("Game never became ready")
	if not Harness.finite(p):
		return _end("non-finite car state in %s" % Step.keys()[step])
	if settle_left > 0:
		settle_left -= 1
		if settle_left == 0:
			_go(p)
		return false
	match step:
		Step.BOOT:
			if t >= hz:
				rest = p.global_transform
				print("car: %s, %d Hz" % [PlayerCar.chassis_kind(), hz])
				_begin(p, Step.CLEAN)
		Step.CLEAN, Step.ARM_85, Step.ARM_40, Step.ARM_0, Step.REPAIRED:
			if step == Step.ARM_85 and t == hz * 2:
				var o := p.damage.applied
				var centre := o.get_car(DamageOffsets.STEER_CENTRE)
				var view := p.steer_centre_view(CockpitFrame.WHEEL_LOCK_RAD) + p.steer_fraction() * CockpitFrame.WHEEL_LOCK_RAD
				print("bent front-left arm, no keys: steering rests at %+.5f of lock (trim %+.5f), cockpit wheel at %+.2f deg (STEER_CENTRE %+.2f deg)" % [
					p.steer_fraction(), p.damage_trim(), rad_to_deg(view), rad_to_deg(centre)])
				_check(p.damage_trim() > 0.0 and absf(p.steer_fraction() - p.damage_trim()) < 1e-4, "with no key held the steering rests on the trim, to the right")
				_check(centre > 0.0 and absf(view - centre) < 1e-3, "the cockpit wheel rests on STEER_CENTRE, crooked to the right")
				_check(absf(p.wheel_array[0].toe - (-p.front_toe + CarDamage.MAX_TOE_BEND)) < 1e-6, "the front-left wheel carries the bend on top of the tuned toe")
			if t == hz * 2:
				drift_2s[step] = p.global_position.x - x0
			elif t == hz * 5:
				drift_5s[step] = p.global_position.x - x0
			if t >= hz * DRIFT_SECS:
				drift[step] = p.global_position.x - x0
				if step == Step.CLEAN or step == Step.ARM_85 or step == Step.REPAIRED:
					_check(p.damage.hits == 0, "%s: nothing was hit in 10 s (%d)" % [Step.keys()[step], p.damage.hits])
				if step == Step.REPAIRED:
					print("drift from 100 km/h with no keys, front-left arm at 100 % (x: + is right; the median barrier is 4 m to the left):")
					for s in [Step.CLEAN, Step.ARM_85, Step.ARM_40, Step.ARM_0, Step.REPAIRED]:
						print("  %-9s after 2 s %+.3f m, 5 s %+.3f m, 10 s %+.3f m" % [Step.keys()[s], drift_2s[s], drift_5s[s], drift[s]])
					var d85: float = drift_5s[Step.ARM_85] - drift_5s[Step.CLEAN]
					var d40: float = drift_5s[Step.ARM_40] - drift_5s[Step.CLEAN]
					_check(d85 < -0.2 and d40 < -0.2 and drift[Step.ARM_85] - drift[Step.CLEAN] < -0.5, "a bent front-left arm drifts left with the trim on (5 s: %.3f, %.3f)" % [d85, d40])
					_check(absf(d85) < absf(d40) * 0.6, "clearly less drift at 0.85 than at 0.40 (5 s)")
					_check(drift_2s[Step.ARM_0] < drift_2s[Step.ARM_40] and drift_2s[Step.ARM_40] < drift_2s[Step.ARM_85], "and less at 0.40 than with no trim (2 s)")
					var apart := absf(drift[Step.REPAIRED] - drift[Step.CLEAN])
					_check(apart < 0.5 and apart < absf(drift[Step.ARM_85] - drift[Step.CLEAN]) * 0.25, "the repaired car holds the clean car's line (%.3f m apart after 10 s)" % apart)
					_begin(p, Step.BRAKE_CLEAN)
				else:
					_begin(p, step + 1)
		Step.BRAKE_CLEAN, Step.BRAKE_HURT:
			if t == hz * COAST_SECS:
				turn_coast[step] = _heading(p)
				keys = PlayerCar.KEY_BRAKE
			elif t >= hz * (COAST_SECS + BRAKE_SECS):
				turn_brake[step] = _heading(p) - turn_coast[step]
				if step == Step.BRAKE_HURT:
					print("front-left brake at 100 %%: heading after 2 s coasting %+.5f rad (clean %+.5f), turned on 2 s of brakes %+.4f rad (clean %+.4f), + is right; %.0f km/h left" % [
						turn_coast[Step.BRAKE_HURT], turn_coast[Step.BRAKE_CLEAN], turn_brake[Step.BRAKE_HURT], turn_brake[Step.BRAKE_CLEAN], p.current_speed() * 3.6])
					# two clean runs differ by about 0.005 rad here: the limit is that noise, far under the brake pull
					_check(absf(turn_coast[Step.BRAKE_HURT] - turn_coast[Step.BRAKE_CLEAN]) < 0.02, "no pull from a hurt brake while not braking")
					_check(turn_brake[Step.BRAKE_HURT] > turn_brake[Step.BRAKE_CLEAN] + 0.005, "on the brakes the car turns toward the healthy side (right)")
					_check(turn_brake[Step.BRAKE_HURT] < 0.17, "and stays a gentle pull: under 10 degrees in a 2 s full stop (Roy 1470)")
					return _end("")
				_begin(p, Step.BRAKE_HURT)
	return false

func _end(why: String) -> bool:
	if why != "":
		failures.append(why)
		print("  FAIL: " + why)
	print("damage_handling: %s" % ("PASS" if failures.is_empty() else "%d failure(s)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
	return true
