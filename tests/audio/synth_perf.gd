extends SceneTree

# Engine synth cost and a bit-exact fingerprint of its output.
#
# SYNTH line: ns per sample and ms per 640-sample block (about one frame at
# 75 fps). The synth is a per-sample GDScript loop that runs on a worker thread
# (engine_audio.gd), so this is what that thread owes every frame.
# FINGERPRINT line: a hash of every sample rendered over scenarios that reach
# each branch (cruise, overrun pops, anti-lag, limiter, boost + blow-off,
# upshift bang). An optimisation of the loop must leave it unchanged; compare
# the value before and after. Exit code 0 always; this is a measuring tool.
#
# Run: godot --headless --path . -s res://tests/audio/synth_perf.gd

func _make(anti_lag: float) -> EngineSynth:
	var s := EngineSynth.new()
	s.tune = ExhaustTune.for_car("p1_coupe")
	s.tune.anti_lag = anti_lag
	s.mix_rate = 48000.0
	s.idle_rpm = 900.0
	s.max_rpm = 7500.0
	s.volume = 0.5
	return s

func _init() -> void:
	var h := 2166136261
	var total := 0
	var us_total := 0
	for scenario in 5:
		var s := _make(1.0 if scenario == 3 else 0.0)
		for i in 300:
			var rpm := 3000.0 + 20.0 * (i % 100)
			var thr := 0.8
			var redline := false
			match scenario:
				1: thr = 0.0; rpm = 5500.0 + 10.0 * (i % 50)    # overrun: pops
				2: rpm = 7400.0; redline = (i % 3 == 0)           # limiter
				3: thr = 0.0; rpm = 6000.0                        # anti-lag volley
				4:
					s.boost = 0.7
					if i == 100: s.blow_off(1.0)
					if i == 200: s.shift_cut(1.0)
			var t0 := Time.get_ticks_usec()
			var block := s.render(640, rpm, thr, redline)
			us_total += Time.get_ticks_usec() - t0
			total += 640
			for v in block:
				h = ((h ^ int(v.x * 1000000.0)) * 16777619) & 0xffffffff
	print("SYNTH ns/sample=%.0f  ms per 640-sample block=%.3f" % [us_total * 1000.0 / total, us_total / float(total / 640) / 1000.0])
	print("FINGERPRINT %d" % h)
	quit()
