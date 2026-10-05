# Exhaust tune (stage B step 2, 2026-10-05). Four knobs, all 0..1, all
# COSMETIC: they change what the exhaust sounds and looks like and nothing
# else. No wear, heat, fuel, police or physics effect (Roy's decision,
# ROADMAP stage B). EngineSynth reads them; a flame visual reads the events
# EngineSynth.take_flames() hands out.
extends RefCounted
class_name ExhaustTune

## How loud the whole exhaust note is. 0.5 is the prototype's old level.
var loudness := 0.5
## Roughness: harder edge, more buzz, more noise in the pulse.
var raspiness := 0.3
## Overrun pops and crackles when the throttle is lifted at rpm. 0 = none.
var pops := 0.3
## Flamethrower: how much fire a pop or a rev-limiter cut spits out the tip.
## 0 = no flames. Cosmetic: it only sizes the flame events.
var flame := 0.0

func _init(l := 0.5, r := 0.3, p := 0.3, f := 0.0) -> void:
	loudness = l
	raspiness = r
	pops = p
	flame = f

## Per-car starting tunes, keyed by the fleet ids in docs/design/fleet/fleet.json.
## Order: loudness, raspiness, pops, flame. Researched 2026-10-05 and mostly
## judgement calls: no per-car dB or pop data is published. Grounding:
## - pops are an ECU-tune effect (overrun fuel cut off, retarded ignition), so
##   stock-type cars pop rarely (https://www.bristol-tuning.com/services/overrun-pop-crackle/);
## - flames come mainly from turbo anti-lag, so only the turbo/tuner cars get any;
## - stock cars are quiet (EU pass-by limit 72 dB, https://link.springer.com/article/10.1007/s40111-018-0010-7),
##   aftermarket exhausts add 6-25 dB, e.g. stock STI vs Invidia +6 dB
##   (https://www.iwsti.com/threads/exhaust-sound-levels.281359/), stock Supra vs
##   aftermarket 81 vs 85-106 dB (https://www.supraforums.com/threads/comparison-of-exhaust-sound-db-levels-on-tt-supra.1106626/);
## - sliders for tone and overrun are how Need for Speed Heat exposes it
##   (https://www.gtplanet.net/exhaust-tuning-will-make-cars-sing-in-need-for-speed-heat/).
## Players are loud and rude, traffic quiet, police subdued. Roy can retune any.
const PRESETS := {
	"p1_coupe":       [0.55, 0.55, 0.35, 0.20],
	"p2_hothatch":    [0.45, 0.60, 0.30, 0.10],
	"p3_tuner":       [0.70, 0.70, 0.60, 0.45],
	"p4_kei":         [0.40, 0.70, 0.35, 0.15],
	"p5_muscle":      [0.75, 0.45, 0.40, 0.20],
	"p6_crossover":   [0.50, 0.55, 0.40, 0.20],
	"n1_commuter":    [0.12, 0.10, 0.02, 0.00],
	"n2_cityhatch":   [0.20, 0.35, 0.05, 0.00],
	"n3_pickup":      [0.30, 0.35, 0.05, 0.00],
	"c1_patrol":      [0.35, 0.30, 0.05, 0.00],
	"c2_patrolsuv":   [0.30, 0.25, 0.05, 0.00],
	"c3_interceptor": [0.50, 0.40, 0.15, 0.05],
}

static func for_car(id: String) -> ExhaustTune:
	var p: Array = PRESETS.get(id, [0.5, 0.3, 0.3, 0.0])
	return ExhaustTune.new(p[0], p[1], p[2], p[3])
