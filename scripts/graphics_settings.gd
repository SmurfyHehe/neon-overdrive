class_name GraphicsSettings
extends RefCounted

# Graphics settings (polish pass, 2026-10-08): a Low / Medium / High preset
# plus each setting on its own, saved under [graphics] in the same
# user://settings.cfg the other settings use. Picking a preset sets every
# value; changing one value by hand makes the preset "custom".
#
# apply(tree) pushes the values to the running game: the root viewport (edge
# smoothing, render scale) and every node in GROUP, which gets
# apply_graphics() called on it, so each effect owns how it switches.
#
# Edge smoothing on the Mobile renderer: MSAA (smooths geometry edges, the
# road lines and car silhouettes) and FXAA (a cheap screen blur on edges, also
# catches thin emissive lines MSAA misses). TAA and SMAA are Forward+ only.
# Render scale below 1 draws the 3D view at fewer pixels and stretches it back
# up (bilinear: FSR 1 is Forward+ only, Godot warns and ignores it on Mobile);
# the HUD is drawn after, so it stays sharp.
#
# NEON_GFX=<low|medium|high> forces a preset for one run (benchmarks, tests);
# it does not touch the file.

const PRESETS := ["low", "medium", "high"]
const PRESET_DEFAULT := "medium"

## Edge smoothing modes, in menu order.
const AA_MODES := ["off", "fxaa", "msaa2", "msaa2_fxaa", "msaa4"]
const AA_NAMES := ["Off", "FXAA", "MSAA 2x", "MSAA 2x + FXAA", "MSAA 4x"]

const SCALE_MIN := 0.5
const SCALE_MAX := 1.0

## Every value per preset. Measured on the i5-1235U (Iris Xe, 1920x1080,
## tests/graphics_perf.gd, GPU median vs no smoothing): MSAA 2x ~0 ms, FXAA
## +1.3 ms, MSAA 4x +1.9 ms, MSAA 2x + FXAA +2.3 ms, 75% scale -1.7 ms. So
## MSAA 2x is the free default and FXAA is not in any preset.
const PRESET_VALUES := {
	"low": {"aa": "msaa2", "render_scale": 0.75, "film_look": true},
	"medium": {"aa": "msaa2", "render_scale": 1.0, "film_look": true},
	"high": {"aa": "msaa4", "render_scale": 1.0, "film_look": true},
}

## On/off effects, in menu order, with their menu names. Each is read by the
## node that draws it (film_look: WorldLook).
const FLAGS := ["film_look"]
const FLAG_NAMES := {"film_look": "Film look"}

## Nodes that switch with these settings join this group and implement
## apply_graphics().
const GROUP := "graphics_settings"

static var preset := PRESET_DEFAULT  # one of PRESETS, or "custom"
static var aa := "msaa2"
static var render_scale := 1.0
static var flags := {"film_look": true}

static func is_on(flag: String) -> bool:
	return bool(flags.get(flag, false))

static func set_flag(flag: String, on: bool) -> void:
	if flag in FLAGS:
		flags[flag] = on
		_mark_custom()

static func set_preset(p: String) -> void:
	if not PRESET_VALUES.has(p):
		return
	preset = p
	var v: Dictionary = PRESET_VALUES[p]
	aa = v.aa
	render_scale = v.render_scale
	for f in FLAGS:
		flags[f] = bool(v[f])

static func set_aa(mode: String) -> void:
	if mode in AA_MODES:
		aa = mode
		_mark_custom()

static func set_render_scale(s: float) -> void:
	render_scale = clampf(s, SCALE_MIN, SCALE_MAX) if is_finite(s) else 1.0  # clampf passes NaN through
	_mark_custom()

## After a hand change: still the named preset if every value matches it.
static func _mark_custom() -> void:
	for p in PRESETS:
		var v: Dictionary = PRESET_VALUES[p]
		if v.aa == aa and is_equal_approx(v.render_scale, render_scale) and FLAGS.all(func(f: String) -> bool: return bool(v[f]) == is_on(f)):
			preset = p
			return
	preset = "custom"

## Pushes the values to the viewport and every GROUP node.
static func apply(tree: SceneTree) -> void:
	apply_viewport(tree.root)
	tree.call_group(GROUP, "apply_graphics")

static func apply_viewport(vp: Viewport) -> void:
	match aa:
		"off":
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		"fxaa":
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		"msaa2":
			vp.msaa_3d = Viewport.MSAA_2X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		"msaa2_fxaa":
			vp.msaa_3d = Viewport.MSAA_2X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		"msaa4":
			vp.msaa_3d = Viewport.MSAA_4X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = render_scale

## Reads the file (missing or damaged means the default preset), then NEON_GFX.
static func load_settings() -> void:
	set_preset(PRESET_DEFAULT)
	var cfg := ConfigFile.new()
	if cfg.load(AudioSettings.path) == OK:
		var p := str(cfg.get_value("graphics", "preset", PRESET_DEFAULT))
		if PRESET_VALUES.has(p):
			set_preset(p)
		else:
			# "custom" (or damaged): read each value, keep the default for a bad one.
			set_aa(str(cfg.get_value("graphics", "aa", aa)))
			set_render_scale(float(cfg.get_value("graphics", "render_scale", render_scale)))
			for f in FLAGS:
				set_flag(f, FxSettings._to_bool(cfg.get_value("graphics", f, is_on(f))))
	var forced := OS.get_environment("NEON_GFX")
	if PRESET_VALUES.has(forced):
		set_preset(forced)

## Rewrites only the [graphics] section; the other sections stay.
static func save_settings() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)
	cfg.set_value("graphics", "preset", preset)
	cfg.set_value("graphics", "aa", aa)
	cfg.set_value("graphics", "render_scale", render_scale)
	for f in FLAGS:
		cfg.set_value("graphics", f, is_on(f))
	return cfg.save(AudioSettings.path) == OK
