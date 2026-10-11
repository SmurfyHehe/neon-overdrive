class_name LimpMode
extends RefCounted

# Limp mode by physics (brief LM, 2026-10-11). Roy: "holding to 60 km/h doesn't
# feel realistic because it's just a limit on the number, not on torque and
# things like that." No cause sets a speed. Each one changes what the engine
# and the gearbox can do, and the speed the car ends up at comes out of the
# sim, so it differs per car:
#
# - engine limp (OVERHEAT: the engine at PowertrainHealth.LIMP_C; ENGINE: set
#   by the damage system, later the totalled meter): what a real engine
#   computer does to get you home. Revs held to ENGINE_REV_FRAC of the redline
#   by a fuel cut that bounces, no boost, ENGINE_TORQUE of the torque, and the
#   gearbox no higher than ENGINE_MAX_GEAR.
# - fuel dry (FUEL): starvation. The engine cuts out for 0.1-0.3 s at a time,
#   more often on a wide throttle, under side load (slosh) and uphill; about
#   FUEL_FLAT_SHARE of the torque gets through at full throttle on the flat.
#
# Worst wins per field (Roy's rule, as before): two causes never multiply,
# each field takes the worse of the two.
#
# Nothing here is random: the stumble is a pattern that depends only on the
# inputs it has been stepped with, so the same drive gives the same stumbles.
#
# A flat tyre on its rim is not here: it does not touch the engine. See
# flat_tyre.gd.

enum Cause { NONE = 0, FUEL = 1, OVERHEAT = 2, ENGINE = 4 }

## Engine limp: share of the redline (Vehicle.max_rpm) the revs are held to.
const ENGINE_REV_FRAC := 0.55
const ENGINE_TORQUE := 0.6
const ENGINE_MAX_GEAR := 3
## Once the overheat limp is on it stays until the engine is back under this
## (PowertrainHealth.DERATE_C), like a real limp-home: without it the limp's
## own torque cut cools the engine a degree and the limp flickers off and on.
const OVERHEAT_EXIT_C := PowertrainHealth.DERATE_C
## The soft cut: fuel comes back once the revs have fallen this far below the
## limit, so the engine bounces off it instead of sitting on a wall.
const REV_CUT_HYSTERESIS_RPM := 250.0

## Fuel starvation: every cut lasts between these, in a fixed repeating order.
const STUMBLE_MIN_S := 0.1
const STUMBLE_MAX_S := 0.3
## Share of the torque that gets through at full throttle on a flat straight.
const FUEL_FLAT_SHARE := 0.35
## How much a wide throttle, side load and a climb each shorten the run
## between cuts: demand = (THROTTLE_FLOOR..1) x (1 + g x LAT_G) x (1 + grade x GRADE).
const STUMBLE_THROTTLE_FLOOR := 0.25
const STUMBLE_PER_LAT_G := 1.0
const STUMBLE_PER_GRADE := 6.0
## Seconds the engine runs between cuts at demand 1, worked out so the average
## cut (the middle of MIN..MAX) leaves FUEL_FLAT_SHARE.
const STUMBLE_RUN_S := (STUMBLE_MIN_S + STUMBLE_MAX_S) * 0.5 * FUEL_FLAT_SHARE / (1.0 - FUEL_FLAT_SHARE)
## The cut lengths walk MIN..MAX by this step (the golden ratio's fraction:
## it never settles into a short loop the ear can pick out).
const STUMBLE_STEP := 0.6180339887

## Set by the damage system: the engine itself asks for limp-home.
var engine_damaged := false

## What the car reads, refreshed by update(). Healthy: 1, 1, 1, 99, 0.
var rev_limit_frac := 1.0
var boost_mult := 1.0
var torque_mult := 1.0
var max_gear := 99
var stumble := 0.0
## Read-outs for the dash lamps, the HUD and tests. `cause` is the most
## serious active one (engine, then overheat, then fuel).
var cause := Cause.NONE
var active_causes := 0

## True while the fuel is cut, by the rev limit or by a stumble.
var fuel_cut := false
## Stumbles so far (tests, and a hook for the engine's cough).
var stumble_count := 0

var _rev_cut := false
var _overheated := false
var _stumble_left := 0.0
var _run_phase := 0.0
var _stumble_index := 0

## Works out the multipliers from the car's state.
func update(fuel_empty: bool, engine_temp: float) -> void:
	active_causes = 0
	if fuel_empty:
		active_causes |= Cause.FUEL
	if engine_temp >= PowertrainHealth.LIMP_C:
		_overheated = true
	elif engine_temp < OVERHEAT_EXIT_C:
		_overheated = false
	if _overheated:
		active_causes |= Cause.OVERHEAT
	if engine_damaged:
		active_causes |= Cause.ENGINE
	rev_limit_frac = 1.0
	boost_mult = 1.0
	torque_mult = 1.0
	max_gear = 99
	stumble = 0.0
	cause = Cause.NONE
	if active_causes & Cause.FUEL:
		stumble = maxf(stumble, 1.0)
		cause = Cause.FUEL
	if active_causes & (Cause.OVERHEAT | Cause.ENGINE):
		rev_limit_frac = minf(rev_limit_frac, ENGINE_REV_FRAC)
		boost_mult = minf(boost_mult, 0.0)
		torque_mult = minf(torque_mult, ENGINE_TORQUE)
		max_gear = mini(max_gear, ENGINE_MAX_GEAR)
		cause = Cause.ENGINE if active_causes & Cause.ENGINE else Cause.OVERHEAT
	if stumble <= 0.0:
		_stumble_left = 0.0
		_run_phase = 0.0

func is_limping() -> bool:
	return active_causes != 0

## The engine computer's limp-home (the engine lamp): overheat or engine damage.
func is_engine_limp() -> bool:
	return (active_causes & (Cause.OVERHEAT | Cause.ENGINE)) != 0

## Engine torque multiplier before any fuel cut: the worse of the health
## derate and the limp's own, never their product.
func torque_for(health_mult: float) -> float:
	return minf(health_mult, torque_mult)

## One tick of the fuel cuts. rpm and redline in rpm; throttle 0..1; lat_g the
## car's side load in g; grade the road's climb as a slope (0.05 = 5 % uphill,
## negative downhill). Returns true while the fuel is cut: the caller gives the
## engine no torque for that tick.
func step_cut(dt: float, rpm: float, redline: float, throttle: float, lat_g: float, grade: float) -> bool:
	# the rev limit: a soft cut with hysteresis, so it bounces
	if rev_limit_frac < 1.0:
		var limit := redline * rev_limit_frac
		if rpm > limit:
			_rev_cut = true
		elif rpm < limit - REV_CUT_HYSTERESIS_RPM:
			_rev_cut = false
	else:
		_rev_cut = false
	# starvation: run for a while (shorter the more the engine asks for), then
	# cut for the next length in the fixed order
	var starved := false
	if stumble > 0.0:
		if _stumble_left > 0.0:
			_stumble_left -= dt
			starved = true
		else:
			var demand := lerpf(STUMBLE_THROTTLE_FLOOR, 1.0, clampf(throttle, 0.0, 1.0)) \
				* (1.0 + absf(lat_g) * STUMBLE_PER_LAT_G) * (1.0 + maxf(grade, 0.0) * STUMBLE_PER_GRADE)
			_run_phase += dt * demand * stumble / STUMBLE_RUN_S
			if _run_phase >= 1.0:
				_run_phase -= 1.0
				_stumble_left = stumble_length(_stumble_index) - dt  # this tick is the first of the cut
				_stumble_index += 1
				stumble_count += 1
				starved = true
	fuel_cut = _rev_cut or starved
	return fuel_cut

## Length (s) of the n-th stumble: MIN..MAX in a fixed, never-random order.
static func stumble_length(n: int) -> float:
	return lerpf(STUMBLE_MIN_S, STUMBLE_MAX_S, fposmod(0.5 + n * STUMBLE_STEP, 1.0))

static func cause_name(c: int) -> String:
	match c:
		Cause.FUEL:
			return "NO FUEL"
		Cause.OVERHEAT:
			return "OVERHEAT"
		Cause.ENGINE:
			return "ENGINE"
	return ""
