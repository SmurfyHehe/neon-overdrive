extends RefCounted

# Tone mapping and colour grade (graphics setup, 2026-10-10).
#
# Before this the Environment had no tone mapper (Godot's default, Linear):
# anything brighter than 1.0 was simply cut off per channel, so a sodium lamp
# head or a headlight clipped to one flat orange patch with no hot core, and
# the glow around it had the same flat colour.
#
# Now: a tone mapper (AgX) rolls the bright end off, so a lamp goes from
# orange at its edge to a pale amber core, and a small grade pushes the picture
# toward the "Amber vs. Dusk" palette: shadows lean a little to navy,
# highlights a little to amber. No magenta, no cyan: the ramp only ever trades
# red against blue, and green sits between them.
#
# Both run inside the post pass the Mobile renderer already does for glow, so
# they add no draw calls and no CPU work. Graphics-chip cost on the i5-1235U:
# inside run-to-run noise (two pairs of 20 s benchmarks, 2026-10-10: old look
# 6.95 and 6.16 ms, graded 6.42 and 6.42 ms, with other work on the laptop).
# Before and after: docs/design/graphics-setup-2026-10-10/.
#
# NEON_GRADE picks a look for one run, for before/after shots and benchmarks:
#   off     the old picture (Linear, no grade)
#   agx     the default
#   filmic  Godot's Filmic curve with the same grade
#   aces    ACES with the same grade
# NEON_GRADE_RAMP=0 keeps the tone mapper and drops the colour ramp.

const DEFAULT_LOOK := "agx"

## Per look: tone mapper, exposure, white point, then the adjustment trio.
## AgX darkens the middle of the range, so its exposure (1.6) gives it back:
## the asphalt in front of the car keeps its old brightness (road patches in
## tests/world/sky_shots.gd: RGB 7,7,18 before, 5,6,18 after). Filmic and ACES
## are there to compare with and are not matched as closely.
const LOOKS := {
	"agx": {"mode": Environment.TONE_MAPPER_AGX, "exposure": 1.6, "white": 6.0, "agx_contrast": 1.25,
		"brightness": 1.0, "contrast": 1.0, "saturation": 1.0},
	"filmic": {"mode": Environment.TONE_MAPPER_FILMIC, "exposure": 1.0, "white": 4.0,
		"brightness": 1.0, "contrast": 1.0, "saturation": 1.0},
	"aces": {"mode": Environment.TONE_MAPPER_ACES, "exposure": 1.0, "white": 4.0,
		"brightness": 1.0, "contrast": 1.0, "saturation": 1.0},
}

## The colour ramp: output colour per input level, each channel read on its
## own (Godot looks red up in the ramp's red, green in green, blue in blue).
## Black stays black, so the night does not go grey.
const RAMP := [
	[0.0, Color(0.0, 0.0, 0.0)],
	[0.12, Color(0.112, 0.12, 0.134)],   # shadows: a touch of navy
	[0.5, Color(0.512, 0.5, 0.47)],      # mids: warm
	[1.0, Color(1.0, 0.975, 0.9)],       # highlights: amber, never pure white
]

static var _ramp: GradientTexture1D

static func look() -> String:
	var forced := OS.get_environment("NEON_GRADE")
	if forced == "off" or LOOKS.has(forced):
		return forced
	return DEFAULT_LOOK

## Sets the tone mapper and grade on the game's Environment.
static func apply(env: Environment) -> void:
	var name := look()
	if name == "off":
		clear(env)
		return
	var v: Dictionary = LOOKS[name]
	env.tonemap_mode = v.mode
	env.tonemap_exposure = v.exposure
	env.tonemap_white = v.white
	if v.has("agx_contrast"):
		env.tonemap_agx_white = v.white
		env.tonemap_agx_contrast = v.agx_contrast
	env.adjustment_enabled = true
	env.adjustment_brightness = v.brightness
	env.adjustment_contrast = v.contrast
	env.adjustment_saturation = v.saturation
	env.adjustment_color_correction = null if OS.get_environment("NEON_GRADE_RAMP") == "0" else ramp()

## Back to the plain picture. Also for a view whose image is shown inside the
## graded view (the cockpit mirrors): grading it there too would do it twice.
static func clear(env: Environment) -> void:
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.tonemap_white = 1.0
	env.adjustment_enabled = false
	env.adjustment_color_correction = null

static func ramp() -> GradientTexture1D:
	if _ramp == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array(RAMP.map(func(p: Array) -> float: return p[0]))
		g.colors = PackedColorArray(RAMP.map(func(p: Array) -> Color: return p[1]))
		_ramp = GradientTexture1D.new()
		_ramp.gradient = g
		_ramp.width = 256
	return _ramp
