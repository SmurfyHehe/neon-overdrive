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
#
# Tiers (2026-10-09, car look doc section 13, Roy 123): a preset is also a CPU
# budget, not only a GPU one. The stress test (docs/research/stress-test.md)
# found traffic is most of the frame on the i5-1235U (a full-sim car ~0.4 ms
# per 120 Hz tick), so each preset also sets the traffic car count, the
# traffic sim/draw distance (cars beyond it run the cheap frozen cruise) and
# the cockpit mirror render size. Those values live in TrafficSettings and
# FxSettings (their own sliders); a preset writes them, and moving one of
# those sliders by hand shows "Custom" here too.
#
# Not in any preset: dynamic resolution (DynamicResolution, on by default,
# lowers the render scale while the GPU is over budget), the frame cap (V-sync
# or 30 fps) and whether the preset was the first-launch automatic pick
# (GraphicsAutoPick).

const PRESETS := ["low", "medium", "high"]
const PRESET_DEFAULT := "medium"

## Edge smoothing modes, in menu order.
const AA_MODES := ["off", "fxaa", "msaa2", "msaa2_fxaa", "msaa4"]
const AA_NAMES := ["Off", "FXAA", "MSAA 2x", "MSAA 2x + FXAA", "MSAA 4x"]

const SCALE_MIN := 0.5
const SCALE_MAX := 1.0

## Frame cap: 0 = V-sync only (the display's rate), 30 = 30 fps.
const FPS_CAPS := [0, 30]

## Every value per preset. Measured on the i5-1235U (Iris Xe, 1920x1080,
## tests/core/graphics_perf.gd, GPU median vs no smoothing): MSAA 2x ~0 ms, FXAA
## +1.3 ms, MSAA 4x +1.9 ms, MSAA 2x + FXAA +2.3 ms, 75% scale -1.7 ms. So
## MSAA 2x is the free default and FXAA is not in any preset.
## CPU side: traffic = car count, detail = traffic sim/draw distance (m),
## mirror_q = FxSettings mirror quality (0 low, 1 medium, 2 high). Medium is
## today's defaults, so Roy's laptop plays exactly as before at Medium.
const PRESET_VALUES := {
	"low": {"aa": "msaa2", "render_scale": 0.75, "traffic": 10, "detail": 100.0, "mirror_q": 0},
	"medium": {"aa": "msaa2", "render_scale": 1.0, "traffic": 16, "detail": 150.0, "mirror_q": 1},
	"high": {"aa": "msaa4", "render_scale": 1.0, "traffic": 25, "detail": 200.0, "mirror_q": 2},
}

## Nodes that switch with these settings join this group and implement
## apply_graphics().
const GROUP := "graphics_settings"

static var preset := PRESET_DEFAULT  # one of PRESETS, or "custom"
static var aa := "msaa2"
static var render_scale := 1.0
static var dynamic_res := true
static var fps_cap := 0
## True when the preset came from the first-launch benchmark, not the menu.
static var auto_picked := false
## False until the file has a [graphics] preset: GraphicsAutoPick runs then.
static var has_saved_preset := false

static func set_preset(p: String) -> void:
	if not PRESET_VALUES.has(p):
		return
	preset = p
	var v: Dictionary = PRESET_VALUES[p]
	aa = v.aa
	render_scale = v.render_scale
	TrafficSettings.set_car_count(v.traffic)
	TrafficSettings.set_detail_distance(v.detail)
	FxSettings.set_mirror_quality(v.mirror_q)

static func set_aa(mode: String) -> void:
	if mode in AA_MODES:
		aa = mode
		refresh_preset()

static func set_render_scale(s: float) -> void:
	render_scale = clampf(s, SCALE_MIN, SCALE_MAX) if is_finite(s) else 1.0  # clampf passes NaN through
	refresh_preset()

static func set_dynamic_res(on: bool) -> void:
	dynamic_res = on

static func set_fps_cap(cap: int) -> void:
	fps_cap = cap if cap in FPS_CAPS else 0

## After a hand change (here, or a traffic or mirror slider): still the named
## preset if every value matches it, else "custom".
static func refresh_preset() -> void:
	preset = matching_preset()

static func matching_preset() -> String:
	for p in PRESETS:
		var v: Dictionary = PRESET_VALUES[p]
		if v.aa == aa and is_equal_approx(v.render_scale, render_scale) 				and TrafficSettings.car_count == v.traffic 				and is_equal_approx(TrafficSettings.detail_distance, v.detail) 				and FxSettings.mirror_quality == v.mirror_q:
			return p
	return "custom"

## Pushes the values to the viewport, the frame cap and every GROUP node
## (the traffic manager, the mirrors, dynamic resolution).
static func apply(tree: SceneTree) -> void:
	apply_viewport(tree.root)
	Engine.max_fps = fps_cap
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

## Reads the file (missing or damaged values keep the defaults), then NEON_GFX.
## Call after TrafficSettings and FxSettings have loaded: the preset name is
## worked out from their values too, so a traffic slider moved since the last
## save shows as "Custom" instead of being reset to the preset.
static func load_settings() -> void:
	aa = PRESET_VALUES[PRESET_DEFAULT].aa
	render_scale = PRESET_VALUES[PRESET_DEFAULT].render_scale
	dynamic_res = true
	fps_cap = 0
	auto_picked = false
	has_saved_preset = false
	var cfg := ConfigFile.new()
	if cfg.load(AudioSettings.path) == OK:
		has_saved_preset = cfg.has_section_key("graphics", "preset")
		set_aa(str(cfg.get_value("graphics", "aa", aa)))
		var sc: Variant = cfg.get_value("graphics", "render_scale", render_scale)
		set_render_scale(float(sc) if (sc is float or sc is int) else 1.0)
		set_dynamic_res(FxSettings._to_bool(cfg.get_value("graphics", "dynamic_res", true)))
		var cap: Variant = cfg.get_value("graphics", "fps_cap", 0)
		set_fps_cap(int(cap) if (cap is float or cap is int) else 0)
		auto_picked = FxSettings._to_bool(cfg.get_value("graphics", "auto", false))
	refresh_preset()
	var forced := OS.get_environment("NEON_GFX")
	if PRESET_VALUES.has(forced):
		set_preset(forced)
		has_saved_preset = true  # a forced run never auto-picks

## True on a first launch: no preset in the file and none forced.
static func needs_auto_pick() -> bool:
	return not has_saved_preset

## Rewrites the [graphics] section, and the traffic and fx sections a preset
## writes to; the other sections stay.
static func save_settings() -> bool:
	TrafficSettings.save_settings()
	FxSettings.save_settings()
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)
	cfg.set_value("graphics", "preset", preset)
	cfg.set_value("graphics", "aa", aa)
	cfg.set_value("graphics", "render_scale", render_scale)
	cfg.set_value("graphics", "dynamic_res", dynamic_res)
	cfg.set_value("graphics", "fps_cap", fps_cap)
	cfg.set_value("graphics", "auto", auto_picked)
	has_saved_preset = true
	return cfg.save(AudioSettings.path) == OK
