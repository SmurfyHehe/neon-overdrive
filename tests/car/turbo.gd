extends SceneTree

# Turbo test (Phase B, 2026-10-05), headless and silent:
# - naturally aspirated (turbo_boost_max 0): boost stays 0
# - with boost: it lags (small after 0.1 s, large after ~3 s), then falls when the
#   throttle lifts, and exactly one blow-off fires
# - the boost speeds the car up (0-100 faster on TuneTrack) and the default car is
#   unchanged
# - TurboSynth (B1, its own stream on the Turbo bus): the whistle and the valve add
#   sound only when asked, silence at boost 0
# - the vent lasts 0.3 to 1 s, a shift vent is shorter; the spool is more than one tone
#   and stays above the mirror whistle (1.25 / 2.5 kHz)
# - the three parts (small / medium / big) whistle at their own pitch; the three valves
#   (recirc / atmo / flutter) differ: atmo is brighter than recirc, flutter stutters
# - the boost setups (C1's boost_kind): a blower whines off boost at an rpm pitch and
#   has no valve, the twin beats, the sequential's big turbo joins at the handover,
#   the twincharger's blower is bypassed mid-range
# - EngineAudio vents when the driver eases off the pedal (a ramp, not a one-tick cut)
# - live: the lift gives exactly one vent, a lift vent, although GEVP shifts up in the
#   same tick (its shift vent, GEVP's blow-off count and the lift ramp fold into one);
#   the Turbo bus and its AudioSettings channel exist and the channel sets the bus
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tests/car/turbo.gd

const TIMEOUT_TICKS := 60 * 40

enum Step { BOOT, NA, SPOOL, LIFT, TRACK, SYNTH, DONE }

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var throttle := 0.0
var early := -1.0
var blow_offs_before := 0
var vents_before := 0
var spool_ms := 0  # wall clock when the turbo came on (see Step.SPOOL)
var shift_vents_before := 0
var audio: EngineAudio

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")  # an empty road, whatever run_tests.bat or the saved settings say
	change_scene_to_file("res://Game.tscn")

func _drive(c: PlayerCar) -> void:
	c.throttle_input = throttle
	c.brake_input = 0.0
	c.steering_input = 0.0

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("player") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	var p: PlayerCar = game.player
	p.driver = _drive
	if audio == null:
		for c in p.get_children():
			if c is EngineAudio:
				audio = c
		if audio == null:
			return _end("no EngineAudio on the player car")
	var waited := tick - step_start
	match step:
		Step.BOOT:
			_check(is_zero_approx(p.turbo_boost_max), "the default car should be naturally aspirated")
			throttle = 1.0
			_go(Step.NA)
		Step.NA:
			if waited >= 120:
				_check(is_zero_approx(p.boost), "boost should stay 0 without a turbo, is %.2f" % p.boost)
				p.turbo_boost_max = 1.0
				p.boost = 0.0
				spool_ms = Time.get_ticks_msec()
				_go(Step.SPOOL)
		Step.SPOOL:
			if waited == 6:
				early = p.boost
			# TurboSynth folds a vent seen within VENT_GAP of the last one into it,
			# and measures that gap in rendered audio (its _since_vent grows with
			# the samples pulled), which the Dummy driver consumes in real time.
			# This run is faster than real time (--fixed-fps), so 240 ticks can
			# pass in well under 0.15 s of audio and the lift below was taken for
			# a repeat of the vent the turbo's first frame made ("vented 0",
			# seen on CI). Hold the lift until the audio clock has moved on.
			if waited >= 240 and Time.get_ticks_msec() - spool_ms >= 600:
				_check(early < 0.3, "boost should lag: %.2f after 0.1 s" % early)
				_check(p.boost > 0.5, "boost should have spooled after 4 s at full throttle, is %.2f" % p.boost)
				blow_offs_before = p.blow_off_count
				vents_before = audio.turbo.vents
				shift_vents_before = audio.turbo.shift_vents
				print("vents during the spool: shift %d, lift %d" % [audio.turbo.shift_vents, audio.turbo.vents])
				throttle = 0.0
				_go(Step.LIFT)
		Step.LIFT:
			if waited >= 90:
				_check(p.boost < 0.3, "boost should fall after lifting, is %.2f" % p.boost)
				_check(p.blow_off_count - blow_offs_before == 1, "lift should fire one blow-off, fired %d" % (p.blow_off_count - blow_offs_before))
				# GEVP shifts up on this lift as well: the shift vent, GEVP's count and
				# the lift ramp all land in one frame and must come out as one lift vent.
				_check(audio.turbo.vents - vents_before == 1, "the lift should vent once (shift vent, GEVP's count and the ramp fold), vented %d" % (audio.turbo.vents - vents_before))
				_check(audio.turbo.shift_vents == shift_vents_before, "a lift in the same frame as a shift is a lift vent, not a shift vent: shift vents %d -> %d" % [shift_vents_before, audio.turbo.shift_vents])
				_bus()
				_go(Step.TRACK)
				_track()
	return false

func _track() -> void:
	var track := TuneTrack.new()
	root.add_child(track)
	await process_frame
	var na := CarSpec.coupe_default()
	var boosted := CarSpec.coupe_default()
	boosted["turbo_boost_max"] = 1.0
	var res: Array = await track.evaluate([na, boosted])
	var t_na: float = res[0].t_0_100
	var t_turbo: float = res[1].t_0_100
	print("0-100: NA %.2f s, turbo %.2f s" % [t_na, t_turbo])
	_check(t_turbo < t_na * 0.97, "turbo should be faster (%.2f vs %.2f)" % [t_turbo, t_na])
	_synth()

## The Turbo bus, its channel and the slider's effect on the bus.
func _bus() -> void:
	var b := AudioServer.get_bus_index(&"Turbo")
	_check(b >= 0, "no Turbo bus in default_bus_layout.tres")
	_check(AudioSettings.CHANNELS.has("Turbo"), "AudioSettings has no Turbo channel (the Sound page's slider)")
	_check(AudioSettings.channel_of(&"Turbo") == "Turbo", "the Turbo bus should belong to the Turbo channel")
	if b >= 0:
		AudioSettings.set_volume("Turbo", 0.5)
		_check(is_equal_approx(AudioServer.get_bus_volume_db(b), linear_to_db(0.5)), "the Turbo slider should set the Turbo bus")
		AudioSettings.set_volume("Turbo", 1.0)
	_check(audio._turbo_player != null and audio._turbo_player.bus == &"Turbo", "the turbo stream should play on the Turbo bus")

func _synth() -> void:
	var quiet := _render(0.0, false)
	var whistle := _render(1.0, false)
	var vent := _render(0.0, true)
	print("synth rms: quiet %.4f whistle %.4f vent %.4f" % [quiet, whistle, vent])
	_check(quiet < 0.0001, "no boost and no vent should be silence, rms %.4f" % quiet)
	_check(whistle > 0.01, "the whistle should add sound")
	_check(vent > 0.01, "the blow-off should add sound")
	for st in [0.3, 1.0]:
		var v := TurboSynth.new()
		v.vent(st)
		var secs := _vent_secs(v)
		print("vent length at strength %.1f: %.2f s" % [st, secs])
		_check(secs >= 0.3 and secs <= 1.0, "vent at strength %.1f should last 0.3-1 s, lasts %.2f" % [st, secs])
	var lift := TurboSynth.new()
	lift.vent(1.0)
	var shift := TurboSynth.new()
	shift.shift_vent(1.0)
	var ls := _vent_secs(lift)
	var ss := _vent_secs(shift)
	print("shift vent %.2f s against a lift vent %.2f s" % [ss, ls])
	_check(ss < ls * 0.75 and ss > 0.15, "a shift vent should be shorter than a lift vent but audible")
	var twice := TurboSynth.new()
	_check(twice.vent(0.8), "the first vent should fire")
	_check(not twice.vent(0.9) and not twice.shift_vent(0.9), "a vent within VENT_GAP of a lift vent is the same event")
	twice.render(int(twice.mix_rate * 0.2))
	_check(twice.vent(0.9), "a vent after VENT_GAP is a new one")
	_check(twice.vents == 2 and twice.shift_vents == 0, "two lift vents, no shift vents: %d / %d" % [twice.vents, twice.shift_vents])
	var upgrade := TurboSynth.new()
	_check(upgrade.shift_vent(0.8), "a shift vent should fire")
	_check(upgrade.vent(0.8), "a lift in the same gap upgrades the shift vent")
	_check(upgrade.vents == 1 and upgrade.shift_vents == 0, "the upgrade is one lift vent: %d / %d" % [upgrade.vents, upgrade.shift_vents])
	_check(_vent_secs(upgrade) > 0.6, "the upgraded vent should be the long one")
	var hold := TurboSynth.new()
	hold.shift_vent(0.8)
	hold.render(int(hold.mix_rate * 0.2))
	_check(hold.shift_vent(0.8) and hold.shift_vents == 2, "a second shift after the gap is its own vent")
	_spool()
	_parts()
	_valves()
	_kinds()
	_lift_ramp()

func _vent_secs(v: TurboSynth) -> float:
	var secs := 0.0
	while v._vent_env > 0.01 and secs < 5.0:
		v._vent_env *= v._vent_decay
		secs += 1.0 / v.mix_rate
	return secs

func _whistle(voice: Dictionary, boost: float) -> PackedFloat32Array:
	var t := TurboSynth.new()
	t.apply_voice(voice)
	t.volume = 1.0
	t.boost = boost
	t.boost_max_bar = 0.7
	t.render(4096)  # let the boost smoothing settle
	var buf := PackedFloat32Array()
	for i in 8:
		for f in t.render(512):
			buf.append(f.x)
	return buf

## Spool at full boost: energy near the partial, none at the mirror-whistle tones.
func _spool() -> void:
	var voice := TurboVoice.build({"part": "medium"})
	var buf := _whistle(voice, 1.0)
	var rate := 44100.0
	var f0: float = voice.hz_low + voice.hz_span
	var main := _tone(buf, f0, rate)
	var partial := _tone(buf, f0 * voice.partial, rate)
	var mirror := maxf(_tone(buf, 1250.0, rate), _tone(buf, 2480.0, rate))
	var gap := _tone(buf, f0 * 1.2, rate)
	print("spool: main %.4f partial %.4f gap %.4f mirror tones %.4f" % [main, partial, gap, mirror])
	_check(partial > gap * 3.0, "spool should carry a second partial")
	_check(main > mirror * 3.0, "spool should sit above the mirror whistle tones")

## Each part whistles at its own pitch: its full-boost tone is strong in its own
## render and weak in the other parts' renders.
func _parts() -> void:
	var rate := 44100.0
	var bufs := {}
	var f0s := {}
	for part in TurboVoice.PARTS:
		var voice := TurboVoice.build({"part": part})
		bufs[part] = _whistle(voice, 1.0)
		f0s[part] = float(voice.hz_low) + float(voice.hz_span)
	var line := "parts:"
	for part in bufs:
		var own: float = _tone(bufs[part], f0s[part], rate)
		line += " %s own %.4f" % [part, own]
		for other in bufs:
			if other == part:
				continue
			var cross: float = _tone(bufs[other], f0s[part], rate)
			_check(own > cross * 3.0, "%s's whistle (%d Hz) should be its own: %.4f against %.4f in %s" % [part, int(f0s[part]), own, cross, other])
	print(line)
	_check(f0s["small"] > f0s["medium"] and f0s["medium"] > f0s["big"], "small should whistle highest, big lowest")
	for part in TurboVoice.PARTS:
		_check(float(TurboVoice.PARTS[part].hz_low) > 2600.0, "%s must stay above the mirror whistle" % part)

## The valves: atmo is brighter than recirc; flutter stutters, the others do not.
func _valves() -> void:
	var out := {}
	for valve in ["recirc", "atmo", "flutter"]:
		var t := TurboSynth.new()
		t.apply_voice(TurboVoice.build({"part": "medium", "valve": valve, "valve_level": 1.0}))
		t.volume = 1.0
		t.vent(1.0)
		var buf := PackedFloat32Array()
		for f in t.render(int(t.mix_rate * 0.3)):
			buf.append(f.x)
		out[valve] = buf
	var rb := _bright(out["recirc"])
	var ab := _bright(out["atmo"])
	var rs := _stutter(out["recirc"])
	var as_ := _stutter(out["atmo"])
	var fs := _stutter(out["flutter"])
	print("valves: bright recirc %.3f atmo %.3f; stutter recirc %.1f atmo %.1f flutter %.1f" % [rb, ab, rs, as_, fs])
	_check(ab > rb * 1.5, "an atmospheric valve should be brighter than a recirculating one")
	_check(fs > maxf(rs, as_) * 3.0 and fs > 6.0, "flutter should stutter, the valves should not")
	for valve in out:
		var rms := 0.0
		for x in out[valve]:
			rms += x * x
		_check(sqrt(rms / out[valve].size()) > 0.01, "%s vent should be audible" % valve)

## The boost setups (TurboVoice.KINDS, C1's boost_kind): a blower whines off
## boost and follows rpm, a plain turbo is silent off boost; the twin beats; the
## sequential's big turbo joins above the handover; the twincharger's blower is
## bypassed in the middle of the rev range.
func _kinds() -> void:
	var rate := 44100.0
	var medium := TurboVoice.for_car("p3_tuner")
	_check(TurboVoice.for_setup(medium, "single") == medium, "the single setup is the car's own voice")
	_check(TurboVoice.for_setup(medium, "twin").get("valve") == "atmo", "a setup keeps the car's valve")
	var single0 := _rms(_setup(medium, "single", 0.0, 0.8))
	var roots0 := _setup(medium, "roots", 0.0, 0.8)
	var roots_lo := _setup(medium, "roots", 0.0, 0.4)
	var hz_hi := 1500.0 * 0.8
	var hz_lo := 1500.0 * 0.4
	print("kinds: single off boost %.4f, roots off boost %.4f; roots tone at %d Hz %.4f / %d Hz %.4f, at 0.4 rpm %.4f / %.4f" % [
			single0, _rms(roots0), int(hz_hi), _tone(roots0, hz_hi, rate), int(hz_lo), _tone(roots0, hz_lo, rate),
			_tone(roots_lo, hz_hi, rate), _tone(roots_lo, hz_lo, rate)])
	_check(single0 < 0.0001, "a plain turbo is silent off boost")
	_check(_rms(roots0) > 0.01, "a Roots blower whines off boost")
	_check(_tone(roots0, hz_hi, rate) > _tone(roots0, hz_lo, rate) * 3.0, "the blower's pitch should follow rpm (0.8)")
	# at 0.4 rpm the 0.8 rpm pitch is the buzz's second harmonic (half the level), so 1.5x
	_check(_tone(roots_lo, hz_lo, rate) > _tone(roots_lo, hz_hi, rate) * 1.5, "the blower's pitch should follow rpm (0.4)")
	var roots := TurboSynth.new()
	roots.apply_voice(TurboVoice.for_setup(medium, "roots"))
	roots.vent(1.0)
	_check(roots._vent_env < 0.01, "a blower has no valve to vent")
	var twin_v := TurboVoice.for_setup(medium, "twin")
	var twin := _setup(medium, "twin", 1.0, 0.8)
	var f0: float = float(twin_v.hz_low) + float(twin_v.hz_span)
	var f1: float = f0 * (1.0 + float(twin_v.detune))
	var small := _setup(TurboVoice.build({"part": "small"}), "single", 1.0, 0.8)
	print("twin: second whistle %.4f against %.4f in a single small turbo" % [_tone(twin, f1, rate), _tone(small, f1, rate)])
	_check(_tone(twin, f1, rate) > _tone(small, f1, rate) * 3.0, "a twin should carry its second, detuned whistle")
	var seq_v := TurboVoice.for_setup(medium, "sequential")
	var big_f: float = float(seq_v.stage2_hz_low) + float(seq_v.stage2_hz_span)
	var seq_lo := _setup(medium, "sequential", 1.0, 0.3)
	var seq_hi := _setup(medium, "sequential", 1.0, 0.9)
	print("sequential: big turbo at %d Hz %.4f below the handover, %.4f above" % [int(big_f), _tone(seq_lo, big_f, rate), _tone(seq_hi, big_f, rate)])
	_check(_tone(seq_hi, big_f, rate) > _tone(seq_lo, big_f, rate) * 3.0, "the sequential's big turbo joins above the handover")
	var tc_v := TurboVoice.for_setup(medium, "twincharger")
	var tc_lo := _setup(medium, "twincharger", 0.5, 0.3)
	var tc_mid := _setup(medium, "twincharger", 0.5, 0.55)
	var tc_hi := _setup(medium, "twincharger", 0.5, 0.8)
	var bmax := float(tc_v.blower_hz_max)
	print("twincharger blower: %.4f at 0.3 rpm, %.4f bypassed at 0.55, %.4f at 0.8" % [_tone(tc_lo, bmax * 0.3, rate), _tone(tc_mid, bmax * 0.55, rate), _tone(tc_hi, bmax * 0.8, rate)])
	_check(_tone(tc_lo, bmax * 0.3, rate) > _tone(tc_mid, bmax * 0.55, rate) * 3.0, "the twincharger's blower is bypassed mid-range")
	_check(_tone(tc_hi, bmax * 0.8, rate) > _tone(tc_mid, bmax * 0.55, rate) * 3.0, "the twincharger's blower is back up top")

func _setup(voice: Dictionary, kind: String, boost: float, rpm: float) -> PackedFloat32Array:
	var t := TurboSynth.new()
	t.apply_voice(TurboVoice.for_setup(voice, kind))
	t.volume = 1.0
	t.boost = boost
	t.rpm_norm = rpm
	t.boost_max_bar = 0.7
	t.render(int(t.mix_rate * 0.5))  # the handover and bypass glide over 0.08 s
	var buf := PackedFloat32Array()
	for i in 8:
		for f in t.render(512):
			buf.append(f.x)
	return buf

func _rms(buf: PackedFloat32Array) -> float:
	var sum := 0.0
	for x in buf:
		sum += x * x
	return sqrt(sum / maxf(buf.size(), 1))

## High-frequency share: the rms of the one-pole high-passed signal over the rms.
func _bright(buf: PackedFloat32Array) -> float:
	var lp := 0.0
	var hi := 0.0
	var all := 0.0
	for x in buf:
		lp += 0.1 * (x - lp)
		hi += (x - lp) * (x - lp)
		all += x * x
	return sqrt(hi / maxf(all, 1.0e-9))

## Amplitude modulation: the loudest 5 ms window over the quietest between 40 and
## 200 ms into the vent (a smooth decay gives about 2, a 20 Hz chop far more).
func _stutter(buf: PackedFloat32Array) -> float:
	var win := 220
	var lo := 1.0e9
	var hi := 0.0
	var i := int(44100 * 0.04)
	while i + win <= int(44100 * 0.2):
		var e := 0.0
		for j in win:
			e += buf[i + j] * buf[i + j]
		lo = minf(lo, e)
		hi = maxf(hi, e)
		i += win
	return sqrt(hi / maxf(lo, 1.0e-12))

## Goertzel magnitude of one frequency.
func _tone(buf: PackedFloat32Array, hz: float, rate: float) -> float:
	var w := TAU * hz / rate
	var c := 2.0 * cos(w)
	var s1 := 0.0
	var s2 := 0.0
	for x in buf:
		var s0 := x + c * s1 - s2
		s2 = s1
		s1 = s0
	return sqrt(s1 * s1 + s2 * s2 - c * s1 * s2) / buf.size()

## A driver easing off the pedal (0.15 s ramp) must vent once; GEVP's one-tick check cannot.
func _lift_ramp() -> void:
	var ea := EngineAudio.new()
	ea._vehicle = PlayerCar.new()
	ea.turbo.boost = 0.8
	var vents := 0
	var thr := 1.0
	for i in 60:
		ea._vehicle.throttle_input = thr
		if ea.lift_off_vent(1.0 / 60.0):
			vents += 1
		thr = maxf(thr - 1.0 / 9.0, 0.0) if i >= 20 else 1.0
	_check(vents == 1, "an eased lift should vent once, vented %d" % vents)
	ea.turbo.boost = 0.1
	ea._lift_vented = false
	ea._since_hot = 0.0
	ea._vehicle.throttle_input = 0.0
	_check(not ea.lift_off_vent(1.0 / 60.0), "a cold boost should not vent")
	ea._vehicle.free()
	ea.free()
	_end("")

func _render(boost: float, vent: bool) -> float:
	var s := TurboSynth.new()
	s.boost = boost
	if vent:
		s.vent(1.0)
	var sum := 0.0
	var n := 0
	for i in 4:
		for f in s.render(512):
			sum += f.x * f.x
			n += 1
	return sqrt(sum / n)

func _go(next: Step) -> void:
	step = next
	step_start = tick

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _end(msg: String) -> bool:
	if msg != "":
		failures.append(msg)
	for f in failures:
		printerr("FAIL: ", f)
	print("turbo: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
