extends SceneTree

# The menu logo's wheel spins while W (the accelerate action) is held on the
# title screen, eases to a stop on release, and stays still otherwise.
# Exit code 1 on failure. Run:
#   godot --headless --audio-driver Dummy --path . -s res://tests/ui/title_logo_spin.gd

const TIMEOUT_FRAMES := 900

var failures: Array[String] = []

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_TITLE", "1")
	OS.set_environment("NEON_SPLASH", "0")
	OS.set_environment("NEON_WELCOME", "0")
	GameState.title_seen = false
	TitleScreen.splash_done = true
	AudioSettings.path = "user://title_logo_spin_test.cfg"
	change_scene_to_file("res://Game.tscn")
	_run.call_deferred()

func _run() -> void:
	var game := await _wait_game()
	if game == null:
		return _finish("Game.tscn never became ready")
	var title: TitleScreen = _node(game, "TitleScreen")
	await _frames(5)
	_check(title.visible and title.panel.visible, "the menu is showing")
	_check(title.menu_wheel != null, "the menu logo wheel is wired")
	if title.menu_wheel == null:
		return _finish("")

	# Not held: nothing moves.
	var r0 := title.menu_wheel.rotation
	await _frames(30)
	_check(is_equal_approx(title.menu_wheel.rotation, r0), "wheel is still while W is not held")
	_check(title.menu_spin == 0.0, "spin speed stays 0 without W")

	# Held: it spools up and turns.
	Input.action_press("accelerate")
	var turned := 0.0
	var last := title.menu_wheel.rotation
	var peak := 0.0
	for i in 90:
		await process_frame
		turned += absf(angle_difference(last, title.menu_wheel.rotation))
		last = title.menu_wheel.rotation
		peak = maxf(peak, title.menu_spin)
	_check(turned > 1.0, "wheel turns while W is held (turned %.2f rad)" % turned)
	_check(peak > 1.0, "spin speed rises (peak %.2f rad/s)" % peak)
	_check(peak <= TitleScreen.MENU_SPIN_MAX + 0.001, "spin speed is capped")

	# Released: it keeps going briefly (eases), then stops, with no snap back.
	Input.action_release("accelerate")
	var at_release := title.menu_spin
	await process_frame
	_check(title.menu_spin > 0.0 and title.menu_spin <= at_release, "speed eases down, not a hard stop")
	for i in 240:
		await process_frame
	_check(title.menu_spin == 0.0, "wheel comes to rest after W is released")
	var r1 := title.menu_wheel.rotation
	await _frames(30)
	_check(is_equal_approx(title.menu_wheel.rotation, r1), "wheel stays put after it settles")
	_finish("")

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _wait_game() -> Node:
	for i in TIMEOUT_FRAMES:
		var game := current_scene
		if game != null and is_instance_valid(game) and game.get("game_state") != null \
				and _node(game, "TitleScreen") != null:
			return game
		await process_frame
	return null

func _node(game: Node, cls: String) -> Node:
	for c in game.get_children():
		var sc: Script = c.get_script()
		if sc != null and sc.get_global_name() == cls:
			return c
	return null

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _finish(abort: String) -> void:
	if abort != "":
		failures.append(abort)
	for f in failures:
		printerr("FAIL: ", f)
	print("title_logo_spin: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
