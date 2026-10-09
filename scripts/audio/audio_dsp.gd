class_name AudioDsp
extends RefCounted

# Small offline DSP kit for the sounds generated in code (2026-10-08): CarAudio,
# DrivelineAudio and CrashAudio build their samples once at load with these,
# so nothing here runs per frame. Everything is synthesised: no files, nothing
# to license or credit.

const CACHE_DIR := "user://audio_cache"
## Bump when a recipe changes. Exported builds carry no script source, so the
## source hash below can't see the change there; in the editor and in tests it
## can, and this is only a backstop.
const CACHE_VERSION := 1
## Tests turn this off to time the real build.
static var use_cache := true

## A generated stream, from disk when this exact recipe was built before.
## Building every car loop takes a few seconds in GDScript; loading them is
## instant, so only the first boot after a change pays. The file name carries
## the recipe script's source hash, so editing a recipe can't load a stale sound.
## Old versions are left in the folder (a few MB at most).
static func cached(recipe_path: String, layer: String, maker: Callable) -> AudioStream:
	if not use_cache:
		return maker.call()
	var src := (load(recipe_path) as GDScript).source_code
	var tag := "%d_%x" % [CACHE_VERSION, src.hash()]
	var path := CACHE_DIR.path_join("%s_%s_%s.res" % [recipe_path.get_file().get_basename(), layer, tag])
	if ResourceLoader.exists(path):
		var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if res is AudioStream:
			return res
	var made: AudioStream = maker.call()
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	ResourceSaver.save(made, path)
	return made

## RBJ biquad, transposed direct form II. set_* return self so a filter can be
## made and tuned in one line; retune mid-loop for a moving centre frequency
## (the state carries over, so it doesn't click).
class Biquad:
	var b0 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	var a1 := 0.0
	var a2 := 0.0
	var z1 := 0.0
	var z2 := 0.0

	## Band-pass, 0 dB at the centre.
	func set_bp(rate: float, hz: float, q: float) -> Biquad:
		var w0 := TAU * minf(hz, rate * 0.45) / rate
		var alpha := sin(w0) / (2.0 * q)
		var a0 := 1.0 + alpha
		b0 = alpha / a0
		b1 = 0.0
		b2 = -alpha / a0
		a1 = -2.0 * cos(w0) / a0
		a2 = (1.0 - alpha) / a0
		return self

	func set_lp(rate: float, hz: float, q := 0.707) -> Biquad:
		var w0 := TAU * minf(hz, rate * 0.45) / rate
		var alpha := sin(w0) / (2.0 * q)
		var c := cos(w0)
		var a0 := 1.0 + alpha
		b0 = (1.0 - c) * 0.5 / a0
		b1 = (1.0 - c) / a0
		b2 = b0
		a1 = -2.0 * c / a0
		a2 = (1.0 - alpha) / a0
		return self

	func set_hp(rate: float, hz: float, q := 0.707) -> Biquad:
		var w0 := TAU * minf(hz, rate * 0.45) / rate
		var alpha := sin(w0) / (2.0 * q)
		var c := cos(w0)
		var a0 := 1.0 + alpha
		b0 = (1.0 + c) * 0.5 / a0
		b1 = -(1.0 + c) / a0
		b2 = b0
		a1 = -2.0 * c / a0
		a2 = (1.0 - alpha) / a0
		return self

	func step(x: float) -> float:
		var y := b0 * x + z1
		z1 = b1 * x - a1 * y + z2
		z2 = b2 * x - a2 * y
		return y

static func bp(rate: float, hz: float, q: float) -> Biquad:
	return Biquad.new().set_bp(rate, hz, q)

static func lp(rate: float, hz: float, q := 0.707) -> Biquad:
	return Biquad.new().set_lp(rate, hz, q)

static func hp(rate: float, hz: float, q := 0.707) -> Biquad:
	return Biquad.new().set_hp(rate, hz, q)

## Crossfades the last `fade` samples of s (rendered n + fade long) into its
## head and drops them, so the loop point can't click.
static func seamless(s: PackedFloat32Array, n: int, fade: int) -> PackedFloat32Array:
	for i in fade:
		var k := float(i) / fade
		s[i] = s[i] * k + s[n + i] * (1.0 - k)
	s.resize(n)
	return s

## Scales s so its peak is `peak` (every layer starts from the same loudness).
static func normalise(s: PackedFloat32Array, peak := 0.8) -> PackedFloat32Array:
	var m := 0.0
	for v in s:
		m = maxf(m, absf(v))
	if m > 0.0:
		var g := peak / m
		for i in s.size():
			s[i] *= g
	return s

## 16-bit AudioStreamWAV from mono samples, or stereo when `right` is given
## (same length as `left`). `loop` makes it a whole-length forward loop.
static func to_wav(left: PackedFloat32Array, rate: int, loop: bool, right := PackedFloat32Array()) -> AudioStreamWAV:
	var stereo := not right.is_empty()
	var n := left.size()
	var ch := 2 if stereo else 1
	var bytes := PackedByteArray()
	bytes.resize(n * 2 * ch)
	for i in n:
		bytes.encode_s16(i * 2 * ch, int(clampf(left[i], -1.0, 1.0) * 32767.0))
		if stereo:
			bytes.encode_s16(i * 4 + 2, int(clampf(right[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = stereo
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = n
	return wav

## A stereo loop from one mono take, leaning to one side: the near channel at
## full level, the far one at `far`. Two of these (one per side, from two
## different takes) let a slide on the left sound on the left.
static func panned(take: PackedFloat32Array, rate: int, side: int, far := 0.4) -> AudioStreamWAV:
	var other := take.duplicate()
	for i in other.size():
		other[i] *= far
	return to_wav(take if side < 0 else other, rate, true, other if side < 0 else take)

## A random-variant stream: each play picks one of `variants` and nudges its
## pitch and volume, so repeated hits never sound identical.
static func randomizer(variants: Array[AudioStream], pitch := 1.08, volume_db := 2.0) -> AudioStreamRandomizer:
	var r := AudioStreamRandomizer.new()
	for v in variants:
		r.add_stream(-1, v)
	r.random_pitch = pitch
	r.random_volume_offset_db = volume_db
	r.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	return r
