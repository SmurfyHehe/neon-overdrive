extends SceneTree

# Title screen, pause screen and Settings from both (title/loading pieces 3-5,
# 2026-10-10), on the real Game.tscn with NEON_TITLE=1:
#
# Title
# - boots into TITLE: title visible, HUD hidden, the world frozen once the car
#   has settled; Esc does nothing there
# - Settings opens from the title (Game tab included) and closes back to it
# - Drive -> PLAYING, tree running, HUD back
# Pause screen
# - the list is exactly Resume, Restart night, Settings, Photo mode, Quit to
#   title, with the night / clock / cash plate
# - a stall pause and an alt-tab pause open the same screen with one amber line;
#   a plain pause has none
# - a chase refuses the pause (no menu, a refusal signal), and a chase lets the
#   quit-to-title box say "bust"
# - Restart asks first; Esc on the box means No and does NOT resume
# - Photo mode opens from the pause screen and Esc comes back to it
# - in a race the second row says "Quit race" and emits race_quit_requested
# Settings
# - Voices and Menu sounds sliders exist; Tips toggles and saves
# - Quit to title -> Yes reloads onto the title
# Exit code 1 on failure. Run (a window opens for a few seconds):
#   Godot_v4.7.2-stable_win64_console.exe --path . -s res://tests/ui/title_and_pause.gd

const SaveStore := preload("res://scripts/save/save_store.gd")
const TIMEOUT_FRAMES := 900

var failures: Array[String] = []
var releases := {}
var tick := 0
var refused := 0
var race_quits := 0

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_TITLE", "1")
	GameState.title_seen = false
	AudioSettings.path = "user://title_pause_test.cfg"
	DirAccess.remove_absolute(AudioSettings.path)
	change_scene_to_file("res://Game.tscn")
	_run.call_deferred()

func _run() -> void:
	var first := await _wait_game(null)
	if first == null:
		return _finish("Game.tscn never became ready")
	var gs: GameState = first.game_state
	var title: TitleScreen = _node(first, "TitleScreen")
	var menu: PauseMenu = _node(first, "PauseMenu")

	# ---------- title ----------
	_check(gs.state == GameState.State.TITLE, "boot should land on the title screen")
	_check(title.visible and not _node(first, "Hud").visible, "title shows, HUD hides behind it")
	_check(await _wait_until(func() -> bool: return paused), "the title should freeze the world")
	_tap(KEY_ESCAPE)
	await _frames(16)
	_check(gs.state == GameState.State.TITLE, "Esc must not leave the title")

	title.settings_button.pressed.emit()
	_check(menu.settings.visible and not title.panel.visible, "Settings should open from the title")
	_check(menu.settings.PAGES.has("Game"), "Settings should have a Game tab")
	menu.settings.close()
	_check(title.panel.visible and gs.state == GameState.State.TITLE, "closing Settings should return to the title")

	title.drive_button.pressed.emit()
	await _frames(4)
	_check(gs.state == GameState.State.PLAYING and not paused, "Drive should start the run")
	_check(_node(first, "Hud").visible and not title.visible, "HUD comes back and the title hides on Drive")

	# ---------- pause screen: rows, plate ----------
	gs.pause()
	await _frames(2)
	_check(menu.visible and menu.main_page.visible, "pause should open the pause screen")
	var rows: Array[String] = []
	for b in menu.main_page.find_children("*", "Button", true, false):
		rows.append((b as Button).text)
	_check(rows == ["Resume", "Restart night", "Settings", "Photo mode", "Quit to title"], "pause rows are the five from the spec, got %s" % [rows])
	_check(menu.plate_night.text.begins_with("NIGHT "), "the plate shows the night")
	_check(menu.plate_time.text.ends_with("AM") or menu.plate_time.text.ends_with("PM"), "the plate shows the clock")
	_check(menu.plate_cash.visible and menu.plate_cash.text.begins_with("$"), "the plate shows cash")
	_check(not menu.notice_label.visible, "a plain pause has no amber line")
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Engine")), "the engine is cut while paused")
	_check(not AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Music")), "the radio keeps playing while paused")

	# ---------- amber line: stall guard and alt-tab ----------
	gs.resume()
	gs.stall_secs = GameState.STALL_SECS
	for i in 6:
		gs._process(1.0)   # the grace seconds, then one frame that fell behind
	await _frames(2)
	_check(gs.state == GameState.State.PAUSED, "a stalled frame should pause the game")
	_check(menu.notice_label.visible and menu.notice_label.text == GameState.REASON_STALL, "the stall line shows")
	_check(menu.notice_label.text.contains("lower Picture setting"), "the stall line points at the Picture settings")
	gs.stall_secs = 0.0
	gs.resume()
	_check(gs.pause_notice == "", "resume clears the pause reason")
	gs.pause_on_focus_loss = true
	gs._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _frames(2)
	_check(gs.state == GameState.State.PAUSED and menu.notice_label.visible and menu.notice_label.text == GameState.REASON_FOCUS,
		"alt-tab should pause with its amber line")
	gs.pause_on_focus_loss = false
	gs.resume()

	# ---------- chase lock ----------
	gs.pause_refused.connect(func() -> void: refused += 1)
	SaveStore.chase_active = true
	_tap(KEY_ESCAPE)
	await _frames(16)
	_check(gs.state == GameState.State.PLAYING, "Esc must not pause while a cop sees you")
	_check(refused >= 1, "the refusal should be announced")
	_check(menu.toast != null and menu.toast.text == GameState.CHASE_LOCK_TEXT, "the refusal toast has the spec text")
	gs.pause()   # an involuntary pause still opens the menu
	await _frames(2)
	menu.title_button.pressed.emit()
	_check(menu.confirm.is_open() and menu.confirm.question.text.contains("bust"), "quitting mid-chase warns about the bust")
	menu.confirm.no_button.pressed.emit()
	SaveStore.chase_active = false
	_check(not menu.confirm.is_open(), "No closes the box")

	# ---------- Restart asks; Esc on the box is No ----------
	menu.restart_button.pressed.emit()
	_check(menu.confirm.is_open() and menu.confirm.no_button.has_focus(), "Restart asks first, with No focused")
	_check(gs.state == GameState.State.PAUSED, "nothing happens before Yes")
	_tap(KEY_ESCAPE)
	await _frames(16)
	_check(not menu.confirm.is_open(), "Esc closes the box")
	_check(paused and gs.state == GameState.State.PAUSED and menu.visible, "Esc on the box must not resume the game")

	# ---------- in a race ----------
	gs.in_race = true
	gs.race_quit_requested.connect(func() -> void: race_quits += 1)
	gs.resume()
	gs.pause()
	await _frames(2)
	_check(menu.restart_button.text == "Quit race", "in a race the row says Quit race")
	menu.restart_button.pressed.emit()
	_check(menu.confirm.is_open(), "Quit race asks first")
	menu.confirm.yes_button.pressed.emit()
	await _frames(2)
	_check(race_quits == 1 and gs.state == GameState.State.PLAYING, "Yes quits the race and resumes")
	gs.in_race = false

	# ---------- photo mode from the pause screen ----------
	gs.pause()
	await _frames(2)
	menu.photo_button.pressed.emit()
	await _frames(2)
	_check(gs.state == GameState.State.PHOTO and not menu.visible, "Photo mode opens from the pause screen")
	gs.close_photo()
	await _frames(2)
	_check(gs.state == GameState.State.PAUSED and menu.visible and paused, "Esc in photo mode comes back to the pause screen")

	# ---------- Settings: Voices, Menu sounds, Tips ----------
	menu.show_settings("Game")
	var st: SettingsScreen = menu.settings
	_check(st.volume_sliders.has("Voices") and st.volume_sliders.has("Menus"), "Sound page has Voices and Menu sounds")
	_check(AudioServer.get_bus_index(&"Voices") >= 0, "the Voices bus exists")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"UI")), AudioSettings.volume_db_for("Menus")),
		"the UI bus follows the Menu sounds slider")
	st.volume_sliders["Menus"].value = 0.5
	_check(is_equal_approx(AudioSettings.volumes["Menus"], 0.5), "the Menu sounds slider sets its channel")
	st.tips_check.button_pressed = false
	_check(not GameSettings.tips, "the Tips switch turns tips off")
	GameSettings.load_settings()
	_check(not GameSettings.tips, "Tips off is saved")
	_check(st.find_child("Build", true, false) != null, "the Game tab shows the build number")
	_check(not st.car_option.disabled and not st.service_button.disabled, "the garage stand-ins are usable from the pause screen")
	st.close()

	# ---------- Quit to title ----------
	menu.title_button.pressed.emit()
	_check(menu.confirm.is_open(), "Quit to title asks first")
	menu.confirm.yes_button.pressed.emit()
	var second := await _wait_game(first)
	if second == null:
		return _finish("Quit to title did not reload")
	_check(second.game_state.state == GameState.State.TITLE, "Quit to title lands on the title")
	_finish("")

# ---------- helpers ----------
func _physics_process(_delta: float) -> bool:
	tick += 1
	for code in releases.keys():
		if tick >= releases[code]:
			_key(code, false)
			releases.erase(code)
	return false

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _wait_until(cond: Callable) -> bool:
	for i in TIMEOUT_FRAMES:
		if cond.call():
			return true
		await physics_frame
	return false

## The running Game once it has everything the test touches; `not_this` skips a
## scene that is being replaced.
func _wait_game(not_this: Node) -> Node:
	for i in TIMEOUT_FRAMES:
		var game := current_scene
		if game != null and is_instance_valid(game) and game != not_this and game.get("game_state") != null \
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

func _tap(code: Key) -> void:
	_key(code, true)
	releases[code] = tick + 6

func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _finish(abort: String) -> void:
	if abort != "":
		failures.append(abort)
	DirAccess.remove_absolute(AudioSettings.path)
	SaveStore.chase_active = false
	for f in failures:
		printerr("FAIL: ", f)
	print("title_and_pause: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
