extends SceneTree

# Dirt and the wash in the real Game.tscn (2026-10-09):
# - FxPack carries a CarDirt that found the player's body material; its level
#   lands in the body shader's "dirt" uniform
# - driving (add_distance) raises it; the "dirt" effect off draws 0, on draws it
# - GameState.open_wash pauses the tree, shows the WashScreen with a model built
#   from the car's level, and close_wash (Esc) keeps what is left
# - scrubbing the whole car ends with CLEAN: level 0, uniform 0, and the screen
#   closes itself back to PLAYING
# Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/car_wash_scene.gd

var failures: Array[String] = []

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_FX", "")   # the dirt flag must be allowed on
	CarDirt.path = CarDirt.path.get_base_dir().path_join("test_car_wash_scene.cfg")
	var f := FileAccess.open(CarDirt.path, FileAccess.WRITE)
	f.store_string("")
	f = null
	change_scene_to_file("res://Game.tscn")
	_run()

func _run() -> void:
	if not await _until(func(): return _ready_game() != null, 15.0):
		return _end("Game.tscn never became ready")
	var game := _ready_game()
	await physics_frame
	await physics_frame
	var fx: Variant = game.get("fx")
	_check(fx != null and fx.get("dirt") is CarDirt, "FxPack has no CarDirt")
	if fx == null or not (fx.get("dirt") is CarDirt):
		return _end("")
	var dirt: CarDirt = fx.dirt
	var mat: ShaderMaterial = game.player.chassis_visual.get_meta("body_mat")
	_check(mat != null, "player body has no body_mat")
	var screen: WashScreen = _find(game, WashScreen)
	_check(screen != null, "Game has no WashScreen")
	if mat == null or screen == null:
		return _end("")
	var gs: GameState = game.game_state

	# --- level -> uniform ---
	_check(dirt.level < 0.001, "a fresh file should start clean (the car settling on spawn is a few millimetres): %s" % dirt.level)
	dirt.add_distance(CarDirt.FULL_NIGHT_METRES * 0.6, false)
	_check(is_equal_approx(dirt.level, 0.6), "level after 60%% of a night: %s" % dirt.level)
	_check(is_equal_approx(float(mat.get_shader_parameter("dirt")), 0.6), "uniform should follow the level: %s" % str(mat.get_shader_parameter("dirt")))
	fx.set_effect("dirt", false)
	_check(float(mat.get_shader_parameter("dirt")) == 0.0, "dirt off should draw 0: %s" % str(mat.get_shader_parameter("dirt")))
	_check(dirt.level > 0.5, "dirt off should keep the level: %s" % dirt.level)
	fx.set_effect("dirt", true)
	_check(is_equal_approx(float(mat.get_shader_parameter("dirt")), 0.6), "dirt on again should draw the level: %s" % str(mat.get_shader_parameter("dirt")))
	# Driving while on adds; the car is parked so a tick adds nothing.
	var before := dirt.level
	await physics_frame
	await physics_frame
	_check(dirt.level >= before and dirt.level < before + 0.01, "a parked car should barely change: %s -> %s" % [before, dirt.level])
	_check(InputMap.has_action("wash_up") and InputMap.has_action("wash_right"), "wash actions not registered")

	# --- open, leave early ---
	gs.pause()
	gs.open_wash()
	_check(gs.state == GameState.State.WASH, "open_wash from the pause menu: state %d" % gs.state)
	_check(paused, "the wash should keep the tree paused")
	_check(screen.visible and screen.active and screen.model != null, "WashScreen did not open")
	if screen.model == null:
		return _end("")
	_check(absf(screen.model.start - 0.6 * 0.85) < 0.08, "model grime should come from the car's level: %s" % screen.model.start)
	screen.scrub(Vector2.RIGHT, 0.3)
	var left := screen.model.remaining()
	_check(left < screen.model.start, "one stroke should take some grime off")
	gs.toggle_pause()  # Esc
	_check(gs.state == GameState.State.PLAYING and not paused, "Esc should leave the wash to PLAYING: %d" % gs.state)
	_check(not screen.visible and not screen.active, "WashScreen should hide on Esc")
	_check(is_equal_approx(dirt.level, left), "leaving early should keep what is left: %s vs %s" % [dirt.level, left])
	_check(is_equal_approx(float(mat.get_shader_parameter("dirt")), left), "uniform after a part wash: %s" % str(mat.get_shader_parameter("dirt")))

	# --- full wash ---
	gs.open_wash()
	_check(gs.state == GameState.State.WASH and screen.active, "open_wash from the road")
	var m := screen.model
	var row := 0.0
	var right := true
	var strokes := 0
	while not m.done and row <= WashScreen.Model.ROWS + 1.0 and strokes < 100000:
		m.sponge = Vector2(0.0 if right else WashScreen.Model.COLS, row)
		var dir := Vector2.RIGHT if right else Vector2.LEFT
		for i in 200:
			screen.scrub(dir, 0.05)
			strokes += 1
			if m.done:
				break
		row += WashScreen.Model.SPONGE_R
		right = not right
		if row > WashScreen.Model.ROWS + 1.0 and not m.done:
			row = 0.0  # second pass
			if strokes > 20000:
				break
	_check(m.done, "sweeping should finish the wash (left %s)" % m.remaining())
	_check(dirt.level == 0.0, "a finished wash should leave the car clean: %s" % dirt.level)
	_check(float(mat.get_shader_parameter("dirt")) == 0.0, "uniform after the wash: %s" % str(mat.get_shader_parameter("dirt")))
	var closed := await _until(func(): return gs.state == GameState.State.PLAYING, 5.0)
	_check(closed, "the screen should close itself after CLEAN")
	_check(not paused, "tree should be unpaused after the wash")

	# --- saved ---
	var cfg := ConfigFile.new()
	_check(cfg.load(CarDirt.path) == OK and float(cfg.get_value("dirt", "level", -1.0)) == 0.0, "clean level not saved")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CarDirt.path))
	_end("")

func _end(msg: String) -> void:
	if msg != "":
		failures.append(msg)
	for f in failures:
		printerr("FAIL: ", f)
	print("car_wash_scene: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _ready_game() -> Node:
	var g := current_scene
	if g != null and is_instance_valid(g) and g.get("player") != null and g.get("game_state") != null and g.get("fx") != null:
		return g
	return null

func _until(cond: Callable, timeout_s: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if (Time.get_ticks_msec() - t0) / 1000.0 > timeout_s:
			return false
		await process_frame
	return true

func _find(game: Node, type) -> Node:
	for c in game.get_children():
		if is_instance_of(c, type):
			return c
	return null

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
