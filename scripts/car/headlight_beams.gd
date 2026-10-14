class_name HeadlightBeams
extends RefCounted

# Low beam, high beam and flash for the player's one headlight spot (lights
# decision list, speed-feel calibration note 2026-10-10, section 10). One key
# does all of it, H (key map K1):
#
#   tap H      lights off: low beam on. Lights on: switch low <-> high.
#              The tap resolves when the key comes up inside HOLD_SECONDS.
#   hold H     longer than HOLD_SECONDS: the high beam is lit while the key is
#              down and goes back to what it was on release. The moment the
#              hold starts counts as ONE flash (`flashes` += 1).
#   H H        double tap: two presses inside DOUBLE_WINDOW switch the lights
#              off and undo what the first tap switched.
#   auto-dip   on by default: a car in the beam's way drops high to low
#
# Low beam: 100 m, aimed 1 degree down, with a cut-off projector (dark above
# the horizon, so an oncoming windscreen and the buildings' upper floors are
# not lit). High beam: 150 m, level, narrower. Cops read the same state:
# PoliceHeat.see_reach_for(mode).
#
# CPU: still the one SpotLight3D with no shadow. A beam change rewrites the
# spot's six properties once, on the frame it changes; a driving frame does a
# few compares and, only while the high beam is on and auto-dip is armed, a
# scan of the traffic position list every DIP_EVERY seconds.

enum Mode { OFF, LOW, HIGH }

const LOW_RANGE := 100.0
const LOW_ANGLE := 32.0         # degrees, half-angle: wide and short
const LOW_ENERGY := 24.0
const LOW_DIP := 1.0            # degrees down from level
const HIGH_RANGE := 150.0
const HIGH_ANGLE := 20.0        # narrower: the same light thrown further
const HIGH_ENERGY := 34.0
const HIGH_DIP := 0.0

const DOUBLE_WINDOW := 0.30     # s between two H presses that make a double tap
const HOLD_SECONDS := 0.20      # a press held longer than this is a flash, not a tap
const DIP_EVERY := 0.1          # s between traffic scans
const DIP_ONCOMING := 150.0     # m: a car coming at you inside the beam's reach
const DIP_AHEAD := 80.0         # m: a car you are following

## Cut-off projector: row CUTOFF_V of the cone image is the horizon. With the
## low beam aimed LOW_DIP down and half-angle LOW_ANGLE, the horizon sits
## tan(LOW_DIP)/tan(LOW_ANGLE) of the half-height above the axis.
## Render layer nothing is drawn on: the low beam's shadow pass (needed for
## its projector) has no casters.
const NO_CASTERS := 1 << 19
const CUTOFF_SIZE := 128
const CUTOFF_SOFT := 2.0        # rows of fade at the edge

var high_on := false            # the high beam is the selected one
var auto_dip := true            # default on (decision list)
var mode := Mode.OFF            # what the lamp is doing right now
var dipped := false             # high is selected but auto-dip holds it low
var flashes := 0                # holds started (one flash each); cops and traffic read it
## Returns true when a car is in the beam's way. Set by game.gd to the traffic
## manager's beam_blocked; unset (no traffic) = never dips.
var dip_probe := Callable()
## Broken head lamps take a share of the beam (CarDamage.headlight_share).
var damage_share := 1.0

var _spot: SpotLight3D
var _lights_on := true
var _down := false              # H is held
var _held := 0.0                # s the current press has been down
var _hold_active := false       # the press became a flash
var _consumed := false          # the press was a double tap: its release does nothing
var _since_press := 99.0        # s since the latest press
var _have_tap := false          # the last tap can still be undone by a double tap
var _tap_lights := false        # lights and beam before that tap
var _tap_high := false
var _dip_t := 0.0
var _applied := -1
var _applied_share := -1.0
var _applied_flash := false

static var _cutoff_tex: GradientTexture2D

func attach(spot: SpotLight3D) -> void:
	_spot = spot
	_applied = -1
	_refresh()

## H: the lights as a whole.
func set_lights(on: bool) -> void:
	_lights_on = on
	if not on:
		high_on = false
	_refresh()

## H went down.
func press_key() -> void:
	_down = true
	_held = 0.0
	_hold_active = false
	_consumed = false
	if _have_tap and _since_press <= DOUBLE_WINDOW:
		# Double tap: undo the first tap's switch and put the lights out.
		_lights_on = false
		high_on = false
		_have_tap = false
		_consumed = true
		_since_press = 99.0
		_refresh()
		return
	_since_press = 0.0

## H came up. A press that never became a hold is a tap.
func release_key() -> void:
	if not _down:
		return
	_down = false
	if _hold_active:
		_hold_active = false   # back to whatever it was
		_refresh()
		return
	if _consumed:
		return
	tap()

## One tap: lights off -> low beam on; lights on -> low <-> high.
func tap() -> void:
	_tap_lights = _lights_on
	_tap_high = high_on
	_have_tap = true
	if not _lights_on:
		_lights_on = true
		high_on = false
	else:
		high_on = not high_on
	_refresh()

func lights_on() -> bool:
	return _lights_on

## The beam as the world sees it: cops and the HUD read this.
func current() -> int:
	return mode

func set_damage_share(s: float) -> void:
	damage_share = s
	_refresh()

func step(delta: float) -> void:
	if _since_press < 90.0:
		_since_press += delta
	if _down and not _hold_active and not _consumed:
		_held += delta
		if _held > HOLD_SECONDS:
			_hold_active = true
			_have_tap = false
			flashes += 1
			_refresh()
	if high_on and _lights_on and auto_dip and dip_probe.is_valid():
		_dip_t -= delta
		if _dip_t <= 0.0:
			_dip_t = DIP_EVERY
			var blocked: bool = dip_probe.call()
			if blocked != dipped:
				dipped = blocked
				_refresh()
	elif dipped:
		dipped = false
		_refresh()

func _wanted() -> int:
	if _hold_active:
		return Mode.HIGH
	if not _lights_on:
		return Mode.OFF
	if high_on and not dipped:
		return Mode.HIGH
	return Mode.LOW

func _refresh() -> void:
	mode = _wanted()
	if _spot == null or not is_instance_valid(_spot):
		return
	if mode == _applied and damage_share == _applied_share and _hold_active == _applied_flash:
		return
	var rewrite := mode != _applied
	var car := _spot.get_parent()
	if rewrite or _hold_active != _applied_flash:
		_light_body(car)
	_applied = mode
	_applied_share = damage_share
	_applied_flash = _hold_active
	_spot.visible = mode != Mode.OFF and damage_share > 0.0
	# The painted beam on the road (CarFx "HeadlightBeam") goes with the lamp.
	var beam: Decal = car.get_node_or_null(^"HeadlightBeam") as Decal if car != null else null
	if beam != null:
		beam.visible = _spot.visible
		beam.emission_energy = CarFx.BEAM_ENERGY * damage_share
	if not rewrite:
		_spot.light_energy = _energy_for(mode) * damage_share
		return
	match mode:
		Mode.HIGH:
			_spot.spot_range = HIGH_RANGE
			_spot.spot_angle = HIGH_ANGLE
			_spot.rotation_degrees.x = -HIGH_DIP
			_spot.light_projector = null
			_spot.shadow_enabled = false
		_:
			_spot.spot_range = LOW_RANGE
			_spot.spot_angle = LOW_ANGLE
			_spot.rotation_degrees.x = -LOW_DIP
			_spot.light_projector = cutoff_texture()
			# The renderer only draws a projector on a light that has shadows
			# on (probe 2026-10-10: white texture, black result without).
			# Nothing is on the caster layer, so the shadow pass draws nothing.
			_spot.shadow_caster_mask = NO_CASTERS
			_spot.shadow_enabled = true
	_spot.light_energy = _energy_for(mode) * damage_share

## The lamps drawn on the body (NpcCarBuilder.GLOW_SHADER, Roy 1521): dark
## with the lights off, lit again while H is held for a flash. Two instance
## uniforms on the car's "Body", written only when the state changes.
func _light_body(car: Node) -> void:
	var vis: Variant = car.get("chassis_visual") if car != null else null
	if not (vis is Node3D):
		return
	var body := (vis as Node3D).get_node_or_null(^"Body") as MeshInstance3D
	if body == null:
		return
	body.set_instance_shader_parameter("lamps", 0.0 if mode == Mode.OFF else 1.0)
	body.set_instance_shader_parameter("flash", 1.0 if _hold_active else 0.0)

static func _energy_for(m: int) -> float:
	return HIGH_ENERGY if m == Mode.HIGH else LOW_ENERGY

## Black above the horizon row, white below it, with a CUTOFF_SOFT-row fade:
## a vertical gradient, built once and shared by every car.
static func cutoff_texture() -> GradientTexture2D:
	if _cutoff_tex == null:
		var half := CUTOFF_SIZE * 0.5
		var above := tan(deg_to_rad(LOW_DIP)) / tan(deg_to_rad(LOW_ANGLE)) * half
		var edge := (half - above) / CUTOFF_SIZE   # 0 = top of the cone image
		var soft := CUTOFF_SOFT / CUTOFF_SIZE
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, edge - soft, edge + soft, 1.0])
		grad.colors = PackedColorArray([Color.BLACK, Color.BLACK, Color.WHITE, Color.WHITE])
		_cutoff_tex = GradientTexture2D.new()
		_cutoff_tex.gradient = grad
		_cutoff_tex.fill = GradientTexture2D.FILL_LINEAR
		_cutoff_tex.fill_from = Vector2(0.5, 0.0)
		_cutoff_tex.fill_to = Vector2(0.5, 1.0)
		_cutoff_tex.width = 4
		_cutoff_tex.height = CUTOFF_SIZE
	return _cutoff_tex
