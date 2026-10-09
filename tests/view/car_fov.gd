extends SceneTree

# Per-car FOV (2026-10-09, Roy: the crossover's view is off, "FOV should be
# adjusted per car"). Every player car boots in turn (NEON_CAR) and:
# - its spec carries finite cockpit_fov / chase_fov / chase_height in range;
# - at rest in the chase view the camera FOV is the car's chase_fov;
# - in the cockpit with the slider at its default the FOV is the car's
#   cockpit_fov plus the speed term; with the slider moved by +6 or -6 the
#   FOV moves by the same 6 (the slider works on top of the car's value);
# - the chase camera sits at the car's chase_height at rest.
# The glass share and dash line at the car's FOV are in view/cockpit_interior
# (run with NEON_CAR=<kind>). Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/view/car_fov.gd

const RATE := 60
var failures: Array[String] = []
var game: Node

func _initialize() -> void:
	ExhaustTune.save_path = "user://autotune/test_car_fov_exhaust.json"
	_run()

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
		print("FAIL: ", msg)

func _run() -> void:
	for k in PlayerCars.KINDS:
		await _one(String(k.id))
	OS.set_environment("NEON_CAR", "")
	ViewSettings.set_cockpit_fov(ViewSettings.COCKPIT_FOV_DEFAULT)
	print("car_fov: %s" % ("PASS" if failures.is_empty() else "FAIL (%d)" % failures.size()))
	quit(0 if failures.is_empty() else 1)

func _one(kind: String) -> void:
	OS.set_environment("NEON_CAR", kind)
	if game != null:
		game.queue_free()
		await process_frame
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for i in RATE * 2:
		await physics_frame
	var p: PlayerCar = game.get("player")
	var cam: ChaseCamera = game.get("camera")
	_check(p != null and cam != null, "%s: no player or camera" % kind)
	if p == null or cam == null:
		return
	var sp: Dictionary = p.spec
	for key in ["cockpit_fov", "chase_fov", "chase_height"]:
		_check(sp.has(key) and is_finite(float(sp[key])), "%s: spec has no finite %s" % [kind, key])
	var base := float(sp.get("cockpit_fov", -1.0))
	var rest := float(sp.get("chase_fov", -1.0))
	var height := float(sp.get("chase_height", -1.0))
	_check(base >= ViewSettings.COCKPIT_FOV_MIN and base <= ViewSettings.COCKPIT_FOV_MAX, "%s: cockpit_fov %.1f is outside the slider's range" % [kind, base])
	_check(rest >= 50.0 and rest <= 70.0, "%s: chase_fov %.1f is unreasonable" % [kind, rest])
	_check(height >= 1.5 and height <= 3.0, "%s: chase_height %.2f is unreasonable" % [kind, height])
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = 0.0
		c.brake_input = 1.0
		c.steering_input = 0.0
	ViewSettings.set_cockpit_fov(ViewSettings.COCKPIT_FOV_DEFAULT)
	cam.set_view(ChaseCamera.View.CHASE)
	for i in RATE * 2:
		await physics_frame
	await process_frame
	_check(absf(cam.fov - rest) < 0.6, "%s: chase FOV at rest %.2f, spec says %.1f" % [kind, cam.fov, rest])
	_check(absf(cam.height_now - height) < 0.02, "%s: chase height %.2f, spec says %.2f" % [kind, cam.height_now, height])
	cam.set_view(ChaseCamera.View.COCKPIT)
	for i in RATE:
		await physics_frame
	await process_frame
	_check(absf(cam.fov - base) < 0.6, "%s: cockpit FOV at rest %.2f, spec says %.1f (slider at default)" % [kind, cam.fov, base])
	ViewSettings.set_cockpit_fov(ViewSettings.COCKPIT_FOV_DEFAULT + 6.0)
	await process_frame
	await process_frame
	_check(absf(cam.fov - (base + 6.0)) < 0.6, "%s: slider +6 should give %.1f, got %.2f" % [kind, base + 6.0, cam.fov])
	ViewSettings.set_cockpit_fov(ViewSettings.COCKPIT_FOV_DEFAULT - 6.0)
	await process_frame
	await process_frame
	_check(absf(cam.fov - (base - 6.0)) < 0.6, "%s: slider -6 should give %.1f, got %.2f" % [kind, base - 6.0, cam.fov])
	print("car_fov: %s cockpit %.0f chase %.0f height %.2f" % [kind, base, rest, height])
