class_name WorldLook
extends WorldEnvironment

# The game's WorldEnvironment plus the switchable parts of the look
# (polish pass, 2026-10-08). game.gd builds the Environment as before; this
# node only adds what GraphicsSettings switches, in apply_graphics().
#
# Film look (GraphicsSettings flag "film_look"): a film-style tone curve and a
# colour grade.
# - Tone curve: AgX instead of the linear clip. Bright things (lamp heads,
#   windows, tail lamps, headlights) roll off softly toward white instead of
#   clipping flat, and the glow round them reads as light rather than paint.
#   AgX darkens the mids, so the exposure is raised to keep the scene about as
#   bright as before (mean screen brightness measured 18 -> 19 at 1280x720).
# - Grade: a 3D colour lookup table built here at startup (no asset): shadows
#   lean navy, highlights lean amber, a gentle S-curve on contrast. Amber vs.
#   Dusk, pushed by the camera instead of by every material.
# Off gives back the stage A linear look exactly.
#
# Reflections (flag "reflections"): fake city reflections, nothing re-rendered.
# The player's paint traces its reflection to the lamp-head and building-front
# planes in its shader (P1CoupeBuilder BODY_SHADER, the city_reflections
# global), and the sky draws lit windows and lamp-row glow into its radiance
# map only (NightSky city), which traffic paint and glass mirror.

const AGX_EXPOSURE := 2.0
const AGX_WHITE := 6.0
const LUT_SIZE := 17

## Grade strengths (display space, 0..1 values).
const CONTRAST := 0.22          # share of the S-curve mixed in
const SHADOW_TINT := Vector3(0.86, 0.94, 1.18)   # multiplier at black, navy
const SHADOW_LIFT := Vector3(0.006, 0.010, 0.022) # tiny navy floor so black is not dead grey
const HIGHLIGHT_TINT := Vector3(1.05, 1.0, 0.88) # multiplier at white, amber
const SATURATION := 1.06

static var _lut: ImageTexture3D

func _ready() -> void:
	add_to_group(GraphicsSettings.GROUP)
	apply_graphics()

func apply_graphics() -> void:
	if environment == null:
		return
	var on := GraphicsSettings.is_on("film_look")
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX if on else Environment.TONE_MAPPER_LINEAR
	environment.tonemap_exposure = AGX_EXPOSURE if on else 1.0
	environment.tonemap_white = AGX_WHITE if on else 1.0
	environment.adjustment_enabled = on
	environment.adjustment_color_correction = get_lut() if on else null
	var refl := 1.0 if GraphicsSettings.is_on("reflections") else 0.0
	RenderingServer.global_shader_parameter_set("city_reflections", refl)
	if environment.sky != null and environment.sky.sky_material is ShaderMaterial:
		NightSky.set_city(environment.sky, refl)

## The grade as a 3D lookup texture, built once.
static func get_lut() -> ImageTexture3D:
	if _lut == null:
		var images: Array[Image] = []
		var n := LUT_SIZE
		for b in n:
			var img := Image.create_empty(n, n, false, Image.FORMAT_RGB8)
			for g in n:
				for r in n:
					var c := grade(Vector3(r, g, b) / float(n - 1))
					img.set_pixel(r, g, Color(c.x, c.y, c.z))
			images.append(img)
		_lut = ImageTexture3D.new()
		_lut.create(Image.FORMAT_RGB8, n, n, n, false, images)
	return _lut

## One colour through the grade (display space in and out).
static func grade(c: Vector3) -> Vector3:
	# S-curve per channel.
	var s := Vector3(_smooth(c.x), _smooth(c.y), _smooth(c.z))
	c = c.lerp(s, CONTRAST)
	var l := c.dot(Vector3(0.2126, 0.7152, 0.0722))
	# Saturation round the luma.
	c = Vector3(l, l, l).lerp(c, SATURATION)
	# Split tone: navy into the shadows, amber into the highlights.
	var sh := pow(1.0 - clampf(l, 0.0, 1.0), 3.0)
	var hi := smoothstep(0.45, 1.0, l)
	c *= Vector3.ONE.lerp(SHADOW_TINT, sh * 0.6)
	c *= Vector3.ONE.lerp(HIGHLIGHT_TINT, hi * 0.7)
	c += SHADOW_LIFT * sh
	return c.clamp(Vector3.ZERO, Vector3.ONE)

static func _smooth(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)
