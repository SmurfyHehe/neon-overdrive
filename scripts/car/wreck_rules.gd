extends RefCounted

# Ending a run on a crash: the rules (decided 2026-10-10). Pure numbers, no
# nodes, so the test can check every rule without booting the game.
#
# A hit is judged by how fast the two things were closing on each other and
# how heavy the other one is, never by how much the player's own speed
# changed (CarDamage.IMPACT_ACCEL does that, for broken parts; a hard brake
# into a nudge reads the same there as a real crash). The measure is the
# speed of a hit on a solid wall that would be just as bad:
#
#   wall speed = closing speed * other mass / (own mass + other mass)
#
# A wall (or anything else that does not move) counts as endlessly heavy, so
# its wall speed is the closing speed itself. Two equal cars closing at
# 100 km/h is a 50 km/h wall; a small car into a heavy pickup is worse than
# the pickup's driver gets.
#
# - below WRECK_KMH: a bump. Cars push each other, nothing counts.
# - WRECK_KMH and up: a counted hit. It adds to the totalled meter
#   (totalled_meter.gd: 0.30 up to BIG_HIT_KMH, 0.60 from there).
# - no single hit ends a run (Roy 1160). At 100% on the meter the car is
#   totalled: the night ends and half of tonight's cash is gone (all of it
#   when bad cops are on you); the first total of a save is free.
#
# Both thresholds are first guesses to be tuned by driving.
# No class_name on purpose: preload it, so no class cache refresh is needed.

const WRECK_KMH := 55.0
const BIG_HIT_KMH := 100.0

## The wall-equivalent speed (same unit as `closing`). `other_mass` <= 0 means
## the other thing does not move (a wall, a barrier, a parked far car).
static func wall_speed(closing: float, own_mass: float, other_mass: float) -> float:
	if other_mass <= 0.0 or own_mass <= 0.0:
		return maxf(closing, 0.0)
	return maxf(closing, 0.0) * other_mass / (own_mass + other_mass)

## What a total takes from tonight's cash. The bank is never touched.
static func cash_loss(cash: int, bad_cops: bool, free: bool) -> int:
	if free or cash <= 0:
		return 0
	if bad_cops:
		return cash
	return cash - cash / 2  # half, and the odd dollar goes with it
