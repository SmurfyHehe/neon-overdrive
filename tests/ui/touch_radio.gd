extends SceneTree

# Touch-screen radio (UI direction blend section 4, Roy 2026-10-07), in the real
# Game.tscn with the real renderer:
# - the head unit is built: a screen (SubViewport texture) under the dash top,
#   four tiles, and on the P1 an aftermarket unit with a physical knob
# - pressing N (the radio_next action) does NOT change the station on the key:
#   the driver's right hand reaches the screen and the station changes on the
#   finger's contact with the glass (hand_contact), with the tap tick, and
#   the hand is on the glass when it happens
# - the contact comes at the start of a swipe (2026-10-11): the finger lands
#   right of the glass centre and drags left while pressed; two quick N: the
#   hand stays over the glass between the swipes
# - N during a manual shift waits: no change while the hand is on the gear
#   knob, the tap comes after the shift
# - V (radio_power): the hand presses the knob, the radio turns off, screen dimmed;
#   V again turns it back on at the same station
# - chase view: the HUD radio card (RadioManager toast) changes on the tap too
# - optional: TOUCH_RADIO_SHOT=<dir> saves cockpit screenshots there
# Exit code 1 on failure. Run (a window opens):
#   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1280x720 -s res://tests/ui/touch_radio.gd

const TIMEOUT_TICKS := 60 * 60
const STEP_TIMEOUT := 60 * 6

enum Step { BOOT, SETTLE, KEY, SHIFT, CYCLE, OFF, CHASE, SHOT, DONE }
const DEFAULT_CARD := RadioStations.DEFAULT_STATION
var key_code := KEY_N

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var game: Node
var p: PlayerCar
var frame: CockpitFrame
var d: DriverModel
var radio: RadioManager
var throttle := 0.0
var key_tick := -1
var key_station := -2
var contacts: Array = []         # [tick, target, station after, toast, taps, hand-to-touch distance]
var touch_pos := Vector3.ZERO
var shift_seen := false
var changed_during_shift := false
var cycle_left := 0
var second_at := -1              # tick of the second press of the queued pair
var left_glass := false          # the hand went back to the rim between queued swipes
var reach_seen := false          # the hand set off for the screen after the key
var swipe_seen := false          # the hand swiped after the first contact
var swipe_min_x := 1e9           # how far left the finger got, car space
var swipe_z_off := 0.0           # how far it lifted off the glass mid-swipe
var shot_dir := ""
var shot_taken := 0

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	ExhaustTune.save_path = "user://autotune/test_touch_radio_exhaust.json"
	shot_dir = OS.get_environment("TOUCH_RADIO_SHOT")
	process_frame.connect(_sample_swipe)
	change_scene_to_file("res://Game.tscn")

func _drive(c: PlayerCar) -> void:
	c.throttle_input = throttle
	c.brake_input = 0.0
	c.handbrake_input = 0.0
	c.steering_input = 0.0

func _key(pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = key_code
	ev.physical_keycode = key_code
	ev.pressed = pressed
	Input.parse_input_event(ev)

## Presses N for two ticks (the game polls input on the physics tick).
func _press(power := false) -> void:
	key_code = KEY_V if power else KEY_N
	_key(true)
	key_tick = tick
	key_station = radio.card
	touch_pos = frame.radio_touch(DriverModel.RADIO_POWER if power else DriverModel.RADIO_NEXT).pos

func _on_contact(target: StringName) -> void:
	if target != DriverModel.CONTACT_RADIO_TILE and target != DriverModel.CONTACT_RADIO_KNOB:
		return
	# hand origin with the fingertips on the glass, at the start of the swipe for a station change
	var dx := DriverModel.SWIPE_M * 0.5 if target == DriverModel.CONTACT_RADIO_TILE else 0.0
	var touch := touch_pos + Vector3(dx, -0.005, 0.055)
	contacts.append([tick, target, radio.card, radio.toast_text, frame.head_unit.taps, d.hand_position(1).distance_to(touch), radio.station, d.act])

## The swipe is sampled on every drawn frame (the hand moves on render
## frames), including the one that ends it: that frame puts the finger at the
## far left and already hands over to the return, so a sample taken by act
## alone missed it, and on a busy machine (few, long frames) the last frame
## still marked as the swipe could be well short of the end.
var _prev_act := -1
func _sample_swipe() -> void:
	if d == null or step != Step.KEY:
		return
	var ended := _prev_act == DriverModel.Act.RADIO_SWIPE
	_prev_act = d.act
	if d.act == DriverModel.Act.RADIO_SWIPE or ended:
		swipe_seen = true
		var hp := d.hand_position(1)
		swipe_min_x = minf(swipe_min_x, hp.x)
		swipe_z_off = maxf(swipe_z_off, absf(hp.z - (touch_pos.z + 0.055)))

func _physics_process(_delta: float) -> bool:
	tick += 1
	if tick > TIMEOUT_TICKS:
		return _end("timed out in step %s" % Step.keys()[step])
	game = current_scene
	if game == null or game.get("player") == null or game.get("camera") == null or game.get("radio") == null:
		return false
	p = game.player
	p.driver = _drive
	var cam: ChaseCamera = game.camera
	frame = cam.frame
	radio = game.radio
	if frame == null:
		return _end("no cockpit frame (NEON_COCKPIT=0?)")
	d = frame.driver
	var waited := tick - step_start
	if key_tick > 0 and tick == key_tick + 2:
		_key(false)
	if waited > STEP_TIMEOUT and step != Step.SHOT:
		return _end("step %s took too long" % Step.keys()[step])
	match step:
		Step.BOOT:
			var hu := frame.head_unit
			_check(hu != null and hu.get_parent() == frame and hu.name == "Radio", "the head unit is built on the cockpit frame")
			_check(hu.screen != null and hu.screen.material_override.albedo_texture is ViewportTexture, "the screen shows a SubViewport")
			_check(hu.has_knob == (HeadUnit.style_for(PlayerCar.chassis_kind()).knob as bool), "the knob follows the car's style")
			if PlayerCar.chassis_kind() == "p1_coupe":
				_check(hu.has_knob and hu.style.aftermarket, "the P1 has an aftermarket unit with a physical knob")
			var top := frame.head_unit.position.y + HeadUnit.SCREEN_H * 0.5 + HeadUnit.BEZEL_BORDER
			_check(top < 0.91, "the head unit stays under the dash top (%.3f)" % top)
			_check(frame.head_unit.position.x > CockpitFrame.SEAT_X + 0.2, "the head unit sits right of the wheel")
			d.hand_contact.connect(_on_contact)
			cam.set_view(ChaseCamera.View.COCKPIT)
			p.automatic_transmission = false
			_check(radio.station == -1, "the radio starts off")
			_go(Step.SETTLE)
		Step.SETTLE:
			throttle = 0.4
			if waited == 60 and not d.is_busy():
				_press()
				_go(Step.KEY)
		Step.KEY:
			if contacts.is_empty():
				_check(radio.card == key_station and radio.station == -1, "the radio changed before the finger touched the screen (tick %d after the key)" % (tick - key_tick))
				if d.act == DriverModel.Act.RADIO_REACH:
					reach_seen = true
				if waited == 3:
					_check(radio.toast_left <= 0.0, "the HUD radio card waits for the tap")
				return false
			var c: Array = contacts[0]
			if d.act != DriverModel.Act.RADIO_RETURN and d.act != DriverModel.Act.GRIP:
				return false   # the swipe is still going (the hand runs on render frames, not ticks)
			_check(reach_seen, "N sends the right hand toward the screen")
			print("key to tap: %d ticks (%.2f s)" % [c[0] - key_tick, float(c[0] - key_tick) / Engine.physics_ticks_per_second])
			_check(c[0] - key_tick >= 6, "the tap should come a moment after the key, not on it (%d ticks)" % (c[0] - key_tick))
			_check(c[1] == DriverModel.CONTACT_RADIO_TILE and c[2] == DEFAULT_CARD and c[6] == DEFAULT_CARD, "the first tap lands on the glass and turns the radio on at the card (%s, card %d, station %d)" % [c[1], c[2], c[6]])
			_check(c[3] == "%s %s." % [RadioStations.STATIONS[DEFAULT_CARD].dial, RadioStations.STATIONS[DEFAULT_CARD].name], "the caption names the station on the tap (%s)" % c[3])
			_check(c[4] == 1, "one tap tick on contact (%d)" % c[4])
			_check(c[5] < 0.03, "the hand is on the glass when the radio turns on (%.3f m off)" % c[5])
			_check(c[7] == DriverModel.Act.RADIO_PRESS, "the contact comes as the finger lands, before the swipe (%s)" % DriverModel.Act.keys()[c[7]])
			_check(swipe_seen, "after the contact the finger swipes across the glass")
			_check(swipe_min_x < touch_pos.x - 0.015 and swipe_z_off < 0.006, "the finger drags left on the glass while pressed (%.3f m left of the centre, %.3f m off the glass)" % [touch_pos.x - swipe_min_x, swipe_z_off])
			if true:
				_check(not frame.head_unit.is_dimmed() and frame.head_unit.station == DEFAULT_CARD, "the screen shows the station lit")
				throttle = 1.0
				_go(Step.SHIFT)
		Step.SHIFT:
			if waited == 30:
				p.shift(1)
				_check(p.is_shifting, "a manual shift starts")
			if waited == 33:
				_check(d.act == DriverModel.Act.SHIFT_REACH or d.act == DriverModel.Act.SHIFT_HOLD, "the hand is on its way to the gear knob (%s)" % DriverModel.Act.keys()[d.act])
				_press()
			if waited > 33:
				var shifting := d.act in [DriverModel.Act.SHIFT_REACH, DriverModel.Act.SHIFT_HOLD, DriverModel.Act.SHIFT_RETURN]
				if shifting:
					shift_seen = true
					if radio.card != key_station:
						changed_during_shift = true
				if contacts.size() >= 2 and waited > 33 + 30:
					var c: Array = contacts[1]
					_check(shift_seen, "the hand was busy with the shift when N was pressed")
					_check(not changed_during_shift, "the ring must not move while the hand is shifting")
					_check(c[2] == (DEFAULT_CARD + 1) % 5 and c[1] == DriverModel.CONTACT_RADIO_TILE, "after the shift the hand taps and the ring moves one card (%s, card %d)" % [c[1], c[2]])
					print("key during shift to tap: %d ticks" % (c[0] - key_tick))
					throttle = 0.3
					cycle_left = 2
					_go(Step.CYCLE)
		Step.CYCLE:
			# two quick N: the second waits for the hand, which stays over the glass
			if cycle_left == 2 and not d.is_busy() and contacts.size() == 2 and waited > 10:
				_press()
				cycle_left = 1
				second_at = tick + 4
			elif tick == second_at:
				_press()
				cycle_left = 0
				second_at = -1
			if cycle_left == 0 and contacts.size() == 3 and d.act in [DriverModel.Act.RADIO_RETURN, DriverModel.Act.GRIP]:
				left_glass = true
			if cycle_left == 0 and contacts.size() == 4 and not d.is_busy():
				_check(radio.card == (DEFAULT_CARD + 3) % 5, "three slides land three cards on (%d)" % radio.card)
				_check(not left_glass, "between two queued presses the hand stays over the glass and swipes again")
				_check(contacts[3][5] < 0.03, "the second queued swipe starts with the finger on the glass (%.3f m off)" % contacts[3][5])
				_press(true)
				_go(Step.OFF)
		Step.OFF:
			if contacts.size() == 5 and not d.is_busy():
				var c: Array = contacts[4]
				var want := DriverModel.CONTACT_RADIO_KNOB
				_check(c[1] == want and c[6] == -1 and c[2] == (DEFAULT_CARD + 3) % 5, "V sends the hand to the knob and the radio turns off (%s, station %d, card %d)" % [c[1], c[6], c[2]])
				_check(c[5] < 0.03, "the hand is on the knob when the radio turns off (%.3f m off)" % c[5])
				if frame.head_unit.has_knob:
					_check(frame.head_unit.knob_presses == 1, "the knob was pressed once (%d)" % frame.head_unit.knob_presses)
				_check(frame.head_unit.is_dimmed(), "the screen dims with the radio off")
				_check(frame.head_unit.canvas.modulate.v < 0.5, "the screen drawing is dimmed")
				cam.set_view(ChaseCamera.View.CHASE)
				_go(Step.CHASE)
		Step.CHASE:
			if waited == 30:
				_press(true)
			if waited > 30:
				if contacts.size() == 5:
					_check(radio.station == -1 and not radio._cap_label.visible, "radio off: no caption, and V waits for the tap (%d)" % radio.station)
				elif waited > 30 + 5:
					var c: Array = contacts[5]
					var want_card := (DEFAULT_CARD + 3) % 5
					_check(c[6] == want_card and c[1] == DriverModel.CONTACT_RADIO_KNOB, "V again turns it back on at the same station (%d)" % c[6])
					_check(c[3] == "%s %s." % [RadioStations.STATIONS[want_card].dial, RadioStations.STATIONS[want_card].name], "chase view: the caption names the station (%s)" % c[3])
					_check(radio._cap_label.visible and radio._cap_label.text == c[3], "the bottom caption is up outside the cockpit (%s)" % radio._cap_label.text)
					cam.set_view(ChaseCamera.View.COCKPIT)
					_go(Step.SHOT)
		Step.SHOT:
			if shot_dir == "":
				return _end("")
			if waited == 60:
				_save("touch_radio_cockpit.png")
				_press()   # one more tap, to catch the finger on the glass
			if contacts.size() == 7 and shot_taken == 1:
				_save("touch_radio_tap.png")
			if waited == 200:
				return _end("")
	return false

func _save(file: String) -> void:
	shot_taken += 1
	var img := root.get_viewport().get_texture().get_image()
	var path := shot_dir.path_join(file)
	img.save_png(path)
	print("screenshot %dx%d: %s" % [img.get_width(), img.get_height(), path])

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
	print("touch_radio: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
