extends SceneTree

# The key map in the real game (key map K1, step 8). Real key events, by
# position, go through the InputMap:
# - V switches the radio and does not move the car
# - F7 puts you back (the test build's rescue starts)
# - P opens photo mode, P again leaves
# - H: tap = low <-> high, one hold = high while down and exactly one flash,
#   double tap = lights off
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
				return _end("")
	if tick > TIMEOUT_TICKS * 3:
		return _end("timed out in phase %d" % phase)
	return false
