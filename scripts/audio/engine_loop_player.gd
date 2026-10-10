# Plays an EngineLoops bank from the car's rpm and throttle (2026-10-10).
#
# At most MAX_VOICES looping players run at once: the nearest rpm band (and its
# neighbour, only while the two cross-fade) at the lifted and the open load, plus
# the odd one still fading out. Every other player is stopped, not muted, so it
# costs nothing.
#
# Why it does not click:
# - a player's stream only changes while that player is stopped or has faded
#   below FREE_LEVEL; if rpm jumps faster than that, the new band waits a frame
#   or two (deferred) rather than cut a voice off;
# - every level moves through a one-pole smoother (LEVEL_TAU), and Godot ramps a
#   player's volume across each mix chunk;
# - loops are seamless (EngineLoops.seam_jump), and a new band starts at the
#   firing phase of the one it replaces, so the note does not jump.
extends Node
class_name EngineLoopPlayer

const VOICES_PER_LOAD := 3
const MAX_VOICES := VOICES_PER_LOAD * 2
## A voice that is no longer wanted fades this fast (seconds), so it is free to take
## a new band before that band is needed.
const RETIRE_TAU := 0.008
## A voice quieter than this may be handed a new stream.
const FREE_LEVEL := 0.02
## Seconds for a level to move 63 % of the way to its target.
const LEVEL_TAU := 0.03
const THROTTLE_TAU := 0.06
## Below this a voice is stopped (-66 dB).
const STOP_LEVEL := 0.0005
## Slow drift of pitch and level so a held rpm does not repeat every loop.
const WANDER_PITCH := 0.0025
const WANDER_LEVEL := 0.1
## The limiter's gate: how much of the note is left in a cut, how long each
## state lasts (seconds).
const LIMITER_FLOOR := 0.35
const LIMITER_HOLD_MIN := 0.025
const LIMITER_HOLD_MAX := 0.07

var loops: EngineLoops
## 0..1 scale on the whole bank: EngineAudio fades it in while the live synth
## fades out.
var gain := 1.0
var wander := 0.6
## Streams replaced while the player was audible (would click). Tests expect 0.
var hard_swaps := 0

var _players: Array[AudioStreamPlayer] = []
var _band := PackedInt32Array([-1, -1, -1, -1, -1, -1])
var _level := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
## Bands that could not be given a voice yet (rpm moved faster than voices free up).
var deferred := 0
var _throttle := 0.0
var _gate := 1.0
var _gate_to := 1.0
var _gate_left := 0.0
var _w_pitch := 0.0
var _w_level := 0.0
var _w_pitch_to := 0.0
var _w_level_to := 0.0
var _w_left := 0.0
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.seed = 20261010
	for i in MAX_VOICES:
		var p := AudioStreamPlayer.new()
		p.name = "Loop%d" % i
		p.bus = &"Engine"
		add_child(p)
		_players.append(p)

## Swaps in a new bank. Everything stops and fades back in from silence.
func set_loops(l: EngineLoops) -> void:
	loops = l
	for i in MAX_VOICES:
		_players[i].stop()
		_band[i] = -1
		_level[i] = 0.0

func playing_count() -> int:
	var n := 0
	for p in _players:
		if p.playing:
			n += 1
	return n

## Call every frame. `running` false (stalled or off) fades everything out.
func update(delta: float, rpm: float, throttle: float, redline: bool, running: bool) -> void:
	if loops == null or loops.band_count() < 2 or _players.size() < MAX_VOICES:
		return
	var k_lvl := 1.0 - exp(-delta / LEVEL_TAU)
	var k_ret := 1.0 - exp(-delta / RETIRE_TAU)
	_throttle += (clampf(throttle, 0.0, 1.0) - _throttle) * (1.0 - exp(-delta / THROTTLE_TAU))
	_step_wander(delta)
	_step_gate(delta, redline)
	var scale := (gain if running else 0.0) * _gate * (1.0 + WANDER_LEVEL * wander * _w_level)
	var pk := EngineLoops.pick(loops.rpms, maxf(rpm, 0.0))
	var k := int(pk.x)
	var state_w := [cos(_throttle * PI * 0.5), sin(_throttle * PI * 0.5)]  # lifted, open
	var band_w := [pk.y, pk.z]
	var target := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var claimed := PackedByteArray([0, 0, 0, 0, 0, 0])
	var phase := _current_phase()
	for state in 2:
		var base := state * VOICES_PER_LOAD
		var todo: Array[int] = []
		# bands that already have a voice keep it
		for j in 2:
			var w: float = state_w[state] * band_w[j] * scale
			if w <= STOP_LEVEL:
				continue
			var band := k + j
			var found := -1
			for v in range(base, base + VOICES_PER_LOAD):
				if _band[v] == band and _players[v].playing and claimed[v] == 0:
					found = v
					break
			if found >= 0:
				claimed[found] = 1
				target[found] = w
			else:
				todo.append(j)
		# the others take the quietest free voice, or wait
		for j in todo:
			var w: float = state_w[state] * band_w[j] * scale
			var pick_v := -1
			for v in range(base, base + VOICES_PER_LOAD):
				if claimed[v] == 1:
					continue
				if not _players[v].playing or _level[v] <= FREE_LEVEL:
					if pick_v < 0 or _level[v] < _level[pick_v]:
						pick_v = v
			if pick_v < 0:
				deferred += 1
				continue
			claimed[pick_v] = 1
			target[pick_v] = w
			_ensure_band(pick_v, k + j, state, phase)
	for v in MAX_VOICES:
		var p := _players[v]
		var kk := k_lvl if target[v] > 0.0 else k_ret
		_level[v] += (target[v] - _level[v]) * kk
		if target[v] <= STOP_LEVEL and _level[v] <= STOP_LEVEL:
			_level[v] = 0.0
			if p.playing:
				p.stop()
			_band[v] = -1
			continue
		if _band[v] < 0:
			continue
		p.volume_db = linear_to_db(maxf(_level[v], 0.00001))
		p.pitch_scale = clampf(rpm / loops.rpms[_band[v]] * (1.0 + WANDER_PITCH * wander * _w_pitch), 0.05, 4.0)

## Makes player `v` play `band` (state 0 lifted, 1 open), starting at the firing
## phase `phase` (cycles, or -1 for none playing yet).
func _ensure_band(v: int, band: int, state: int, phase: float) -> void:
	if _band[v] == band and _players[v].playing:
		return
	var p := _players[v]
	if p.playing and _level[v] > FREE_LEVEL:
		hard_swaps += 1
	var stream: AudioStreamWAV = loops.open[band] if state == 1 else loops.lift[band]
	p.stream = stream
	var cycle_s := 120.0 / loops.rpms[band]
	var cycle_idx := _rng.randi_range(0, maxi(loops.cycles[band] - 1, 0))
	var start := (maxf(phase, 0.0) + cycle_idx) * cycle_s
	p.play(fposmod(start, maxf(stream.get_length() - 0.001, 0.001)))
	_band[v] = band

## Firing phase (0..1 of a cycle) of the loudest voice playing, from the audio
## clock, or -1 when none is.
func _current_phase() -> float:
	var best := -1
	for v in MAX_VOICES:
		if _band[v] >= 0 and _players[v].playing and (best < 0 or _level[v] > _level[best]):
			best = v
	if best < 0:
		return -1.0
	var cycle_s := 120.0 / loops.rpms[_band[best]]
	return fposmod(_players[best].get_playback_position() / cycle_s, 1.0)

func _step_wander(delta: float) -> void:
	_w_left -= delta
	if _w_left <= 0.0:
		_w_pitch_to = _rng.randf_range(-1.0, 1.0)
		_w_level_to = _rng.randf_range(-1.0, 1.0)
		_w_left = _rng.randf_range(0.6, 1.4)
	var k := 1.0 - exp(-delta / 0.5)
	_w_pitch += (_w_pitch_to - _w_pitch) * k
	_w_level += (_w_level_to - _w_level) * k

## On the limiter the note chops: random short holds between full level and
## LIMITER_FLOOR, smoothed so each edge is a few ms, not a click.
func _step_gate(delta: float, redline: bool) -> void:
	if redline:
		_gate_left -= delta
		if _gate_left <= 0.0:
			_gate_to = 1.0 if _gate_to < 1.0 else LIMITER_FLOOR
			_gate_left = _rng.randf_range(LIMITER_HOLD_MIN, LIMITER_HOLD_MAX)
	else:
		_gate_to = 1.0
		_gate_left = 0.0
	_gate += (_gate_to - _gate) * (1.0 - exp(-delta / 0.012))
