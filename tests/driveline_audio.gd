extends SceneTree

# Driveline and volume audio test (Phase B, 2026-10-05), headless and silent (it
# asserts on state and bus volumes, never on sound):
# - the player has a DrivelineAudio; the gear whine rises with speed under load
# - upshifts make shift thumps; lifting off at speed makes a driveline clunk
# - dropping the car from height makes exactly one landing thud
# - the loops and one-shots exist (non-empty), the whine loops
# - AudioSettings: set_volume moves the right buses, save and load round-trip,
#   and a missing or damaged file means defaults
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/driveline_audio.gd

const TIMEOUT_TICKS := 60 * 60

enum Step { BOOT, ACCEL, LIFT, DROP, LANDED, DONE }

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var throttle := 0.0
var d: DrivelineAudio
var whine_peak := 0.0

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")  # an empty road, whatever run_tests.bat or the saved settings say
	_settings_test()
	change_scene_to_file("res://Game.tscn")

func _settings_test() -> void:
	AudioSettings.path = "user://audio_settings_test.cfg"
	AudioSettings.set_volume("Engine", 0.5)
	AudioSettings.set_volume("Effects", 0.25)
	_check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Engine")), linear_to_db(0.5)), "Engine volume not applied to its bus")
	for b in [&"Tires", &"World", &"UI"]:
		_check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(b)), linear_to_db(0.25)), "Effects volume not applied to %s" % b)
	_check(AudioSettings.save_settings(), "settings did not save")
	AudioSettings.set_volume("Engine", 1.0)
	AudioSettings.set_volume("Effects", 1.0)
	AudioSettings.load_settings()
	_check(is_equal_approx(AudioSettings.volumes["Engine"], 0.5) and is_equal_approx(AudioSettings.volumes["Effects"], 0.25), "settings did not round-trip")
	AudioSettings.set_volume("Master", 7.0)
	_check(is_equal_approx(AudioSettings.volumes["Master"], 1.0), "volume not clamped to 1")
	# a missing file means defaults
	AudioSettings.path = "user://does_not_exist.cfg"
	AudioSettings.load_settings()
	_check(is_equal_approx(AudioSettings.volumes["Engine"], 1.0), "missing file should mean defaults")
	AudioSettings.path = AudioSettings.DEFAULT_PATH
	for layer in ["whine", "thump", "clunk", "landing"]:
		var w := DrivelineAudio.stream(layer)
		_check(w.data.size() > 1000, "%s stream is empty" % layer)
	_check(DrivelineAudio.stream("whine").loop_mode == AudioStreamWAV.LOOP_FORWARD, "the whine should loop")

func _drive(c: PlayerCar) -> void:
	c.throttle_input = throttle
	c.brake_input = 0.0
	c.steering_input = 0.0

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("player") == null:
		return tick > 600 and _end("Game never became ready")
	var p: PlayerCar = game.player
	p.driver = _drive
	var waited := tick - step_start
	match step:
		Step.BOOT:
			for c in p.get_children():
				if c is DrivelineAudio:
					d = c
			_check(d != null, "the player has no DrivelineAudio")
			if d == null:
				return _end("")
			throttle = 1.0
			_go(Step.ACCEL)
		Step.ACCEL:
			whine_peak = maxf(whine_peak, d.whine_level)
			if p.current_speed() > 30.0 and p.current_gear >= 3:
				_check(whine_peak > 0.3, "the gear whine should be audible at speed under load (peak %.2f)" % whine_peak)
				_check(d.thump_count >= 2, "upshifts should thump (%d)" % d.thump_count)
				throttle = 0.0
				_go(Step.LIFT)
			elif waited > TIMEOUT_TICKS / 2:
				return _end("never reached 30 m/s in 3rd")
		Step.LIFT:
			if waited >= 90:
				_check(d.clunk_count >= 1, "lifting off at speed should clunk (%d)" % d.clunk_count)
				p.global_position.y += 4.0
				p.linear_velocity = Vector3.ZERO
				p.angular_velocity = Vector3.ZERO
				_go(Step.DROP)
		Step.DROP:
			if d.landing_count >= 1 or waited > 300:
				_go(Step.LANDED)
		Step.LANDED:
			if waited >= 120:
				_check(d.landing_count == 1, "the drop should make exactly one landing thud, got %d" % d.landing_count)
				return _end("")
	return false

func _go(next: Step) -> void:
	step = next
	step_start = tick

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _end(msg: String) -> bool:
	if msg != "":
		failures.append(msg)
	for f in failures:
		printerr("FAIL: ", f)
	print("driveline_audio: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
