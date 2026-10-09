# Exhaust tune (stage B step 2, 2026-10-05). Four knobs, all 0..1, plus the
# anti-lag switch (2026-10-07), all
# COSMETIC: they change what the exhaust sounds and looks like and nothing
# else. No wear, heat, fuel, police or physics effect (Roy's decision,
# ROADMAP stage B). EngineSynth reads them; a flame visual reads the events
# EngineSynth.take_flames() hands out.
extends RefCounted
class_name ExhaustTune

const TestMode := preload("res://scripts/test_mode.gd")

## How loud the whole exhaust note is. 0.5 is the prototype's old level.
var loudness := 0.5
## Roughness: harder edge, more buzz, more noise in the pulse.
var raspiness := 0.3
## Overrun pops and crackles when the throttle is lifted at rpm. 0 = none.
var pops := 0.3
## Flamethrower: how much fire a pop or a rev-limiter cut spits out the tip.
## 0 = no flames. Cosmetic: it only sizes the flame events.
var flame := 0.0
## Anti-lag crackle switch (exhaust flames, 2026-10-07, Roy: cosmetic only, its
## own switch). 0 = off, 1 = on; a float so tune slots and the save file treat
## it like the knobs. On: lifting off at rpm keeps banging and spitting fire the
## way a rally car's anti-lag does. No boost, wear or physics effect.
## Turbo cars only (exhaust sound research, option A, 2026-10-07): every car
## preset has it on (for_car()), but it only fires while the car has a turbo (see
## anti_lag_live()). A naturally aspirated car keeps the switch and stays quiet.
## A bare ExhaustTune.new() (a synth with no car) has it off.
var anti_lag := 0.0

## Where the player's tune is kept between runs (one entry per car id). Tests
## point this at a scratch file so they never read or write the real one.
static var save_path := TestMode.path("user://exhaust_tune.json")

const KEYS := ["loudness", "raspiness", "pops", "flame", "anti_lag"]

func _init(l := 0.5, r := 0.3, p := 0.3, f := 0.0, al := 0.0) -> void:
	loudness = l
	raspiness = r
	pops = p
	flame = f
	anti_lag = al

## The knobs as {key: float}, the form a car's spec holds under "exhaust" and a
## saved file stores.
func to_dict() -> Dictionary:
	return {"loudness": loudness, "raspiness": raspiness, "pops": pops, "flame": flame, "anti_lag": anti_lag}

## Copies the knobs of a {key: float} dictionary into this tune (keys it does not
## have are left alone), clamped to 0..1.
func apply_dict(d: Dictionary) -> void:
	loudness = clampf(float(d.get("loudness", loudness)), 0.0, 1.0)
	raspiness = clampf(float(d.get("raspiness", raspiness)), 0.0, 1.0)
	pops = clampf(float(d.get("pops", pops)), 0.0, 1.0)
	flame = clampf(float(d.get("flame", flame)), 0.0, 1.0)
	anti_lag = 1.0 if float(d.get("anti_lag", anti_lag)) >= 0.5 else 0.0  # a switch

## The saved tune of a car as {key: float}, or {} if there is none (no file, a
## file that will not parse, or no entry for this car).
static func load_saved(car_id: String) -> Dictionary:
	var cars := _read_cars()
	var d: Variant = cars.get(car_id)
	if not d is Dictionary:
		return {}
	var out := {}
	for k in KEYS:
		if d.has(k) and (d[k] is float or d[k] is int):
			out[k] = clampf(float(d[k]), 0.0, 1.0)
	return out

## Stores a car's tune, keeping the other cars' entries. A file that will not
## parse is replaced. Returns false if the file cannot be written.
static func save_car(car_id: String, d: Dictionary) -> bool:
	var cars := _read_cars()
	var entry := {}
	for k in KEYS:
		if d.has(k):
			entry[k] = snappedf(float(d[k]), 0.001)
	cars[car_id] = entry
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		push_error("ExhaustTune: cannot write %s (%s)" % [save_path, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify({"version": 1, "cars": cars}, "	"))
	return true

static func _read_cars() -> Dictionary:
	if not FileAccess.file_exists(save_path):
		return {}
	var json := JSON.new()  # parse() reports an error code; parse_string() prints an engine error
	if json.parse(FileAccess.get_file_as_string(save_path)) != OK:
		return {}
	var parsed: Variant = json.data
	if parsed is Dictionary and parsed.get("cars") is Dictionary:
		return parsed.cars
	return {}

## Per-car starting tunes, keyed by the fleet ids in docs/design/fleet/fleet.json.
## Order: loudness, raspiness, pops, flame. Anti-lag starts off on every car. Researched 2026-10-05 and mostly
## judgement calls: no per-car dB or pop data is published. Grounding:
## - pops are an ECU-tune effect (overrun fuel cut off, retarded ignition), so
##   stock-type cars pop rarely (https://www.bristol-tuning.com/services/overrun-pop-crackle/);
## - flames come mainly from turbo anti-lag, so only the turbo/tuner cars get any;
## - stock cars are quiet (EU pass-by limit 72 dB, https://link.springer.com/article/10.1007/s40111-018-0010-7),
##   aftermarket exhausts add 6-25 dB, e.g. stock STI vs Invidia +6 dB
##   (https://www.iwsti.com/threads/exhaust-sound-levels.281359/), stock Supra vs
##   aftermarket 81 vs 85-106 dB (https://www.supraforums.com/threads/comparison-of-exhaust-sound-db-levels-on-tt-supra.1106626/);
## - sliders for tone and overrun are how Need for Speed Heat exposes it
##   (https://www.gtplanet.net/exhaust-tuning-will-make-cars-sing-in-need-for-speed-heat/).
## Players are loud and rude, traffic quiet, police subdued. Roy can retune any.
const PRESETS := {
	"p1_coupe":       [0.55, 0.55, 0.35, 0.20],
	"p0_beater":      [0.30, 0.25, 0.20, 0.00],  # one rusty pipe, no flames
	"p2_hothatch":    [0.45, 0.60, 0.30, 0.10],
	"p3_tuner":       [0.70, 0.70, 0.60, 0.45],
	"p4_kei":         [0.40, 0.70, 0.35, 0.15],
	"p5_muscle":      [0.75, 0.45, 0.40, 0.20],
	"p6_crossover":   [0.50, 0.55, 0.40, 0.20],
	"n1_commuter":    [0.12, 0.10, 0.02, 0.00],
	"n2_cityhatch":   [0.20, 0.35, 0.05, 0.00],
	"n3_pickup":      [0.30, 0.35, 0.05, 0.00],
	"c1_patrol":      [0.35, 0.30, 0.05, 0.00],
	"c2_patrolsuv":   [0.30, 0.25, 0.05, 0.00],
	"c3_interceptor": [0.50, 0.40, 0.15, 0.05],
}

## Whether anti-lag fires on this car: the switch is on and the car has a turbo
## (turbo_boost_max > 0). The one rule both the synth feed (EngineAudio) and the
## traffic flame sim use, so sound and fire agree.
static func anti_lag_live(spec: Dictionary) -> bool:
	var ex: Variant = spec.get("exhaust", {})
	var on := ex is Dictionary and float(ex.get("anti_lag", 0.0)) >= 0.5
	return on and float(spec.get("turbo_boost_max", 0.0)) > 0.0

static func for_car(id: String) -> ExhaustTune:
	var p: Array = PRESETS.get(id, [0.5, 0.3, 0.3, 0.0])
	return ExhaustTune.new(p[0], p[1], p[2], p[3], 1.0)  # anti-lag on: it fires only with a turbo
