extends "res://tests/curve_drive.gd"

# Hills (#37 step R5): curve_drive.gd on a road that bends AND climbs
# (NEON_HILLS=1, crests no tighter than 600 m). Everything curve_drive checks,
# plus its hill checks: the road really climbs, the collision surface is
# where the road says to 1 cm (chunk joins included), and the player never
# leaves the ground at 120 km/h.
#
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/hill_drive.gd

func _initialize() -> void:
	if not OS.get_environment("CURVE_DRIVE_HILLS").is_valid_float():
		OS.set_environment("CURVE_DRIVE_HILLS", "1.0")
	super()
