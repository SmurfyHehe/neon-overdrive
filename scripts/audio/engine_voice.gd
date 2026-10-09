# Per-car engine voice (ROADMAP #80, 2026-10-07). The exhaust tune
# (exhaust_tune.gd) is what the owner bolts on; this is what the engine IS:
# cylinder count, firing pattern, pipe and intake resonances. A car's spec
# holds it under "engine_voice" and EngineAudio hands it to EngineSynth once,
# when the car spawns. Not a tuning knob: no slider, no Auto-Tune, no save file.
#
# Every car uses the same synth; only these numbers differ. Original voices
# built by engine type, not copies of any real car's recording:
# - cylinders + firing set the beat. Even firing is a steady buzz; a V8 with
#   one bank louder than the other (the crossplane order is L R R L R L L R)
#   burbles; a flat-four with unequal headers pairs its pulses into a rumble.
# - body_hz is the pipe's boom (big engines low, small ones high), rasp_hz the
#   upper edge, tone opens or closes the low-pass, pulse_width how sharp each
#   firing is (short = brighter).
# - cyl_spread is how different the cylinders are from each other: the idle
#   lope. A tired commuter is smooth, a cammed muscle car lopes.
# - wander is the anti-repetition layer: a slow random drift of the pipe
#   resonance and loudness so a held rpm never loops the same block. Real
#   engines vary cycle to cycle; a perfectly steady synth tires the ear.
extends RefCounted
class_name EngineVoice

const KEYS := ["cylinders", "firing", "cyl_amps", "cyl_spread", "seed",
		"body_hz", "body_q", "rasp_hz", "rasp_q", "tone", "pulse_width", "wander"]

# Firing tables, as fractions of one four-stroke cycle (two crank turns).
const _BOXER_UNEQUAL := [0.0, 0.28, 0.5, 0.78]
# Crossplane V8: even 90-degree firing, but each bank's pipe hears the uneven
# L R R L R L L R order. Mono, that reads as a louder and a softer bank plus a
# little timing smear from the different path lengths.
const _V8_FIRING := [0.0, 0.127, 0.25, 0.374, 0.5, 0.626, 0.75, 0.877]
const _V8_BANKS := [1.0, 0.8, 0.8, 1.0, 0.8, 1.0, 1.0, 0.8]

## Keyed by the fleet ids in docs/design/fleet/fleet.json. Judgement calls by
## car type; Roy can retune any.
const PRESETS := {
	# Long-hood coupe, straight six: smooth, even, a clean metallic top end.
	"p1_coupe": {"cylinders": 6, "cyl_spread": 0.08, "seed": 11, "body_hz": 125.0, "body_q": 1.6,
			"rasp_hz": 1500.0, "rasp_q": 2.2, "tone": 1.1, "pulse_width": 0.33, "wander": 0.6},
	# Hot hatch, small high-revving four: buzzy, bright, nasal.
	"p2_hothatch": {"cylinders": 4, "cyl_spread": 0.12, "seed": 23, "body_hz": 165.0, "body_q": 1.8,
			"rasp_hz": 1900.0, "rasp_q": 2.6, "tone": 1.25, "pulse_width": 0.28, "wander": 0.6},
	# Tuner sedan, straight six on a bigger pipe: deeper than the coupe, raspier.
	"p3_tuner": {"cylinders": 6, "cyl_spread": 0.14, "seed": 37, "body_hz": 98.0, "body_q": 1.4,
			"rasp_hz": 1150.0, "rasp_q": 1.8, "tone": 1.05, "pulse_width": 0.26, "wander": 0.7},
	# Kei roadster, tiny three: high, thrummy, a little uneven.
	"p4_kei": {"cylinders": 3, "cyl_spread": 0.18, "seed": 41, "body_hz": 210.0, "body_q": 1.7,
			"rasp_hz": 2300.0, "rasp_q": 2.4, "tone": 1.2, "pulse_width": 0.30, "wander": 0.7},
	# Muscle sedan, big crossplane V8: low boom, heavy lope, dark.
	"p5_muscle": {"cylinders": 8, "firing": _V8_FIRING, "cyl_amps": _V8_BANKS, "cyl_spread": 0.2, "seed": 53,
			"body_hz": 70.0, "body_q": 1.3, "rasp_hz": 900.0, "rasp_q": 1.6, "tone": 0.8,
			"pulse_width": 0.42, "wander": 0.8},
	# Performance crossover, flat four with unequal headers: the paired rumble.
	"p6_crossover": {"cylinders": 4, "firing": _BOXER_UNEQUAL, "cyl_spread": 0.15, "seed": 67,
			"body_hz": 95.0, "body_q": 1.5, "rasp_hz": 1250.0, "rasp_q": 1.9, "tone": 0.95,
			"pulse_width": 0.36, "wander": 0.7},
	# Traffic: quiet, smooth, muffled. They should not compete with the player.
	"n1_commuter": {"cylinders": 4, "cyl_spread": 0.04, "seed": 71, "body_hz": 140.0, "body_q": 1.2,
			"rasp_hz": 1000.0, "rasp_q": 1.4, "tone": 0.7, "pulse_width": 0.42, "wander": 0.5},
	"n2_cityhatch": {"cylinders": 3, "cyl_spread": 0.08, "seed": 79, "body_hz": 185.0, "body_q": 1.3,
			"rasp_hz": 1700.0, "rasp_q": 1.6, "tone": 0.8, "pulse_width": 0.38, "wander": 0.5},
	"n3_pickup": {"cylinders": 6, "cyl_spread": 0.1, "seed": 83, "body_hz": 90.0, "body_q": 1.3,
			"rasp_hz": 950.0, "rasp_q": 1.5, "tone": 0.75, "pulse_width": 0.4, "wander": 0.5},
	# Police: V8s, subdued but heavier than traffic; the interceptor growls.
	"c1_patrol": {"cylinders": 8, "firing": _V8_FIRING, "cyl_amps": _V8_BANKS, "cyl_spread": 0.08, "seed": 89,
			"body_hz": 82.0, "body_q": 1.3, "rasp_hz": 1000.0, "rasp_q": 1.5, "tone": 0.8,
			"pulse_width": 0.4, "wander": 0.5},
	"c2_patrolsuv": {"cylinders": 8, "firing": _V8_FIRING, "cyl_amps": _V8_BANKS, "cyl_spread": 0.06, "seed": 97,
			"body_hz": 88.0, "body_q": 1.2, "rasp_hz": 950.0, "rasp_q": 1.4, "tone": 0.75,
			"pulse_width": 0.42, "wander": 0.5},
	"c3_interceptor": {"cylinders": 8, "firing": _V8_FIRING, "cyl_amps": _V8_BANKS, "cyl_spread": 0.15, "seed": 101,
			"body_hz": 76.0, "body_q": 1.4, "rasp_hz": 1100.0, "rasp_q": 1.8, "tone": 0.9,
			"pulse_width": 0.38, "wander": 0.7},
}

## A car's voice as a fresh dictionary (safe to store in a spec), or {} for an
## unknown id, which leaves EngineSynth on its built-in four-cylinder default.
static func for_car(id: String) -> Dictionary:
	var p: Variant = PRESETS.get(id)
	return (p as Dictionary).duplicate(true) if p is Dictionary else {}

## Even firing for n cylinders, as cycle fractions.
static func even_firing(n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in n:
		out.append(float(i) / n)
	return out
