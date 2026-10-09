extends SceneTree

# Crash and scrape variety test (2026-10-09), headless and silent: it checks
# counts, levels and which take played, never the sound itself (the listen
# pack, tests/sound_listen_pack.gd clips 11-16, is for judging that).
#
# - every one-shot pool holds CrashAudio.VARIANTS takes and every scrape loop
#   LOOP_TAKES takes, each played from its rendered file in assets/sfx/crash,
#   and the files match the current recipes; each take peaks near the same
#   level, is not silent, sits within RANGE_DB of its pool's average loudness;
#   loop takes all differ in length and their loop point doesn't jump
# - firing every hit size off every surface many times: the right layers play
#   (tap / thud / sparks / debris / crunch / glass, per surface), no pool ever
#   plays the same take twice in a row, every take gets used, and every play's
#   volume and pitch stay in range
# - grounding hits: same no-repeat and range checks
# - each scrape surface held at speed: it loops, crossfades to new takes
#   without repeating one, bites on a fast start (not the underbody), and
#   sparks crackle over concrete, metal and road but not car on car
# - real contacts: classify() sorts cars, tagged metal, walls and the road;
#   driving into a plain wall is a concrete hit, into a wall tagged metal a
#   metal one, and sliding along the metal wall scrapes as metal
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/crash_variety.gd

const TIMEOUT := 180.0
const FIRES := 40        # hits per surface and size (x5 layers stays under PLAY_LOG)
const RANGE_DB := 7.0    # a take's RMS may sit this far from its pool's average
const DB_MIN := -30.0
const DB_MAX := 0.5
const PITCH_MIN := 0.85
const PITCH_MAX := 1.15

var fails := 0
var game: Node
var t := 0.0
var step := "boot"
var step_t := 0.0
var p: PlayerCar
var crash: CrashAudio
var wall: StaticBody3D
var quit_in := 0
var samples := {}
var scrape_i := 0
var used := {}   # pool -> {take: true}

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL ", msg)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fail(msg)

func _go(s: String) -> void:
	step = s
	step_t = 0.0

func _hold(c: PlayerCar) -> void:
	c.throttle_input = 0.0
	c.brake_input = 0.0
	c.handbrake_input = 0.0
	c.steering_input = 0.0

func _wall(pos: Vector3, size: Vector3, surface := "") -> StaticBody3D:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	b.add_child(cs)
	if surface != "":
		b.set_meta(&"audio_surface", surface)
	game.add_child(b)
	b.global_position = pos
	return b

func _process(delta: float) -> bool:
	if quit_in > 0:
		quit_in -= 1
		if quit_in == 0:
			quit(0 if fails == 0 else 1)
		return false
	if game == null:
		return false
	t += delta
	step_t += delta
	if t > TIMEOUT:
		_fail("timed out in step %s" % step)
		_finish()
		return false
	match step:
		"boot":
			p = game.get("player")
			if p == null or step_t < 0.5:
				return false
			p.driver = _hold
			for c in p.get_children():
				if c is CrashAudio: crash = c
			_check(crash != null, "the player has no CrashAudio")
			if crash == null:
				_finish()
				return false
			_check_takes()
			_check_hits()
			_check_ground()
			_check_classify()
			_go("scrape_forced")
		"scrape_forced":
			# each surface held at 20 m/s for 9 s, then let go
			var kinds := CrashAudio.SCRAPE_KINDS
			var kind: String = kinds[scrape_i]
			if step_t < delta * 1.5:
				samples.plays0 = crash.plays.size()
				samples.peak = 0.0
				samples.spark = 0.0
			crash.forced_scrape_kind = kind
			crash.forced_scrape_speed = 20.0 if step_t < 9.0 else -1.0
			samples.peak = maxf(samples.peak, crash.scrape_level)
			samples.spark = maxf(samples.spark, (crash._loops["sparks"] as CrashAudio.LoopLayer).level)
			if step_t > 10.0:
				_report_scrape(kind)
				scrape_i += 1
				if scrape_i >= kinds.size():
					crash.forced_scrape_speed = -1.0
					_go("settle")
				else:
					_go("scrape_forced")
		"settle":
			if step_t > 1.5:
				_go("wall_concrete")
		"wall_concrete", "wall_metal":
			var surface := "concrete" if step == "wall_concrete" else "metal"
			if not samples.has(step):
				samples[step] = true
				var fwd := _fwd()
				var at := p.global_position + fwd * 14.0
				wall = _wall(at + Vector3(0.0, 1.0, 0.0), Vector3(12.0, 3.0, 1.0), "metal" if surface == "metal" else "")
				wall.look_at(wall.global_position + fwd, Vector3.UP)
				p.linear_velocity = fwd * 20.0
				samples.hits0 = crash.impact_count
			if step_t > 1.5:
				var hits: int = crash.impact_count - samples.hits0
				print("into a %s wall at 20 m/s: %d hit(s), last %s off %s at %.1f m/s" % [surface, hits, crash.last_tier, crash.last_surface, crash.last_dv])
				_check(hits >= 1, "driving into a %s wall made no crash sound" % surface)
				_check(crash.last_surface == surface, "a %s wall hit should sound %s, got %s" % [surface, surface, crash.last_surface])
				wall.queue_free()
				# back off the wall and straighten up
				p.linear_velocity = Vector3.ZERO
				p.angular_velocity = Vector3.ZERO
				_go("wall_metal" if surface == "concrete" else "scrape_setup")
		"scrape_setup":
			if step_t > 1.0:
				var fwd := _fwd()
				var right := fwd.cross(Vector3.UP)
				var bb := p.chassis_visual.get_meta("half_w", 0.9) as float
				wall = _wall(p.global_position + right * (bb + 0.55) + fwd * 30.0 + Vector3(0.0, 1.0, 0.0), Vector3(0.6, 3.0, 90.0), "metal")
				wall.look_at(wall.global_position + fwd, Vector3.UP)
				samples.fwd = fwd
				samples.right = right
				samples.kinds = {}
				_go("scrape_real")
		"scrape_real":
			p.linear_velocity = samples.fwd * 15.0 + samples.right * 2.0
			if crash.scrape_level > 0.3:
				samples.kinds[crash.scrape_kind] = true
			if step_t > 1.5:
				print("sliding along a metal wall at 15 m/s: loudest scrape kinds %s" % [samples.kinds.keys()])
				_check(samples.kinds.has("metal"), "sliding along a wall tagged metal should scrape as metal (%s)" % [samples.kinds.keys()])
				_finish()
	return false

func _fwd() -> Vector3:
	var fwd := -p.global_transform.basis.z
	fwd.y = 0.0
	return fwd.normalized()

## 16-bit mono samples of a rendered WAV file (its data chunk).
func _read_wav(path: String) -> PackedByteArray:
	var b := FileAccess.get_file_as_bytes(path)
	var i := 12
	while i + 8 <= b.size():
		var id := b.slice(i, i + 4).get_string_from_ascii()
		var size := b.decode_u32(i + 4)
		if id == "data":
			return b.slice(i + 8, i + 8 + size)
		i += 8 + size + (size & 1)
	return PackedByteArray()

## Every take is a rendered file, up to date with the recipes; peak, RMS and
## loop seams straight from the files.
func _check_takes() -> void:
	var stamp := FileAccess.get_file_as_string(CrashSfx.DIR.path_join("recipe_hash.txt")).strip_edges()
	_check(stamp == CrashSfx.recipe_hash(), "assets/sfx/crash is older than scripts/crash_sfx.gd: run tools/render_crash_sfx.gd")
	var names: Array = CrashAudio.POOLS.keys()
	for kind in CrashAudio.LOOPS:
		names.append("loop_" + kind)
	for name in names:
		var pl: CrashAudio.Pool = crash._pools[name] if crash._pools.has(name) else (crash._loops[name.trim_prefix("loop_")] as CrashAudio.LoopLayer).pool
		var want := CrashAudio.LOOP_TAKES if name.begins_with("loop_") else CrashAudio.VARIANTS
		_check(pl.streams.size() == want, "%s should hold %d takes, has %d" % [name, want, pl.streams.size()])
		var rms_db := []
		var lengths := {}
		for k in pl.streams.size():
			var layer := "%s%d" % [name, k]
			var path := CrashSfx.path(layer)
			_check(ResourceLoader.exists(path), "%s has no rendered file" % layer)
			_check(pl.streams[k].resource_path == path, "%s should play its rendered file, not a fallback" % layer)
			var looping := (pl.streams[k] as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD
			_check(looping == name.begins_with("loop_"), "%s: loop mode %s" % [layer, looping])
			var d := _read_wav(ProjectSettings.globalize_path(path))
			var n := d.size() / 2
			var peak := 0.0
			var sum := 0.0
			var step := 0.0
			var prev := d.decode_s16(0) / 32768.0 if n > 0 else 0.0
			for i in n:
				var v := d.decode_s16(i * 2) / 32768.0
				peak = maxf(peak, absf(v))
				sum += v * v
				step = maxf(step, absf(v - prev))
				prev = v
			var rms := sqrt(sum / maxf(n, 1))
			rms_db.append(linear_to_db(maxf(rms, 1e-6)))
			_check(peak > 0.75 and peak < 0.95, "%s peaks at %.2f (want 0.75-0.95)" % [layer, peak])
			_check(rms > 0.01, "%s is nearly silent (rms %.4f)" % [layer, rms])
			if name.begins_with("loop_"):
				_check(not lengths.has(n), "%s has the same length as another take" % layer)
				lengths[n] = true
				# the loop point should be no bigger a step than the sound already takes
				var seam := absf(d.decode_s16(0) - d.decode_s16((n - 1) * 2)) / 32768.0
				_check(seam <= step, "%s jumps %.2f at its loop point (largest step inside %.2f)" % [layer, seam, step])
		var avg := 0.0
		for v in rms_db:
			avg += v
		avg /= rms_db.size()
		var lo := 0.0
		var hi := -100.0
		for k in rms_db.size():
			lo = minf(lo, rms_db[k])
			hi = maxf(hi, rms_db[k])
			_check(absf(rms_db[k] - avg) <= RANGE_DB, "%s%d is %.1f dB off its pool's average loudness" % [name, k, rms_db[k] - avg])
		print("%-18s %d takes, rms %.1f to %.1f dB" % [name, rms_db.size(), lo, hi])

## Plays since `from`, grouped by pool.
func _plays_since(from: int) -> Dictionary:
	var by := {}
	for i in range(from, crash.plays.size()):
		var e: Dictionary = crash.plays[i]
		if not by.has(e.pool):
			by[e.pool] = []
		by[e.pool].append(e)
	return by

## No take twice in a row, levels and pitches in range; notes takes used.
func _check_plays(pool: String, list: Array) -> void:
	if not used.has(pool):
		used[pool] = {}
	for i in list.size():
		var e: Dictionary = list[i]
		used[pool][e.take] = true
		if i > 0 and e.take == list[i - 1].take:
			_fail("%s played take %d twice in a row" % [pool, e.take])
		_check(e.db >= DB_MIN and e.db <= DB_MAX, "%s played at %.1f dB (want %.0f to %.1f)" % [pool, e.db, DB_MIN, DB_MAX])
		_check(e.pitch >= PITCH_MIN and e.pitch <= PITCH_MAX, "%s played at pitch %.2f" % [pool, e.pitch])

func _check_hits() -> void:
	# every surface at every size; the log is capped, so each batch starts clean
	for surface in CrashAudio.SURFACES:
		for dv in [2.0, 5.0, 8.0, 14.0]:
			crash.plays.clear()
			var from := 0
			var count0 := crash.impact_count
			for i in FIRES:
				crash._wait = 0.0
				crash.impact(dv, surface)
			_check(crash.impact_count - count0 == FIRES, "%d hits fired, %d counted" % [FIRES, crash.impact_count - count0])
			var by := _plays_since(from)
			var want := ["tap_" + surface] if dv < CrashAudio.THUD_DV else ["thud_" + surface]
			if dv >= CrashAudio.DEBRIS_DV:
				want.append("debris")
			if dv >= CrashAudio.CRUNCH_DV:
				want.append("crunch")
			var maybe := []
			if dv >= CrashAudio.SPARK_DV and surface != "car":
				maybe.append("sparks")
			if dv >= CrashAudio.GLASS_DV:
				maybe.append("glass")
			for pool in want:
				_check(by.has(pool) and by[pool].size() == FIRES, "%s at %.0f m/s: %s should play every hit (%d of %d)" % [surface, dv, pool, by.get(pool, []).size(), FIRES])
			for pool in maybe:
				var c: int = by.get(pool, []).size()
				_check(c > FIRES / 4 and c < FIRES, "%s at %.0f m/s: %s should play on most hits, not all (%d of %d)" % [surface, dv, pool, c, FIRES])
			for pool in by:
				_check(pool in want or pool in maybe, "%s at %.0f m/s should not play %s" % [surface, dv, pool])
				_check_plays(pool, by[pool])
			var summary := []
			for pool in by:
				summary.append("%s x%d" % [pool, by[pool].size()])
			print("%-8s %4.0f m/s x%d: %s" % [surface, dv, FIRES, ", ".join(summary)])
	# over all of that, every pool used every take
	for pool in used:
		_check(used[pool].size() == CrashAudio.VARIANTS, "%s used only %d of %d takes" % [pool, used[pool].size(), CrashAudio.VARIANTS])
	# the cooldown still merges hits fired together
	crash._wait = 0.0
	var c0 := crash.impact_count
	crash.impact(5.0)
	crash.impact(5.0)
	_check(crash.impact_count - c0 == 1, "two hits in the same tick should be one sound")

func _check_ground() -> void:
	crash.plays.clear()
	var g0 := crash.ground_hits
	for i in FIRES:
		crash._ground_wait = 0.0
		crash.ground_hit(6.0)
	var by := _plays_since(0)
	_check(crash.ground_hits - g0 == FIRES, "grounding hits: %d fired, %d counted" % [FIRES, crash.ground_hits - g0])
	_check(by.has("ground_hit") and by.ground_hit.size() == FIRES, "every grounding hit should play")
	if by.has("ground_hit"):
		_check_plays("ground_hit", by.ground_hit)
		_check(used.ground_hit.size() == CrashAudio.VARIANTS, "ground_hit used only %d takes" % used.ground_hit.size())
	print("ground_hit x%d: no repeats, levels in range" % FIRES)
	crash.plays.clear()

func _check_classify() -> void:
	var car := Vehicle.new()
	var metal := StaticBody3D.new()
	metal.set_meta(&"audio_surface", "metal")
	var plain := StaticBody3D.new()
	_check(CrashAudio.classify(car, Vector3.RIGHT) == "car", "a Vehicle should classify as car")
	_check(CrashAudio.classify(metal, Vector3.RIGHT) == "metal", "a body tagged metal should classify as metal")
	_check(CrashAudio.classify(plain, Vector3.RIGHT) == "concrete", "a plain wall should classify as concrete")
	_check(CrashAudio.classify(plain, Vector3.UP) == "underbody", "the road under the body should classify as underbody")
	_check(CrashAudio.classify(plain, Vector3.DOWN) == "underbody", "the road on the roof should classify as underbody")
	car.free()
	metal.free()
	plain.free()

func _report_scrape(kind: String) -> void:
	var layer: CrashAudio.LoopLayer = crash._loops[kind]
	var st := layer.started
	var repeats := 0
	for i in range(1, st.size()):
		if st[i] == st[i - 1]:
			repeats += 1
	var bites := 0
	for i in range(samples.plays0, crash.plays.size()):
		if crash.plays[i].pool == "scrape_bite":
			bites += 1
	print("scrape %-9s at 20 m/s: level %.2f, takes %s, bites %d, sparks %.2f" % [kind, samples.peak, st, bites, samples.spark])
	_check(samples.peak > 0.5, "%s scrape at 20 m/s should be loud (%.2f)" % [kind, samples.peak])
	_check(st.size() >= 3, "a 9 s %s scrape should move through 3+ takes (%d)" % [kind, st.size()])
	_check(repeats == 0, "%s scrape repeated a take back to back" % kind)
	_check(layer.level < 0.05 and not layer.players[0].playing and not layer.players[1].playing, "%s scrape should stop when let go" % kind)
	if kind == "underbody":
		_check(bites == 0, "the underbody should not bite")
	else:
		_check(bites == 1, "a %s scrape starting at 20 m/s should bite once (%d)" % [kind, bites])
	if kind == "car":
		_check(samples.spark < 0.05, "car on car should not spark (%.2f)" % samples.spark)
	else:
		_check(samples.spark > 0.3, "%s at 20 m/s should spark (%.2f)" % [kind, samples.spark])

func _finish() -> void:
	if quit_in > 0 or game == null:
		return
	print("crash_variety: %s" % ("PASS" if fails == 0 else "%d failure(s)" % fails))
	game.queue_free()
	game = null
	quit_in = 3
