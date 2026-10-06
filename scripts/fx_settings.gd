class_name FxSettings
extends RefCounted

# Effects pack v1 (2026-10-06): one on/off flag per cheap effect, so a pause-menu
# toggle can be wired to each later. Saved under [fx] in the same
# user://settings.cfg the audio and traffic sliders use. NEON_FX=0 turns the
# whole pack off for one run (frame-cost A/B, tests); it does not touch the file.

const EFFECTS := ["vignette", "speed_lines", "skid_marks", "exhaust_flames"]

static var enabled := {"vignette": true, "speed_lines": true, "skid_marks": true, "exhaust_flames": true}

static func is_on(effect: String) -> bool:
	return bool(enabled.get(effect, false))

static func set_on(effect: String, on: bool) -> void:
	if enabled.has(effect):
		enabled[effect] = on

## Reads the file (missing or damaged means all on) and applies NEON_FX=0.
static func load_settings() -> void:
	var cfg := ConfigFile.new()
	var ok := cfg.load(AudioSettings.path) == OK
	for e in EFFECTS:
		enabled[e] = bool(cfg.get_value("fx", e, true)) if ok else true
	if OS.get_environment("NEON_FX") == "0":
		for e in EFFECTS:
			enabled[e] = false

static func save_settings() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)  # keep the other sections; a missing file is fine
	for e in EFFECTS:
		cfg.set_value("fx", e, enabled[e])
	return cfg.save(AudioSettings.path) == OK
