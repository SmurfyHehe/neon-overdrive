extends "res://tests/core/drive_clean.gd"

# The clean-driving test (tests/core/drive_clean.gd) on a road with bends and
# hills: the bot has to slow for the bends it cannot take at its target speed
# and still touch nothing.
#
#   godot --headless --fixed-fps 120 --path . -s res://tests/core/drive_bends.gd

func _initialize() -> void:
	if OS.get_environment("DRIVE_CURVES") == "":
		OS.set_environment("DRIVE_CURVES", "1.0")
	if OS.get_environment("DRIVE_HILLS") == "":
		OS.set_environment("DRIVE_HILLS", "1.0")
	super()
