class_name SkyDirector
extends Node

# Drives the night sky from the game (night pass, 2026-10-10):
# - the moon crosses the sky as the clock runs (NightSky.moon_direction),
# - the glow dome follows the district the player is in, blending over a few
#   seconds when the road changes district,
# - a new night (6 a.m. rollover) re-seeds the stars, phase and moon path,
# - the air follows the district too (better world B8): fog density and
#   colour and the grade's saturation (NightSky.AIR) blend with the dome, and
#   the fog thickens into a ground mist before dawn (NightSky.mist_for_minutes,
#   stepped with the moon).
#
# The moon direction and the dome are global shader parameters (see
# night_sky.gd), so moving them costs nothing on the render side; they are
# still stepped (MOON_STEP_SECS, BLEND_STEP_SECS) rather than set every frame,
# and the district lookup runs DISTRICT_CHECK_SECS apart. No draw calls.

const Districts := preload("res://scripts/world/districts.gd")

const MOON_STEP_SECS := 5.0   # the moon turns 15 degrees an hour: 0.3 degrees a step (its disc is 2.5)
const BLEND_SECS := 4.0
const BLEND_STEP_SECS := 0.1
const DISTRICT_CHECK_SECS := 0.25
const BLINK_STEP_SECS := 0.2

var sky: Sky
var env: Environment  # the game's; null in tools: the air is left alone
var night_clock: NightClock
var game: Node  # Game: player, origin_index

var _district := NightSky.DEFAULT_DISTRICT
var _from_color: Color
var _from_height := 0.0
var _to_color: Color
var _to_height := 0.0
var _from_air: Dictionary
var _to_air: Dictionary
var _mist := 1.0
var _base_sat := 1.0
var _blend := 1.0
var _blend_acc := 0.0
var _moon_acc := 0.0
var _district_acc := 0.0
var _blink_acc := 0.0
var _blink_time := 0.0
var _night := 0

func _ready() -> void:
	name = "SkyDirector"
	_night = night_clock.night
	var g: Dictionary = NightSky.GLOW.get(_district, NightSky.GLOW["downtown"])
	_from_color = g.color
	_to_color = g.color
	_from_height = g.height_deg
	_to_height = g.height_deg
	_from_air = NightSky.air(_district)
	_to_air = _from_air
	if env != null:
		_base_sat = env.adjustment_saturation
	_mist = NightSky.mist_for_minutes(night_clock.minutes)
	_apply_air(1.0)
	night_clock.night_ended.connect(_on_night_ended)
	_apply_moon()
	NightSky.set_dawn(NightSky.dawn_for_minutes(night_clock.minutes))
	NightSky.set_cloud_offset(NightSky.cloud_offset_for_minutes(night_clock.minutes))

func _process(delta: float) -> void:
	_moon_acc += delta
	if _moon_acc >= MOON_STEP_SECS and night_clock.speed > 0.0:
		_moon_acc = 0.0
		_apply_moon()
		_apply_dawn()
		NightSky.set_cloud_offset(NightSky.cloud_offset_for_minutes(night_clock.minutes))
		var mist := NightSky.mist_for_minutes(night_clock.minutes)
		if not is_equal_approx(mist, _mist):
			_mist = mist
			_apply_air(smoothstep(0.0, 1.0, _blend))
	_blink_acc += delta
	if _blink_acc >= BLINK_STEP_SECS:
		_blink_time += _blink_acc
		_blink_acc = 0.0
		NightSky.set_blink(_blink_time)
	if _blend < 1.0:
		_blend_acc += delta
		if _blend_acc >= BLEND_STEP_SECS:
			_blend += _blend_acc / BLEND_SECS
			_blend_acc = 0.0
			_blend = minf(_blend, 1.0)
			var k := smoothstep(0.0, 1.0, _blend)
			NightSky.set_glow(sky, _from_color.lerp(_to_color, k), lerpf(_from_height, _to_height, k))
			_apply_air(k)
	_district_acc += delta
	if _district_acc < DISTRICT_CHECK_SECS:
		return
	_district_acc = 0.0
	var d := current_district()
	if d != _district:
		_district = d
		# every kind has a glow row (#653); downtown's is only a safety net
		var g: Dictionary = NightSky.GLOW.get(d, NightSky.GLOW["downtown"])
		_from_color = _from_color.lerp(_to_color, _blend)
		_from_height = lerpf(_from_height, _to_height, _blend)
		_from_air = _air_at(_blend)
		_to_color = g.color
		_to_height = g.height_deg
		_to_air = NightSky.air(d)
		_blend = 0.0
		_blend_acc = 0.0

## The building-mix district (districts.gd) of the chunk the player is on.
func current_district() -> String:
	if game == null or game.get("player") == null:
		return _district
	var z: float = RoadFrame.unroll(game.player.position).z
	var idx := int(floor(-z / RoadChunkBuilder.CHUNK_LEN)) + int(game.origin_index)
	return Districts.name_at(idx)

## The air between the district we left and the one we are in, k 0..1.
func _air_at(k: float) -> Dictionary:
	return {
		"fog": lerpf(float(_from_air.fog), float(_to_air.fog), k),
		"color": (_from_air.color as Color).lerp(_to_air.color, k),
		"sat": lerpf(float(_from_air.sat), float(_to_air.sat), k),
	}

## Writes the air at blend k (and the hour's mist) to the Environment.
func _apply_air(k: float) -> void:
	if env == null:
		return
	var a := _air_at(k)
	env.fog_density = NightSky.FOG_DENSITY * float(a.fog) * _mist
	env.fog_light_color = a.color
	env.adjustment_saturation = _base_sat * float(a.sat)

func _apply_moon() -> void:
	NightSky.set_moon_time(sky, _night, night_clock.minutes / NightClock.NIGHT_MINUTES)

## Dawn follows the clock (5 a.m. to 6 a.m.); only set when the value moves.
func _apply_dawn() -> void:
	var d := NightSky.dawn_for_minutes(night_clock.minutes)
	if not is_equal_approx(d, NightSky.dawn):
		NightSky.set_dawn(d)

func _on_night_ended(n: int) -> void:
	# Emitted just before the clock steps on, so the new night is n + 1.
	_night = n + 1
	NightSky.set_night(sky, _night)
	_apply_moon()
	NightSky.set_dawn(0.0)
	NightSky.set_cloud_offset(0.0)
