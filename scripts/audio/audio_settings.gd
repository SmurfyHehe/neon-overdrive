class_name AudioSettings
extends RefCounted

# Volume settings (Phase B, 2026-10-05; stage B step 4's "Settings tab" starts
# here): one slider each for Master, Engine, Effects (tyres, wind, UI, traffic,
# sirens) and Music (the radio and the scanner),
# applied to the audio buses and saved in user://settings.cfg. The pause menu
# shows the sliders; Game applies the saved values at start. 1.0 is the buses'
# own level, so the defaults change nothing.

const DEFAULT_PATH := "user://settings.cfg"
const TestMode := preload("res://scripts/core/test_mode.gd")

## DEFAULT_PATH, or its test_ twin when a test is running (scripts/core/test_mode.gd).
static func default_path() -> String:
	return TestMode.path(DEFAULT_PATH)
const CHANNELS := {
	"Master": [&"Master"],
	"Engine": [&"Engine"],
	"Effects": [&"Tires", &"World", &"UI", &"Traffic", &"Sirens"],
	"Music": [&"Music", &"Scanner"],
}

## Tests point this at a scratch file.
static var path := default_path()
static var volumes := {"Master": 1.0, "Engine": 1.0, "Effects": 1.0, "Music": 1.0}
## Turbo sounds (spool, whistle, blow-off) on top of the Engine channel: 0..1,
## saved as [audio] turbo. The Settings Sound page has the slider; the turbo
## voice reads turbo_gain() when it lands (turbo sounds plan, section 13).
static var turbo_volume := 1.0

static func set_turbo_volume(value: float) -> void:
	turbo_volume = clampf(value, 0.0, 1.0) if is_finite(value) else 1.0

## Linear gain for the turbo voice: the Engine slider times the Turbo slider.
static func turbo_gain() -> float:
	return float(volumes["Engine"]) * turbo_volume

static func set_volume(channel: String, value: float) -> void:
	if not CHANNELS.has(channel):
		return
	volumes[channel] = clampf(value, 0.0, 1.0) if is_finite(value) else 1.0  # clampf passes NaN through
	_apply(channel)

static func apply_all() -> void:
	for channel in CHANNELS:
		_apply(channel)

## The dB a channel's slider asks for (-80 for silence), for code that adds an
## offset on top (PerspectiveAudio on the Music bus).
static func volume_db_for(channel: String) -> float:
	if not volumes.has(channel):
		return 0.0
	return linear_to_db(volumes[channel]) if volumes[channel] > 0.0001 else -80.0

## The slider that sets a bus ("Master" for a bus no slider owns).
static func channel_of(bus_name: StringName) -> String:
	for channel in CHANNELS:
		if bus_name in CHANNELS[channel]:
			return channel
	return "Master" if bus_name == &"Master" else ""

static func _apply(channel: String) -> void:
	var db := volume_db_for(channel)
	for bus_name in CHANNELS[channel]:
		var i := AudioServer.get_bus_index(bus_name)
		if i >= 0:
			AudioServer.set_bus_volume_db(i, db)

## Reads the file (missing or damaged means defaults) and applies it.
static func load_settings() -> void:
	var cfg := ConfigFile.new()
	var ok := cfg.load(path) == OK
	for channel in CHANNELS:
		var v := float(cfg.get_value("audio", channel.to_lower(), 1.0)) if ok else 1.0
		volumes[channel] = clampf(v, 0.0, 1.0) if is_finite(v) else 1.0  # a hand-edited "nan" loads as NaN
	var t := float(cfg.get_value("audio", "turbo", 1.0)) if ok else 1.0
	set_turbo_volume(t)
	apply_all()

static func save_settings() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(path)  # keep the other sections (TrafficSettings); a missing file is fine
	for channel in CHANNELS:
		cfg.set_value("audio", channel.to_lower(), volumes[channel])
	cfg.set_value("audio", "turbo", turbo_volume)
	return cfg.save(path) == OK
