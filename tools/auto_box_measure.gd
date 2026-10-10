extends SceneTree

# 0-100 and 0-160 km/h for every player car, AUTO against SEMI (realistic
# automatic, step A6). SEMI shifts at 97% of max rpm like TuneTrack's driver;
# AUTO is left to the car. Flat pad, full throttle from a standstill, at the
# game's 120 Hz. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tools/auto_box_measure.gd

const H := preload("res://tests/car/auto_box_harness.gd")
const LIMIT_S := 60.0

func _initialize() -> void:
	_run()

func _run() -> void:
	H.ground(root)
	await physics_frame
	print("car | family | AUTO 0-100 | SEMI 0-100 | AUTO 0-160 | SEMI 0-160 | AUTO shifts")
	for k in PlayerCars.KINDS:
		var a: Dictionary = await _one(k.id, PlayerCar.Transmission.AUTO)
		var s: Dictionary = await _one(k.id, PlayerCar.Transmission.SEMI)
		print("%s | %s | %s | %s | %s | %s | %d" % [k.id, a.family, _t(a.t100), _t(s.t100), _t(a.t160), _t(s.t160), a.shifts])
	quit(0)

func _t(x: float) -> String:
	return "%.2f s" % x if is_finite(x) else "never"

func _one(kind: String, mode: int) -> Dictionary:
	var pedals := H.Pedals.new()
	var c: PlayerCar = H.car(root, kind, mode, pedals)
	var dt := 1.0 / Engine.physics_ticks_per_second
	pedals.brake = 1.0
	for i in int(1.0 / dt):
		await physics_frame
	pedals.brake = 0.0
	pedals.throttle = 1.0
	var out := {"t100": INF, "t160": INF, "shifts": 0, "family": str(c.spec.get("auto", {}).get("family", "-"))}
	var t := 0.0
	var gear := c.current_gear
	while t < LIMIT_S and not is_finite(out.t160):
		await physics_frame
		t += dt
		if mode == PlayerCar.Transmission.SEMI and c.current_gear >= 1 and c.current_gear < c.gear_ratios.size() \
				and not c.is_shifting and c.motor_rpm >= c.max_rpm * 0.97:
			c.manual_shift(1)
		if c.current_gear != gear:
			gear = c.current_gear
			out.shifts += 1
		var v: float = H.kmh(c)
		if v >= 100.0 and not is_finite(out.t100):
			out.t100 = t
		if v >= 160.0:
			out.t160 = t
	c.queue_free()
	await physics_frame
	return out
