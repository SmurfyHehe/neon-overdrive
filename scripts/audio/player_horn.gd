class_name PlayerHorn
extends Node3D

# The player's horn (key map K2, 2026-10-11): J sounds it, from the key going
# down until it comes up. The voices are TrafficHorns' (the same six horns the
# traffic uses, by car kind; a badly damaged car gets the sour one).
#
# One looping take per horn (TrafficHorns.hold_stream): the onset once, then
# the steady horn round and round while the key is held. A tap still sounds
# for TAP_S (a real horn cannot make a shorter toot than its disc takes to
# speak). On release the level runs out over TAIL_S.
#
# It plays on the Traffic bus from the car's own position, with the traffic
# horns' reach, so the cockpit's low-pass (PerspectiveAudio) muffles it the way
# it muffles theirs: the horn is outside the cabin.
#
# It also says what the player did, for whoever listens later (nothing does
# yet): player_horn("toot") for a tap, "hey" for a second tap within HEY_GAP_S
# of the first, "lean" once the key has been down LEAN_S. It changes nothing
# else: no heat, cash, rep, score or damage.

signal player_horn(pattern: String)

const ACTION := &"horn"
const TAP_S := 0.16
const TAIL_S := 0.07
const HEY_GAP_S := 0.4
const LEAN_S := 1.0
## Body damage (CarDamage.Part.BODY, 0..1) from which the horn is the sour one.
const SOUR_BODY := 0.6
const HORN_DB := 3.0

## The car kind the horn goes by. Empty: the parent PlayerCar's.
var kind := ""
## The horn last sounded ("" before the first press), and what was counted.
var horn := ""
var presses := 0
var patterns: Array[String] = []

var _voice: AudioStreamPlayer3D
var _down := false
var _held := 0.0
var _leaned := false
var _since_tap := 1000.0
var _tap_waiting := false
var _second := false
var _sounding := false
var _sound_t := 0.0
var _tail_t := 0.0

func _init() -> void:
	name = "PlayerHorn"

func _ready() -> void:
	if kind == "" and get_parent() is PlayerCar:
		kind = PlayerCar.chassis_kind()
	_voice = AudioStreamPlayer3D.new()
	_voice.name = "HornVoice"
	# the tail fades every frame while it sounds: a gain bus (#567)
	PlayerGain.route(_voice, &"Traffic", HORN_DB)
	_voice.unit_size = 14.0
	_voice.max_distance = 160.0
	add_child(_voice)
	TrafficHorns.warm(horn_name())

func _exit_tree() -> void:
	_voice.stop()
	_voice.stream = null
	_sounding = false
	TrafficHorns.finish()

## The horn this car sounds right now.
func horn_name() -> String:
	return TrafficHorns.horn_for(kind, _badly_damaged())

func _badly_damaged() -> bool:
	var car := get_parent()
	if car == null:
		return false
	var damage: Variant = car.get("damage")
	return damage is CarDamage and damage.enabled and damage.part(CarDamage.Part.BODY) >= SOUR_BODY

## True from the press until the tail has run out.
func is_sounding() -> bool:
	return _sounding

func _process(delta: float) -> void:
	var down := InputMap.has_action(ACTION) and Input.is_action_pressed(ACTION)
	if down and not _down:
		_press()
	elif _down and not down:
		_release()
	_down = down
	if _down:
		_held += delta
		if _held >= LEAN_S and not _leaned:
			_leaned = true
			_tap_waiting = false
			_say("lean")
	else:
		_since_tap += delta
	if not _sounding:
		return
	_sound_t += delta
	if _down or _sound_t < TAP_S:
		return
	_tail_t += delta
	if _tail_t >= TAIL_S:
		_voice.stop()
		_sounding = false
	else:
		PlayerGain.set_db(_voice, HORN_DB + linear_to_db(1.0 - _tail_t / TAIL_S))

func _press() -> void:
	presses += 1
	_held = 0.0
	_leaned = false
	_second = _tap_waiting and _since_tap <= HEY_GAP_S
	horn = horn_name()
	_sounding = true
	_sound_t = 0.0
	_tail_t = 0.0
	var take := TrafficHorns.hold_stream(horn)
	if take == null:
		return   # still being built: this one is silent
	_voice.stream = take
	PlayerGain.set_db(_voice, HORN_DB)
	_voice.play()

func _release() -> void:
	if _leaned:
		return
	_since_tap = 0.0
	if _second:
		_tap_waiting = false
		_say("hey")
	else:
		_tap_waiting = true
		_say("toot")

func _say(pattern: String) -> void:
	patterns.append(pattern)
	if patterns.size() > 20:
		patterns.pop_front()
	player_horn.emit(pattern)
