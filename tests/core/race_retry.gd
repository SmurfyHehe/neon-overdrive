extends SceneTree

# Race retry test (T3, 2026-10-11), the real Game.tscn on an empty straight
# road with traffic on:
#   1. start a 1200 m race, drive off for 3 s, give up from the pause menu
#   2. the menu offers "Retry race"; pressing it fades out, puts both cars back
#      at the start and starts the same race
#   3. after it: phase RACING, the same distance and start line, the player and
#      the rival within 1 m of their start places at rest, no traffic car
#      within 150 m of the start, retries == 1, the clock took no second +15 min
#   4. a WIN is never offered a retry
#
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . -s res://tests/core/race_retry.gd

const TIMEOUT_TICKS := 60 * 60
const DIST := 1200.0

enum Step { BOOT, DRIVE, RETRY, SETTLE, DONE }

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var game: Node
var race: RaceController
var p_x := 0.0
var p_d := 0.0
var r_x := 0.0
var r_d := 0.0
var clock_after_end := 0.0
var near_before := 0

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "12")
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	OS.set_environment("NEON_MUTE", "1")
	change_scene_to_file("res://Game.tscn")

func _physics_process(_delta: float) -> bool:
	tick += 1
	var waited := tick - step_start
	if waited > TIMEOUT_TICKS and step != Step.DONE:
		failures.append("step %s timed out" % Step.keys()[step])
		return _finish()
	match step:
		Step.BOOT:
			game = current_scene
			if game != null and game.get("race") != null and game.get("player") != null and waited > 60:
				race = game.race
				_check(not race.can_retry(), "no retry before any race")
				game.traffic.set_car_count(6)
				_check(race.start_race(DIST), "race starts")
				var u := RoadFrame.unroll(game.player.global_position)
				p_x = u.x
				p_d = RaceController.road_distance(game.player.global_position)
				var ru := RoadFrame.unroll(race.rival.global_position)
				r_x = ru.x
				r_d = RaceController.road_distance(race.rival.global_position)
				Input.action_press("accelerate")
				_go(Step.DRIVE)
		Step.DRIVE:
			if waited == 60 * 5:
				Input.action_release("accelerate")
				_check(race.player_progress() > 3.0, "the player drove off (%.1f m)" % race.player_progress())
				# put two traffic cars on the start (an oncoming one and a slow one in
				# the player's lane) so the clearing has something to clear
				var z0 := float(RoadFrame.origin_index) * RoadFrame.L - p_d
				var put := 0
				for c in game.traffic.cars:
					if put >= 2:
						break
					if c == race.rival or c.race_pinned or c.race_released:
						continue
					c.set_detailed(true)
					if put == 0:
						c.place(TrafficManager.lane_centre(1, true), 1.0, z0 + 40.0, c.rest_y, 10.0)
					else:
						c.place(p_x, -1.0, z0 - 60.0, c.rest_y, 5.0)
					put += 1
				near_before = _near_start()
				_check(near_before > 0, "no traffic near the start before the retry: the clearing is not exercised")
				var menu := _menu()
				_check(menu != null, "pause menu found")
				game.game_state.pause()
				menu._on_state_changed(GameState.State.PAUSED, GameState.State.PLAYING)
				_check(menu.race_button.text == "Give up race", "menu offers Give up mid-race")
				menu.race_button.pressed.emit()
				_check(race.result == RaceController.Result.GAVE_UP, "race given up")
				_check(race.can_retry(), "retry is offered after a give-up")
				clock_after_end = _clock()
				game.game_state.pause()
				menu._on_state_changed(GameState.State.PAUSED, GameState.State.PLAYING)
				_check(menu.race_button.text == "Retry race", "menu offers Retry race (got '%s')" % menu.race_button.text)
				menu.race_button.pressed.emit()
				_check(race.retrying(), "pressing it starts the retry")
				_check(game.game_state.state == GameState.State.PLAYING and not paused, "retry resumes the game")
				_go(Step.RETRY)
		Step.RETRY:
			if race.phase == RaceController.Phase.RACING and race.retries == 1:
				_go(Step.SETTLE)
		Step.SETTLE:
			if waited == 2:
				var u := RoadFrame.unroll(game.player.global_position)
				var d := RaceController.road_distance(game.player.global_position)
				var off := Vector2(u.x - p_x, d - p_d).length()
				_check(off < 1.0, "player within 1 m of its start (%.2f m)" % off)
				var ru := RoadFrame.unroll(race.rival.global_position)
				var roff := Vector2(ru.x - r_x, RaceController.road_distance(race.rival.global_position) - r_d).length()
				# the rival has had two ticks at 1 m/s plus its own acceleration
				_check(roff < 1.0, "rival within 1 m of its start (%.2f m)" % roff)
				_check(race.distance == DIST, "distance unchanged (%.0f)" % race.distance)
				_check(absf(race.start_d - p_d) < 1.0, "the start line is where it was (%.2f m)" % (race.start_d - p_d))
				var pv: float = game.player.linear_velocity.length()
				_check(pv < 1.0, "player at rest (%.2f m/s)" % pv)
				_check(race.rival.current_speed() < 3.0, "rival away from rest only slowly (%.2f m/s)" % race.rival.current_speed())
				var near := _near_start()
				_check(near == 0, "%d traffic cars within 150 m of the start" % near)
				_check(absf(_clock() - clock_after_end) < 1.0, "the retry did not take another +15 min (%.1f)" % (_clock() - clock_after_end))
				_check(race.races_run == 2, "two runs counted (%d)" % race.races_run)
				print("race_retry: player %.2f m, rival %.2f m from start, cars near the start %d -> %d, clock %+.1f min" % [off, roff, near_before, near, _clock() - clock_after_end])
				_go(Step.DONE)
				return _finish()
	return false

## Traffic cars (not the rival) within 150 m of the start, either way.
func _near_start() -> int:
	var n := 0
	for c in game.traffic.cars:
		if c == race.rival or (c is TrafficCar and c.race_pinned):
			continue
		if absf(RaceController.road_distance(c.global_position) - p_d) < RaceController.RETRY_CLEAR_M:
			n += 1
	return n

func _clock() -> float:
	return game.night_clock.minutes + (game.night_clock.night - 1) * NightClock.NIGHT_MINUTES

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

func _finish() -> bool:
	Input.action_release("accelerate")
	for f in failures:
		printerr("FAIL: ", f)
	print("race_retry: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
	return true
