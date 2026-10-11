class_name CrashSfx
extends RefCounted

# The crash and scrape takes CrashAudio plays (2026-10-09; the hits rebuilt
# heavier 2026-10-11, tests/audio/crash_timbre.gd holds them to it), synthesised: no
# recordings, nothing to license or credit. Rendered once into
# assets/sfx/crash by tools/render_crash_sfx.gd (building all of them in
# GDScript takes about a minute, too long for a boot); CrashAudio falls back to
# building a take here, cached in user://audio_cache, if its file is missing.
# Edit a recipe, then re-render: tests/audio/crash_variety.gd fails while the files
# are older than this script (assets/sfx/crash/recipe_hash.txt).

const MIX_RATE := 32000
const DIR := "res://assets/sfx/crash"
## One-shot lengths, s (each take varies +-12 %; a tail is 0.5-1.5 s).
const SECONDS := {
	"tap_concrete": 0.3,
	"tap_metal": 0.55,
	"tap_car": 0.34,
	"thud_concrete": 0.9,
	"thud_metal": 1.1,
	"thud_car": 0.95,
	"crunch": 1.7,
	"smash": 2.05,
	"glass": 1.2,
	"debris": 1.4,
	"sparks": 0.6,
	"ground_hit": 0.9,
	"scrape_bite": 0.45,
	"tail": 1.0,
}
## Soft clip (tanh) on the heavy hits before the final normalise: how hard
## each is driven. It thickens the hit and puts harmonics of the low body
## where small speakers can play them.
const DRIVE := {
	"thud_concrete": 2.5,
	"thud_metal": 2.2,
	"thud_car": 2.5,
	"crunch": 3.0,
	"smash": 3.5,
	"ground_hit": 2.5,
}

static func path(layer: String) -> String:
	return DIR.path_join(layer + ".wav")

## This script's source hash: what the rendered files were made from.
static func recipe_hash() -> String:
	return "%x" % (load("res://scripts/audio/crash_sfx.gd") as GDScript).source_code.hash()

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
	if pname == "tail":
		secs = rng.randf_range(0.5, 1.5)
	var n := int(secs * r)
	var s := _one_shot(pname, rng, n)
	if DRIVE.has(pname):
		s = _saturate(s, DRIVE[pname])
	# a 2 ms fade-in so no take starts on a click, a 30 ms fade-out so none cuts off
	var fade_in := int(0.002 * r)
	for i in fade_in:
		s[i] *= float(i) / fade_in
	var fade_out := int(0.03 * r)
	for i in fade_out:
		s[n - 1 - i] *= float(i) / fade_out
	return AudioDsp.to_wav(AudioDsp.normalise(s, 0.9), MIX_RATE, false)

# ---------- recipes ----------
# Each sound is a few parts built separately (a noise body, a panel of many
# modes, a sub, filtered noise, grains), each normalised and then mixed at a
# set weight, so the balance between parts holds for every random take.
#
# What makes a hit heavy on small speakers (2026-10-11, Roy: crashes "sound
# like Lego"): the weight is a noise body at 100-280 Hz, not a sine sub nobody
# with a laptop hears; a panel is dozens of short-lived modes struck by a
# 15-40 ms shove, not a handful of clean ones struck by a click (that is hard
# plastic); and the heavy hits are soft-clipped (DRIVE).

static func _one_shot(pname: String, rng: RandomNumberGenerator, n: int) -> PackedFloat32Array:
	var r := float(MIX_RATE)
	match pname:
		"tap_concrete":
			# a panel knocked against a hard wall: a short dull knock, a small
			# body thump and a few grit grains off the wall
			return _mix(n, [
				[_panel(rng, n, 16, rng.randf_range(220.0, 320.0), 3500.0, 32.0, 75.0, rng.randf_range(0.008, 0.015), 4500.0, 0.6), 0.7],
				[_body(rng, n, 130.0, 280.0, rng.randf_range(26.0, 34.0)), 0.6],
				[_boom(n, rng.randf_range(90.0, 130.0), 1.0, 0.1, 45.0), 0.13],
				[_grains(rng, n, _times(rng, rng.randi_range(2, 4), 0.0, 0.06, 2.0), 0.001, AudioDsp.hp(r, 2500.0)), 0.3],
			])
		"tap_metal":
			# a knock on a guardrail: the rail rings, the car's panel thumps
			var f := rng.randf_range(230.0, 380.0)
			return _mix(n, [
				[_rail(rng, n, f, 7.0, 0.0015), 0.85],
				[_panel(rng, n, 12, 400.0, 3000.0, 40.0, 80.0, 0.006, 5000.0, 0.5), 0.3],
				[_body(rng, n, 150.0, 300.0, rng.randf_range(26.0, 34.0)), 0.3],
				[_grains(rng, n, [0.0], 0.001, AudioDsp.hp(r, 3000.0)), 0.25],
			])
		"tap_car":
			# a bumper nudge: plastic crack, a soft panel, a low push
			return _mix(n, [
				[_noise(rng, n, AudioDsp.bp(r, rng.randf_range(1200.0, 2400.0), 2.5), 70.0), 0.5],
				[_panel(rng, n, 14, rng.randf_range(170.0, 240.0), 2500.0, 26.0, 50.0, rng.randf_range(0.01, 0.016), 3500.0, 0.7), 0.65],
				[_body(rng, n, 120.0, 250.0, rng.randf_range(20.0, 28.0)), 0.55],
				[_boom(n, rng.randf_range(70.0, 100.0), 0.85, 0.08, 30.0), 0.17],
			])
		"thud_concrete":
			# the body hitting a wall: a heavy noise thump, a sub under it, the
			# panels banging and the wall's surface crumbling
			return _mix(n, [
				[_body(rng, n, 125.0, 270.0, rng.randf_range(6.0, 10.0)), 1.0],
				[_boom(n, rng.randf_range(50.0, 75.0), 0.7, 0.2, 11.0), 0.33],
				[_panel(rng, n, rng.randi_range(30, 44), 150.0, 4000.0, 12.0, 40.0, rng.randf_range(0.015, 0.04), 4000.0, 0.8), 0.8],
				[_grains(rng, n, _times(rng, rng.randi_range(15, 35), 0.0, 0.25, 2.0), 0.0015, AudioDsp.hp(r, 1500.0)), 0.35],
			])
		"thud_metal":
			# into a guardrail: a big clang that rings on, the body thump
			# under it, the car's panels, and the rail rattling on its posts
			var f := rng.randf_range(140.0, 240.0)
			return _mix(n, [
				[_rail(rng, n, f, 3.5, rng.randf_range(0.003, 0.006)), 0.8],
				[_body(rng, n, 125.0, 270.0, rng.randf_range(7.0, 10.0)), 0.85],
				[_boom(n, rng.randf_range(55.0, 75.0), 0.75, 0.2, 12.0), 0.23],
				[_panel(rng, n, rng.randi_range(24, 32), 200.0, 4000.0, 12.0, 36.0, rng.randf_range(0.015, 0.03), 4000.0, 0.6), 0.45],
				[_grains(rng, n, _times(rng, rng.randi_range(3, 6), 0.02, 0.09, 1.0), 0.002, AudioDsp.bp(r, rng.randf_range(1500.0, 2500.0), 8.0)), 0.25],
			])
		"thud_car":
			# two cars meeting: the thump, the panels of both, plastic cracking
			return _mix(n, [
				[_body(rng, n, 120.0, 250.0, rng.randf_range(6.0, 9.0)), 0.95],
				[_boom(n, rng.randf_range(60.0, 85.0), 0.72, 0.18, 12.0), 0.3],
				[_panel(rng, n, rng.randi_range(24, 32), 150.0, 2500.0, 12.0, 32.0, rng.randf_range(0.02, 0.04), 3000.0, 0.9), 0.65],
				[_panel(rng, n, rng.randi_range(20, 28), 300.0, 4000.0, 16.0, 40.0, rng.randf_range(0.015, 0.03), 5000.0, 0.5), 0.45],
				[_grains(rng, n, _times(rng, rng.randi_range(2, 4), 0.0, 0.04, 1.0), 0.004, AudioDsp.bp(r, rng.randf_range(1500.0, 3000.0), 3.0)), 0.4],
			])
		"crunch":
			# crumpling metal: a burst of grains with a few loud buckles in
			# it, thinning into creaks, rung through sagging metal resonances
			# and a low fold; plastic snapping; the body thump
			var c := _crumple(rng, n)
			return _mix(n, [
				[c[0], 1.0],
				[c[1], 0.25],
				[c[2], 0.85],
				[c[3], 0.2],
				[_grains(rng, n, _times(rng, rng.randi_range(3, 6), 0.0, 0.5, 1.5), 0.003, AudioDsp.bp(r, rng.randf_range(1500.0, 4000.0), 3.0)), 0.4],
				[_body(rng, n, 110.0, 250.0, rng.randf_range(6.0, 8.0)), 0.7],
				[_boom(n, rng.randf_range(42.0, 55.0), 0.85, 0.3, 9.0), 0.2],
			])
		"smash":
			# a highway-speed hit: two crumples a moment apart (the nose, then
			# what is behind it), a bigger and longer body, every panel at once
			var a := _crumple(rng, n)
			var b := _crumple(rng, n)
			var off := int(rng.randf_range(0.04, 0.09) * r)
			for k in 4:
				var pa: PackedFloat32Array = AudioDsp.normalise(a[k], 1.0)
				var pb: PackedFloat32Array = AudioDsp.normalise(b[k], 1.0)
				for i in range(off, n):
					pa[i] += pb[i - off] * 0.85
				a[k] = pa
			return _mix(n, [
				[a[0], 1.0],
				[a[1], 0.25],
				[a[2], 0.9],
				[a[3], 0.2],
				[_grains(rng, n, _times(rng, rng.randi_range(5, 9), 0.0, 0.7, 1.5), 0.003, AudioDsp.bp(r, rng.randf_range(1500.0, 4000.0), 3.0)), 0.4],
				[_body(rng, n, 100.0, 240.0, rng.randf_range(4.5, 6.0), 0.008), 0.95],
				[_panel(rng, n, 48, 150.0, 4000.0, 10.0, 34.0, 0.04, 4500.0, 0.8), 0.6],
				[_boom(n, rng.randf_range(38.0, 50.0), 0.8, 0.35, 7.0), 0.25],
			])
		"glass":
			# glass going: a low pop as the pane lets go, the crack, a bright
			# shatter, shards (half of them ring, half only tick) tinkling
			# down, some of them bouncing
			var times: Array[float] = []
			var freqs: Array[float] = []
			var decays: Array[float] = []
			var amps: Array[float] = []
			var ticks := _buf(n)
			for k in rng.randi_range(25, 50):
				var t := 0.015 + (-log(maxf(rng.randf(), 1e-4))) * 0.16
				var amp := rng.randf_range(0.3, 1.0) * exp(-t * 2.0)
				if k % 2 == 0:
					_clack(rng, ticks, t, rng.randf_range(2000.0, 6000.0), rng.randf_range(2.0, 5.0), rng.randf_range(0.002, 0.01), amp)
					continue
				times.append(t)
				freqs.append(rng.randf_range(2500.0, 9000.0))
				decays.append(rng.randf_range(25.0, 70.0))
				amps.append(amp)
			for k in rng.randi_range(4, 8):
				_bounces(rng, times, freqs, decays, amps, rng.randf_range(0.05, 0.3), rng.randf_range(3000.0, 8000.0), rng.randf_range(30.0, 60.0), rng.randi_range(2, 3))
			var pop := _buf(n)
			_clack(rng, pop, rng.randf_range(0.004, 0.012), rng.randf_range(300.0, 600.0), 2.0, 0.03, 1.0)
			return _mix(n, [
				[_noise(rng, n, AudioDsp.hp(r, 1500.0), 60.0), 0.55],
				[_noise(rng, n, AudioDsp.hp(r, 2500.0), 18.0, 0.005), 0.6],
				[_pings(n, times, freqs, decays, amps), 0.5],
				[ticks, 0.6],
				[pop, 0.5],
			])
		"debris":
			# trim and plastic bits landing on the road a moment after the
			# hit: small dull clacks, a few metal bits that ring, a couple
			# that slide instead of bouncing
			var d := _debris(rng, n)
			return _mix(n, [
				[d[0], 0.7],
				[d[1], 0.4],
				[d[2], 0.4],
				[_grains(rng, n, _times(rng, rng.randi_range(10, 20), 0.12, 0.7, 1.0), 0.0008, AudioDsp.hp(r, 3000.0)), 0.2],
			])
		"tail":
			# after a big hit: a heat shield buzzing itself still, loose trim
			# clacking, the exhaust knocking on its hangers
			var secs := n / r
			var shield := _buf(n)
			var hz := rng.randf_range(500.0, 1400.0)
			var t := rng.randf_range(0.0, 0.08)
			var gap := rng.randf_range(0.05, 0.09)
			var a := rng.randf_range(0.7, 1.0)
			while t < secs - 0.12 and gap > 0.01:
				_ring_bit(rng, shield, t, hz * rng.randf_range(0.98, 1.02), rng.randf_range(45.0, 90.0), a)
				t += gap * rng.randf_range(0.85, 1.15)
				gap *= rng.randf_range(0.82, 0.93)
				a *= rng.randf_range(0.84, 0.94)
			var trim := _buf(n)
			for k in rng.randi_range(3, 7):
				var tt := rng.randf_range(0.02, maxf(secs - 0.2, 0.05))
				var g := rng.randf_range(0.04, 0.1)
				var amp := rng.randf_range(0.4, 1.0) * exp(-tt * 1.5)
				var chz := rng.randf_range(500.0, 1800.0)
				for bounce in rng.randi_range(1, 3):
					_clack(rng, trim, tt, chz * rng.randf_range(0.93, 1.07), rng.randf_range(3.0, 6.0), rng.randf_range(0.005, 0.012), amp)
					tt += g
					g *= 0.6
					amp *= 0.5
			var knocks := _buf(n)
			for k in rng.randi_range(2, 4):
				var tt := rng.randf_range(0.0, maxf(secs - 0.25, 0.05))
				_clack(rng, knocks, tt, rng.randf_range(140.0, 320.0), 3.0, 0.03, rng.randf_range(0.5, 1.0) * exp(-tt * 1.2))
			return _mix(n, [
				[shield, 0.8],
				[trim, 0.6],
				[knocks, 0.7],
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
			# the floor pan slamming onto the road: a heavy thump, the chassis
			# banging, a short grind, the heat shield rattling
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
				[_body(rng, n, 110.0, 240.0, rng.randf_range(7.0, 9.0)), 1.0],
				[_boom(n, rng.randf_range(35.0, 55.0), 0.8, 0.15, 13.0), 0.33],
				[_panel(rng, n, 24, 120.0, 1500.0, 12.0, 30.0, rng.randf_range(0.02, 0.035), 2000.0, 0.7), 0.7],
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

## Crumpling metal: a stream of grains, dense at first and thinning right to
## the end, with two to four loud buckle pops in it, through eight to twelve
## loose resonances (Q 4-8) that sag 8-15 % as the panel folds, and through a
## low fold band (150-500 Hz); late on, a few creaks.
## Returns [ringing, grit, fold, creaks].
static func _crumple(rng: RandomNumberGenerator, n: int) -> Array:
	var r := float(MIX_RATE)
	var secs := n / r
	var res: Array[AudioDsp.Biquad] = []
	var hz := []
	var qs := []
	for k in rng.randi_range(8, 12):
		hz.append(300.0 * pow(3800.0 / 300.0, rng.randf()))
		qs.append(rng.randf_range(4.0, 8.0))
		res.append(AudioDsp.bp(r, hz[k], qs[k]))
	var folds: Array[AudioDsp.Biquad] = []
	var fhz := []
	var fqs := []
	for k in rng.randi_range(2, 3):
		fhz.append(rng.randf_range(150.0, 500.0))
		fqs.append(rng.randf_range(2.5, 4.0))
		folds.append(AudioDsp.bp(r, fhz[k], fqs[k]))
	var sag := rng.randf_range(0.08, 0.15)
	var grit := AudioDsp.hp(r, 1800.0)
	# [time, size], in time order
	var grains := []
	var tt := 0.0
	while tt < secs * 0.93:
		grains.append([tt, rng.randf_range(0.5, 1.0) * exp(-tt * 1.8)])
		tt += rng.randf_range(0.004, 0.02) * (1.0 + tt * 9.0)
	for k in rng.randi_range(2, 4):
		var at := rng.randf_range(0.06, minf(0.9, secs * 0.55))
		grains.append([at, rng.randf_range(1.1, 1.5) * exp(-at * 0.6)])
	grains.sort_custom(func(a, b): return a[0] < b[0])
	# creaks: short runs of pulses, speeding up or slowing, in the tail
	var creaks := []   # [from, secs, pulses per second at the start, at the end]
	for k in rng.randi_range(2, 4):
		creaks.append([rng.randf_range(secs * 0.4, secs * 0.88), rng.randf_range(0.06, 0.16), rng.randf_range(40.0, 90.0), rng.randf_range(40.0, 90.0)])
	var cres := AudioDsp.bp(r, rng.randf_range(500.0, 1200.0), 6.0)
	var ring := _buf(n)
	var gs := _buf(n)
	var fold := _buf(n)
	var creak := _buf(n)
	var g := 0
	var excite := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / r
		if i % 64 == 0:
			var k := 1.0 - sag * minf(t / (secs * 0.6), 1.0)
			for j in res.size():
				res[j].set_bp(r, hz[j] * k, qs[j])
			for j in folds.size():
				folds[j].set_bp(r, fhz[j] * k, fqs[j])
		while g < grains.size() and grains[g][0] <= t:
			excite = maxf(excite, grains[g][1])
			g += 1
		excite *= 0.996
		var w := rng.randf_range(-1.0, 1.0) * excite
		var v := 0.0
		for f in res:
			v += f.step(w)
		ring[i] = v
		gs[i] = grit.step(w)
		var lo := 0.0
		for f in folds:
			lo += f.step(w)
		fold[i] = lo
		var x := 0.0
		for c in creaks:
			if t >= c[0] and t < c[0] + c[1]:
				var k: float = (t - c[0]) / c[1]
				phase += lerpf(c[2], c[3], k) / r
				if phase >= 1.0:
					phase -= 1.0
					x = sin(PI * k)
		creak[i] = cres.step(x)
	return [ring, gs, fold, creak]

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

## Soft clip: tanh at `drive`, scaled back to a peak of 1.
static func _saturate(s: PackedFloat32Array, drive: float) -> PackedFloat32Array:
	AudioDsp.normalise(s, 1.0)
	var k := 1.0 / tanh(drive)
	for i in s.size():
		s[i] = tanh(s[i] * drive) * k
	return s

## The weight of a hit: low-passed noise through two or three wide resonances
## (Q 1.5-3) between lo and hi Hz, dying at `decay` per second. Noise, not a
## sine: it fills the band, and small speakers play the top of it.
static func _body(rng: RandomNumberGenerator, n: int, lo: float, hi: float, decay: float, attack := 0.004) -> PackedFloat32Array:
	var r := float(MIX_RATE)
	var soft := AudioDsp.lp(r, hi * 1.6)
	var bank: Array[AudioDsp.Biquad] = []
	var gains: Array[float] = []
	var count := rng.randi_range(2, 3)
	for k in count:
		bank.append(AudioDsp.bp(r, lerpf(lo, hi, (k + rng.randf()) / count), rng.randf_range(1.5, 3.0)))
		gains.append(rng.randf_range(0.7, 1.0))
	var s := _buf(n)
	for i in n:
		var t := float(i) / r
		var x := soft.step(rng.randf_range(-1.0, 1.0)) * exp(-t * decay) * minf(t / attack, 1.0)
		var v := 0.0
		for k in count:
			v += bank[k].step(x) * gains[k]
		s[i] = v
	return s

## Sheet metal struck: `count` modes spread evenly (in pitch) from lo to hi
## Hz, short-lived (decay d_lo per second at the bottom to d_hi at the top),
## each with a slightly detuned twin so the ring beats, all shoved by one
## noise burst `excite` s long, low-passed at `soft` Hz. `tilt` leans the
## level towards the low modes. Dozens of modes this short read as a bang,
## not as a note.
static func _panel(rng: RandomNumberGenerator, n: int, count: int, lo: float, hi: float, d_lo: float, d_hi: float, excite: float, soft: float, tilt: float) -> PackedFloat32Array:
	var r := float(MIX_RATE)
	var ex := mini(int(excite * r), n)
	var shove := _buf(ex)
	var lp := AudioDsp.lp(r, soft)
	for i in ex:
		var k := float(i) / ex
		shove[i] = lp.step(rng.randf_range(-1.0, 1.0)) * minf(k / 0.1, 1.0) * (1.0 - k)
	var s := _buf(n)
	for m in count:
		var pos := (m + rng.randf()) / count
		var hz := lo * pow(hi / lo, pos)
		var decay := lerpf(d_lo, d_hi, pos) * rng.randf_range(0.8, 1.25)
		var amp := pow(hz / lo, -tilt) * rng.randf_range(0.5, 1.0)
		for twin in 2:
			var w := TAU * minf(hz + (rng.randf_range(1.0, 4.0) if twin == 1 else 0.0), r * 0.45) / r
			var rr := exp(-decay * (1.1 if twin == 1 else 1.0) / r)
			var c1 := 2.0 * rr * cos(w)
			var c2 := -rr * rr
			var g := sin(w) * amp * (0.7 if twin == 1 else 1.0)
			var y1 := 0.0
			var y2 := 0.0
			for i in mini(n, ex + int(7.0 / decay * r)):   # until it is ~0.1 %
				var y := c1 * y1 + c2 * y2
				if i < ex:
					y += g * shove[i]
				y2 = y1
				y1 = y
				s[i] += y
	return s

## One dull click into s at t: noise through a band at hz (Q q), about `glen`
## s long. Plastic on asphalt, a glass grain, a knock: no ring to it.
static func _clack(rng: RandomNumberGenerator, s: PackedFloat32Array, t: float, hz: float, q: float, glen: float, amp: float) -> void:
	var r := float(MIX_RATE)
	var at := int(t * r)
	var f := AudioDsp.bp(r, hz, q)
	var fall := exp(-3.0 / (glen * r))
	var env := amp
	for i in maxi(mini(int(glen * 3.0 * r), s.size() - at), 0):
		s[at + i] += f.step(rng.randf_range(-1.0, 1.0) * env)
		env *= fall

## One small metal bit into s at t: two or three inharmonic modes from hz,
## dying at `decay` per second.
static func _ring_bit(rng: RandomNumberGenerator, s: PackedFloat32Array, t: float, hz: float, decay: float, amp: float) -> void:
	var r := float(MIX_RATE)
	var at := int(t * r)
	var ratios := [1.0, rng.randf_range(2.3, 2.8), rng.randf_range(4.1, 5.4)]
	for k in rng.randi_range(2, 3):
		var w: float = TAU * minf(hz * ratios[k], r * 0.45) / r
		var d := decay * (1.0 + 0.4 * k)
		var a := amp * pow(0.6, k)
		for i in maxi(mini(int(7.0 / d * r), s.size() - at), 0):
			s[at + i] += sin(w * i) * a * exp(-float(i) / r * d)

## A bit sliding on the road into s from t for `secs`: stick-slip noise in a
## band at hz, fading.
static func _slide(rng: RandomNumberGenerator, s: PackedFloat32Array, t: float, secs: float, hz: float, amp: float) -> void:
	var r := float(MIX_RATE)
	var at := int(t * r)
	var f := AudioDsp.bp(r, hz, rng.randf_range(1.5, 2.5))
	var m := maxi(mini(int(secs * r), s.size() - at), 0)
	var env := 0.0
	var wait := 0
	for i in m:
		wait -= 1
		if wait <= 0:
			env = rng.randf_range(0.3, 1.0)
			wait = int(rng.randf_range(0.003, 0.008) * r)
		var k := float(i) / m
		s[at + i] += f.step(rng.randf_range(-1.0, 1.0) * env) * amp * minf(k / 0.08, 1.0) * (1.0 - k)

## Bits landing on the road over 0.1-1.2 s: 8-20 small pieces. Most are
## plastic (a dull clack, maybe a bounce or two), some metal (a short ring),
## and two or three slide instead. Returns [clacks, metal, slides].
static func _debris(rng: RandomNumberGenerator, n: int) -> Array:
	var r := float(MIX_RATE)
	var last := minf(n / r - 0.15, 1.2)
	var clacks := _buf(n)
	var metal := _buf(n)
	var slides := _buf(n)
	var sliders := rng.randi_range(2, 3)
	for k in rng.randi_range(8, 20):
		var t := 0.1 + (last - 0.1) * pow(rng.randf(), 1.4)
		var a := rng.randf_range(0.25, 1.0) * exp(-t * 0.8)
		if k < sliders:
			_slide(rng, slides, t, rng.randf_range(0.06, 0.18), rng.randf_range(900.0, 2800.0), a)
			continue
		var is_metal := rng.randf() < 0.3
		var hz := rng.randf_range(1500.0, 4200.0) if is_metal else rng.randf_range(700.0, 3200.0)
		var gap := rng.randf_range(0.05, 0.14)
		for bounce in rng.randi_range(1, 3):
			if is_metal:
				_ring_bit(rng, metal, t, hz * rng.randf_range(0.98, 1.02), rng.randf_range(25.0, 60.0), a)
			else:
				_clack(rng, clacks, t, hz * rng.randf_range(0.92, 1.08), rng.randf_range(3.0, 6.0), rng.randf_range(0.005, 0.015), a)
			t += gap
			gap *= rng.randf_range(0.5, 0.7)
			a *= rng.randf_range(0.4, 0.6)
	return [clacks, metal, slides]
