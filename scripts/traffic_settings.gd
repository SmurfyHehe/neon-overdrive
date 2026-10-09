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
## Night lights (2026-10-07): scales the traffic tail lamps, their distance
## flares and the median barrier's reflectors together. 0 is the old look
## (lamps at the headlight level, no flares, dark reflectors); 1 the default.
## Purely what you see: no car, sim or hitbox changes with it.
const LIGHT_GLOW_DEFAULT := 1.0
const LIGHT_GLOW_MIN := 0.0
const LIGHT_GLOW_MAX := 2.0

## City lights (2026-10-09, Junction J0/J1a): one signalised crossing on the
## road, traffic stopping at red. Off by default; takes effect on Restart (the
## crossing is part of the road layout, built before the first chunk).
const CITY_LIGHTS_DEFAULT := false

static var car_count := CAR_COUNT_DEFAULT
static var city_lights := CITY_LIGHTS_DEFAULT
static var detail_distance := DETAIL_DEFAULT
static var light_glow := LIGHT_GLOW_DEFAULT

static func set_car_count(n: int) -> void:
	car_count = clampi(n, 0, CAR_COUNT_MAX)

static func set_detail_distance(d: float) -> void:
	detail_distance = clampf(d, DETAIL_MIN, DETAIL_MAX) if is_finite(d) else DETAIL_DEFAULT  # clampf passes NaN through

## Sets and applies the night-lights level (shared materials: every car and
## chunk changes at once, built or not).
static func set_light_glow(g: float) -> void:
	light_glow = clampf(g, LIGHT_GLOW_MIN, LIGHT_GLOW_MAX)
	NpcCarBuilder.set_light_glow(light_glow)
	RoadChunkBuilder.set_reflector_glow(light_glow)

## Reads the file (missing or damaged means defaults). Shares AudioSettings.path
## so tests that redirect one redirect both.
static func load_settings() -> void:
	var cfg := ConfigFile.new()
	var ok := cfg.load(AudioSettings.path) == OK
	var n: Variant = cfg.get_value("traffic", "car_count", CAR_COUNT_DEFAULT) if ok else CAR_COUNT_DEFAULT
	set_car_count(int(n) if is_finite(float(n)) else CAR_COUNT_DEFAULT)  # int(NaN) is a huge negative
	set_detail_distance(float(cfg.get_value("traffic", "detail_distance", DETAIL_DEFAULT)) if ok else DETAIL_DEFAULT)
	set_light_glow(float(cfg.get_value("traffic", "light_glow", LIGHT_GLOW_DEFAULT)) if ok else LIGHT_GLOW_DEFAULT)
	city_lights = (cfg.get_value("traffic", "city_lights", CITY_LIGHTS_DEFAULT) == true) if ok else CITY_LIGHTS_DEFAULT
	# NEON_CITY_LIGHTS=1/0 overrides it for one run (tests, screenshots).
	var lights_env := OS.get_environment("NEON_CITY_LIGHTS")
	if lights_env == "1" or lights_env == "0":
		city_lights = lights_env == "1"
	# NEON_NIGHT_LIGHTS=<0-2> overrides it for one run (frame-cost A/B), like NEON_FX.
	var env := OS.get_environment("NEON_NIGHT_LIGHTS")
	if env.is_valid_float():
		set_light_glow(env.to_float())

## Rewrites only the [traffic] section; the audio values stay.
static func save_settings() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)
	cfg.set_value("traffic", "car_count", car_count)
	cfg.set_value("traffic", "detail_distance", detail_distance)
	cfg.set_value("traffic", "light_glow", light_glow)
	cfg.set_value("traffic", "city_lights", city_lights)
	return cfg.save(AudioSettings.path) == OK
