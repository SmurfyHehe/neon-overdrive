extends SceneTree

# The key map in the real game (key map K1, step 8). Real key events, by
# position, go through the InputMap:
# - V switches the radio and does not move the car
# - F7 puts you back (the test build's rescue starts)
# - P opens photo mode, P again leaves
# - H: tap = low <-> high, one hold = high while down and exactly one flash,
#   double tap = lights off
# - the numpad and the digit row are different keys (Roy 1464): KP_n triggers
#   only its own action, digit-row n never triggers a numpad action, and a
#   numpad key with Num Lock off (logical key = Home / arrows, same physical
#   key) still triggers only the numpad action
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/ui/key_map_drive.gd

const TIMEOUT_TICKS := 2400
const TestBuild := preload("res://scripts/core/test_build.gd")
const DRIVING := ["accelerate", "brake", "handbrake", "steer_left", "steer_right", "reverse", "starter", "shift_up", "shift_down", "clutch"]

var failures: Array[String] = []
var tick := 0
var phase := 0
var mark := 0
var game: Node
var player: PlayerCar
var gs: GameState
var radio_before := false
var flashes_before := 0

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _initialize() -> void:
	TestBuild.forced = 1   # F7 only exists in the test build
	change_scene_to_file("res://Game.tscn")

func _key(code: int, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code as Key
	e.pressed = down
	Input.parse_input_event(e)

func _secs(n: int) -> float:
	return float(n) / float(Engine.physics_ticks_per_second)

func _since() -> int:
	return tick - mark

## Ticks that make `s` seconds.
func _t(s: float) -> int:
	return int(ceil(s * Engine.physics_ticks_per_second))

func _go(next_phase: int) -> void:
	phase = next_phase
	mark = tick

func _end(msg: String) -> bool:
	if msg != "":
		failures.append(msg)
	print("key_map_drive: ", "FAIL" if not failures.is_empty() else "PASS")
	for f in failures:
		print("  - ", f)
	quit(1 if not failures.is_empty() else 0)
	return true

func _physics_process(_delta: float) -> bool:
	tick += 1
	game = current_scene
	if game == null or game.get("player") == null or game.get("game_state") == null or game.get("radio") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	player = game.player
	gs = game.game_state
	if player.beams == null:
		return false
	match phase:
		0:
			if tick < 60 or gs.state != GameState.State.PLAYING:
				return tick > TIMEOUT_TICKS and _end("never reached PLAYING")
			player.beams.auto_dip = false
			radio_before = game.radio.player_on()
			_key(KEY_V, true)
			_go(1)
		1:
			if _since() == 2:
				for a in DRIVING:
					_check(not Input.is_action_pressed(a), "V pressed the driving action %s" % a)
			if _since() >= 3:
				_key(KEY_V, false)
				_go(2)
		2:
			# the hand may need a moment to reach the head unit
			if game.radio.player_on() != radio_before or _since() > _t(4.0):
				_check(game.radio.player_on() != radio_before, "V did not switch the radio")
				_check(game.rescue.phase == OffMapRescue.Phase.WATCH, "V started the rescue")
				_key(KEY_F7, true)
				_go(3)
		3:
			if _since() >= 3:
				_key(KEY_F7, false)
				_go(4)
		4:
			if game.rescue.phase != OffMapRescue.Phase.WATCH or _since() > _t(2.0):
				_check(game.rescue.phase != OffMapRescue.Phase.WATCH, "F7 did not put the car back")
				_go(5)
		5:
			# wait the rescue out, then photo mode
			if game.rescue.phase == OffMapRescue.Phase.WATCH and gs.state == GameState.State.PLAYING and _since() > _t(1.0):
				_key(KEY_P, true)
				_go(6)
			elif _since() > _t(30.0):
				_check(false, "the rescue never finished")
				_go(7)
		6:
			if _since() >= 3:
				_key(KEY_P, false)
			if gs.state == GameState.State.PHOTO:
				_key(KEY_P, false)
				_go(61)
			elif _since() > _t(2.0):
				_check(false, "P did not open photo mode (state %d)" % gs.state)
				_go(7)
		61:
			if _since() >= 4:
				_key(KEY_P, true)
				_go(62)
		62:
			if _since() >= 3:
				_key(KEY_P, false)
			if gs.state == GameState.State.PLAYING:
				_key(KEY_P, false)   # may still be down if the state flipped inside 3 ticks
				_go(7)
			elif _since() > _t(2.0):
				_check(false, "P did not leave photo mode (state %d)" % gs.state)
				_go(7)
		7:
			# lights: start from the default, low beam on
			if _since() < _t(0.5):
				return false
			_check(player.beams.mode == HeadlightBeams.Mode.LOW, "lights should start on low (mode %d)" % player.beams.mode)
			_key(KEY_H, true)
			_go(8)
		8:
			if _since() >= 3:
				_key(KEY_H, false)
				_go(9)
		9:
			if _since() >= _t(0.5):
				_check(player.beams.mode == HeadlightBeams.Mode.HIGH, "H tap: not high (mode %d)" % player.beams.mode)
				_check(player.beams.flashes == 0, "H tap counted a flash")
				_key(KEY_H, true)
				_go(10)
		10:
			if _since() >= 3:
				_key(KEY_H, false)
				_go(11)
		11:
			if _since() >= _t(0.5):
				_check(player.beams.mode == HeadlightBeams.Mode.LOW, "second H tap: not low (mode %d)" % player.beams.mode)
				flashes_before = player.beams.flashes
				_key(KEY_H, true)
				_go(12)
		12:
			if _since() >= _t(0.4):
				_check(player.beams.mode == HeadlightBeams.Mode.HIGH, "H held: not high (mode %d)" % player.beams.mode)
				_check(player.beams.flashes == flashes_before + 1, "H held: %d flashes, wanted 1" % (player.beams.flashes - flashes_before))
				_key(KEY_H, false)
				_go(13)
		13:
			if _since() >= _t(0.5):
				_check(player.beams.mode == HeadlightBeams.Mode.LOW, "H released: not back on low (mode %d)" % player.beams.mode)
				_check(player.beams.flashes == flashes_before + 1, "one hold raised flashes by %d" % (player.beams.flashes - flashes_before))
				_key(KEY_H, true)
				_go(14)
		14:
			if _since() >= 2:
				_key(KEY_H, false)
				_go(15)
		15:
			if _since() >= _t(0.08):
				_key(KEY_H, true)
				_go(16)
		16:
			if _since() >= 2:
				_key(KEY_H, false)
				_go(17)
		17:
			if _since() >= _t(0.5):
				_check(player.beams.mode == HeadlightBeams.Mode.OFF, "double tap: lights not off (mode %d)" % player.beams.mode)
				_check(player.beams.flashes == flashes_before + 1, "a double tap counted a flash")
				_go(18)
		18:
			_numpad_vs_digits()
			return _end("")
	if tick > TIMEOUT_TICKS * 3:
		return _end("timed out in phase %d" % phase)
	return false

## What a numpad key reports with Num Lock OFF: the logical key is the
## navigation key printed under the digit, the physical key is unchanged.
const NUMLOCK_OFF := {
	KEY_KP_0: KEY_INSERT, KEY_KP_1: KEY_END, KEY_KP_2: KEY_DOWN, KEY_KP_3: KEY_PAGEDOWN,
	KEY_KP_4: KEY_LEFT, KEY_KP_5: KEY_CLEAR, KEY_KP_6: KEY_RIGHT, KEY_KP_7: KEY_HOME,
	KEY_KP_8: KEY_UP, KEY_KP_9: KEY_PAGEUP,
}

func _pressed_actions() -> Array:
	var out := []
	for a in KeyBindings.game_actions():
		if Input.is_action_pressed(a):
			out.append(String(a))
	out.sort()
	return out

## Presses one physical key with the given logical keycode and returns the
## game actions that fired, then releases it.
func _fire(physical: int, logical: int) -> Array:
	var e := InputEventKey.new()
	e.physical_keycode = physical as Key
	e.keycode = logical as Key
	e.pressed = true
	Input.parse_input_event(e)
	Input.flush_buffered_events()
	var got := _pressed_actions()
	e = e.duplicate()
	e.pressed = false
	Input.parse_input_event(e)
	Input.flush_buffered_events()
	return got

func _numpad_vs_digits() -> void:
	var kp := [KEY_KP_0, KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4, KEY_KP_5, KEY_KP_6, KEY_KP_7, KEY_KP_8, KEY_KP_9]
	var digit := [KEY_0, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]
	for n in 10:
		# what the game binds to this numpad key
		var want := []
		for a in KeyBindings.game_actions():
			if kp[n] in KeyBindings.keys(a):
				want.append(String(a))
		want.sort()
		var got := _fire(kp[n], kp[n])
		_check(got == want, "Numpad %d fired %s, wanted %s" % [n, got, want])
		got = _fire(kp[n], NUMLOCK_OFF[kp[n]])
		_check(got == want, "Numpad %d with Num Lock off fired %s, wanted %s" % [n, got, want])
		# the digit row never fires a numpad action
		var want_d := []
		for a in KeyBindings.game_actions():
			if digit[n] in KeyBindings.keys(a):
				want_d.append(String(a))
		want_d.sort()
		got = _fire(digit[n], digit[n])
		_check(got == want_d, "digit %d fired %s, wanted %s" % [n, got, want_d])
		for a in got:
			_check(not (kp[n] in KeyBindings.keys(StringName(a))) and not String(a).begins_with("hyd_"),
				"digit %d fired the lowrider action %s" % [n, a])
	# the lowrider's keys really are the numpad ones, and the names differ
	for a in SpecialKeys.KEYS:
		if String(a).begins_with("hyd_"):
			for c in KeyBindings.keys(a):
				_check(not (c in digit), "%s is on the digit row" % a)
	_check(KeyBindings.key_name(KEY_KP_7) == "Numpad 7" and KeyBindings.key_name(KEY_7) == "7",
		"names: '%s' vs '%s'" % [KeyBindings.key_name(KEY_KP_7), KeyBindings.key_name(KEY_7)])
