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
## The block being rendered on a worker thread (WorkerThreadPool task id), or
## -1. See _process.
var _task := -1
var _task_start_usec := 0
## Flame events from finished blocks, waiting for ExhaustFlames (take_flames).
var _flames := 0.0
## How long ago (s) the block those flames came from was handed to the synth.
var flames_late := 0.0

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

# Rendering runs on a worker thread (frame-rate pass, 2026-10-08). The synth is
# a per-sample GDScript loop, and after a slow frame the buffer has drained
# further, so the next block is bigger and lands on a frame that is already
# late. The block is the same one as before (same length, same inputs, rendered
# and pushed in this frame); only the thread differs, so the sound is unchanged.
# The synth is touched only by the task while one runs: every main-thread use
# goes through _join() first, which by then is normally a no-op (the task had
# the rest of the frame).
func _process(_delta: float) -> void:
	if _playback == null:
		return
	_join()
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
		_task_start_usec = Time.get_ticks_usec()
		_task = WorkerThreadPool.add_task(_render.bind(n, _vehicle.motor_rpm,
				_vehicle.throttle_amount, _vehicle.motor_is_redline), false, "engine audio")

## Worker thread: one block, straight into the stream.
func _render(n: int, rpm: float, throttle: float, redline: bool) -> void:
	_playback.push_buffer(synth.render(n, rpm, throttle, redline))

## Waits for the block in flight (if any) and collects its flame events.
func _join() -> void:
	if _task < 0:
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	var f := synth.take_flames()
	if f > 0.0:
		_flames = maxf(_flames, f)
		flames_late = (Time.get_ticks_usec() - _task_start_usec) / 1000000.0

## Largest flame since the last call, then resets: EngineSynth.take_flames()
## for the blocks collected so far. No _join(): ExhaustFlames calls this right
## after _process starts a block, and waiting for it here would put the render
## back on the main thread. See flames_late for the timing.
func take_flames() -> float:
	var f := _flames
	_flames = 0.0
	return f

func _exit_tree() -> void:
	_join()

# The exhaust tune is edited on the Tuner screen (Exhaust page) through
# CarSpec.set_param(), the single write path, so the spec stays the one copy.
# Here it is mirrored into the synth and saved: a change made while the game was
# paused is written to disk on the first tick after it resumes.
func _physics_process(_delta: float) -> void:
	# No sync_tune() here: _process syncs before every block, and syncing from
	# the physics tick would have to wait for the block in flight.
	if _spec.get("exhaust", {}) != _saved:
		_save_tune()

## Spec -> synth. The spec is the single copy; this is the only reader. Runs every
## frame while driving; the Tuner screen calls it too, because this node does not
## tick while the game is paused.
func sync_tune() -> void:
	_join()
	synth.tune.apply_dict(_spec.get("exhaust", {}))
	# Anti-lag is turbo-only: the synth sees it off on a car with no boost.
	if not ExhaustTune.anti_lag_live(_spec):
		synth.tune.anti_lag = 0.0

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
