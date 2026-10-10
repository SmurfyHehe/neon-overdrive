extends Node
class_name DamageAudio

# Rattle of a damaged car (damage slice 1, 2026-10-09, Roy: "rattle sounds
# when damaged"). Next to CrashAudio on the player's car; reads CarDamage,
# never touches physics.
#
# One loop, synthesised here (no files, nothing to license): loose trim and
# panels knocking in uneven bursts, three small resonances for metal and
# plastic. Its level is CarDamage.rattle_level() (nothing until a part is
# properly hurt) times how hard the road shakes the car: speed, plus the
# suspension working over bumps and kerbs. Stopped, the car is silent.
#
# `level` is for tests (silent driver).

const RATE := 22050
const SECONDS := 3.0
const BURSTS_PER_SEC := 7.0
const GAIN := 0.55
const SPEED_FROM := 2.0     # m/s
const SPEED_FULL := 25.0
const BUMP_FULL := 2.5      # m/s of summed suspension travel speed: a kerb
const ATTACK := 12.0
const RELEASE := 6.0

var level := 0.0
var _player: PlayerCar
var _audio: AudioStreamPlayer
var _prev_len: Array[float] = [0.0, 0.0, 0.0, 0.0]

func _init() -> void:
	name = "DamageAudio"

func _ready() -> void:
	_player = get_parent() as PlayerCar
	if _player == null:
		push_error("DamageAudio must be a child of a PlayerCar")
		set_physics_process(false)
		return
	_audio = AudioStreamPlayer.new()
	_audio.name = "RattleAudio"
	_audio.bus = &"Tires"
	_audio.volume_db = -80.0
	_audio.stream = AudioDsp.cached("res://scripts/audio/damage_audio.gd", "rattle", make_rattle)
	add_child(_audio)

func _physics_process(delta: float) -> void:
	var loose := _player.damage.rattle_level()
	var target := 0.0
	if loose > 0.0:
		var bump := 0.0
		for i in mini(4, _player.wheel_array.size()):
			var w: Wheel = _player.wheel_array[i]
			bump += absf(w.spring_current_length - _prev_len[i]) / delta
			_prev_len[i] = w.spring_current_length
		var shake := maxf(smoothstep(SPEED_FROM, SPEED_FULL, _player.speed) * 0.7,
			clampf(bump / BUMP_FULL, 0.0, 1.0))
		target = loose * shake
	level = move_toward(level, target, delta * (ATTACK if target > level else RELEASE))
	if level > 0.001:
		_audio.volume_db = linear_to_db(level * GAIN)
		if not _audio.playing:
			_audio.play(randf() * SECONDS)
	elif _audio.playing:
		_audio.stop()

## The loop: random knocks in bursts through metal and plastic resonances.
static func make_rattle() -> AudioStream:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4411
	var n := int(RATE * SECONDS)
	var fade := int(RATE * 0.05)
	var s := PackedFloat32Array()
	s.resize(n + fade)
	var bank: Array[AudioDsp.Reso] = [
		AudioDsp.reso(RATE, 1850.0, 180.0),
		AudioDsp.reso(RATE, 3150.0, 260.0),
		AudioDsp.reso(RATE, 640.0, 90.0),
	]
	var amps := [0.6, 0.35, 0.9]
	var hp := AudioDsp.hp(RATE, 180.0)
	# a burst is a few knocks a few ms apart, like a panel bouncing
	var knocks := {}
	var t := 0.0
	while t < SECONDS:
		t += rng.randf_range(0.3, 1.7) / BURSTS_PER_SEC
		var at := int(t * RATE)
		var count := rng.randi_range(1, 4)
		var strength := rng.randf_range(0.4, 1.0)
		for k in count:
			var i := at + int(k * rng.randf_range(0.004, 0.011) * RATE)
			if i < n + fade:
				knocks[i] = strength * pow(0.6, k)
	for i in n + fade:
		var x: float = knocks.get(i, 0.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		var v := 0.0
		for k in bank.size():
			v += bank[k].step(x) * float(amps[k])
		s[i] = hp.step(v)
	s = AudioDsp.seamless(s, n, fade)
	return AudioDsp.to_wav(AudioDsp.normalise(s, 0.7), RATE, true)
