class_name TrafficHorns
extends RefCounted

# Car horns (traffic near-miss fix step 5, 2026-10-10; Roy: drivers honk when
# cut off, and different cars honk differently. Second pass 2026-10-11 for the
# player's horn on J: "make GOOD horn sounds"). Six horns, synthesized here
# into AudioStreamWAVs the way the engine and menu sounds are: no bought or
# credited recordings.
#
#   beep      one small disc, 500 Hz: kei cars and small hatches
#   two_tone  the ordinary disc pair, 335 + 400 Hz: sedans, wagons, commuters,
#             and any car this table does not know
#   blare     lower and thicker, 300 + 360 Hz: pickups, crossovers, trucks
#   sharp     a trumpet pair, 410 + 510 Hz, brighter: coupes, tuner and sports
#             cars
#   sour      a disc pair on a weak battery: 13% flat, the high horn comes and
#             goes, the buzz is ragged, the baked takes cut out early: old
#             beaters, and any car that is badly damaged
#   air       three air trumpets, 185 + 233 + 277 Hz, with a breathy start and
#             a falling tail: buses and big trucks (no car uses it yet)
#
# What a horn is: an electromagnet buzzing a steel disc, a low and a high one
# sounding together. So each tone is a band-limited pulse (not a sine), the
# pulse width jitters and every other buzz is a little weaker (the roughness),
# and the mix goes through two or three fixed band-pass formants (the disc's
# or the trumpet's brass colour) and a soft clipper. The onset is hard with a
# small click, the pitch sags a little over the first half second and the level
# wobbles slowly, so a held horn is not a test tone.
#
# Three takes per horn:
#   short  SHORT_S, a tap (traffic: a close pass or a mild cut)
#   long   LONG_S, leaning on it (traffic)
#   hold   the player's: HOLD_HEAD_S of onset, then HOLD_LOOP_S that loops for
#          as long as the key is down. Every tone, wobble and jitter in the
#          loop repeats exactly every HOLD_LOOP_S, so the seam is silent.
#
# Built once, off the main thread (warm()), a few seconds in all. Until that
# finishes stream() returns null and a honk is silent. TrafficManager plays
# them on two shared AudioStreamPlayer3Ds on the Traffic bus; the player's car
# has its own (PlayerHorn).

const RATE := 22050
const SHORT_S := 0.4
const LONG_S := 1.0
const HOLD_HEAD_S := 0.6
const HOLD_LOOP_S := 2.0
const NAMES: Array[String] = ["beep", "two_tone", "blare", "air", "sharp", "sour"]
const DEFAULT := "two_tone"
## The pitch starts this share high and settles over SAG_S.
const SAG_S := 0.5

## Car kind (NpcCarBuilder.KINDS key) -> horn. Anything else goes by WORDS,
## then DEFAULT.
const BY_KIND := {
	"n1_commuter": "two_tone", "n2_cityhatch": "beep", "n3_pickup": "blare",
	"p0_beater": "sour", "p1_coupe": "sharp", "p2_hothatch": "beep", "p3_tuner": "sharp",
	"p4_kei": "beep", "p5_muscle": "blare", "p6_crossover": "blare", "p17_work_pickup": "blare",
	"p8_driftcoupe": "sharp", "m1_monster": "blare", "l1_lowrider": "two_tone",
	"c1_patrol": "two_tone", "c2_patrolsuv": "blare", "c3_interceptor": "sharp",
}
## For a kind that is not in BY_KIND yet: the first word found in its name.
const WORDS := [
	["beater", "sour"], ["bug", "sour"], ["kei", "beep"], ["hatch", "beep"],
	["coupe", "sharp"], ["tuner", "sharp"], ["drift", "sharp"], ["mid", "sharp"], ["gt", "sharp"],
	["pickup", "blare"], ["crossover", "blare"], ["truck", "blare"], ["suv", "blare"],
]

## Per horn:
##   hz        the tones (whole Hz, so each fits the loop exactly)
##   duty      pulse width, 0.5 = square; narrower is thinner and brighter
##   formants  [centre Hz, Q, gain] band-passes the buzz rings through
##   dry, lp   share of the buzz itself under the formants, and its low-pass
##   drive     into the soft clipper
##   rough     pulse-width jitter and the weaker every-other buzz
##   sag       how far above its pitch the horn starts
##   attack, release (s), level
## and the odd ones out: breath (air before the note), fall (pitch drop over
## the tail), wobble (pitch waver), waver (the last tone comes and goes), cut
## (share of a baked take after which it dies).
const RECIPES := {
	"beep": {"hz": [500], "duty": 0.3, "formants": [[1500.0, 3.0, 1.0], [3000.0, 3.5, 1.2]],
		"dry": 0.15, "lp": 3000.0, "drive": 1.5, "rough": 0.12, "sag": 0.008,
		"attack": 0.010, "release": 0.05, "level": 0.6},
	"two_tone": {"hz": [335, 400], "duty": 0.35, "formants": [[1200.0, 3.0, 1.0], [2700.0, 3.5, 1.4]],
		"dry": 0.2, "lp": 2500.0, "drive": 1.9, "rough": 0.15, "sag": 0.012,
		"attack": 0.012, "release": 0.06, "level": 0.8},
	"blare": {"hz": [300, 360], "duty": 0.42, "formants": [[1000.0, 2.5, 1.0], [2300.0, 3.0, 1.1]],
		"dry": 0.4, "lp": 2000.0, "drive": 2.6, "rough": 0.2, "sag": 0.014,
		"attack": 0.016, "release": 0.07, "level": 0.85},
	"air": {"hz": [185, 233, 277], "duty": 0.5, "formants": [[600.0, 4.0, 1.0], [1400.0, 5.0, 0.7]],
		"dry": 0.5, "lp": 1600.0, "drive": 1.8, "rough": 0.08, "sag": 0.006,
		"attack": 0.05, "release": 0.25, "level": 0.8, "breath": 0.3, "fall": 0.06},
	"sharp": {"hz": [410, 510], "duty": 0.25, "formants": [[1100.0, 4.0, 0.8], [2400.0, 4.0, 1.0], [3600.0, 4.0, 0.6]],
		"dry": 0.2, "lp": 5000.0, "drive": 2.2, "rough": 0.1, "sag": 0.010,
		"attack": 0.010, "release": 0.05, "level": 0.8},
	"sour": {"hz": [291, 348], "duty": 0.4, "formants": [[1100.0, 3.0, 1.0], [2400.0, 3.0, 0.6]],
		"dry": 0.4, "lp": 2200.0, "drive": 1.6, "rough": 0.5, "sag": 0.02,
		"attack": 0.02, "release": 0.05, "level": 0.5, "wobble": 0.018, "waver": 1.0, "cut": 0.6},
}

static var _streams := {}
static var _lock := Mutex.new()
static var _task := -1
static var _users := 0
static var _first := ""

static func horn_for(kind: String, sour := false) -> String:
	if sour:
		return "sour"
	if BY_KIND.has(kind):
		return String(BY_KIND[kind])
	for w in WORDS:
		if kind.contains(w[0]):
			return w[1]
	return DEFAULT

## Starts building every horn on a worker thread (once). `first` is built
## before the others (the player's own horn). Each caller pairs this with one
## finish().
static func warm(first := "") -> void:
	_users += 1
	if _task >= 0:
		return
	_first = first
	_task = WorkerThreadPool.add_task(_build_all, false, "traffic horns")

## A user is leaving the tree. After the last one: waits for the build if it
## is still running and lets the takes go (nothing static holds a resource at
## exit). The next warm() builds them again.
static func finish() -> void:
	_users = maxi(_users - 1, 0)
	if _task < 0 or _users > 0:
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	_lock.lock()
	_streams.clear()
	_lock.unlock()

static func ready() -> bool:
	_lock.lock()
	var ok := _streams.size() == NAMES.size() * 3
	_lock.unlock()
	return ok

## The take to play, or null while the horns are still being built.
static func stream(horn: String, long: bool) -> AudioStreamWAV:
	return _take(_key(horn, long))

## The player's take: the onset once, then the steady part looping. Null while
## it is still being built.
static func hold_stream(horn: String) -> AudioStreamWAV:
	return _take(horn + "|hold")

static func _take(key: String) -> AudioStreamWAV:
	_lock.lock()
	var s: AudioStreamWAV = _streams.get(key)
	_lock.unlock()
	return s

static func _keep(key: String, wav: AudioStreamWAV) -> void:
	_lock.lock()
	_streams[key] = wav
	_lock.unlock()

static func _key(horn: String, long: bool) -> String:
	return horn + ("|long" if long else "|short")

static func _build_all() -> void:
	var order: Array[String] = NAMES.duplicate()
	if _first in order:
		order.erase(_first)
		order.push_front(_first)
		_keep(_first + "|hold", hold_wav(_first))
	for horn in order:
		for long in [false, true]:
			_keep(_key(horn, long), AudioDsp.to_wav(samples(horn, LONG_S if long else SHORT_S), RATE, false))
	for horn in order:
		if horn != _first:
			_keep(horn + "|hold", hold_wav(horn))

## The player's looping take as a stream.
static func hold_wav(horn: String) -> AudioStreamWAV:
	var s := hold_samples(horn)
	var wav := AudioDsp.to_wav(s, RATE, false)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = int(HOLD_HEAD_S * RATE)
	wav.loop_end = s.size()
	return wav

## One baked take (onset, body, release) as mono samples in -1..1. Pure, so a
## test can look at it.
static func samples(horn: String, secs: float) -> PackedFloat32Array:
	return _render(horn, int(secs * RATE), true)

## The player's take: HOLD_HEAD_S of onset, then HOLD_LOOP_S of the steady
## horn that repeats exactly. No release: the player fades it.
static func hold_samples(horn: String) -> PackedFloat32Array:
	return _render(horn, int((HOLD_HEAD_S + HOLD_LOOP_S) * RATE), false)

## The correction that takes the stair-step out of a pulse edge (polyBLEP):
## `ph` is the phase past the edge, `dt` the phase step per sample.
static func _blep(ph: float, dt: float) -> float:
	if ph < dt:
		var a := ph / dt
		return a + a - a * a - 1.0
	if ph > 1.0 - dt:
		var b := (ph - 1.0) / dt
		return b * b + b + b + 1.0
	return 0.0

static func _render(horn: String, n: int, shaped_end: bool) -> PackedFloat32Array:
	var r: Dictionary = RECIPES.get(horn, RECIPES[DEFAULT])
	var out := PackedFloat32Array()
	out.resize(n)
	var hz: Array = r.hz
	var tones := hz.size()
	var duty := float(r.duty)
	var dry := float(r.dry)
	var drive := float(r.drive)
	var rough := float(r.rough)
	var sag := float(r.sag)
	var attack := float(r.attack)
	var release := float(r.release)
	var level := float(r.level)
	var breath := float(r.get("breath", 0.0))
	var fall := float(r.get("fall", 0.0))
	var wobble := float(r.get("wobble", 0.0))
	var waver := float(r.get("waver", 0.0))
	var cut := float(r.get("cut", 1.0)) if shaped_end else 1.0
	var secs := float(n) / RATE
	var live := secs * cut
	var lp := AudioDsp.lp(RATE, float(r.lp))
	var dc := AudioDsp.hp(RATE, 90.0)
	var bands: Array[AudioDsp.Biquad] = []
	var band_gain := PackedFloat32Array()
	for f in r.formants:
		bands.append(AudioDsp.bp(RATE, float(f[0]), float(f[1])))
		band_gain.append(float(f[2]))
	# Slow noise that repeats every HOLD_LOOP_S: the jitter on the pulse width
	# and the air under an air horn. Twice round the filter so its end meets
	# its start.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(horn)
	var loop_n := int(HOLD_LOOP_S * RATE)
	var jit := PackedFloat32Array()
	jit.resize(loop_n)
	var white := PackedFloat32Array()
	white.resize(loop_n)
	for i in loop_n:
		white[i] = rng.randf_range(-1.0, 1.0)
	var j := 0.0
	for pass_i in 2:
		for i in loop_n:
			j += (white[i] - j) * 0.08
			jit[i] = j * 3.0
	var phase: Array[float] = []
	var odd: Array[bool] = []
	for k in tones:
		phase.append(rng.randf())
		odd.append(false)
	for i in n:
		var t := float(i) / RATE
		var nz := jit[i % loop_n]
		# Pitch: starts a little high and settles (the coil pulling the supply
		# down), a falling tail (an air horn losing pressure), a waver (sour).
		var bend := 1.0
		if t < SAG_S:
			var s := 1.0 - t / SAG_S
			bend += sag * s * s
		if fall > 0.0 and shaped_end and t > live - release:
			bend -= fall * (t - (live - release)) / release
		if wobble > 0.0:
			bend += wobble * sin(TAU * 6.5 * t) + wobble * 0.5 * sin(TAU * 2.5 * t)
		var x := 0.0
		for k in tones:
			var dt := float(hz[k]) * bend * (1.0 + 0.0015 * sin(TAU * (5.0 + k) * t + 1.7 * k)) / RATE
			var ph := phase[k] + dt
			if ph >= 1.0:
				ph -= 1.0
				odd[k] = not odd[k]
			phase[k] = ph
			# The contact does not open at quite the same point every buzz.
			var w := clampf(duty + rough * 0.25 * nz * (1.0 if k == 0 else -1.0), 0.08, 0.92)
			var v := (1.0 if ph < w else -1.0) + _blep(ph, dt) - _blep(fposmod(ph - w, 1.0), dt) - (2.0 * w - 1.0)
			if odd[k]:
				v *= 1.0 - rough * 0.5
			if waver > 0.0 and k == tones - 1:
				# The weak horn of the pair drops out and comes back.
				v *= clampf(0.5 + 1.4 * sin(TAU * 1.0 * t + 0.6) + 0.5 * sin(TAU * 3.5 * t), 0.0, 1.0) * waver + (1.0 - waver)
			x += v
		x /= float(tones)
		if t < 0.02:
			# The click of the disc being pulled in.
			x += 0.9 * exp(-t / 0.002) * white[i % loop_n]
		var y := lp.step(x) * dry
		for b in bands.size():
			y += bands[b].step(x) * band_gain[b]
		y = dc.step(tanh(y * drive))
		if breath > 0.0:
			# Air rushing before the trumpets speak, and a little under the note.
			y += nz * breath * (exp(-t / 0.07) * 1.6 + 0.12)
		# Level: a hard onset that overshoots, then a slow wobble.
		var env := minf(t / attack, 1.0) * (1.0 + 0.18 * exp(-t / 0.03))
		env *= 1.0 + 0.04 * sin(TAU * 1.5 * t) + 0.025 * sin(TAU * 4.0 * t + 1.3)
		if wobble > 0.0:
			env *= 0.85 + 0.15 * sin(TAU * 5.0 * t)
		if shaped_end:
			if t > live - release:
				var e := maxf((live - t) / release, 0.0)
				env *= e * e
			if cut < 1.0 and t > live * 0.75:
				# The sour horn sputters before it gives up.
				env *= 0.55 + 0.45 * sin(TAU * 31.0 * t)
		out[i] = y * env * level / 1.5
	return out
