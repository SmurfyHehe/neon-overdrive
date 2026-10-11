extends SceneTree

# Damage, slice 1 (Stage C, 2026-10-09), headless and silent, scripted driver.
# Unit part (no car):
# - small hits do nothing; a straight front hit shares the two front corners
#   and the radiator; an oblique one lands on its corner and breaks its lamp;
#   a rear hit leaves the front alone
# - no effect below FREE_BELOW; the engine limps from ENGINE_LIMP_AT and keeps
#   limping at 1.0 (damage never kills it); a hurt radiator runs the engine
#   hotter
# - offsets (DP0): a hit gives the toe and spring numbers it always did, a
#   repair puts the offsets back to neutral, the save carries `totalled`
# - the station patch (once a night), the garage (bank pays, short bank
#   changes nothing, null is free), the tow (never in a chase, bank pays what
#   it has), to_dict / from_dict
# - hit detection: a big velocity change while touching is one hit after the
#   window; the same change in the air is none
# Drive part (Game.tscn, straight flat road, no traffic), for the car in
# NEON_CAR (run once per car for the sweep):
# - WALL: into the right-hand wall at 20 m/s, 45 deg: a hit registers, the
#   front-right takes more than the front-left, the numbers stay finite
# - PULL: a fully bent front-left arm, wheel straight at ~70 km/h for 4 s: the
#   car drifts left, a healthy car does not (much); front-right drifts right
# - SAG: a broken rear-left corner softens that spring by SPRING_LOSS, a repair
#   brings the tuned rate back exactly, and a Tuner spring change keeps the
#   damage on the new base
# - LIMP: radiator at 1.0, full throttle from rest: the car still drives
# - LAMPS: both head lamps broken switch the beam off
# - STEAM / RATTLE: a hurt radiator steams; a loose car at speed rattles
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 120 --audio-driver Dummy --path . -s res://tests/car/car_damage.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const DamageOffsets := preload("res://scripts/car/damage_offsets.gd")

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

enum Step { BOOT, WALL, PULL_BASE, PULL_FL, PULL_FR, SAG, LIMP, LAMPS, STEAM, DONE }

var game: Node
var step := Step.BOOT
var t := 0
var tick := 0
var hz := 120
var failures: Array[String] = []
var x0 := 0.0
var drift := {}
var rest := Transform3D()
var wall_x := 0.0

func _initialize() -> void:
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	_unit_tests()
	game = Harness.boot(self, 0, 300.0, 4242)

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		print("  FAIL: " + what)

func _unit_tests() -> void:
	var D := CarDamage
	var d := CarDamage.new()
	d.apply_hit(Vector3(0, 0, D.DV_FREE - 0.1))
	_check(d.hits == 0 and d.part(D.Part.BODY) == 0.0, "a tap does no damage")
	d.apply_hit(Vector3(0, 0, 13.0))   # straight on, from the front
	var fl := d.part(D.Part.STEER_FL)
	var fr := d.part(D.Part.STEER_FR)
	print("front hit dv 13: radiator %.2f FL %.2f FR %.2f body %.2f" % [d.part(D.Part.RADIATOR), fl, fr, d.part(D.Part.BODY)])
	_check(d.hits == 1 and is_equal_approx(fl, fr) and fl > 0.0, "a straight front hit shares the front corners")
	_check(d.part(D.Part.SUSP_RL) == 0.0 and d.part(D.Part.SUSP_RR) == 0.0, "a front hit leaves the rear alone")
	_check(is_equal_approx(d.part(D.Part.RADIATOR), 10.0 * D.DAMAGE_PER_DV), "the radiator takes the whole front share")
	_check(not d.lamps.has(true) or d.lamps[D.Lamp.HEAD_L], "only front lamps can break from the front")
	var o := CarDamage.new()
	o.apply_hit(Vector3(9.0, 0, 9.0))   # from the front-left corner
	_check(o.part(D.Part.STEER_FL) > 0.4 and o.part(D.Part.STEER_FR) < 0.001, "an oblique hit lands on its corner (FL %.2f FR %.2f)" % [o.part(D.Part.STEER_FL), o.part(D.Part.STEER_FR)])
	_check(o.lamps[D.Lamp.HEAD_L] and not o.lamps[D.Lamp.HEAD_R], "the hit corner's head lamp breaks")
	_check(is_equal_approx(o.headlight_share(), 0.5), "one head lamp left: half the beam")
	var r := CarDamage.new()
	r.apply_hit(Vector3(0, 0, -12.0))   # rear-ended
	_check(r.part(D.Part.RADIATOR) == 0.0 and r.part(D.Part.SUSP_RL) > 0.0 and is_equal_approx(r.part(D.Part.SUSP_RL), r.part(D.Part.SUSP_RR)), "a rear hit is the rear's")
	# effects
	var e := CarDamage.new()
	e.parts[D.Part.RADIATOR] = 0.2
	e.parts[D.Part.STEER_FL] = 0.2
	e.parts[D.Part.SUSP_RR] = 0.2
	_check(e.cooling_mult() == 1.0 and e.toe_offset(0) == 0.0 and e.spring_mult(3) == 1.0 and e.engine_cap_kmh() == INF, "no effect under 25 %")
	_check(not e.warning(), "no DMG lamp under 25 %")
	e.parts[D.Part.RADIATOR] = 0.5
	_check(e.cooling_mult() < 1.0 and e.engine_cap_kmh() == INF and e.warning(), "a hurt radiator cools worse, no limp yet, DMG on")
	e.parts[D.Part.RADIATOR] = D.ENGINE_LIMP_AT
	_check(e.engine_cap_kmh() == D.ENGINE_LIMP_KMH, "the engine limps from ENGINE_LIMP_AT")
	e.parts[D.Part.RADIATOR] = 1.0
	_check(not e.is_engine_dead() and e.engine_cap_kmh() == D.ENGINE_LIMP_KMH, "the front at 100 % limps, it does not kill the engine")
	var limp := LimpMode.new()
	limp.engine_damage_kmh = e.engine_cap_kmh()
	limp.update(false, 90.0)
	_check(limp.cause == LimpMode.Cause.ENGINE and limp.throttle_scale(0.0) > 0.0, "a wrecked radiator still gets throttle")
	# heat: same drive, healthy against half-broken radiator
	var temps := []
	for rad in [0.0, 0.6]:
		var hd := CarDamage.new()
		hd.parts[D.Part.RADIATOR] = rad
		var h := PowertrainHealth.new()
		h.cooling_mult = hd.cooling_mult()
		for i in 120 * 60:
			h.step_values(1.0 / 120.0, 0.6, false, 25.0, 0.0)
		temps.append(h.engine_temp)
	print("engine after 60 s at 60 %% load, 90 km/h: healthy %.0f C, radiator 0.6 %.0f C" % temps)
	_check(temps[1] > temps[0] + 5.0, "a hurt radiator runs the engine hotter")
	# station patch: once a night
	_check(e.station_patch(3) and e.engine_cap_kmh() == INF and e.part(D.Part.RADIATOR) < D.FREE_BELOW, "a station patch ends the limp")
	e.parts[D.Part.RADIATOR] = 0.9
	_check(not e.station_patch(3) and e.part(D.Part.RADIATOR) == 0.9, "only one patch a night")
	_check(e.station_patch(4), "a new night, a new patch")
	_check(not CarDamage.new().station_patch(1), "nothing to patch on a healthy car")
	# offsets (DP0): the same numbers the old per-tick writes gave
	var ox := CarDamage.new()
	_check(ox.offsets.is_neutral(), "a new car has neutral offsets")
	ox.apply_hit(Vector3(9.0, 0, 9.0))   # from the front-left corner
	var fl_effect := clampf((ox.part(D.Part.STEER_FL) - D.FREE_BELOW) / (1.0 - D.FREE_BELOW), 0.0, 1.0)
	var ox_toe: float = ox.offsets.get_wheel(0, DamageOffsets.TOE_ADD)
	print("front-left hit dv 12.7: FL %.3f -> toe %+.5f rad (MAX_TOE_BEND %.3f)" % [ox.part(D.Part.STEER_FL), ox_toe, D.MAX_TOE_BEND])
	_check(ox_toe > 0.0 and is_equal_approx(ox_toe, D.MAX_TOE_BEND * fl_effect) and is_equal_approx(ox_toe, ox.toe_offset(0)), "a front-left hit bends that toe by MAX_TOE_BEND x effect")
	_check(ox.offsets.get_wheel(1, DamageOffsets.TOE_ADD) == 0.0 and ox.offsets.get_wheel(2, DamageOffsets.TOE_ADD) == 0.0, "the other toes stay at zero")
	var ox_rr := CarDamage.new()
	ox_rr.apply_hit(Vector3(0, 0, -16.0))   # rear-ended
	var rr_effect := clampf((ox_rr.part(D.Part.SUSP_RR) - D.FREE_BELOW) / (1.0 - D.FREE_BELOW), 0.0, 1.0)
	var rr_mult: float = ox_rr.offsets.get_wheel(3, DamageOffsets.SPRING_MULT)
	print("rear hit dv 16: RR %.3f -> spring x%.4f" % [ox_rr.part(D.Part.SUSP_RR), rr_mult])
	_check(rr_mult < 1.0 and is_equal_approx(rr_mult, 1.0 - D.SPRING_LOSS * rr_effect), "a rear hit softens that spring by SPRING_LOSS x effect")
	_check(ox_rr.offsets.get_wheel(0, DamageOffsets.SPRING_MULT) == 1.0, "a front spring is untouched")
	var ox_rad := CarDamage.new()
	ox_rad.apply_hit(Vector3(0, 0, 22.0))
	_check(is_equal_approx(ox_rad.offsets.get_car(DamageOffsets.COOLING_MULT), ox_rad.cooling_mult()) and ox_rad.cooling_mult() < 1.0, "a hurt radiator lowers COOLING_MULT")
	_check(ox_rad.offsets.get_car(DamageOffsets.TORQUE_MULT) == 1.0 and ox_rad.offsets.get_wheel(0, DamageOffsets.GRIP_MULT) == 1.0, "fields no sim reads yet stay neutral")
	ox_rad.garage_repair(null)
	ox.garage_repair(null)
	ox_rr.garage_repair(null)
	_check(ox.offsets.is_neutral() and ox_rr.offsets.is_neutral() and ox_rad.offsets.is_neutral(), "a repair puts the offsets back to neutral")
	var ox_k := CarDamage.new()
	ox_k.apply_kerb_strike(0, 12.0)
	_check(ox_k.offsets.get_wheel(0, DamageOffsets.TOE_ADD) > 0.0, "a kerb strike bends the toe through the offsets")
	var ox_p := CarDamage.new()
	ox_p.parts[D.Part.RADIATOR] = 0.9
	ox_p.rebuild_offsets()
	_check(ox_p.station_patch(1) and ox_p.offsets.get_car(DamageOffsets.COOLING_MULT) == 1.0, "a station patch rebuilds the offsets")
	# garage
	var g := CarDamage.new()
	g.apply_hit(Vector3(9.0, 0, 9.0))
	var price := g.repair_price()
	var short := StubBank.new(price - 1)
	_check(price > 0 and g.garage_repair(short) == 0 and short.bank == price - 1 and g.part(D.Part.BODY) > 0.0, "a short bank repairs nothing")
	var rich := StubBank.new(10000)
	_check(g.garage_repair(rich) == price and rich.bank == 10000 - price and g.part(D.Part.BODY) == 0.0 and not g.lamps.has(true), "the garage fixes everything for %d" % price)
	g.apply_hit(Vector3(0, 0, 10.0))
	_check(g.garage_repair(null) > 0 and g.part(D.Part.RADIATOR) == 0.0, "null bank: free service")
	# tow
	var bank := StubBank.new(1000)
	_check(not g.tow(bank, true) and bank.bank == 1000, "no tow in a chase")
	_check(g.tow(bank, false) and bank.bank == 1000 - D.TOW_PRICE, "a tow costs %d" % D.TOW_PRICE)
	var poor := StubBank.new(40)
	_check(g.tow(poor, false) and poor.bank == 0, "a broke driver still gets towed")
	# a tow ends the night: the clock skips to 6 a.m. and dawn fires once
	var clock := NightClock.new()
	clock.fixed_minutes = 100.0   # never saves to disk
	clock.minutes = 100.0
	var ended := []
	clock.night_ended.connect(func(n: int) -> void: ended.append(n))
	clock.end_night()
	_check(ended.size() == 1 and clock.night == 2 and clock.minutes < 1.0, "end_night skips to the next night (ended %s, night %d, %.2f min)" % [ended, clock.night, clock.minutes])
	clock.free()
	# save
	var s := CarDamage.new()
	s.apply_hit(Vector3(-7.0, 0, -7.0))
	s.patched_night = 2
	var copy := CarDamage.new()
	copy.from_dict(s.to_dict())
	_check(copy.parts == s.parts and copy.lamps == s.lamps and copy.patched_night == 2, "to_dict / from_dict round trip")
	_check(copy.offsets.data == s.offsets.data and not copy.offsets.is_neutral(), "a loaded car has its offsets rebuilt")
	s.totalled = 0.5
	copy.from_dict(s.to_dict())
	_check(is_equal_approx(copy.totalled, 0.5) and CarDamage.new().to_dict().has("totalled"), "totalled round trips (0 by default)")
	# detection
	var det := CarDamage.new()
	var dt := 1.0 / 120.0
	det.step_values(dt, Vector3(0, 0, -20.0), Basis(), false)   # cruising
	det.step_values(dt, Vector3(0, 0, -20.0), Basis(), true)
	det.step_values(dt, Vector3(0, 0, -8.0), Basis(), true)   # 12 m/s gone in a tick, nose first (-Z)
	for i in 20:
		det.step_values(dt, Vector3(0, 0, -8.0), Basis(), true)
	_check(det.hits == 1 and det.part(D.Part.RADIATOR) > 0.0, "a wall stop while touching is one front hit")
	var air := CarDamage.new()
	air.step_values(dt, Vector3(0, 0, -20.0), Basis(), false)
	air.step_values(dt, Vector3(0, 0, -20.0), Basis(), false)
	air.step_values(dt, Vector3(0, 0, -8.0), Basis(), false)
	for i in 20:
		air.step_values(dt, Vector3(0, 0, -8.0), Basis(), false)
	_check(air.hits == 0, "the same change touching nothing is no hit (a reset)")

func _launch(p: PlayerCar, speed: float) -> void:
	p.global_transform = rest
	p.angular_velocity = Vector3.ZERO
	Harness.move_player_to_lane(p, Harness.lane_x(1))
	x0 = p.global_position.x
	Harness.launch_player(p, speed)
	t = 0

func _fresh(p: PlayerCar) -> void:
	p.damage.garage_repair(null)
	p.health.repair()
	p.fuel.litres = FuelTank.CAPACITY_L

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
	match step:
		Step.BOOT:
			if t >= hz:
				rest = p.global_transform
				print("car: %s" % PlayerCar.chassis_kind())
				_start_wall(p)
		Step.WALL:
			if t >= hz * 3:
				var dm := p.damage
				print("wall 20 m/s 45 deg: hits %d dv %.1f FL %.2f FR %.2f radiator %.2f body %.2f" % [dm.hits, dm.last_hit_dv,
					dm.part(CarDamage.Part.STEER_FL), dm.part(CarDamage.Part.STEER_FR), dm.part(CarDamage.Part.RADIATOR), dm.part(CarDamage.Part.BODY)])
				_check(dm.hits >= 1, "the wall hit registered")
				_check(dm.part(CarDamage.Part.STEER_FR) > dm.part(CarDamage.Part.STEER_FL), "the right-hand wall hurts the front-right most")
				_next_pull(p, Step.PULL_BASE)
		Step.PULL_BASE, Step.PULL_FL, Step.PULL_FR:
			if t >= hz * 4:
				drift[step] = p.global_position.x - x0
				if step == Step.PULL_FR:
					print("crash pull, 4 s at ~70 km/h wheel straight: healthy %+.2f m, FL bent %+.2f m, FR bent %+.2f m (x: + is right)" % [drift[Step.PULL_BASE], drift[Step.PULL_FL], drift[Step.PULL_FR]])
					_check(drift[Step.PULL_FL] < drift[Step.PULL_BASE] - 0.5, "a bent front-left pulls left")
					_check(drift[Step.PULL_FR] > drift[Step.PULL_BASE] + 0.5, "a bent front-right pulls right")
					_check(absf(drift[Step.PULL_FL]) < 8.0 and absf(drift[Step.PULL_FR]) < 8.0, "the pull is slight (under a lane change in 4 s)")
					_fresh(p)
					_launch(p, 0.0)
					p.driver = _hold(0.0, 0.0)
					step = Step.SAG
				else:
					_next_pull(p, step + 1)
		Step.SAG:
			var ratio_off := 1.0 - CarDamage.SPRING_LOSS
			if t == hz / 2:
				drift["rl0"] = p.wheel_array[2].spring_rate
				drift["rr0"] = p.wheel_array[3].spring_rate
				p.damage.parts[CarDamage.Part.SUSP_RL] = 1.0
				p.damage.rebuild_offsets()
			elif t == hz / 2 + 2:
				var ratio: float = p.wheel_array[2].spring_rate / drift["rl0"]
				_check(is_equal_approx(ratio, ratio_off), "a broken rear-left spring is %.2f of stock (%.2f)" % [ratio_off, ratio])
				_check(is_equal_approx(p.wheel_array[3].spring_rate, drift["rr0"]), "the other rear spring is untouched")
				p.damage.garage_repair(null)
			elif t == hz / 2 + 4:
				_check(p.damage.offsets.is_neutral(), "after the repair the offsets are neutral")
				_check(p.wheel_array[2].spring_rate == drift["rl0"], "the tuned spring rate is back exactly after hit + repair (%.4f vs %.4f)" % [p.wheel_array[2].spring_rate, drift["rl0"]])
				# what a Tuner spring change does: a new rear ride, applied to the wheels
				p.rear_resting_ratio *= 1.2
				p.apply_suspension()
				drift["rl1"] = p.wheel_array[2].spring_rate
				p.damage.parts[CarDamage.Part.SUSP_RL] = 1.0
				p.damage.rebuild_offsets()
			elif t == hz / 2 + 6:
				var ratio2: float = p.wheel_array[2].spring_rate / p.wheel_array[3].spring_rate
				_check(not is_equal_approx(drift["rl1"], drift["rl0"]), "the Tuner change moved the spring rate (%.1f -> %.1f)" % [drift["rl0"], drift["rl1"]])
				_check(absf(ratio2 - ratio_off) < 0.01, "the damage stays on after a Tuner change (%.2f)" % ratio2)
			elif t >= hz:
				_fresh(p)
				p.damage.parts[CarDamage.Part.RADIATOR] = 1.0
				p.damage.rebuild_offsets()
				_launch(p, 0.0)
				p.driver = _hold(1.0, 0.0)
				step = Step.LIMP
		Step.LIMP:
			if t >= hz * 3:
				var kmh := p.current_speed() * 3.6
				print("wrecked radiator, 3 s full throttle: %.1f km/h (limp cap %.0f)" % [kmh, CarDamage.ENGINE_LIMP_KMH])
				_check(kmh > 10.0, "a wrecked radiator limps, it does not stop the car (%.1f km/h)" % kmh)
				_check(not p.damage.is_engine_dead(), "damage never kills the engine")
				_fresh(p)
				p.damage.lamps[CarDamage.Lamp.HEAD_L] = true
				p.damage.lamps[CarDamage.Lamp.HEAD_R] = true
				step = Step.LAMPS
				t = 0
		Step.LAMPS:
			if t == 3:
				var spot := p.get_node_or_null("Headlights") as SpotLight3D
				_check(spot == null or not spot.visible, "both head lamps broken: no beam")
				p.damage.lamps[CarDamage.Lamp.HEAD_L] = false
			elif t >= 6:
				var spot2 := p.get_node_or_null("Headlights") as SpotLight3D
				_check(spot2 == null or (spot2.visible and is_equal_approx(spot2.light_energy, CarFx.HEADLIGHT_ENERGY * 0.5)), "one head lamp: half the beam")
				_fresh(p)
				p.damage.parts[CarDamage.Part.RADIATOR] = 0.6
				p.damage.parts[CarDamage.Part.SUSP_RR] = 0.6
				p.damage.rebuild_offsets()
				_launch(p, 20.0)
				p.driver = _hold(0.5, 0.0)
				step = Step.STEAM
		Step.STEAM:
			if t >= hz * 2:
				var smoke := _find(game, "TyreSmoke") as TyreSmoke
				var rattle := _find(p, "DamageAudio") as DamageAudio
				if smoke != null:
					print("steam puffs in 2 s: %d" % smoke.emitted_steam)
					_check(not smoke.enabled or smoke.emitted_steam > 0, "a hurt radiator steams")
				if rattle != null:
					print("rattle level at %.0f km/h: %.2f" % [p.current_speed() * 3.6, rattle.level])
					_check(rattle.level > 0.05, "a loose car rattles at speed")
				else:
					_check(false, "DamageAudio is on the car")
				_check(p.damage.hits == 0, "steady driving makes no hits (%d)" % p.damage.hits)
				return _end("")
	return false

func _start_wall(p: PlayerCar) -> void:
	step = Step.WALL
	t = 0
	_fresh(p)
	p.damage.hits = 0
	var found := []
	_collect(game, "BoundaryOwn", found)
	wall_x = INF
	for b in found:
		for c in (b as Node).get_children():
			var col := c as CollisionShape3D
			if col != null and col.shape is BoxShape3D and absf(col.global_position.z - p.global_position.z) < (col.shape as BoxShape3D).size.z / 2.0 + 1.0:
				wall_x = minf(wall_x, col.global_position.x - (col.shape as BoxShape3D).size.x / 2.0)
	if wall_x == INF:
		_check(false, "found the right-hand wall")
		wall_x = p.global_position.x + 12.0
	var pos := Vector3(wall_x - 8.0, rest.origin.y, p.global_position.z)
	p.global_transform = Transform3D(Basis(Vector3.UP, -deg_to_rad(45.0)), pos)
	p.angular_velocity = Vector3.ZERO
	TrafficCar.set_moving(p, 20.0)
	p.reset_physics_interpolation()
	p.driver = _hold(0.0, 0.0)

func _next_pull(p: PlayerCar, s: int) -> void:
	_fresh(p)
	if s == Step.PULL_FL:
		p.damage.parts[CarDamage.Part.STEER_FL] = 1.0
	elif s == Step.PULL_FR:
		p.damage.parts[CarDamage.Part.STEER_FR] = 1.0
	p.damage.rebuild_offsets()
	step = s as Step
	_launch(p, 19.0)
	p.driver = _hold(0.35, 0.0)
	p.damage.hits = 0

## Fixed pedals, wheel straight, top gear held by the auto box.
func _hold(throttle: float, brake: float) -> Callable:
	return func(c: Vehicle) -> void:
		c.steering_input = 0.0
		c.throttle_input = throttle
		c.brake_input = brake
		c.handbrake_input = 0.0

func _find(n: Node, name: String) -> Node:
	if n.name == name:
		return n
	for c in n.get_children():
		var f := _find(c, name)
		if f != null:
			return f
	return null

func _collect(n: Node, name: String, out: Array) -> void:
	if n.name == name:
		out.append(n)
	for c in n.get_children():
		_collect(c, name, out)

func _end(why: String) -> bool:
	if why != "":
		failures.append(why)
		print("  FAIL: " + why)
	print("car_damage: %s" % ("PASS" if failures.is_empty() else "%d failure(s)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
	return true
