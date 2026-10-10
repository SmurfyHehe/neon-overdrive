extends Node

# The starter motor (2026-10-10, Roy: "i want you to need to actually start
# the car"). A run starts with the engine off and X cranks it; until now the
# crank was silent, so a press of X seemed to do nothing for half a second.
#
# One loop, synthesised here (no files, nothing to license): the starter's
# gear whine, sagging and recovering as each cylinder comes up on compression
# ("ruh-ruh-ruh"), a thump per compression and some brush hash. It plays while
# PlayerCar.is_cranking() and stops the tick the engine fires, when
# EngineAudio's own voice comes in.
#
# `level` is for tests (silent driver).
#
# No class_name on purpose: preload it, so no class cache refresh is needed.

const RATE := 22050
const SECONDS := 1.0
## Compression strokes a second while cranking (a four at about 270 rpm).
const CHUGS := 9
const WHINE_HZ := 430.0
const GAIN := 0.5
const ATTACK := 30.0
const RELEASE := 14.0

var level := 0.0
## How many times the starter has begun to turn (tests).
var cranks := 0
var _player: PlayerCar
var _audio: AudioStreamPlayer
var _was_cranking := false

func _init() -> void:
	name = "StarterAudio"

func _ready() -> void:
	_player = get_parent() as PlayerCar
	if _player == null:
		push_error("StarterAudio must be a child of a PlayerCar")
		set_physics_process(false)
		return
	_audio = AudioStreamPlayer.new()
	_audio.name = "CrankAudio"
	_audio.bus = &"Engine"
	_audio.volume_db = -80.0
	_audio.stream = AudioDsp.cached("res://scripts/audio/starter_audio.gd", "crank", make_crank)
	add_child(_audio)

func _physics_process(delta: float) -> void:
	var cranking := _player.is_cranking()
	if cranking and not _was_cranking:
		cranks += 1
	_was_cranking = cranking
	var target := 1.0 if cranking else 0.0
	level = move_toward(level, target, delta * (ATTACK if target > level else RELEASE))
	if level > 0.001:
		_audio.volume_db = linear_to_db(level * GAIN)
		if not _audio.playing:
			_audio.play()
	elif _audio.playing:
		_audio.stop()

## The loop: a whine that sags on every compression stroke, with a thump.
static func make_crank() -> AudioStream:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9127
	var n := int(RATE * SECONDS)
	var fade := int(RATE * 0.03)
	var s := PackedFloat32Array()
	s.resize(n + fade)
	var hash_bp := AudioDsp.bp(RATE, 2400.0, 1.2)
	var body := AudioDsp.lp(RATE, 2600.0)
	var phase := 0.0
	for i in n + fade:
		var t := float(i) / RATE
		var stroke := fposmod(t * CHUGS, 1.0)
		# comp: high as the piston comes up, gone once it is over the top
		var comp := pow(sin(stroke * PI), 2.0)
		var hz := WHINE_HZ * (1.0 - 0.22 * comp)
		phase += hz / RATE
		var saw := fposmod(phase, 1.0) * 2.0 - 1.0
		var whine := saw * 0.5 + sin(phase * TAU * 2.0) * 0.25 + sin(phase * TAU * 0.5) * 0.2
		var thump := sin(TAU * 62.0 * stroke / CHUGS) * exp(-stroke * 9.0) * 0.9
		var hiss := hash_bp.step(rng.randf_range(-1.0, 1.0)) * 0.25
		s[i] = body.step(whine * (0.55 + 0.45 * comp) + thump + hiss * (0.4 + 0.6 * comp))
	s = AudioDsp.seamless(s, n, fade)
	return AudioDsp.to_wav(AudioDsp.normalise(s, 0.7), RATE, true)
