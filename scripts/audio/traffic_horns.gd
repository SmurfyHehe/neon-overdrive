class_name TrafficHorns
extends RefCounted

# Traffic horns (traffic near-miss fix step 5, 2026-10-10; Roy: drivers honk
# when cut off, and different cars honk differently). Six horns, synthesized
# here into AudioStreamWAVs the way the engine and menu sounds are: no bought
# or credited recordings.
#
#   beep      thin, about 600 Hz: kei cars and small hatches
#   two_tone  the ordinary pair, about 400 + 500 Hz, slightly detuned: sedans,
#             wagons, commuters, and any car this table does not know
#   blare     lower and thicker, about 300 + 360 Hz: pickups and crossovers
#   air       about 180 + 220 Hz with a breathy start and a falling tail:
#             trucks, vans, buses
#   sharp     bright and clipped, about 520 + 650 Hz: sports and tuner cars
#   sour      weak, a little flat and wobbly, about 350 Hz, cuts out early:
#             old beaters and damaged cars
#
# Each horn has a short take (SHORT_S: a tap for a close pass or a mild cut)
# and a long one (LONG_S: leaning on it). A horn is two reeds: each a sine
# with two harmonics pushed through a soft clipper, which is what gives the
# buzz, then a one-pole low-pass for how bright the trumpet is.
#
# Built once, off the main thread (warm()), about a second of sound each. Until
# that finishes stream() returns null and a honk is silent. TrafficManager
# plays them on two shared AudioStreamPlayer3Ds on the Traffic bus; no car
# owns a player.

const RATE := 22050
const SHORT_S := 0.4
const LONG_S := 1.0
const NAMES: Array[String] = ["beep", "two_tone", "blare", "air", "sharp", "sour"]
const DEFAULT := "two_tone"

## Car kind (NpcCarBuilder.KINDS key) -> horn. Anything else gets DEFAULT.
const BY_KIND := {
	"n1_commuter": "two_tone", "n2_cityhatch": "beep", "n3_pickup": "blare",
	"p0_beater": "sour", "p2_hothatch": "sharp", "p3_tuner": "sharp", "p4_kei": "beep",
	"p5_muscle": "blare", "p6_crossover": "blare", "p17_work_pickup": "air",
	"c1_patrol": "two_tone", "c2_patrolsuv": "blare", "c3_interceptor": "sharp",
}

## Per horn: reed pitches (Hz), drive into the clipper, low-pass (Hz), attack
## and release (s), level, and the odd ones out: breath (noise at the start),
## fall (share the pitch drops over the tail), wobble (vibrato depth), cut
## (share of the take after which it dies), hard (clip instead of soft-clip).
const RECIPES := {
	"beep": {"hz": [604.0], "drive": 1.6, "lp": 5200.0, "attack": 0.004, "release": 0.03, "level": 0.62, "thin": 0.6},
	"two_tone": {"hz": [398.0, 503.0], "drive": 2.2, "lp": 3600.0, "attack": 0.008, "release": 0.05, "level": 0.8},
	"blare": {"hz": [301.0, 362.0], "drive": 3.4, "lp": 2800.0, "attack": 0.012, "release": 0.07, "level": 0.9},
	"air": {"hz": [181.0, 221.0], "drive": 2.6, "lp": 2200.0, "attack": 0.05, "release": 0.25, "level": 0.8, "breath": 0.3, "fall": 0.06},
	"sharp": {"hz": [522.0, 652.0], "drive": 4.0, "lp": 6500.0, "attack": 0.003, "release": 0.03, "level": 0.8, "hard": true},
	"sour": {"hz": [343.0], "drive": 1.4, "lp": 2400.0, "attack": 0.02, "release": 0.04, "level": 0.45, "wobble": 0.025, "cut": 0.6},
}

static var _streams := {}
static var _lock := Mutex.new()
static var _task := -1

static func horn_for(kind: String, sour := false) -> String:
	return "sour" if sour else String(BY_KIND.get(kind, DEFAULT))

## Starts building every horn on a worker thread (once).
static func warm() -> void:
	if _task >= 0:
		return
	_task = WorkerThreadPool.add_task(_build_all, false, "traffic horns")

## Waits for the build if it is still running (the manager is leaving the tree).
static func finish() -> void:
	if _task >= 0 and not WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)

static func ready() -> bool:
	_lock.lock()
	var ok := _streams.size() == NAMES.size() * 2
	_lock.unlock()
	return ok

## The take to play, or null while the horns are still being built.
static func stream(horn: String, long: bool) -> AudioStreamWAV:
	_lock.lock()
	var s: AudioStreamWAV = _streams.get(_key(horn, long))
	_lock.unlock()
	return s

static func _key(horn: String, long: bool) -> String:
	return horn + ("|long" if long else "|short")

static func _build_all() -> void:
	for horn in NAMES:
		for long in [false, true]:
			var wav := AudioDsp.to_wav(samples(horn, LONG_S if long else SHORT_S), RATE, false)
			_lock.lock()
			_streams[_key(horn, long)] = wav
			_lock.unlock()

## One take as mono samples in -1..1. Pure, so a test can look at it.
static func samples(horn: String, secs: float) -> PackedFloat32Array:
	var r: Dictionary = RECIPES.get(horn, RECIPES[DEFAULT])
	var n := int(secs * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var hz: Array = r.hz
	var drive := float(r.drive)
	var attack := float(r.attack)
	var release := float(r.release)
	var level := float(r.level)
	var breath := float(r.get("breath", 0.0))
	var fall := float(r.get("fall", 0.0))
	var wobble := float(r.get("wobble", 0.0))
	var cut := float(r.get("cut", 1.0))
	var thin := float(r.get("thin", 0.0))
	var hard: bool = r.get("hard", false)
	var lp_k := 1.0 - exp(-TAU * float(r.lp) / RATE)
	var hp_k := 1.0 - exp(-TAU * 900.0 / RATE)
	var live := secs * cut
	var phase := PackedFloat32Array()
	phase.resize(hz.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(horn)
	var lp := 0.0
	var low := 0.0
	var noise_lp := 0.0
	for i in n:
		var t := float(i) / RATE
		# Pitch: a falling tail (air horn losing pressure), a wobble (sour).
		var bend := 1.0
		if fall > 0.0 and t > live * 0.7:
			bend -= fall * (t - live * 0.7) / maxf(secs - live * 0.7, 0.01)
		if wobble > 0.0:
			bend += wobble * sin(TAU * 7.0 * t) + wobble * 0.5 * sin(TAU * 2.3 * t)
		var x := 0.0
		for k in hz.size():
			phase[k] = fmod(phase[k] + float(hz[k]) * bend / RATE, 1.0)
			var ph := TAU * phase[k]
			x += sin(ph) + 0.5 * sin(2.0 * ph) + 0.3 * sin(3.0 * ph + 0.6)
		x *= drive / float(hz.size())
		x = clampf(x, -1.0, 1.0) if hard else tanh(x)
		lp += (x - lp) * lp_k
		var y := lp
		if thin > 0.0:
			# Thin: take some of the body out (what is left under 900 Hz).
			low += (y - low) * hp_k
			y -= low * thin
		if breath > 0.0:
			# Air rushing before the reeds speak, and a little under the note.
			noise_lp += (rng.randf_range(-1.0, 1.0) - noise_lp) * 0.35
			y += noise_lp * breath * (exp(-t / 0.07) * 1.6 + 0.12)
		# Envelope: attack, hold, release at the end of the live part.
		var env := minf(t / attack, 1.0)
		if t > live - release:
			env *= maxf((live - t) / release, 0.0)
		if cut < 1.0 and t > live * 0.8:
			# The sour horn sputters before it gives up.
			env *= 0.6 + 0.4 * sin(TAU * 31.0 * t)
		if wobble > 0.0:
			env *= 0.85 + 0.15 * sin(TAU * 5.1 * t)
		out[i] = y * env * level
	return out
