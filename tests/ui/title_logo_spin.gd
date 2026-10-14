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
	var steady_ok := true
	var boost_at_2 := 0.0
	var boost_at_3 := 0.0
	var spin_at_3_5 := 0.0
	var dipped := false
	var limiter_pitch_hi := 0.0
	while t < 6.0:
		await process_frame
		t += _dt()
		if t < 0.1:
			continue
		if not loop.playing:
			stopped = true
		# Up to the limiter (boost 0.85 = 5.1 s) the whistle only rises.
		if t < 5.0:
			if loop.pitch_scale < last_pitch - 0.0005:
				dropped = "pitch fell to %.3f from %.3f at %.2f s" % [loop.pitch_scale, last_pitch, t]
			if PlayerGain.get_db(loop) < last_db - 0.01 and dropped == "":
				dropped = "level fell to %.2f dB from %.2f dB at %.2f s" % [PlayerGain.get_db(loop), last_db, t]
		else:
			limiter_pitch_hi = maxf(limiter_pitch_hi, loop.pitch_scale)
		if t > 5.4 and loop.pitch_scale < limiter_pitch_hi - 0.03:
			dipped = true
		last_pitch = loop.pitch_scale
		last_db = PlayerGain.get_db(loop)
		# The wheel is at 18 rad/s and boost is under half: steady 2.0 - 2.9 s.
		if t > 2.0 and t < 2.9:
			if held_pitch == 0.0:
				held_pitch = loop.pitch_scale
				held_db = PlayerGain.get_db(loop)
			elif not (is_equal_approx(loop.pitch_scale, held_pitch) and is_equal_approx(PlayerGain.get_db(loop), held_db)):
				steady_ok = false
		if boost_at_2 == 0.0 and t >= 2.0:
			boost_at_2 = title.menu_boost
		if boost_at_3 == 0.0 and t >= 3.0:
			boost_at_3 = title.menu_boost
		if spin_at_3_5 == 0.0 and t >= 3.5:
			spin_at_3_5 = title.menu_spin
	_check(not stopped, "the whistle never stops or restarts while W is held 6 s")
	_check(dropped == "", "pitch and level never fall before the limiter (%s)" % dropped)
	_check(steady_ok, "whistle is steady from 2.0 s to 2.9 s (pitch %.3f, %.2f dB)" % [held_pitch, held_db])
	_check(held_pitch > 0.99, "whistle is at full pitch once the wheel is up (%.3f)" % held_pitch)
	_check(loop.pitch_scale > 1.1, "pitch keeps rising past half boost (%.3f at 6 s)" % loop.pitch_scale)
	_check(dipped, "above the limiter the whistle dips in pitch (bounces)")
	_check(absf(boost_at_2 - 1.0 / 3.0) < 0.03, "boost is about 1/3 at 2 s (%.3f)" % boost_at_2)
	_check(absf(boost_at_3 - 0.5) < 0.03, "boost is about half at 3 s (%.3f)" % boost_at_3)
	_check(title.menu_boost > 0.97, "boost is full after 6 s (%.3f)" % title.menu_boost)
	_check(spin_at_3_5 > TitleScreen.MENU_SPIN_MAX, "spin passes 18 rad/s after 3 s (%.2f at 3.5 s)" % spin_at_3_5)
	_check(title.menu_spin > TitleScreen.MENU_SPIN_MAX + 4.0, "spin creeps well past 18 by 6 s (%.2f)" % title.menu_spin)
	var grind: AudioStreamPlayer = title.get("_menu_grind")
	_check(grind != null and grind.playing, "the grind layer is playing at full boost")
	var sparks: CPUParticles2D = title.get("_sparks")
	_check(sparks != null and sparks.emitting, "sparks are emitting at full boost")
	_check(sparks != null and sparks.amount <= 64, "no more than 64 sparks")
	var ring: Control = title.get("_ring")
	_check(ring != null and ring.modulate.g > 0.3 and ring.modulate.b > 0.5,
			"the hot ring is near white at full boost (%s)" % [ring.modulate if ring != null else "-"])
	# the turbo's wind: near 2.0 at full boost, then eases down after release
	var k: TitleKerbside = title.kerbside
	_check(k != null and k.wind_now() > 1.9, "title wind is near 2.0 at full boost (%.2f)" % (k.wind_now() if k != null else -1.0))
	Input.action_release("accelerate")
	await process_frame
	_check(k != null and k.wind_now() > 1.5 and k.wind_now() <= 2.0,
			"wind eases down after release, not a snap (%.2f)" % (k.wind_now() if k != null else -1.0))
	for i in 240:
		await process_frame
		if title.menu_spin == 0.0:
			break
	for i in 600:
		if k == null or is_equal_approx(k.wind_now(), TitleKerbside.WIND_REST):
			break
		await process_frame
	_check(k != null and is_equal_approx(k.wind_now(), TitleKerbside.WIND_REST),
			"wind is back at the default breeze once boost is gone (%.2f)" % (k.wind_now() if k != null else -1.0))
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

	# Held 1.5 s: loop plays, pitch up, mark jitters, boost still under half.
	Input.action_press("accelerate")
	var moved := 0.0
	var t := 0.0
	var sparks_early := false
	var blowoff: AudioStreamPlayer = title.get("_menu_blowoff")
	var sparks: CPUParticles2D = title.get("_sparks")
	while t < 1.5:
		await process_frame
		t += _dt()
		moved = maxf(moved, absf(mark.position.y - rest.y) + absf(mark.rotation))
		sparks_early = sparks_early or sparks.emitting
	_check(loop.playing, "the whistle loop plays while W is held")
	_check(loop.pitch_scale > 0.95, "whistle pitch rises with the wheel (%.2f)" % loop.pitch_scale)
	_check(moved > 0.0, "the mark shakes while the wheel spins")
	_check(not flutter.playing, "no flutter while held")
	_check(not sparks_early and title.menu_boost < 0.5, "no sparks under half boost (boost %.2f)" % title.menu_boost)

	# Release under 0.4 (1.5 s in = 0.25): the fade only, no blow-off, no flutter.
	Input.action_release("accelerate")
	await process_frame
	await process_frame
	_check(title.menu_spin > TitleScreen.MENU_FLUTTER_MIN, "fast at release (%.2f rad/s)" % title.menu_spin)
	_check(not blowoff.playing and not flutter.playing, "under 0.4 boost: no blow-off and no flutter")
	await _secs(1.0)
	_check(not blowoff.playing and not flutter.playing and mark.position == rest and mark.rotation == 0.0,
			"under 0.4 boost: still quiet and the mark is at rest")
	for i in 240:
		await process_frame
		if title.menu_spin == 0.0 and title.menu_boost == 0.0:
			break

	# Held 3.4 s (boost about 0.57): sparks fly. Release: blow-off, puff, then flutter.
	Input.action_press("accelerate")
	t = 0.0
	var sparked := false
	while t < 3.4:
		await process_frame
		t += _dt()
		sparked = sparked or sparks.emitting
	_check(sparked and sparks.emitting, "sparks emit above half boost (boost %.2f)" % title.menu_boost)
	Input.action_release("accelerate")
	await process_frame
	await process_frame
	_check(blowoff.playing, "the blow-off plays on release above 0.4 boost")
	_check(not loop.playing, "the loop stops on release at boost")
	_check(not sparks.emitting, "no sparks once W is let go")
	var puff: CPUParticles2D = title.get("_puff")
	_check(puff != null and puff.emitting and puff.amount == 24, "the vapour puff bursts (24 particles)")
	_check(not flutter.playing, "the flutter follows the blow-off, not with it")
	var shook := 0.0
	t = 0.0
	var flutter_seen := false
	while t < 0.9:
		await process_frame
		t += _dt()
		flutter_seen = flutter_seen or flutter.playing
		shook = maxf(shook, absf(mark.position.y - rest.y))
	_check(flutter_seen, "the flutter plays after the blow-off")
	_check(shook > 0.0, "the mark shakes out after release")
	await _secs(1.0)
	_check(mark.position == rest and mark.rotation == 0.0, "the mark is back at rest after the shake")
	_check(not loop.playing, "the loop is still stopped")
	for i in 240:
		await process_frame
		if title.menu_spin == 0.0 and title.menu_boost == 0.0:
			break

	# No new sparks inside the 1 s cooldown after a blow-off: boost is back
	# above half only by holding W again, and the sparks wait for the cooldown.
	title.set("menu_boost", 0.6)
	title.set("_spark_cooldown", 0.5)
	Input.action_press("accelerate")
	await process_frame
	await process_frame
	_check(title.menu_boost > 0.5 and not sparks.emitting, "no sparks while the blow-off cooldown runs")
	title.set("_spark_cooldown", 0.0)
	await process_frame
	await process_frame
	_check(sparks.emitting, "sparks come back when the cooldown is over")
	Input.action_release("accelerate")
	await process_frame
	await process_frame
	# The real blow-off sets the cooldown to a full second.
	_check(title.get("_spark_cooldown") > 0.8, "a blow-off starts a 1 s spark cooldown (%.2f)" % title.get("_spark_cooldown"))
	await _secs(1.5)
	for i in 240:
		await process_frame
		if title.menu_spin == 0.0 and title.menu_boost == 0.0:
			break
	flutter.stop()

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
	_check(title.menu_boost == 0.0 and not sparks.emitting, "no boost or sparks with the Load list open")
	title.load_list.visible = false
	title.panel.visible = false   # Settings hides the panel
	await _secs(0.5)
	_check(not loop.playing, "no whistle behind Settings")
	_check(mark.position == rest and mark.rotation == 0.0, "no shake behind Settings")
	_check(title.menu_boost == 0.0 and not sparks.emitting and not title.get("_menu_grind").playing,
			"no boost, sparks or grind behind Settings")
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
