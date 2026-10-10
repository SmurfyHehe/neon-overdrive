extends RefCounted

# The test build's sandbox switch (2026-10-10, Roy: "the game is incomplete
# and as long as that is the case it needs to be treated as an infinite
# testing ground"). ONE setting, neon/test_build in project.godot, read here.
# While it is on, nothing may stop a tester from driving on:
# - money never runs out: nothing is taken from tonight's cash or the bank,
#   every payment succeeds, the pump fills for free (Wallet, FuelTank);
# - no hit ends the run and no flip restarts it (Game.wrecks_on, the special
#   cars' flip rule): crashes just happen;
# - "Put me back on the road" (the pause menu row and the put_back key) parks
#   the car at the kerb, level and standing still, from anywhere: on a
#   barrier, on its roof, out of fuel, engine dead. A car left on its roof or
#   side is put back by itself (OffMapRescue);
# - the tow, which ends the night, is not needed for anything.
#
# For release: set neon/test_build=false in project.godot. Nothing else reads
# the setting.
#
# Automated tests (TestMode) run with the sandbox OFF, so they keep testing the
# real rules; a test that wants it sets NEON_TEST_BUILD=1 or `forced`.
# NEON_TEST_BUILD=0 turns it off in a play session.
#
# No class_name on purpose: preload it, so no class cache refresh is needed.

const SETTING := "neon/test_build"
const TestModeScript := preload("res://scripts/core/test_mode.gd")

## Tests: 1 forces the sandbox on, 0 off, -1 follows the setting.
static var forced := -1

static func on() -> bool:
	if forced >= 0:
		return forced == 1
	var env := OS.get_environment("NEON_TEST_BUILD")
	if env == "0":
		return false
	if env == "1":
		return true
	if TestModeScript.active():
		return false
	return bool(ProjectSettings.get_setting(SETTING, false))
