class_name FxSettings
extends RefCounted

# Effects pack v1 (2026-10-06): one on/off flag per cheap effect, so a pause-menu
# toggle can be wired to each later. Saved under [fx] in the same
# user://settings.cfg the audio and traffic sliders use. NEON_FX=0 turns the
# whole pack off for one run (frame-cost A/B, tests); it does not touch the file.
# The cockpit milestone adds the mirrors flag and their render quality,
# head_motion (the cockpit eye swaying with the car's forces, ChaseCamera)
# and rear_strip (the HUD's rear-view strip in the chase view, fed by the same
# rearview mirror render).
# Tyre smoke (2026-10-07) adds the tyre_smoke flag and two amounts, burnout
# and drift (0..2, 1 = TyreSmoke's default rates), pause-menu sliders.
# Dirt (2026-10-09) adds the dirt flag: road grime on the player car over a
# night (car_dirt.gd), washed off in the garage wash (wash_screen.gd).

# Heat shimmer (2026-10-10, HeatShimmer): its own switch, "heat_shimmer".
const EFFECTS := ["vignette", "speed_lines", "skid_marks", "exhaust_flames", "mirrors", "head_motion", "rear_strip", "tyre_smoke", "heat_shimmer", "dirt"]
## Mirror render size as a share of CockpitMirrors' base sizes: 0 = low (half),
## 1 = medium (base), 2 = high (double). Default medium.
const MIRROR_QUALITIES := ["low", "medium", "high"]
const MIRROR_QUALITY_DEFAULT := 1
const SMOKE_MAX := 2.0

static var enabled := {"vignette": true, "speed_lines": true, "skid_marks": true, "exhaust_flames": true, "mirrors": true, "head_motion": true, "rear_strip": true, "tyre_smoke": true, "heat_shimmer": true, "dirt": true}
static var mirror_quality := MIRROR_QUALITY_DEFAULT
## Tyre smoke amounts, 0 (none) .. SMOKE_MAX; 1 is the default.
static var smoke_burnout := 1.0
static var smoke_drift := 1.0

static func is_on(effect: String) -> bool:
	return bool(enabled.get(effect, false))

static func set_on(effect: String, on: bool) -> void:
	if enabled.has(effect):
		enabled[effect] = on

## A file value as a switch. bool("false") is true (any non-empty string), so a
## hand-edited quoted "false" would leave the effect on.
static func _to_bool(x: Variant) -> bool:
	if x is String:
		return x.strip_edges().to_lower() in ["true", "1", "yes", "on"]
	return bool(x)

static func set_mirror_quality(q: int) -> void:
	mirror_quality = clampi(q, 0, MIRROR_QUALITIES.size() - 1)

static func set_smoke(burnout: float, drift: float) -> void:
	smoke_burnout = clampf(burnout, 0.0, SMOKE_MAX)
	smoke_drift = clampf(drift, 0.0, SMOKE_MAX)

## Render-size multiplier for the mirrors at the current quality.
static func mirror_scale() -> float:
	return [0.5, 1.0, 2.0][mirror_quality]

## Reads the file (missing or damaged means all on) and applies NEON_FX=0.
static func load_settings() -> void:
	var cfg := ConfigFile.new()
	var ok := cfg.load(AudioSettings.path) == OK
	for e in EFFECTS:
		enabled[e] = _to_bool(cfg.get_value("fx", e, true)) if ok else true
	set_mirror_quality(int(cfg.get_value("fx", "mirror_quality", MIRROR_QUALITY_DEFAULT)) if ok else MIRROR_QUALITY_DEFAULT)
	set_smoke(float(cfg.get_value("fx", "smoke_burnout", 1.0)) if ok else 1.0,
		float(cfg.get_value("fx", "smoke_drift", 1.0)) if ok else 1.0)
	if OS.get_environment("NEON_FX") == "0":
		for e in EFFECTS:
			enabled[e] = false

static func save_settings() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)  # keep the other sections; a missing file is fine
	for e in EFFECTS:
		cfg.set_value("fx", e, enabled[e])
	cfg.set_value("fx", "mirror_quality", mirror_quality)
	cfg.set_value("fx", "smoke_burnout", smoke_burnout)
	cfg.set_value("fx", "smoke_drift", smoke_drift)
	return cfg.save(AudioSettings.path) == OK
