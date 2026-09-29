# Plays EngineSynth live from the parent Vehicle's GEVP state (2026-09-29,
# prototype for PROPOSAL-audio.md option C). One node the vehicle owns,
# reading motor_rpm / throttle_amount / motor_is_redline each frame -- audio
# stays out of the physics code.
extends AudioStreamPlayer
class_name EngineAudio

## Seconds of audio buffered ahead. Lower = engine reacts sooner to the
## throttle, higher = more tolerant of frame hitches.
const BUFFER_SECS := 0.06

var synth := EngineSynth.new()
var _vehicle: Vehicle
var _playback: AudioStreamGeneratorPlayback

func _ready() -> void:
	_vehicle = get_parent() as Vehicle
	synth.mix_rate = AudioServer.get_mix_rate()
	synth.idle_rpm = _vehicle.idle_rpm
	synth.max_rpm = _vehicle.max_rpm
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = synth.mix_rate
	gen.buffer_length = BUFFER_SECS
	stream = gen
	bus = &"Engine"
	play()
	_playback = get_stream_playback()

func _process(_delta: float) -> void:
	if _playback == null:
		return
	var n := _playback.get_frames_available()
	if n > 0:
		_playback.push_buffer(synth.render(n, _vehicle.motor_rpm,
				_vehicle.throttle_amount, _vehicle.motor_is_redline))
