extends SceneTree

# "Mute" test, on the real Game.tscn. Key map K1 (b455e6f, Roy's decided keys)
# removed the mute key: M is the map and V is the radio on/off. This test used
# to check that M toggled the master bus mute; it now checks the keys that
# replaced it, so nothing quietly brings a master mute back:
# - there is no mute action; map is on M, radio_power on V (by position)
# - M never mutes the master bus: on a loop road it opens the pause straight on
#   the Map page and a second M closes it; on the endless road it does nothing
# - V turns the radio fully off (no station, screen dark, both music players
#   stopped) and the master bus is still not muted
# Keys are pressed by position (KeyBindings), held for 3 physics ticks so the
# game's physics-tick input poll sees them. Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/audio/mute.gd

const RoadMap := preload("res://scripts/world/road_map.gd")
const TIMEOUT_TICKS := 2400

var failures: Array[String] = []
var tick := 0
var phase := 0
var mark := 0
var bus := 0
var game: Node
var gs: GameState
var on_loop := false

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")  # an empty road, whatever run_tests.bat or the saved settings say
	OS.set_environment("NEON_POLICE", "0")   # no cop may refuse the map
	change_scene_to_file("res://Game.tscn")

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _go(next: int) -> void:
	phase = next
	mark = tick

func _since() -> int:
	return tick - mark

func _t(s: float) -> int:
	return int(ceil(s * Engine.physics_ticks_per_second))

func _muted() -> bool:
	return AudioServer.is_bus_mute(bus)

func _music_playing(radio: RadioManager) -> bool:
	return (radio._music != null and radio._music.playing) or (radio._music_b != null and radio._music_b.playing)

func _physics_process(_delta: float) -> bool:
	tick += 1
	game = current_scene
	if game == null or game.get("player") == null or game.get("game_state") == null or game.get("radio") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	gs = game.game_state
	var radio: RadioManager = game.radio
	bus = AudioServer.get_bus_index("Master")
	match phase:
		0:
			if tick < 60 or gs.state != GameState.State.PLAYING:
				return tick > TIMEOUT_TICKS and _end("never reached PLAYING")
			_check(not InputMap.has_action(&"mute"), "there should be no mute action (key map K1)")
			_check(KEY_M in KeyBindings.keys(&"map"), "map should be on M, has %s" % [KeyBindings.keys(&"map")])
			_check(KEY_V in KeyBindings.keys(&"radio_power"), "radio on/off should be on V, has %s" % [KeyBindings.keys(&"radio_power")])
			AudioServer.set_bus_mute(bus, false)
			on_loop = RoadMap.road_id != RoadMap.ENDLESS and RoadMap.is_loop()
			print("mute: road %d, %s" % [RoadMap.road_id, "a loop, M opens the map" if on_loop else "endless, M does nothing"])
			_key(KEY_M, true)
			_go(1)
		1:
			if _since() >= 3:
				_key(KEY_M, false)
				_go(2)
		2:
			# M: the map on a loop road, nothing on the endless one; never a mute
			_check(not _muted(), "M muted the master bus")
			if on_loop:
				if gs.state == GameState.State.PAUSED and gs.map_open:
					_key(KEY_M, true)
					_go(3)
				elif _since() > _t(2.0):
					return _end("M did not open the map (state %d, map_open %s)" % [gs.state, gs.map_open])
			elif _since() > _t(1.0):
				_check(gs.state == GameState.State.PLAYING, "M changed the state on the endless road (%d)" % gs.state)
				_go(5)
		3:
			if _since() >= 3:
				_key(KEY_M, false)
				_go(4)
		4:
			_check(not _muted(), "the second M muted the master bus")
			if gs.state == GameState.State.PLAYING:
				_go(5)
			elif _since() > _t(2.0):
				return _end("the second M did not close the map (state %d)" % gs.state)
		5:
			# the radio on with a song on air, so V has something to stop
			if not radio.player_on():
				radio.set_power(true)
			if radio.now_playing != "" and _music_playing(radio):
				_key(KEY_V, true)
				_go(6)
			elif _since() > _t(20.0):
				return _end("the radio never played a song (station %d)" % radio.station)
		6:
			if _since() >= 3:
				_key(KEY_V, false)
				_go(7)
		7:
			# the hand may need a moment to reach the head unit; the music fades out
			if not radio.player_on() and not _music_playing(radio):
				_check(radio.station == -1 and not radio.lit() and radio.now_playing == "", "V should turn the radio fully off (station %d, lit %s, '%s')" % [radio.station, radio.lit(), radio.now_playing])
				_check(not _muted(), "V muted the master bus instead of switching the radio off")
				return _end("")
			elif _since() > _t(5.0):
				return _end("V did not switch the radio off (on %s, music playing %s)" % [radio.player_on(), _music_playing(radio)])
	return false

func _key(code: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code as Key
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _end(msg: String) -> bool:
	if msg != "":
		failures.append(msg)
	for f in failures:
		printerr("FAIL: ", f)
	print("mute: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
