extends Node

# Physics tick rate override (Phase C, 2026-10-05). The game runs at 120 Hz now
# (project setting physics/common/physics_ticks_per_second; GEVP recommends at least
# 120, and its tyres and suspension are steadier there). Most of the old test suite
# counts physics ticks as sixtieths of a second, so tests/run_tests.bat sets
# NEON_TICKS=60 for them; this autoload applies it before any scene loads. Normal
# play never sets it.

func _init() -> void:
	var v := OS.get_environment("NEON_TICKS")
	if v.is_valid_int():
		Engine.physics_ticks_per_second = clampi(int(v), 30, 240)
	# Catch-up steps per frame (project setting: 4, so a slow frame turns into
	# slow motion instead of a pile of physics steps). NEON_MAX_STEPS overrides
	# it for before/after measurements (8 is the engine default).
	var m := OS.get_environment("NEON_MAX_STEPS")
	if m.is_valid_int():
		Engine.max_physics_steps_per_frame = clampi(int(m), 1, 32)
