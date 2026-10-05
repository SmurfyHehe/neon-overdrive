extends SceneTree

# Mute test: M toggles the master bus mute in the real Game.tscn. The key is
# held for 2 physics ticks so the game's physics-tick input poll sees it.
# Exit code 1 on failure. Run (a window opens for a few seconds):
#   Godot_v4.7.2-stable_win64_console.exe --path . -s res://tests/mute.gd

const TIMEOUT_TICKS := 600

var tick := 0
var phase := 0
var phase_start := 0
var bus := 0

func _initialize() -> void:
	change_scene_to_file("res://Game.tscn")

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("player") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	bus = AudioServer.get_bus_index("Master")
	match phase:
		0:
			AudioServer.set_bus_mute(bus, false)
			_key(true)
			_next()
		1:
			if tick - phase_start >= 2:
				_key(false)
				_next()
		2:
			if AudioServer.is_bus_mute(bus):
				_key(true)
				_next()
			elif tick - phase_start > TIMEOUT_TICKS:
				return _end("M did not mute")
		3:
			if tick - phase_start >= 2:
				_key(false)
				_next()
		4:
			if not AudioServer.is_bus_mute(bus):
				return _end("")
			elif tick - phase_start > TIMEOUT_TICKS:
				return _end("second M did not unmute")
	return false

func _next() -> void:
	phase += 1
	phase_start = tick

func _key(pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_M
	ev.physical_keycode = KEY_M
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _end(msg: String) -> bool:
	if msg != "":
		printerr("FAIL: ", msg)
	print("mute: ", "PASS" if msg == "" else "FAIL")
	quit(0 if msg == "" else 1)
	return true
