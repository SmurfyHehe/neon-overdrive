class_name CrashSfx
extends RefCounted

# The crash and scrape takes CrashAudio plays (2026-10-09), synthesised: no
# recordings, nothing to license or credit. Rendered once into
# assets/sfx/crash by tools/render_crash_sfx.gd (building all of them in
# GDScript takes about a minute, too long for a boot); CrashAudio falls back to
# building a take here, cached in user://audio_cache, if its file is missing.
# Edit a recipe, then re-render: tests/crash_variety.gd fails while the files
# are older than this script (assets/sfx/crash/recipe_hash.txt).

const MIX_RATE := 32000
const DIR := "res://assets/sfx/crash"
## One-shot lengths, s (each take varies +-12 %).
const SECONDS := {
	"tap_concrete": 0.24,
	"tap_metal": 0.55,
	"tap_car": 0.3,
	"thud_concrete": 0.6,
	"thud_metal": 1.1,
	"thud_car": 0.7,
	"crunch": 1.1,
	"glass": 1.2,
	"debris": 0.95,
	"sparks": 0.6,
	"ground_hit": 0.7,
	"scrape_bite": 0.45,
}

static func path(layer: String) -> String:
	return DIR.path_join(layer + ".wav")

## This script's source hash: what the rendered files were made from.
static func recipe_hash() -> String:
	return "%x" % (load("res://scripts/crash_sfx.gd") as GDScript).source_code.hash()

## One take ("tap_concrete0", "loop_metal5", ...).
static func make(layer: String) -> AudioStreamWAV:
	var r := float(MIX_RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(layer)
	var pname := layer.rstrip("0123456789")
	if pname.begins_with("loop_"):
		var k := int(layer.substr(pname.length()))
		# every take a different length, so two crossfading takes never line up
		var secs := 1.6 + 0.31 * k + rng.randf_range(0.0, 0.12)
		var n := int(secs * r)
		var fade := int(0.15 * r)
		var s := _loop(pname.trim_prefix("loop_"), rng, n + fade)
		return AudioDsp.to_wav(AudioDsp.seamless(AudioDsp.normalise(s, 0.85), n, fade), MIX_RATE, true)
	var secs: float = SECONDS[pname] * rng.randf_range(0.88, 1.12)
	var n := int(secs * r)
	var s := _one_shot(pname, rng, n)
	# a 2 ms fade-in so no take starts on a click, a 30 ms fade-out so none cuts off
	var fade_in := int(0.002 * r)
	for i in fade_in:
		s[i] *= float(i) / fade_in
	var fade_out := int(0.03 * r)
	for i in fade_out:
		s[n - 1 - i] *= float(i) / fade_out
	return AudioDsp.to_wav(AudioDsp.normalise(s, 0.9), MIX_RATE, false)

# ---------- recipes ----------
# Each sound is a few parts built separately (a modal ring, a boom, filtered
# noise, grains), each normalised and then mixed at a set weight, so the
# balance between parts holds for every random take.

static func _one_shot(pname: String, rng: RandomNumberGenerator, n: int) -> PackedFloat32Array:
	var r := float(MIX_RATE)
	match pname:
		"tap_concrete":
			# knuckle on a panel against a hard wall: short knock, tight body
			# modes, a dry tick and a few grit grains off the wall
			var f := rng.randf_range(260.0, 420.0)
			return _mix(n, [
				[_modes(rng, n, [f, f * rng.randf_range(2.1, 2.5), f * rng.randf_range(4.5, 5.2)], [38.0, 52.0, 75.0], [1.0, 0.6, 0.35], 0.003, 6000.0), 0.6],
				[_noise(rng, n, AudioDsp.lp(r, 160.0), 55.0), 0.5],
				[_boom(n, rng.randf_range(90.0, 130.0), 1.0, 0.1, 45.0), 0.4],
				[_grains(rng, n, _times(rng, rng.randi_range(2, 4), 0.0, 0.06, 2.0), 0.001, AudioDsp.hp(r, 2500.0)), 0.35],
			])
		"tap_metal":
			# a knock on a guardrail: the rail rings, the car's panel ticks
			var f := rng.randf_range(230.0, 380.0)
			return _mix(n, [
				[_rail(rng, n, f, 7.0, 0.0015), 0.85],
				[_modes(rng, n, [rng.randf_range(600.0, 900.0)], [60.0], [1.0], 0.002, 5000.0), 0.3],
				[_grains(rng, n, [0.0], 0.001, AudioDsp.hp(r, 3000.0)), 0.25],
			])
		"tap_car":
			# a bumper nudge: plastic crack, a soft panel, a low push
			var f := rng.randf_range(180.0, 300.0)
			return _mix(n, [
				[_noise(rng, n, AudioDsp.bp(r, rng.randf_range(1200.0, 2400.0), 2.5), 70.0), 0.55],
				[_modes(rng, n, [f, f * rng.randf_range(1.9, 2.3), f * rng.randf_range(3.4, 4.0)], [28.0, 34.0, 40.0], [1.0, 0.6, 0.4], 0.004, 4000.0), 0.6],
				[_boom(n, rng.randf_range(70.0, 100.0), 0.85, 0.08, 30.0), 0.5],
			])
		"thud_concrete":
			# the body hitting a wall: a falling low boom, panel modes, dull
			# noise and the wall's surface crumbling
			var modes := []
			for k in 5:
				modes.append(rng.randf_range(200.0, 1300.0))
			return _mix(n, [
				[_boom(n, rng.randf_range(50.0, 75.0), 0.7, 0.2, 11.0), 1.0],
				[_modes(rng, n, modes, _spread(rng, 5, 9.0, 18.0), [1.0, 0.8, 0.6, 0.5, 0.4], rng.randf_range(0.006, 0.012), 4000.0), 0.7],
				[_noise(rng, n, AudioDsp.lp(r, 300.0), 15.0), 0.6],
				[_grains(rng, n, _times(rng, rng.randi_range(15, 35), 0.0, 0.25, 2.0), 0.0015, AudioDsp.hp(r, 1500.0)), 0.35],
			])
		"thud_metal":
			# into a guardrail: a big clang that rings on, the body boom
			# under it, and the rail rattling on its posts
			var f := rng.randf_range(140.0, 240.0)
			var panel := []
			for k in 4:
				panel.append(rng.randf_range(250.0, 1100.0))
			return _mix(n, [
				[_rail(rng, n, f, 3.5, rng.randf_range(0.003, 0.006)), 0.9],
				[_boom(n, rng.randf_range(55.0, 75.0), 0.75, 0.2, 12.0), 0.7],
				[_modes(rng, n, panel, _spread(rng, 4, 12.0, 16.0), [1.0, 0.7, 0.5, 0.4], 0.008, 4000.0), 0.4],
				[_grains(rng, n, _times(rng, rng.randi_range(3, 6), 0.02, 0.09, 1.0), 0.002, AudioDsp.bp(r, rng.randf_range(1500.0, 2500.0), 8.0)), 0.25],
			])
		"thud_car":
			# two cars meeting: boom, both cars' panels, plastic cracking
			var a := []
			var b := []
			for k in 3:
				a.append(rng.randf_range(200.0, 700.0))
				b.append(rng.randf_range(350.0, 1400.0))
			return _mix(n, [
				[_boom(n, rng.randf_range(60.0, 85.0), 0.72, 0.18, 12.0), 0.9],
				[_modes(rng, n, a, _spread(rng, 3, 12.0, 20.0), [1.0, 0.7, 0.5], 0.008, 3500.0), 0.6],
				[_modes(rng, n, b, _spread(rng, 3, 15.0, 25.0), [1.0, 0.7, 0.5], 0.006, 5000.0), 0.5],
				[_grains(rng, n, _times(rng, rng.randi_range(2, 4), 0.0, 0.04, 1.0), 0.004, AudioDsp.bp(r, rng.randf_range(1500.0, 3000.0), 3.0)), 0.4],
				[_noise(rng, n, AudioDsp.lp(r, 400.0), 18.0), 0.4],
			])
		"crunch":
			# crumpling metal: a burst of grains, thinning out, rung through
			# metal resonances that sag as the panel folds; plastic snapping;
			# a low boom
			var crumple := _crumple(rng, n)
			return _mix(n, [
				[crumple[0], 1.0],
				[crumple[1], 0.25],
				[_grains(rng, n, _times(rng, rng.randi_range(3, 6), 0.0, 0.5, 1.5), 0.003, AudioDsp.bp(r, rng.randf_range(1500.0, 4000.0), 3.0)), 0.45],
				[_boom(n, rng.randf_range(42.0, 55.0), 0.85, 0.3, 9.0), 0.6],
			])
		"glass":
			# glass going: the crack, a bright shatter, pieces tinkling down,
			# some of them bouncing
			var times: Array[float] = []
			var freqs: Array[float] = []
			var decays: Array[float] = []
			var amps: Array[float] = []
			for k in rng.randi_range(25, 50):
				var t := 0.015 + (-log(maxf(rng.randf(), 1e-4))) * 0.16
				times.append(t)
				freqs.append(rng.randf_range(2500.0, 9000.0))
				decays.append(rng.randf_range(25.0, 70.0))
				amps.append(rng.randf_range(0.3, 1.0) * exp(-t * 2.0))
			for k in rng.randi_range(4, 8):
				_bounces(rng, times, freqs, decays, amps, rng.randf_range(0.05, 0.3), rng.randf_range(3000.0, 8000.0), rng.randf_range(30.0, 60.0), rng.randi_range(2, 3))
			return _mix(n, [
				[_noise(rng, n, AudioDsp.hp(r, 1500.0), 60.0), 0.6],
				[_noise(rng, n, AudioDsp.hp(r, 2500.0), 18.0, 0.005), 0.7],
				[_pings(n, times, freqs, decays, amps), 0.7],
			])
		"debris":
			# trim and plastic bits landing and bouncing on the road, a
			# moment after the hit
			var delay := rng.randf_range(0.03, 0.12)
			var times: Array[float] = []
			var freqs: Array[float] = []
			var decays: Array[float] = []
			var amps: Array[float] = []
			for k in rng.randi_range(3, 6):
				var metal := rng.randf() < 0.4
				_bounces(rng, times, freqs, decays, amps, delay + rng.randf_range(0.0, 0.12),
					rng.randf_range(2000.0, 5500.0) if metal else rng.randf_range(700.0, 1800.0),
					rng.randf_range(20.0, 35.0) if metal else rng.randf_range(40.0, 70.0), rng.randi_range(2, 5))
			var sorted := times.duplicate()
			sorted.sort()
			var clicks := _grains(rng, n, sorted, 0.003, AudioDsp.bp(r, rng.randf_range(1500.0, 3500.0), 1.5))
			return _mix(n, [
				[_pings(n, times, freqs, decays, amps), 0.7],
				[clicks, 0.5],
				[_grains(rng, n, _times(rng, rng.randi_range(10, 20), delay + 0.05, 0.5, 1.0), 0.0008, AudioDsp.hp(r, 3000.0)), 0.25],
			])
		"sparks":
			# a shower of sparks: dense crackle thinning out, a hiss under it
			var rate := rng.randf_range(2500.0, 4000.0)
			var fall := rng.randf_range(4.0, 7.0)
			return _mix(n, [
				[_crackle(rng, n, rate, fall, AudioDsp.hp(r, 2500.0)), 1.0],
				[_crackle(rng, n, rate * 0.5, fall, AudioDsp.bp(r, rng.randf_range(5000.0, 8000.0), 1.5)), 0.5],
				[_noise(rng, n, AudioDsp.hp(r, 5000.0), 6.0, 0.01), 0.25],
			])
		"ground_hit":
			# the floor pan slamming onto the road: a sub thump, the chassis
			# banging, a short grind, the heat shield rattling
			var modes := []
			for k in 4:
				modes.append(rng.randf_range(120.0, 500.0))
			var tick_hz := rng.randf_range(1500.0, 2600.0)
			var times := _times(rng, rng.randi_range(4, 8), 0.03, 0.35, 1.3)
			var freqs: Array[float] = []
			var decays: Array[float] = []
			var amps: Array[float] = []
			for t in times:
				freqs.append(tick_hz * rng.randf_range(0.98, 1.02))
				decays.append(50.0)
				amps.append(rng.randf_range(0.4, 1.0) * exp(-t * 4.0))
			return _mix(n, [
				[_boom(n, rng.randf_range(35.0, 55.0), 0.8, 0.15, 13.0), 1.0],
				[_modes(rng, n, modes, _spread(rng, 4, 12.0, 22.0), [1.0, 0.8, 0.6, 0.5], 0.01, 2000.0), 0.7],
				[_grind(rng, n, 0.25, rng.randf_range(500.0, 1200.0)), 0.45],
				[_pings(n, times, freqs, decays, amps), 0.25],
			])
		"scrape_bite":
			# the moment metal catches: a screech whose stick-slip speeds up,
			# then lets go
			var res: Array[AudioDsp.Biquad] = []
			for k in 3:
				res.append(AudioDsp.bp(r, rng.randf_range(900.0, 3000.0), rng.randf_range(18.0, 30.0)))
			var s := _buf(n)
			var env := 0.0
			var wait := 0
			for i in n:
				var t := float(i) / r
				wait -= 1
				if wait <= 0:
					env = rng.randf_range(0.5, 1.0)
					wait = int(lerpf(0.012, 0.003, minf(t / 0.2, 1.0)) * r * rng.randf_range(0.7, 1.3))
				env *= 0.998
				var x := rng.randf_range(-1.0, 1.0) * env * minf(t / 0.005, 1.0) * exp(-t * 6.0)
				var v := 0.0
				for f in res:
					v += f.step(x)
				s[i] = v
			return _mix(n, [
				[s, 1.0],
				[_noise(rng, n, AudioDsp.hp(r, 2500.0), 8.0, 0.005), 0.3],
			])
	push_error("CrashSfx: no recipe for %s" % pname)
	return _buf(n)

## Scrape loops, `n` samples (the caller crossfades the tail into the head).
static func _loop(kind: String, rng: RandomNumberGenerator, n: int) -> PackedFloat32Array:
	var r := float(MIX_RATE)
	match kind:
		"concrete":
			# panel grinding along concrete: dense abrasive grit, the body
			# resonating in stick-slip bursts, a rough low rumble
			return _mix(n, [
				[_crackle(rng, n, rng.randf_range(2000.0, 3500.0), 0.0, AudioDsp.bp(r, 3000.0, 0.7)), 0.55],
				[_stick_slip(rng, n, 0.008, 0.025, [[rng.randf_range(350.0, 500.0), 6.0], [rng.randf_range(800.0, 1100.0), 8.0], [rng.randf_range(1600.0, 2100.0), 8.0]], 0.0), 0.8],
				[_rumble(rng, n, 140.0), 0.5],
				[_noise(rng, n, AudioDsp.hp(r, 4000.0), 0.0), 0.12],
			])
		"metal":
			# metal on a guardrail: a screech of hard, wobbling resonances,
			# grit, and the rail's joints knocking past
			var joints := _times(rng, int(n / r / 0.5) + 1, 0.1, n / r - 0.1, 1.0)
			var thunks := PackedFloat32Array()
			thunks.resize(n)
			var f := rng.randf_range(200.0, 320.0)
			for t in joints:
				var part := _rail(rng, mini(int(0.25 * r), n - int(t * r)), f * rng.randf_range(0.97, 1.03), 12.0, 0.002)
				var at := int(t * r)
				for i in part.size():
					thunks[at + i] += part[i]
			return _mix(n, [
				[_stick_slip(rng, n, 0.002, 0.008, [[rng.randf_range(900.0, 1400.0), 25.0], [rng.randf_range(1700.0, 2500.0), 30.0], [rng.randf_range(2800.0, 3800.0), 35.0]], 0.025), 1.0],
				[_noise(rng, n, AudioDsp.hp(r, 2500.0), 0.0), 0.25],
				[thunks, 0.35],
				[_rumble(rng, n, 200.0), 0.25],
			])
		"car":
			# two cars rubbing: soft panels in slow stick-slip, plastic rub,
			# the odd creak, a low rumble
			var creak := PackedFloat32Array()
			creak.resize(n)
			var cres := AudioDsp.bp(r, rng.randf_range(500.0, 800.0), 5.0)
			var t0 := rng.randf_range(0.1, 0.5)
			var bursts := []
			while t0 < n / r - 0.2:
				bursts.append([t0, rng.randf_range(0.06, 0.15), rng.randf_range(35.0, 70.0)])
				t0 += rng.randf_range(0.4, 1.0)
			for i in n:
				var t := float(i) / r
				var x := 0.0
				for b in bursts:
					if t >= b[0] and t < b[0] + b[1] and fmod(t - b[0], 1.0 / b[2]) < 1.0 / r:
						x = 1.0
				creak[i] = cres.step(x)
			return _mix(n, [
				[_stick_slip(rng, n, 0.01, 0.035, [[rng.randf_range(250.0, 450.0), 6.0], [rng.randf_range(600.0, 900.0), 7.0], [rng.randf_range(1100.0, 1500.0), 8.0]], 0.0), 0.9],
				[_modulated(rng, n, AudioDsp.bp(r, rng.randf_range(1800.0, 2800.0), 1.2)), 0.35],
				[creak, 0.4],
				[_rumble(rng, n, 150.0), 0.3],
			])
		"underbody":
			# the floor pan grinding on asphalt: a heavy rumble, a grind, grit,
			# the odd clunk
			var clunk_t := _times(rng, int(n / r / 0.45) + 1, 0.05, n / r - 0.1, 1.0)
			var freqs: Array[float] = []
			var decays: Array[float] = []
			var amps: Array[float] = []
			for t in clunk_t:
				freqs.append(rng.randf_range(120.0, 260.0))
				decays.append(18.0)
				amps.append(rng.randf_range(0.5, 1.0))
			return _mix(n, [
				[_rumble(rng, n, 220.0), 1.0],
				[_stick_slip(rng, n, 0.006, 0.02, [[rng.randf_range(350.0, 700.0), 4.0], [rng.randf_range(900.0, 1400.0), 6.0]], 0.0), 0.6],
				[_crackle(rng, n, rng.randf_range(1500.0, 2500.0), 0.0, AudioDsp.hp(r, 2000.0)), 0.4],
				[_pings(n, clunk_t, freqs, decays, amps), 0.35],
			])
		"sparks":
			# a steady stream of sparks: crackle in clusters, a hiss
			return _mix(n, [
				[_crackle(rng, n, rng.randf_range(900.0, 1500.0), 0.0, AudioDsp.hp(r, 3000.0), true), 1.0],
				[_crackle(rng, n, rng.randf_range(400.0, 700.0), 0.0, AudioDsp.bp(r, 7000.0, 1.5), true), 0.4],
				[_noise(rng, n, AudioDsp.hp(r, 5000.0), 0.0), 0.2],
			])
	push_error("CrashSfx: no loop recipe for %s" % kind)
	return _buf(n)

# ---------- parts ----------

static func _buf(n: int) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(n)
	return s

## Normalises each part to the same peak and sums them at their weights.
## parts: [[samples, weight], ...]
static func _mix(n: int, parts: Array) -> PackedFloat32Array:
	var s := _buf(n)
	for part in parts:
		var p: PackedFloat32Array = AudioDsp.normalise(part[0], 1.0)
		var w: float = part[1]
		for i in mini(n, p.size()):
			s[i] += p[i] * w
	return s

## Random times in [from, to], bunched towards `from` when skew > 1, sorted.
static func _times(rng: RandomNumberGenerator, count: int, from: float, to: float, skew: float) -> Array[float]:
	var out: Array[float] = []
	for k in count:
		out.append(from + (to - from) * pow(rng.randf(), skew))
	out.sort()
	return out

## count decay rates spread from lo to hi, each nudged a little.
static func _spread(rng: RandomNumberGenerator, count: int, lo: float, hi: float) -> Array:
	var out := []
	for k in count:
		out.append(lerpf(lo, hi, float(k) / maxf(count - 1, 1)) * rng.randf_range(0.85, 1.15))
	return out

## A struck object: modes at `freqs` (decay per second, amplitude) rung by a
## noise burst `excite` seconds long, low-passed at `soft` Hz (lower = a
## softer strike).
static func _modes(rng: RandomNumberGenerator, n: int, freqs: Array, decays: Array, amps: Array, excite: float, soft: float) -> PackedFloat32Array:
	var r := float(MIX_RATE)
	var bank: Array[AudioDsp.Reso] = []
	for k in freqs.size():
		bank.append(AudioDsp.reso(r, freqs[k] * rng.randf_range(0.98, 1.02), decays[k]))
	var lp := AudioDsp.lp(r, soft)
	var ex := int(excite * r)
	var s := _buf(n)
	for i in n:
		var x := lp.step(rng.randf_range(-1.0, 1.0) * (1.0 - float(i) / ex)) if i < ex else 0.0
		var v := 0.0
		for k in bank.size():
			v += bank[k].step(x) * float(amps[k])
		s[i] = v
	return s

## A W-beam guardrail struck at fundamental f: inharmonic plate-like modes,
## each with a slightly detuned twin so the ring beats and shimmers.
static func _rail(rng: RandomNumberGenerator, n: int, f: float, decay: float, excite: float) -> PackedFloat32Array:
	var ratios := [1.0, 2.32, 2.76, 4.07, 5.4, 6.9, 8.3, 9.9]
	var freqs := []
	var decays := []
	var amps := []
	for k in ratios.size():
		var hz: float = f * ratios[k] * rng.randf_range(0.97, 1.03)
		var d: float = decay * (1.0 + 0.3 * k) * rng.randf_range(0.85, 1.15)
		var a := pow(0.75, k) * rng.randf_range(0.7, 1.0)
		freqs.append_array([hz, hz + rng.randf_range(1.0, 3.0)])
		decays.append_array([d, d * 1.1])
		amps.append_array([a, a * 0.7])
	return _modes(rng, n, freqs, decays, amps, excite, 8000.0)

## A low sine falling from hz to hz * fall over `glide` s, dying at `decay`.
static func _boom(n: int, hz: float, fall: float, glide: float, decay: float) -> PackedFloat32Array:
	var r := float(MIX_RATE)
	var s := _buf(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / r
		ph += TAU * hz * lerpf(1.0, fall, minf(t / glide, 1.0)) / r
		s[i] = sin(ph) * exp(-t * decay)
	return s

## Noise through `filter`, dying at `decay` per second (0 = steady), with a
## linear attack of `attack` s.
static func _noise(rng: RandomNumberGenerator, n: int, filter: AudioDsp.Biquad, decay: float, attack := 0.0) -> PackedFloat32Array:
	var r := float(MIX_RATE)
	var s := _buf(n)
	for i in n:
		var t := float(i) / r
		var env := exp(-t * decay) * (minf(t / attack, 1.0) if attack > 0.0 else 1.0)
		s[i] = filter.step(rng.randf_range(-1.0, 1.0)) * env
	return s

## Noise through `filter` with its level wandering slowly (rubbing, rumble).
static func _modulated(rng: RandomNumberGenerator, n: int, filter: AudioDsp.Biquad) -> PackedFloat32Array:
	var r := float(MIX_RATE)
	var s := _buf(n)
	var level := 0.6
	var goal := 0.6
	var wait := 0
	for i in n:
		wait -= 1
		if wait <= 0:
			goal = rng.randf_range(0.3, 1.0)
			wait = int(rng.randf_range(0.05, 0.15) * r)
		level += (goal - level) * 0.0008
		s[i] = filter.step(rng.randf_range(-1.0, 1.0)) * level
	return s

static func _rumble(rng: RandomNumberGenerator, n: int, hz: float) -> PackedFloat32Array:
	return _modulated(rng, n, AudioDsp.lp(float(MIX_RATE), hz))

## Short clicks of filtered noise, `len` s each, at `times`, louder early.
static func _grains(rng: RandomNumberGenerator, n: int, times: Array, glen: float, filter: AudioDsp.Biquad) -> PackedFloat32Array:
	var r := float(MIX_RATE)
	var s := _buf(n)
	var g := 0
	var env := 0.0
	var fall := exp(-1.0 / (glen * r))
	for i in n:
		var t := float(i) / r
		while g < times.size() and float(times[g]) <= t:
			env = maxf(env, rng.randf_range(0.5, 1.0) * exp(-float(times[g]) * 3.0))
			g += 1
		env *= fall
		s[i] = filter.step(rng.randf_range(-1.0, 1.0) * env)
	return s

## Random impulses at `rate` per second (falling at `fall` per second), of
## random size, through `filter`: sparks, grit. `clusters` bunches them.
static func _crackle(rng: RandomNumberGenerator, n: int, rate: float, fall: float, filter: AudioDsp.Biquad, clusters := false) -> PackedFloat32Array:
	var r := float(MIX_RATE)
	var s := _buf(n)
	var bunch := 1.0
	var wait := 0
	for i in n:
		var t := float(i) / r
		if clusters:
			wait -= 1
			if wait <= 0:
				bunch = rng.randf_range(0.2, 1.8)
				wait = int(rng.randf_range(0.03, 0.12) * r)
		var x := 0.0
		if rng.randf() < rate * bunch * exp(-t * fall) / r:
			x = rng.randf_range(-1.0, 1.0) * pow(rng.randf(), 2.0)
		s[i] = filter.step(x)
	return s

## Friction: noise gated by stick-slip bursts (a new grip level every
## slip_lo..slip_hi s) driving resonances [[hz, q], ...]. `wobble` sways
## their pitch by that fraction, so the screech is never quite still.
static func _stick_slip(rng: RandomNumberGenerator, n: int, slip_lo: float, slip_hi: float, res: Array, wobble: float) -> PackedFloat32Array:
	var r := float(MIX_RATE)
	var bank: Array[AudioDsp.Biquad] = []
	var gains := [1.0, 0.8, 0.5, 0.4]
	var rates := []
	var phases := []
	for k in res.size():
		bank.append(AudioDsp.bp(r, res[k][0], res[k][1]))
		rates.append(rng.randf_range(0.3, 1.2))
		phases.append(rng.randf_range(0.0, TAU))
	var grit := AudioDsp.hp(r, 2500.0)
	var s := _buf(n)
	var env := 0.0
	var wait := 0
	for i in n:
		if wobble > 0.0 and i % 256 == 0:
			var t := float(i) / r
			for k in bank.size():
				bank[k].set_bp(r, res[k][0] * (1.0 + wobble * sin(TAU * rates[k] * t + phases[k])), res[k][1])
		var w := rng.randf_range(-1.0, 1.0)
		wait -= 1
		if wait <= 0:
			env = rng.randf_range(0.5, 1.0)
			wait = int(rng.randf_range(slip_lo, slip_hi) * r)
		env *= 0.999
		var x := w * (0.35 + 0.65 * env)
		var v := 0.0
		for k in bank.size():
			v += float(gains[k]) * bank[k].step(x)
		s[i] = v + 0.12 * grit.step(w)
	return s

## A grind over the first `secs`: stick-slip noise through a band at hz.
static func _grind(rng: RandomNumberGenerator, n: int, secs: float, hz: float) -> PackedFloat32Array:
	var r := float(MIX_RATE)
	var band := AudioDsp.bp(r, hz, 3.0)
	var grit := AudioDsp.hp(r, 2500.0)
	var s := _buf(n)
	var env := 0.0
	var wait := 0
	for i in n:
		var t := float(i) / r
		wait -= 1
		if wait <= 0:
			env = rng.randf_range(0.4, 1.0)
			wait = int(rng.randf_range(0.004, 0.015) * r)
		var w := rng.randf_range(-1.0, 1.0) * env * clampf(1.0 - t / secs, 0.0, 1.0)
		s[i] = band.step(w) + 0.3 * grit.step(w)
	return s

## Crumpling metal: grains, thinning out, through four to six resonances
## that sag 8-15 % as the panel folds. Returns [ringing, grit].
static func _crumple(rng: RandomNumberGenerator, n: int) -> Array:
	var r := float(MIX_RATE)
	var secs := n / r
	var res: Array[AudioDsp.Biquad] = []
	var hz := []
	var qs := []
	for k in rng.randi_range(4, 6):
		hz.append(rng.randf_range(400.0, 3500.0))
		qs.append(rng.randf_range(10.0, 25.0))
		res.append(AudioDsp.bp(r, hz[k], qs[k]))
	var sag := rng.randf_range(0.08, 0.15)
	var grit := AudioDsp.hp(r, 1800.0)
	var grains: Array[float] = []
	var tt := 0.0
	while tt < secs * 0.7:
		grains.append(tt)
		tt += rng.randf_range(0.004, 0.02) * (1.0 + tt * 12.0)
	var ring := _buf(n)
	var gs := _buf(n)
	var g := 0
	var excite := 0.0
	for i in n:
		var t := float(i) / r
		if i % 64 == 0:
			var k := 1.0 - sag * minf(t / (secs * 0.6), 1.0)
			for j in res.size():
				res[j].set_bp(r, hz[j] * k, qs[j])
		while g < grains.size() and grains[g] <= t:
			excite = maxf(excite, rng.randf_range(0.5, 1.0) * exp(-grains[g] * 3.0))
			g += 1
		excite *= 0.996
		var w := rng.randf_range(-1.0, 1.0) * excite
		var v := 0.0
		for f in res:
			v += f.step(w)
		ring[i] = v
		gs[i] = grit.step(w)
	return [ring, gs]

## Adds a piece bouncing: `count` hits from t0, each gap and level shrinking.
static func _bounces(rng: RandomNumberGenerator, times: Array[float], freqs: Array[float], decays: Array[float], amps: Array[float], t0: float, hz: float, decay: float, count: int) -> void:
	var t := t0
	var gap := rng.randf_range(0.08, 0.16)
	var a := rng.randf_range(0.6, 1.0)
	for k in count:
		times.append(t)
		freqs.append(hz * rng.randf_range(0.97, 1.03))
		decays.append(decay)
		amps.append(a)
		t += gap
		gap *= rng.randf_range(0.55, 0.7)
		a *= rng.randf_range(0.45, 0.65)

## Struck pings: a decaying sine per entry, written straight into the buffer.
static func _pings(n: int, times: Array, freqs: Array, decays: Array, amps: Array) -> PackedFloat32Array:
	var r := float(MIX_RATE)
	var s := _buf(n)
	for k in times.size():
		var at := int(float(times[k]) * r)
		var d: float = decays[k]
		var w: float = TAU * minf(float(freqs[k]), r * 0.45) / r
		var a: float = amps[k]
		var plen := mini(int(7.0 / d * r), n - at)   # until it is ~0.1 %
		for i in maxi(plen, 0):
			s[at + i] += sin(w * i) * a * exp(-float(i) / r * d)
	return s
