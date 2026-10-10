# Baked engine loops (2026-10-10, ROADMAP "engine sound loops").
#
# EngineSynth builds the engine note sample by sample in GDScript, every frame,
# for as long as the car runs. This bakes that same synth once into a bank of
# short seamless loops, so the steady note costs a few looping players instead
# of a per-sample script loop (EngineLoopPlayer does the playing).
#
# - One loop per rpm band, idle to redline, two loads: throttle lifted
#   (engine braking, dark) and throttle open (bright, raspy). Bands are
#   BAND_RATIO apart, so no loop is ever stretched more than about 6 %.
# - Every loop holds a whole number of engine cycles (the firing pattern closes
#   on itself) and its tail is cross-faded into its head, so the loop point has
#   no click and no beat: see seam_jump().
# - Pops, limiter bangs, upshift cuts, anti-lag and the turbo are NOT in the
#   loops. They stay live (EngineSynth.render_events, TurboSynth), because they
#   are events, not a steady tone.
# - Everything is synthesised by this project: nothing to license or credit.
#
# Baking takes a few seconds, so EngineAudio does it on a worker thread and keeps
# the live synth playing until the bank is ready. The result is cached in
# user://audio_cache, keyed by the voice, the two tune values that colour the
# tone, and the source of this file and engine_synth.gd.
extends RefCounted
class_name EngineLoops

const RATE := 44100
## Neighbouring bands are this far apart in rpm: the largest pitch stretch is
## about half of it either way.
const BAND_RATIO := 1.12
## A loop holds this many seconds, rounded to a whole number of engine cycles.
const LOOP_SECS := 0.75
## The tail of each loop is cross-faded into its head over this long.
const XFADE_SECS := 0.12
## Rendered and thrown away first, so filters and the DC blocker are settled
## (also rounded to whole cycles, so every loop starts on a firing).
const WARMUP_SECS := 0.3
## Two bands cross-fade only over this fraction of the gap between them (in
## log rpm), centred half-way. A wide fade between two loops that are not
## phase-locked makes the firing note phase in and out; a narrow one passes
## through that in a fraction of a band.
const XFADE_WIDTH := 0.3
const LOAD_LIFT := 0.0
const LOAD_OPEN := 1.0
## Bump when the recipe changes in a way the source hash can't see (exported
## builds carry no script source).
const CACHE_VERSION := 1
const CACHE_DIR := "user://audio_cache"
## Tests turn the cache off to time a real bake.
static var use_cache := true

## True rpm of each band's loop (the target rounded to a whole sample count).
var rpms := PackedFloat32Array()
## Engine cycles inside each band's loop.
var cycles := PackedInt32Array()
## One AudioStreamWAV (mono, looping) per band, per load.
var lift: Array[AudioStreamWAV] = []
var open: Array[AudioStreamWAV] = []

func band_count() -> int:
	return rpms.size()

## Band centres: idle, then x BAND_RATIO until the last one reaches redline.
static func band_rpms(idle: float, max_rpm: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var r := maxf(idle, 300.0)
	while r < max_rpm * 0.999:
		out.append(r)
		r *= BAND_RATIO
	# the top band sits on redline (at least 1 % above the one below it)
	out.append(maxf(max_rpm, out[-1] * 1.01) if not out.is_empty() else max_rpm)
	return out

## Which two bands play at `rpm` and how loud each is: (k, w_lo, w_hi), where the
## bands are k and k + 1. Below the first band and above the last the end band
## plays alone (pitch does the rest). Equal-power fade over XFADE_WIDTH.
static func pick(bands: PackedFloat32Array, rpm: float) -> Vector3:
	var n := bands.size()
	if n < 2 or rpm <= bands[0]:
		return Vector3(0.0, 1.0, 0.0)
	if rpm >= bands[n - 1]:
		return Vector3(float(n - 2), 0.0, 1.0)
	var k := 0
	while k < n - 2 and rpm >= bands[k + 1]:
		k += 1
	var u := log(rpm / bands[k]) / log(bands[k + 1] / bands[k])
	var t := clampf((u - (0.5 - XFADE_WIDTH * 0.5)) / XFADE_WIDTH, 0.0, 1.0)
	return Vector3(float(k), cos(t * PI * 0.5), sin(t * PI * 0.5))

## Bakes a whole bank for one voice. Pure CPU, touches no scene state, so it is
## safe on a worker thread. Returns what from_baked() takes, or {} when
## cancel["stop"] was set meanwhile.
static func bake(voice: Dictionary, loudness: float, raspiness: float, idle: float,
		max_rpm: float, engine_volume: float, cancel := {}) -> Dictionary:
	var bands := band_rpms(idle, max_rpm)
	var true_rpm := PackedFloat32Array()
	var cyc := PackedInt32Array()
	var lifts: Array = []
	var opens: Array = []
	for r in bands:
		if cancel.get("stop", false):
			return {}
		var a := make_loop(voice, loudness, raspiness, idle, max_rpm, engine_volume, r, LOAD_LIFT)
		var b := make_loop(voice, loudness, raspiness, idle, max_rpm, engine_volume, r, LOAD_OPEN)
		true_rpm.append(a.rpm)
		cyc.append(a.cycles)
		lifts.append(a.pcm)
		opens.append(b.pcm)
	return {"rpms": true_rpm, "cycles": cyc, "lift": lifts, "open": opens}

## One seamless loop: {pcm: PackedByteArray (16-bit mono), rpm, cycles, samples}.
static func make_loop(voice: Dictionary, loudness: float, raspiness: float, idle: float,
		max_rpm: float, engine_volume: float, rpm: float, throttle: float) -> Dictionary:
	var s := EngineSynth.new()
	s.mix_rate = RATE
	s.idle_rpm = idle
	s.max_rpm = max_rpm
	s.apply_voice(voice)
	s.wander = 0.0  # a steady note; the player adds its own slow drift
	s.tune = ExhaustTune.new(loudness, raspiness, 0.0, 0.0, 0.0)
	s.volume = engine_volume
	var cycle_s := 120.0 / rpm
	var n_cyc := maxi(1, roundi(LOOP_SECS / cycle_s))
	var length := maxi(roundi(n_cyc * cycle_s * RATE), 64)
	var fade := mini(roundi(XFADE_SECS * RATE), length / 2)
	var warm := maxi(roundi(WARMUP_SECS / cycle_s), 1) * cycle_s
	_render_block(s, roundi(warm * RATE), rpm, throttle)
	var seg := _render_block(s, length + fade, rpm, throttle)
	var out := PackedFloat32Array()
	out.resize(length)
	for i in length:
		out[i] = seg[i]
	# out[length - 1] is followed by out[0] = seg[length]: the signal's own next
	# sample, cross-faded into the head so the two ends agree for `fade` samples.
	for i in fade:
		var t := float(i) / fade
		out[i] = seg[length + i] * cos(t * PI * 0.5) + seg[i] * sin(t * PI * 0.5)
	var bytes := PackedByteArray()
	bytes.resize(length * 2)
	for i in length:
		bytes.encode_s16(i * 2, int(clampf(out[i], -1.0, 1.0) * 32767.0))
	return {"pcm": bytes, "rpm": float(n_cyc) * 120.0 * RATE / length, "cycles": n_cyc,
			"samples": length}

static func _render_block(s: EngineSynth, frames: int, rpm: float, throttle: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var done := 0
	while done < frames:
		var k := mini(4096, frames - done)
		for v in s.render(k, rpm, throttle, false):
			out.append(v.x)
		done += k
	return out

## Largest sample-to-sample step across the loop point, relative to the largest
## step anywhere inside the loop (1.0 = the seam is as smooth as the signal).
static func seam_jump(pcm: PackedByteArray) -> float:
	var n := pcm.size() / 2
	if n < 3:
		return 0.0
	var worst := 0.0
	var prev := pcm.decode_s16(0)
	for i in range(1, n):
		var v := pcm.decode_s16(i * 2)
		worst = maxf(worst, absf(float(v - prev)))
		prev = v
	var seam := absf(float(pcm.decode_s16(0) - pcm.decode_s16((n - 1) * 2)))
	return seam / maxf(worst, 1.0)

static func to_stream(pcm: PackedByteArray) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = pcm
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = pcm.size() / 2
	return wav

## Streams from bake()'s dictionary (cheap; main thread is fine).
static func from_baked(d: Dictionary) -> EngineLoops:
	var e := EngineLoops.new()
	e.rpms = d["rpms"]
	e.cycles = d["cycles"]
	for p in d["lift"]:
		e.lift.append(to_stream(p))
	for p in d["open"]:
		e.open.append(to_stream(p))
	return e

## Cache key for a voice and the two tune values that colour the steady tone.
static func cache_key(voice: Dictionary, loudness: float, raspiness: float, idle: float,
		max_rpm: float) -> String:
	var src := ""
	for p in ["res://scripts/audio/engine_loops.gd", "res://scripts/audio/engine_synth.gd"]:
		var sc := load(p) as GDScript
		if sc != null:
			src += sc.source_code
	var recipe := "%s|%.2f|%.2f|%.0f|%.0f|%d|%d" % [JSON.stringify(voice, "", true),
			loudness, raspiness, idle, max_rpm, CACHE_VERSION, src.hash()]
	return "engine_loops_%x" % recipe.hash()

## Bakes, or loads this exact bank from disk when it was baked before.
static func bake_cached(voice: Dictionary, loudness: float, raspiness: float, idle: float,
		max_rpm: float, engine_volume: float, cancel := {}) -> Dictionary:
	var path := CACHE_DIR.path_join(cache_key(voice, loudness, raspiness, idle, max_rpm) + ".bin")
	if use_cache and FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var d: Variant = f.get_var()
			if d is Dictionary and d.has("rpms") and d.has("lift") and d.has("open") \
					and (d["lift"] as Array).size() == (d["rpms"] as PackedFloat32Array).size():
				return d
	var baked := bake(voice, loudness, raspiness, idle, max_rpm, engine_volume, cancel)
	if use_cache and not baked.is_empty():
		DirAccess.make_dir_recursive_absolute(CACHE_DIR)
		var w := FileAccess.open(path, FileAccess.WRITE)
		if w != null:
			w.store_var(baked)
	return baked
