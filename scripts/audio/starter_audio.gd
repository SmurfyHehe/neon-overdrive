extends Node

# The starter motor and the key (2026-10-10, Roy: "i want you to need to
# actually start the car"). A run starts with the engine off and X cranks it;
# X on a running, standing car switches it off again (PlayerCar.key_off).
#
# Second pass 2026-10-11 (Roy on playtest build 3: "i dont like the starter
# turning the car on, sounds weak"): a heavier motor and grind with its weight
# at 120-400 Hz (a laptop speaker has nothing below that), hard compression
# chugs, coughs before the catch, and every engine its own starter.
#
# Four sounds, all synthesised here (no files, nothing to license) and kept as
# plain samples, so playing them costs nothing per frame:
#
#  crank     the solenoid clunk and the pinion ratcheting into the ring gear,
#            then the motor growling and sagging on every compression stroke
#            ("ruh-RUH-ruh-ruh"), each stroke a thump and a huff of air. The
#            head plays once and the tail loops, so it lasts as long as the
#            crank does (PlayerCar.crank_hold: longer on a cold engine).
#  cough     a cylinder fires and the engine does not follow: one just before
#            the catch, two on a cold engine (cough_times). The starter dips
#            under each.
#  catch     the starter thrown out and winding down, and the first firing
#            strokes: heavy uneven thumps with one missing (the stumble) and a
#            breath of exhaust. EngineAudio's own voice comes in under it on
#            the rev blip (PlayerCar.START_FLARE) and settles to the fast idle.
#  shutdown  the last firing strokes slowing to nothing, two or three loose
#            exhaust burbles, the engine rocking to a stop on its mounts.
#
# Per engine, from the car's engine_voice and nothing else (recipe()):
#  cylinders   how fast the strokes come (chug_rate), how low the motor sits
#              and how far it sags; a big engine also turns over for longer
#              (pace, which PlayerCar divides the crank time by)
#  firing      uneven firing is an uneven crank: the flat four with unequal
#              headers goes da-dum da-dum
#  cyl_amps    the bank weights: a crossplane V8 cranks lumpy, heavy and light
#              strokes in its L R R L R L L R order
#  cyl_spread  a loose engine chatters: valve gear ticking on every stroke
#              (the air-cooled beater most of all)
#  body_hz     where the thumps and the first firing strokes ring
#
# Each has a few takes and every play picks one and nudges its pitch, so two
# starts in a row are not the same. The starter is in the cabin with you: it
# is VIEW_CHASE_DB quieter from the chase view than from the driver's seat.
#
# `level`, `cranks`, `coughs`, `catches`, `shutdowns` are for tests (silent
# driver). render_start() is the whole start as samples, for tests and the
# listen pack.
#
# No class_name on purpose: preload it, so no class cache refresh is needed.

const RATE := 22050
const PATH := "res://scripts/audio/starter_audio.gd"
const CRANK_TAKES := 2
const COUGH_TAKES := 2
const CATCH_TAKES := 3
const STOP_TAKES := 2
## The crank take: the head (engage, slow first strokes) plays once, then
## [CRANK_LOOP_S, CRANK_S) repeats for as long as the starter is held.
const CRANK_S := 2.4
const CRANK_LOOP_S := 1.0
const COUGH_S := 0.34
const CATCH_S := 0.9
const STOP_S := 1.15
## The first, slowest stroke comes at this share of the engine's chug_rate.
const FIRST_STROKE := 0.6
## Firing strokes a second at idle, where the shutdown begins (a four at 850).
const IDLE_FIRE_HZ := 28.0
const GAIN := 0.62
const COUGH_GAIN := 0.6
const CATCH_GAIN := 0.75
const STOP_GAIN := 0.55
## The starter under a cough: the engine kicks ahead of it for a moment.
const COUGH_DUCK := 0.5
## A cough comes this long before the catch, and the one before it this much
## earlier; none sooner than COUGH_FIRST_S into the crank.
const COUGH_LEAD_S := 0.24
const COUGH_GAP_S := 0.3
const COUGH_FIRST_S := 0.25
## The starter from the chase view, against the driver's seat (dB), and what
## it takes to undo the Engine bus's own cabin cut (PerspectiveAudio).
const VIEW_CHASE_DB := -6.5
const VIEW_COCKPIT_DB := 2.0
const ATTACK := 60.0
const RELEASE := 14.0
## Each play is this much off pitch, either way.
const PITCH_SPREAD := 0.035

var level := 0.0
## How many times the starter has begun to turn, a cylinder has coughed, the
## engine has caught off it, and the key has switched it off (tests).
var cranks := 0
var coughs := 0
var catches := 0
var shutdowns := 0
var _player: PlayerCar
var _car_audio: CarAudio
var _crank: AudioStreamPlayer
var _cough: AudioStreamPlayer
var _catch: AudioStreamPlayer
var _stop: AudioStreamPlayer
var _crank_takes: Array[AudioStream] = []
var _cough_takes: Array[AudioStream] = []
var _catch_takes: Array[AudioStream] = []
var _stop_takes: Array[AudioStream] = []
## Seconds of the cough, the catch and the shutdown still to play, on the
## game's clock (a headless run's audio clock is not the game's).
var _cough_left := 0.0
var _catch_left := 0.0
var _stop_left := 0.0
var _crank_t := 0.0
var _cough_at := PackedFloat32Array()
var _cough_i := 0
var _was_cranking := false
var _key_offs := 0
var _pace := 1.0
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	name = "StarterAudio"

## How fast an engine of this many cylinders turns over against a four: under
## 1 is slower (PlayerCar.crank_hold is divided by it). Also the shutdown's
## playback speed.
static func pace(cylinders: int) -> float:
	if cylinders <= 3:
		return 1.24
	if cylinders <= 4:
		return 1.06
	if cylinders <= 6:
		return 0.94
	return 0.82

## Compression strokes a second once the starter is up to speed: more
## cylinders, more strokes a turn, though the big engine turns slower.
static func chug_rate(cylinders: int) -> float:
	if cylinders <= 3:
		return 7.0
	if cylinders <= 4:
		return 7.6
	if cylinders <= 6:
		return 8.6
	return 9.6

## How long a key start turns this engine over (`cold` 0 warm .. 1 cold),
## before PlayerCar's own give or take.
static func hold_for(cylinders: int, cold: float) -> float:
	return lerpf(PlayerCar.CRANK_WARM_S, PlayerCar.CRANK_COLD_S, clampf(cold, 0.0, 1.0)) / pace(cylinders)

## When the coughs come, in seconds into a crank of `hold` seconds.
static func cough_times(hold: float, cold: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var last := hold - COUGH_LEAD_S
	if cold > 0.5 and last - COUGH_GAP_S >= COUGH_FIRST_S:
		out.append(last - COUGH_GAP_S)
	if last >= COUGH_FIRST_S:
		out.append(last)
	return out

## The starter's character for one engine_voice (see the top of the file).
static func recipe(voice: Dictionary) -> Dictionary:
	var n := clampi(int(voice.get("cylinders", 4)), 1, 16)
	var firing := PackedFloat32Array(voice.get("firing", []))
	if firing.size() != n:
		firing = EngineVoice.even_firing(n)
	var amps := PackedFloat32Array(voice.get("cyl_amps", []))
	var gaps := PackedFloat32Array()
	var weights := PackedFloat32Array()
	for i in n:
		# the gap to the next stroke against an even engine's, overdrawn: at
		# cranking speed the ear follows every stroke
		var g := fposmod(firing[(i + 1) % n] - firing[i], 1.0) * n
		gaps.append(clampf(1.0 + (g - 1.0) * 1.6, 0.5, 1.6) if g > 0.0 else 1.0)
		weights.append(pow(clampf(amps[i], 0.3, 1.2), 3.0) if amps.size() == n else 1.0)
	var body := clampf(float(voice.get("body_hz", 120.0)), 70.0, 220.0)
	var chatter := smoothstep(0.1, 0.26, float(voice.get("cyl_spread", 0.1)))
	return {
		"cylinders": n, "gaps": gaps, "weights": weights,
		"chugs": chug_rate(n),
		"whine_hz": clampf(430.0 - 17.0 * n, 250.0, 400.0),
		"sag": clampf(0.26 + 0.02 * n, 0.3, 0.44),
		"chug_hz": clampf(body * 0.9, 85.0, 170.0),
		"body_hz": body,
		# a deep engine's thumps sit under what a small speaker plays: lean
		# on their octave instead (0 at 125 Hz and up .. 1 at 85 and under)
		"lift": clampf((125.0 - body * 0.9) / 40.0, 0.0, 1.0),
		"chatter": chatter,
		"key": "%dc%08x" % [n, [gaps, weights, body, chatter].hash() & 0xffffffff],
	}

func _ready() -> void:
	_player = get_parent() as PlayerCar
	if _player == null:
		push_error("StarterAudio must be a child of a PlayerCar")
		set_physics_process(false)
		return
	_rng.randomize()
	_pace = _player.crank_pace()
	_key_offs = _player.key_offs
	# Booting into the garage the engine is off until the player goes out:
	# the takes (on a cold cache still being made, issue #524) are collected on
	# the first start or stop instead of holding up the garage.
	if not CarAudio.garage_boot():
		_collect_takes()
	_crank = _voice("CrankAudio")
	_cough = _voice("CoughAudio")
	_catch = _voice("CatchAudio")
	_stop = _voice("ShutdownAudio")

## Every take for this car: [set, cache layer, maker].
static func take_list(spec: Dictionary) -> Array:
	var rec := recipe(spec.get("engine_voice", {}) as Dictionary)
	var key: String = rec.key
	var out := []
	for i in CRANK_TAKES:
		out.append(["crank", "crank%d_%s" % [i, key], make_crank.bind(crank_seed(i), rec)])
	for i in COUGH_TAKES:
		out.append(["cough", "cough%d_%s" % [i, key], make_cough.bind(cough_seed(i), rec)])
	for i in CATCH_TAKES:
		out.append(["catch", "catch%d_%s" % [i, key], make_catch.bind(catch_seed(i), rec)])
	for i in STOP_TAKES:
		out.append(["stop", "stop%d" % i, make_shutdown.bind(2203 + i * 17)])
	return out

## Starts making this car's takes off the main thread (issue #524). On a
## garage boot nothing waits for them (see _ready): AudioDsp's background lane.
static func prefetch(spec: Dictionary) -> void:
	var urgent := not CarAudio.garage_boot()
	for t in take_list(spec):
		AudioDsp.prefetch(PATH, t[1], t[2], urgent)

func _collect_takes() -> void:
	if not _crank_takes.is_empty():
		return
	for t in take_list(_player.spec):
		var s := AudioDsp.cached(PATH, t[1], t[2])
		match String(t[0]):
			"crank": _crank_takes.append(s)
			"cough": _cough_takes.append(s)
			"catch": _catch_takes.append(s)
			_: _stop_takes.append(s)

static func crank_seed(i: int) -> int:
	return 9127 + i * 31

static func cough_seed(i: int) -> int:
	return 5501 + i * 43

static func catch_seed(i: int) -> int:
	return 417 + i * 53

func _voice(voice_name: String) -> AudioStreamPlayer:
	var a := AudioStreamPlayer.new()
	a.name = voice_name
	a.bus = &"Engine"
	add_child(a)
	return a

## Plays one of `takes`, a little off pitch (times `pitch`); returns how long
## it lasts.
func _play(a: AudioStreamPlayer, takes: Array[AudioStream], gain: float, pitch := 1.0) -> float:
	_collect_takes()
	a.stream = takes[_rng.randi() % takes.size()]
	a.pitch_scale = pitch * _rng.randf_range(1.0 - PITCH_SPREAD, 1.0 + PITCH_SPREAD)
	a.volume_db = linear_to_db(gain)
	a.play()
	return a.stream.get_length() / a.pitch_scale

## The starter's gain for the view: `cabin` 0 chase .. 1 cockpit.
static func view_gain(cabin: float) -> float:
	return db_to_linear(lerpf(VIEW_CHASE_DB, VIEW_COCKPIT_DB, clampf(cabin, 0.0, 1.0)))

func _cabin() -> float:
	if _car_audio == null:
		for c in _player.get_children():
			if c is CarAudio:
				_car_audio = c
	return _car_audio.cabin if _car_audio != null else 0.0

func _physics_process(delta: float) -> void:
	var cranking := _player.is_cranking()
	if cranking and not _was_cranking:
		cranks += 1
		level = 0.0
		_cough.stop()
		_catch.stop()
		_stop.stop()
		_cough_left = 0.0
		_catch_left = 0.0
		_stop_left = 0.0
		_crank_t = 0.0
		_cough_at = cough_times(_player.crank_hold, _player.crank_cold)
		_cough_i = 0
		_play(_crank, _crank_takes, 0.001)
	elif _was_cranking and not cranking and _player.engine_running:
		catches += 1
		_catch_left = _play(_catch, _catch_takes, CATCH_GAIN)
	if cranking:
		_crank_t += delta
		if _cough_i < _cough_at.size() and _crank_t >= _cough_at[_cough_i]:
			_cough_i += 1
			coughs += 1
			_cough_left = _play(_cough, _cough_takes, COUGH_GAIN)
	_was_cranking = cranking
	if _player.key_offs != _key_offs:
		_key_offs = _player.key_offs
		shutdowns += 1
		_cough.stop()
		_catch.stop()
		_cough_left = 0.0
		_catch_left = 0.0
		_stop_left = _play(_stop, _stop_takes, STOP_GAIN, _pace)
	_cough_left = maxf(_cough_left - delta, 0.0)
	_catch_left = maxf(_catch_left - delta, 0.0)
	_stop_left = maxf(_stop_left - delta, 0.0)
	# The crank fades out over a few hundredths as the starter lets go, and
	# dips while a cylinder coughs.
	var target := 0.0
	if cranking:
		target = COUGH_DUCK if _cough_left > 0.0 else 1.0
	level = move_toward(level, target, delta * (ATTACK if target > level else RELEASE))
	if level > 0.001:
		_crank.volume_db = linear_to_db(level * GAIN * view_gain(_cabin()))
	elif _crank.playing and not cranking:
		_crank.stop()

## Which of them are sounding (tests): never the crank with the shutdown.
func sounding() -> PackedStringArray:
	var out := PackedStringArray()
	if _crank.playing:
		out.append("crank")
	if _cough_left > 0.0:
		out.append("cough")
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

## The crank: engage, then the motor growling and sagging on the strokes.
static func make_crank(seed_value: int, rec: Dictionary) -> AudioStream:
	var wav := AudioDsp.to_wav(crank_samples(seed_value, rec), RATE, true)
	wav.loop_begin = int(RATE * CRANK_LOOP_S)
	return wav

static func make_cough(seed_value: int, rec: Dictionary) -> AudioStream:
	return AudioDsp.to_wav(cough_samples(seed_value, rec), RATE, false)

static func make_catch(seed_value: int, rec: Dictionary) -> AudioStream:
	return AudioDsp.to_wav(catch_samples(seed_value, rec), RATE, false)

## Squashes the peaks (the weight of a sound is in its body, not its spikes)
## and sets the peak.
static func _dense(s: PackedFloat32Array, drive: float, peak: float) -> PackedFloat32Array:
	s = AudioDsp.normalise(s, 1.0)
	for i in s.size():
		s[i] = tanh(s[i] * drive)
	return AudioDsp.normalise(s, peak)

static func crank_samples(seed_value: int, rec: Dictionary) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := int(RATE * CRANK_S)
	var loop_at := int(RATE * CRANK_LOOP_S)
	var fade := int(RATE * 0.04)
	var s := PackedFloat32Array()
	s.resize(n)
	var n_cyl: int = rec.cylinders
	var gaps: PackedFloat32Array = rec.gaps
	var chugs: float = rec.chugs
	var first := chugs * FIRST_STROKE
	var whine_hz: float = rec.whine_hz
	var sag: float = rec.sag
	var chug_hz: float = rec.chug_hz
	var chatter: float = rec.chatter
	var lift: float = rec.lift
	# the motor: its weight at 200-350 Hz, a harder edge near 900
	var motor_lo := AudioDsp.bp(RATE, 270.0, 0.8)
	var motor_mid := AudioDsp.bp(RATE, 900.0, 1.0)
	var grind_bp := AudioDsp.bp(RATE, 1500.0, 1.3)
	var huff_bp := AudioDsp.bp(RATE, 330.0, 0.8)
	var thump_lo := AudioDsp.reso(RATE, chug_hz, 22.0)
	var thump_hi := AudioDsp.reso(RATE, chug_hz * 2.04, 32.0)
	var clunk_a := AudioDsp.reso(RATE, 125.0, 30.0)
	var clunk_b := AudioDsp.reso(RATE, 310.0, 55.0)
	var teeth_a := AudioDsp.reso(RATE, 2900.0, 260.0)
	var teeth_b := AudioDsp.reso(RATE, 4300.0, 340.0)
	var tick := AudioDsp.reso(RATE, 3100.0, 520.0)
	var cough := Puff.new(RATE, rec.body_hz, 30.0, 700.0, 45.0, rng)
	# Each cylinder comes up on compression a little differently, on top of
	# the engine's own heavy and light strokes.
	var cyl_w: Array[float] = []
	for c in n_cyl:
		cyl_w.append(float(rec.weights[c]) * rng.randf_range(0.8, 1.12))
	var phase := 0.0
	var stroke := 0.0
	var stroke_no := 0
	var stroke_hz := first / gaps[0]
	var weight := cyl_w[0]
	var half := false
	var tooth := 0.0
	for i in n:
		var t := float(i) / RATE
		var hit := 0.0
		var kick := weight if i == 0 else 0.0
		var tk := 0.0
		stroke += stroke_hz / RATE
		if stroke >= 1.0:
			stroke -= 1.0
			stroke_no += 1
			half = false
			var idx := stroke_no % n_cyl
			# the battery recovers over the first few strokes, then it only wanders
			var settled := minf(stroke_no / 4.0, 1.0)
			stroke_hz = lerpf(first, chugs, settled) / gaps[idx] * rng.randf_range(0.9, 1.1)
			weight = cyl_w[idx] * rng.randf_range(0.9, 1.1)
			kick = weight
			tk = rng.randf_range(0.5, 1.0)
			if stroke_no > 3 and rng.randf() < 0.12:
				hit = rng.randf_range(0.2, 0.4)  # a cylinder half fires
		elif not half and stroke >= 0.5:
			half = true
			tk = rng.randf_range(0.3, 0.8)
		# comp: high as the piston comes up, gone once it is over the top
		var comp := pow(sin(stroke * PI), 2.0) * weight
		# the motor spins up as the pinion goes in, and never quite holds its speed
		var spin := (1.0 - exp(-t * 26.0)) * (1.0 - sag * minf(comp, 1.1))
		phase += whine_hz * spin / RATE
		var saw := fposmod(phase, 1.0) * 2.0 - 1.0
		var sub := fposmod(phase * 0.5, 1.0) * 2.0 - 1.0
		var growl := tanh((saw * 0.5 + sub * 0.5 + sin(phase * TAU * 2.0) * 0.2) * 1.8)
		var noise := rng.randf_range(-1.0, 1.0)
		# the ring gear: noise let through tooth by tooth
		var teeth := grind_bp.step(noise * (1.0 if saw > 0.0 else 0.2)) * 1.6
		var motor := motor_lo.step(growl) * 1.2 + motor_mid.step(growl) * 0.5 + growl * 0.2 + teeth
		var turning := minf(t * 40.0, 1.0)
		var thump := thump_lo.step(kick) * (1.0 - 0.4 * lift) + thump_hi.step(kick) * (0.7 + 1.1 * lift)
		var huff := huff_bp.step(noise) * comp * 2.6
		# the solenoid throws the pinion in: one clunk, then teeth ratcheting
		# into mesh, faster and fainter, for a tenth of a second
		var c0 := 1.0 if i == 0 else 0.0
		var engage := (clunk_a.step(c0) + clunk_b.step(c0) * 0.8) * 1.5
		if t < 0.11:
			tooth += lerpf(70.0, 260.0, t / 0.11) / RATE
			var click := 0.0
			if tooth >= 1.0:
				tooth -= 1.0
				click = 1.0 - t / 0.11
			engage += (teeth_a.step(click) + teeth_b.step(click) * 0.7) * 0.8
		s[i] = motor * (0.6 + 0.4 * comp) * turning * 0.8 + thump * 1.1 * turning + huff * turning \
				+ engage + tick.step(tk) * chatter * 0.45 + cough.step(hit) * 0.8
	# The tail runs into the sound just ahead of the loop point, so the jump
	# back is seamless and the first pass through that point is untouched.
	for i in fade:
		var k := float(i) / fade
		s[n - fade + i] = s[n - fade + i] * (1.0 - k) + s[loop_at - fade + i] * k
	return _dense(s, 1.5, 0.8)

## A cough: one cylinder fires, a second half follows, the engine falls back.
static func cough_samples(seed_value: int, rec: Dictionary) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := int(RATE * COUGH_S)
	var s := PackedFloat32Array()
	s.resize(n)
	var body: float = rec.body_hz
	var fire := Puff.new(RATE, body, 20.0, 800.0, 30.0, rng)
	var bark := Puff.new(RATE, body * 2.1, 30.0, 1500.0, 50.0, rng)
	var chuff := AudioDsp.bp(RATE, 430.0, 0.8)
	var second := int(rng.randf_range(0.065, 0.1) * RATE)
	var second_amp := rng.randf_range(0.35, 0.6)
	var lift: float = rec.lift
	for i in n:
		var t := float(i) / RATE
		var hit := 1.0 if i == 0 else (second_amp if i == second else 0.0)
		var out := fire.step(hit) * (1.0 - 0.4 * lift) + bark.step(hit) * (0.7 + 1.1 * lift) + chuff.step(rng.randf_range(-1.0, 1.0)) * exp(-t * 14.0) * 2.2
		s[i] = out * minf((COUGH_S - t) / 0.06, 1.0)
	return _dense(s, 1.4, 0.8)

## The catch: the starter winds down, the first strokes fire unevenly.
static func catch_samples(seed_value: int, rec: Dictionary) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := int(RATE * CATCH_S)
	var s := PackedFloat32Array()
	s.resize(n)
	var n_cyl: int = rec.cylinders
	var body: float = rec.body_hz
	var fire := Puff.new(RATE, body, 24.0, 900.0, 34.0, rng)
	var bark := Puff.new(RATE, body * 2.1, 34.0, 1600.0, 55.0, rng)
	var breath := AudioDsp.bp(RATE, 420.0, 0.8)
	var motor_lo := AudioDsp.bp(RATE, 270.0, 0.8)
	var zing := AudioDsp.reso(RATE, 2300.0, 60.0)
	var tick := AudioDsp.reso(RATE, 3100.0, 520.0)
	# When each stroke fires: quickening from cranking speed towards the blip,
	# one of the early ones missing (the stumble), the engine's own heavy and
	# light strokes, fading as the engine voice takes over.
	var hits := {}
	var t_hit := 0.0
	var gap: float = 1.0 / rec.chugs
	var fastest: float = 1.0 / (rec.chugs * 3.4)
	var missed := 1 + rng.randi() % 2
	var k := 0
	while t_hit < CATCH_S - 0.15:
		if k != missed:
			hits[int(t_hit * RATE)] = rng.randf_range(0.7, 1.0) * float(rec.weights[k % n_cyl]) * maxf(1.0 - t_hit / 0.8, 0.15)
		gap = maxf(gap * rng.randf_range(0.7, 0.86), fastest)
		t_hit += gap * float(rec.gaps[k % n_cyl]) * rng.randf_range(0.92, 1.08)
		k += 1
	var zing_at := int(0.03 * RATE)
	var lift: float = rec.lift
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		# the starter, thrown out: its growl falls away in a fifth of a second
		var wind := exp(-t * 17.0)
		phase += float(rec.whine_hz) * (0.25 + 0.75 * wind) / RATE
		var saw := fposmod(phase, 1.0) * 2.0 - 1.0
		var growl := motor_lo.step(tanh((saw + (fposmod(phase * 0.5, 1.0) * 2.0 - 1.0)) * 0.9)) * wind
		var noise := rng.randf_range(-1.0, 1.0)
		# the first breath through the exhaust as the revs flare
		var swell := sin(clampf(t / 0.5, 0.0, 1.0) * PI)
		breath.set_bp(RATE, lerpf(320.0, 820.0, clampf(t / 0.35, 0.0, 1.0)), 0.8)
		var hit: float = hits.get(i, 0.0)
		var out := growl * 0.9 + fire.step(hit) * (1.1 - 0.45 * lift) + bark.step(hit) * (0.7 + 1.1 * lift) + breath.step(noise) * swell * 0.9
		out += zing.step(1.0 if i == zing_at else 0.0) * 0.25 + tick.step(hit) * float(rec.chatter) * 0.3
		s[i] = out * minf((CATCH_S - t) / 0.22, 1.0)
	return _dense(s, 1.5, 0.8)

## The whole start as the game plays it from the driver's seat, starter only
## (the engine's own voice is EngineAudio's): the crank for hold_for(cold)
## seconds with its coughs, then the catch. Tests and the listen pack.
static func render_start(rec: Dictionary, cold: float, take := 0) -> PackedFloat32Array:
	var hold := hold_for(rec.cylinders, cold)
	var crank := crank_samples(crank_seed(take % CRANK_TAKES), rec)
	var catch_take := catch_samples(catch_seed(take % CATCH_TAKES), rec)
	var at := cough_times(hold, cold)
	var cough_takes: Array[PackedFloat32Array] = []
	for i in at.size():
		cough_takes.append(cough_samples(cough_seed((take + i) % COUGH_TAKES), rec))
	var loop_at := int(RATE * CRANK_LOOP_S)
	var hold_n := int(hold * RATE)
	var n := hold_n + catch_take.size()
	var s := PackedFloat32Array()
	s.resize(n)
	var lvl := 0.0
	for i in n:
		var t := float(i) / RATE
		var coughing := false
		var out := 0.0
		for c in at.size():
			var ci := i - int(at[c] * RATE)
			if ci >= 0 and ci < cough_takes[c].size():
				coughing = true
				out += cough_takes[c][ci] * COUGH_GAIN
		var target := 0.0
		if i < hold_n:
			target = COUGH_DUCK if coughing else 1.0
		lvl = move_toward(lvl, target, (ATTACK if target > lvl else RELEASE) / RATE)
		var ci2 := i if i < crank.size() else loop_at + (i - loop_at) % (crank.size() - loop_at)
		out += crank[ci2] * lvl * GAIN
		if i >= hold_n:
			out += catch_take[i - hold_n] * CATCH_GAIN
		s[i] = out
	return s

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
