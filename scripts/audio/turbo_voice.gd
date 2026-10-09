# Per-setup turbo voice (B1, 2026-10-09). The engine voice (engine_voice.gd) is
# what the engine is; this is what sits on its intake. A car's spec holds it
# under "turbo_voice" and EngineAudio hands it to TurboSynth once, when the car
# spawns. Not a tuning knob: no slider, no save file. The Tuner's boost slider
# (turbo_boost_max) still shapes the sound live: more bar, further the whistle
# climbs.
#
# Every turbo uses the same synth; only these numbers differ. Original voices
# built by turbo type, not copies of any recording:
# - a small turbo spins fast: a high, clean whistle that spools in a blink.
#   A big single spins slower: lower, airier, more "shhh" than "eee".
# - the second partial is the turbine wheel against the compressor wheel
#   (two blade counts); its ratio and mix set how "metallic" the whine is.
# - the valve comes with the part. "recirc" is the stock recirculating valve:
#   a short, muffled puff back into the intake. "atmo" is an aftermarket
#   atmospheric valve: the loud, bright "pssh". "flutter" is no valve at all:
#   the compressor surges against the closed throttle, a chopped
#   "stu-tu-tu-tu" that drags the whistle down with it.
extends RefCounted
class_name TurboVoice

const KEYS := ["part", "valve", "hz_low", "hz_span", "partial", "partial_mix", "air",
		"flutter_hz", "flutter_depth", "level", "valve_level", "detune",
		"blower", "blower_hz_max", "blower_off_from", "blower_off_to",
		"stage2_at", "stage2_hz_low", "stage2_hz_span"]

## The boost setup (spec boost_kind, C1's ForcedInduction kinds; "single" is the
## plain turbo) laid over the car's part and valve. The numbers are the sound of
## the setup, not of any one real car:
## - twin: two small turbos that never spin quite alike, so the whistle beats
##   (detune); the car keeps its valve.
## - roots: a gear-driven blower, so no spool whistle and no valve. The whine
##   follows rpm, not boost: lobes passing the housing at a fixed ratio to the
##   crank, a buzzy tone that is there off boost too.
## - sequential: the small turbo whistles from low rpm, the big one joins at
##   the handover (60% of max rpm, SEQ_HANDOVER in forced_induction.gd), lower
##   and airier under it.
## - twincharger: the blower fills the bottom and is bypassed between 45% and
##   65% of max rpm (the whine fades out, then the turbo carries it).
const KINDS := {
	"single": {},
	"twin": {"part": "small", "detune": 0.03, "level": 0.9},
	"roots": {"level": 0.0, "valve": "none", "blower": 1.0, "blower_hz_max": 1500.0},
	"sequential": {"part": "small", "stage2_at": 0.6, "stage2_hz_low": 2800.0, "stage2_hz_span": 2600.0},
	"twincharger": {"part": "medium", "blower": 0.7, "blower_hz_max": 1300.0,
			"blower_off_from": 0.45, "blower_off_to": 0.65},
}

## The parts. Keyed by part id; a car's preset names one and may override keys.
const PARTS := {
	# Small stock turbo: high, clean, quick. The hot hatch's.
	"small": {"hz_low": 4200.0, "hz_span": 4400.0, "partial": 1.52, "partial_mix": 0.3, "air": 0.3,
			"flutter_hz": 8.0, "flutter_depth": 0.008, "level": 0.8},
	# Medium single: the tuner-sedan middle ground.
	"medium": {"hz_low": 3000.0, "hz_span": 4000.0, "partial": 1.37, "partial_mix": 0.45, "air": 0.5,
			"flutter_hz": 6.5, "flutter_depth": 0.012, "level": 1.0},
	# Big single: lower, breathy, a slow heavy flutter. Stays above the mirror
	# whistle's 1.25 / 2.5 kHz tones (cockpit wind), like the others.
	"big": {"hz_low": 2800.0, "hz_span": 2600.0, "partial": 1.41, "partial_mix": 0.6, "air": 0.8,
			"flutter_hz": 4.5, "flutter_depth": 0.02, "level": 1.15},
}

## Keyed by the fleet ids in docs/design/fleet/fleet.json. Judgement calls by
## car type; Roy can retune any. Cars with no boost get no entry: TurboSynth is
## silent at boost 0 whatever the voice.
const PRESETS := {
	# Hot hatch: small stock turbo, stock recirculating valve. Polite.
	"p2_hothatch": {"part": "small", "valve": "recirc", "valve_level": 0.6},
	# Tuner sedan: medium single on an atmospheric valve. The loud one.
	"p3_tuner": {"part": "medium", "valve": "atmo", "valve_level": 1.0},
	# Performance crossover: medium turbo, no valve: compressor flutter on
	# every lift, the flat-four-with-a-turbo cliche.
	"p6_crossover": {"part": "medium", "valve": "flutter", "valve_level": 0.9, "air": 0.65},
}

## A car's voice as a fresh dictionary (safe to store in a spec): the part's
## numbers with the car's overrides on top. A car with no preset gets the
## medium part on a recirculating valve, so a Tuner-added turbo still sounds.
static func for_car(kind: String) -> Dictionary:
	var p: Dictionary = PRESETS.get(kind, {"part": "medium", "valve": "recirc", "valve_level": 0.6})
	return build(p)

## The car's voice under a boost setup: the kind's part replaces the car's
## (its valve stays), the kind's other numbers go on top.
static func for_setup(voice: Dictionary, boost_kind: String) -> Dictionary:
	var out := voice.duplicate()
	if out.is_empty():
		out = for_car("")
	var k: Dictionary = KINDS.get(boost_kind, {})
	if k.has("part"):
		var part: Dictionary = PARTS.get(k["part"], PARTS["medium"])
		for key in part:
			out[key] = part[key]
		out["part"] = k["part"]
	for key in k:
		if key != "part":
			out[key] = k[key]
	return out

## Same for a hand-written preset (tests, future mod nodes).
static func build(p: Dictionary) -> Dictionary:
	var out: Dictionary = PARTS.get(p.get("part", "medium"), PARTS["medium"]).duplicate()
	for k in p:
		if k in KEYS:
			out[k] = p[k]
	return out
