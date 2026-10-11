extends SceneTree

# New game start (test build, 2026-10-10), headless, no scene. Every start is a
# full tank: the player's tank is built the way a new game builds it (no test
# switch), for two player cars. The night start after a tow and the testing
# ground use the same FuelTank start. Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --audio-driver Dummy --path . -s res://tests/car/fuel_start.gd

var failures: Array[String] = []

func _initialize() -> void:
	_check(FuelTank.START_FULL_TANK, "this build starts every tank full (START_FULL_TANK)")
	_check(is_equal_approx(FuelTank.START_FRACTION, 1.0), "the start fraction is full")
	for i in 2:
		var car := PlayerCar.new()
		_check(car.fuel.enabled, "car %d: the tank is on" % i)
		_check(is_equal_approx(car.fuel.litres, FuelTank.CAPACITY_L), "car %d starts full (%.1f L)" % [i, car.fuel.litres])
		_check(is_equal_approx(car.fuel.fraction(), 1.0), "car %d reads 100%% on the gauge" % i)
		car.free()
	var bare := FuelTank.new()
	_check(is_equal_approx(bare.litres, FuelTank.CAPACITY_L), "a bare FuelTank starts full too")
	bare = null
	for f in failures:
		printerr("FAIL: " + f)
	print("fuel_start: %s" % ("ok" if failures.is_empty() else "%d failure(s)" % failures.size()))
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
