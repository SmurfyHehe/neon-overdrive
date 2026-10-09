extends SceneTree

# Game-state test (issue #27): runs the real Game.tscn and checks that
# - Esc pauses: tree paused, menu visible, the car stops moving
# - Esc again resumes: tree unpaused, menu hidden, the car moves again
# - Restart reloads the scene: a fresh Game node, unpaused, in PLAYING
# Quit is not exercised (it would end the test run itself).
#
# Timing: every step is paced in PHYSICS ticks (fixed 60 Hz), never render
# frames, and every step waits for the condition it needs (with a timeout)
# instead of assuming it has happened by frame N. The original version used
# render-frame counts, which made it depend on the machine's frame rate:
# - Game polls input in _physics_process (#30), and Input.is_action_just_pressed
#   is only true on the physics tick the press landed in. A key pressed and
#   released within one render frame is gone before that tick can see it, so
#   Esc was missed some of the time. Keys are now held for HOLD_TICKS ticks.
# - "car moved >0.5 m in 80 frames" is a few ms of driving at a high frame
#   rate. Movement is now judged by distance travelled, not frames elapsed.
#
# Exit code 1 on failure. Run (a window opens for a few seconds):
#   Godot_v4.7.2-stable_win64_console.exe --path . -s res://tests/core/game_state.gd

const HOLD_TICKS := 6          # a tap lasts this many physics ticks
const TIMEOUT_TICKS := 600     # 10 s of game time per step before giving up
const PAUSED_WATCH_TICKS := 60 # how long the car must stay still while paused

enum Step { BOOT, DRIVE, PAUSE, WATCH_PAUSED, RESUME, MOVE_AGAIN, RESTART }

var step := Step.BOOT
var step_start := 0            # physics tick the current step began on
var tick := 0
var failures: Array[String] = []
var paused_pos := Vector3.ZERO
var first_game: Node
var releases := {}             # Key -> tick on which to release it

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")  # an empty road, whatever run_tests.bat or the saved settings say
	change_scene_to_file("res://Game.tscn")

func _physics_process(_delta: float) -> bool:
	tick += 1
	for code in releases.keys():
		if tick >= releases[code]:
			_key(code, false)
			releases.erase(code)
	var game := current_scene
	var waited := tick - step_start
	match step:
		Step.BOOT:
			if _is_ready(game):
				first_game = game
				_key(KEY_W, true)
				_go(Step.DRIVE)
			elif waited > TIMEOUT_TICKS:
				return _abort("Game.tscn never became ready")
		Step.DRIVE:
			if game.player.linear_velocity.length() > 3.0:
				_tap(KEY_ESCAPE)
				_go(Step.PAUSE)
			elif waited > TIMEOUT_TICKS:
				return _abort("car never started moving with W held")
		Step.PAUSE:
			if paused:
				_check(game.game_state.state == GameState.State.PAUSED, "state should be PAUSED")
				_check(_menu(game).visible, "pause menu should be visible")
				paused_pos = game.player.global_position
				_go(Step.WATCH_PAUSED)
			elif waited > TIMEOUT_TICKS:
				return _abort("Esc did not pause the tree")
		Step.WATCH_PAUSED:
			# Absence of change, so a fixed window is the only way to assert it.
			if waited >= PAUSED_WATCH_TICKS:
				_check(game.player.global_position.distance_to(paused_pos) < 0.001,
					"car moved while paused (%s -> %s)" % [paused_pos, game.player.global_position])
				_tap(KEY_ESCAPE)
				_go(Step.RESUME)
		Step.RESUME:
			if not paused:
				_check(game.game_state.state == GameState.State.PLAYING, "state should be PLAYING")
				_check(not _menu(game).visible, "pause menu should hide on resume")
				_go(Step.MOVE_AGAIN)
			elif waited > TIMEOUT_TICKS:
				return _abort("second Esc did not unpause")
		Step.MOVE_AGAIN:
			if game.player.global_position.distance_to(paused_pos) > 0.5:
				_key(KEY_W, false)
				game.game_state.pause()
				game.game_state.restart()
				_go(Step.RESTART)
			elif waited > TIMEOUT_TICKS:
				return _abort("car did not move again after resume")
		Step.RESTART:
			if game != first_game and _is_ready(game):
				_check(not paused, "restart should leave the tree unpaused")
				_check(game.game_state.state == GameState.State.PLAYING, "fresh run starts PLAYING")
				return _finish()
			elif waited > TIMEOUT_TICKS:
				return _abort("restart did not load a fresh Game")
	return false

func _go(next: Step) -> void:
	step = next
	step_start = tick

func _is_ready(game: Node) -> bool:
	return game != null and is_instance_valid(game) and game.get("player") != null \
		and game.get("game_state") != null and _menu(game) != null

func _finish() -> bool:
	for f in failures:
		printerr("FAIL: ", f)
	print("game_state: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true

func _abort(msg: String) -> bool:
	failures.append("%s (stuck in step %s)" % [msg, Step.keys()[step]])
	return _finish()

# Press now, release HOLD_TICKS physics ticks later, so at least one tick sees
# the key down and is_action_just_pressed fires.
func _tap(code: Key) -> void:
	_key(code, true)
	releases[code] = tick + HOLD_TICKS

func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _menu(game: Node) -> PauseMenu:
	for c in game.get_children():
		if c is PauseMenu:
			return c
	return null

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
