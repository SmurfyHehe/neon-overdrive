extends SceneTree

# Vanity plates (R1), on the real Game.tscn:
# - clean(): upper case, letters and numbers only, at most 8
# - the P1 coupe carries a front and a rear plate with the saved text
# - typing in the Tuner's Sound page box cleans the text in the box, changes
#   both plates live and keeps it for next time; the box counts as typing, so
#   game keys don't fire while it has focus
# Uses a scratch file, never the player's own plate. Optional NEON_SHOT=<png>
# (real renderer) saves the rear plate in the chase view.
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tests/vanity_plate.gd

const SCRATCH := "user://test_vanity_plate.txt"

var failures: Array[String] = []

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	VanityPlate.file = SCRATCH
	var f := FileAccess.open(SCRATCH, FileAccess.WRITE)  # start from a known plate (overwrite; never deleted)
	f.store_string("night 7!")
	f.close()
	change_scene_to_file("res://Game.tscn")
	_run()

func _run() -> void:
	_check(VanityPlate.clean("ab-1 2c") == "AB12C", "clean drops other characters: %s" % VanityPlate.clean("ab-1 2c"))
	_check(VanityPlate.clean("abcdefghijk") == "ABCDEFGH", "clean keeps at most 8")
	_check(VanityPlate.clean("ä!? ") == "", "nothing usable is empty")
	var t0 := Time.get_ticks_msec()
	while (current_scene == null or current_scene.get("game_state") == null) and Time.get_ticks_msec() - t0 < 15000:
		await process_frame
	var game := current_scene
	var visual: Node3D = game.player.chassis_visual
	var plates := []
	for c in visual.get_children():
		if c.name.begins_with("Plate_"):
			plates.append(c)
	_check(plates.size() == 2, "the coupe should have a front and a rear plate: %d" % plates.size())
	_check(VanityPlate.shown(visual) == "NIGHT7", "the plates should show the saved text cleaned: %s" % VanityPlate.shown(visual))
	var rear: Node3D = visual.get_node_or_null("Plate_Rear")
	_check(rear != null and rear.global_basis.z.dot(game.player.global_basis.z) > 0.9, "the rear plate should face backwards")

	var screen: TunerScreen = null
	for c in game.get_children():
		if c is TunerScreen:
			screen = c
	game.game_state.toggle_tuning()
	await process_frame
	screen.show_page("sound")
	await process_frame
	screen.plate_edit.grab_focus()
	_check(game.game_state.typing_in_text(), "the plate box should count as typing")
	screen.plate_edit.text = "drift-99"
	screen.plate_edit.text_changed.emit("drift-99")
	_check(screen.plate_edit.text == "DRIFT99", "the box should show the cleaned plate: %s" % screen.plate_edit.text)
	_check(VanityPlate.shown(visual) == "DRIFT99", "the car's plates should change as you type")
	_check(FileAccess.get_file_as_string(SCRATCH) == "DRIFT99", "it should be kept for next time")
	screen.plate_edit.release_focus()
	game.game_state.toggle_tuning()
	await process_frame

	var shot := OS.get_environment("NEON_SHOT")
	if shot != "":
		root.size = Vector2i(1280, 720)
		for i in 30:
			await process_frame
		root.get_texture().get_image().save_png(shot)
		print("screenshot: ", shot)
	_end("")

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
		print("FAIL ", msg)

func _end(msg: String) -> void:
	if msg != "":
		failures.append(msg)
	print("vanity_plate: %s" % ("PASS" if failures.is_empty() else "FAIL (%d)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
