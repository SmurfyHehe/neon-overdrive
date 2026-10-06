class_name TrafficSettings
extends RefCounted

# Traffic settings (stage B step 3, 2026-10-05): how many cars are on the road
# and the traffic draw distance, in the same user://settings.cfg AudioSettings
# uses (its own [traffic] section). The pause menu shows two sliders; Game
# applies the saved values when it builds the TrafficManager.
#
# Draw distance is also the sim-quality distance: a car beyond it is hidden and
# runs the frozen lane cruise instead of the raycast sim (traffic_car.gd).
# 300 m (the chunk pool) keeps every car in the full sim, which is Option C;
# measured 2026-10-05 (tests/traffic_perf.gd, i5-1235U, headless): a full-sim
# car costs about 0.22 ms per 120 Hz tick, so 40 cars at 300 m is 9.6 ms, over
# the 8.33 ms tick with no rendering counted. The default of 150 m keeps
# roughly half of 40 cars full-sim; Roy's in-game fps decides the final value.

const CAR_COUNT_DEFAULT := 40
const CAR_COUNT_MAX := 80
const DETAIL_DEFAULT := 150.0
const DETAIL_MIN := 50.0
const DETAIL_MAX := 300.0

static var car_count := CAR_COUNT_DEFAULT
static var detail_distance := DETAIL_DEFAULT

static func set_car_count(n: int) -> void:
	car_count = clampi(n, 0, CAR_COUNT_MAX)

static func set_detail_distance(d: float) -> void:
	detail_distance = clampf(d, DETAIL_MIN, DETAIL_MAX)

## Reads the file (missing or damaged means defaults). Shares AudioSettings.path
## so tests that redirect one redirect both.
static func load_settings() -> void:
	var cfg := ConfigFile.new()
	var ok := cfg.load(AudioSettings.path) == OK
	set_car_count(int(cfg.get_value("traffic", "car_count", CAR_COUNT_DEFAULT)) if ok else CAR_COUNT_DEFAULT)
	set_detail_distance(float(cfg.get_value("traffic", "detail_distance", DETAIL_DEFAULT)) if ok else DETAIL_DEFAULT)

## Rewrites only the [traffic] section; the audio values stay.
static func save_settings() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)
	cfg.set_value("traffic", "car_count", car_count)
	cfg.set_value("traffic", "detail_distance", detail_distance)
	return cfg.save(AudioSettings.path) == OK
