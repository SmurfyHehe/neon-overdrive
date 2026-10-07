extends SceneTree

# Tuner job sheet (UI blend PR 2): the dyno sheet's "vs stock" column reads
# "stock" on the stock setup and shows signed ▲/▼ deltas after a preset.
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/tuner_vs_stock.gd

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
	game.game_state.toggle_tuning()
	await process_frame
	screen._on_preset("Stock")
	for k in ["top", "accel", "brake", "grip"]:
		_check(screen.stats.vs[k].text == "stock", "stock setup: %s should read 'stock', got '%s'" % [k, screen.stats.vs[k].text])
	screen._on_preset("Grip")
	var shown := 0
	for k in ["top", "accel", "brake", "grip"]:
		var t: String = screen.stats.vs[k].text
		if t.contains("▲") or t.contains("▼"):
			shown += 1
	_check(shown >= 1, "the Grip preset should change at least one stat vs stock")
	_check(screen.stats.vs.balance.text == "", "balance has no delta")
	game.game_state.toggle_tuning()
	_end("")

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
		print("FAIL ", msg)

func _end(msg: String) -> void:
	if msg != "":
		failures.append(msg)
	print("tuner_vs_stock: %s" % ("PASS" if failures.is_empty() else "FAIL (%d)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
