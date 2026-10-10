class_name SkyDirector
extends Node

# Drives the night sky from the game (night pass, 2026-10-10):
# - the moon climbs along tonight's path as the clock runs (NightSky.moon_path),
# - the glow dome follows the district the player is in, blending over a few
#   seconds when the road changes district,
# - a new night (6 a.m. rollover) re-seeds the stars, phase and moon path.
#
# The moon direction and the dome are global shader parameters (see
# night_sky.gd), so moving them costs nothing on the render side; they are
# still stepped (MOON_STEP_SECS, BLEND_STEP_SECS) rather than set every frame,
# and the district lookup runs DISTRICT_CHECK_SECS apart. No draw calls.

const Districts := preload("res://scripts/world/districts.gd")

const MOON_STEP_SECS := 2.0
const BLEND_SECS := 4.0
const BLEND_STEP_SECS := 0.1
const DISTRICT_CHECK_SECS := 0.25

var sky: Sky
var night_clock: NightClock
var game: Node  # Game: player, origin_index

var _district := NightSky.DEFAULT_DISTRICT
var _from_color: Color
var _from_height := 0.0
var _to_color: Color
var _to_height := 0.0
var _blend := 1.0
var _blend_acc := 0.0
var _moon_acc := 0.0
var _district_acc := 0.0
var _night := 0

func _ready() -> void:
	name = "SkyDirector"
	_night = night_clock.night
	var g: Dictionary = NightSky.GLOW[_district]
	_from_color = g.color
	_to_color = g.color
	_from_height = g.height_deg
	_to_height = g.height_deg
	night_clock.night_ended.connect(_on_night_ended)
	_apply_moon()
	NightSky.set_dawn(NightSky.dawn_for_minutes(night_clock.minutes))

func _process(delta: float) -> void:
	_moon_acc += delta
	if _moon_acc >= MOON_STEP_SECS and night_clock.speed > 0.0:
		_moon_acc = 0.0
		_apply_moon()
		_apply_dawn()
	if _blend < 1.0:
		_blend_acc += delta
		if _blend_acc >= BLEND_STEP_SECS:
			_blend += _blend_acc / BLEND_SECS
			_blend_acc = 0.0
			_blend = minf(_blend, 1.0)
			var k := smoothstep(0.0, 1.0, _blend)
			NightSky.set_glow(sky, _from_color.lerp(_to_color, k), lerpf(_from_height, _to_height, k))
	_district_acc += delta
	if _district_acc < DISTRICT_CHECK_SECS:
		return
	_district_acc = 0.0
	var d := current_district()
	if d != _district:
		_district = d
		var g: Dictionary = NightSky.GLOW[d]
		_from_color = _from_color.lerp(_to_color, _blend)
		_from_height = lerpf(_from_height, _to_height, _blend)
		_to_color = g.color
		_to_height = g.height_deg
		_blend = 0.0
		_blend_acc = 0.0

## The building-mix district (districts.gd) of the chunk the player is on.
func current_district() -> String:
	if game == null or game.get("player") == null:
		return _district
	var z: float = RoadFrame.unroll(game.player.position).z
	var idx := int(floor(-z / RoadChunkBuilder.CHUNK_LEN)) + int(game.origin_index)
	return Districts.name_at(idx)

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
