extends SceneTree

# Roy's theme song on the title (M3): it plays on the Music bus and loops,
# muffled at rest; holding W (the turbo) opens the low-pass and letting go
# closes it again; it is on no radio station; and it stops when the drive
# starts. Exit code 1 on failure. Run:
#   godot --headless --audio-driver Dummy --path . -s res://tests/ui/title_theme.gd

const TIMEOUT_FRAMES := 900

var failures: Array[String] = []

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_TITLE", "1")
	OS.set_environment("NEON_SPLASH", "0")
	OS.set_environment("NEON_WELCOME", "0")
	GameState.title_seen = false
	TitleScreen.splash_done = true
	AudioSettings.path = "user://title_theme_test.cfg"
	change_scene_to_file("res://Game.tscn")
	_run.call_deferred()

func _run() -> void:
	var game := await _wait_game()
	if game == null:
		return _finish("Game.tscn never became ready")
	var title: TitleScreen = _node(game, "TitleScreen")
	var look: PauseLook = _node(game, "PauseLook")
	await _frames(10)
	_check(title.visible and title.panel.visible, "the menu is showing")
	_check(look != null, "PauseLook is in the game")
	_check(title._theme != null and title.theme_playing(), "the theme song is playing on the title")
	if title._theme == null or look == null:
		return _finish("")
	_check(PlayerGain.target(title._theme) == &"Music", "the song is on the Music bus (slider and mute apply)")
	var st := title._theme.stream as AudioStreamOggVorbis
	_check(st != null and st.loop, "the song loops")
	_check(st != null and st.resource_path.ends_with("title_theme_full_boost.ogg"), "it is Roy's Full Boost")

	# Not on the radio: the title's own radio is off, and no station folder holds it.
	_check(game.radio.station == -1, "the radio is off under the song, got station %d" % game.radio.station)
	for s in RadioStations.STATIONS:
		_check(not str(s.get("dir", "")).contains("title_theme") and not str(s.get("dir", "")).contains("assets/music"),
			"no radio station folder is the theme's (%s)" % s.get("dir", ""))

	# Muffled at rest.
	_check(look.muffled(), "the Music bus is muffled on the title")
	_check(is_equal_approx(look.muffle_hz(), TitleScreen.THEME_MUFFLE_HZ),
		"muffled at %.0f Hz at rest, got %.0f" % [TitleScreen.THEME_MUFFLE_HZ, look.muffle_hz()])

	# Held: the filter opens with the boost, to the full range.
	Input.action_press("accelerate")
	var peak := 0.0
	for i in TIMEOUT_FRAMES:
		await process_frame
		peak = maxf(peak, look.muffle_hz())
		if peak >= TitleScreen.THEME_OPEN_HZ - 1.0:
			break
	_check(peak > TitleScreen.THEME_MUFFLE_HZ * 4.0, "the cut-off rises with the boost (peak %.0f Hz)" % peak)
	_check(peak >= TitleScreen.THEME_OPEN_HZ - 1.0, "it opens fully at boost 1 (peak %.0f Hz)" % peak)

	# Released: it comes back to muffled.
	Input.action_release("accelerate")
	var low := false
	for i in TIMEOUT_FRAMES * 4:
		await process_frame
		if is_equal_approx(look.muffle_hz(), TitleScreen.THEME_MUFFLE_HZ):
			low = true
			break
	_check(low, "the cut-off falls back to %.0f Hz after the turbo is let go (now %.0f)" % [
		TitleScreen.THEME_MUFFLE_HZ, look.muffle_hz()])
	_check(title.theme_playing(), "the song keeps playing after the turbo")

	# Settings / Load keep it playing.
	title._show_list(title.load_list)
	await _frames(10)
	_check(title.theme_playing(), "the song keeps playing under the Load list")
	title._show_list(title.main_list)

	# The drive starts: ducked, then stopped.
	game.game_state.start_drive()
	await _frames(3)
	_check(PlayerGain.get_db(title._theme) < 0.0 or not title.theme_playing(), "the song ducks under the start of the drive")
	await create_timer(TitleScreen.THEME_DUCK_SECS + 0.5).timeout
	_check(not title.theme_playing(), "the song stops when the drive starts")
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
	print("title_theme: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
