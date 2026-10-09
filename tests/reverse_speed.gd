extends SceneTree

# Reversing still reads a speed (Roy, 2026-10-09: "the game fails to count km/h
# while going in reverse"). Hud.kmh() used to clamp negative speed to 0, so the
# HUD speedo and the steering-wheel LCD showed 0 backwards. Headless, silent:
# - Hud.kmh is the magnitude of speed, either direction
# - the car rolled backwards: current_speed() stays signed (< 0) for the logic that
#   needs it, while the HUD label, the wheel LCD and the speedo needle all read > 0
# - the tuner panel's NOW line shows a positive km/h
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/reverse_speed.gd

const TIMEOUT_TICKS := 60 * 30
const WARM_TICKS := 40
const SETTLE_TICKS := 20
const REVERSE_MS := [2.0, 6.0, 12.0]  # walking pace, a three-point turn, a quick reverse

var tick := 0
var phase := 0
var phase_start := 0
var failures: Array[String] = []

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	ExhaustTune.save_path = "user://autotune/test_reverse_speed_exhaust.json"
	change_scene_to_file("res://Game.tscn")

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("player") == null or game.get("camera") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	if tick < WARM_TICKS:
		return false
	var p: PlayerCar = game.player
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = 0.0
		c.brake_input = 0.0
		c.steering_input = 0.0
	var hud: Hud = _find(game, Hud)
	var frame: CockpitFrame = game.camera.frame
	if hud == null or frame == null:
		return _end("Game has no Hud or cockpit frame")

	if phase == 0:
		_check(Hud.kmh(-27.78) == 100 and Hud.kmh(27.78) == 100, "kmh() should be the magnitude: -27.78 m/s -> %d, +27.78 -> %d" % [Hud.kmh(-27.78), Hud.kmh(27.78)])
		_check(Hud.kmh(0.0) == 0, "standing still should read 0")
		phase = 1
		phase_start = tick
		return false

	# Roll the car backwards at a set speed (forward = -Z, so back is +Z in the car's frame).
	var want: float = REVERSE_MS[phase - 1]
	p.linear_velocity = p.global_transform.basis.z * want
	if tick - phase_start < SETTLE_TICKS:
		return false

	var v := p.current_speed()
	_check(v < -0.5, "the car should be rolling backwards, current_speed() is %.2f" % v)
	var expect := Hud.kmh(v)
	_check(expect > 0, "kmh() of a reversing car (%.2f m/s) should be > 0, got %d" % [v, expect])
	hud._refresh()
	_check(int(hud.lbl_speed.text) == expect and expect > 0, "HUD speed label '%s' should read %d km/h backwards (%.2f m/s)" % [hud.lbl_speed.text, expect, v])
	frame._process(0.016)
	var lcd: Label3D = frame.wheel.lcd
	if lcd != null:
		_check(lcd.text.contains("%d km/h" % expect), "wheel LCD '%s' should show %d km/h backwards" % [lcd.text.replace("\n", " | "), expect])
	else:
		_check(false, "the wheel should have an LCD")
	_check(frame.speedo_needle.rotation.z < deg_to_rad(135.0) - 0.001, "the speedo needle should have left its rest position backwards")

	phase += 1
	phase_start = tick
	if phase > REVERSE_MS.size():
		return _end("")
	return false

func _find(n: Node, type: Variant) -> Node:
	for c in n.get_children():
		if is_instance_of(c, type):
			return c
	return null

func _end(reason: String) -> bool:
	if reason != "":
		failures.append(reason)
	for m in failures:
		printerr("FAIL: ", m)
	print("reverse_speed: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
	return true

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
