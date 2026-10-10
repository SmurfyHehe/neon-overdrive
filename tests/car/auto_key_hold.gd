extends SceneTree

# Realistic automatic, driven the way the game is: on a keyboard, where the
# throttle is a key that is down or up. A driver holds a speed by tapping it.
# Followed tap by tap, the box's demand swung between lifted and floored and
# the map hunted 5-4-3-4-5 every five seconds at a steady 90 km/h (Roy,
# 2026-10-10: "pretty sure the automatic was messed up"; tools/auto_box_trace.gd
# shows it). auto_shift_brain's own hold uses a smooth pedal and never saw it.
# On a bare pad at the game's 120 Hz, per car:
#   - the key holds a speed: from 3 s after the car first gets there, for
#     15 s, the box never goes back to a gear it left (it may still work its
#     way up, twice at most)
#   - floored from rest it still runs first gear out (the 1-2 shift comes
#     above 80% of max rpm): the steadier demand did not make it short-shift
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/car/auto_key_hold.gd

const H := preload("res://tests/car/auto_box_harness.gd")
const AUTO := PlayerCar.Transmission.AUTO
## [kind, km/h to hold]: the cars and speeds that hunted worst, one per family
const CASES := [
	["p2_hothatch", 90.0],
	["p4_kei", 90.0],
	["p3_tuner", 130.0],
	["p17_work_pickup", 40.0],
	["p0_beater", 60.0],
	["p5_muscle", 90.0],
]
const KEY_HZ := 30.0       # how often the "finger" decides: down under the speed, up over it
const SETTLE_S := 3.0      # after the car first reaches the speed
const HOLD_S := 15.0
const REACH_S := 40.0

var fails: Array[String] = []
var dt := 1.0 / 120.0

func _initialize() -> void:
	Engine.physics_ticks_per_second = 120  # the game's rate, whatever NEON_TICKS says
	_run()

func _run() -> void:
	dt = 1.0 / Engine.physics_ticks_per_second
	H.ground(root)
	await physics_frame
	for c in CASES:
		await _hold(c[0], c[1])
	await _launch("p1_coupe")
	await _launch("p4_kei")
	for f in fails:
		printerr("FAIL: ", f)
	print("auto_key_hold: ", "PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	quit(0 if fails.is_empty() else 1)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)

func _hold(kind: String, kmh: float) -> void:
	var p := H.Pedals.new()
	var c: PlayerCar = H.car(root, kind, AUTO, p)
	await H.settle(self, p)
	var gear := c.current_gear
	var seen: Array[int] = []
	var went_back := false
	var every := maxi(roundi(1.0 / (KEY_HZ * dt)), 1)
	var since := -1.0   # s since the car first reached the speed
	var i := 0
	while since < SETTLE_S + HOLD_S and i < int((REACH_S + SETTLE_S + HOLD_S) / dt):
		if i % every == 0:
			p.throttle = 1.0 if H.kmh(c) < kmh else 0.0
		await physics_frame
		i += 1
		if since >= 0.0:
			since += dt
		elif H.kmh(c) >= kmh:
			since = 0.0
		if since >= SETTLE_S and seen.is_empty():
			seen = [c.current_gear]
			gear = c.current_gear
		if c.current_gear != gear:
			gear = c.current_gear
			if not seen.is_empty():
				if gear in seen:
					went_back = true
				seen.append(gear)
	print("%s: %.0f km/h held on the key, gears after settling %s, ends at %.0f km/h" % [kind, kmh, str(seen), H.kmh(c)])
	_check(absf(H.kmh(c) - kmh) < 5.0, "%s: the key did not hold %.0f km/h (%.0f)" % [kind, kmh, H.kmh(c)])
	_check(not seen.is_empty(), "%s: never reached %.0f km/h" % [kind, kmh])
	_check(seen.size() <= 3, "%s: %d gear changes while holding %.0f km/h on the key: %s" % [kind, seen.size() - 1, kmh, str(seen)])
	_check(not went_back, "%s: hunted while holding %.0f km/h on the key: %s" % [kind, kmh, str(seen)])
	await H.remove(self, c)

func _launch(kind: String) -> void:
	var p := H.Pedals.new()
	var c: PlayerCar = H.car(root, kind, AUTO, p)
	await H.settle(self, p)
	p.throttle = 1.0
	var t := 0.0
	var rpm := 0.0
	while c.current_gear == 1 and t < 20.0:
		rpm = H.gearbox_rpm(c)
		await physics_frame
		t += dt
	print("%s: floored from rest, 1-2 after %.1f s at %.0f rpm (max %.0f)" % [kind, t, rpm, c.max_rpm])
	_check(c.current_gear == 2, "%s: no 1-2 shift within 20 s of a floored start" % kind)
	_check(rpm > 0.8 * c.max_rpm, "%s: floored, it left first at %.0f rpm, under 80%% of %.0f" % [kind, rpm, c.max_rpm])
	await H.remove(self, c)
