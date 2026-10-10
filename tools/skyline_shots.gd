extends SceneTree

# World step 1 (2026-10-10): screenshots of the roof shapes, the facade wear
# and the four district landmarks, for judging them by eye. Boots the game's
# night scene with no traffic, hides its own chunks, and for each district
# builds ten chunks of the first run of that district around its landmark
# chunk (Districts.LANDMARK_CHUNK, 8) on a straight flat road, then shoots it
# from the street and from a low skyline view. Needs the real renderer (no
# --headless). Writes PNGs to user://skyline_shots/<tag>/.
#
#   <godot> --path . --audio-driver Dummy -s res://tools/skyline_shots.gd [-- <tag>]
#
# The landmark chunk is hard-coded to 8 so the same tool can shoot a
# checkout from before this step (no Districts.LANDMARK_CHUNK there).

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const B := preload("res://scripts/world/road_chunk_builder.gd")
const LANDMARK_CHUNK := 8
const RUN := 16

var game: Node

func _initialize() -> void:
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	game = Harness.boot(self, 0, 300.0, 3)
	_run.call_deferred()

func _run() -> void:
	for i in 30:
		await process_frame
	var tag := "shots"
	for a in OS.get_cmdline_user_args():
		tag = a
	var dir := "user://skyline_shots/%s" % tag
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	for c in game.get("chunk_pool"):
		(c.root as Node3D).visible = false
	# no HUD, and the car parked out of sight (a moving car would shift the
	# floating origin under the chunks built here)
	for c in game.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
	var player: Node3D = game.get("player")
	if player != null:
		player.visible = false
		if player is RigidBody3D:
			(player as RigidBody3D).freeze = true
	var D := B.Districts
	var runs := {}
	for r in 60:
		var n: String = D.name_of_run(r)
		if not runs.has(n):
			runs[n] = r
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.make_current()
	# chunk `origin` spans z 0 .. -50; the landmark chunk is two chunks on,
	# so its first building (slot 0, the player's side, x > 0) stands at
	# z ~ -112. street: the driver's view. facade: the building fronts from
	# the sidewalk, for the wear. skyline: over the roofs, for the tops and
	# the landmark. [position, aim, fov]
	var views := {
		"street": [Vector3(-3.5, 1.4, 8.0), Vector3(0.0, 10.0, -110.0), 60.0],
		"facade": [Vector3(-4.0, 1.6, -20.0), Vector3(16.0, 7.0, -55.0), 60.0],
		"skyline": [Vector3(-22.0, 20.0, 70.0), Vector3(6.0, 45.0, -112.0), 65.0],
	}
	for n in runs:
		var r: int = runs[n]
		var first := r * RUN + LANDMARK_CHUNK - 6
		var origin := first + 4
		var roots := []
		for idx in range(first, first + 10):
			var chunk := B.build_chunk(idx, game._section_at(idx - 1), game._section_at(idx), origin)
			game.add_child(chunk)
			roots.append(chunk)
		for v in views:
			cam.fov = views[v][2]
			cam.global_position = views[v][0]
			cam.look_at(views[v][1])
			for i in 12:
				await process_frame
			var path := "%s/%s_%s.png" % [dir, n, v]
			root.get_viewport().get_texture().get_image().save_png(path)
			print("wrote ", ProjectSettings.globalize_path(path))
		for chunk in roots:
			chunk.queue_free()
		await process_frame
	quit(0)
