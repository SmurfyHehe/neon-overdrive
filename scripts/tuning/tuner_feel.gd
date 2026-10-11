class_name TunerFeel
extends RefCounted

# One "what you'll feel" line for every row in the Tuner (tuner overhaul,
# 2026-10-10, Roy's decision). The hint under the page says what a setting IS;
# this says what the driver notices from the seat when it moves. One table for
# the simple pages, the raw Advanced sliders and the Exhaust page, keyed by the
# TuneParams path the row writes (or the setting id for rows that write several).
#
# Written low end first, high end second, in the same order as the row's bar.

const PREFIX := "You'll feel: "

## Rows that are not one path: choices, the merged Gearing bar, the Quick dials.
const BY_ID := {
	"compound": "Street slides early and gently. Semi-slick holds on far longer, then lets go all at once.",
	"gearing": "Short: every gear is over quickly and the car leaps out of corners. Long: lazy pull, but it keeps going on the freeway.",
	"power_band": "Low-end: shove from low revs, runs out of breath up top. Top-end: sleepy until the revs climb, then it screams.",
	"diff_lock": "Open: the inside wheel spins up out of tight corners. Locked: both rears push and the tail swings out on power.",
	"bias_mode": "Auto: the car stays straight under hard braking. Manual: you decide whether the nose or the tail gets nervous.",
	"traction": "Off: the rears light up when you floor it. High: the engine hesitates out of corners, but the tail stays put.",
	"abs": "Off: stamp the pedal and the wheels lock, the car slides straight on. On: the pedal pulses and you can still steer.",
	"stability": "Off: a slide is yours to catch. High: the car tugs itself straight before you notice it moved.",
	"q_preset": "Stock is the factory car. Street is calm and forgiving, Grip is sharp and planted, Drift lets the tail swing.",
	"q_grip_slide": "Toward Grip the tail stays hooked up and the car tracks where you point it. Toward Slide it comes round on the throttle.",
	"q_soft_stiff": "Soft: the body leans and soaks up rough road. Stiff: it changes direction at once and jolts over every bump.",
	"q_pull_top": "Toward Pull the car lunges off the line and out of corners. Toward Top speed it pulls longer and keeps gaining on the freeway.",
	"q_walt": "Walt drives it on his test track and keeps the setup that scores best. You feel the one thing you asked for; the rest stays close.",
	"q_detailed": "Nothing: this only shows or hides the full pages.",
}

const BY_PATH := {
	# gearing and engine
	"final_drive": "Low: long gears, slow launch, more top speed. High: short gears, hard launch, the engine is at the limiter sooner.",
	"gear_ratios/0": "Low: a soft, bogging launch. High: wheelspin off the line and an early shift to second.",
	"gear_ratios/1": "Low: a big rev drop after first. High: second is over quickly and pulls hard.",
	"gear_ratios/2": "Low: third stretches a long way. High: quick pull through the middle speeds.",
	"gear_ratios/3": "Low: fourth becomes a cruising gear. High: it keeps accelerating hard at freeway speed.",
	"gear_ratios/4": "Low: more top speed, if the engine can pull it. High: fifth runs into the limiter early.",
	"max_torque": "More: a harder shove in every gear, and more wheelspin to manage.",
	"max_rpm": "Low: you shift early and often. High: each gear runs longer before the limiter.",
	"turbo_boost_max": "None: instant, even pull. More: a pause, then a surge as the turbo comes in.",
	"torque_shape/low_end": "Low: nothing below the middle of the revs. High: it pulls from idle.",
	"torque_shape/peak_pos": "Low: the punch comes early and fades. High: you have to rev it out to find the power.",
	"torque_shape/plateau": "Narrow: one sweet spot to shift around. Wide: it pulls the same across a broad band.",
	"torque_shape/falloff": "Low: the pull dies before the limiter, so shift early. High: it pulls all the way to the limiter.",
	# tires
	"coefficient_of_friction/Road": "Low: slides early in every corner and under braking. High: corners and stops much harder, snaps when it finally lets go.",
	"longitudinal_grip_ratio/Road": "Low: wheelspin on launch and longer stops. High: hooks up hard off the line.",
	"lateral_grip_assist/Road": "More: the car holds its line a little more easily mid-corner.",
	"tire_stiffnesses/Road": "Soft: vague steering that warns you early. Stiff: sharp steering with little warning before it slides.",
	"front_tyre_pressure": "Low: mushy turn-in, the nose takes a moment to answer. High: crisp steering, the front gives up a little sooner.",
	"rear_tyre_pressure": "Low: a lazy, squirmy tail. High: a sharper rear that lets go sooner.",
	"front_static_camber": "Negative: more bite mid-corner, longer stops. Positive: the nose washes wide.",
	"rear_static_camber": "Negative: the tail holds in corners, looser when you launch. Positive: the rear lets go early.",
	"front_toe": "Out: darts into corners, wanders on the straight. In: runs straight, turns in lazily.",
	"rear_toe": "Zero: the tail turns with you and can step out. In: the rear stays planted.",
	# suspension
	"front_spring_length": "Low: flat in corners, scrapes and thumps on bumps. High: more lean, more travel.",
	"rear_spring_length": "Low: the tail sits and bottoms out. High: weight tips forward and the rear goes light.",
	"front_resting_ratio": "Soft: the nose dives and grips over bumps. Stiff: sharp turn-in, then it pushes wide.",
	"rear_resting_ratio": "Soft: it squats and grips on the way out. Stiff: the tail steps out on power.",
	"front_damping_ratio": "Soft: the nose floats and bobs after a bump. Firm: it settles at once, skips on rough road.",
	"rear_damping_ratio": "Soft: the tail floats and bobs after a bump. Firm: it settles at once, skips on rough road.",
	"front_arb_ratio": "Soft: the front bites and the body leans. Stiff: flat, and the nose pushes wide.",
	"rear_arb_ratio": "Soft: planted, leans more. Stiff: the tail rotates into corners and can snap.",
	"front_locking_differential_engage_torque": "Low (locked): the steering tugs and pushes wide on power. High (open): light steering.",
	"rear_locking_differential_engage_torque": "Low (locked): both rears push, the tail swings out on power. High (open): the inside wheel spins instead.",
	# brakes
	"brake_force_multiplier": "Low: a long pedal and long stops. High: it bites at once and locks easily without ABS.",
	"front_brake_bias": "Rear: the car turns in under braking and can spin. Front: stays straight, pushes wide if you brake into a corner.",
	"front_abs_spin_difference_threshold": "Low: ABS steps in early, you can always steer. High: the fronts lock before it helps.",
	"rear_abs_spin_difference_threshold": "Low: the tail stays in line under braking. High: the rears can lock and step out.",
	# aero
	"coefficient_of_drag": "Low: it keeps pulling at high speed. High: it runs out of breath on the freeway.",
	"aero_downforce_coefficient_front": "Low: the nose goes light at speed. High: the front bites in fast corners, the tail feels lighter.",
	"aero_downforce_coefficient_rear": "Low: loose at speed, faster on the straight. High: planted in fast corners, slower on the straight.",
	# assists and steering
	"max_steering_angle": "Less: calm, wide turns. More: tight turns and big slides you can still catch, twitchy at speed.",
	"traction_control_max_slip": "Low: power is cut as soon as the rears slip. High: they spin a long way first. Zero is off.",
	"stability_yaw_strength": "Low: slides are yours to catch. High: the car pulls itself straight.",
	# exhaust: sound and flames only
	"exhaust/loudness": "Only what you hear: quiet to shouting. The car drives the same.",
	"exhaust/raspiness": "Only what you hear: a smooth hum to a hard metallic rasp.",
	"exhaust/pops": "Only what you hear: more bangs and crackle when you lift off.",
	"exhaust/flame": "Only what you see: bigger flames from the tailpipe.",
	"exhaust/anti_lag": "Only what you hear: machine-gun crackle off the throttle on a turbo car.",
}

## The line for a TunerModel setting (a row on a simple page or the Quick page).
static func for_setting(s: Dictionary) -> String:
	if BY_ID.has(s.id):
		return BY_ID[s.id]
	var paths: Array = s.get("paths", [])
	return BY_PATH.get(paths[0], "") if not paths.is_empty() else ""

## The line for a raw slider (Advanced, Exhaust).
static func for_path(path: String) -> String:
	return BY_PATH.get(path, "")
