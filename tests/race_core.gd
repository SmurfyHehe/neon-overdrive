extends SceneTree

# Race core test (RC1, races plan section 8). Pure checks first, then the real
# Game.tscn on an empty straight road with the scripted dummy rival:
#   1. WIN: full throttle over 1200 m, across a floating-origin recenter
#      (recenter_dist is 1000 m), beats the 108 km/h dummy. The Tuner is shut
#      mid-race; the clock gains 15 min; the rival is released to traffic.
#   2. LOSE: the player sits still and the rival crosses 300 m first.
#   3. GAVE_UP: the pause menu button gives the race up and resumes.
#
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . -s res://tests/race_core.gd

const TIMEOUT_TICKS := 60 * 90

enum Step { BOOT, WIN_RACE, WIN_CAPTION, LOSE_RACE, GIVE_UP, DONE }

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var game: Node
var race: RaceController
var clock_before := 0.0
var night_before := 1
var recenters_before := 0
var rival_ref: TrafficCar
var rival_m := 0.0  # rival progress on the last racing tick

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	OS.set_environment("NEON_MUTE", "1")
	_pure_checks()
	change_scene_to_file("res://Game.tscn")

func _pure_checks() -> void:
	_check(RaceController.decide(10.0, 20.0, 100.0) == RaceController.Result.NONE, "decide: nobody over the line")
	_check(RaceController.decide(100.0, 50.0, 100.0) == RaceController.Result.WIN, "decide: player over the line")
	_check(RaceController.decide(50.0, 100.0, 100.0) == RaceController.Result.LOSE, "decide: rival over the line")
	_check(RaceController.decide(100.0, 100.0, 100.0) == RaceController.Result.WIN, "decide: dead heat goes to the player")
	_check(RaceController.readout_text(820.4, 34.0, false) == "820 m to go    rival +34 m", "readout: rival ahead")
	_check(RaceController.readout_text(10.0, -5.2, false) == "10 m to go    you +5 m", "readout: player ahead")
	_check(RaceController.readout_text(-3.0, 0.0, true) == "0 m to go    rival out", "readout: rival out, never negative")
	var l0 := TrafficManager.lane_centre(0, false)
	var l1 := TrafficManager.lane_centre(1, false)
	_check(is_equal_approx(RaceController.rival_lane_x(l1, 4), l0), "rival lane: beside lane 1 is lane 0")
	_check(is_equal_approx(RaceController.rival_lane_x(l0, 4), l1), "rival lane: beside lane 0 is lane 1")

func _physics_process(_delta: float) -> bool:
	tick += 1
	var waited := tick - step_start
	if waited > TIMEOUT_TICKS and step != Step.DONE:
		return _abort("step %s timed out" % Step.keys()[step])
	match step:
		Step.BOOT:
			game = current_scene
			if game != null and game.get("race") != null and game.get("player") != null and waited > 30:
				race = game.race
				clock_before = game.night_clock.minutes
				night_before = game.night_clock.night
				recenters_before = game.recenter_count
				_check(race.start_race(1200.0), "start_race returns true")
				_check(race.is_racing(), "racing after start")
				_check(game.game_state.race_active, "GameState.race_active set")
				rival_ref = race.rival
				_check(rival_ref != null and rival_ref.race_pinned, "rival spawned and pinned")
				_check(game.traffic.cars.has(rival_ref), "rival is in the traffic index")
				game.game_state.toggle_tuning()
				_check(game.game_state.state == GameState.State.PLAYING, "Tuner refused mid-race")
				Input.action_press("accelerate")
				_go(Step.WIN_RACE)
		Step.WIN_RACE:
			if waited == 60 * 4 and rival_ref != null:
				_check(rival_ref.detailed, "rival still full sim")
			if race.phase == RaceController.Phase.RACING:
				rival_m = race.rival_progress()
			else:
				Input.action_release("accelerate")
				_check(race.result == RaceController.Result.WIN, "race 1 is a WIN (got %s)" % RaceController.Result.keys()[race.result])
				_check(game.recenter_count > recenters_before, "race 1 crossed a floating-origin recenter")
				_check(race.player_progress() >= 1200.0 - 1.0, "player really crossed 1200 m (%.0f)" % race.player_progress())
				var gained: float = game.night_clock.minutes - clock_before + (game.night_clock.night - night_before) * NightClock.NIGHT_MINUTES
				# 15 min jump plus the ordinary clock while driving (30 s per game minute... 2 s real per game min).
				_check(gained >= 15.0 and gained < 15.0 + race.race_time / 2.0 + 2.0, "clock gained 15 min plus driving (%.1f)" % gained)
				_check(not game.game_state.race_active, "race_active cleared")
				_check(is_instance_valid(rival_ref) and not rival_ref.race_pinned and rival_ref.race_released, "rival released to traffic")
				_check(is_equal_approx(race.stub_pay, RaceController.PAY_WIN_NIGHTS), "win paid into the stub")
				_check(rival_m > 400.0, "the dummy rival really raced (%.0f m)" % rival_m)
				print("race 1: WIN in %.1f s, rival at %.0f m of 1200" % [race.race_time, rival_m])
				_go(Step.WIN_CAPTION)
		Step.WIN_CAPTION:
			# Brake to a stop (released before it turns into reverse), then wait
			# for the caption to clear.
			var stopped: bool = game.player.linear_velocity.length() < 1.0
			if stopped:
				Input.action_release("brake")
			elif waited == 1:
				Input.action_press("brake")
			if race.phase == RaceController.Phase.IDLE and stopped:
				_check(race.start_race(300.0), "race 2 starts")
				_go(Step.LOSE_RACE)
		Step.LOSE_RACE:
			if race.phase != RaceController.Phase.RACING:
				_check(race.result == RaceController.Result.LOSE, "race 2 is a LOSE (got %s)" % RaceController.Result.keys()[race.result])
				_check(race.player_progress() < 300.0, "player did not cross")
				_check(is_equal_approx(race.stub_pay, RaceController.PAY_WIN_NIGHTS), "a loss pays nothing")
				print("race 2: LOSE in %.1f s" % race.race_time)
				_check(race.start_race(1500.0), "race 3 starts")
				_go(Step.GIVE_UP)
		Step.GIVE_UP:
			if waited == 30:
				var menu := _menu()
				_check(menu != null, "pause menu found")
				game.game_state.pause()
				menu._on_state_changed(GameState.State.PAUSED, GameState.State.PLAYING)
				_check(menu.race_button.text == "Give up race", "menu offers Give up mid-race")
				menu.race_button.pressed.emit()
				_check(race.result == RaceController.Result.GAVE_UP, "race 3 given up")
				_check(game.game_state.state == GameState.State.PLAYING and not paused, "give up resumes the game")
				_check(race.races_run == 3, "three races run")
				return _finish()
	return false

func _menu() -> PauseMenu:
	for c in game.get_children():
		if c is PauseMenu:
			return c
	return null

func _go(s: Step) -> void:
	step = s
	step_start = tick

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		printerr("FAIL: ", what)

func _abort(why: String) -> bool:
	failures.append(why)
	return _finish()

func _finish() -> bool:
	Input.action_release("accelerate")
	Input.action_release("brake")
	for f in failures:
		printerr("FAIL: ", f)
	print("race_core: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
	return true
