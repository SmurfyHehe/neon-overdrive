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
	await _hold_six_seconds(title)
	await _whistle_and_shake(game, title)
	_finish("")

# Holding W: the whistle climbs while the wheel spools and then stays put for
# as long as W is held (a menu that "loses boost" while held is the bug), and
# the loop it plays has no dip at its seam to pulse once per cycle.
func _hold_six_seconds(title: TitleScreen) -> void:
	var loop: AudioStreamPlayer = title.get("_menu_whistle")
	if loop == null:
		return
	Input.action_press("accelerate")
	var t := 0.0
	var last_pitch := 0.0
	var last_db := -INF
	var dropped := ""
	var stopped := false
	var held_pitch := 0.0
	var held_db := 0.0
	while t < 6.0:
		await process_frame
		t += _dt()
		if t < 0.1:
			continue
		if not loop.playing:
			stopped = true
		if loop.pitch_scale < last_pitch - 0.0005:
			dropped = "pitch fell to %.3f from %.3f at %.2f s" % [loop.pitch_scale, last_pitch, t]
		if loop.volume_db < last_db - 0.01 and dropped == "":
			dropped = "level fell to %.2f dB from %.2f dB at %.2f s" % [loop.volume_db, last_db, t]
		last_pitch = loop.pitch_scale
		last_db = loop.volume_db
		if t > 2.0 and held_pitch == 0.0:
			held_pitch = loop.pitch_scale
			held_db = loop.volume_db
	_check(not stopped, "the whistle never stops or restarts while W is held 6 s")
	_check(dropped == "", "pitch and level never fall while W is held (%s)" % dropped)
	_check(is_equal_approx(loop.pitch_scale, held_pitch) and is_equal_approx(loop.volume_db, held_db),
			"whistle is steady from 2 s to 6 s (pitch %.3f, %.2f dB)" % [loop.pitch_scale, loop.volume_db])
	_check(loop.pitch_scale > 0.99, "whistle is at full pitch after 6 s (%.3f)" % loop.pitch_scale)
	Input.action_release("accelerate")
	for i in 240:
		await process_frame
		if title.menu_spin == 0.0:
			break
	_check_loop_level(TitleScreen.MENU_WHISTLE_LOOP)

# 20 ms RMS windows over the loop, wrapped once so the seam is inside a
# window: none may sit more than 2 dB under the median.
# Read from the source file: the imported stream is compressed.
func _check_loop_level(path: String) -> void:
	var wav := AudioStreamWAV.load_from_file(path)
	_check(wav != null and wav.format == AudioStreamWAV.FORMAT_16_BITS and wav.stereo,
			"the whistle loop is a 16-bit stereo WAV")
	if wav == null or wav.format != AudioStreamWAV.FORMAT_16_BITS or not wav.stereo:
		return
	var d := wav.data
	var frames := d.size() / 4
	var left := PackedFloat32Array()
	for i in frames:
		left.append(float(d.decode_s16(i * 4)) / 32768.0)
	var win := int(wav.mix_rate * 0.02)
	var wrapped := left + left.slice(0, win)
	var levels: Array[float] = []
	var pos := 0
	while pos + win <= wrapped.size():
		var e := 0.0
		for i in win:
			e += wrapped[pos + i] * wrapped[pos + i]
		levels.append(sqrt(e / win))
		pos += win / 2
	var sorted := levels.duplicate()
	sorted.sort()
	var median: float = sorted[sorted.size() / 2]
	var lowest: float = sorted[0]
	_check(median > 0.02, "the whistle loop is not silent (median %.3f)" % median)
	_check(lowest >= median * 0.794,
			"no dip in the loop, seam included (lowest %.3f vs median %.3f = %.1f dB)"
			% [lowest, median, 20.0 * log(lowest / median) / log(10.0)])

# The whistle and the logo shake that go with holding W.
func _whistle_and_shake(game: Node, title: TitleScreen) -> void:
	var mark := title.menu_mark
	_check(mark != null, "the menu mark is wired")
	var loop: AudioStreamPlayer = title.get("_menu_whistle")
	var flutter: AudioStreamPlayer = title.get("_menu_flutter")
	if mark == null or loop == null or flutter == null:
		return
	var rest := mark.position
	_check(not loop.playing and not flutter.playing, "quiet while W is not held")

	# Held 1.5 s: loop plays, pitch up, mark jitters.
	Input.action_press("accelerate")
	var moved := 0.0
	var t := 0.0
	while t < 1.5:
		await process_frame
		t += _dt()
		moved = maxf(moved, absf(mark.position.y - rest.y) + absf(mark.rotation))
	_check(loop.playing, "the whistle loop plays while W is held")
	_check(loop.pitch_scale > 0.95, "whistle pitch rises with the wheel (%.2f)" % loop.pitch_scale)
	_check(moved > 0.0, "the mark shakes while the wheel spins")
	_check(not flutter.playing, "no flutter while held")

	# Release at speed: flutter, then the mark returns exactly and the loop stops.
	Input.action_release("accelerate")
	await process_frame
	await process_frame
	_check(title.menu_spin > TitleScreen.MENU_FLUTTER_MIN, "fast at release (%.2f rad/s)" % title.menu_spin)
	_check(flutter.playing, "the flutter plays on release at speed")
	_check(not loop.playing, "the loop stops on release at speed")
	var shook := 0.0
	t = 0.0
	while t < 0.3:
		await process_frame
		t += _dt()
		shook = maxf(shook, absf(mark.position.y - rest.y))
	_check(shook > 0.0, "the mark shakes out after release")
	await _secs(1.0)
	_check(mark.position == rest and mark.rotation == 0.0, "the mark is back at rest after the shake")
	_check(not loop.playing, "the loop is still stopped")
	for i in 240:
		await process_frame
		if title.menu_spin == 0.0:
			break

	# A short tap: under 6 rad/s, no flutter.
	flutter.stop()
	Input.action_press("accelerate")
	await _secs(0.25)
	var tap_spin := title.menu_spin
	Input.action_release("accelerate")
	await process_frame
	await process_frame
	_check(tap_spin < TitleScreen.MENU_FLUTTER_MIN, "the tap stayed slow (%.2f rad/s)" % tap_spin)
	_check(not flutter.playing, "a short tap does not flutter")
	await _secs(0.4)
	_check(not loop.playing and mark.position == rest and mark.rotation == 0.0,
			"a short tap fades out and leaves the mark at rest")
	for i in 240:
		await process_frame
		if title.menu_spin == 0.0:
			break

	# Behind something else: no sound, no shake.
	title.load_list.visible = true
	Input.action_press("accelerate")
	await _secs(0.5)
	_check(not loop.playing, "no whistle with the Load list open")
	_check(mark.position == rest and mark.rotation == 0.0, "no shake with the Load list open")
	title.load_list.visible = false
	title.panel.visible = false   # Settings hides the panel
	await _secs(0.5)
	_check(not loop.playing, "no whistle behind Settings")
	_check(mark.position == rest and mark.rotation == 0.0, "no shake behind Settings")
	title.panel.visible = true
	await _secs(0.5)
	_check(loop.playing, "the whistle returns once the menu is back")

	# Leaving the title stops it at once.
	game.game_state.start_drive()
	await process_frame
	_check(not loop.playing, "leaving the title stops the loop at once")
	_check(mark.position == rest and mark.rotation == 0.0, "the mark is at rest after leaving")
	Input.action_release("accelerate")

func _dt() -> float:
	return root.get_process_delta_time()

func _secs(s: float) -> void:
	var t := 0.0
	while t < s:
		await process_frame
		t += _dt()

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
