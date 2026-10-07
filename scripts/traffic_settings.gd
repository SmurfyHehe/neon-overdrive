class_name TrafficSettings
extends RefCounted

# Traffic settings (stage B step 3, 2026-10-05): how many cars are on the road
# and the traffic draw distance, in the same user://settings.cfg AudioSettings
# uses (its own [traffic] section). The pause menu shows two sliders; Game
# applies the saved values when it builds the TrafficManager.
#
# Draw distance is also the sim-quality distance: a car beyond it is hidden and
# runs the frozen lane cruise instead of the raycast sim (traffic_car.gd).
# 300 m (the chunk pool) keeps every car in the full sim, which is Option C.
#
# Budget (2026-10-06, traffic milestone 4, Roy: default 40 -> 16): a full-sim
# car costs 0.19-0.36 ms per 120 Hz tick (tests/traffic_perf.gd, i5-1235U,
# headless, so no rendering in that number). At 60 fps two 120 Hz ticks run
# per rendered frame, so the 16.7 ms frame holds 2 ticks plus the render: the
# physics budget is about 4 ms per tick, not the 8.33 ms tick length the old
# 40-car default was sized against. ~0.6 ms of that is the player and the
# world with no traffic, which leaves room for roughly 12-16 full-sim cars.
# 16 cars at the 150 m default draw distance keeps most of them full-sim at
# well under that. The slider still goes to 80 for machines with room.

const CAR_COUNT_DEFAULT := 16
const CAR_COUNT_MAX := 80
const DETAIL_DEFAULT := 150.0
const DETAIL_MIN := 50.0
const DETAIL_MAX := 300.0

static var car_count := CAR_COUNT_DEFAULT
static var detail_distance := DETAIL_DEFAULT

static func set_car_count(n: int) -> void:
	car_count = clampi(n, 0, CAR_COUNT_MAX)

static func set_detail_distance(d: float) -> void:
	detail_distance = clampf(d, DETAIL_MIN, DETAIL_MAX) if is_finite(d) else DETAIL_DEFAULT  # clampf passes NaN through

## Reads the file (missing or damaged means defaults). Shares AudioSettings.path
## so tests that redirect one redirect both.
static func load_settings() -> void:
	var cfg := ConfigFile.new()
	var ok := cfg.load(AudioSettings.path) == OK
	var n: Variant = cfg.get_value("traffic", "car_count", CAR_COUNT_DEFAULT) if ok else CAR_COUNT_DEFAULT
	set_car_count(int(n) if is_finite(float(n)) else CAR_COUNT_DEFAULT)  # int(NaN) is a huge negative
	set_detail_distance(float(cfg.get_value("traffic", "detail_distance", DETAIL_DEFAULT)) if ok else DETAIL_DEFAULT)

## Rewrites only the [traffic] section; the audio values stay.
static func save_settings() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)
	cfg.set_value("traffic", "car_count", car_count)
	cfg.set_value("traffic", "detail_distance", detail_distance)
	return cfg.save(AudioSettings.path) == OK
