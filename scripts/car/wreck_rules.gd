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
# - below WRECK_KMH: a bump. Cars push each other, nothing ends.
# - WRECK_KMH and up: a wreck. The run ends and half of tonight's cash is gone
#   (all of it when bad cops are on you). The night goes on.
# - NIGHT_END_KMH and up: a huge crash. Same cost, and the night ends too.
# - The first wreck of a save is free: Moose picks you up and Walt fixes the
#   car, once.
#
# Both thresholds are first guesses to be tuned by driving.
# No class_name on purpose: preload it, so no class cache refresh is needed.

enum Outcome { BUMP, WRECK, NIGHT_END }

const WRECK_KMH := 55.0
const NIGHT_END_KMH := 100.0

## The wall-equivalent speed (same unit as `closing`). `other_mass` <= 0 means
## the other thing does not move (a wall, a barrier, a parked far car).
static func wall_speed(closing: float, own_mass: float, other_mass: float) -> float:
	if other_mass <= 0.0 or own_mass <= 0.0:
		return maxf(closing, 0.0)
	return maxf(closing, 0.0) * other_mass / (own_mass + other_mass)

static func outcome(wall_kmh: float) -> Outcome:
	if wall_kmh >= NIGHT_END_KMH:
		return Outcome.NIGHT_END
	if wall_kmh >= WRECK_KMH:
		return Outcome.WRECK
	return Outcome.BUMP

## What a wreck takes from tonight's cash. The bank is never touched.
static func cash_loss(cash: int, bad_cops: bool, free: bool) -> int:
	if free or cash <= 0:
		return 0
	if bad_cops:
		return cash
	return cash - cash / 2  # half, and the odd dollar goes with it
