extends SceneTree

# HUD and gauges look (2026-10-14): the cockpit's tach and speedo carry
# numerals that read the car's own range (max_rpm, speedo_max_kmh), so a
# needle says a number. Boots EVERY player car in turn (PlayerCars.KINDS,
# like tests/view/gauge_layout.gd; one car with NEON_NUMERALS_CAR=<kind>) and
# checks, headless:
# - the tach has a numeral per 1000 rpm up to max_rpm, the speedo one per
#   speedo_step() up to speedo_max_kmh, each inside its dial's face (or on
#   the ribbon, for the muscle car's strip speedo)
# - no numeral sits on a gear window (the coupe's); its tick still does
# - the numeral at a value is where the needle points at that value
# - speedo_step() lands on every player car's top speed in 5..8 steps or
#   falls back to 20
# - on the first car: the HUD's fuel and boost gauges are drawn (no text)
#   and the debug line only shows in test mode
#   <godot> --headless --audio-driver Dummy --path . -s res://tests/view/dial_numerals.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const TestMode := preload("res://scripts/core/test_mode.gd")
const RATE := 60

var failures: Array[String] = []
var game: Node
var hud_checked := false

func _initialize() -> void:
	Engine.physics_ticks_per_second = RATE
	OS.set_environment("NEON_TRAFFIC", "0")
	_run.call_deferred()

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _run() -> void:
	# --- the step rule, for every player car's dial
	var tops := []
	for k in PlayerCars.KINDS:
		var cab := CabinSpec.for_kind(String(k.id))
		if cab.has("speedo_max_kmh"):
			tops.append(float(cab.speedo_max_kmh))
	_check(tops.size() >= 10, "only %d cars have a cabin with a speedo" % tops.size())
	for top: float in tops:
		var step := CockpitFrame.speedo_step(top)
		var n: float = top / step
		_check(fmod(top, step) < 0.5, "%.0f km/h: step %.0f does not land on the top" % [top, step])
		_check(n <= 14.0, "%.0f km/h: %.0f steps of %.0f is too many numerals" % [top, n, step])
	_check(CockpitFrame.speedo_step(300.0) == 50.0 and CockpitFrame.speedo_step(240.0) == 40.0 and CockpitFrame.speedo_step(260.0) == 20.0, "300 -> 50, 240 -> 40, 260 -> 20")
	_check(CockpitFrame.tach_marks(7000.0).size() == 8 and CockpitFrame.tach_marks(7200.0).size() == 8, "a 7000 or 7200 rpm tach reads 0..7")

	var only := OS.get_environment("NEON_NUMERALS_CAR")
	var cars := 0
	for k in PlayerCars.KINDS:
		if only != "" and String(k.id) != only:
			continue
		await _car(String(k.id))
		cars += 1
	OS.set_environment("NEON_CAR", "")
	for m in failures:
		printerr("FAIL: ", m)
	print("dial_numerals: %d cars, %s" % [cars, "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size()])
	quit(0 if failures.is_empty() else 1)

func _car(kind: String) -> void:
	OS.set_environment("NEON_CAR", kind)
	game = Harness.boot(self, 0, 150.0, 7, 1.0e6)
	for i in RATE:
		await physics_frame
	var p: PlayerCar = game.get("player")
	var cam: ChaseCamera = game.get("camera")
	if p == null or cam == null or cam.frame == null:
		failures.append("%s: the game should boot with a cockpit frame" % kind)
		game.queue_free()
		await process_frame
		return
	var frame: CockpitFrame = cam.frame
	_numerals(kind, p, frame)
	if not hud_checked:
		hud_checked = true
		_hud(p)
	game.queue_free()
	await process_frame

func _numerals(kind: String, p: PlayerCar, frame: CockpitFrame) -> void:
	# --- the numerals on this car
	var faces := frame.dial_faces()
	var centres := frame.dial_centres()
	var sweep: float = frame.dial_sweep
	var a_start := 225.0 if sweep > 180.0 else 90.0 + sweep * 0.5
	var counts := [0, 0]
	var want := [CockpitFrame.tach_marks(p.max_rpm).size(), CockpitFrame.speedo_marks(float(frame.cab.speedo_max_kmh)).size()]
	var win := Rect2(CockpitFrame.GEAR_WIN_AT - CockpitFrame.GEAR_WIN_SIZE * 0.5, CockpitFrame.GEAR_WIN_SIZE)
	var has_window: bool = frame.cab.get("gear_window", false)
	for l in frame.get_children():
		if not (l is Label3D) or not l.name.begins_with("Numeral"):
			continue
		var i := int(l.name.substr(7, 1))
		counts[i] += 1
		var c: Vector3 = centres[i]
		var r: float = faces[i]["r"] if i == 1 and frame.cab.cluster_style == "strip" else faces[i]["r"]
		var local: Vector3 = l.position - c
		var dist := Vector2(local.x, local.y).length()
		if frame.cab.cluster_style == "strip" and i == 1:
			var ring: float = frame.dial_radii()[1]
			_check(dist > ring * CockpitFrame.STRIP_INNER and dist < ring, "%s is off the ribbon (%.3f m from the pivot)" % [(kind + " " + l.name), dist])
		else:
			_check(dist < r - 0.004 and dist > 0.008, "%s is not on its face (%.3f m from the centre, r %.3f)" % [(kind + " " + l.name), dist, r])
		# the needle at that value points at the numeral
		var v := float(l.text) * (1000.0 if i == 0 else 1.0)
		var top: float = p.max_rpm if i == 0 else float(frame.cab.speedo_max_kmh)
		var a := deg_to_rad(a_start - sweep * v / top)
		var ang := atan2(local.y, local.x)
		_check(absf(angle_difference(a, ang)) < 0.02, "%s sits at %.1f deg, the needle reads it at %.1f" % [(kind + " " + l.name), rad_to_deg(ang), rad_to_deg(a)])
		if i == 0 and has_window:
			_check(not win.has_point(Vector2(local.x, local.y)), "%s sits on the gear window" % (kind + " " + l.name))
	_check(counts[0] >= want[0] - 1 and counts[0] <= want[0], "%s: the tach should carry %d numerals (one may give way to the gear window), has %d" % [kind, want[0], counts[0]])
	_check(counts[1] == want[1], "%s: the speedo should carry %d numerals, has %d" % [kind, want[1], counts[1]])
	if has_window:
		_check(counts[0] == want[0] - 1, "the coupe's 2 should give way to the gear window")


func _hud(p: PlayerCar) -> void:
	var hud: Hud = null
	for c in game.get_children():
		if c is Hud:
			hud = c
	_check(hud != null, "the game has no Hud")
	if hud == null:
		return
	hud._refresh()
	_check(hud.aux.fuel_bars == (Hud.fuel_bars(p.fuel) if p.fuel.enabled else -1), "the fuel gauge should show %d blocks" % Hud.fuel_bars(p.fuel))
	_check(hud.aux.boost_q == -1 or p.turbo_boost_max > 0.0, "a boost bar on a car with no boost setup")
	_check(hud.lbl_info.visible == TestMode.active(), "the camera/traffic line shows only in test mode")
	var words := 0
	for l in hud.cluster.find_children("*", "Label", true, false):
		var t: String = (l as Label).text
		if t.to_upper().contains("FUEL") or t.to_upper().contains("BOOST") or t.contains("rpm"):
			words += 1
	_check(words == 0, "the HUD still spells FUEL, BOOST or rpm (%d labels)" % words)
	_check(Hud.fuel_bars(p.fuel) == clampi(ceili(p.fuel.fraction() * 8.0 - 0.001), 0, 8), "fuel blocks round up")
