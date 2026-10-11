extends SceneTree

# Crash timbre test (2026-10-11, Roy: crashes "sound like Lego"). Headless, no
# game boot: it reads every rendered take in assets/sfx/crash and measures
# where its energy sits, so a recipe can't slide back to a sub boom nobody
# hears on laptop speakers plus a few clean plastic-sounding modes.
#
# Per pool, the mean over its takes of:
# - the share of the take's energy under 120 Hz (a laptop plays none of it),
#   at 120-400 Hz (what makes a hit heavy on small speakers) and above 3 kHz;
#   each band is the take through two AudioDsp filters in a row per edge
# - the tail: the time until the take stays below 3 % of its peak
# Asserts:
# - thud_*, crunch, smash, ground_hit: at most 35 % under 120 Hz, at least
#   20 % at 120-400 Hz (thud_* 25 %)
# - crunch and smash: a tail of 1.0 s or more
# - glass: 50-85 % above 3 kHz (grains and a low pop, not only pings)
# - the tail and smash pools exist with VARIANTS takes each
# Prints the whole table (the PR's before/after numbers come from it).
# CRASH_TIMBRE_MAKE=<pool,pool> builds those pools straight from the recipes
# (2 takes each) instead of reading the files: for tuning a recipe without a
# full render. That mode never passes.
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/audio/crash_timbre.gd

const HEAVY := ["thud_concrete", "thud_metal", "thud_car", "crunch", "smash", "ground_hit"]
const LONG := ["crunch", "smash"]
const NEW_POOLS := ["tail", "smash"]
const LOW_MAX := 0.35
const MID_MIN := 0.20
const MID_MIN_THUD := 0.25
const TAIL_MIN := 1.0
const GLASS_HIGH := [0.50, 0.85]

var fails := 0

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL ", msg)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fail(msg)

func _initialize() -> void:
	var live := OS.get_environment("CRASH_TIMBRE_MAKE")
	var names: Array = CrashAudio.POOLS.keys()
	for extra in NEW_POOLS + HEAVY:
		if not (extra in names):
			names.append(extra)
	if live != "":
		names = Array(live.split(","))
	var rows := {}
	var bytes := 0
	print("%-15s %5s %8s %9s %8s %7s %7s" % ["pool", "takes", "<120 Hz", "120-400", ">3 kHz", "tail s", "rms dB"])
	for pname in names:
		var sum := {"low": 0.0, "mid": 0.0, "high": 0.0, "tail": 0.0, "rms": 0.0}
		var takes := 0
		for k in (2 if live != "" else CrashAudio.VARIANTS):
			var layer := "%s%d" % [pname, k]
			var s := PackedFloat32Array()
			if live != "":
				s = _floats((CrashSfx.make(layer) as AudioStreamWAV).data)
			else:
				var path := ProjectSettings.globalize_path(CrashSfx.path(layer))
				if not FileAccess.file_exists(path):
					continue
				var d := _read_wav(path)
				bytes += d.size()
				s = _floats(d)
			if s.is_empty():
				continue
			var m := measure(s, float(CrashSfx.MIX_RATE))
			for key in sum:
				sum[key] += m[key]
			takes += 1
		if takes == 0:
			rows[pname] = {"takes": 0}
			print("%-15s %5d" % [pname, 0])
			continue
		for key in sum:
			sum[key] /= takes
		sum.takes = takes
		rows[pname] = sum
		print("%-15s %5d %7.0f%% %8.0f%% %7.0f%% %7.2f %7.1f" % [pname, takes, sum.low * 100.0, sum.mid * 100.0, sum.high * 100.0, sum.tail, sum.rms])
	if live != "":
		print("crash_timbre: tuning run, not a pass")
		quit(1)
		return
	for pname in HEAVY:
		var row: Dictionary = rows[pname]
		if row.takes == 0:
			_fail("%s has no rendered takes" % pname)
			continue
		_check(row.low <= LOW_MAX, "%s has %.0f%% of its energy under 120 Hz (want at most %.0f%%): a laptop plays none of that" % [pname, row.low * 100.0, LOW_MAX * 100.0])
		var want: float = MID_MIN_THUD if pname.begins_with("thud_") else MID_MIN
		_check(row.mid >= want, "%s has %.0f%% of its energy at 120-400 Hz (want at least %.0f%%): no weight on small speakers" % [pname, row.mid * 100.0, want * 100.0])
	for pname in LONG:
		var row: Dictionary = rows[pname]
		if row.takes > 0:
			_check(row.tail >= TAIL_MIN, "%s is over in %.2f s (want %.1f s or more)" % [pname, row.tail, TAIL_MIN])
	var glass: Dictionary = rows["glass"]
	_check(glass.takes > 0 and glass.high >= GLASS_HIGH[0] and glass.high <= GLASS_HIGH[1], "glass has %.0f%% of its energy above 3 kHz (want %.0f-%.0f%%)" % [glass.get("high", 0.0) * 100.0, GLASS_HIGH[0] * 100.0, GLASS_HIGH[1] * 100.0])
	for pname in NEW_POOLS:
		_check(CrashAudio.POOLS.has(pname), "CrashAudio has no %s pool" % pname)
		_check(rows[pname].takes == CrashAudio.VARIANTS, "%s should have %d rendered takes, has %d" % [pname, CrashAudio.VARIANTS, rows[pname].takes])
	print("one-shot takes on disk: %.1f MB" % (bytes / 1048576.0))
	print("crash_timbre: %s" % ("PASS" if fails == 0 else "%d failure(s)" % fails))
	quit(0 if fails == 0 else 1)

## Band shares (of the take's energy), tail (s) and loudness (dB RMS) of one take.
static func measure(s: PackedFloat32Array, rate: float) -> Dictionary:
	var n := s.size()
	var lo_a := AudioDsp.lp(rate, 120.0)
	var lo_b := AudioDsp.lp(rate, 120.0)
	var mid_a := AudioDsp.hp(rate, 120.0)
	var mid_b := AudioDsp.hp(rate, 120.0)
	var mid_c := AudioDsp.lp(rate, 400.0)
	var mid_d := AudioDsp.lp(rate, 400.0)
	var hi_a := AudioDsp.hp(rate, 3000.0)
	var hi_b := AudioDsp.hp(rate, 3000.0)
	var total := 0.0
	var low := 0.0
	var mid := 0.0
	var high := 0.0
	var peak := 0.0
	for v in s:
		total += v * v
		peak = maxf(peak, absf(v))
		var a := lo_b.step(lo_a.step(v))
		low += a * a
		var b := mid_d.step(mid_c.step(mid_b.step(mid_a.step(v))))
		mid += b * b
		var c := hi_b.step(hi_a.step(v))
		high += c * c
	var last := 0
	for i in n:
		if absf(s[i]) >= peak * 0.03:
			last = i
	total = maxf(total, 1e-12)
	return {
		"low": low / total,
		"mid": mid / total,
		"high": high / total,
		"tail": last / rate,
		"rms": linear_to_db(maxf(sqrt(total / maxf(n, 1)), 1e-6)),
	}

static func _floats(d: PackedByteArray) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(d.size() / 2)
	for i in s.size():
		s[i] = d.decode_s16(i * 2) / 32768.0
	return s

## 16-bit mono samples of a rendered WAV file (its data chunk).
static func _read_wav(path: String) -> PackedByteArray:
	var b := FileAccess.get_file_as_bytes(path)
	var i := 12
	while i + 8 <= b.size():
		var id := b.slice(i, i + 4).get_string_from_ascii()
		var size := b.decode_u32(i + 4)
		if id == "data":
			return b.slice(i + 8, i + 8 + size)
		i += 8 + size + (size & 1)
	return PackedByteArray()
