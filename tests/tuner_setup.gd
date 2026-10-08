extends SceneTree

# Tuner Setup and Mechanic pages (Tuner UI overhaul PR 4), on the real Game.tscn:
# - the Grip to Drift dial: notch 0 is the Grip preset, 10 the Drift preset,
#   5 stock, and a notch between blends in proportion; the slider drives it
# - setup sheets A-C save the whole setup and load it back
# - the Setup and Mechanic pages have their graphic (dial, job ticket)
# - the Test run verdict in words
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tests/tuner_setup.gd

const SLOT_FILE := "user://autotune/test_setup_sheets.json"

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
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute("user://autotune")
	var sf := FileAccess.open(SLOT_FILE, FileAccess.WRITE)  # start empty (overwrite; never deleted)
	sf.store_string("{}")
	sf.close()
	screen.auto.slots = TuneSlots.new(SLOT_FILE)
	game.game_state.toggle_tuning()
	await process_frame
	var model := screen.model
	var spec: Dictionary = screen.player.spec

	# --- the dial
	var grip := CarSpec.clone_spec(model.stock)
	TunerModel.new(null, grip, model.stock).apply_preset("Grip")
	var drift := CarSpec.clone_spec(model.stock)
	TunerModel.new(null, drift, model.stock).apply_preset("Drift")
	screen.character_slider.value = 0
	_check(_same(spec, grip, "front_arb_ratio") and _same(spec, grip, "aero_downforce_coefficient_rear"), "dial at 0 should be the Grip preset")
	_check(model.preset_label() == "Grip 5", "dial at 0 reads Grip 5: %s" % model.preset_label())
	screen.character_slider.value = 10
	_check(_same(spec, drift, "rear_locking_differential_engage_torque") and _same(spec, drift, "max_steering_angle"), "dial at 10 should be the Drift preset")
	screen.character_slider.value = 8
	var p := "max_steering_angle"
	var want := lerpf(TuneParams.get_value(model.stock, p), TuneParams.get_value(drift, p), 0.6)
	_check(absf(TuneParams.get_value(spec, p) - want) < 0.002, "dial at 8 should be 60%% of the way to Drift: %.3f vs %.3f" % [TuneParams.get_value(spec, p), want])
	_check(model.preset_label() == "Drift 3", "dial at 8 reads Drift 3: %s" % model.preset_label())
	screen.character_slider.value = 5
	_check(_same(spec, model.stock, p) and _same(spec, model.stock, "front_arb_ratio") and model.preset_label() == "Stock", "dial at 5 should be stock: %s" % model.preset_label())
	screen._on_preset("Drift")
	_check(roundi(screen.character_slider.value) == 10, "the Drift preset card should move the dial to Drift")

	# --- sheets
	screen.save_sheet("Sheet A")
	_check(screen.auto.slots.has("Sheet A") and screen.sheet_labels["Sheet A"].text.contains("saved"), "Save A should store the setup: %s" % screen.sheet_labels["Sheet A"].text)
	_check(screen.sheet_labels["Sheet B"].text.contains("empty"), "B should read empty")
	screen._on_preset("Stock")
	_check(_same(spec, model.stock, p), "back to stock before loading")
	_check(screen.load_sheet("Sheet A"), "Load A should work")
	_check(_same(spec, drift, p) and _same(spec, drift, "rear_locking_differential_engage_torque"), "Load A should bring the Drift setup back")
	_check(model.preset_label() == "Sheet A", "the header should name the sheet: %s" % model.preset_label())
	_check(not screen.load_sheet("Sheet C"), "an empty sheet loads nothing")

	# --- graphics on Setup and Mechanic
	screen.show_page("setup")
	await process_frame
	_check(screen.graphic_plate.visible and screen.graphics.setup.visible, "Setup should show the dial graphic")
	_check(screen.graphics.setup.dial.readout == "Sheet A", "after loading a sheet the dial should name it: %s" % screen.graphics.setup.dial.readout)
	screen.show_page("mechanic")
	await process_frame
	_check(screen.graphics.mechanic.visible and String(screen.graphics.mechanic.ctx.get("goal", "")) != "", "Mechanic should show the job ticket with the goal")

	# --- the verdict
	var stock_m := {"t_0_100": 5.6, "top_speed_kmh": 244.0, "brake_dist_100": 42.7, "peak_lat_g": 1.3}
	var mine := {"t_0_100": 5.37, "top_speed_kmh": 244.2, "brake_dist_100": 44.0, "peak_lat_g": 1.3}
	var v := TunerScreen.PitWall.verdict_words(mine, stock_m)
	_check(v == "Quicker to 100 by 0.23 s. But stops 1.3 m longer. Top speed and grip the same.", "verdict: %s" % v)
	_check(TunerScreen.PitWall.verdict_words(stock_m, stock_m) == "Same as stock on the test track.", "stock vs stock verdict")

	var shot := OS.get_environment("NEON_SHOT_DIR")
	if shot != "":
		for id in ["setup", "mechanic"]:
			screen.show_page(id)
			for i in 3:
				await process_frame
			screen.bench.snap()
			for i in 3:
				await process_frame
			root.get_texture().get_image().save_png(shot.path_join("setup_%s.png" % id))
	game.game_state.toggle_tuning()
	_end("")

func _same(a: Dictionary, b: Dictionary, path: String) -> bool:
	return absf(TuneParams.get_value(a, path) - TuneParams.get_value(b, path)) < 0.001

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
		print("FAIL ", msg)

func _end(msg: String) -> void:
	if msg != "":
		failures.append(msg)
	print("tuner_setup: %s" % ("PASS" if failures.is_empty() else "FAIL (%d)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
