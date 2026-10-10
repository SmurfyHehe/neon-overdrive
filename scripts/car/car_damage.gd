class_name CarDamage
extends RefCounted

# Damage, slice 1 (Stage C, 2026-10-09). Roy's decisions (damage proposal and
# the damage/fuel design notes, 2026-10-09):
# - model "broken parts" (option C): a crash breaks parts, each part changes
#   the handling a little. Slice 1 has five: the radiator, a front steering
#   arm per corner, a rear suspension corner each side, the four lamps, and
#   the body (cost only).
# - no performance loss under 25 % in a part (FREE_BELOW).
# - the front at 100 % kills the engine: towed home, the night ends.
# - parts break instead of the hood popping: nothing ever covers the view,
#   and there are no dents until the car redesign (week of 2026-10-12). For
#   now the signs are a DMG lamp, steam off a hurt radiator, a crash pull,
#   dead lamps and a rattle.
# - once a night a fuel station patches the engine for free; the garage
#   repairs everything; repairs and tows are paid from the BANK, never the
#   night's pot. No tow during a chase.
# - traffic is look-only (no damage sim); this is the player's car (and the
#   race rival's, later).
#
# What breaks comes from the hit's direction in the car's frame: the velocity
# change over one hit window (like CrashAudio), turned into a car-local
# direction. A hit from the front pushes the car back (+Z), one on the left
# side pushes it right (+X). Each corner takes the square of the hit's
# projection on its diagonal, so a straight-on hit shares the two front
# corners, an oblique one lands on one corner, and the shares add up to one.
#
# Effects (each only past FREE_BELOW, scaled from 0 there to full at 1.0):
# - radiator: the engine cools worse (PowertrainHealth.cooling_mult), so it
#   runs hot and the existing derate and OVERHEAT limp take over; from
#   ENGINE_LIMP_AT the engine limps on its own (LimpMode.ENGINE); at 1.0 it is
#   dead (cap 0) until towed.
# - front corner: the wheel's toe is bent toward the hit, so the car pulls to
#   that side (the "crash pull").
# - rear corner: that spring is softer, the corner sags and the rear wallows.
# - lamps: a head lamp past LAMP_BREAK goes dark (half the beam each); tail
#   lamps are tracked for the lamps the redesign will give each side.
# - body: only the repair price.
#
# Kerb strikes (pavements step 4, 2026-10-10; Roy: "kerb strike bends wheel"):
# a wheel that comes onto the pavement (the "Kerb" surface) with more than
# KERB_FREE_MS of speed across the road, toward the kerb, bends that
# corner: a front corner's steering arm (the same toe pull as a wall hit),
# a rear corner's spring. The body takes a quarter of it as cost. A
# shallow, slow mount - a normal drive up a dropped kerb - does nothing.
#
# The state is plain numbers (to_dict / from_dict) so the save system and the
# garage can keep it. Until the save system lands it lives as long as the car,
# like FuelTank: Restart starts a fresh, undamaged car.

enum Part { RADIATOR, STEER_FL, STEER_FR, SUSP_RL, SUSP_RR, BODY }
enum Lamp { HEAD_L, HEAD_R, TAIL_L, TAIL_R }
const PART_NAMES := ["radiator", "steer_fl", "steer_fr", "susp_rl", "susp_rr", "body"]
const LAMP_NAMES := ["head_l", "head_r", "tail_l", "tail_r"]

## Hit detection, matching CrashAudio: a horizontal acceleration this big while
## the body touches something opens a window; everything in it is one hit.
const IMPACT_ACCEL := 35.0        # m/s^2
const HIT_WINDOW := 0.12          # s
const COOLDOWN := 0.12
## Velocity change (m/s) that does no damage: CrashAudio's thud and smaller.
const DV_FREE := 3.0
## Damage per m/s of velocity change above DV_FREE, shared out over the parts.
## A 36 km/h straight wall hit (dv 10) puts each front part near 0.3; a
## 72 km/h one (dv 20) is past 0.5; head-on at 130 km/h kills the engine.
const DAMAGE_PER_DV := 0.06
## Below this a part is cosmetic (Roy: no performance loss under 25 %).
const FREE_BELOW := 0.25
## The radiator from here makes the engine limp at ENGINE_LIMP_KMH.
const ENGINE_LIMP_AT := 0.75
const ENGINE_LIMP_KMH := 70.0
## Engine cooling lost with a wrecked radiator (1.0 = no cooling at all).
const COOLING_LOSS := 0.7
## Toe (rad) a fully bent front arm adds. The Tuner's toe range is +-0.02;
## "slightly" (Roy) keeps this inside it.
const MAX_TOE_BEND := 0.004
## A wheel's speed into the kerb (m/s, horizontal, across the kerb face)
## below which nothing bends; 5 m/s is 18 km/h straight at it, or about 14
## degrees at 100 km/h.
const KERB_FREE_MS := 5.0
## Damage per m/s above KERB_FREE_MS: 100 km/h at 30 degrees (13.9 m/s) puts
## about 0.4 on the corner, 100 km/h square on bends it fully.
const KERB_DAMAGE_PER_MS := 0.045
## A strike's cost to the body, as a share of the corner's.
const KERB_BODY_SHARE := 0.25
## Spring rate lost on a fully broken rear corner.
const SPRING_LOSS := 0.35
## A lamp breaks when its corner takes this much in one hit.
const LAMP_BREAK := 0.1
## The DMG lamp comes on once any part is past FREE_BELOW.
## Rattle: how loud the loose parts get, 0..1 (DamageAudio scales it by speed).
const RATTLE_FROM := 0.15
## Steam off the radiator from FREE_BELOW, puffs per second at 1.0.
const STEAM_RATE := 14.0

## Placeholder prices in Cred until the economy pass. Paid from the bank.
const REPAIR_PRICE := {"radiator": 400, "steer_fl": 250, "steer_fr": 250, "susp_rl": 300, "susp_rr": 300, "body": 600}
const LAMP_PRICE := 60
const TOW_PRICE := 150
## A station's free patch brings the radiator back to here (no performance loss).
const PATCH_TO := FREE_BELOW - 0.01

var enabled := true
var parts: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var lamps: Array[bool] = [false, false, false, false]   # true = broken
## The night number of the last free patch; one patch per night.
var patched_night := -1
var hits := 0
var last_hit_dv := 0.0
var last_hit_dir := Vector2.ZERO   # car-local (x, z) of the velocity change

## Kerb strikes this car has taken, and the speed into the kerb of the last.
var kerb_strikes := 0
var last_kerb_strike := 0.0

var _on_kerb: Array[bool] = [false, false, false, false]
var _prev_vel := Vector3.ZERO
var _hit_dv := Vector3.ZERO
var _hit_left := -1.0
var _wait := 0.0
var _base_rate: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _written_rate: Array[float] = [-1.0, -1.0, -1.0, -1.0]

func part(p: Part) -> float:
	return parts[p]

## 0 below FREE_BELOW, then up to 1 at full damage: how much a part hurts.
static func effect(amount: float) -> float:
	return clampf((amount - FREE_BELOW) / (1.0 - FREE_BELOW), 0.0, 1.0)

func is_engine_dead() -> bool:
	return enabled and parts[Part.RADIATOR] >= 1.0

## The DMG lamp: any part past the free band, or a lamp out.
func warning() -> bool:
	if not enabled:
		return false
	for i in Part.BODY:
		if parts[i] >= FREE_BELOW:
			return true
	return lamps.has(true)

## Engine cooling multiplier for PowertrainHealth.
func cooling_mult() -> float:
	return 1.0 - COOLING_LOSS * effect(parts[Part.RADIATOR]) if enabled else 1.0

## The cap LimpMode.engine_damage_kmh takes: INF healthy, 0 dead.
func engine_cap_kmh() -> float:
	if not enabled:
		return INF
	if is_engine_dead():
		return 0.0
	return ENGINE_LIMP_KMH if parts[Part.RADIATOR] >= ENGINE_LIMP_AT else INF

## Toe added to wheel i (FL, FR, RL, RR): bent toward the hit side, so the
## car pulls that way (a wheel's rotation.y turns it left when positive).
## Rear wheels are not bent in slice 1.
func toe_offset(i: int) -> float:
	match i:
		0:
			return MAX_TOE_BEND * effect(parts[Part.STEER_FL])
		1:
			return -MAX_TOE_BEND * effect(parts[Part.STEER_FR])
	return 0.0

## Spring rate multiplier for wheel i.
func spring_mult(i: int) -> float:
	match i:
		2:
			return 1.0 - SPRING_LOSS * effect(parts[Part.SUSP_RL])
		3:
			return 1.0 - SPRING_LOSS * effect(parts[Part.SUSP_RR])
	return 1.0

## Head lamp beam left 0..1: each working head lamp gives half.
func headlight_share() -> float:
	return (0.0 if lamps[Lamp.HEAD_L] else 0.5) + (0.0 if lamps[Lamp.HEAD_R] else 0.5)

## How loose the car is, 0..1, for the rattle.
func rattle_level() -> float:
	if not enabled:
		return 0.0
	var worst := 0.0
	var total := 0.0
	for a in parts:
		worst = maxf(worst, a)
		total += a
	return clampf(maxf(worst, total * 0.4) - RATTLE_FROM, 0.0, 1.0) / (1.0 - RATTLE_FROM)

## Steam puffs per second off the radiator.
func steam_rate() -> float:
	return STEAM_RATE * effect(parts[Part.RADIATOR]) if enabled else 0.0

## One hit from raw numbers (testable without a car). `dv` is the velocity
## change in the car's frame (x right, z back); only its x and z count.
func apply_hit(dv_local: Vector3) -> void:
	if not enabled:
		return
	var d := Vector2(dv_local.x, dv_local.z)
	var size := d.length()
	if size <= DV_FREE:
		return
	hits += 1
	last_hit_dv = size
	d /= size
	last_hit_dir = d
	var amount := (size - DV_FREE) * DAMAGE_PER_DV
	# corner shares: projection of the hit on each corner's diagonal, squared
	# (from the front = +z, from the left = +x)
	var k := 0.70710678
	var fl := maxf((d.y + d.x) * k, 0.0)
	var fr := maxf((d.y - d.x) * k, 0.0)
	var rl := maxf((-d.y + d.x) * k, 0.0)
	var rr := maxf((-d.y - d.x) * k, 0.0)
	var share := [fl * fl, fr * fr, rl * rl, rr * rr]
	var front := maxf(d.y, 0.0)
	_add(Part.RADIATOR, amount * front * front)
	_add(Part.STEER_FL, amount * share[0])
	_add(Part.STEER_FR, amount * share[1])
	_add(Part.SUSP_RL, amount * share[2])
	_add(Part.SUSP_RR, amount * share[3])
	_add(Part.BODY, amount)
	for i in 4:
		if amount * share[i] >= LAMP_BREAK:
			lamps[[Lamp.HEAD_L, Lamp.HEAD_R, Lamp.TAIL_L, Lamp.TAIL_R][i]] = true

## One kerb strike from raw numbers (testable without a car): wheel i (FL,
## FR, RL, RR) met the kerb at `approach` m/s across the kerb face.
func apply_kerb_strike(i: int, approach: float) -> void:
	if not enabled or approach <= KERB_FREE_MS:
		return
	var amount := (approach - KERB_FREE_MS) * KERB_DAMAGE_PER_MS
	kerb_strikes += 1
	last_kerb_strike = approach
	_add([Part.STEER_FL, Part.STEER_FR, Part.SUSP_RL, Part.SUSP_RR][clampi(i, 0, 3)], amount)
	_add(Part.BODY, amount * KERB_BODY_SHARE)

## Looks for a wheel that has just come onto the "Kerb" surface and, if it
## came hard, strikes. The speed into the kerb is the car's sideways speed in
## road space (across the road, toward the wheel's side), not the ramp's
## contact normal: at 45 degrees and highway speed a wheel clears the 0.3 m
## ramp in one tick and its first contact is the flat top.
func _kerb_step(v: Vehicle) -> void:
	for i in mini(4, v.wheel_array.size()):
		var w: Wheel = v.wheel_array[i]
		var on: bool = w.is_colliding() and w.surface_type == "Kerb"
		if on and not _on_kerb[i]:
			var pos := RoadFrame.unroll(w.global_position)
			var across := RoadFrame.dir_to_road(pos.z, v.linear_velocity).x
			apply_kerb_strike(i, across if pos.x > 0.0 else -across)
		_on_kerb[i] = on

func _add(p: Part, a: float) -> void:
	parts[p] = clampf(parts[p] + a, 0.0, 1.0)

## The car was moved and stopped by the game (off-map rescue): the jump in
## velocity is not a hit.
func forget_motion() -> void:
	_prev_vel = Vector3.ZERO
	_hit_dv = Vector3.ZERO
	_hit_left = -1.0

## One physics step from raw numbers: world velocity, the car's basis, and
## whether the body touches something other than the road.
func step_values(dt: float, vel: Vector3, basis: Basis, touching: bool) -> void:
	_wait = maxf(_wait - dt, 0.0)
	var dv := vel - _prev_vel
	_prev_vel = vel
	dv.y = 0.0
	if _hit_left >= 0.0:
		_hit_dv += dv
		_hit_left -= dt
		if _hit_left < 0.0:
			# the velocity change, seen from the car (+x right, +z back)
			apply_hit(basis.inverse() * _hit_dv)
			_hit_dv = Vector3.ZERO
			_wait = COOLDOWN
	elif _wait <= 0.0 and touching and dv.length() / dt > IMPACT_ACCEL:
		_hit_dv = dv
		_hit_left = HIT_WINDOW

## One step on the car: reads contacts, applies the parts' effects.
func step(v: Vehicle, dt: float, health: PowertrainHealth, limp: LimpMode) -> void:
	if not enabled:
		return
	step_values(dt, v.linear_velocity, v.global_transform.basis, _touching(v))
	_kerb_step(v)
	health.cooling_mult = cooling_mult()
	limp.engine_damage_kmh = engine_cap_kmh()
	_apply_wheels(v)

## Toe and springs. The base values come from the tune (GEVP initialize sets
## them, the Tuner re-runs it), so a rate this did not write is a new base.
func _apply_wheels(v: Vehicle) -> void:
	var base_toe := [-v.front_toe, v.front_toe, -v.rear_toe, v.rear_toe]
	for i in mini(4, v.wheel_array.size()):
		var w: Wheel = v.wheel_array[i]
		w.toe = base_toe[i] + toe_offset(i)
		if not is_equal_approx(w.spring_rate, _written_rate[i]):
			_base_rate[i] = w.spring_rate
		w.spring_rate = _base_rate[i] * spring_mult(i)
		_written_rate[i] = w.spring_rate

## Touching a wall, a building or another car (not the road under the body).
static func _touching(v: Vehicle) -> bool:
	var st := PhysicsServer3D.body_get_direct_state(v.get_rid())
	if st == null:
		return false
	for i in st.get_contact_count():
		var obj := st.get_contact_collider_object(i)
		if obj is Vehicle or absf(st.get_contact_local_normal(i).y) <= 0.6:
			return true
	return false

## The garage: everything fixed, paid from the bank. Returns the price paid;
## nothing changes if the bank can't cover it. `bank` is anything with an int
## `bank` and spend_bank(int) -> bool (as FuelTank.refuel); null = free (the
## pause menu's service button until the garage exists).
func garage_repair(bank: Object) -> int:
	var price := repair_price()
	if price > 0 and bank != null and not bank.call("spend_bank", price):
		return 0
	for i in parts.size():
		parts[i] = 0.0
	for i in lamps.size():
		lamps[i] = false
	return price

## What the garage would charge right now.
func repair_price() -> int:
	var total := 0.0
	for i in parts.size():
		total += parts[i] * REPAIR_PRICE[PART_NAMES[i]]
	for b in lamps:
		if b:
			total += LAMP_PRICE
	return roundi(total)

## A fuel station's free engine patch, once a night: the radiator comes back
## to the no-loss band (a dead engine runs again). Returns true if it patched.
func station_patch(night: int) -> bool:
	if not enabled or night == patched_night or parts[Part.RADIATOR] < FREE_BELOW:
		return false
	parts[Part.RADIATOR] = PATCH_TO
	patched_night = night
	return true

## Ferris's tow: never during a chase. Paid from the bank, as much as it holds
## (a tow is never refused for money). The caller ends the night and puts the
## car home. Returns false if refused.
func tow(bank: Object, in_chase: bool) -> bool:
	if in_chase:
		return false
	if bank != null:
		var pay := mini(TOW_PRICE, int(bank.get("bank")))
		if pay > 0:
			bank.call("spend_bank", pay)
	return true

func to_dict() -> Dictionary:
	var d := {"lamps": lamps.duplicate(), "patched_night": patched_night}
	for i in parts.size():
		d[PART_NAMES[i]] = parts[i]
	return d

func from_dict(d: Dictionary) -> void:
	for i in parts.size():
		parts[i] = clampf(float(d.get(PART_NAMES[i], 0.0)), 0.0, 1.0)
	var l: Array = d.get("lamps", [])
	for i in lamps.size():
		lamps[i] = bool(l[i]) if i < l.size() else false
	patched_night = int(d.get("patched_night", -1))
