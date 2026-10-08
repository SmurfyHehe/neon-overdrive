extends SceneTree

# Driving-feel extras (2026-10-08): slipstream (D1), shift kick (D2), the
# headlight key. Headless and silent; asserts on levels, counters and the
# camera's spring state.
#
# - slipstream: 6 m behind a stand-in car at 25 m/s the level rises past 0.5,
#   the wind gets the same number, the lines show and a line alongside the
#   body clears it; pulling out 5 m to the side fades it under 0.1 within
#   1.5 s; at 10 m/s, or with the switch off, nothing
# - shift kick: a flat-out manual upshift near the redline nods the camera
#   (peak 0.5-1.3, settles); the automatic is half as strong; a real drive
#   on the automatic from rest upshifts and nods
# - headlights: H turns the beam off, H again turns it back on
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/driving_feel_extras.gd

const TIMEOUT := 90.0

class Leader extends Node3D:
	var half_l := 2.2
	var half_w := 0.95

var fails := 0
var game: Node
var t := 0.0
var step := "boot"
var step_t := 0.0
var p: PlayerCar
var fx: FxPack
var cam: ChaseCamera
var car_audio: CarAudio
var leader: Leader
var quit_in := 0
var samples := {}
var fwd := Vector3.ZERO
var right := Vector3.ZERO
var speed := 25.0
var side := 0.0
var key_frames := 0

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	AudioSettings.path = "user://driving_feel_extras_test.cfg"   # defaults, never the real file
	DirAccess.remove_absolute(ProjectSettings.globalize_path(AudioSettings.path))
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL ", msg)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fail(msg)

func _go(s: String) -> void:
	step = s
	step_t = 0.0

func _hold(c: PlayerCar) -> void:
	c.throttle_input = 0.0
	c.brake_input = 0.0
	c.handbrake_input = 0.0
	c.steering_input = 0.0

func _floor_it(c: PlayerCar) -> void:
	_hold(c)
	c.throttle_input = 1.0

## Holds the player at `speed` down the road and the leader 6 m ahead of it,
## `side` metres to the side, at the same speed.
func _convoy() -> void:
	p.linear_velocity = fwd * speed
	leader.global_position = p.global_position + fwd * 6.0 + right * side + Vector3.UP * 0.0
	leader.look_at(leader.global_position + fwd, Vector3.UP)

func _process(delta: float) -> bool:
	if quit_in > 0:
		quit_in -= 1
		if quit_in == 0:
			quit(0 if fails == 0 else 1)
		return false
	if game == null:
		return false
	t += delta
	step_t += delta
	if t > TIMEOUT:
		_fail("timed out in step %s" % step)
		_finish()
		return false
	match step:
		"boot":
			p = game.get("player")
			if p == null or step_t < 1.0:
				return false
			p.driver = _hold
			fx = game.get("fx")
			cam = game.get("camera")
			for c in p.get_children():
				if c is CarAudio: car_audio = c
			_check(fx != null and fx.slipstream != null and car_audio != null, "Slipstream not built")
			if fails > 0:
				_finish()
				return false
			fwd = -p.global_transform.basis.z
			fwd.y = 0.0
			fwd = fwd.normalized()
			right = fwd.cross(Vector3.UP)
			leader = Leader.new()
			game.add_child(leader)
			leader.add_to_group("aero_vehicles")
			# a line that starts inside the body width is pushed out alongside it
			var x := Slipstream._path(0.3, 0.8, 0.0, leader.half_l, leader.half_w).x
			_check(x > leader.half_w, "a line alongside the car should clear the body (%.2f)" % x)
			var behind := Slipstream._path(1.2, 0.8, leader.half_l + 8.0, leader.half_l, leader.half_w).x
			_check(behind < 1.2, "lines should close in behind the car (%.2f)" % behind)
			speed = 25.0
			side = 0.0
			samples.peak = 0.0
			_go("draft")
		"draft":
			_convoy()
			samples.peak = maxf(samples.peak, fx.slipstream.level)
			if step_t > 1.5:
				print("6 m behind at 25 m/s: slipstream %.2f, wind gets %.2f, lines shown %s (%d)" % [
					fx.slipstream.level, car_audio.slipstream, fx.slipstream.visible, fx.slipstream.multimesh.visible_instance_count])
				_check(fx.slipstream.level > 0.5, "close behind at speed should be a strong slipstream (%.2f)" % fx.slipstream.level)
				_check(absf(car_audio.slipstream - fx.slipstream.level) < 0.01, "the wind should get the slipstream level")
				_check(fx.slipstream.visible and fx.slipstream.multimesh.visible_instance_count == Slipstream.LINES, "the air lines should show")
				side = 5.0
				_go("pull_out")
		"pull_out":
			_convoy()
			if step_t > 1.5:
				print("pulled out 5 m: slipstream %.3f" % fx.slipstream.level)
				_check(fx.slipstream.level < 0.1, "pulling out should fade the slipstream (%.2f)" % fx.slipstream.level)
				side = 0.0
				speed = 10.0
				_go("slow")
		"slow":
			_convoy()
			if step_t > 1.5:
				print("6 m behind at 10 m/s: slipstream %.3f" % fx.slipstream.level)
				_check(fx.slipstream.level < 0.05, "no slipstream to feel at 10 m/s (%.2f)" % fx.slipstream.level)
				speed = 25.0
				FxSettings.set_on("slipstream", false)
				fx.apply_settings()
				_go("off")
		"off":
			_convoy()
			if step_t > 1.5:
				print("switched off: slipstream %.3f, wind %.3f" % [fx.slipstream.level, car_audio.slipstream])
				_check(fx.slipstream.level < 0.05 and car_audio.slipstream == 0.0, "slipstream off should show and sound nothing")
				FxSettings.set_on("slipstream", true)
				fx.apply_settings()
				leader.queue_free()
				leader = null
				_go("shift")
		"shift":
			_hold(p)
			if step_t > 1.0:
				_check_shift_kick()
				samples.shifts = cam.shift_count
				p.automatic_transmission = true
				p.driver = _floor_it
				_go("auto_drive")
		"auto_drive":
			if step_t > 8.0:
				var n: int = cam.shift_count - samples.shifts
				print("automatic from rest, 8 s flat out: gear %d, %d upshift nod(s), last %.2f" % [p.current_gear, n, cam.last_shift_strength])
				_check(n >= 1, "a real drive should upshift and nod")
				_check(cam.last_shift_strength <= ChaseCamera.SHIFT_AUTO + 0.001, "automatic nods should be the soft ones (%.2f)" % cam.last_shift_strength)
				_check(cam.last_shift_strength > 0.25, "a flat-out automatic upshift should still nod clearly (%.2f)" % cam.last_shift_strength)
				p.driver = Callable()   # the keyboard, for the headlight key
				_go("lights_off")
		"lights_off":
			_press("headlights")
			if step_t > 0.3:
				var spot := p.get_node_or_null("Headlights") as Light3D
				_check(spot != null and not spot.visible and not p.headlights_on, "H should turn the headlights off")
				_go("lights_on")
		"lights_on":
			_press("headlights")
			if step_t > 0.3:
				var spot := p.get_node_or_null("Headlights") as Light3D
				print("headlight key: off then on, beam now %s" % ("on" if spot != null and spot.visible else "off"))
				_check(spot != null and spot.visible and p.headlights_on, "H again should turn them back on")
				_finish()
	return false

## Presses an action once per step: down for a few frames, then up.
func _press(action: String) -> void:
	if not samples.get("pressed_" + step, false):
		samples["pressed_" + step] = true
		Input.action_press(action)
		key_frames = 0
	elif Input.is_action_pressed(action):
		key_frames += 1
		if key_frames > 2:
			Input.action_release(action)

func _check_shift_kick() -> void:
	p.automatic_transmission = false
	p.throttle_input = 1.0
	p.motor_rpm = p.max_rpm * 0.95
	cam._rpm_peak = 0.0
	p.current_gear = 2
	cam._watch_shift()
	p.current_gear = 3
	cam._watch_shift()
	var hard := cam.last_shift_strength
	var peak := 0.0
	for i in 60:
		cam._kick(1.0 / 60.0, 1.0)
		peak = maxf(peak, cam.shift_x)
	var after := cam.shift_x
	for i in 60:
		cam._kick(1.0 / 60.0, 1.0)
	p.automatic_transmission = true
	p.current_gear = 4
	cam._watch_shift()
	var soft := cam.last_shift_strength
	for i in 120:
		cam._kick(1.0 / 60.0, 1.0)
	p.throttle_input = 0.2
	p.motor_rpm = p.max_rpm * 0.4
	cam._rpm_peak = 0.0
	p.automatic_transmission = false
	p.current_gear = 5
	cam._watch_shift()
	var lazy := cam.last_shift_strength
	for i in 120:
		cam._kick(1.0 / 60.0, 1.0)
	print("shift kick: flat-out manual %.2f (camera peak %.2f, after 1 s %.3f), automatic %.2f, lazy manual %.2f" % [hard, peak, after, soft, lazy])
	_check(hard > 0.85, "a flat-out shift near the redline should kick hard (%.2f)" % hard)
	_check(peak > 0.5 and peak < 1.3, "camera nod peak %.2f, expected 0.5-1.3" % peak)
	_check(absf(after) < 0.05, "the nod should settle within a second (%.3f)" % after)
	_check(absf(soft - hard * ChaseCamera.SHIFT_AUTO) < 0.01, "the automatic should be half as strong (%.2f vs %.2f)" % [soft, hard])
	_check(lazy < hard * 0.5 and lazy >= ChaseCamera.SHIFT_MIN, "a lazy shift should nod softly (%.2f)" % lazy)
	p.current_gear = 1
	cam._watch_shift()

func _finish() -> void:
	if quit_in > 0 or game == null:
		return
	for a in ["headlights"]:
		Input.action_release(a)
	print("driving_feel_extras: %s" % ("PASS" if fails == 0 else "%d failure(s)" % fails))
	game.queue_free()
	game = null
	quit_in = 30
