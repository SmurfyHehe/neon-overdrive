extends SceneTree

# The Kerbside title screen (2026-10-10), on the real Game.tscn with
# NEON_TITLE=1, NEON_SPLASH=1 and NEON_WELCOME=1:
#
# - the splash runs first with the menu hidden; a key skips it
# - the first-launch card shows once, OK closes it and it is remembered
# - the Kerbside set exists with a copy of the player's car, and its camera is
#   the one in use
# - the menu has Continue, New Game, Load, Settings, Extras, Quit; Load lists
#   one row per save slot plus Back; Esc comes back to the main list
# - the news line has text; the Early Access tag is on the title
# - the radio is on the synthwave station but the save keeps the player's own
# - Continue (the drive button) starts the drive: the set is freed, the radio
#   is back on the player's station, the game camera is back
# - every brand icon size is in the .ico
# Exit code 1 on failure. Run:
#   godot --headless --audio-driver Dummy --path . -s res://tests/ui/title_kerbside.gd

const SaveStore := preload("res://scripts/save/save_store.gd")
const TIMEOUT_FRAMES := 900
const ICO := "res://assets/brand/logo_B4_combined.ico"

var failures: Array[String] = []

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_TITLE", "1")
	OS.set_environment("NEON_SPLASH", "1")
	OS.set_environment("NEON_WELCOME", "1")
	GameState.title_seen = false
	TitleScreen.splash_done = false
	AudioSettings.path = "user://title_kerbside_test.cfg"
	var cfg := ConfigFile.new()
	cfg.set_value("title", "welcome_seen", false)
	cfg.save(AudioSettings.path)
	change_scene_to_file("res://Game.tscn")
	_run.call_deferred()

func _run() -> void:
	var game := await _wait_game()
	if game == null:
		return _finish("Game.tscn never became ready")
	var gs: GameState = game.game_state
	var title: TitleScreen = _node(game, "TitleScreen")
	await _frames(3)
	_check(gs.state == GameState.State.TITLE and title.visible, "boots onto the title")

	# ---------- splash ----------
	_check(title.splash_running() and title.splash.visible, "the splash runs first")
	_check(not title.panel.visible, "the menu is hidden behind the splash")
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.physical_keycode = KEY_SPACE
	ev.pressed = true
	Input.parse_input_event(ev)
	for i in 60:
		if not title.splash_running():
			break
		await process_frame
	await _frames(2)
	_check(not title.splash_running() and not title.splash.visible, "a key skips the splash")
	_check(gs.state == GameState.State.TITLE, "skipping the splash stays on the title")
	_check(title.panel.visible, "the menu shows after the splash")

	# ---------- first-launch card ----------
	_check(title.welcome.visible, "the Early Access card shows on the first launch")
	title.welcome_button.pressed.emit()
	await _frames(2)
	_check(not title.welcome.visible and title.main_list.visible, "OK closes the card onto the menu")
	_check(not TitleScreen.welcome_due(), "the card is remembered as seen")

	# ---------- the set ----------
	var set_node := title.kerbside
	_check(set_node != null and set_node.is_inside_tree(), "the Kerbside set is built")
	if set_node != null:
		_check(set_node.camera.current, "the Kerbside camera is the one in use")
		_check(set_node.kind == PlayerCar.chassis_kind(), "the parked car is the player's car")
		_check(set_node.car.find_children("*", "MeshInstance3D", true, false).size() > 4, "the parked car has a body and wheels")
		_check(set_node.global_position.y < -300.0, "the set is clear of the road")
		var lights := set_node.find_children("*", "Light3D", true, false)
		_check(lights.size() == 1, "one lamp lights the set, got %d" % lights.size())

	# ---------- menu ----------
	var rows: Array[String] = []
	for b in title.main_list.get_children():
		rows.append((b as Button).text)
	_check(rows == ["CONTINUE", "NEW GAME", "LOAD", "SETTINGS", "EXTRAS", "QUIT"], "main rows, got %s" % [rows])
	title.load_button.pressed.emit()
	await _frames(2)
	_check(title.load_list.visible and not title.main_list.visible, "Load opens the save list")
	_check(title.load_list.get_child_count() == SaveStore.SLOTS + 1, "one row per save slot plus Back")
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	Input.parse_input_event(esc)
	for i in 60:   # input lands on a drawn frame, which can lag physics frames
		if title.main_list.visible:
			break
		await process_frame
	_check(title.main_list.visible and gs.state == GameState.State.TITLE, "Esc comes back to the main list")
	_check(title.ticker_label.text.length() > 40, "the news line has text")
	_check(title.slide.find_child("EarlyAccessTag", true, false) != null, "the Early Access tag is on the title")
	_check(not TitleScreen.news_lines().is_empty(), "there are news lines")
	_check(title.ticker_speaker.text.strip_edges() == "DALE", "the news line is Dale's, got '%s'" % title.ticker_speaker.text)
	_check(not ("Dave" in title.ticker_label.text), "no Dave on the news line")

	# ---------- radio ----------
	var radio: RadioManager = game.radio
	var synth := TitleScreen._synthwave_station()
	var own := radio.player_station()
	_check(radio.station == synth, "the title plays the synthwave station")
	radio.give_back()
	radio.tune_to(1)
	radio.borrow(synth)
	_check(radio.player_station() == 1 and radio.station == synth, "a borrowed radio still reports the player's station")
	radio.give_back()
	radio.tune_to(own)
	radio.borrow(synth)

	# ---------- drive ----------
	title.drive_button.pressed.emit()
	await _frames(4)
	_check(gs.state == GameState.State.PLAYING and not title.visible, "Continue starts the drive")
	_check(title.kerbside == null and (not is_instance_valid(set_node) or set_node.is_queued_for_deletion()),
		"the set is freed for the drive")
	_check(radio.station == own, "the radio is back on the player's station, got %d want %d" % [radio.station, own])
	var cam := game.get_viewport().get_camera_3d()
	_check(cam != null and cam.global_position.y > -300.0, "the game camera is back")

	# ---------- brand files ----------
	_check(str(ProjectSettings.get_setting("application/config/windows_native_icon", "")).ends_with(".ico"),
		"the window uses the multi-size .ico")
	_check(_ico_sizes(ICO) == [16, 20, 24, 32, 40, 48, 64, 128, 256], "the .ico holds every size, got %s" % [_ico_sizes(ICO)])
	_finish("")

## The picture sizes inside a Windows .ico, smallest first.
func _ico_sizes(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	f.get_16()
	f.get_16()
	var n := f.get_16()
	var out := []
	for i in n:
		var w := f.get_8()
		out.append(256 if w == 0 else w)
		f.seek(f.get_position() + 15)
	out.sort()
	return out

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _wait_game() -> Node:
	for i in TIMEOUT_FRAMES:
		var game := current_scene
		if game != null and is_instance_valid(game) and game.get("game_state") != null \
				and _node(game, "PauseMenu") != null and _node(game, "TitleScreen") != null:
			return game
		await physics_frame
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
	print("title_kerbside: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
