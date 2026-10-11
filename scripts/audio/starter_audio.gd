extends Node

# The starter motor and the key (2026-10-10, Roy: "i want you to need to
# actually start the car"). A run starts with the engine off and X cranks it;
# X on a running, standing car switches it off again (PlayerCar.key_off).
#
# Three sounds, all synthesised here (no files, nothing to license) and kept
# as plain samples, so playing them costs nothing per frame:
#
#  crank     the solenoid clunk and the pinion ratcheting into the ring gear,
#            then the starter's whine sagging on every compression stroke
#            ("ruh-RUH-ruh-ruh"): the first strokes slow, no two the same
#            length or weight, now and then a cylinder that half fires. The
#            head plays once and the tail loops, so it lasts as long as the
#            crank does (PlayerCar.crank_hold: longer on a cold engine).
#  catch     the starter winding down as it lets go, and the first firing
#            strokes: a few uneven thumps with one missing (the stumble) and
#            a breath of exhaust. EngineAudio's own voice comes in under it,
#            following the real revs as they flare and settle (START_FLARE).
#  shutdown  the last firing strokes slowing to nothing, two or three loose
#            exhaust burbles, the engine rocking to a stop on its mounts.
#
# Each has a few takes and every play picks one and nudges its pitch, so two
# starts in a row are not the same. Per car: one number, pace(cylinders), is
# the playback speed (and PlayerCar divides the crank time by it): a big V8
# turns over slow and heavy, the three-cylinder kei quick and buzzy.
#
# `level`, `cranks`, `catches`, `shutdowns` are for tests (silent driver).
#
# No class_name on purpose: preload it, so no class cache refresh is needed.

const RATE := 22050
const PATH := "res://scripts/audio/starter_audio.gd"
const CRANK_TAKES := 2
const CATCH_TAKES := 3
const STOP_TAKES := 2
## The crank take: the head (engage, slow first strokes) plays once, then
## [CRANK_LOOP_S, CRANK_S) repeats for as long as the starter is held.
const CRANK_S := 2.4
const CRANK_LOOP_S := 1.0
const CATCH_S := 0.8
const STOP_S := 1.15
## Compression strokes a second once the starter is up to speed (a four at
## about 270 rpm), and on the first, slowest stroke.
const CHUGS := 9.0
const CHUGS_FIRST := 5.5
const WHINE_HZ := 430.0
## Firing strokes a second at idle, where the shutdown begins (a four at 850).
const IDLE_FIRE_HZ := 28.0
const GAIN := 0.5
const CATCH_GAIN := 0.42
const STOP_GAIN := 0.55
const ATTACK := 60.0
const RELEASE := 14.0
## Each play is this much off pitch, either way.
const PITCH_SPREAD := 0.035

var level := 0.0
## How many times the starter has begun to turn, the engine has caught off
## it, and the key has switched it off (tests).
var cranks := 0
var catches := 0
var shutdowns := 0
var _player: PlayerCar
var _crank: AudioStreamPlayer
var _catch: AudioStreamPlayer
var _stop: AudioStreamPlayer
var _crank_takes: Array[AudioStream] = []
var _catch_takes: Array[AudioStream] = []
var _stop_takes: Array[AudioStream] = []
## Seconds of the catch and the shutdown still to play, on the game's clock
## (a headless run's audio clock is not the game's).
var _catch_left := 0.0
var _stop_left := 0.0
var _was_cranking := false
var _key_offs := 0
var _pace := 1.0
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	name = "StarterAudio"

## Playback speed for an engine of this many cylinders: under 1 is slower and
## deeper. Also how fast it turns over (PlayerCar.crank_hold).
static func pace(cylinders: int) -> float:
	if cylinders <= 3:
		return 1.24
	if cylinders <= 4:
		return 1.06
	if cylinders <= 6:
		return 0.94
	return 0.82

func _ready() -> void:
	_player = get_parent() as PlayerCar
	if _player == null:
		push_error("StarterAudio must be a child of a PlayerCar")
		set_physics_process(false)
		return
	_rng.randomize()
	_pace = _player.crank_pace()
	_key_offs = _player.key_offs
	for i in CRANK_TAKES:
		_crank_takes.append(AudioDsp.cached(PATH, "crank%d" % i, make_crank.bind(9127 + i * 31)))
	for i in CATCH_TAKES:
		_catch_takes.append(AudioDsp.cached(PATH, "catch%d" % i, make_catch.bind(417 + i * 53)))
	for i in STOP_TAKES:
		_stop_takes.append(AudioDsp.cached(PATH, "stop%d" % i, make_shutdown.bind(2203 + i * 17)))
	_crank = _voice("CrankAudio")
	_catch = _voice("CatchAudio")
	_stop = _voice("ShutdownAudio")

func _voice(voice_name: String) -> AudioStreamPlayer:
	var a := AudioStreamPlayer.new()
	a.name = voice_name
	a.bus = &"Engine"
	add_child(a)
	return a

## Plays one of `takes`, a little off pitch; returns how long it lasts.
func _play(a: AudioStreamPlayer, takes: Array[AudioStream], gain: float) -> float:
	a.stream = takes[_rng.randi() % takes.size()]
	a.pitch_scale = _pace * _rng.randf_range(1.0 - PITCH_SPREAD, 1.0 + PITCH_SPREAD)
	a.volume_db = linear_to_db(gain)
	a.play()
	return a.stream.get_length() / a.pitch_scale

func _physics_process(delta: float) -> void:
	var cranking := _player.is_cranking()
	if cranking and not _was_cranking:
		cranks += 1
		level = 0.0
		_catch.stop()
		_stop.stop()
		_catch_left = 0.0
		_stop_left = 0.0
		_play(_crank, _crank_takes, 0.001)
	elif _was_cranking and not cranking and _player.engine_running:
		catches += 1
		_catch_left = _play(_catch, _catch_takes, CATCH_GAIN)
	_was_cranking = cranking
	if _player.key_offs != _key_offs:
		_key_offs = _player.key_offs
		shutdowns += 1
		_catch.stop()
		_catch_left = 0.0
		_stop_left = _play(_stop, _stop_takes, STOP_GAIN)
	_catch_left = maxf(_catch_left - delta, 0.0)
	_stop_left = maxf(_stop_left - delta, 0.0)
	# The crank fades out over a few hundredths as the starter lets go.
	var target := 1.0 if cranking else 0.0
	level = move_toward(level, target, delta * (ATTACK if target > level else RELEASE))
	if level > 0.001:
		_crank.volume_db = linear_to_db(level * GAIN)
	elif _crank.playing and not cranking:
		_crank.stop()

## Which of the three is sounding (tests): never the crank with the shutdown.
func sounding() -> PackedStringArray:
	var out := PackedStringArray()
	if _crank.playing:
		out.append("crank")
	if _catch_left > 0.0:
		out.append("catch")
	if _stop_left > 0.0:
		out.append("shutdown")
	return out

## One exhaust thump: a low ring with a puff of noise on top.
class Puff:
	var ring: AudioDsp.Reso
	var air: AudioDsp.Biquad
	var env := 0.0
	var decay := 0.0
	var rng: RandomNumberGenerator

	func _init(rate: float, hz: float, ring_decay: float, air_hz: float, air_decay: float, r: RandomNumberGenerator) -> void:
		ring = AudioDsp.reso(rate, hz, ring_decay)
		air = AudioDsp.lp(rate, air_hz)
		decay = exp(-air_decay / rate)
		rng = r

	## `hit` is the strength of a thump starting on this sample, else 0.
	func step(hit: float) -> float:
		if hit > 0.0:
			env = hit
		env *= decay
		return ring.step(hit) + air.step(rng.randf_range(-1.0, 1.0)) * env

## The crank: engage, then the whine sagging on uneven compression strokes.
static func make_crank(seed_value: int) -> AudioStream:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := int(RATE * CRANK_S)
	var loop_at := int(RATE * CRANK_LOOP_S)
	var fade := int(RATE * 0.04)
	var s := PackedFloat32Array()
	s.resize(n)
	var hash_bp := AudioDsp.bp(RATE, 2400.0, 1.2)
	var chuff_bp := AudioDsp.bp(RATE, 520.0, 0.9)
	var body := AudioDsp.lp(RATE, 3000.0)
	var clunk := AudioDsp.reso(RATE, 95.0, 38.0)
	var teeth_a := AudioDsp.reso(RATE, 2900.0, 260.0)
	var teeth_b := AudioDsp.reso(RATE, 4300.0, 340.0)
	var cough := Puff.new(RATE, 84.0, 30.0, 700.0, 45.0, rng)
	# Each cylinder comes up on compression a little differently.
	var weights: Array[float] = []
	for c in 4:
		weights.append(rng.randf_range(0.7, 1.15))
	var phase := 0.0
	var stroke := 0.0
	var stroke_no := 0
	var stroke_hz := CHUGS_FIRST
	var weight := weights[0]
	var tooth := 0.0
	for i in n:
		var t := float(i) / RATE
		var hit := 0.0
		stroke += stroke_hz / RATE
		if stroke >= 1.0:
			stroke -= 1.0
			stroke_no += 1
			# the battery recovers over the first few strokes, then it only wanders
			var settled := minf(stroke_no / 4.0, 1.0)
			stroke_hz = lerpf(CHUGS_FIRST, CHUGS, settled) * rng.randf_range(0.86, 1.14)
			weight = weights[stroke_no % 4] * rng.randf_range(0.9, 1.1)
			if stroke_no > 3 and rng.randf() < 0.22:
				hit = rng.randf_range(0.25, 0.5)  # a cylinder half fires
		# comp: high as the piston comes up, gone once it is over the top
		var comp := pow(sin(stroke * PI), 2.0) * weight
		# the motor spins up as the pinion goes in, and never quite holds its speed
		var spin := (1.0 - exp(-t * 28.0)) * (1.0 - 0.24 * comp)
		phase += WHINE_HZ * spin / RATE
		var saw := fposmod(phase, 1.0) * 2.0 - 1.0
		var whine := saw * 0.5 + sin(phase * TAU * 2.0) * 0.25 + sin(phase * TAU * 0.5) * 0.2 + sin(phase * TAU * 6.3) * 0.07
		var thump := sin(TAU * 62.0 * stroke / stroke_hz) * exp(-stroke * 9.0) * 0.9 * weight
		var noise := rng.randf_range(-1.0, 1.0)
		var hiss := hash_bp.step(noise) * 0.25
		var chuff := chuff_bp.step(noise) * exp(-stroke * 6.0) * 0.5 * weight
		# the solenoid throws the pinion in: one clunk, then teeth ratcheting
		# into mesh, faster and fainter, for a tenth of a second
		var engage := clunk.step(1.0 if i == 0 else 0.0) * 1.4
		if t < 0.11:
			tooth += lerpf(70.0, 260.0, t / 0.11) / RATE
			var click := 0.0
			if tooth >= 1.0:
				tooth -= 1.0
				click = 1.0 - t / 0.11
			engage += (teeth_a.step(click) + teeth_b.step(click) * 0.7) * 0.8
		var turning := minf(t * 40.0, 1.0)
		s[i] = body.step(whine * (0.55 + 0.45 * comp) * turning + hiss * (0.4 + 0.6 * comp) * turning) \
				+ thump + chuff + engage + cough.step(hit) * 0.8
	# The tail runs into the sound just ahead of the loop point, so the jump
	# back is seamless and the first pass through that point is untouched.
	for i in fade:
		var k := float(i) / fade
		s[n - fade + i] = s[n - fade + i] * (1.0 - k) + s[loop_at - fade + i] * k
	var wav := AudioDsp.to_wav(AudioDsp.normalise(s, 0.7), RATE, true)
	wav.loop_begin = loop_at
	return wav

## The catch: the starter winds down, the first strokes fire unevenly.
static func make_catch(seed_value: int) -> AudioStream:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := int(RATE * CATCH_S)
	var s := PackedFloat32Array()
	s.resize(n)
	var fire := Puff.new(RATE, 96.0, 26.0, 900.0, 34.0, rng)
	var breath := AudioDsp.bp(RATE, 420.0, 0.8)
	var body := AudioDsp.lp(RATE, 2600.0)
	# When each stroke fires: quickening from cranking speed, one of the early
	# ones missing (the stumble), each a different weight.
	var hits := {}
	var t_hit := 0.0
	var gap := 1.0 / CHUGS
	var missed := 1 + rng.randi() % 2
	for k in 9:
		if k != missed:
			hits[int(t_hit * RATE)] = rng.randf_range(0.55, 1.0) * (1.0 - k / 11.0)
		gap = maxf(gap * rng.randf_range(0.66, 0.84), 1.0 / IDLE_FIRE_HZ)
		t_hit += gap * rng.randf_range(0.9, 1.1)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		# the starter, let go: its whine falls away in a sixth of a second
		var wind := exp(-t * 22.0)
		phase += WHINE_HZ * (0.3 + 0.7 * wind) / RATE
		var whine := (fposmod(phase, 1.0) * 2.0 - 1.0) * 0.3 * wind
		var noise := rng.randf_range(-1.0, 1.0)
		# the first breath through the exhaust as the revs flare
		var swell := sin(clampf(t / 0.45, 0.0, 1.0) * PI)
		breath.set_bp(RATE, lerpf(320.0, 760.0, clampf(t / 0.4, 0.0, 1.0)), 0.8)
		var out := body.step(whine) + fire.step(hits.get(i, 0.0)) + breath.step(noise) * swell * 0.22
		s[i] = out * minf((CATCH_S - t) / 0.2, 1.0)
	return AudioDsp.to_wav(AudioDsp.normalise(s, 0.7), RATE, false)

## The shutdown: firing strokes slowing to nothing, a burble, the last rock.
static func make_shutdown(seed_value: int) -> AudioStream:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := int(RATE * STOP_S)
	var s := PackedFloat32Array()
	s.resize(n)
	var fire := Puff.new(RATE, 110.0, 34.0, 1100.0, 60.0, rng)
	var burble := Puff.new(RATE, 68.0, 16.0, 1400.0, 26.0, rng)
	var rock := AudioDsp.reso(RATE, 44.0, 11.0)
	var tick := AudioDsp.reso(RATE, 3300.0, 420.0)
	var spin_bp := AudioDsp.bp(RATE, 600.0, 0.7)
	# two or three loose pops from the exhaust as the last charge goes through
	var pops := {}
	var t_pop := rng.randf_range(0.36, 0.44)
	for k in 2 + rng.randi() % 2:
		pops[int(t_pop * RATE)] = rng.randf_range(0.5, 0.9) * (1.0 - k * 0.22)
		t_pop += rng.randf_range(0.09, 0.17)
	var rock_at := int((t_pop + 0.05) * RATE)
	var tick_at := int(minf(t_pop + rng.randf_range(0.2, 0.3), STOP_S - 0.08) * RATE)
	var beat := 0.0
	for i in n:
		var t := float(i) / RATE
		# the revs fall away: strokes further apart and weaker, gone by 0.55 s
		var run := maxf(1.0 - t / 0.55, 0.0)
		var hit := 0.0
		if run > 0.0:
			beat += IDLE_FIRE_HZ * (0.18 + 0.82 * run * run) / RATE
			if beat >= 1.0:
				beat -= 1.0
				hit = (0.35 + 0.65 * run) * rng.randf_range(0.8, 1.1)
		var noise := rng.randf_range(-1.0, 1.0)
		# belts and fan running down
		spin_bp.set_bp(RATE, 250.0 + 650.0 * run, 0.7)
		var out := fire.step(hit) + burble.step(pops.get(i, 0.0)) * 1.1 + spin_bp.step(noise) * run * 0.2
		out += rock.step(1.0 if i == rock_at else 0.0) * 0.9
		out += tick.step(1.0 if i == tick_at else 0.0) * 0.12
		s[i] = out * minf((STOP_S - t) / 0.1, 1.0)
	return AudioDsp.to_wav(AudioDsp.normalise(s, 0.7), RATE, false)
