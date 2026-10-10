class_name FuelTank
extends RefCounted

# Fuel, v1 (Stage C, 2026-10-09). Roy's decisions (damage/fuel design notes):
# - the tank starts about a third full, so the first stop for fuel comes early
# - one fill-up lasts most of a night (sized when a night was 20 real minutes; it is 40 since
#   2026-10-09, so a tank now covers under half: recalibrate if wanted)
# - a dry tank never ends the run: the car limps at LimpMode.FUEL_KMH
# - fuel is paid from the BANK, never the night's pot
#
# Burn follows engine power: a little at idle, the rest in proportion to load,
# so cruising lasts longer than flat-out. Game-scaled on purpose (a real tank
# lasts hours); the litres are only for the gauge and the price.
#
# Off (enabled = false) for sim_only cars and traffic, like PowertrainHealth.
# Tests start with a full tank (TestMode) so long drive tests never hit limp by
# accident; tests that want the real start set `litres` themselves.
#
# The state is one number so a stop or the garage can save it later.

const TestMode := preload("res://scripts/core/test_mode.gd")
const TestBuild := preload("res://scripts/core/test_build.gd")

const CAPACITY_L := 50.0
const START_FRACTION := 1.0 / 3.0
## Seconds a full tank lasts at full engine load (8 min flat out). The rest is
## idle burn, so the tank is part clock: ~27 min idling, ~16.6 min in a city
## cycle with stops (tests/car/fuel_limp.gd: most of the old 20-minute night).
const FULL_LOAD_SECONDS := 480.0
## Fraction of the full-load burn the engine uses at idle.
const IDLE_SHARE := 0.3
## The FUEL light comes on below this fraction.
const LOW_FRACTION := 0.12
## Placeholder price in Cred per litre, until the economy pass sets it.
const PRICE_PER_LITRE := 3

var enabled := true
var litres := CAPACITY_L * START_FRACTION

func _init() -> void:
	if TestMode.active():
		litres = CAPACITY_L

func fraction() -> float:
	return litres / CAPACITY_L

func is_empty() -> bool:
	return enabled and litres <= 0.0

func is_low() -> bool:
	return enabled and fraction() < LOW_FRACTION

## Litres per second at a load 0..1 with the engine running.
static func burn_rate(eload: float) -> float:
	return CAPACITY_L / FULL_LOAD_SECONDS * (IDLE_SHARE + (1.0 - IDLE_SHARE) * clampf(eload, 0.0, 1.0))

## One step from raw numbers (testable without a car).
func step_values(dt: float, eload: float, engine_running: bool) -> void:
	if not enabled or not engine_running:
		return
	litres = maxf(litres - burn_rate(eload) * dt, 0.0)

## Fills from the bank: as many whole litres as fit and the bank covers, up to
## `max_litres`. `bank` is anything with an int `bank` and spend_bank(int) -> bool
## (Wallet). Returns the litres bought; nothing changes when the bank is empty.
func refuel(bank: Object, max_litres := INF) -> float:
	if bank == null:
		return 0.0
	var room := minf(CAPACITY_L - litres, max_litres)
	var want := int(ceil(room - 0.001))
	var can := floori(float(bank.get("bank")) / PRICE_PER_LITRE) if PRICE_PER_LITRE > 0 else want
	if TestBuild.on():
		can = want  # sandbox: the pump always fills, whatever the bank holds
	var buy := clampi(mini(want, can), 0, want)
	if buy <= 0 or not bank.call("spend_bank", buy * PRICE_PER_LITRE):
		return 0.0
	var got := minf(float(buy), CAPACITY_L - litres)
	litres += got
	return got

func to_dict() -> Dictionary:
	return {"litres": litres}

func from_dict(d: Dictionary) -> void:
	litres = clampf(float(d.get("litres", litres)), 0.0, CAPACITY_L)
