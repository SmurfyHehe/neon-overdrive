# Plays EngineSynth live from the parent Vehicle's GEVP state (2026-09-29,
# prototype for PROPOSAL-audio.md option C). One node the vehicle owns,
# reading motor_rpm / throttle_amount / motor_is_redline each frame -- audio
# stays out of the physics code.
extends AudioStreamPlayer
class_name EngineAudio

## Seconds of audio buffered ahead. Lower = engine reacts sooner to the
## throttle, higher = more tolerant of frame hitches.
const BUFFER_SECS := 0.06
const ENGINE_VOLUME := 0.5  # EngineSynth's own default level

## Which car's exhaust preset the player car starts with (exhaust_tune.gd).
## Placeholder until the cars are built from fleet.json (stage B step 5).
const START_PRESET := "p1_coupe"

var synth := EngineSynth.new()
## The exhaust tune lives in the car's spec under "exhaust" (a dictionary, the
## same one the Tuner screen's sliders and tune slots write); this node copies it
## into synth.tune every frame and keeps a saved copy on disk.
var _spec: Dictionary
var _saved := {}
var _seen_blow_offs := 0
var _was_up_shifting := false
var _vehicle: Vehicle
var _playback: AudioStreamGeneratorPlayback

func _ready() -> void:
	_vehicle = get_parent() as Vehicle
	synth.tune = ExhaustTune.for_car(START_PRESET)
	_load_tune()
	synth.apply_voice(_spec.get("engine_voice", {}))  # per-car engine (#80)
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
	sync_tune()
	synth.volume = ENGINE_VOLUME if _vehicle.engine_running else 0.0  # a stalled engine is silent
	if _vehicle.turbo_boost_max > 0.0:
		synth.boost = clampf(_vehicle.boost / _vehicle.turbo_boost_max, 0.0, 1.0)
		if _vehicle.blow_off_count != _seen_blow_offs:
			_seen_blow_offs = _vehicle.blow_off_count
			synth.blow_off(synth.boost + 0.3)
	else:
		synth.boost = 0.0
	# Flat-out upshift: the ignition cut bangs (the synth only does it on
	# high-flame cars). Same edge and law as the upshift flame.
	var up := _vehicle.is_up_shifting
	if up and not _was_up_shifting and ExhaustFlames.upshift_spits(_vehicle):
		synth.shift_cut(0.8 + 0.2 * clampf(_vehicle.throttle_input, 0.0, 1.0))
	_was_up_shifting = up
	var n := _playback.get_frames_available()
	if n > 0:
		_playback.push_buffer(synth.render(n, _vehicle.motor_rpm,
				_vehicle.throttle_amount, _vehicle.motor_is_redline))

# The exhaust tune is edited on the Tuner screen (Exhaust page) through
# CarSpec.set_param(), the single write path, so the spec stays the one copy.
# Here it is mirrored into the synth and saved: a change made while the game was
# paused is written to disk on the first tick after it resumes.
func _physics_process(_delta: float) -> void:
	sync_tune()
	if _spec.get("exhaust", {}) != _saved:
		_save_tune()

## Spec -> synth. The spec is the single copy; this is the only reader. Runs every
## frame while driving; the Tuner screen calls it too, because this node does not
## tick while the game is paused.
func sync_tune() -> void:
	synth.tune.apply_dict(_spec.get("exhaust", {}))

func _load_tune() -> void:
	var s: Variant = _vehicle.get("spec")
	_spec = s if s is Dictionary else {}
	if not _spec.get("exhaust") is Dictionary:
		_spec["exhaust"] = ExhaustTune.for_car(START_PRESET).to_dict()
	# A saved tune from an earlier run wins over the preset.
	var saved := ExhaustTune.load_saved(START_PRESET)
	for k in saved:
		CarSpec.set_param(_vehicle, _spec, "exhaust/" + k, saved[k])
	_saved = _spec.exhaust.duplicate()
	sync_tune()

func _save_tune() -> void:
	_saved = _spec.exhaust.duplicate()
	ExhaustTune.save_car(START_PRESET, _saved)
