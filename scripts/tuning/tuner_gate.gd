class_name TunerGate
extends RefCounted

# The Advanced page's one-time confirm (settings safety part 4, 2026-10-07).
# Advanced goes out to the hard limits, where the car can spin or crawl, so the
# first visit asks once; after that it opens straight away. Stored in the same
# user://settings.cfg as the other settings (its own [tuner] section), so tests
# that redirect AudioSettings.path redirect this too.

static func advanced_ok() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(AudioSettings.path) != OK:
		return false
	return cfg.get_value("tuner", "advanced_ok", false) == true

## Rewrites only the [tuner] section; the other sections stay.
static func set_advanced_ok(ok: bool) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)
	cfg.set_value("tuner", "advanced_ok", ok)
	return cfg.save(AudioSettings.path) == OK

## The Quick page's Detailed switch (tuner overhaul, 2026-10-10): whether the
## full pages show next to Quick. Off until the player turns it on.
static func detailed() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(AudioSettings.path) != OK:
		return false
	return cfg.get_value("tuner", "detailed", false) == true

static func set_detailed(on: bool) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)
	cfg.set_value("tuner", "detailed", on)
	return cfg.save(AudioSettings.path) == OK
