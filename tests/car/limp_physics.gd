extends SceneTree

# Limp by physics (brief LM, 2026-10-11), headless and silent, scripted driver.
# Unit part (no car):
# - each cause sets the right multipliers; two causes take the worse per field
# - LimpMode, CarDamage and FlatTyre have no speed-cap code path left (no
#   member with "kmh" in its name, none of the old cap members)
# - the rev limit is a soft cut that bounces (hysteresis)
# - fuel starvation: every cut is 0.1-0.3 s, about 35 % of the torque gets
#   through at full throttle on the flat, more cuts under side load and uphill,
#   fewer on a light throttle, and the same inputs give the same pattern
# - a wheel on its rim: a very hard kerb strike bursts the tyre, the offsets
#   carry it, drag and shake grow with speed, rim wear grows and is capped,
#   Looks only switches it off, the garage fixes it, the save keeps it
# Drive part (Game.tscn, straight flat road, no traffic), the selected car
# (NEON_CAR=<kind> picks another; run once per car for the table): from rest
# at full throttle for TRIAL_S, each cause alone:
# - engine limp (the engine held at LIMP_C): 3rd gear at most, revs held
# - fuel dry, run twice: the two runs must agree
# - front-left tyre on its rim: the car shakes, the rim wears
# The top speed (the average of the last 5 s) of every cause must be 50 km/h
# or more. That is a floor the numbers are tuned to, not a cap. On the rim a
# strong car held flat out goes fast enough to lose its lane and hit the
# wall; its top speed is then the fastest it went before the hit, and the
# test prints when that was.
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --audio-driver Dummy --path . -s res://tests/car/limp_physics.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const DamageOffsets := preload("res://scripts/car/damage_offsets.gd")
const FlatTyre := preload("res://scripts/car/flat_tyre.gd")

const FLOOR_KMH := 50.0
const TRIAL_S := 50.0
const TOP_WINDOW_S := 5.0
const TRIALS := ["engine", "fuel", "fuel again", "rim"]

var game: Node
var tick := 0
var t := 0
var hz := 60
var failures: Array[String] = []
var rest := Transform3D()
var booted := false
var trial_i := -1
var top_sum := 0.0
var top_n := 0
var max_kmh := 0.0
var max_gear_seen := 0
var max_rpm_late := 0.0
var max_shake := 0.0
var stumbles0 := 0
var hit_at := -1.0
var hit_kmh := 0.0
var off_lane := 0.0
var results := {}

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		print("  FAIL: " + what)

func _initialize() -> void:
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	_unit_limp()
	_unit_stumble()
	_unit_rim()
	game = Harness.boot(self, 0, 150.0, 7)

func _member_names(script: Script, obj: Object) -> Array[String]:
	var names: Array[String] = []
	for p in obj.get_property_list():
		names.append(String(p["name"]))
	for m in script.get_script_method_list():
		names.append(String(m["name"]))
	for c in script.get_script_constant_map():
		names.append(String(c))
	return names

func _unit_limp() -> void:
	var L := LimpMode
	var hot := PowertrainHealth.LIMP_C + 1.0
	var l := LimpMode.new()
	l.update(false, 90.0)
	_check(not l.is_limping() and l.cause == L.Cause.NONE and l.rev_limit_frac == 1.0 and l.boost_mult == 1.0 and l.torque_mult == 1.0 and l.max_gear == 99 and l.stumble == 0.0, "healthy: 1, 1, 1, 99, 0")
	# engine limp, by heat and by damage
	for by_damage in [false, true]:
		var e := LimpMode.new()
		e.engine_damaged = by_damage
		e.update(false, 90.0 if by_damage else hot)
		var what := "engine damage" if by_damage else "overheat"
		_check(e.is_limping() and e.is_engine_limp() and e.cause == (L.Cause.ENGINE if by_damage else L.Cause.OVERHEAT), "%s: the engine limps" % what)
		_check(e.rev_limit_frac == 0.55 and e.boost_mult == 0.0 and e.torque_mult == 0.6 and e.max_gear == 3 and e.stumble == 0.0, "%s: revs 0.55, no boost, torque 0.6, 3rd at most, no stumble" % what)
	# fuel dry
	l.update(true, 90.0)
	_check(l.is_limping() and not l.is_engine_limp() and l.cause == L.Cause.FUEL, "dry tank: the cause is fuel, the engine lamp stays off")
	_check(l.rev_limit_frac == 1.0 and l.boost_mult == 1.0 and l.torque_mult == 1.0 and l.max_gear == 99 and l.stumble == 1.0, "dry tank: only the stumble")
	# worst wins per field
	l.update(true, hot)
	_check(l.active_causes == (L.Cause.FUEL | L.Cause.OVERHEAT), "dry + hot: both causes active")
	_check(l.rev_limit_frac == 0.55 and l.boost_mult == 0.0 and l.torque_mult == 0.6 and l.max_gear == 3 and l.stumble == 1.0, "dry + hot: every field takes the worse cause")
	_check(is_equal_approx(l.torque_for(0.5), 0.5) and is_equal_approx(l.torque_for(1.0), 0.6) and is_equal_approx(l.torque_for(0.55), 0.55), "torque is the worse of the health derate and the limp's, never the product")
	l.update(false, PowertrainHealth.LIMP_C - 5.0)
	_check(l.is_engine_limp(), "the overheat limp holds while the engine is still hot (no flicker at LIMP_C)")
	l.update(false, L.OVERHEAT_EXIT_C - 1.0)
	_check(not l.is_limping() and l.max_gear == 99, "the limp ends once the engine has cooled")
	# no speed-cap code path
	var names := _member_names(LimpMode as Script, LimpMode.new())
	names.append_array(_member_names(CarDamage as Script, CarDamage.new()))
	names.append_array(_member_names(FlatTyre as Script, FlatTyre.new()))
	var bad: Array[String] = []
	for n in names:
		var low := n.to_lower()
		if low.contains("kmh") or low.contains("speed_cap") or low in ["throttle_scale", "gov_band", "engine_cap"]:
			bad.append(n)
	_check(bad.is_empty(), "LimpMode, CarDamage and FlatTyre have no speed-cap member (found %s)" % str(bad))
	_check(not LimpMode.new().has_method("throttle_scale") and not ("cap_kmh" in LimpMode.new()) and not ("engine_damage_kmh" in LimpMode.new()), "the old cap API is gone")
	# the rev limit bounces: cut above the limit, stays cut inside the hysteresis, back below it
	var r := LimpMode.new()
	r.update(false, hot)
	var limit := 7000.0 * L.ENGINE_REV_FRAC
	_check(not r.step_cut(1.0 / 60.0, limit - 10.0, 7000.0, 1.0, 0.0, 0.0), "no cut just under the rev limit")
	_check(r.step_cut(1.0 / 60.0, limit + 10.0, 7000.0, 1.0, 0.0, 0.0), "fuel cut just over the rev limit (%.0f rpm)" % limit)
	_check(r.step_cut(1.0 / 60.0, limit - L.REV_CUT_HYSTERESIS_RPM + 10.0, 7000.0, 1.0, 0.0, 0.0), "still cut inside the hysteresis")
	_check(not r.step_cut(1.0 / 60.0, limit - L.REV_CUT_HYSTERESIS_RPM - 10.0, 7000.0, 1.0, 0.0, 0.0), "fuel back once the revs have fallen")
	var healthy := LimpMode.new()
	healthy.update(false, 90.0)
	_check(not healthy.step_cut(1.0 / 60.0, 9000.0, 7000.0, 1.0, 2.0, 0.2), "a healthy car never gets a limp fuel cut")

## Steps a dry LimpMode for `secs` and returns [share of ticks with fuel, cuts,
## shortest cut s, longest cut s, the pattern as a PackedByteArray].
func _stumble_run(secs: float, throttle: float, lat_g: float, grade: float) -> Array:
	var l := LimpMode.new()
	l.update(true, 90.0)
	var dt := 1.0 / 120.0
	var n := int(secs / dt)
	var fed := 0
	var pattern := PackedByteArray()
	var run := 0
	var shortest := INF
	var longest := 0.0
	for i in n:
		var cut := l.step_cut(dt, 3000.0, 7000.0, throttle, lat_g, grade)
		pattern.append(1 if cut else 0)
		if cut:
			run += 1
		else:
			fed += 1
			if run > 0:
				shortest = minf(shortest, run * dt)
				longest = maxf(longest, run * dt)
			run = 0
	return [fed / float(n), l.stumble_count, shortest, longest, pattern]

func _unit_stumble() -> void:
	var L := LimpMode
	var flat := _stumble_run(120.0, 1.0, 0.0, 0.0)
	print("fuel starvation, full throttle on the flat: %.1f %% of the torque gets through, %d cuts in 120 s, each %.2f-%.2f s" % [flat[0] * 100.0, flat[1], flat[2], flat[3]])
	_check(absf(flat[0] - L.FUEL_FLAT_SHARE) <= 0.03, "about 35 %% of the torque on the flat (%.1f %%)" % (flat[0] * 100.0))
	_check(flat[2] >= L.STUMBLE_MIN_S - 0.01 and flat[3] <= L.STUMBLE_MAX_S + 0.02, "every cut lasts 0.1-0.3 s (%.3f-%.3f)" % [flat[2], flat[3]])
	var again := _stumble_run(120.0, 1.0, 0.0, 0.0)
	_check(flat[4] == again[4] and flat[1] == again[1], "the same inputs give the same stumble pattern, tick for tick")
	var corner := _stumble_run(120.0, 1.0, 0.6, 0.0)
	var climb := _stumble_run(120.0, 1.0, 0.0, 0.08)
	var light := _stumble_run(120.0, 0.3, 0.0, 0.0)
	var downhill := _stumble_run(120.0, 1.0, 0.0, -0.08)
	print("  cuts in 120 s: flat %d, 0.6 g corner %d, 8 %% climb %d, 30 %% throttle %d" % [flat[1], corner[1], climb[1], light[1]])
	_check(corner[1] > flat[1] and corner[0] < flat[0], "side load (slosh) cuts more often")
	_check(climb[1] > flat[1] and climb[0] < flat[0], "uphill cuts more often")
	_check(light[1] < flat[1] and light[0] > flat[0], "a light throttle cuts less often")
	_check(downhill[1] == flat[1], "downhill is no worse than the flat")
	_check(corner[0] > 0.15 and climb[0] > 0.15, "some torque always gets through (corner %.2f, climb %.2f)" % [corner[0], climb[0]])
	for n in 200:
		var cut_s := L.stumble_length(n)
		if cut_s < L.STUMBLE_MIN_S or cut_s > L.STUMBLE_MAX_S:
			_check(false, "stumble %d is %.3f s, outside 0.1-0.3" % [n, cut_s])
			break

func _unit_rim() -> void:
	var D := CarDamage
	var d := CarDamage.new()
	_check(not d.any_tyre_flat() and not FlatTyre.on_rim(d.offsets, 0), "a new car has air in its tyres")
	d.apply_kerb_strike(1, D.KERB_FREE_MS * D.RIM_STRIKE - 0.1)
	_check(not d.tyre_flat(1) and d.offsets.get_wheel(1, DamageOffsets.PRESSURE_MULT) == 1.0 and d.offsets.get_wheel(1, DamageOffsets.GRIP_MULT) == 1.0, "a kerb strike just under 2.5 x the free speed keeps the tyre")
	d.apply_kerb_strike(1, D.KERB_FREE_MS * D.RIM_STRIKE + 0.1)
	_check(d.tyre_flat(1) and not d.tyre_flat(0) and d.warning(), "a kerb strike over 2.5 x the free speed bursts that tyre only, DMG lamp on")
	_check(FlatTyre.on_rim(d.offsets, 1) and d.offsets.get_wheel(1, DamageOffsets.PRESSURE_MULT) <= 0.1, "the offsets carry it: PRESSURE_MULT at or under 0.1")
	_check(is_equal_approx(d.offsets.get_wheel(1, DamageOffsets.GRIP_MULT), 0.45) and d.offsets.get_wheel(0, DamageOffsets.GRIP_MULT) == 1.0, "that wheel's GRIP_MULT is 0.45")
	var same := CarDamage.new()
	same.apply_kerb_strike(1, D.KERB_FREE_MS * D.RIM_STRIKE - 0.1)
	same.apply_kerb_strike(1, D.KERB_FREE_MS * D.RIM_STRIKE + 0.1)
	_check(same.offsets.data == d.offsets.data and same.pressure == d.pressure, "the same strikes always do the same")
	# drag and shake grow with speed, wear raises both, both are bounded
	var wheel_n := 3200.0
	_check(FlatTyre.drag_force(wheel_n, 0.0, 0.0) == 0.0, "no rim drag standing still")
	var crawl := FlatTyre.drag_force(wheel_n, FlatTyre.DRAG_FADE_MS, 0.0)
	_check(crawl >= FlatTyre.RIM_DRAG * wheel_n and crawl < FlatTyre.RIM_DRAG * wheel_n * 1.02, "rim drag at a crawl is RIM_DRAG of the wheel's load (%.0f N)" % crawl)
	var d10 := FlatTyre.drag_force(wheel_n, 10.0, 0.0)
	var d20 := FlatTyre.drag_force(wheel_n, 20.0, 0.0)
	_check(FlatTyre.drag_force(wheel_n, 0.5, 0.0) < crawl and crawl < d10 and d10 < d20, "rim drag grows with speed (%.0f N at 36 km/h, %.0f N at 72)" % [d10, d20])
	_check(FlatTyre.drag_force(wheel_n, 20.0, 1.0) > d20 and FlatTyre.drag_force(wheel_n, 20.0, 5.0) == FlatTyre.drag_force(wheel_n, 20.0, 1.0), "rim wear raises the drag, up to a cap")
	_check(is_equal_approx(FlatTyre.drag_force(wheel_n, 300.0, 1.0), FlatTyre.RIM_DRAG_MAX * wheel_n), "rim drag never passes RIM_DRAG_MAX of the load, at any speed")
	_check(FlatTyre.drag_force(2.0 * wheel_n, 20.0, 0.0) > FlatTyre.drag_force(wheel_n, 20.0, 0.0), "a heavier corner drags more")
	var s10 := FlatTyre.shake_force(wheel_n, 10.0, 0.0)
	var s20 := FlatTyre.shake_force(wheel_n, 20.0, 0.0)
	_check(s10 > 0.0 and is_equal_approx(s20, 4.0 * s10), "the shake grows with speed squared (%.0f N at 36 km/h, %.0f N at 72)" % [s10, s20])
	_check(FlatTyre.shake_force(wheel_n, 20.0, 1.0) > s20, "rim wear raises the shake")
	_check(FlatTyre.shake_force(wheel_n, 500.0, 1.0) <= FlatTyre.RIM_SHAKE_MAX * wheel_n, "the shake is capped under the wheel's load: it never throws the wheel off the road")
	_check(is_equal_approx(FlatTyre.wear_step(20.0, 1.0), 4.0 * FlatTyre.wear_step(10.0, 1.0)), "rim wear grows with distance x speed")
	for i in 100000:
		d.step_rim_wear(1, 40.0, 1.0)
		if d.rim_wear[1] >= 1.0:
			break
	_check(d.rim_wear[1] == 1.0 and d.rim_wear[0] == 0.0, "rim wear stops at 1 (the wheel never comes off)")
	# Damage setting, save, repair
	d.sync_settings(GameSettings.Damage.LOOKS_ONLY, d.difficulty)
	_check(not FlatTyre.on_rim(d.offsets, 1) and d.offsets.is_neutral() and d.tyre_flat(1), "Looks only: the tyre is flat on the bill but the car drives as new")
	d.sync_settings(GameSettings.Damage.FULL, d.difficulty)
	_check(FlatTyre.on_rim(d.offsets, 1), "back on Full the rim is on the road again")
	var price := d.repair_price()
	var copy := CarDamage.new()
	copy.from_dict(d.to_dict())
	_check(copy.pressure == d.pressure and copy.rim_wear == d.rim_wear and copy.offsets.data == d.offsets.data, "the save keeps pressure and rim wear")
	var old := CarDamage.new()
	old.from_dict({"radiator": 0.3})
	_check(not old.any_tyre_flat() and old.rim_wear[2] == 0.0, "an old save without tyres loads with air in them")
	_check(price >= D.TYRE_PRICE + D.RIM_PRICE, "a burst tyre and a worn rim are on the repair bill (%d)" % price)
	d.garage_repair(null)
	_check(not d.any_tyre_flat() and d.rim_wear[1] == 0.0 and d.offsets.is_neutral(), "the garage fits a new tyre and rim")

func _start_trial(p: PlayerCar) -> void:
	trial_i += 1
	t = 0
	top_sum = 0.0
	top_n = 0
	max_kmh = 0.0
	max_gear_seen = 0
	max_rpm_late = 0.0
	max_shake = 0.0
	hit_at = -1.0
	hit_kmh = 0.0
	off_lane = 0.0
	if trial_i >= TRIALS.size():
		return
	GameSettings.set_damage(GameSettings.Damage.FULL)
	p.damage.garage_repair(null)
	p.damage.hits = 0
	p.health.repair()
	p.fuel.litres = FuelTank.CAPACITY_L
	p.limp = LimpMode.new()
	p.set_transmission_mode(PlayerCar.Transmission.AUTO)
	var kind: String = TRIALS[trial_i]
	if kind == "rim":
		p.damage.pressure[0] = 0.0
		p.damage.rebuild_offsets()
	elif kind.begins_with("fuel"):
		p.fuel.litres = 0.0
	p.global_transform = rest
	p.linear_velocity = Vector3.ZERO
	p.angular_velocity = Vector3.ZERO
	Harness.move_player_to_lane(p, Harness.lane_x(1))
	Harness.launch_player(p, 0.0)
	p.driver = Harness.lane_driver(Harness.lane_x(1), 1.0)
	stumbles0 = p.limp.stumble_count

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
			print("car: %s  (redline %.0f rpm, %d gears)" % [PlayerCar.chassis_kind(), p.max_rpm, p.gear_ratios.size()])
			_start_trial(p)
		return false
	if trial_i >= TRIALS.size():
		return _report(p)
	var kind: String = TRIALS[trial_i]
	# one cause at a time
	if kind == "engine":
		p.health.engine_temp = PowertrainHealth.LIMP_C + 1.0
	else:
		p.health.engine_temp = minf(p.health.engine_temp, 95.0)
	if kind.begins_with("fuel"):
		p.fuel.litres = 0.0
	var kmh := p.current_speed() * 3.6
	var secs := t / float(hz)
	max_kmh = maxf(max_kmh, kmh)
	max_shake = maxf(max_shake, p.wheel_shake)
	if hit_at < 0.0:
		off_lane = maxf(off_lane, absf(p.global_position.x - Harness.lane_x(1)))
		if p.damage.hits > 0:
			hit_at = secs
		else:
			hit_kmh = maxf(hit_kmh, kmh)
	if secs > 5.0:
		max_gear_seen = maxi(max_gear_seen, p.gear)
	if secs > TRIAL_S - TOP_WINDOW_S:
		top_sum += kmh
		top_n += 1
		max_rpm_late = maxf(max_rpm_late, p.motor_rpm)
	if secs >= TRIAL_S:
		var top := top_sum / maxf(top_n, 1)
		if kind == "rim" and hit_at >= 0.0:
			# flat out on a rim a strong car ends up in the wall: its top speed
			# is the fastest it went before that
			top = hit_kmh
		results[kind] = {"top": top, "max": max_kmh, "gear": p.gear, "stumbles": p.limp.stumble_count - stumbles0}
		print("%s: top speed %.1f km/h (peak %.1f), gear %d, %.0f rpm, cause '%s'" % [kind, top, max_kmh, p.gear, p.motor_rpm, LimpMode.cause_name(p.limp.cause)])
		_check(top >= FLOOR_KMH, "%s: top speed %.1f km/h is under the 50 km/h floor" % [kind, top])
		_check(p.engine_running, "%s: the engine is still running" % kind)
		match kind:
			"engine":
				_check(p.limp.cause == LimpMode.Cause.OVERHEAT and p.limp.is_engine_limp(), "engine: the limp cause is the engine's")
				_check(max_gear_seen <= LimpMode.ENGINE_MAX_GEAR, "engine: never above 3rd (saw gear %d)" % max_gear_seen)
				_check(max_rpm_late <= p.max_rpm * LimpMode.ENGINE_REV_FRAC * 1.08, "engine: the revs are held near %.0f rpm (saw %.0f)" % [p.max_rpm * LimpMode.ENGINE_REV_FRAC, max_rpm_late])
				_check(p.boost == 0.0, "engine: no boost (%.2f bar)" % p.boost)
			"fuel":
				_check(p.limp.cause == LimpMode.Cause.FUEL, "fuel: the limp cause is fuel")
				_check(results[kind]["stumbles"] > 30, "fuel: the engine stumbles (%d)" % results[kind]["stumbles"])
			"fuel again":
				var first: Dictionary = results["fuel"]
				print("  the two dry runs: %.2f and %.2f km/h, %d and %d stumbles" % [first["top"], top, first["stumbles"], results[kind]["stumbles"]])
				_check(absf(first["top"] - top) <= 1.0, "fuel: two runs give the same top speed (%.2f vs %.2f km/h)" % [first["top"], top])
				_check(absi(first["stumbles"] - results[kind]["stumbles"]) <= 2, "fuel: two runs stumble the same (%d vs %d)" % [first["stumbles"], results[kind]["stumbles"]])
			"rim":
				_check(not p.limp.is_limping(), "rim: a flat tyre is not an engine limp")
				_check(p.damage.rim_wear[0] > 0.0 and p.damage.rim_wear[0] <= 1.0, "rim: the rim wears as it runs (%.2f)" % p.damage.rim_wear[0])
				_check(max_shake > 0.05, "rim: the car shakes (%.2f)" % max_shake)
				print("  rim: %s, up to %.1f m off its lane before that" % [("hit something after %.1f s at %.0f km/h" % [hit_at, hit_kmh]) if hit_at >= 0.0 else "never hit anything", off_lane])
				_check(p.damage.offsets.get_wheel(0, DamageOffsets.GRIP_MULT) < 0.5, "rim: that wheel has lost its grip")
				print("  rim wear after %.0f s: %.2f, camera shake up to %.2f, repair bill %d" % [TRIAL_S, p.damage.rim_wear[0], max_shake, p.damage.repair_price()])
		_start_trial(p)
	return false

func _report(_p: PlayerCar) -> bool:
	print("LIMP TABLE | %s | engine %.0f | fuel %.0f | rim %.0f |" % [PlayerCar.chassis_kind(), results["engine"]["top"], results["fuel"]["top"], results["rim"]["top"]])
	return _end("")

func _end(why: String) -> bool:
	if why != "":
		failures.append(why)
		print("  FAIL: " + why)
	GameSettings.reset_defaults()
	print("limp_physics: %s" % ("PASS" if failures.is_empty() else "%d failure(s)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
	return true
