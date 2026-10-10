extends SceneTree

# Realistic automatic, step A1: in AUTO the shift keys do nothing. The real
# game, real input actions (shift_up / shift_down pressed and released), in
# the cockpit view, at a standstill, at 40 and at 100 km/h:
#   - GEVP's manual shift never starts (is_shifting stays false)
#   - every gear change is one the box made itself (its own shift count)
#   - no paddle flick on the wheel or in the driver's hand (the coupe has no
#     paddles), no upshift bang from the engine
#   - the pause menu says so: "Shift up / down (semi and manual only)"
# Then, as a control, the same key in SEMI does shift, so the presses above
# really reached the car.
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/car/auto_ignores_shift_keys.gd

const TIMEOUT_S := 90.0
const SPEEDS := [0.0, 40.0, 100.0]
const TAPS := 8

var fails: Array[String] = []

func _initialize() -> void:
	Engine.physics_ticks_per_second = 120  # the game's rate, whatever NEON_TICKS says
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	change_scene_to_file("res://Game.tscn")
	_run()

func _check(ok: bool, msg: String) -> void:
	if not ok and not (msg in fails):
		fails.append(msg)

func _tap(action: String) -> void:
	Input.action_press(action)
	await physics_frame
	await physics_frame
	Input.action_release(action)
	await physics_frame

func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while current_scene == null or current_scene.get("player") == null or current_scene.get("camera") == null:
		await physics_frame
		if Time.get_ticks_msec() - t0 > 30000:
			_check(false, "Game never became ready")
			return _end()
	var p: PlayerCar = current_scene.player
	var cam: ChaseCamera = current_scene.camera
	cam.set_view(ChaseCamera.View.COCKPIT)
	p.set_transmission_mode(PlayerCar.Transmission.AUTO)
	for i in 60:
		await physics_frame
	var frame: CockpitFrame = cam.frame
	var synth: EngineSynth = null
	for c in p.get_children():
		if c is EngineAudio:
			synth = c.synth
	_check(p.auto_box != null, "the player's car has no AutoBox")
	_check(synth != null, "no engine synth found")
	_check(not p.has_paddles(), "the coupe should have no paddles")
	if not fails.is_empty():
		return _end()

	var labels := {}
	for group in PauseMenu.GROUPS:
		for row in group[1]:
			labels[row[0]] = row[1]
	_check(labels.get("shift_up") == "Shift up (semi and manual only)", "pause menu shift_up label is '%s'" % labels.get("shift_up"))
	_check(labels.get("shift_down") == "Shift down (semi and manual only)", "pause menu shift_down label is '%s'" % labels.get("shift_down"))

	var dt := 1.0 / Engine.physics_ticks_per_second
	for want in SPEEDS:
		if want <= 0.0:
			Input.action_press("brake")
		else:
			Input.action_release("brake")
			Input.action_press("accelerate")
			var t := 0.0
			while p.current_speed() * 3.6 < want and t < TIMEOUT_S:
				await physics_frame
				t += dt
			_check(p.current_speed() * 3.6 >= want, "never reached %d km/h" % want)
		var gear := p.gear
		var own: int = p.auto_box.shift_count
		var bangs := synth.upshift_clusters
		var changes := 0
		var manual_shift_seen := false
		var flicked := false
		for i in TAPS:
			var action := "shift_up" if i % 2 == 0 else "shift_down"
			Input.action_press(action)
			for k in 12:   # 0.1 s held, 0.1 s released
				if k == 6:
					Input.action_release(action)
				await physics_frame
				manual_shift_seen = manual_shift_seen or p.is_shifting
				if p.gear != gear:
					changes += 1
					gear = p.gear
				flicked = flicked or frame.wheel._paddle_t[-1] > 0.0 or frame.wheel._paddle_t[1] > 0.0 or frame.driver.paddle_t > 0.0
		var own_shifts: int = p.auto_box.shift_count - own
		print("AUTO at %d km/h: %d presses, %d gear changes, %d by the box, manual shift started: %s, paddle flick: %s, upshift bangs: %d" % [
			want, TAPS, changes, own_shifts, manual_shift_seen, flicked, synth.upshift_clusters - bangs])
		_check(not manual_shift_seen, "at %d km/h a shift key started a manual shift in AUTO" % want)
		_check(changes == own_shifts, "at %d km/h the gear changed %d times but the box shifted %d times" % [want, changes, own_shifts])
		if want <= 0.0:
			_check(changes == 0, "the gear changed at a standstill")
		_check(not flicked, "at %d km/h a paddle flicked in AUTO" % want)
		_check(synth.upshift_clusters == bangs, "at %d km/h the engine banged an upshift in AUTO" % want)

	# control: the same key in SEMI shifts
	Input.action_release("accelerate")
	p.set_transmission_mode(PlayerCar.Transmission.SEMI)
	for i in 30:
		await physics_frame
	var before := p.gear
	Input.action_press("shift_down")
	var shifted := false
	for i in 12:
		await physics_frame
		shifted = shifted or p.is_shifting or p.gear != before
	Input.action_release("shift_down")
	print("SEMI control: Q %s" % ("shifted" if shifted else "did nothing"))
	_check(shifted, "control failed: Q did nothing in SEMI, so the AUTO presses prove nothing")
	_end()

func _end() -> void:
	for a in ["accelerate", "brake", "shift_up", "shift_down"]:
		Input.action_release(a)
	for f in fails:
		printerr("FAIL: ", f)
	print("auto_ignores_shift_keys: ", "PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	quit(0 if fails.is_empty() else 1)
