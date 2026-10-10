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
const TURBO_VOLUME := 0.5   # TurboSynth's; the Turbo bus slider sits on top

## Which car's exhaust preset the player car starts with (exhaust_tune.gd).
## Placeholder until the cars are built from fleet.json (stage B step 5).
const START_PRESET := "p1_coupe"

## Lift-off blow-off: the pedal drops below LIFT_OFF within LIFT_WINDOW seconds of being
## above LIFT_HOT, on at least LIFT_BOOST of full boost. GEVP's own count only trips when
## throttle_amount falls from over 0.5 to under 0.2 in a single tick, which in practice
## means a gearshift or the limiter cut, never a driver easing off the pedal.
const LIFT_HOT := 0.6
const LIFT_OFF := 0.2
const LIFT_WINDOW := 0.6
const LIFT_BOOST := 0.3

## Baked loops (EngineLoops) carry the steady engine note once they are ready;
## NEON_ENGINE_LOOPS=0 keeps the per-sample live synth for everything (A/B, fallback).
static var loops_enabled := OS.get_environment("NEON_ENGINE_LOOPS") != "0"
## Seconds the live note fades out while the loops fade in.
const HANDOFF_SECS := 0.12
## A tone change (Tuner sliders) re-bakes after the value has held this long.
const REBAKE_DELAY := 0.8
enum LoopMode { LIVE, HANDOFF, LOOPS }

var synth := EngineSynth.new()
## The bank player and the state of the hand-over; see _update_loops.
var bank: EngineLoopPlayer
var loop_mode := LoopMode.LIVE
## Blocks handed to the worker as the full live voice / as events only (tests).
var blocks_full := 0
var blocks_events := 0
var _handoff_t := 0.0
var _bake_task := -1
var _bake_cancel := {"stop": false}
var _bake_out := {}
var _baked_sig := Vector2i(-1, -1)
var _want_sig := Vector2i(-1, -1)
var _want_for := 0.0
## The turbo voice (B1): its own synth and its own stream on the Turbo bus, so
## the Turbo slider is a bus fader. Rendered by the same worker task as the engine.
var turbo := TurboSynth.new()
var _turbo_player: AudioStreamPlayer
var _turbo_playback: AudioStreamGeneratorPlayback
var _was_shifting := false
## The exhaust tune lives in the car's spec under "exhaust" (a dictionary, the
## same one the Tuner screen's sliders and tune slots write); this node copies it
## into synth.tune every frame and keeps a saved copy on disk.
var _spec: Dictionary
var _saved := {}
var _seen_blow_offs := 0
var _since_hot := 9.0     # seconds since the throttle last sat above LIFT_HOT
var _lift_vented := false # this lift has already vented; rearms when the throttle is back on
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
	turbo.mix_rate = synth.mix_rate
	# Per-part turbo voice (B1) under the car's boost setup: C1's ForcedInduction
	# keeps the kind in the boost_kind meta ("single" when unset or before C1).
	turbo.apply_voice(TurboVoice.for_setup(_spec.get("turbo_voice", {}),
			String(_vehicle.get_meta(&"boost_kind", "single"))))
	_turbo_player = AudioStreamPlayer.new()
	_turbo_player.name = "Turbo"
	var tgen := AudioStreamGenerator.new()
	tgen.mix_rate = synth.mix_rate
	tgen.buffer_length = BUFFER_SECS
	_turbo_player.stream = tgen
	_turbo_player.bus = &"Turbo"
	add_child(_turbo_player)
	_turbo_player.play()
	_turbo_playback = _turbo_player.get_stream_playback()
	bank = EngineLoopPlayer.new()
	bank.name = "Loops"
	bank.wander = float(_spec.get("engine_voice", {}).get("wander", 0.6))
	add_child(bank)

# Rendering runs on a worker thread (frame-rate pass, 2026-10-08). The synth is
# a per-sample GDScript loop, about 0.5 us a sample on the i5-1235U: 0.4 ms of
# a 60 fps frame, and after a slow frame the buffer has drained further, so the
# next block is bigger (up to 2.6k samples) and lands on a frame that is
# already late.
# The block is the same one as before (same length, same inputs, rendered and
# pushed in this frame); only the thread differs, so the sound is unchanged.
# The synth is touched only by the task while one runs: every main-thread use
# goes through _join() first, which by then is normally a no-op (the task had
# the rest of the frame).
func _process(delta: float) -> void:
	if _playback == null:
		return
	_join()
	sync_tune()
	synth.volume = ENGINE_VOLUME if _vehicle.engine_running else 0.0  # a stalled engine is silent
	turbo.volume = TURBO_VOLUME if _vehicle.engine_running else 0.0
	_update_loops(delta)
	var shifting := _vehicle.is_shifting
	if _vehicle.turbo_boost_max > 0.0:
		turbo.boost = clampf(_vehicle.boost / _vehicle.turbo_boost_max, 0.0, 1.0)
		turbo.boost_max_bar = _vehicle.turbo_boost_max
		turbo.rpm_norm = clampf(_vehicle.motor_rpm / maxf(_vehicle.max_rpm, 1.0), 0.0, 1.0)
		# Between gears on boost: the valve, short (the throttle is only off for
		# the shift). GEVP's one-tick throttle cut counts the same shift a tick
		# later; TurboSynth folds the two together (VENT_GAP).
		if shifting and not _was_shifting and turbo.boost > LIFT_BOOST:
			turbo.shift_vent(turbo.boost + 0.2)
		if _vehicle.blow_off_count != _seen_blow_offs:
			_seen_blow_offs = _vehicle.blow_off_count
			turbo.vent(turbo.boost + 0.3)
		if lift_off_vent(delta):
			turbo.vent(turbo.boost + 0.3)
	else:
		turbo.boost = 0.0
		turbo.rpm_norm = 0.0
	_was_shifting = shifting
	# Flat-out upshift: the ignition cut bangs (the synth only does it on
	# high-flame cars). Same edge and law as the upshift flame.
	var up := _vehicle.is_up_shifting
	if up and not _was_up_shifting and ExhaustFlames.upshift_spits(_vehicle):
		synth.shift_cut(0.8 + 0.2 * clampf(_vehicle.throttle_input, 0.0, 1.0))
	_was_up_shifting = up
	var n := _playback.get_frames_available()
	var tn := _turbo_playback.get_frames_available()
	if n > 0 or tn > 0:
		# The live note's level: full on its own, fading out through the hand-over,
		# and only the pops and bangs once the loops carry the tone.
		var f0 := 1.0
		var f1 := 1.0
		if loop_mode == LoopMode.HANDOFF:
			f0 = cos(clampf(_handoff_t - delta, 0.0, 1.0) * PI * 0.5)
			f1 = cos(clampf(_handoff_t, 0.0, 1.0) * PI * 0.5)
		if loop_mode == LoopMode.LOOPS:
			blocks_events += 1
		else:
			blocks_full += 1
		_task_start_usec = Time.get_ticks_usec()
		_task = WorkerThreadPool.add_task(_render.bind(n, _vehicle.motor_rpm,
				_vehicle.throttle_amount, _vehicle.motor_is_redline, tn,
				loop_mode == LoopMode.LOOPS, f0, f1), false, "engine audio")

## Worker thread: one block of each, straight into the streams.
func _render(n: int, rpm: float, throttle: float, redline: bool, tn: int,
		events_only := false, f0 := 1.0, f1 := 1.0) -> void:
	if n > 0:
		var block := synth.render_events(n, rpm, throttle, redline) if events_only 				else synth.render(n, rpm, throttle, redline)
		if f0 != 1.0 or f1 != 1.0:
			for i in n:
				var g := lerpf(f0, f1, float(i) / n)
				block[i] = block[i] * g
		_playback.push_buffer(block)
	if tn > 0:
		_turbo_playback.push_buffer(turbo.render(tn))

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
	if _bake_task >= 0:
		_bake_cancel["stop"] = true
		WorkerThreadPool.wait_for_task_completion(_bake_task)
		_bake_task = -1

## True on the frame the driver lifts off a hot boost. Needs the throttle to have been
## on within LIFT_WINDOW and the boost above LIFT_BOOST; one vent per lift.
func lift_off_vent(delta: float) -> bool:
	var thr := _vehicle.throttle_input
	if thr > LIFT_HOT:
		_since_hot = 0.0
		_lift_vented = false
	else:
		_since_hot += delta
	if thr < LIFT_OFF and not _lift_vented and _since_hot <= LIFT_WINDOW \
			and turbo.boost > LIFT_BOOST:
		_lift_vented = true
		return true
	return false

# The exhaust tune is edited on the Tuner screen (Exhaust page) through
# CarSpec.set_param(), the single write path, so the spec stays the one copy.
# _process mirrors it into the synth; here it is saved: a change made while the
# game was paused is written to disk on the first tick after it resumes.
func _physics_process(_delta: float) -> void:
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

# --- Baked loops ---------------------------------------------------------------
# The live synth plays from the first frame. A worker bakes (or loads from the
# cache) the loop bank for this car's voice; when it is ready the live note fades
# out over HANDOFF_SECS while the loops fade in, and from then on the synth only
# renders events (pops, limiter bangs, upshift cuts). A change to the two tune
# values that colour the note re-bakes in the background and swaps the bank in
# without dropping back to the live synth.

func _tone_sig() -> Vector2i:
	var t := synth.tune
	return Vector2i(roundi(t.loudness * 100.0), roundi(t.raspiness * 100.0))

func _update_loops(delta: float) -> void:
	if not loops_enabled:
		return
	if _bake_task >= 0:
		if not WorkerThreadPool.is_task_completed(_bake_task):
			return
		WorkerThreadPool.wait_for_task_completion(_bake_task)
		_bake_task = -1
		if not _bake_out.is_empty():
			bank.set_loops(EngineLoops.from_baked(_bake_out))
			if loop_mode == LoopMode.LIVE:
				loop_mode = LoopMode.HANDOFF
				_handoff_t = 0.0
		_bake_out = {}
	var sig := _tone_sig()
	if sig != _want_sig:
		_want_sig = sig
		_want_for = 0.0
	_want_for += delta
	if _baked_sig != _want_sig and (_baked_sig.x < 0 or _want_for >= REBAKE_DELAY):
		_baked_sig = _want_sig
		_bake_cancel = {"stop": false}
		var voice: Dictionary = (_spec.get("engine_voice", {}) as Dictionary).duplicate(true)
		_bake_task = WorkerThreadPool.add_task(_bake_job.bind(voice, sig.x / 100.0, sig.y / 100.0,
				_vehicle.idle_rpm, _vehicle.max_rpm, _bake_cancel), false, "engine loops")
		return
	if loop_mode == LoopMode.HANDOFF:
		_handoff_t += delta / HANDOFF_SECS
		bank.gain = sin(clampf(_handoff_t, 0.0, 1.0) * PI * 0.5)
		if _handoff_t >= 1.0:
			loop_mode = LoopMode.LOOPS
			bank.gain = 1.0
	if loop_mode != LoopMode.LIVE:
		bank.update(delta, _vehicle.motor_rpm, _vehicle.throttle_amount, _vehicle.motor_is_redline,
				_vehicle.engine_running)

## Worker thread: the bank for one voice, from the cache when it was baked before.
func _bake_job(voice: Dictionary, loudness: float, raspiness: float, idle: float, max_rpm: float,
		cancel: Dictionary) -> void:
	_bake_out = EngineLoops.bake_cached(voice, loudness, raspiness, idle, max_rpm, ENGINE_VOLUME, cancel)
