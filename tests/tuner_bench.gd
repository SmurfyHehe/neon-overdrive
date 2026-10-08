extends SceneTree

# The car on the bench (Tuner UI overhaul PR 1), on the real Game.tscn:
# - opening the Tuner makes the tuner camera current, dims the street (its own
#   environment copy, the street's is untouched), lights the work lamp and hides
#   the HUD and warning lights; closing gives all of it back
# - every page has a shot, and the part pages outline their part on screen
# - the camera swings toward the new page's shot after Q/E
# - opened from the cockpit view, the body shows and the cockpit comes back
# Headless by default. With the real renderer, NEON_SHOT_DIR=<folder> saves a
# 1280x720 screenshot per page and prints the frame rate with the Tuner closed
# and open (vsync off):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/tuner_bench.gd
#   set NEON_SHOT_DIR=C:\shots & Godot_v4.7.2-stable_win64_console.exe --audio-driver Dummy --resolution 1280x720 --path . -s res://tests/tuner_bench.gd

var failures: Array[String] = []

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	change_scene_to_file("res://Game.tscn")
	_run()

func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while (current_scene == null or current_scene.get("game_state") == null) and Time.get_ticks_msec() - t0 < 15000:
		await process_frame
	var game := current_scene
	var screen: TunerScreen = null
	for c in game.get_children():
		if c is TunerScreen:
			screen = c
	if screen == null:
		return _end("no TunerScreen")
	var shots := OS.get_environment("NEON_SHOT_DIR")
	root.size = Vector2i(1280, 720)  # headless starts at 64x64
	if shots != "":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# let the car settle on its springs
	for i in 90:
		await physics_frame
	var chase: ChaseCamera = game.camera
	var hud: CanvasLayer = null
	for c in game.get_children():
		if c is Hud:
			hud = c
	var fps_closed := 0.0
	if shots != "":
		fps_closed = await _fps()

	game.game_state.toggle_tuning()
	await process_frame
	await process_frame
	var bench := screen.bench
	_check(bench != null and bench.is_open, "the bench should open with the Tuner")
	_check(root.get_camera_3d() == bench.cam, "the tuner camera should be current")
	_check(bench.work_light.visible, "the work light should be on")
	_check(bench.cam.environment != null and bench.cam.environment != chase.get_world_3d().environment, "the tuner camera should dim its own copy of the environment")
	if bench.cam.environment != null and chase.get_world_3d().environment != null:
		_check(bench.cam.environment.tonemap_exposure < chase.get_world_3d().environment.tonemap_exposure, "the street should be dimmed")
	_check(hud == null or not hud.visible, "the HUD should hide under the bench")
	print("viewport %s, window %s, plate %s, body %s" % [root.get_visible_rect().size, screen.car_window.size, screen.page_plate.size, screen.car_window.get_parent().get_parent().size])
	_check(screen.car_window.size.y > 150.0, "the car window should be at least 150 px tall: %.0f" % screen.car_window.size.y)

	for id in screen.page_ids:
		screen.show_page(id)
		await process_frame  # the page plate's new height lays out
		await process_frame
		bench.snap()
		await process_frame
		_check(TunerBench.SHOTS.has(id), "page %s has no shot" % id)
		_check(not bench.outline.lines.is_empty(), "page %s outlines nothing" % id)
		# the part (or the car) is in front of the camera and inside the car window
		var centre := bench.project(bench._shot_look(id))
		var win := screen.car_window.get_global_rect().grow(40.0)
		_check(not bench.behind_camera(bench._shot_look(id)) and win.has_point(centre),
			"page %s: the part should sit in the car window (%s not in %s)" % [id, centre, win])
		if shots != "":
			for i in 3:
				await process_frame
			var path := shots.path_join("tuner_%02d_%s.png" % [screen.page_ids.find(id), id])
			root.get_texture().get_image().save_png(path)
			print("screenshot: ", path)

	# Q/E: the camera blends toward the next shot instead of jumping
	screen.show_page("tyres")
	bench.snap()
	var before := bench.cam.global_position
	screen.show_page("diff")
	await process_frame
	var moved := bench.cam.global_position.distance_to(before)
	_check(moved > 0.0 and moved < 3.0, "the camera should blend between shots, moved %.2f m in one frame" % moved)

	var fps_open := 0.0
	if shots != "":
		fps_open = await _fps()
		print("fps: tuner closed %.0f, tuner open %.0f" % [fps_closed, fps_open])

	game.game_state.toggle_tuning()
	await process_frame
	_check(not bench.is_open and root.get_camera_3d() == chase, "closing should give the view back to the chase camera")
	_check(not bench.work_light.visible, "the work light should go off")
	_check(hud == null or hud.visible, "the HUD should come back")

	# From the cockpit view: the body shows on the bench, the cockpit comes back after.
	chase.set_view(ChaseCamera.View.COCKPIT)
	game.game_state.toggle_tuning()
	await process_frame
	_check(chase.view == ChaseCamera.View.CHASE, "the bench should show the car's body, not the cockpit")
	game.game_state.toggle_tuning()
	await process_frame
	_check(chase.view == ChaseCamera.View.COCKPIT, "the cockpit view should come back after the Tuner")
	chase.set_view(ChaseCamera.View.CHASE)
	_end("")

func _fps() -> float:
	for i in 30:
		await process_frame
	var t := Time.get_ticks_usec()
	for i in 120:
		await process_frame
	return 120.0 / ((Time.get_ticks_usec() - t) / 1e6)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
		print("FAIL ", msg)

func _end(msg: String) -> void:
	if msg != "":
		failures.append(msg)
	print("tuner_bench: %s" % ("PASS" if failures.is_empty() else "FAIL (%d)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
