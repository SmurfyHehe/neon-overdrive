extends SceneTree

# One fixed, repeatable frame of the night scene, for before/after look
# checks of rendering changes (perf pass 2026-10-09). Boots the game with
# the test harness (its own settings file, not yours), the road seed and
# clock pinned, no traffic, the player parked where it spawns, and saves
# the chase view after a settling delay. Two runs of the same code give the
# same PNG; diff them with any image tool. Needs the real renderer.
#
#   NEON_SHOT=<path.png> [NEON_SHOT_FRAMES=<n>] <godot> --path . -s res://tools/look_shot.gd
#
# NEON_SHOT defaults to user://look_shot.png; NEON_SHOT_FRAMES (default 150)
# is how many frames to wait, enough for the sky and lamp pools to settle.

var game: Node

func _initialize() -> void:
	if OS.get_environment("NEON_ROAD_SEED") == "":
		OS.set_environment("NEON_ROAD_SEED", "777")
	if OS.get_environment("NEON_CLOCK") == "":
		OS.set_environment("NEON_CLOCK", "22:30")
	if OS.get_environment("NEON_SEED") == "":
		OS.set_environment("NEON_SEED", "777")   # buildings, signs and window lights
	OS.set_environment("NEON_CURVES", "0.5")
	OS.set_environment("NEON_HILLS", "0")
	game = (preload("res://tests/traffic/traffic_harness.gd") as GDScript).boot(self, 0, 150.0, 777)
	_run.call_deferred()

func _run() -> void:
	var frames := 150
	var env := OS.get_environment("NEON_SHOT_FRAMES")
	if env.is_valid_int() and int(env) > 0:
		frames = int(env)
	for i in frames:
		await process_frame
	var path := OS.get_environment("NEON_SHOT")
	if path == "":
		path = "user://look_shot.png"
	var img := root.get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("look_shot: %s (%dx%d, draw_calls=%d objects=%d) -> %s" % [
		error_string(err), img.get_width(), img.get_height(),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), ProjectSettings.globalize_path(path)])
	quit(0 if err == OK else 1)
