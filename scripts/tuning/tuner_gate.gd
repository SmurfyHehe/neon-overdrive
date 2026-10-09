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
