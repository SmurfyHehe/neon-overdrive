extends SceneTree

# World step 3 (W6, 2026-10-10): a contact sheet of every district kind, for
# checking by eye that two kinds can be told apart from the skyline alone.
# Boots the game's night scene with no traffic, hides its own chunks, and for
# each kind in Districts.SPECS builds ten chunks of its first run in the loop
# around the landmark chunk on a straight flat road, then shoots it twice:
#   far   from 18 m over the road, 150 m short of the landmark: the skyline
#   near  the driver's view down the street
# Needs the real renderer (no --headless). Writes one PNG per shot and
# sheet.jpg (every kind, far beside near, named) to
# user://district_sheet/<tag>/.
#
#   <godot> --path . --audio-driver Dummy -s res://tools/district_sheet.gd [-- <tag>]

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const B := preload("res://scripts/world/road_chunk_builder.gd")
const CELL := Vector2i(640, 360)

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
	var dir := "user://district_sheet/%s" % tag
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
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.make_current()
	# the name of the kind, burnt into each shot
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var label := Label.new()
	label.position = Vector2(24.0, 16.0)
	label.add_theme_font_size_override("font_size", 44)
	label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.4))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	label.add_theme_constant_override("outline_size", 10)
	layer.add_child(label)
	# chunk `origin` spans z 0 .. -50; the landmark chunk is two chunks on,
	# so its building (slot 0, the player's side, x > 0) stands at z ~ -112.
	# [position, aim, fov]
	var views := {
		"far": [Vector3(-3.5, 18.0, 40.0), Vector3(6.0, 20.0, -112.0), 55.0],
		"near": [Vector3(-3.5, 1.4, 8.0), Vector3(0.0, 9.0, -110.0), 62.0],
	}
	var names: Array = D.SPECS.keys()
	var sheet := Image.create(CELL.x * 2, CELL.y * names.size(), false, Image.FORMAT_RGB8)
	for k in names.size():
		var n: String = names[k]
		var r: int = D.ORDER.find(n)
		var first := r * D.RUN + D.LANDMARK_CHUNK - 6
		var origin := first + 4
		var roots := []
		for idx in range(first, first + 10):
			var chunk := B.build_chunk(idx, game._section_at(idx - 1), game._section_at(idx), origin)
			game.add_child(chunk)
			roots.append(chunk)
		var col := 0
		for v in views:
			label.text = "%s  (%s)" % [n, v]
			cam.fov = views[v][2]
			cam.global_position = views[v][0]
			cam.look_at(views[v][1])
			for i in 12:
				await process_frame
			# what the view costs to draw, for comparing two branches
			print("cost %-12s %-4s draw calls %d, objects %d, primitives %d" % [n, v,
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
			var img := root.get_viewport().get_texture().get_image()
			var path := "%s/%s_%s.png" % [dir, n, v]
			img.save_png(path)
			img.convert(Image.FORMAT_RGB8)
			img.resize(CELL.x, CELL.y, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(col * CELL.x, k * CELL.y))
			col += 1
		for chunk in roots:
			chunk.queue_free()
		await process_frame
	var sheet_path := "%s/sheet.jpg" % dir
	sheet.save_jpg(sheet_path, 0.88)
	print("wrote ", ProjectSettings.globalize_path(sheet_path))
	quit(0)
