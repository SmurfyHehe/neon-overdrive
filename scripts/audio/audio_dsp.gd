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
	var path := _cache_path(recipe_path, layer)
	if _jobs.has(path):
		# prefetch() started it: take that build instead of making it again
		var built := _collect(path)
		if built != null:
			DirAccess.make_dir_recursive_absolute(CACHE_DIR)
			ResourceSaver.save(built, path)
			return built
	if ResourceLoader.exists(path):
		var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if res is AudioStream:
			return res
	var made: AudioStream = maker.call()
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	ResourceSaver.save(made, path)
	return made

## Cold cache, first boot (issue #524): the player car's sounds took about 3.5 s
## to make one after another on the main thread before the garage could open.
## prefetch() starts each missing one off the main thread; the cached() call
## that follows (same recipe and layer) takes it and saves it. Makers must be
## pure (they run off the main thread): every one in the car's audio is a
## static function of its arguments.
## `urgent`: the main thread asks for it straight away, so it goes to the
## worker pool as a high-priority task (low-priority ones share only a few
## threads). Not urgent: nothing waits for it yet (the garage boot), so it
## goes to one background thread of its own, in order. Not the pool: seconds
## of these at the front of the pool's queue held up the engine's per-frame
## audio block and its loop bake, and the main thread waits on those.
static func prefetch(recipe_path: String, layer: String, maker: Callable, urgent := true) -> void:
	if not use_cache:
		return
	var path := _cache_path(recipe_path, layer)
	if _jobs.has(path) or ResourceLoader.exists(path):
		return
	var built: Array = []
	if urgent:
		var task := WorkerThreadPool.add_task(func() -> void: built.append(maker.call()), true, "audio bake")
		_jobs[path] = [task, built]
		return
	_jobs[path] = [-1, built]
	_lane_lock.lock()
	_lane_queue.append([path, maker, built])
	_lane_lock.unlock()
	if _lane == null or not _lane.is_alive():
		if _lane != null:
			_lane.wait_to_finish()
		_lane = Thread.new()
		_lane.start(_run_lane, Thread.PRIORITY_LOW)

## True while prefetch() is still making this one.
static func building(recipe_path: String, layer: String) -> bool:
	if not use_cache:
		return false
	var job: Variant = _jobs.get(_cache_path(recipe_path, layer))
	if job == null:
		return false
	if int(job[0]) >= 0:
		return not WorkerThreadPool.is_task_completed(int(job[0]))
	_lane_lock.lock()
	var pending: bool = (job[1] as Array).is_empty()
	_lane_lock.unlock()
	return pending

## Call before the scene that asked for prefetches goes away: drops the
## background jobs that have not started (made again the next time they are
## asked for), waits for the ones running (at most one take each), and saves
## and lets go of every finished one nobody collected. Nothing outlives it.
static func release() -> void:
	_lane_lock.lock()
	for job in _lane_queue:
		_jobs.erase(job[0])
	_lane_queue.clear()
	_lane_lock.unlock()
	if _lane != null:
		_lane.wait_to_finish()
		_lane = null
	for path in _jobs.keys():
		var built := _collect(path)
		if built != null:
			DirAccess.make_dir_recursive_absolute(CACHE_DIR)
			ResourceSaver.save(built, path)

static var _tags := {}   # recipe script path -> cache tag (its source hash), read once
static var _jobs := {}   # cache file path -> [pool task id or -1 on the lane, [the stream, once built]]
static var _lane: Thread
static var _lane_lock := Mutex.new()
static var _lane_queue := []   # [cache path, maker, result array], oldest first

static func _run_lane() -> void:
	while true:
		_lane_lock.lock()
		if _lane_queue.is_empty():
			_lane_lock.unlock()
			return
		var job: Array = _lane_queue.pop_front()
		_lane_lock.unlock()
		var made: Variant = (job[1] as Callable).call()
		_lane_lock.lock()
		(job[2] as Array).append(made)
		_lane_lock.unlock()

## The stream prefetch() made for this cache file, waiting for it if needed;
## null if it failed.
static func _collect(path: String) -> AudioStream:
	var job: Array = _jobs[path]
	_jobs.erase(path)
	var built: Array = job[1]
	if int(job[0]) >= 0:
		WorkerThreadPool.wait_for_task_completion(int(job[0]))
	else:
		_lane_lock.lock()
		var queued := -1
		for i in _lane_queue.size():
			if _lane_queue[i][0] == path:
				queued = i
		if queued >= 0:
			# not started yet: make it here rather than wait behind the others
			var maker: Callable = _lane_queue[queued][1]
			_lane_queue.remove_at(queued)
			_lane_lock.unlock()
			built.append(maker.call())
		else:
			_lane_lock.unlock()
			while true:   # on the lane right now: at most one take
				_lane_lock.lock()
				var done := not built.is_empty()
				_lane_lock.unlock()
				if done:
					break
				OS.delay_usec(200)
	return built[0] if not built.is_empty() and built[0] is AudioStream else null

static func _cache_path(recipe_path: String, layer: String) -> String:
	if not _tags.has(recipe_path):
		var src := (load(recipe_path) as GDScript).source_code
		_tags[recipe_path] = "%d_%x" % [CACHE_VERSION, src.hash()]
	return CACHE_DIR.path_join("%s_%s_%s.res" % [recipe_path.get_file().get_basename(), layer, _tags[recipe_path]])

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

## Two-pole resonator: one unit impulse rings as a unit sine at `hz` that dies
## away as e^(-decay * t). The building block of modal (struck-object) sounds:
## a panel, a guardrail or a glass shard is a handful of these at once.
class Reso:
	var c1 := 0.0
	var c2 := 0.0
	var g := 0.0
	var y1 := 0.0
	var y2 := 0.0

	func setup(rate: float, hz: float, decay: float) -> Reso:
		var w := TAU * minf(hz, rate * 0.45) / rate
		var r := exp(-decay / rate)
		c1 = 2.0 * r * cos(w)
		c2 = -r * r
		g = sin(w)
		return self

	func step(x: float) -> float:
		var y := g * x + c1 * y1 + c2 * y2
		y2 = y1
		y1 = y
		return y

static func reso(rate: float, hz: float, decay: float) -> Reso:
	return Reso.new().setup(rate, hz, decay)

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
