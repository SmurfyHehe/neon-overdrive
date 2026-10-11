extends Node

# Discord Rich Presence (2026-10-10): "Playing <game>" on the player's Discord
# profile, with the night, the area, the car and the radio station. It talks to
# the Discord app already running on the PC (scripts/vendor/discord_rich_presence,
# MIT, pure GDScript, Windows named pipe). Nothing is sent anywhere else.
#
# Shown: night number, area, car name, radio station, time played (Discord
# counts it from `timestamps.start`). Never shown: cash, heat, rival names,
# story titles. The image is the logo only, no car picture.
#
# Cost: a 5 s timer builds one small Dictionary and compares it to the last
# one; Discord is only told when it changed. With Discord closed the vendored
# node tries again every 20 s and does nothing else. Off in tests, benchmarks
# and --headless, and while APP_ID is empty.
#
# No class_name on purpose: preload it, so no class cache refresh is needed.

const Rich := preload("res://scripts/vendor/discord_rich_presence/discord_rich_presence.gd")
const TestMode := preload("res://scripts/core/test_mode.gd")
const Districts := preload("res://scripts/world/districts.gd")

## The Discord developer application's id (Discord Developer Portal > the
## "Boost Simcade" app > General Information > Application ID). It is public,
## not a secret. Empty = the feature stays dormant. NEON_DISCORD_APP_ID
## overrides it for a quick local try.
const APP_ID := ""
## Key of the logo under Rich Presence > Art Assets in the Developer Portal.
const LOGO_KEY := "logo"
const UPDATE_EVERY := 5.0

## What the area line says for each Districts kind. Unknown kinds (new ones
## land with the district work) fall back to a capitalised id.
const AREA_NAMES := {
	"downtown": "Downtown",
	"residential": "Residential",
	"strip": "The Strip",
	"industrial": "Industrial",
	"old_town": "Old Town",
	"lofts": "The Lofts",
	"hillside": "Hillside",
	"airport": "Airport",
	"docks": "The Docks",
	"freeway": "Route 9",
	"canyon": "Canyon",
}

## On by default, saved in [discord] of the shared settings file.
static var enabled := true

static func set_enabled(on: bool) -> void:
	enabled = on

static func load_settings() -> void:
	var cfg := ConfigFile.new()
	var ok := cfg.load(AudioSettings.path) == OK
	enabled = bool(cfg.get_value("discord", "enabled", true)) if ok else true

## Rewrites only the [discord] section; the other sections stay.
static func save_settings() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)
	cfg.set_value("discord", "enabled", enabled)
	return cfg.save(AudioSettings.path) == OK

static func area_name(kind: String) -> String:
	return String(AREA_NAMES.get(kind, kind.capitalize()))

## The activity Discord shows. Pure, so a test can check exactly what leaves
## the game. station < 0 means the radio is off.
static func build_activity(night: int, area: String, car: String, station_name: String, started_unix: int) -> Dictionary:
	var state := car if station_name.is_empty() else "%s · %s" % [car, station_name]
	return {
		"details": "Night %d" % maxi(night, 1) if area.is_empty() else "Night %d · %s" % [maxi(night, 1), area],
		"state": state,
		"timestamps": {"start": started_unix},
		"assets": {"large_image": LOGO_KEY},
	}

var _game: Node
var _rich: Node
var _timer: Timer
var _started := 0
var _last := {}

static func app_id() -> String:
	var env := OS.get_environment("NEON_DISCORD_APP_ID").strip_edges()
	return env if env.is_valid_int() else APP_ID

## True when this run should talk to Discord at all.
static func wanted() -> bool:
	if app_id().is_empty() or TestMode.active() or Benchmark.requested():
		return false
	return DisplayServer.get_name() != "headless" and OS.get_name() == "Windows"

func _init(game: Node = null) -> void:
	_game = game

func _ready() -> void:
	if not wanted() or _game == null:
		return
	_started = int(Time.get_unix_time_from_system())
	_rich = Rich.new()
	_rich.app_id = app_id()
	add_child(_rich)
	_timer = Timer.new()
	_timer.wait_time = UPDATE_EVERY
	_timer.timeout.connect(_update)
	add_child(_timer)
	_timer.start()
	_update()

func _update() -> void:
	if _rich == null:
		return
	if not enabled:
		if not _last.is_empty():
			_last = {}
			_rich.clear_activity()
		return
	var a := build_activity(_night(), _area(), _car(), _station(), _started)
	if a != _last:
		_last = a
		_rich.set_activity(a)

func _night() -> int:
	var c = _game.get("night_clock")
	return int(c.night) if c != null else 1

func _area() -> String:
	var p = _game.get("player")
	if p == null:
		return ""
	var idx := int(floor(-RoadFrame.unroll(p.global_position).z / RoadChunkBuilder.CHUNK_LEN)) + int(_game.get("origin_index"))
	return area_name(Districts.name_at(idx))

func _car() -> String:
	return String(PlayerCars.info(PlayerCar.chassis_kind()).name)

func _station() -> String:
	var r = _game.get("radio")
	if r == null or int(r.station) < 0:
		return ""
	return String(RadioStations.STATIONS[int(r.station)].name)
