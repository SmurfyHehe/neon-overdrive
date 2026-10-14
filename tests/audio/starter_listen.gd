extends SceneTree

# Listen pack for the key start (StarterAudio + the engine's own voice): the
# whole thing as the driver hears it, cold and warm, for a four-cylinder, the
# V8 and the air-cooled flat four: crank, coughs, catch, the rev blip and the
# first seconds of the fast idle. Also the shutdown takes. One .wav each and a
# README.txt with a line for every file.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/audio/starter_listen.gd
#
# STARTER_LISTEN_DIR=<folder>   where they go (default user://listen/starter)
# STARTER_BEFORE=<old starter_audio.gd>   also writes before_*.wav from an
#   older StarterAudio (the one with make_crank(seed) and make_catch(seed),
#   played at pace(cylinders), revs jumping to 1.45 x idle), to compare.

const StarterAudio := preload("res://scripts/audio/starter_audio.gd")
const ENGINES := {"four_cyl": "p2_hothatch", "v8": "p5_muscle", "flat_four": "p0_beater"}
const NAMES := {"four_cyl": "four-cylinder (hot hatch)", "v8": "V8 (muscle)", "flat_four": "air-cooled flat four (beater)"}
const ENGINE_VOLUME := 0.5  # EngineAudio.ENGINE_VOLUME
const OUT_RATE := 44100
## Seconds of the engine running kept after the catch.
const AFTER_S := 4.0
const OLD_GAIN := 0.5
const OLD_CATCH_GAIN := 0.42
const OLD_FLARE := 1.45

var dir := "user://listen/starter"
var readme := PackedStringArray()
var ok := true

func _initialize() -> void:
	var env := OS.get_environment("STARTER_LISTEN_DIR")
	if env != "":
		dir = env
	DirAccess.make_dir_recursive_absolute(dir)
	var before: GDScript = null
	var before_path := OS.get_environment("STARTER_BEFORE")
	if before_path != "":
		before = load(before_path) as GDScript
		if before == null:
			print("starter_listen: could not load STARTER_BEFORE=%s" % before_path)
			ok = false
	var t0 := Time.get_ticks_msec()
	readme.append("Key start listen pack. Each file: the starter, then the engine catching and settling, from the driver's seat.")
	readme.append("")
	for label: String in ENGINES:
		var spec := CarSpec.player_spec(ENGINES[label])
		var voice: Dictionary = spec.get("engine_voice", {})
		var idle := float(spec.get("idle_rpm", 1000.0))
		var rec: Dictionary = StarterAudio.recipe(voice)
		for cold: float in [1.0, 0.0]:
			var which := "cold" if cold > 0.5 else "warm"
			var hold: float = StarterAudio.hold_for(rec.cylinders, cold)
			var starter: PackedFloat32Array = StarterAudio.render_start(rec, cold)
			var fast := idle + PlayerCar.fast_idle_add(idle, cold, 0.0)
			var rpm := func(t: float) -> float:
				var now := idle + PlayerCar.fast_idle_add(idle, cold, t)
				var peak := now * PlayerCar.START_FLARE
				if t < PlayerCar.FLARE_RISE_S:
					return lerpf(Vehicle.STARTER_RPM, peak, 1.0 - pow(1.0 - t / PlayerCar.FLARE_RISE_S, 2.0))
				return now + (peak - now) * exp(-(t - PlayerCar.FLARE_RISE_S) / 0.3)
			var thr := func(t: float) -> float:
				return 0.8 * clampf((PlayerCar.FLARE_THROTTLE_S - t) / (PlayerCar.FLARE_THROTTLE_S - PlayerCar.FLARE_RISE_S), 0.0, 1.0)
			_save("after_%s_%s" % [label, which], _with_engine(starter, hold, voice, idle, rpm, thr),
					"NEW, %s, %s engine: %.1f s crank, %d cough(s), blip, fast idle about %.0f rpm" % [
					NAMES[label], which, hold, StarterAudio.cough_times(hold, cold).size(), fast])
			if before != null:
				var old := _old_start(before, rec.cylinders, hold)
				var old_rpm := func(t: float) -> float:
					return idle + idle * (OLD_FLARE - 1.0) * exp(-t / 0.4)
				_save("before_%s_%s" % [label, which], _with_engine(old, hold, voice, idle, old_rpm, func(_t: float) -> float: return 0.0),
						"BEFORE (playtest build 3), %s, %s engine: %.1f s crank, no coughs, no fast idle" % [NAMES[label], which, hold])
	for i in StarterAudio.STOP_TAKES:
		var wav := StarterAudio.make_shutdown(2203 + i * 17) as AudioStreamWAV
		wav.save_to_wav(dir.path_join("shutdown_take%d.wav" % i))
		readme.append("shutdown_take%d.wav  X off: the engine winding down (unchanged from playtest build 3)" % i)
	var f := FileAccess.open(dir.path_join("README.txt"), FileAccess.WRITE)
	if f == null:
		ok = false
	else:
		f.store_string("\r\n".join(readme) + "\r\n")
		f.close()
	print("starter_listen: %d files in %d ms" % [readme.size() - 2, Time.get_ticks_msec() - t0])
	print("starter_listen: %s, written to %s" % ["PASS" if ok else "FAIL", ProjectSettings.globalize_path(dir)])
	quit(0 if ok else 1)

## `starter` (StarterAudio.RATE, the catch beginning at `hold` seconds) over
## the engine's own voice from the catch on, at OUT_RATE.
func _with_engine(starter: PackedFloat32Array, hold: float, voice: Dictionary, idle: float, rpm: Callable, thr: Callable) -> PackedFloat32Array:
	var synth := EngineSynth.new()
	synth.apply_voice(voice)
	synth.mix_rate = OUT_RATE
	synth.idle_rpm = idle
	synth.volume = ENGINE_VOLUME
	var n := int((hold + AFTER_S) * OUT_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var k := float(StarterAudio.RATE) / OUT_RATE
	for i in n:
		var x := i * k
		var j := int(x)
		if j + 1 < starter.size():
			out[i] = lerpf(starter[j], starter[j + 1], x - j)
	var at := int(hold * OUT_RATE)
	var block := 512
	var i0 := at
	while i0 < n:
		var m := mini(block, n - i0)
		var t := float(i0 - at) / OUT_RATE
		var b := synth.render(m, rpm.call(t), thr.call(t), false)
		for q in m:
			out[i0 + q] += b[q].x
		i0 += m
	# the last quarter second fades, so the file does not end on a click
	var fade := int(0.25 * OUT_RATE)
	for q in fade:
		out[n - fade + q] *= 1.0 - float(q) / fade
	return out

## An older StarterAudio's start: its crank at the engine's pace for `hold`
## seconds, then its catch.
func _old_start(old: GDScript, cylinders: int, hold: float) -> PackedFloat32Array:
	var rate: int = StarterAudio.RATE
	var pace: float = old.pace(cylinders)
	var crank := _floats(old.make_crank(9127) as AudioStreamWAV)
	var catch_take := _floats(old.make_catch(417) as AudioStreamWAV)
	var loop_at := (old.make_crank(9127) as AudioStreamWAV).loop_begin
	var hold_n := int(hold * rate)
	var n := hold_n + int(catch_take.size() / pace)
	var out := PackedFloat32Array()
	out.resize(n)
	var lvl := 0.0
	for i in n:
		var target := 1.0 if i < hold_n else 0.0
		lvl = move_toward(lvl, target, (60.0 if target > lvl else 14.0) / rate)
		var j := int(i * pace)
		if j >= crank.size():
			j = loop_at + (j - loop_at) % (crank.size() - loop_at)
		out[i] = crank[j] * lvl * OLD_GAIN
		if i >= hold_n:
			var c := int((i - hold_n) * pace)
			if c < catch_take.size():
				out[i] += catch_take[c] * OLD_CATCH_GAIN
	return out

static func _floats(wav: AudioStreamWAV) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(wav.data.size() / 2)
	for i in out.size():
		out[i] = wav.data.decode_s16(i * 2) / 32768.0
	return out

func _save(file: String, s: PackedFloat32Array, line: String) -> void:
	var peak := 0.0
	for v in s:
		peak = maxf(peak, absf(v))
	if peak <= 0.05 or peak > 1.0:
		print("starter_listen: %s peak %.3f" % [file, peak])
		ok = false
	var wav := AudioDsp.to_wav(s, OUT_RATE, false)
	if wav.save_to_wav(dir.path_join(file + ".wav")) != OK:
		ok = false
	readme.append("%s.wav  %s" % [file, line])
	print("starter_listen: %s.wav  %.1f s  peak %.2f" % [file, float(s.size()) / OUT_RATE, peak])
