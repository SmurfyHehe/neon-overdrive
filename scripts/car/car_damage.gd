class_name CarDamage
extends RefCounted

# Damage, slice 1 (Stage C, 2026-10-09). Roy's decisions (damage proposal and
# the damage/fuel design notes, 2026-10-09):
# - model "broken parts" (option C): a crash breaks parts, each part changes
#   the handling a little. Slice 1 has five: the radiator, a front steering
#   arm per corner, a rear suspension corner each side, the four lamps, and
#   the body (cost only).
# - no performance loss under 25 % in a part (FREE_BELOW).
# - the engine never dies from damage (the fun test, 2026-10-11): a wrecked
#   radiator limps at ENGINE_LIMP_KMH, it does not stop the car. The tow is
#   kept for a totalled car (`totalled`, unused for now).
# - parts break instead of the hood popping: nothing ever covers the view,
#   and there are no dents until the car redesign (week of 2026-10-12). For
#   now the signs are a DMG lamp, steam off a hurt radiator, a crash pull,
#   dead lamps and a rattle.
# - once a night a fuel station patches the engine for free; the garage
#   repairs everything; repairs and tows are paid from the BANK, never the
#   night's pot. No tow during a chase.
# - (DP0, 2026-10-11) damage reaches the sim only as `offsets` (DamageOffsets):
#   numbers built here when damage changes and applied by the car on top of the
#   tune. Nothing here writes into a Wheel any more.
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
#   ENGINE_LIMP_AT the engine limps on its own (LimpMode.ENGINE), at
#   ENGINE_LIMP_KMH, also at 1.0: it never dies.
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
# Wheel corners (brief DP1+DP2, 2026-10-11; Roy's fun rules): the same hit,
# split by corner as above, also hurts the parts in the table below. Each is
# 0..1, free under FREE_BELOW and scaled from 0 there to the full offset at 1.
#   rear toe RL/RR   rear corner share, rear kerb strike   REAR_TOE_BEND toward toe-out
#   camber x4        the hit's side share >= CAMBER_SIDE_MIN   CAMBER_BEND_DEG, top of the wheel in
#   front sag FL/FR  front corner share                    SPRING_LOSS and RIDE_DROP_M
#   rear corner      (the slice 1 spring part)             + RIDE_DROP_M
#   damper x4        a hard landing, the third kerb strike on a corner   DAMPER_LOSS
#   steering rack    front share >= RACK_FRONT_MIN, part >= GATE_AT   RACK_LOSS of the lock
#   brake x4         corner share >= BRAKE_SHARE_MIN, part >= GATE_AT   BRAKE_LOSS on that wheel
# The fun rules, all enforced where the offsets are built:
# - at most MAX_EFFECTS handling effects at once: the biggest three count, the
#   rest stay cost, looks and sound (ties go to the part listed first);
# - one hit or strike adds at most MAX_PER_HIT to any part;
# - the toe damage adds per axle stay inside the Tuner's range (TOE_AXLE_MAX);
# - damage never takes more than GRIP_LOSS_MAX of the grip in total;
# - parts fade in: `applied` (what the car reads) moves from the old numbers
#   to the new ones over FADE_TICKS physics ticks. Repairs, loads and
#   rebuild_offsets() are at once.
# Nothing is random: the same hit always gives the same parts and offsets.
#
# The state is plain numbers (to_dict / from_dict) so the save system and the
# garage can keep it. Until the save system lands it lives as long as the car,
# like FuelTank: Restart starts a fresh, undamaged car.

const DamageOffsets := preload("res://scripts/car/damage_offsets.gd")

enum Part { RADIATOR, STEER_FL, STEER_FR, SUSP_RL, SUSP_RR, BODY,
	TOE_RL, TOE_RR, CAMBER_FL, CAMBER_FR, CAMBER_RL, CAMBER_RR, SAG_FL, SAG_FR,
	DAMPER_FL, DAMPER_FR, DAMPER_RL, DAMPER_RR, RACK, BRAKE_FL, BRAKE_FR, BRAKE_RL, BRAKE_RR }
enum Lamp { HEAD_L, HEAD_R, TAIL_L, TAIL_R }
const PART_NAMES := ["radiator", "steer_fl", "steer_fr", "susp_rl", "susp_rr", "body",
	"toe_rl", "toe_rr", "camber_fl", "camber_fr", "camber_rl", "camber_rr", "sag_fl", "sag_fr",
	"damper_fl", "damper_fr", "damper_rl", "damper_rr", "rack", "brake_fl", "brake_fr", "brake_rl", "brake_rr"]
## Per wheel (FL, FR, RL, RR): the part behind each offset.
const TOE_PARTS := [Part.STEER_FL, Part.STEER_FR, Part.TOE_RL, Part.TOE_RR]
const SPRING_PARTS := [Part.SAG_FL, Part.SAG_FR, Part.SUSP_RL, Part.SUSP_RR]
const CAMBER_PARTS := [Part.CAMBER_FL, Part.CAMBER_FR, Part.CAMBER_RL, Part.CAMBER_RR]
const DAMPER_PARTS := [Part.DAMPER_FL, Part.DAMPER_FR, Part.DAMPER_RL, Part.DAMPER_RR]
const BRAKE_PARTS := [Part.BRAKE_FL, Part.BRAKE_FR, Part.BRAKE_RL, Part.BRAKE_RR]
## Parts that only bite once they are at GATE_AT.
const GATED_PARTS := [Part.RACK, Part.BRAKE_FL, Part.BRAKE_FR, Part.BRAKE_RL, Part.BRAKE_RR]
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
## 72 km/h one (dv 20) is past 0.5; head-on at 130 km/h wrecks the radiator.
const DAMAGE_PER_DV := 0.06
## Below this a part is cosmetic (Roy: no performance loss under 25 %).
const FREE_BELOW := 0.25
## The radiator from here makes the engine limp at ENGINE_LIMP_KMH.
const ENGINE_LIMP_AT := 0.75
const ENGINE_LIMP_KMH := 70.0   # the cap stays up at 100 %: the engine never dies
## Engine cooling lost with a wrecked radiator (1.0 = no cooling at all).
const COOLING_LOSS := 0.7
## Toe (rad) a fully bent front arm adds. The Tuner's toe range is +-0.02;
## "slightly" (Roy) keeps this inside it.
const MAX_TOE_BEND := 0.004
## Toe (rad) a fully bent rear corner adds, toward toe-out on its side.
const REAR_TOE_BEND := 0.003
## Camber (degrees) a fully bent corner adds, top of the wheel in.
const CAMBER_BEND_DEG := 2.5
## A hit bends camber only when this much of it comes from the side.
const CAMBER_SIDE_MIN := 0.4
## How far (m) a fully broken corner sits low, on top of the softer spring.
const RIDE_DROP_M := 0.025
## Damping lost on a fully blown damper (DAMPER_MULT 0.35).
const DAMPER_LOSS := 0.65
## Steering lock lost with a fully bent rack (STEER_LOCK_MULT 0.8).
const RACK_LOSS := 0.2
## The rack only takes hits that are this much from the front.
const RACK_FRONT_MIN := 0.6
## Brake torque lost on a fully hurt brake corner (BRAKE_MULT 0.6).
const BRAKE_LOSS := 0.4
## A brake corner only takes hits that land this much on its corner.
const BRAKE_SHARE_MIN := 0.5
## The rack and the brakes do nothing until the part is this hurt.
const GATE_AT := 0.5
## The fun rules: see the header.
const MAX_EFFECTS := 3
const MAX_PER_HIT := 0.5
const TOE_AXLE_MAX := 0.02
const GRIP_LOSS_MAX := 0.15
const FADE_TICKS := 240   # 2 s at the game's 120 Hz; counted in ticks, never time
## A corner's damper goes on its third hard kerb strike (and every one after).
const KERB_STRIKES_TO_DAMPER := 3
## Landings: a wheel that was in the air for LANDING_AIR_MIN and comes down
## faster than LANDING_FREE_MS (4 m/s is a 0.8 m drop) hurts its damper.
const LANDING_AIR_MIN := 0.15
const LANDING_FREE_MS := 4.0
const LANDING_DAMAGE_PER_MS := 0.08
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
const REPAIR_PRICE := {"radiator": 400, "steer_fl": 250, "steer_fr": 250, "susp_rl": 300, "susp_rr": 300, "body": 600,
	"toe_rl": 200, "toe_rr": 200, "camber_fl": 150, "camber_fr": 150, "camber_rl": 150, "camber_rr": 150,
	"sag_fl": 250, "sag_fr": 250, "damper_fl": 180, "damper_fr": 180, "damper_rl": 180, "damper_rr": 180,
	"rack": 350, "brake_fl": 200, "brake_fr": 200, "brake_rl": 200, "brake_rr": 200}
const LAMP_PRICE := 60
const TOW_PRICE := 150
## A station's free patch brings the radiator back to here (no performance loss).
const PATCH_TO := FREE_BELOW - 0.01

var enabled := true
var parts: Array[float] = []
var lamps: Array[bool] = [false, false, false, false]   # true = broken
## The night number of the last free patch; one patch per night.
var patched_night := -1
## 0..1, unused yet: a totalled car (the save core stores it).
var totalled := 0.0
## Where the damage is heading: rebuilt only when damage changes.
var offsets := DamageOffsets.new()
## What the sim reads on top of the tune: `offsets`, faded in over FADE_TICKS.
var applied := DamageOffsets.new()
## Steering wheel turn per unit of road wheel turn, for STEER_CENTRE (the
## cockpit's 1.5 turns lock to lock over 40 degrees; the camera sets the car's).
var steering_ratio := 6.75
var hits := 0
var last_hit_dv := 0.0
var last_hit_dir := Vector2.ZERO   # car-local (x, z) of the velocity change

## Kerb strikes this car has taken, and the speed into the kerb of the last.
var kerb_strikes := 0
var last_kerb_strike := 0.0
## Counted kerb strikes per corner (FL, FR, RL, RR), for the dampers.
var kerb_corner: Array[int] = [0, 0, 0, 0]
var landings := 0
var last_landing := 0.0

var _on_kerb: Array[bool] = [false, false, false, false]
var _prev_vel := Vector3.ZERO
var _hit_dv := Vector3.ZERO
var _hit_left := -1.0
var _wait := 0.0
var _active: Array[bool] = []
var _fade_from := PackedFloat32Array()
var _fade_left := 0
var _air: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _fall: Array[float] = [0.0, 0.0, 0.0, 0.0]

func _init() -> void:
	parts.resize(PART_NAMES.size())
	parts.fill(0.0)
	_active.resize(PART_NAMES.size())
	_active.fill(false)

func part(p: Part) -> float:
	return parts[p]

## 0 below FREE_BELOW, then up to 1 at full damage: how much a part hurts.
static func effect(amount: float) -> float:
	return clampf((amount - FREE_BELOW) / (1.0 - FREE_BELOW), 0.0, 1.0)

## Damage never kills the engine (the fun test, 2026-10-11): always false. The
## name stays for the HUD and the pause menu's tow until a totalled car uses it.
func is_engine_dead() -> bool:
	return false

## The DMG lamp: any part past the free band, or a lamp out.
func warning() -> bool:
	if not enabled:
		return false
	for i in parts.size():
		if i != Part.BODY and parts[i] >= FREE_BELOW:
			return true
	return lamps.has(true)

## Engine cooling multiplier for PowertrainHealth.
func cooling_mult() -> float:
	return 1.0 - COOLING_LOSS * effect(parts[Part.RADIATOR]) if enabled else 1.0

## The cap LimpMode.engine_damage_kmh takes: INF healthy, ENGINE_LIMP_KMH from
## ENGINE_LIMP_AT up to 100 % (never 0).
func engine_cap_kmh() -> float:
	if not enabled:
		return INF
	return ENGINE_LIMP_KMH if parts[Part.RADIATOR] >= ENGINE_LIMP_AT else INF

## Rebuilds the offsets from the parts, at once (no fade). Called by a repair
## and a load; a test or tool that sets `parts` directly calls it too. A hit or
## a kerb strike fades in instead (_damage_changed). The reader functions
## below stay plain readers of the parts.
func rebuild_offsets() -> void:
	_build()
	applied.data = offsets.data.duplicate()
	_fade_left = 0

## A hit, a strike or a landing changed the parts: new target, faded in.
func _damage_changed() -> void:
	_fade_from = applied.data.duplicate()
	_build()
	_fade_left = FADE_TICKS

## One physics tick of the fade; step() calls it. Returns true while fading.
func fade_step() -> bool:
	if _fade_left <= 0:
		return false
	_fade_left -= 1
	if _fade_left == 0:
		applied.data = offsets.data.duplicate()
		return false
	var k := 1.0 - float(_fade_left) / FADE_TICKS
	for i in DamageOffsets.SIZE:
		applied.data[i] = lerpf(_fade_from[i], offsets.data[i], k)
	return true

## How much part p changes the handling, 0..1, before the worst-three rule.
## The radiator and the body are not handling; the rack and the brakes wait
## for GATE_AT.
func handling_effect(p: int) -> float:
	if p == Part.RADIATOR or p == Part.BODY:
		return 0.0
	if GATED_PARTS.has(p) and parts[p] < GATE_AT:
		return 0.0
	return effect(parts[p])

## The parts whose handling effects count right now: the MAX_EFFECTS biggest,
## ties to the part listed first. Set by the last build.
func active_effects() -> Array[int]:
	var out: Array[int] = []
	for p in _active.size():
		if _active[p]:
			out.append(p)
	return out

## Part p's handling effect after the worst-three rule (0 if it lost).
func felt(p: int) -> float:
	return handling_effect(p) if _active[p] else 0.0

func _rank() -> void:
	_active.fill(false)
	for n in MAX_EFFECTS:
		var best := -1
		var best_e := 0.0
		for p in parts.size():
			var e := handling_effect(p)
			if not _active[p] and e > best_e:
				best = p
				best_e = e
		if best < 0:
			return
		_active[best] = true

func _build() -> void:
	offsets.neutral()
	if not enabled:
		return
	_rank()
	var toe_sign := [1.0, -1.0, 1.0, -1.0]   # toward the hit side in front, toe-out behind
	for i in 4:
		var bend := MAX_TOE_BEND if i < 2 else REAR_TOE_BEND
		offsets.set_wheel(i, DamageOffsets.TOE_ADD, toe_sign[i] * bend * felt(TOE_PARTS[i]))
		offsets.set_wheel(i, DamageOffsets.CAMBER_ADD, -deg_to_rad(CAMBER_BEND_DEG) * felt(CAMBER_PARTS[i]))
		var sag := felt(SPRING_PARTS[i])
		offsets.set_wheel(i, DamageOffsets.SPRING_MULT, 1.0 - SPRING_LOSS * sag)
		offsets.set_wheel(i, DamageOffsets.RIDE_DROP, RIDE_DROP_M * sag)
		offsets.set_wheel(i, DamageOffsets.DAMPER_MULT, 1.0 - DAMPER_LOSS * felt(DAMPER_PARTS[i]))
		offsets.set_wheel(i, DamageOffsets.BRAKE_MULT, 1.0 - BRAKE_LOSS * felt(BRAKE_PARTS[i]))
	offsets.set_car(DamageOffsets.STEER_LOCK_MULT, 1.0 - RACK_LOSS * felt(Part.RACK))
	offsets.set_car(DamageOffsets.COOLING_MULT, cooling_mult())
	apply_caps(offsets)
	# the wheel sits crooked by the front toe bend, turned the way that holds the car straight
	offsets.set_car(DamageOffsets.STEER_CENTRE, steering_ratio
			* (offsets.get_wheel(0, DamageOffsets.TOE_ADD) + offsets.get_wheel(1, DamageOffsets.TOE_ADD)))

## The caps on built offsets: the toe adds of an axle sum to at most
## TOE_AXLE_MAX either way, and the grip multipliers multiply to at least
## 1 - GRIP_LOSS_MAX. Scales, never reorders.
static func apply_caps(o: RefCounted) -> void:
	for axle in 2:
		var a := axle * 2
		var total: float = o.get_wheel(a, DamageOffsets.TOE_ADD) + o.get_wheel(a + 1, DamageOffsets.TOE_ADD)
		if absf(total) > TOE_AXLE_MAX:
			var k := TOE_AXLE_MAX / absf(total)
			o.set_wheel(a, DamageOffsets.TOE_ADD, o.get_wheel(a, DamageOffsets.TOE_ADD) * k)
			o.set_wheel(a + 1, DamageOffsets.TOE_ADD, o.get_wheel(a + 1, DamageOffsets.TOE_ADD) * k)
	var grip := 1.0
	for i in 4:
		grip *= o.get_wheel(i, DamageOffsets.GRIP_MULT)
	var floor_grip := 1.0 - GRIP_LOSS_MAX
	if grip < floor_grip and grip > 0.0:
		# raise every multiplier by the same power so the product lands on the floor
		var power := log(floor_grip) / log(grip)
		for i in 4:
			o.set_wheel(i, DamageOffsets.GRIP_MULT, pow(o.get_wheel(i, DamageOffsets.GRIP_MULT), power))

## The damage pull in `o` as one angle (rad at the road wheels, + = left like
## a wheel's rotation.y): the front axle's mean toe add, less the rear's (a
## rear axle pointing left yaws the car right). The car holds a share of minus
## this when no steer key is down (PlayerCar.damage_trim).
static func pull_angle(o: RefCounted) -> float:
	var front: float = o.get_wheel(0, DamageOffsets.TOE_ADD) + o.get_wheel(1, DamageOffsets.TOE_ADD)
	var rear: float = o.get_wheel(2, DamageOffsets.TOE_ADD) + o.get_wheel(3, DamageOffsets.TOE_ADD)
	return (front - rear) * 0.5

## Toe a bent front arm adds to wheel i (FL, FR), before the worst-three rule:
## bent toward the hit side, so the car pulls that way (a wheel's rotation.y
## turns it left when positive). The rear's toe is the TOE_RL / TOE_RR parts.
func toe_offset(i: int) -> float:
	match i:
		0:
			return MAX_TOE_BEND * effect(parts[Part.STEER_FL])
		1:
			return -MAX_TOE_BEND * effect(parts[Part.STEER_FR])
	return 0.0

## Rear spring rate multiplier for wheel i, before the worst-three rule.
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
	for i in Part.BODY + 1:   # the slice 1 parts; the corner parts ride on the same hits
		worst = maxf(worst, parts[i])
		total += parts[i]
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
	# wheel corners (DP1): the same split
	_add(Part.SAG_FL, amount * share[0])
	_add(Part.SAG_FR, amount * share[1])
	_add(Part.TOE_RL, amount * share[2])
	_add(Part.TOE_RR, amount * share[3])
	if front * front >= RACK_FRONT_MIN:
		_add(Part.RACK, amount * front * front)
	for i in 4:
		if share[i] >= BRAKE_SHARE_MIN:
			_add(BRAKE_PARTS[i], amount * share[i])
	# camber: the side share, on the hit side's two wheels, more on the end the hit leans to
	var side := d.x * d.x
	if side >= CAMBER_SIDE_MIN:
		var first := 0 if d.x > 0.0 else 1   # from the left = +x
		_add(CAMBER_PARTS[first], amount * side * 0.5 * (1.0 + d.y))
		_add(CAMBER_PARTS[first + 2], amount * side * 0.5 * (1.0 - d.y))
	for i in 4:
		if amount * share[i] >= LAMP_BREAK:
			lamps[[Lamp.HEAD_L, Lamp.HEAD_R, Lamp.TAIL_L, Lamp.TAIL_R][i]] = true
	_damage_changed()

## One kerb strike from raw numbers (testable without a car): wheel i (FL,
## FR, RL, RR) met the kerb at `approach` m/s across the kerb face.
func apply_kerb_strike(i: int, approach: float) -> void:
	if not enabled or approach <= KERB_FREE_MS:
		return
	var amount := (approach - KERB_FREE_MS) * KERB_DAMAGE_PER_MS
	i = clampi(i, 0, 3)
	kerb_strikes += 1
	last_kerb_strike = approach
	kerb_corner[i] += 1
	_add([Part.STEER_FL, Part.STEER_FR, Part.SUSP_RL, Part.SUSP_RR][i], amount)
	if i >= 2:
		_add(TOE_PARTS[i], amount)
	if kerb_corner[i] >= KERB_STRIKES_TO_DAMPER:
		_add(DAMPER_PARTS[i], amount)
	_add(Part.BODY, amount * KERB_BODY_SHARE)
	_damage_changed()

## One landing from raw numbers (testable without a car): wheel i came down
## at `fall` m/s after time in the air. Over LANDING_FREE_MS it hurts that
## wheel's damper.
func apply_landing(i: int, fall: float) -> void:
	if not enabled or fall <= LANDING_FREE_MS:
		return
	landings += 1
	last_landing = fall
	_add(DAMPER_PARTS[clampi(i, 0, 3)], (fall - LANDING_FREE_MS) * LANDING_DAMAGE_PER_MS)
	_damage_changed()

## Times each wheel's air and, on touch-down, lands it (apply_landing).
func _landing_step(v: Vehicle, dt: float) -> void:
	var fall := -v.linear_velocity.y
	for i in mini(4, v.wheel_array.size()):
		if (v.wheel_array[i] as Wheel).is_colliding():
			if _air[i] >= LANDING_AIR_MIN:
				apply_landing(i, _fall[i])
			_air[i] = 0.0
			_fall[i] = 0.0
		else:
			_air[i] += dt
			_fall[i] = maxf(_fall[i], fall)

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

## One hit's worth on one part: never more than MAX_PER_HIT.
func _add(p: Part, a: float) -> void:
	parts[p] = clampf(parts[p] + minf(a, MAX_PER_HIT), 0.0, 1.0)

## The car was moved and stopped by the game (off-map rescue): the jump in
## velocity is not a hit.
func forget_motion() -> void:
	_prev_vel = Vector3.ZERO
	_hit_dv = Vector3.ZERO
	_hit_left = -1.0
	_air.fill(0.0)
	_fall.fill(0.0)

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

## One step on the car: moves the fade on a tick, reads contacts (a hit, a kerb
## strike or a landing gives new offsets) and sets the engine's limp cap. The offsets themselves are applied
## by the car (PlayerCar._apply_damage_offsets), on top of the tune.
func step(v: Vehicle, dt: float, _health: PowertrainHealth, limp: LimpMode) -> void:
	if not enabled:
		return
	fade_step()
	step_values(dt, v.linear_velocity, v.global_transform.basis, _touching(v))
	_kerb_step(v)
	_landing_step(v, dt)
	limp.engine_damage_kmh = engine_cap_kmh()

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
	kerb_corner.fill(0)
	rebuild_offsets()
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
## to the no-loss band (the limp ends). Returns true if it patched.
func station_patch(night: int) -> bool:
	if not enabled or night == patched_night or parts[Part.RADIATOR] < FREE_BELOW:
		return false
	parts[Part.RADIATOR] = PATCH_TO
	patched_night = night
	rebuild_offsets()
	return true

## Ferris's tow: kept for a totalled car (the engine never dies from damage
## now, so nothing calls it yet). Never during a chase. Paid from the bank, as much as it holds
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
	var d := {"lamps": lamps.duplicate(), "patched_night": patched_night, "totalled": totalled, "kerb_corner": kerb_corner.duplicate()}
	for i in parts.size():
		d[PART_NAMES[i]] = parts[i]
	return d

func from_dict(d: Dictionary) -> void:
	for i in parts.size():
		parts[i] = clampf(float(d.get(PART_NAMES[i], 0.0)), 0.0, 1.0)
	var l: Array = d.get("lamps", [])
	for i in lamps.size():
		lamps[i] = bool(l[i]) if i < l.size() else false
	var kc: Array = d.get("kerb_corner", [])
	for i in kerb_corner.size():
		kerb_corner[i] = int(kc[i]) if i < kc.size() else 0
	patched_night = int(d.get("patched_night", -1))
	totalled = clampf(float(d.get("totalled", 0.0)), 0.0, 1.0)
	rebuild_offsets()
