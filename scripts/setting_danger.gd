class_name SettingDanger
extends RefCounted

# Danger zones and consequence lines for tuning settings (settings safety part 3,
# 2026-10-07; plan in docs/planning/settings-safety-design-2026-10-07.md, signed
# off by Roy). No UI here: TunerScreen and TuningPanel colour their bars and
# write the line under each risky setting from these.
#
# Zones per TuneParams path, from the test track sweeps on the coupe:
#   green  within about 10% of stock on every stat
#   amber  one stat 10-30% worse, or slip 15-25 deg
#   red    the car spins (slip over 25 deg) or a stat is over 30% worse
# Red is a warning, never a limit: the hard limits are TuneParams.ADVANCED.
# The simple pages stay inside the safe range, so red shows on Advanced only.
#
# Thresholds are absolute values measured on the coupe; the other player cars
# get their own sweep when they arrive (premortem in the plan).

enum Level { GREEN, AMBER, RED }

# Same colours as the HUD (hud.gd): RPM-bar green, amber, tail red.
const GREEN := Color("#3FD060")
const AMBER := Color("#FFC066")
const RED := Color("#E5262B")

const NO := INF  # "no threshold on this side"

## path: [red_below, amber_below, amber_above, red_above]. Use NO / -NO for none.
const ZONES := {
	"coefficient_of_friction/Road": [0.9, 1.05, 2.0, 2.8],
	"longitudinal_grip_ratio/Road": [0.7, 0.9, NO, NO],
	"front_tyre_pressure": [-NO, 1.4, 3.0, NO],
	"rear_tyre_pressure": [1.4, 1.7, 2.7, 3.0],
	"front_static_camber": [-6.5, -4.5, 1.5, NO],
	"rear_static_camber": [-6.0, -4.0, 1.0, 2.0],
	"front_toe": [-NO, -0.04, 0.04, NO],
	"rear_toe": [0.0, 0.003, 0.04, NO],
	"front_spring_length": [-NO, -NO, 0.32, NO],
	"rear_spring_length": [0.10, 0.14, 0.28, 0.30],
	"front_resting_ratio": [-NO, -NO, 0.8, NO],
	"rear_resting_ratio": [0.25, 0.3, 0.58, 0.65],
	"front_damping_ratio": [-NO, 0.2, 1.2, NO],
	"rear_damping_ratio": [-NO, 0.2, 1.2, NO],
	"front_arb_ratio": [0.05, 0.1, 0.9, NO],
	"rear_arb_ratio": [-NO, -NO, 0.45, 0.6],
	"final_drive": [2.2, 2.8, 5.0, 6.3],
	"gear_ratios/0": [1.2, 1.8, NO, NO],
	"max_rpm": [4500.0, 5500.0, NO, NO],
	"torque_shape/falloff": [0.3, 0.4, NO, NO],
	"rear_locking_differential_engage_torque": [-NO, -NO, 1500.0, NO],
	"brake_force_multiplier": [1.0, 1.6, NO, NO],
	"front_brake_bias": [0.4, 0.45, 0.75, 0.85],  # a set bias only; Auto is green
	"aero_downforce_coefficient_front": [-NO, -NO, 0.8, 1.2],
	"aero_downforce_coefficient_rear": [0.15, 0.3, 2.0, NO],
	"max_steering_angle": [-NO, -NO, 0.96, NO],  # 55 deg
}

## What a setting does to the car, in real tuning terms. Four phrases: lower
## than stock, higher than stock, and the red versions of each (empty = the
## plain one). Kept short: it is one line under the bar.
const LINES := {
	"coefficient_of_friction/Road": ["Hard compound: slides early, easy to catch", "Sticky: big grip, snaps when it lets go", "Ice: barely grips, spins on any input", "Glue: huge grip, violent when it breaks"],
	"longitudinal_grip_ratio/Road": ["Wheels spin up easily, rear light on power", "Hooks up hard off the line", "Lights up the rears, spins on launch", ""],
	"tire_stiffnesses/Road": ["Soft carcass: progressive, vague", "Stiff carcass: sharp, less warning", "", ""],
	"front_tyre_pressure": ["Low: bigger patch, mushy turn-in", "High: crisp, less front grip at the limit", "", ""],
	"rear_tyre_pressure": ["Low: bigger patch, lazy rear", "High: crisp, rear lets go sooner", "Rear squirms and lets go: spins", "Rear skates: spins"],
	"front_static_camber": ["More negative: corner grip, weaker braking", "Positive: front washes wide", "Tyre on its edge: front grip falls away", ""],
	"rear_static_camber": ["More negative: corner grip, looser on power", "Positive: rear lets go early", "Rear on its edge: spins", "Rear camber positive: spins"],
	"front_toe": ["Toe-out: darty turn-in, wanders", "Toe-in: stable, lazy turn-in", "", ""],
	"rear_toe": ["Less toe-in: rear rotates", "Toe-in: planted rear, scrubs speed", "Toe-out: rear steers itself, spins", ""],
	"front_spring_length": ["Low: less roll, bottoms out", "High: more roll and weight transfer", "", ""],
	"rear_spring_length": ["Low rear: less roll, rear bottoms out", "High rear: weight shifts forward, loose", "Slammed rear: bottoms and spins", "Tall rear: tips into oversteer, spins"],
	"front_resting_ratio": ["Soft front: grip over bumps, slow response", "Stiff front: sharp, pushes wide", "", ""],
	"rear_resting_ratio": ["Soft rear: squats, grips out of corners", "Stiff rear: rear steps out on power", "Rear wallows and lets go: spins", "Rear skips and snaps: spins"],
	"front_damping_ratio": ["Soft: floaty, bounces after kerbs", "Hard: skips over bumps", "", ""],
	"rear_damping_ratio": ["Soft: floaty, bounces after kerbs", "Hard: skips over bumps", "", ""],
	"front_arb_ratio": ["Soft front bar: front bites, rear looser", "Stiff front bar: more understeer", "No front bar: rear snaps around", ""],
	"rear_arb_ratio": ["Soft rear bar: planted, rolls more", "Stiff rear bar: rotates, can snap", "", "Rear bar solid: snaps into a spin"],
	"final_drive": ["Long: top speed, slow launch", "Short: punchy, runs out of gears", "Very long: crawls off the line", "Very short: tops out early"],
	"gear_ratios/0": ["Tall first: soft launch", "Short first: wheelspin off the line", "First like third: bogs off the line", ""],
	"max_rpm": ["Low redline: short gears, less power", "High redline: longer gears usable", "Revs die early: slow everywhere", ""],
	"turbo_boost_max": ["", "More boost: lag, then a shove up top", "", ""],
	"torque_shape/falloff": ["Power dies near the limiter", "Pulls to the limiter", "Falls flat on top: no top speed", ""],
	"rear_locking_differential_engage_torque": ["More lock: both wheels push, easy drifts", "More open: inside wheel spins", "", ""],
	"brake_force_multiplier": ["Weak brakes: long stops", "Strong brakes: easy to lock without ABS", "Barely stops", ""],
	"front_brake_bias": ["Rear bias: rotates on entry, can spin", "Front bias: safe, pushes wide", "Rear-heavy: spins under braking", "Front-heavy: plows, long stops"],
	"aero_downforce_coefficient_front": ["Less front wing: understeer at speed", "Front bite, rear goes light at speed", "", "Front glued, rear floats: spins"],
	"aero_downforce_coefficient_rear": ["Less wing: loose at speed", "Big wing: planted, slow on straights", "No wing: rear floats at speed, spins", ""],
	"max_steering_angle": ["Less lock: wide turns, calm", "More lock: tight turns, twitchy", "", ""],
}

## Green, amber or red for `value` on `path`. Paths without zones are green.
static func level(path: String, value: float) -> Level:
	if path == "front_brake_bias" and value < 0.0:
		return Level.GREEN  # Auto
	var z: Array = ZONES.get(path, [])
	if z.is_empty() or not is_finite(value):
		return Level.RED if not is_finite(value) else Level.GREEN
	if value < z[0] or value > z[3]:
		return Level.RED
	if value < z[1] or value > z[2]:
		return Level.AMBER
	return Level.GREEN

static func colour(l: Level) -> Color:
	return [GREEN, AMBER, RED][l]

## The one-line consequence for `value` against `stock`, or "" for a path with
## no line. Near stock it says so.
static func consequence(path: String, value: float, stock: float) -> String:
	var lines: Array = LINES.get(path, [])
	if lines.is_empty():
		return ""
	if path == "front_brake_bias":
		if value < 0.0:
			return "Auto: split set from the springs"
		if stock < 0.0:
			stock = 0.55  # what Auto gives the coupe
	var e := TuneParams.find(path)
	var span: float = (e.adv_max - e.adv_min) if not e.is_empty() else 1.0
	if absf(value - stock) <= span * 0.02:
		return "Stock"
	var high := value > stock
	var red := level(path, value) == Level.RED
	var plain: String = lines[1] if high else lines[0]
	var hot: String = lines[3] if high else lines[2]
	var out := hot if red and hot != "" else plain
	return out if out != "" else plain
