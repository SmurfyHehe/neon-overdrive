extends SceneTree

# Title screen, "are you sure?" boxes and reset-to-defaults (menus A-list,
# 2026-10-08), on the real Game.tscn:
# - NEON_TITLE=1 boots into TITLE: title visible, HUD hidden, the world frozen
#   once the car has settled; Esc does nothing there
# - Drive -> PLAYING, tree running, HUD back
# - Restart asks first; Esc on the box means No and does NOT resume the game
# - Reset to defaults (after Yes) puts volume / traffic / FOV back
# - Restart -> Yes reloads straight into PLAYING (no title the second time)
# Exit code 1 on failure. Run (a window opens for a few seconds):
#   Godot_v4.7.2-stable_win64_console.exe --path . -s res://tests/title_and_confirm.gd

const HOLD_TICKS := 6
const TIMEOUT_TICKS := 600

enum Step { BOOT, FROZEN, ESC_ON_TITLE, DRIVE, PAUSE, ASK_RESTART, ESC_ON_BOX, RESET, RESTART }

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var first_game: Node
var releases := {}

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_TITLE", "1")
	GameState.title_seen = false
	AudioSettings.path = "user://title_confirm_test.cfg"
	DirAccess.remove_absolute(AudioSettings.path)
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
				_check(game.game_state.state == GameState.State.TITLE, "boot should land on the title screen")
				_check(_node(game, "TitleScreen").visible, "title screen should show")
				_check(not _node(game, "Hud").visible, "HUD should hide behind the title")
				_go(Step.FROZEN)
			elif waited > TIMEOUT_TICKS:
				return _abort("Game.tscn never became ready")
		Step.FROZEN:
			if paused:
				_tap(KEY_ESCAPE)
				_go(Step.ESC_ON_TITLE)
			elif waited > TIMEOUT_TICKS:
				return _abort("the title never froze the world")
		Step.ESC_ON_TITLE:
			if waited >= HOLD_TICKS + 10:
				_check(game.game_state.state == GameState.State.TITLE, "Esc must not leave the title")
				_node(game, "TitleScreen").drive_button.pressed.emit()
				_go(Step.DRIVE)
		Step.DRIVE:
			if not paused and game.game_state.state == GameState.State.PLAYING:
				_check(_node(game, "Hud").visible, "HUD should come back on Drive")
				_check(not _node(game, "TitleScreen").visible, "title should hide on Drive")
				game.game_state.pause()
				_go(Step.PAUSE)
			elif waited > TIMEOUT_TICKS:
				return _abort("Drive did not start the run")
		Step.PAUSE:
			var menu: PauseMenu = _node(game, "PauseMenu")
			menu.restart_button.pressed.emit()
			_check(menu.confirm.is_open(), "Restart should ask first")
			_check(game == first_game, "Restart must not reload before Yes")
			_check(menu.confirm.no_button.has_focus(), "No should have the focus")
			_tap(KEY_ESCAPE)
			_go(Step.ESC_ON_BOX)
		Step.ESC_ON_BOX:
			if waited >= HOLD_TICKS + 10:
				var menu: PauseMenu = _node(game, "PauseMenu")
				_check(not menu.confirm.is_open(), "Esc should close the box")
				_check(paused and game.game_state.state == GameState.State.PAUSED, "Esc on the box must not resume the game")
				_check(menu.visible, "the pause menu should still be open")
				AudioSettings.set_volume("Music", 0.3)
				TrafficSettings.set_car_count(40)
				ViewSettings.set_cockpit_fov(75.0)
				menu.reset_button.pressed.emit()
				_check(menu.confirm.is_open(), "Reset should ask first")
				menu.confirm.yes_button.pressed.emit()
				_go(Step.RESET)
		Step.RESET:
			var menu: PauseMenu = _node(game, "PauseMenu")
			_check(is_equal_approx(AudioSettings.volumes["Music"], 1.0), "reset should restore music volume")
			_check(TrafficSettings.car_count == TrafficSettings.CAR_COUNT_DEFAULT, "reset should restore the car count")
			_check(is_equal_approx(ViewSettings.cockpit_fov, ViewSettings.COCKPIT_FOV_DEFAULT), "reset should restore the FOV")
			_check(is_equal_approx(menu.volume_sliders["Music"].value, 1.0), "the slider should show the reset value")
			menu.restart_button.pressed.emit()
			menu.confirm.yes_button.pressed.emit()
			_go(Step.RESTART)
		Step.RESTART:
			if game != first_game and _is_ready(game):
				_check(not paused, "restart should leave the tree unpaused")
				_check(game.game_state.state == GameState.State.PLAYING, "restart should skip the title")
				return _finish()
			elif waited > TIMEOUT_TICKS:
				return _abort("Restart -> Yes did not reload")
	return false

func _go(next: Step) -> void:
	step = next
	step_start = tick

func _is_ready(game: Node) -> bool:
	return game != null and is_instance_valid(game) and game.get("game_state") != null \
		and _node(game, "PauseMenu") != null and _node(game, "TitleScreen") != null

func _node(game: Node, cls: String) -> Node:
	for c in game.get_children():
		var sc: Script = c.get_script()
		if sc != null and sc.get_global_name() == cls:
			return c
	return null

func _finish() -> bool:
	DirAccess.remove_absolute(AudioSettings.path)
	for f in failures:
		printerr("FAIL: ", f)
	print("title_and_confirm: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true

func _abort(msg: String) -> bool:
	failures.append("%s (stuck in step %s)" % [msg, Step.keys()[step]])
	return _finish()

func _tap(code: Key) -> void:
	_key(code, true)
	releases[code] = tick + HOLD_TICKS

func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
