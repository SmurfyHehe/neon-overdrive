extends SceneTree

# Radio volume knob in play (Roy 2026-10-08), in the real Game.tscn with the
# real renderer:
# - holding . (radio_volume_up) sends the driver's right hand to the knob; the
#   volume does not move on the key, only once the hand is on the knob
# - while the key is held the volume rises, the knob turns with it (its angle
#   is HeadUnit.knob_angle(volume)) and the hand rolls with the knob
# - the screen shows the VOLUME bar while the volume changes
# - letting go: the volume stops, the hand returns to the wheel, and the
#   volume is saved (it is the pause menu's Music slider)
# - holding , (radio_volume_down) turns it back down, clamped at 0
# - the Music slider moving the volume turns the knob too
# - a touch-only screen takes the volume on its bar, at the current level
# - optional: RADIO_VOLUME_SHOT=<dir> saves cockpit screenshots there
# Exit code 1 on failure. Run (a window opens):
#   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1280x720 -s res://tests/radio_volume_knob.gd

const TIMEOUT_SECS := 40.0
const STEP_TIMEOUT_SECS := 6.0
const SETTINGS := "user://test_radio_volume_knob.cfg"

enum Step { BOOT, SETTLE, UP, RELEASE, DOWN, SLIDER, DONE }

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var game: Node
var p: PlayerCar
var frame: CockpitFrame
var d: DriverModel
var held := KEY_NONE
var key_tick := -1
## Render frames at the key press / slider set. The hand's pose and the knob move
## in _process by the render frame's delta, and a loaded machine renders far
## fewer frames than it ticks physics, so "N ticks later" is not "N frames later".
var key_frame := -1
var act_checked := false
var contact_tick := -1
var vol_at_key := 0.0
var vol_at_release := 0.0
var shot_dir := ""

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	ExhaustTune.save_path = "user://autotune/test_radio_volume_exhaust.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	shot_dir = OS.get_environment("RADIO_VOLUME_SHOT")
	change_scene_to_file("res://Game.tscn")

func _drive(c: PlayerCar) -> void:
	c.throttle_input = 0.3
	c.brake_input = 0.0
	c.handbrake_input = 0.0
	c.steering_input = 0.0

func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
	held = code if pressed else KEY_NONE

func _on_contact(target: StringName) -> void:
	if target == DriverModel.CONTACT_RADIO_VOLUME and contact_tick < 0:
		contact_tick = tick

func _vol() -> float:
	return AudioSettings.volumes["Music"]

func _knob_ok(msg: String) -> void:
	var want := HeadUnit.knob_angle(_vol())
	var got := frame.head_unit.knob.rotation.z
	_check(absf(got - want) < 0.02, "%s: knob at %.1f deg, volume %.2f wants %.1f deg" % [msg, rad_to_deg(got), _vol(), rad_to_deg(want)])

func _physics_process(_delta: float) -> bool:
	tick += 1
	if tick > _s(TIMEOUT_SECS):
		return _end("timed out in step %s" % Step.keys()[step])
	game = current_scene
	if game == null or game.get("player") == null or game.get("camera") == null or game.get("radio") == null:
		return false
	p = game.player
	p.driver = _drive
	var cam: ChaseCamera = game.camera
	frame = cam.frame
	if frame == null:
		return _end("no cockpit frame (NEON_COCKPIT=0?)")
	d = frame.driver
	var waited := tick - step_start
	if OS.get_environment("RVK_TRACE") == "1" and tick % _s(0.25) == 0:
		print("t%d %s act=%s dir=%d vol=%.3f axis=%.1f vis=%s fps=%d" % [tick, Step.keys()[step], DriverModel.Act.keys()[d.act], d.volume_dir, _vol(), Input.get_axis("radio_volume_down", "radio_volume_up"), frame.visible, Engine.get_frames_per_second()])
	if waited > _s(STEP_TIMEOUT_SECS):
		return _end("step %s took too long" % Step.keys()[step])
	match step:
		Step.BOOT:
			AudioSettings.path = SETTINGS
			AudioSettings.set_volume("Music", 0.5)
			_check(frame.head_unit.knob != null, "the P1 head unit has a volume knob")
			if frame.head_unit.knob == null:
				return _end("")
			d.hand_contact.connect(_on_contact)
			cam.set_view(ChaseCamera.View.COCKPIT)
			_touch_only_unit()
			_go(Step.SETTLE)
		Step.SETTLE:
			if waited == _s(1.0):
				_knob_ok("at rest")
				_check(not frame.head_unit.is_volume_shown(), "no VOLUME bar at rest")
				_shot("radio_volume_rest.png")
				vol_at_key = _vol()
				key_tick = tick
				key_frame = Engine.get_process_frames()
				act_checked = false
				_key(KEY_PERIOD, true)
				_go(Step.UP)
		Step.UP:
			if contact_tick < 0:
				_check(is_equal_approx(_vol(), vol_at_key), "the volume moved before the hand reached the knob (%.3f)" % _vol())
				if not act_checked and Engine.get_process_frames() >= key_frame + 3:
					act_checked = true
					_check(d.act == DriverModel.Act.VOLUME_REACH, ". sends the right hand to the knob (act %s)" % DriverModel.Act.keys()[d.act])
				return false
			if tick == contact_tick + 1:
				print("key to knob: %d ticks" % (contact_tick - key_tick))
				_check(contact_tick - key_tick >= _s(0.1), "the hand takes a moment to reach the knob (%d ticks)" % (contact_tick - key_tick))
				var tip := frame.volume_touch() + Vector3(0.0, -0.005, 0.055)
				_check(d.hand_position(1).distance_to(tip) < 0.03, "the hand is on the knob (%.3f m off)" % d.hand_position(1).distance_to(tip))
			if tick == contact_tick + _s(0.5):
				_check(_vol() > vol_at_key + 0.05, "holding . turns the volume up (%.2f -> %.2f)" % [vol_at_key, _vol()])
				_knob_ok("turning up")
				_check(frame.head_unit.is_volume_shown(), "the VOLUME bar shows while turning")
				var axis := (frame.head_unit.transform.basis * Vector3.BACK).normalized()
				var want := Basis(axis, frame.head_unit.knob.rotation.z) * d._radio_hand_transform(1.0).basis
				var off := (d._hand_xf.basis.inverse() * want).get_rotation_quaternion().get_angle()
				_check(off < 0.05, "the hand rolls with the knob (%.1f deg off)" % rad_to_deg(off))
				_shot("radio_volume_turning.png")
			if is_equal_approx(_vol(), 1.0) and tick > contact_tick + _s(0.5):
				_knob_ok("full")
				_key(KEY_PERIOD, false)
				vol_at_release = _vol()
				_go(Step.RELEASE)
		Step.RELEASE:
			if waited > _s(0.1) and d.act == DriverModel.Act.GRIP:
				_check(is_equal_approx(_vol(), vol_at_release), "the volume kept moving after the key was released (%.3f -> %.3f)" % [vol_at_release, _vol()])
				var cfg := ConfigFile.new()
				_check(cfg.load(SETTINGS) == OK and is_equal_approx(float(cfg.get_value("audio", "music", -1.0)), _vol()), "the new volume is saved as the Music setting")
				contact_tick = -1
				key_tick = tick
				vol_at_key = _vol()
				_key(KEY_COMMA, true)
				_go(Step.DOWN)
		Step.DOWN:
			if contact_tick > 0 and is_equal_approx(_vol(), 0.0):
				_knob_ok("zero")
				vol_at_key = 0.0
				print("full sweep down: %.2f s" % (float(tick - contact_tick) / Engine.physics_ticks_per_second))
				_key(KEY_COMMA, false)
				_go(Step.SLIDER)
		Step.SLIDER:
			if vol_at_key >= 0.0 and d.act == DriverModel.Act.GRIP:
				AudioSettings.set_volume("Music", 0.7)
				vol_at_key = -1.0
				key_tick = tick
				key_frame = Engine.get_process_frames()
			if vol_at_key < 0.0 and Engine.get_process_frames() >= key_frame + 3:
				_knob_ok("Music slider set to 0.7")
				_check(d.act == DriverModel.Act.GRIP, "the slider doesn't send the hand (act %s)" % DriverModel.Act.keys()[d.act])
				return _end("")
	return false

## A touch-only screen (no knob): the finger takes the volume on the bar, at
## the current level.
func _touch_only_unit() -> void:
	var hu := HeadUnit.new("test")
	_check(not hu.has_knob, "the test car's screen is touch only")
	hu.volume = 0.0
	var lo := hu.volume_point()
	hu.volume = 1.0
	var hi := hu.volume_point()
	_check(hi.x - lo.x > HeadUnit.SCREEN_W * 0.5, "the volume bar runs across the screen (%.3f m)" % (hi.x - lo.x))
	_check(absf(lo.y - hi.y) < 0.0001 and lo.y > 0.0, "the volume bar sits in the header (y %.3f)" % lo.y)
	hu.free()

func _shot(file: String) -> void:
	if shot_dir == "":
		return
	var img := root.get_viewport().get_texture().get_image()
	var path := shot_dir.path_join(file)
	img.save_png(path)
	print("screenshot %dx%d: %s" % [img.get_width(), img.get_height(), path])

## Seconds to physics ticks (the game may run at 60 or 120 Hz).
func _s(secs: float) -> int:
	return int(round(secs * Engine.physics_ticks_per_second))

func _go(next: Step) -> void:
	step = next
	step_start = tick

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _end(msg: String) -> bool:
	if msg != "":
		failures.append(msg)
	if held != KEY_NONE:
		_key(held, false)
	for f in failures:
		printerr("FAIL: ", f)
	print("radio_volume_knob: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
