extends SceneTree

# Race core test (RC1, docs/planning/races-rivals-plan-2026-10-09.md),
# headless and silent:
# - the referee on its own, with two plain markers on a straight road and the
#   clock stepped by hand: win, lose, both over the line in one tick, give up,
#   busted, a stuck (or deleted) rival never ends the race so you must still
#   cross the line, no second start while racing, the night clock moves on 15
#   minutes, a win pays into the stub and a loss pays nothing, the line does
#   not move when the floating origin shifts, the readout text
# - the real game on an empty straight road against the scripted dummy rival:
#   you outrun a slow dummy and win (with a floating-origin shift mid-race, the
#   dummy is shifted with the world), the gap readout shows while racing and
#   the caption after; a fast dummy beats you while you hold the brake; "Give
#   up" shows in the pause menu only during a race and ends it as given up.
#
# Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/race_core.gd

const TIMEOUT_TICKS := 9000
const R := RaceSession.Result

enum Step { BOOT, SETTLE, WIN, STOP, LOSE, GIVE_UP, DONE }

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var game: Node
var race: RaceSession
var hud: RaceHud
var clock_before := 0.0
var shifts_before := 0
var last_rival_d := NAN
var max_rival_jump := 0.0
var saw_gap_label := false
var first_dummy: Node

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	OS.set_environment("NEON_CLOCK", "21:00")
	NightClock.path = "user://test_race_core_clock.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(NightClock.path))
	change_scene_to_file("res://Game.tscn")

# ---------- the referee alone ----------

func _marker(root: Node, z: float) -> Node3D:
	var n := Node3D.new()
	root.add_child(n)
	n.position = Vector3(0, 0, z)
	return n

func _move(n: Node3D, metres: float) -> void:
	n.position.z -= metres  # forward is -z

func _referee_tests() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var clock := NightClock.new()
	clock.minutes = 60.0

	# Win: you get there first; pays into the stub, +15 min, caption.
	var s := RaceSession.new()
	s.night_clock = clock
	var p := _marker(root, 0.0)
	var r := _marker(root, 0.0)
	_check(s.start(p, r, 100.0, 300, "Test"), "start a race")
	_check(s.is_racing(), "racing after start")
	_check(not s.start(p, r, 50.0), "no second start while racing")
	_move(p, 50.0)
	_move(r, 30.0)
	s.tick(0.1)
	_check(is_equal_approx(s.gap(), 20.0), "gap is +20 m (%.1f)" % s.gap())
	_check(is_equal_approx(s.to_go(), 50.0), "50 m to go (%.1f)" % s.to_go())
	_move(p, 51.0)
	s.tick(0.1)
	_check(s.result == R.WIN, "you crossed first: win (%d)" % s.result)
	_check(s.winnings == 300, "a win pays 300 into the stub (%d)" % s.winnings)
	_check(is_equal_approx(clock.minutes, 75.0), "a race takes 15 minutes off the night (%.2f)" % clock.minutes)
	_check(s.caption == "You won  +$300", "win caption ('%s')" % s.caption)
	_move(r, 200.0)
	s.tick(0.1)
	_check(s.result == R.WIN, "the result holds after the rival comes in")
	s.tick(RaceSession.CAPTION_SECONDS)
	_check(s.caption == "", "the caption goes after a few seconds")

	# Lose: the rival gets there first; no pay.
	p.position = Vector3.ZERO
	r.position = Vector3.ZERO
	_check(s.start(p, r, 100.0, 300), "start after the last race finished")
	_move(r, 101.0)
	_move(p, 90.0)
	s.tick(0.1)
	_check(s.result == R.LOSE, "rival crossed first: loss (%d)" % s.result)
	_check(s.winnings == 300, "a loss pays nothing (%d)" % s.winnings)
	_check(is_equal_approx(clock.minutes, 90.0), "a lost race takes 15 minutes too (%.2f)" % clock.minutes)

	# Both over in one tick: whoever is further past crossed first.
	p.position = Vector3.ZERO
	r.position = Vector3.ZERO
	s.start(p, r, 100.0, 100)
	_move(p, 103.0)
	_move(r, 101.0)
	s.tick(0.1)
	_check(s.result == R.WIN, "both over, you further past: win")
	p.position = Vector3.ZERO
	r.position = Vector3.ZERO
	s.start(p, r, 100.0, 100)
	_move(p, 101.0)
	_move(r, 104.0)
	s.tick(0.1)
	_check(s.result == R.LOSE, "both over, rival further past: loss")

	# A stuck rival never ends it: you must still cross the line (Roy 87).
	p.position = Vector3.ZERO
	r.position = Vector3.ZERO
	s.start(p, r, 100.0, 50)
	_move(r, 20.0)  # wrecked 20 m in, never moves again
	for i in 600:   # a minute of stepping
		s.tick(0.1)
	_check(s.is_racing() and s.result == R.NONE, "a stuck rival does not end the race")
	_move(p, 99.0)
	s.tick(0.1)
	_check(s.is_racing(), "1 m short is still racing")
	_move(p, 2.0)
	s.tick(0.1)
	_check(s.result == R.WIN, "cross the line past a stuck rival: win")

	# A rival that is gone (freed) cannot win either.
	p.position = Vector3.ZERO
	var r2 := _marker(root, 0.0)
	s.start(p, r2, 100.0, 0)
	r2.free()
	s.tick(0.1)
	_check(s.is_racing() and s.gap() == 0.0, "a deleted rival: still racing, gap reads 0")
	_move(p, 101.0)
	s.tick(0.1)
	_check(s.result == R.WIN and s.caption == "You won", "win with no pay: plain caption ('%s')" % s.caption)

	# Give up and busted: losses, no pay; outside a race they do nothing.
	var won := s.winnings
	p.position = Vector3.ZERO
	r.position = Vector3.ZERO
	s.start(p, r, 100.0, 500)
	s.give_up()
	_check(s.result == R.GIVE_UP and s.winnings == won and s.caption == "You gave up", "give up: a loss, no pay")
	s.give_up()
	s.busted()
	_check(s.result == R.GIVE_UP, "give up / busted outside a race change nothing")
	s.start(p, r, 100.0, 500)
	s.busted()
	_check(s.result == R.BUSTED and s.winnings == won, "busted: a loss, no pay")

	# Floating origin: shifting everything back by whole chunks keeps the line.
	p.position = Vector3.ZERO
	r.position = Vector3.ZERO
	s.start(p, r, 300.0, 0)
	_move(p, 120.0)
	var before := s.progress(p)
	RoadFrame.origin_index += 2
	p.position.z += 2.0 * RoadFrame.L
	r.position.z += 2.0 * RoadFrame.L
	_check(is_equal_approx(s.progress(p), before), "progress survives an origin shift (%.2f vs %.2f)" % [s.progress(p), before])
	RoadFrame.origin_index -= 2
	s.give_up()

	# Readout text.
	_check(RaceHud.gap_text(42.4) == "+42 m" and RaceHud.gap_text(-17.2) == "-17 m" and RaceHud.gap_text(0.2) == "+0 m", "gap text")
	_check(RaceHud.to_go_text(1250.0) == "1.25 km to go" and RaceHud.to_go_text(349.2) == "350 m to go", "to-go text")

	s.free()
	clock.free()
	root.free()

# ---------- the real game ----------

func _physics_process(_delta: float) -> bool:
	tick += 1
	if tick == 1:
		_referee_tests()  # needs the tree running (global positions)
	if tick > TIMEOUT_TICKS:
		return _end("timed out in step %s" % Step.keys()[step])
	game = current_scene
	if game == null or game.get("race") == null or game.get("player") == null:
		return false
	race = game.race
	var t := tick - step_start
	match step:
		Step.BOOT:
			_check(not race.is_racing(), "no race without NEON_RACE")
			hud = _find_hud()
			_check(hud != null, "the race readout is in the game")
			_check(hud == null or not hud.lbl_gap.visible, "no gap readout outside a race")
			_go(Step.SETTLE)
		Step.SETTLE:
			if t >= 120:
				game.recenter_dist = 150.0  # force an origin shift mid-race
				shifts_before = game.recenter_count
				clock_before = game.night_clock.minutes
				_check(race.start_dummy(game, game.player, 400.0, 8.0, 300), "start a dummy race in the game")
				first_dummy = race.rival
				Input.action_press("accelerate")
				_go(Step.WIN)
		Step.WIN:
			_watch_rival()
			if race.is_racing() and hud.lbl_gap.visible and hud.lbl_gap.text == RaceHud.gap_text(race.gap()):
				saw_gap_label = true
			if not race.is_racing():
				Input.action_release("accelerate")
				_check(race.result == R.WIN, "outrun an 8 m/s dummy: win (%s)" % R.keys()[race.result])
				_check(race.winnings == 300, "the win paid 300 (%d)" % race.winnings)
				_check(saw_gap_label, "the gap readout showed during the race")
				_check(hud.lbl_caption.visible and hud.lbl_caption.text == "You won  +$300", "the caption shows ('%s')" % hud.lbl_caption.text)
				_check(not hud.lbl_gap.visible, "the gap readout goes at the finish")
				var dm: float = game.night_clock.minutes - clock_before
				var driving := race.elapsed * 60.0 / NightClock.REAL_SECONDS_PER_HOUR
				_check(dm >= 15.0 and dm <= 15.0 + driving + 0.5, "clock moved 15 min plus driving (%.2f, driving %.2f)" % [dm, driving])
				_check(game.recenter_count > shifts_before, "an origin shift happened mid-race (%d)" % (game.recenter_count - shifts_before))
				_check(max_rival_jump < 1.0, "the dummy moved with the world (largest step %.2f m)" % max_rival_jump)
				_check(race.progress(race.rival) > 50.0, "the dummy really drove (%.0f m)" % race.progress(race.rival))
				print("race_core: win in %.1f s, rival %.0f m behind" % [race.elapsed, race.gap()])
				Input.action_press("brake")
				_go(Step.STOP)
			elif t > 60 * 120:
				_check(false, "the win race never finished (%.0f m to go)" % race.to_go())
				_go(Step.DONE)
		Step.STOP:
			if t >= 240:
				_check(race.start_dummy(game, game.player, 150.0, 30.0, 300), "start a race against a fast dummy")
				_check(not is_instance_valid(first_dummy) or first_dummy.is_queued_for_deletion(), "the old dummy is cleared away")
				_go(Step.LOSE)
		Step.LOSE:
			if not race.is_racing():
				Input.action_release("brake")
				_check(race.result == R.LOSE, "a 30 m/s dummy beats you on the brake: loss (%s)" % R.keys()[race.result])
				_check(race.winnings == 300, "a loss pays nothing (%d)" % race.winnings)
				_check(race.start_dummy(game, game.player, 2000.0, 10.0, 300), "start a race to give up")
				game.game_state.pause()
				var menu := _find_menu()
				_check(menu != null and menu.visible and menu.give_up_button.visible, "Give up shows in the pause menu during a race")
				if menu != null:
					menu.give_up_button.pressed.emit()
				_check(race.result == R.GIVE_UP, "Give up ends it as given up (%s)" % R.keys()[race.result])
				_check(game.game_state.state == GameState.State.PLAYING, "Give up goes back to the road")
				game.game_state.pause()
				_check(menu != null and not menu.give_up_button.visible, "no Give up outside a race")
				game.game_state.resume()
				_go(Step.DONE)
			elif t > 30 * 120:
				_check(false, "the lose race never finished")
				_go(Step.DONE)
		Step.DONE:
			return _end("")
	return false

func _watch_rival() -> void:
	if race.rival == null or not is_instance_valid(race.rival):
		return
	var d := RaceSession.road_distance(race.rival.global_position)
	if not is_nan(last_rival_d):
		max_rival_jump = maxf(max_rival_jump, absf(d - last_rival_d))
	last_rival_d = d

func _find_hud() -> RaceHud:
	for n in game.get_children():
		if n is RaceHud:
			return n
	return null

func _find_menu() -> PauseMenu:
	for n in game.get_children():
		if n is PauseMenu:
			return n
	return null

func _go(next: Step) -> void:
	step = next
	step_start = tick

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

var _ended := false
func _end(msg: String) -> bool:
	if _ended:
		return true
	_ended = true
	if msg != "":
		failures.append(msg)
	for f in failures:
		printerr("FAIL: ", f)
	print("race_core: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
