class_name NightClock
extends Node

# Night game clock (living world step 1, 2026-10-08). The game is played at
# night only: the clock runs from 8 p.m. to 6 a.m. while you drive, stops while
# the game is paused (a pausable node, so the pause menu and the tuner hold it),
# and is saved across sessions in its own file. The HUD and the head unit show
# it, building windows follow it (WindowLights) and Dave reads the hour out on
# his station (RadioManager.announce).
#
# At 6 a.m. the night is over. The tired drive home (a cutscene) is a later
# step; for now the clock rolls straight into the next night at 8 p.m. and
# counts it.
#
# Time is kept as game minutes since 8 p.m. (0 .. NIGHT_MINUTES).

signal hour_changed(hour24: int)
signal night_ended(night: int)

const START_HOUR := 20
const END_HOUR := 6
const NIGHT_MINUTES := 600.0          # 8 p.m. to 6 a.m.
## How long one game hour lasts in real seconds of driving: a whole night is
## 10 of these (20 minutes at 120 s).
const REAL_SECONDS_PER_HOUR := 120.0
## The clock saves itself every this many game minutes, and on exit.
const SAVE_EVERY_MINUTES := 15.0
const DEFAULT_PATH := "user://night_clock.cfg"
const BENCHMARK_MINUTES := 240.0      # midnight
const TestMode := preload("res://scripts/core/test_mode.gd")
const SaveStore := preload("res://scripts/save/save_store.gd")

static var path := TestMode.path(DEFAULT_PATH)

## Game minutes since 8 p.m. this night.
var minutes := 0.0
## Nights finished so far (1 = the first night).
var night := 1
## Multiplies the clock rate; tests turn it up.
var speed := 1.0
## >= 0: the clock is pinned at this time, nothing is loaded or saved
## (benchmark runs must look the same every time).
var fixed_minutes := -1.0
var _last_hour := -1
var _last_save := 0.0

func _ready() -> void:
	name = "NightClock"
	if fixed_minutes >= 0.0:
		minutes = fixed_minutes
		speed = 0.0
		_last_hour = hour24(minutes)
		WindowLights.set_minutes(minutes)
		return
	load_clock()
	# NEON_CLOCK=HH:MM starts the night at that time (tests, screenshots).
	var env := OS.get_environment("NEON_CLOCK")
	if env != "":
		var m := parse_time(env)
		if m >= 0.0:
			minutes = m
	_last_hour = hour24(minutes)
	_last_save = minutes
	WindowLights.set_minutes(minutes)

func _physics_process(delta: float) -> void:
	advance(delta * speed)

## Real seconds of driving pass; the clock moves, windows follow, and the hour
## and dawn signals fire.
func advance(real_seconds: float) -> void:
	minutes += real_seconds * 60.0 / REAL_SECONDS_PER_HOUR
	if minutes >= NIGHT_MINUTES:
		night_ended.emit(night)
		night += 1
		minutes = fmod(minutes - NIGHT_MINUTES, NIGHT_MINUTES)
		_last_save = minutes
		if fixed_minutes < 0.0:
			save_clock()
	var h := hour24(minutes)
	if h != _last_hour:
		_last_hour = h
		hour_changed.emit(h)
	if fixed_minutes < 0.0 and absf(minutes - _last_save) >= SAVE_EVERY_MINUTES:
		_last_save = minutes
		save_clock()
	WindowLights.set_minutes(minutes)

func _exit_tree() -> void:
	if fixed_minutes < 0.0:
		save_clock()

## A resumed run's time (save system). Bad values keep the current ones.
func set_time(m: Variant, n: Variant) -> void:
	if fixed_minutes >= 0.0:
		return
	if (m is float or m is int) and is_finite(float(m)):
		minutes = clampf(float(m), 0.0, NIGHT_MINUTES - 0.001)
	if n is int or n is float:
		night = maxi(int(n), 1)
	_last_hour = hour24(minutes)
	_last_save = minutes
	WindowLights.set_minutes(minutes)

## Missing or damaged file: a fresh night 1 at 8 p.m.
func load_clock() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	var m = cfg.get_value("clock", "minutes", 0.0)
	var n = cfg.get_value("clock", "night", 1)
	if (m is float or m is int) and is_finite(float(m)):
		minutes = clampf(float(m), 0.0, NIGHT_MINUTES - 0.001)
	if n is int or n is float:
		night = maxi(int(n), 1)

func save_clock() -> bool:
	if SaveStore.chase_active:
		return false  # never save during a chase (run structure, 2026-10-09)
	var cfg := ConfigFile.new()
	cfg.set_value("clock", "minutes", minutes)
	cfg.set_value("clock", "night", night)
	return cfg.save(path) == OK

func text() -> String:
	return clock_text(minutes)

# ---------- pure helpers (tests use these) ----------

## 0..23 for game minutes since 8 p.m.
static func hour24(m: float) -> int:
	return (START_HOUR + int(floor(m / 60.0))) % 24

## "11:42 PM" style, as a car clock shows it.
static func clock_text(m: float) -> String:
	var total := int(floor(m)) + START_HOUR * 60
	var h := (total / 60) % 24
	var mm := total % 60
	var h12 := h % 12
	if h12 == 0:
		h12 = 12
	return "%d:%02d %s" % [h12, mm, "AM" if h < 12 else "PM"]

## "HH:MM" (24 h) to game minutes since 8 p.m.; -1 when it is not night time.
static func parse_time(s: String) -> float:
	var parts := s.split(":")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return -1.0
	var h := int(parts[0])
	var mm := int(parts[1])
	if h < 0 or h > 23 or mm < 0 or mm > 59:
		return -1.0
	var since := (h - START_HOUR + 24) % 24 * 60 + mm
	if since >= int(NIGHT_MINUTES):
		return -1.0
	return float(since)
