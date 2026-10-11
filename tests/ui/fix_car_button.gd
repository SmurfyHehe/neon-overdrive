extends SceneTree

# Fix the car, on the real Game.tscn, headless:
# - the fix is on in every build (FixCar.FIX_CAR_ENABLED), and F6 is bound to fix_car
# - a hit leaves a warning; F6 while driving puts every part and lamp back
# - a hit again, then pause and press the "Fix the car" row: the warning clears
#   and the game is playing again
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --audio-driver Dummy --path . -s res://tests/ui/fix_car_button.gd

const FixCar := preload("res://scripts/car/fix_car.gd")
const TIMEOUT_TICKS := 600

enum Step { BOOT, HIT_KEY, HIT_ROW }

var step := Step.BOOT
var tick := 0
var step_start := 0
var failures: Array[String] = []

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	change_scene_to_file("res://Game.tscn")

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game: Variant = current_scene
	var waited := tick - step_start
	if waited > TIMEOUT_TICKS:
		return _end("timed out in step %d" % step)
	match step:
		Step.BOOT:
			if game == null or game.get("player") == null or waited < 30:
				return false
			_check(FixCar.FIX_CAR_ENABLED, "the fix is on in every build")
			_check(_f6_bound(), "fix_car is bound to F6")
			game.player.damage.apply_hit(Vector3(0, 0, 20))
			_check(game.player.damage.warning(), "a hit leaves a warning")
			Input.parse_input_event(_key(KEY_F6))
			_go(Step.HIT_KEY)
		Step.HIT_KEY:
			if waited < 3:
				return false
			_check(not game.player.damage.warning(), "F6 clears the warning")
			_check(_all_fixed(game.player), "F6 puts every part and lamp back")
			game.player.damage.apply_hit(Vector3(0, 0, 20))
			_check(game.player.damage.warning(), "a second hit leaves a warning")
			game.game_state.pause()
			_check(game.game_state.state == game.game_state.State.PAUSED, "the game pauses")
			_go(Step.HIT_ROW)
		Step.HIT_ROW:
			var row := _find_button(game, "Fix the car")
			if row == null or not row.visible:
				return _end("the Fix the car row is missing or hidden on the pause menu")
			row.pressed.emit()
			_check(game.game_state.state == game.game_state.State.PLAYING, "the row resumes the game")
			_check(not game.player.damage.warning(), "the row clears the warning")
			_check(_all_fixed(game.player), "the row puts every part and lamp back")
			return _end("")
	return false

func _go(next: Step) -> void:
	step = next
	step_start = tick

func _f6_bound() -> bool:
	for ev in InputMap.action_get_events("fix_car"):
		if ev is InputEventKey and ev.keycode == KEY_F6:
			return true
	return false

func _key(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	return ev

func _all_fixed(player: Variant) -> bool:
	for v in player.damage.parts:
		if v != 0.0:
			return false
	for lamp in player.damage.lamps:
		if lamp:
			return false
	return true

func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node
	for c in node.get_children():
		var hit := _find_button(c, text)
		if hit != null:
			return hit
	return null

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		print("  FAIL: " + what)

func _end(why: String) -> bool:
	if why != "":
		failures.append(why)
		print("  FAIL: " + why)
	print("fix_car_button: %s" % ("PASS" if failures.is_empty() else "%d failure(s)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
	return true
